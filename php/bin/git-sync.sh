#!/usr/bin/env bash
#
# One synchronisation pass. Safe to run by hand:
#
#     docker exec <container> git-sync
#     docker exec <container> git-sync --force     # re-apply even if unchanged
#
# Exit codes: 0 nothing to do or updated, 1 failed.

set -Eeuo pipefail

LOG_TAG=git-sync
# shellcheck source=../lib/common.sh
source "${PHP_GITHUB_LIB:-/usr/local/lib/php-github}/common.sh"

load_config
setup_git_auth

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# ------------------------------------------------------------------- refs ---

# GIT_REF and the rest of the configuration arrive through load_config.
# shellcheck disable=SC2153

# Resolves GIT_REF on the remote without downloading a single object. Tried in
# order: branch, annotated tag (peeled to its commit), lightweight tag.
remote_sha() {
    local sha
    sha="$(git ls-remote --heads "${GIT_REPO}" "${GIT_REF}" 2> /dev/null | head -n1 | cut -f1)"
    [[ -n "${sha}" ]] && { printf '%s' "${sha}"; return 0; }
    sha="$(git ls-remote --tags "${GIT_REPO}" "${GIT_REF}^{}" 2> /dev/null | head -n1 | cut -f1)"
    [[ -n "${sha}" ]] && { printf '%s' "${sha}"; return 0; }
    sha="$(git ls-remote --tags "${GIT_REPO}" "${GIT_REF}" 2> /dev/null | head -n1 | cut -f1)"
    [[ -n "${sha}" ]] && { printf '%s' "${sha}"; return 0; }
    return 1
}

local_sha() {
    git -C "${GIT_TARGET}" rev-parse HEAD 2> /dev/null || true
}

# ------------------------------------------------------------------ fetch ---

# One code path for branches, tags and commit SHAs: fetch the ref and check it
# out detached. A deployment has no business being on a tracking branch, and
# the special cases are where the bugs live.
#
# Every git call is checked explicitly. Inside an `if !` condition bash
# suspends errexit, so relying on `set -e` here would silently continue past a
# failed fetch and then reset the working copy to whatever FETCH_HEAD last was.
fetch_and_checkout() {
    local -a depth=()
    if [[ "${GIT_DEPTH}" != "0" ]]; then
        depth=("--depth=${GIT_DEPTH}")
    fi

    mkdir -p "${GIT_TARGET}" || return 1

    if [[ ! -d "${GIT_TARGET}/.git" ]]; then
        if [[ -n "$(ls -A "${GIT_TARGET}" 2> /dev/null)" ]]; then
            err "${GIT_TARGET} is not empty and is not a git working copy. Refusing to overwrite it."
            return 1
        fi
        info "Initialising working copy in ${GIT_TARGET}"
        git init -q "${GIT_TARGET}" || return 1
        git -C "${GIT_TARGET}" remote add origin "${GIT_REPO}" || return 1
    else
        git -C "${GIT_TARGET}" remote set-url origin "${GIT_REPO}" || return 1
    fi

    git -C "${GIT_TARGET}" fetch --force --prune "${depth[@]}" origin "${GIT_REF}" || return 1
    git -C "${GIT_TARGET}" checkout -q --force --detach FETCH_HEAD || return 1
    git -C "${GIT_TARGET}" reset -q --hard FETCH_HEAD || return 1

    if is_true "${GIT_CLEAN}"; then
        local -a clean=(clean -q -fd)
        local pattern
        # Ignored files are never touched: no -x. Uploads and caches that the
        # application writes belong in .gitignore, and then survive every
        # update without anyone having to configure an exclude.
        # shellcheck disable=SC2086
        for pattern in ${GIT_CLEAN_EXCLUDE:-}; do
            clean+=(-e "${pattern}")
        done
        git -C "${GIT_TARGET}" "${clean[@]}" || return 1
    fi

    if is_true "${GIT_SUBMODULES}"; then
        git -C "${GIT_TARGET}" submodule update --init --recursive "${depth[@]}" || return 1
    fi

    return 0
}

# ------------------------------------------------------------ after a pull ---

