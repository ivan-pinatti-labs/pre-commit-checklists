#!/usr/bin/env bash
#
# Phase `units`: every line of every script under scripts/, with nothing
# real behind it.
#
# lint_shell.sh (phase `shell`) tests the same scripts against the real
# pre-commit, git and detect-secrets, which is what proves they work. This
# file proves every line of them runs: `make coverage` runs it under kcov
# and fails below 100%. So the commands the scripts call out to (git,
# pre-commit, detect-secrets, curl, wget) are stubs in a scratch directory,
# and every script runs with a PATH holding those stubs plus a short list of
# coreutils and nothing else. Nothing here touches the network, the real git
# configuration or a real repository, which is also why it can run in the
# locked down kcov container.
#
# Each case runs the script as its own bash process, the way pre-commit
# and a consumer do, and kcov follows it there.
#
# install.sh picks its mode from where it is: next to a templates/ tree it
# copies files off disk, anywhere else it fetches them. The remote cases
# therefore run it through a symlink in a scratch directory with no
# templates/ beside it. kcov resolves the link, so those lines count
# against scripts/install.sh itself.
#
# Exit status: 0 if every case passed, 1 otherwise.

set -o errexit
set -o pipefail
set -o nounset

HERE=$(dirname "$(realpath "${0}")")
REPO_ROOT=$(realpath "${HERE}/../..")
SCRIPTS="${REPO_ROOT}/scripts"
BASH_BIN=$(command -v bash)

# What a CI runner or a developer shell may already carry, and what would
# change what the scripts do.
unset GITHUB_HEAD_REF DEBUG

SCRATCH=$(mktemp -d)
trap 'rm -rf "${SCRATCH}"' EXIT
FAILURES=0
TOTAL=0

# --- The PATH every script under test gets ---------------------------------

# Coreutils the scripts and the stubs need, linked from wherever this host
# keeps them. curl and wget are deliberately absent: a case that wants a
# fetcher adds the stub directory for it.
TOOLS="${SCRATCH}/tools"
mkdir -p "${TOOLS}"
for tool in bash cat dirname basename realpath mktemp mkdir rm cp grep tail head sed awk tr chmod; do
  ln -s "$(command -v "${tool}")" "${TOOLS}/${tool}"
done

STUBS="${SCRATCH}/stubs"
CURL_DIR="${SCRATCH}/curl"
WGET_DIR="${SCRATCH}/wget"
NO_SECRETS="${SCRATCH}/no-secrets"
NO_PRE_COMMIT="${SCRATCH}/no-pre-commit"
mkdir -p "${STUBS}" "${CURL_DIR}" "${WGET_DIR}" "${NO_SECRETS}" "${NO_PRE_COMMIT}"

# Every stub records its arguments here, one call per line.
STUB_LOG="${SCRATCH}/stub.log"
export STUB_LOG

# git: only `git symbolic-ref --short HEAD` is ever called. STUB_BRANCH is
# the answer; unset, it fails the way git does outside a branch.
cat >"${STUBS}/git" <<'EOF'
#!/usr/bin/env bash
echo "git $*" >>"${STUB_LOG}"
[[ -n "${STUB_BRANCH:-}" ]] || exit 128
echo "${STUB_BRANCH}"
EOF

# pre-commit: `run` exits STUB_RUN_EXIT, `autoupdate` fails when
# STUB_AUTOUPDATE=fail, `install` succeeds.
cat >"${STUBS}/pre-commit" <<'EOF'
#!/usr/bin/env bash
echo "pre-commit $*" >>"${STUB_LOG}"
case "${1}" in
run) exit "${STUB_RUN_EXIT:-0}" ;;
autoupdate) [[ "${STUB_AUTOUPDATE:-ok}" = ok ]] ;;
esac
EOF

cat >"${STUBS}/detect-secrets" <<'EOF'
#!/usr/bin/env bash
echo "detect-secrets $*" >>"${STUB_LOG}"
echo '{"results": {}}'
EOF

# The two fetchers serve templates/<path> out of STUB_TEMPLATES (this
# repository's own templates/ by default) and answer the GitHub releases API
# with STUB_TAG, or fail it when STUB_TAG is unset. STUB_STATUS forces an
# HTTP status for any template URL matching STUB_STATUS_MATCH, and
# STUB_DOWN=1 makes every transfer fail before any HTTP status at all, the
# shape of a DNS or connection error. A template the source tree lacks is a
# 404.
cat >"${STUBS}/serve" <<'EOF'
# Sourced by the curl and wget stubs. Sets STATUS and BODY for URL.
STATUS=200
BODY=""
case "${URL}" in
*/releases/latest)
  [[ -n "${STUB_TAG:-}" ]] || STATUS=404
  BODY="{\"url\": \"x\", \"tag_name\": \"${STUB_TAG:-}\", \"name\": \"x\"}"
  ;;
