#!/usr/bin/env bash
#
# Exercises git-sync against a throwaway local repository. No Docker, no
# network, no root — so it runs anywhere, including in CI before the image is
# built.
#
#     ./test/sync-test.sh
#
# What it cannot cover, because those need a container: the Apache
# configuration, the webhook over HTTP, chown, and running hooks as www-data.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "${HERE}")"

export PHP_GITHUB_LIB="${ROOT}/lib"
export PATH="${ROOT}/bin:${PATH}"

# The scripts are installed without their .sh suffix in the image.
BIN="$(mktemp -d)"
cp "${ROOT}/bin/git-sync.sh" "${BIN}/git-sync"
chmod +x "${BIN}/git-sync"
export PATH="${BIN}:${PATH}"

WORK="$(mktemp -d)"
ORIGIN="${WORK}/origin"
export GIT_TARGET="${WORK}/www"
export PHP_GITHUB_RUN_DIR="${WORK}/run"
export GIT_REPO="file://${ORIGIN}"
export GIT_REF=main
export GIT_CHOWN=false
export GIT_CLEAN=true
export COMPOSER_INSTALL=false
export GIT_DEPTH=1

mkdir -p "${PHP_GITHUB_RUN_DIR}/spool"

PASS=0
FAIL=0

cleanup() { rm -rf "${WORK}" "${BIN}"; }
trap cleanup EXIT

ok()   { printf '  \033[32mok\033[0m   %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }
check() { if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 (expected '$2', got '$1')"; fi; }
exists() { if [[ -e "$1" ]]; then ok "$2"; else bad "$2"; fi; }
absent() { if [[ -e "$1" ]]; then bad "$2"; else ok "$2"; fi; }

heading() { printf '\n\033[1m%s\033[0m\n' "$1"; }

git_origin() { git -C "${ORIGIN}" -c user.email=t@t -c user.name=t "$@"; }

sync() { git-sync "$@" > "${WORK}/last.log" 2>&1; }

status_state()   { sed -n 's/.*"state":"\([^"]*\)".*/\1/p' "${PHP_GITHUB_RUN_DIR}/status"; }
status_message() { sed -n 's/.*"message":"\([^"]*\)".*/\1/p' "${PHP_GITHUB_RUN_DIR}/status"; }

# --------------------------------------------------------------- fixtures ---

heading "Fixture"
git init -q -b main "${ORIGIN}"
mkdir -p "${ORIGIN}/html"
echo '<?php echo "v1";' > "${ORIGIN}/html/index.php"
printf 'html/uploads/\n' > "${ORIGIN}/.gitignore"
git_origin add -A
git_origin commit -qm "v1"
ok "origin repository created"

# ------------------------------------------------------------------ tests ---

heading "First clone"
if sync; then ok "git-sync exits 0"; else bad "git-sync failed: $(tail -3 "${WORK}/last.log")"; fi
exists "${GIT_TARGET}/html/index.php" "working copy contains html/index.php"
check "$(cat "${GIT_TARGET}/html/index.php")" '<?php echo "v1";' "content matches the commit"
check "$(status_state)" "ok" "status is ok"

heading "No change"
sync
check "$(status_state)" "ok" "second run stays ok"
check "$(status_message)" "up to date" "short-circuits without fetching"

heading "Update"
echo '<?php echo "v2";' > "${ORIGIN}/html/index.php"
git_origin add -A
git_origin commit -qm "v2"
sync
check "$(cat "${GIT_TARGET}/html/index.php")" '<?php echo "v2";' "new commit is checked out"

heading "Local edits are overwritten"
echo 'tampered' > "${GIT_TARGET}/html/index.php"
sync --force
check "$(cat "${GIT_TARGET}/html/index.php")" '<?php echo "v2";' "reset --hard restores the tracked file"

heading "clean -fd removes untracked files"
echo 'junk' > "${GIT_TARGET}/leftover.txt"
sync --force
absent "${GIT_TARGET}/leftover.txt" "untracked file removed"

heading "Ignored files survive (no -x)"
mkdir -p "${GIT_TARGET}/html/uploads"
echo 'a user upload' > "${GIT_TARGET}/html/uploads/photo.jpg"
sync --force
exists "${GIT_TARGET}/html/uploads/photo.jpg" ".gitignore protects uploads"

heading "GIT_CLEAN_EXCLUDE"
echo 'not ignored, but excluded' > "${GIT_TARGET}/keepme.log"
GIT_CLEAN_EXCLUDE='keepme.log' sync --force
exists "${GIT_TARGET}/keepme.log" "excluded pattern survives"
sync --force
absent "${GIT_TARGET}/keepme.log" "removed again without the exclude"

heading "Tags"
git_origin tag v1.0
GIT_REF=v1.0 sync
check "$(cat "${GIT_TARGET}/html/index.php")" '<?php echo "v2";' "a tag ref checks out"

heading "Annotated tags"
git_origin -c user.email=t@t -c user.name=t tag -a v2.0 -m "release"
GIT_REF=v2.0 sync
check "$(status_state)" "ok" "an annotated tag resolves to its commit"

heading "Unknown ref with a working copy present"
GIT_REF=does-not-exist sync
check "$?" "0" "exits 0 rather than taking the site down"
check "$(status_state)" "degraded" "status is degraded"
exists "${GIT_TARGET}/html/index.php" "old working copy still served"

heading "Unknown ref with nothing to fall back on"
env GIT_TARGET="${WORK}/nothing-here" GIT_REF=does-not-exist git-sync > /dev/null 2>&1
check "$?" "1" "exits 1 so the restart policy notices"

heading "Non-empty directory that is not a repository"
mkdir -p "${WORK}/occupied"
echo 'somebody else lives here' > "${WORK}/occupied/data.txt"
GIT_TARGET="${WORK}/occupied" sync
check "$?" "1" "refuses to clone over it"
exists "${WORK}/occupied/data.txt" "existing data untouched"

heading "Deleted files are really deleted"
GIT_REF=main sync
git_origin rm -q "html/index.php"
git_origin commit -qm "remove index"
sync
absent "${GIT_TARGET}/html/index.php" "upstream deletion applied"

# ----------------------------------------------------------------- result ---

printf '\n%d passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
