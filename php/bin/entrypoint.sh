#!/usr/bin/env bash
#
# Boot order, and why it is this order:
#
#   1. resolve configuration and credentials
#   2. clone or update, before Apache exists, so the first request already
#      sees the application rather than an empty directory
#   3. work out DOCUMENT_ROOT from what was actually cloned
#   4. write the Apache and PHP configuration
#   5. strip the secrets out of the environment
#   6. start the update loop, then hand over to Apache

set -Eeuo pipefail

LOG_TAG=entrypoint
# shellcheck source=../lib/common.sh
source "${PHP_GITHUB_LIB:-/usr/local/lib/php-github}/common.sh"

# Anything that is not Apache (git-sync, bash, a one-off command) gets to run
# without the whole boot sequence.
case "${1:-}" in
    apache2 | apache2-foreground) ;;
    *)
        exec "$@"
        ;;
esac

# ------------------------------------------------------------- credentials ---

prepare_runtime_dirs() {
    mkdir -p "${RUN_DIR}" "${SPOOL_DIR}"
    chmod 0755 "${RUN_DIR}"
    # The webhook runs as www-data and needs to drop a file here. Nothing else
    # in this directory is readable by it.
    chown www-data:www-data "${SPOOL_DIR}"
    chmod 0700 "${SPOOL_DIR}"
}

# Strips a userinfo section out of a URL so credentials cannot end up in the
# log by accident.
redact_url() {
    sed -E 's#(://)[^/@]+@#\1***@#' <<< "$1"
}

setup_credentials() {
    file_env GIT_TOKEN
    file_env GIT_SSH_KEY
    file_env WEBHOOK_SECRET

    umask 077

    if [[ -n "${GIT_TOKEN:-}" ]]; then
        printf '%s' "${GIT_TOKEN}" > "${TOKEN_FILE}"
        chmod 0600 "${TOKEN_FILE}"
        cat > "${ASKPASS_FILE}" <<EOF
#!/bin/sh
case "\$1" in
  Username*) printf '%s\n' "\${GIT_USERNAME:-x-access-token}" ;;
  Password*) cat ${TOKEN_FILE} ;;
esac
EOF
        chmod 0700 "${ASKPASS_FILE}"
        info "HTTPS credential configured for user ${GIT_USERNAME:-x-access-token}"
    fi

    if [[ -n "${GIT_SSH_KEY:-}" ]]; then
        printf '%s\n' "${GIT_SSH_KEY}" > "${SSH_KEY_FILE}"
        chmod 0600 "${SSH_KEY_FILE}"
        info "SSH key configured"
    fi

    if [[ -n "${WEBHOOK_SECRET:-}" ]]; then
        printf '%s' "${WEBHOOK_SECRET}" > "${SECRET_FILE}"
        # Readable by the webhook script, which runs as www-data. The git
        # credential above is not: that one is worth stealing, this one only
        # buys you the ability to trigger a pull.
        chown root:www-data "${SECRET_FILE}"
        chmod 0640 "${SECRET_FILE}"
    fi

    umask 022
}

# ----------------------------------------------------------- configuration ---

resolve_ref() {
    if [[ -n "${GIT_REF:-}" ]]; then
        # A bare commit SHA cannot be discovered with ls-remote, so it is
        # pinned by definition and polling would be pointless.
        if [[ "${GIT_REF}" =~ ^[0-9a-f]{7,40}$ ]] \
            && ! git ls-remote --heads --tags "${GIT_REPO}" "${GIT_REF}" 2> /dev/null | grep -q .; then
            GIT_PINNED=true
            info "GIT_REF looks like a commit. Pinned, no polling."
        fi
        return 0
    fi

    info "GIT_REF is not set, asking the remote for its default branch"
    GIT_REF="$(git ls-remote --symref "${GIT_REPO}" HEAD 2> /dev/null \
        | awk '/^ref:/ { sub("refs/heads/", "", $2); print $2; exit }')" || true

    if [[ -z "${GIT_REF}" ]]; then
        warn "Could not determine the default branch. Falling back to 'main'."
        GIT_REF=main
    else
        info "Default branch is ${GIT_REF}"
    fi
}