*)
  BODY="${STUB_TEMPLATES}/${URL#*/templates/}"
  [[ -f "${BODY}" ]] || STATUS=404
  if [[ -n "${STUB_STATUS:-}" ]] && [[ ${URL} =~ ${STUB_STATUS_MATCH:-.} ]]; then
    STATUS="${STUB_STATUS}"
  fi
  ;;
esac
EOF

cat >"${CURL_DIR}/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >>"${STUB_LOG}"
fail=false
out=""
write=""
while [[ $# -gt 1 ]]; do
  case "${1}" in
  -o) out="${2}"; shift ;;
  -w) write="${2}"; shift ;;
  -f*) fail=true ;;
  esac
  shift
done
URL="${1}"
[[ "${STUB_DOWN:-0}" = 1 ]] && exit 6
source "$(dirname "${0}")/../stubs/serve"
if [[ "${fail}" = true ]] && [[ "${STATUS}" -ge 400 ]]; then
  exit 22
fi
if [[ -n "${out}" ]]; then
  if [[ -f "${BODY}" ]]; then cat "${BODY}" >"${out}"; else echo "not found" >"${out}"; fi
else
  echo "${BODY}"
fi
[[ -z "${write}" ]] || printf '%s' "${STATUS}"
EOF

# wget prints its status lines on stderr only with --server-response, and
# STUB_QUIET=1 leaves them out, the way some proxies and old wget builds do.
cat >"${WGET_DIR}/wget" <<'EOF'
#!/usr/bin/env bash
echo "wget $*" >>"${STUB_LOG}"
out=""
while [[ $# -gt 1 ]]; do
  case "${1}" in
  -O) out="${2}"; shift ;;
  -qO-) out="-" ;;
  esac
  shift
done
URL="${1}"
[[ "${STUB_DOWN:-0}" = 1 ]] && exit 4
source "$(dirname "${0}")/../stubs/serve"
if [[ "${out}" = "-" ]]; then
  [[ "${STATUS}" -lt 400 ]] || exit 8
  echo "${BODY}"
  exit 0
fi
[[ "${STUB_QUIET:-0}" = 1 ]] || echo "  HTTP/1.1 ${STATUS} Stub" >&2
[[ "${STATUS}" -lt 400 ]] || exit 8
cat "${BODY}" >"${out}"
EOF

chmod +x "${STUBS}/git" "${STUBS}/pre-commit" "${STUBS}/detect-secrets" "${CURL_DIR}/curl" "${WGET_DIR}/wget"
for stub in git; do
  ln -s "${STUBS}/${stub}" "${NO_SECRETS}/${stub}"
  ln -s "${STUBS}/${stub}" "${NO_PRE_COMMIT}/${stub}"
done
ln -s "${STUBS}/pre-commit" "${NO_SECRETS}/pre-commit"
ln -s "${STUBS}/detect-secrets" "${NO_PRE_COMMIT}/detect-secrets"

# --- Running a case and checking it -----------------------------------------

