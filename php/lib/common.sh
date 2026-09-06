#!/usr/bin/env bash
# Shared helpers for the php-*-apache-github image.
# Sourced by the entrypoint, the sync script and the loop. Not executable.

# Every path below is consumed by the scripts that source this file, not by
# this file itself.
# shellcheck disable=SC2034

# Overridable so that the test suite can run the real code paths without root.
# Nothing in the image ever sets it.
RUN_DIR="${PHP_GITHUB_RUN_DIR:-/run/php-github}"
SPOOL_DIR="${RUN_DIR}/spool"
TRIGGER_FILE="${SPOOL_DIR}/trigger"
CONFIG_FILE="${RUN_DIR}/config"
STATUS_FILE="${RUN_DIR}/status"
LOCK_FILE="${RUN_DIR}/sync.lock"
TOKEN_FILE="${RUN_DIR}/git-token"
SECRET_FILE="${RUN_DIR}/webhook-secret"
ASKPASS_FILE="${RUN_DIR}/askpass"
SSH_KEY_FILE="${RUN_DIR}/ssh-key"

# ---------------------------------------------------------------- logging ---

_log() { printf '%s %-5s [%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" "${LOG_TAG:-php-github}" "$2"; }
info() { _log INFO "$*"; }
warn() { _log WARN "$*"; }
err()  { _log ERROR "$*" >&2; }
die()  { err "$*"; exit 1; }

# ------------------------------------------------------------------ types ---

is_true() {
    case "${1,,}" in
        1 | true | yes | on) return 0 ;;
        *) return 1 ;;
    esac
}

# Reads VAR or VAR_FILE into VAR. The _FILE form is how Docker and Podman
# secrets get in without the value ever appearing in `docker inspect`.
file_env() {
    local var="$1" file_var="${1}_FILE" default="${2:-}" value

    if [[ -n "${!var:-}" && -n "${!file_var:-}" ]]; then
        die "${var} and ${file_var} are both set. Pick one."
    fi

    if [[ -n "${!var:-}" ]]; then
        value="${!var}"
    elif [[ -n "${!file_var:-}" ]]; then
        [[ -r "${!file_var}" ]] || die "${file_var} points at ${!file_var}, which is not readable."
        value="$(< "${!file_var}")"
    else
        value="${default}"
    fi

    printf -v "${var}" '%s' "${value}"
    export "${var?}"
    unset "${file_var}"
}

# ----------------------------------------------------------------- config ---

# The entrypoint resolves the configuration once and writes it here so that
# `docker exec <container> git-sync` sees the same settings, and so that the
# loop does not depend on an environment we deliberately strip before Apache
# starts.
CONFIG_KEYS=(
    GIT_REPO GIT_REF GIT_TARGET GIT_DEPTH GIT_POLL_INTERVAL
    GIT_CLEAN GIT_CLEAN_EXCLUDE GIT_SUBMODULES GIT_CHOWN
    GIT_USERNAME GIT_PINNED
    DOCUMENT_ROOT COMPOSER_INSTALL POST_UPDATE_CMD WEBHOOK_DEBOUNCE
)

write_config() {
    local key
    umask 077
    : > "${CONFIG_FILE}"
    for key in "${CONFIG_KEYS[@]}"; do
        printf '%s=%q\n' "${key}" "${!key:-}" >> "${CONFIG_FILE}"
    done
}

load_config() {
    if [[ -r "${CONFIG_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${CONFIG_FILE}"
    fi
    apply_defaults
}

# The Dockerfile sets the same defaults as ENV, which is where a user goes
# looking for them. Repeating them here means the scripts still behave when
# somebody clears a variable with `-e GIT_CLEAN=` or runs them outside the
# image, instead of dying on an unbound variable.
apply_defaults() {
    : "${GIT_TARGET:=/var/www}"
    : "${GIT_REF:=}"
    : "${GIT_DEPTH:=1}"
    : "${GIT_POLL_INTERVAL:=300}"
    : "${GIT_CLEAN:=true}"
    : "${GIT_CLEAN_EXCLUDE:=}"
    : "${GIT_SUBMODULES:=false}"
    : "${GIT_CHOWN:=true}"
    : "${GIT_CLONE_RETRIES:=5}"
    : "${GIT_PINNED:=false}"
    : "${APACHE_MODS:=rewrite headers}"
    : "${APACHE_ALLOW_OVERRIDE:=All}"
    : "${PHP_INI_PRESET:=production}"
    : "${COMPOSER_INSTALL:=false}"
    : "${POST_UPDATE_CMD:=}"
    : "${WEBHOOK_PATH:=/_git/webhook}"
    : "${WEBHOOK_DEBOUNCE:=5}"
}

# ------------------------------------------------------------------- auth ---

# Neither the token nor the key is passed to git through the environment or
# through the remote URL. The URL would end up in .git/config, in `git
# remote -v` and in every error message; the environment is inherited by
# Apache, where any deployed script could read it back out with getenv().
setup_git_auth() {
    if [[ -r "${ASKPASS_FILE}" ]]; then
        export GIT_ASKPASS="${ASKPASS_FILE}"
        export GIT_TERMINAL_PROMPT=0
        # The askpass helper is a separate process and reads this from its own
        # environment. `source config` alone would leave it unexported, and a
        # manual `docker exec git-sync` would then authenticate as the wrong
        # user against hosts that care.
        export GIT_USERNAME="${GIT_USERNAME:-x-access-token}"
    fi
    if [[ -r "${SSH_KEY_FILE}" ]]; then
        export GIT_SSH_COMMAND="ssh -i ${SSH_KEY_FILE} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o BatchMode=yes"
    fi
}

# ----------------------------------------------------------------- status ---

write_status() {
    local state="$1" sha="${2:-}" message="${3:-}"
    umask 022
    cat > "${STATUS_FILE}" <<EOF
{"state":"${state}","sha":"${sha}","message":"${message//\"/\'}","at":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')"}
EOF
}

read_status_state() {
    [[ -r "${STATUS_FILE}" ]] || return 1
    sed -n 's/.*"state":"\([^"]*\)".*/\1/p' "${STATUS_FILE}"
}