first_sync() {
    local attempt=1 delay

    while true; do
        if git-sync; then
            return 0
        fi

        if [[ -d "${GIT_TARGET}/.git" ]]; then
            warn "Working copy present but out of date. Starting anyway; the loop keeps trying."
            return 0
        fi

        if ((attempt >= GIT_CLONE_RETRIES)); then
            die "Could not clone $(redact_url "${GIT_REPO}") after ${GIT_CLONE_RETRIES} attempts and there is nothing to serve."
        fi

        delay=$((5 * 2 ** (attempt - 1)))
        ((delay > 120)) && delay=120
        warn "Clone attempt ${attempt} failed. Retrying in ${delay}s."
        sleep "${delay}"
        attempt=$((attempt + 1))
    done
}

# The point of the /var/www default: a repository that carries an html/
# directory needs no configuration at all. Everything else is a one-line guess
# that saves the next person a support round trip.
resolve_document_root() {
    if [[ -n "${DOCUMENT_ROOT:-}" ]]; then
        [[ -d "${DOCUMENT_ROOT}" ]] || warn "DOCUMENT_ROOT ${DOCUMENT_ROOT} does not exist in the working copy. Apache will answer 404."
        return 0
    fi

    local candidate
    for candidate in html public web htdocs www public_html; do
        if [[ -d "${GIT_TARGET}/${candidate}" ]]; then
            DOCUMENT_ROOT="${GIT_TARGET}/${candidate}"
            info "DOCUMENT_ROOT not set, using ${DOCUMENT_ROOT}"
            return 0
        fi
    done

    DOCUMENT_ROOT="${GIT_TARGET}"
    info "DOCUMENT_ROOT not set and no html/ or public/ in the repository, serving ${GIT_TARGET} itself"
}

configure_apache() {
    local module
    # shellcheck disable=SC2086
    for module in ${APACHE_MODS:-}; do
        a2enmod -q "${module}" 2> /dev/null || warn "Apache module '${module}' does not exist. Ignored."
    done

    sed -ri "s#^(\s*DocumentRoot\s+).*#\1${DOCUMENT_ROOT}#" /etc/apache2/sites-available/000-default.conf

    {
        echo "# Generated by php-github-entrypoint on every start. Do not edit."
        echo "ServerTokens Prod"
        echo "ServerSignature Off"

        if [[ -n "${APACHE_SERVER_NAME:-}" ]]; then
            echo "ServerName ${APACHE_SERVER_NAME}"
        else
            # Silences the FQDN warning that otherwise opens every log.
            echo "ServerName localhost"
        fi

        echo
        echo "<Directory \"${DOCUMENT_ROOT}\">"
        echo "    Options -Indexes +FollowSymLinks"
        echo "    AllowOverride ${APACHE_ALLOW_OVERRIDE}"
        echo "    Require all granted"
        echo "</Directory>"

        echo
        echo "# .git, .env, .docker and friends are never served, wherever"
        echo "# DOCUMENT_ROOT happens to point. /.well-known stays reachable."
        echo '<LocationMatch "(^|/)\.(?!well-known/)">'
        echo "    Require all denied"
        echo "</LocationMatch>"

        if [[ -n "${TRUSTED_PROXIES:-}" ]]; then
            echo
            echo "RemoteIPHeader X-Forwarded-For"
            local proxy
            # shellcheck disable=SC2086
            for proxy in ${TRUSTED_PROXIES}; do
                echo "RemoteIPTrustedProxy ${proxy}"
            done
            # Redefining the nickname is enough: conf-enabled is read before
            # sites-enabled, so the vhost's CustomLog picks this version up.
            echo 'LogFormat "%a %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" combined'
        fi

        if [[ -r "${SECRET_FILE}" ]]; then
            echo
            echo "Alias \"${WEBHOOK_PATH}\" \"/opt/webhook/index.php\""
            echo '<Directory "/opt/webhook">'
            echo "    Options -Indexes"
            echo "    Require all granted"
            echo "</Directory>"
            echo '# mod_php sees the Authorization header, but not on every build.'
            # $1 is Apache's backreference, not a shell positional parameter.
            # shellcheck disable=SC2016
            echo 'SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=$1'
        fi
    } > /etc/apache2/conf-available/zz-php-github.conf

    a2enconf -q zz-php-github

    if [[ -r "${SECRET_FILE}" ]]; then
        info "Webhook enabled at POST ${WEBHOOK_PATH}"
    else
        info "Webhook disabled (WEBHOOK_SECRET not set)"
    fi
}