# run <stub dirs> <script> [args...]: runs scripts/<script> (or the path
# given) with PATH set to the stub directories, colon separated, then the
# tools. Sets STATUS; standard output and error land in OUT and ERR files.
# Environment for the case goes in front, as `VAR=x run ...`; RUN_IN names
# the directory to run it from, the current one by default.
OUT="${SCRATCH}/out"
ERR="${SCRATCH}/err"
run() {
  local dirs="${1}" script="${2}"
  shift 2
  [[ ${script} == /* ]] || script="${SCRIPTS}/${script}"
  : >"${STUB_LOG}"
  STATUS=0
  (cd "${RUN_IN:-.}" && PATH="${dirs}:${TOOLS}" exec "${BASH_BIN}" "${script}" "$@") >"${OUT}" 2>"${ERR}" || STATUS=$?
}

# check <name> <status> [<out|err|log> <text>]...: the case passed when the
# script exited <status> and every <text> appears in its stream.
check() {
  local name="${1}" want="${2}" stream file problem=""
  shift 2
  if [[ "${STATUS}" -ne "${want}" ]]; then
    problem="exit ${STATUS}, wanted ${want}"
  fi
  while [[ -z "${problem}" ]] && [[ $# -gt 0 ]]; do
    stream="${1}"
    case "${stream}" in
    out) file="${OUT}" ;;
    err) file="${ERR}" ;;
    log) file="${STUB_LOG}" ;;
    esac
    grep --quiet --fixed-strings -- "${2}" "${file}" || problem="'${2}' not in ${stream}"
    shift 2
  done
  TOTAL=$((TOTAL + 1))
  if [[ -n "${problem}" ]]; then
    FAILURES=$((FAILURES + 1))
    echo "  FAIL: ${name}: ${problem}"
    sed 's/^/         out: /' "${OUT}"
    sed 's/^/         err: /' "${ERR}"
  else
    echo "  ok  : ${name}"
  fi
}

# expect <name> <test expression...>: a plain assertion about files a case
# left behind.
expect() {
  local name="${1}"
  shift
  TOTAL=$((TOTAL + 1))
  if "$@"; then
    echo "  ok  : ${name}"
  else
    FAILURES=$((FAILURES + 1))
    echo "  FAIL: ${name}"
  fi
}

# A fresh, empty directory to bootstrap.
new_target() {
  TARGET=$(mktemp -d "${SCRATCH}/target.XXXXXX")
}

# A directory holding scripts/install.sh as a symlink to the real one, with
# whatever templates/ the caller then puts beside it (none, for remote mode).
fake_checkout() {
  CHECKOUT=$(mktemp -d "${SCRATCH}/checkout.XXXXXX")
  mkdir "${CHECKOUT}/scripts"
  ln -s "${SCRIPTS}/install.sh" "${CHECKOUT}/scripts/install.sh"
}

# --- check-branch-name.sh ---------------------------------------------------

echo "=== check-branch-name.sh ==="

STUB_BRANCH=main run "${STUBS}" check-branch-name.sh
check "a protected branch passes" 0 out "is a protected branch name" log "git symbolic-ref --short HEAD"

STUB_BRANCH=fix/flaky-test DEBUG=true run "${STUBS}" check-branch-name.sh
check "an ordinary slug passes, with DEBUG on" 0 out "'fix/flaky-test' is valid"

GITHUB_HEAD_REF=BadName STUB_BRANCH=main run "${STUBS}" check-branch-name.sh
check "GITHUB_HEAD_REF wins over git and a bad name fails" 1 out "must be lowercase"

run "${STUBS}" check-branch-name.sh
check "no branch at all exits 2" 2 err "could not be determined"

STUB_BRANCH=trunk run "${STUBS}" check-branch-name.sh --protected-branches "trunk release"
check "--protected-branches replaces the list" 0 out "'trunk' is a protected branch name"

STUB_BRANCH=proj-12-login run "${STUBS}" check-branch-name.sh --ticket-prefixes "PROJ ACME"
check "a ticket branch passes with --ticket-prefixes" 0 out "'proj-12-login' is valid"

STUB_BRANCH=add-login run "${STUBS}" check-branch-name.sh --ticket-prefixes PROJ
check "a branch with no ticket fails with --ticket-prefixes" 1 out "prefixes (case-insensitive)"

run "${STUBS}" check-branch-name.sh --help
check "--help prints usage and exits 3" 3 out "Usage: check-branch-name.sh"

run "${STUBS}" check-branch-name.sh --bogus
check "an unknown option exits 3" 3 err "Unknown option: --bogus"

# --- check-commit-msg.sh ----------------------------------------------------

echo "=== check-commit-msg.sh ==="

MSG="${SCRATCH}/COMMIT_EDITMSG"
echo "feat(auth): add login" >"${MSG}"

DEBUG=true run "${STUBS}" check-commit-msg.sh "${MSG}"
check "a Conventional Commit passes, with DEBUG on" 0 out "Commit message is valid."

echo "added stuff" >"${MSG}"
run "${STUBS}" check-commit-msg.sh -- "${MSG}"
check "a free form message fails, after --" 1 out "does not follow Conventional Commits"

echo "feat(PROJ-7): add login" >"${MSG}"
run "${STUBS}" check-commit-msg.sh --ticket-prefixes "PROJ ACME" "${MSG}"
check "a ticket scope passes with --ticket-prefixes" 0 out "Commit message is valid."

echo "feat: add login" >"${MSG}"
run "${STUBS}" check-commit-msg.sh --ticket-prefixes PROJ "${MSG}"
check "no ticket scope fails with --ticket-prefixes" 1 out "type(TICKET-ID): description"

run "${STUBS}" check-commit-msg.sh --help
check "--help prints usage and exits 0" 0 out "Usage: check-commit-msg.sh"

run "${STUBS}" check-commit-msg.sh --bogus "${MSG}"
check "an unknown option exits 2" 2 err "Unknown option: --bogus"

run "${STUBS}" check-commit-msg.sh
check "no message file exits 3" 3 err "missing commit message file"

# --- run-checklist.sh -------------------------------------------------------

echo "=== run-checklist.sh ==="

DEBUG=true STUB_RUN_EXIT=1 run "${STUBS}" run-checklist.sh checklist-toml a.toml b.toml
check "hands the checklist to pre-commit and returns its status" 1 \
  log "pre-commit run --config ${SCRIPTS}/../checklists/checklist-toml.yaml --files a.toml b.toml"

run "${STUBS}" run-checklist.sh
check "no checklist name exits 1" 1 out "Usage: run-checklist.sh"

run "${STUBS}" run-checklist.sh --hook-arg a.toml
check "an unknown checklist exits 2 and names the args: hazard" 2 err "docs/overrides.md"

# --- install.sh, local mode -------------------------------------------------

echo "=== install.sh (local) ==="

run "${STUBS}" install.sh --help
check "--help prints usage and exits 1" 1 out "Usage: install.sh"

run "${STUBS}" install.sh --bogus
check "an unknown option exits 1" 1 err "Unknown option: --bogus"

run "${STUBS}" install.sh
check "local mode requires --target" 1 err "--target is required"

run "${STUBS}" install.sh --target "${SCRATCH}/absent"
check "a missing target exits 2" 2 err "does not exist"

new_target
run "${STUBS}" install.sh --target "${TARGET}" --template nope
check "an unknown template exits 3" 3 err "no template named 'nope'"

new_target
DEBUG=true run "${STUBS}" install.sh --target "${TARGET}" --template minimal --community-files --ref ignored
check "bootstraps every file, with DEBUG on" 0 \
  out "Wrote ${TARGET}/.pre-commit-config.yaml" \
  out "Wrote ${TARGET}/SECURITY.md" \
  out "Appended gitignore entries" \
  out "Resolved the pre-commit-checklists pin to v2.4.0." \
  out "rev:' pin is already at this library's latest release" \
  out "Search CODE_OF_CONDUCT.md and SECURITY.md" \
  log "detect-secrets scan" \
  log "pre-commit autoupdate --repo https://github.com/ivan-pinatti-labs/pre-commit-checklists" \
  log "pre-commit install"
expect "the baseline is private to its owner" test "$(stat -c %a "${TARGET}/.secrets.baseline")" = 600

STUB_AUTOUPDATE=fail run "${STUBS}" install.sh --target "${TARGET}" --template minimal
check "a second run skips what exists and survives a failed autoupdate" 0 \
  err "Skipping ${TARGET}/.editorconfig: already exists" \
  out "Skipping .gitignore: already has the pre-commit-checklists section." \
  out "Skipping .secrets.baseline: already exists" \
  err "could not reach GitHub to resolve the 'rev:' pin"

run "${STUBS}" install.sh --target "${TARGET}" --template minimal --force
check "--force writes everything again" 0 out "Wrote ${TARGET}/.editorconfig" out "Wrote ${TARGET}/.secrets.baseline"

new_target
run "${NO_SECRETS}" install.sh --target "${TARGET}"
check "no detect-secrets exits 5" 5 err "detect-secrets is not installed"

new_target
run "${NO_PRE_COMMIT}" install.sh --target "${TARGET}"
check "no pre-commit exits 5" 5 err "pre-commit is not installed"

# A checkout from before templates/community/ existed, and before
# ruff.toml did, with a template that pins nothing.
fake_checkout
mkdir -p "${CHECKOUT}/templates/pre-commit-config"
printf 'repos: []\n' >"${CHECKOUT}/templates/pre-commit-config/recommended.yaml"
for f in .editorconfig .cspell.json .yamllint.yml .markdownlint.yaml .markdown-link-check.json checkmake.ini .lycheeignore gitignore.fragment; do
  cp "${REPO_ROOT}/templates/${f}" "${CHECKOUT}/templates/${f}"
done
new_target
run "${STUBS}" "${CHECKOUT}/scripts/install.sh" --target "${TARGET}" --community-files
check "--community-files against a checkout without them exits 3" 3 err "no templates/community/ directory"

run "${STUBS}" "${CHECKOUT}/scripts/install.sh" --target "${TARGET}"
check "a template file the checkout lacks is skipped, and a template with no pin still resolves" 0 \
  err "ruff.toml is not part of this ref" \
  out "Resolved the pre-commit-checklists pin to this library's latest release."

# --- install.sh, remote mode ------------------------------------------------

echo "=== install.sh (remote) ==="

fake_checkout
REMOTE="${CHECKOUT}/scripts/install.sh"
export STUB_TEMPLATES="${REPO_ROOT}/templates"

new_target
run "${STUBS}" "${REMOTE}" --target "${TARGET}"
check "no curl and no wget exits 6" 6 err "neither curl nor wget"

new_target
STUB_TAG=v9.9.9 run "${STUBS}:${CURL_DIR}" "${REMOTE}" --target "${TARGET}" --template python --community-files
check "curl fetches every file at the latest release" 0 \
  out "Wrote ${TARGET}/ruff.toml" \
  out "Wrote ${TARGET}/CONTRIBUTING.md" \
  log "/v9.9.9/templates/community/SECURITY.md"

new_target
RUN_IN="${TARGET}" run "${STUBS}:${CURL_DIR}" "${REMOTE}"
check "with no release, curl falls back to main, and --target defaults to here" 0 \
  err "No published release found" \
  out "Wrote ${TARGET}/.pre-commit-config.yaml" \
  log "/main/templates/pre-commit-config/recommended.yaml"

new_target
STUB_STATUS=404 STUB_STATUS_MATCH=ruff run "${STUBS}:${CURL_DIR}" "${REMOTE}" --target "${TARGET}" --ref v1.0.0
check "curl: an optional file the ref lacks is skipped" 0 err "templates/ruff.toml does not exist at ref 'v1.0.0'"

new_target
run "${STUBS}:${CURL_DIR}" "${REMOTE}" --target "${TARGET}" --ref v1.0.0 --template nope
check "curl: a template the ref lacks exits 3" 3 err "no template named 'nope' at ref 'v1.0.0'"

new_target
STUB_STATUS=500 STUB_STATUS_MATCH=editorconfig run "${STUBS}:${CURL_DIR}" "${REMOTE}" --target "${TARGET}" --ref v1.0.0
check "curl: a server error on a required file exits 7" 7 err "failed to fetch"

new_target
STUB_STATUS=429 STUB_STATUS_MATCH=checkmake run "${STUBS}:${CURL_DIR}" "${REMOTE}" --target "${TARGET}" --ref v1.0.0
check "curl: a rate limit on an optional file exits 7, not a skip" 7 err "failed to fetch"

new_target
STUB_DOWN=1 run "${STUBS}:${CURL_DIR}" "${REMOTE}" --target "${TARGET}"
check "curl: no network falls back to main, then exits 7" 7 err "No published release found" err "failed to fetch"

new_target
STUB_TAG=v9.9.9 run "${STUBS}:${WGET_DIR}" "${REMOTE}" --target "${TARGET}" --community-files
check "wget fetches every file at the latest release" 0 \
  out "Wrote ${TARGET}/SECURITY.md" \
  log "/v9.9.9/templates/.lycheeignore"

new_target
run "${STUBS}:${WGET_DIR}" "${REMOTE}" --target "${TARGET}"
check "with no release, wget falls back to main" 0 err "No published release found"

new_target
STUB_QUIET=1 run "${STUBS}:${WGET_DIR}" "${REMOTE}" --target "${TARGET}" --ref v1.0.0
check "wget: a transfer that prints no status still counts by its content" 0 out "Wrote ${TARGET}/.editorconfig"

new_target
STUB_STATUS=404 STUB_STATUS_MATCH=checkmake run "${STUBS}:${WGET_DIR}" "${REMOTE}" --target "${TARGET}" --ref v1.0.0
check "wget: an optional file the ref lacks is skipped" 0 err "templates/checkmake.ini does not exist"

new_target
STUB_STATUS=403 STUB_STATUS_MATCH=cspell run "${STUBS}:${WGET_DIR}" "${REMOTE}" --target "${TARGET}" --ref v1.0.0
check "wget: a refused required file exits 7" 7 err "failed to fetch"

new_target
STUB_DOWN=1 run "${STUBS}:${WGET_DIR}" "${REMOTE}" --target "${TARGET}" --ref v1.0.0
check "wget: no network exits 7" 7 err "failed to fetch"

echo ""
echo "${TOTAL} cases, $((TOTAL - FAILURES)) passed, ${FAILURES} failed."
[[ "${FAILURES}" -eq 0 ]]
