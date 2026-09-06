#!/usr/bin/env bash
#
# Unhealthy means: no working copy, the update loop has died, Apache does not
# answer, or the last synchronisation failed outright.
#
# "degraded" (the remote was unreachable but an older working copy is being
# served) counts as healthy on purpose. GitHub being down is not a reason to
# take a working site out of a load balancer.

set -uo pipefail

# shellcheck source=../lib/common.sh
source "${PHP_GITHUB_LIB:-/usr/local/lib/php-github}/common.sh"

load_config

target="${GIT_TARGET:-/var/www}"

[[ -d "${target}/.git" ]] || {
    echo "no working copy in ${target}"
    exit 1
}

if [[ -r "${RUN_DIR}/loop.pid" ]]; then
    if ! kill -0 "$(< "${RUN_DIR}/loop.pid")" 2> /dev/null; then
        echo "update loop is not running"
        exit 1
    fi
fi

code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 http://127.0.0.1/ 2> /dev/null || true)"
if [[ -z "${code}" || "${code}" == "000" ]]; then
    echo "apache did not answer on 127.0.0.1:80"
    exit 1
fi

if [[ "$(read_status_state || true)" == "error" ]]; then
    echo "last synchronisation failed"
    exit 1
fi

exit 0