configure_php() {
    local preset="${PHP_INI_PRESET:-production}"
    case "${preset}" in
        production | development)
            cp "/usr/local/etc/php/php.ini-${preset}" /usr/local/etc/php/php.ini
            ;;
        none) ;;
        *)
            warn "PHP_INI_PRESET '${preset}' is neither production, development nor none. Using production."
            cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini
            ;;
    esac

    {
        echo "; Generated by php-github-entrypoint on every start. Do not edit."
        [[ -n "${PHP_MEMORY_LIMIT:-}" ]] && echo "memory_limit = ${PHP_MEMORY_LIMIT}"
        [[ -n "${PHP_UPLOAD_MAX_FILESIZE:-}" ]] && echo "upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}"
        [[ -n "${PHP_POST_MAX_SIZE:-}" ]] && echo "post_max_size = ${PHP_POST_MAX_SIZE}"
        [[ -n "${PHP_MAX_EXECUTION_TIME:-}" ]] && echo "max_execution_time = ${PHP_MAX_EXECUTION_TIME}"
        [[ -n "${PHP_TIMEZONE:-}" ]] && echo "date.timezone = ${PHP_TIMEZONE}"
        [[ -n "${PHP_ERROR_REPORTING:-}" ]] && echo "error_reporting = ${PHP_ERROR_REPORTING}"
        [[ -n "${PHP_DISPLAY_ERRORS:-}" ]] && echo "display_errors = ${PHP_DISPLAY_ERRORS}"
        true
    } > /usr/local/etc/php/conf.d/zz-php-github.ini
}

# Apache inherits this process's environment, and mod_php hands it straight to
# the application through getenv(). A repository that prints phpinfo() would
# otherwise print the deploy token with it.
scrub_environment() {
    unset GIT_TOKEN GIT_TOKEN_FILE GIT_SSH_KEY GIT_SSH_KEY_FILE
    unset WEBHOOK_SECRET WEBHOOK_SECRET_FILE
    unset GIT_REPO GIT_REF GIT_USERNAME
    unset GIT_ASKPASS GIT_SSH_COMMAND
}

# ------------------------------------------------------------------- main ---

main() {
    [[ -n "${GIT_REPO:-}" ]] || die "GIT_REPO is not set. This image has nothing to serve without it."

    prepare_runtime_dirs
    setup_credentials
    setup_git_auth

    # Read back by git-sync through the config file, not in this process.
    # shellcheck disable=SC2034
    GIT_PINNED=false
    resolve_ref

    info "Repository $(redact_url "${GIT_REPO}") ref ${GIT_REF} into ${GIT_TARGET}"
    write_config

    first_sync
    resolve_document_root

    # DOCUMENT_ROOT may have been discovered rather than configured, and
    # git-sync reads it back from here.
    write_config

    configure_apache
    configure_php

    git-sync-loop &
    echo $! > "${RUN_DIR}/loop.pid"

    scrub_environment

    info "Handing over to $*"
    exec "$@"
}

main "$@"