run_as_web() {
    if command -v runuser > /dev/null 2>&1; then
        runuser -u www-data -- "$@"
    else
        su -s /bin/bash -c "$(printf '%q ' "$@")" www-data
    fi
}

apply_ownership() {
    is_true "${GIT_CHOWN}" || return 0
    chown -R www-data:www-data "${GIT_TARGET}"
}

run_composer() {
    is_true "${COMPOSER_INSTALL}" || return 0
    if [[ ! -f "${GIT_TARGET}/composer.json" ]]; then
        warn "COMPOSER_INSTALL is on but ${GIT_TARGET}/composer.json does not exist. Skipping."
        return 0
    fi
    info "composer install"
    ( cd "${GIT_TARGET}" && run_as_web composer install --no-dev --no-progress --optimize-autoloader ) \
        || warn "composer install failed. The new code is deployed, its dependencies may not be."
}

run_hooks() {
    local hook="${GIT_TARGET}/.docker/post-update.sh"
    if [[ -f "${hook}" ]]; then
        info "Running .docker/post-update.sh"
        ( cd "${GIT_TARGET}" && run_as_web /bin/bash "${hook}" ) \
            || warn "post-update.sh exited non-zero."
    fi
    if [[ -n "${POST_UPDATE_CMD:-}" ]]; then
        info "Running POST_UPDATE_CMD"
        ( cd "${GIT_TARGET}" && run_as_web /bin/bash -c "${POST_UPDATE_CMD}" ) \
            || warn "POST_UPDATE_CMD exited non-zero."
    fi
}

reload_apache() {
    # Only once Apache is actually up. The first sync happens before it starts.
    pgrep -x apache2 > /dev/null 2>&1 || return 0
    info "Reloading Apache (graceful)"
    apache2ctl -k graceful 2> /dev/null \
        || kill -USR1 "$(cat /var/run/apache2/apache2.pid 2> /dev/null)" 2> /dev/null \
        || warn "Graceful reload failed. Apache keeps running on the old code until it is restarted."
}

# ------------------------------------------------------------------- main ---

main() {
    [[ -n "${GIT_REPO:-}" ]] || die "GIT_REPO is not set."

    exec 9> "${LOCK_FILE}"
    if ! flock -w 600 9; then
        die "Another synchronisation has held the lock for ten minutes. Giving up."
    fi

    local before after target=""
    before="$(local_sha)"

    if is_true "${GIT_PINNED:-false}" && [[ -n "${before}" ]]; then
        info "GIT_REF is pinned to a commit and the working copy is already there. Nothing to do."
        write_status ok "${before}" "pinned"
        return 0
    fi

    if ! is_true "${GIT_PINNED:-false}"; then
        if ! target="$(remote_sha)"; then
            if [[ -n "${before}" ]]; then
                warn "Cannot resolve ${GIT_REF} on the remote. Keeping the working copy at ${before:0:8}."
                write_status degraded "${before}" "remote unreachable or ref gone"
                return 0
            fi
            write_status error "" "cannot resolve ${GIT_REF} on ${GIT_REPO}"
            err "Cannot resolve ${GIT_REF} on ${GIT_REPO} and there is no working copy to fall back on."
            return 1
        fi

        if [[ "${before}" == "${target}" ]] && ! ${FORCE}; then
            write_status ok "${before}" "up to date"
            return 0
        fi
    fi

    if [[ -n "${before}" ]]; then
        info "Updating ${before:0:8} -> ${target:0:8} (${GIT_REF})"
    else
        info "Cloning ${GIT_REPO} at ${GIT_REF} into ${GIT_TARGET}"
    fi

    if ! fetch_and_checkout; then
        if [[ -n "${before}" ]]; then
            warn "Update failed. The working copy stays at ${before:0:8} and Apache keeps serving it."
            write_status degraded "${before}" "fetch failed"
        else
            write_status error "" "clone failed"
        fi
        return 1
    fi

    after="$(local_sha)"
    apply_ownership
    run_composer
    run_hooks
    reload_apache

    write_status ok "${after}" "synchronised"
    info "Working copy is at ${after:0:8}"
    return 0
}

main "$@"
