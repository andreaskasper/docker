#!/usr/bin/env bash
#
# Background loop. Two ways to wake up:
#   - the clock, every GIT_POLL_INTERVAL seconds (0 disables polling)
#   - the webhook, which drops a file in the spool directory
#
# Deliberately no `set -e`: a failed synchronisation must not take the loop
# down with it. A container that stops updating silently is worse than one
# that logs an error every few minutes.

set -Euo pipefail

LOG_TAG=git-sync-loop
# shellcheck source=../lib/common.sh
source "${PHP_GITHUB_LIB:-/usr/local/lib/php-github}/common.sh"

load_config

SLICE=5
elapsed=0

interval="${GIT_POLL_INTERVAL:-300}"
debounce="${WEBHOOK_DEBOUNCE:-5}"

if [[ "${interval}" == "0" ]]; then
    info "Polling disabled. Updates only happen on a webhook or a manual git-sync."
else
    info "Watching ${GIT_REF} every ${interval}s"
fi

while true; do
    sleep "${SLICE}"
    elapsed=$((elapsed + SLICE))
    triggered=false

    if [[ -e "${TRIGGER_FILE}" ]]; then
        rm -f "${TRIGGER_FILE}"
        # A push often arrives as a burst of events. Wait out the burst and
        # drop whatever else landed, so one update covers all of them.
        sleep "${debounce}"
        rm -f "${TRIGGER_FILE}"
        info "Webhook trigger received"
        triggered=true
    fi

    if [[ "${triggered}" == "true" ]] || { [[ "${interval}" != "0" ]] && ((elapsed >= interval)); }; then
        elapsed=0
        git-sync || warn "Synchronisation failed. Retrying on the next tick."
    fi
done
