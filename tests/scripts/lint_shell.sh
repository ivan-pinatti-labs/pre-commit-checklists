#!/usr/bin/env bash

: '
  Phase 3: shellcheck plus behavioral assertions for scripts/*.sh.

  Covers run-checklist.sh, check-branch-name.sh (including the opt-in
  --ticket-prefixes path), check-commit-msg.sh (including --ticket-prefixes)
  and install.sh, against their documented exit codes, using real scratch
  git repositories under /tmp rather than mocks.
'

set -o errexit
set -o pipefail
set -o nounset

HERE=$(dirname "$(realpath "${0}")")
REPO_ROOT=$(realpath "${HERE}/../..")
# shellcheck source=../lib/harness.sh
source "${HERE}/../lib/harness.sh"

cd "${REPO_ROOT}"

BRANCH_SCRIPT="${REPO_ROOT}/scripts/check-branch-name.sh"
MSG_SCRIPT="${REPO_ROOT}/scripts/check-commit-msg.sh"
RUN_SCRIPT="${REPO_ROOT}/scripts/run-checklist.sh"
INSTALL_SCRIPT="${REPO_ROOT}/scripts/install.sh"

run_and_capture() {
  # run_and_capture <cmd...>: sets OUT and EXIT, never aborts on nonzero.
  set +o errexit
  OUT=$("$@" 2>&1)
  EXIT=$?
  set -o errexit
}

section "shellcheck (--severity=warning, matches the shipped hook plus one notch stricter)"
if shellcheck --severity=warning "${REPO_ROOT}"/scripts/*.sh >/tmp/pcc-shellcheck.log 2>&1; then
  pass "shellcheck: scripts/*.sh clean at --severity=warning"
else
  fail "shellcheck: scripts/*.sh has warning-or-worse findings" "$(cat /tmp/pcc-shellcheck.log)"
fi
rm -f /tmp/pcc-shellcheck.log

section "check-branch-name.sh"
__scratch=$(mktemp -d /tmp/pcc-branch.XXXXXX)
git init -q -b main "${__scratch}"
git -C "${__scratch}" config user.email "test@example.invalid"
git -C "${__scratch}" config user.name "test"
echo x >"${__scratch}/f"
git -C "${__scratch}" add f

check_branch() {
  __branch="${1}"
  shift
  git -C "${__scratch}" checkout -q -B "${__branch}"
  run_and_capture bash -c "cd '${__scratch}' && '${BRANCH_SCRIPT}' $*"
}

check_branch "main"
[ "${EXIT}" -eq 0 ] && pass "check-branch-name.sh: protected branch 'main' accepted" || fail "check-branch-name.sh: 'main' should be accepted" "${OUT}"

check_branch "feature/add-thing"
[ "${EXIT}" -eq 0 ] && pass "check-branch-name.sh: ordinary slug 'feature/add-thing' accepted" || fail "check-branch-name.sh: ordinary slug should be accepted" "${OUT}"

check_branch "BadBranchName"
[ "${EXIT}" -eq 1 ] && pass "check-branch-name.sh: 'BadBranchName' rejected with exit 1" || fail "check-branch-name.sh: uppercase/no-slug branch should be rejected (exit 1)" "exit=${EXIT} ${OUT}"

check_branch "proj-123-add-thing"
[ "${EXIT}" -eq 0 ] && pass "check-branch-name.sh: ticket-shaped slug accepted with no --ticket-prefixes given" || fail "check-branch-name.sh: ticket-shaped slug should still pass as an ordinary slug" "${OUT}"

check_branch "proj-123-add-thing" --ticket-prefixes PROJ
[ "${EXIT}" -eq 0 ] && pass "check-branch-name.sh: --ticket-prefixes PROJ accepts 'proj-123-add-thing'" || fail "check-branch-name.sh: --ticket-prefixes PROJ should accept a matching ticket branch" "${OUT}"

check_branch "random-no-ticket" --ticket-prefixes PROJ
[ "${EXIT}" -eq 1 ] && pass "check-branch-name.sh: --ticket-prefixes PROJ rejects a branch with no ticket" || fail "check-branch-name.sh: --ticket-prefixes PROJ should reject a non-ticket branch (exit 1)" "exit=${EXIT} ${OUT}"

rm -rf "${__scratch}"

section "check-commit-msg.sh"
__msg_dir=$(mktemp -d /tmp/pcc-msg.XXXXXX)

write_msg() {
  echo "${2}" >"${__msg_dir}/${1}"
}

write_msg plain.txt "feat: add login page"
run_and_capture "${MSG_SCRIPT}" "${__msg_dir}/plain.txt"
[ "${EXIT}" -eq 0 ] && pass "check-commit-msg.sh: plain Conventional Commit accepted" || fail "check-commit-msg.sh: plain conventional commit should be accepted" "${OUT}"

write_msg scoped.txt "fix(auth): handle expired token"
run_and_capture "${MSG_SCRIPT}" "${__msg_dir}/scoped.txt"
[ "${EXIT}" -eq 0 ] && pass "check-commit-msg.sh: scoped Conventional Commit accepted" || fail "check-commit-msg.sh: scoped conventional commit should be accepted" "${OUT}"

write_msg bad.txt "did some stuff"
run_and_capture "${MSG_SCRIPT}" "${__msg_dir}/bad.txt"
[ "${EXIT}" -eq 1 ] && pass "check-commit-msg.sh: non-conventional message rejected with exit 1" || fail "check-commit-msg.sh: non-conventional message should be rejected (exit 1)" "exit=${EXIT} ${OUT}"

write_msg ticket.txt "feat(PROJ-123): add login page"
run_and_capture "${MSG_SCRIPT}" --ticket-prefixes PROJ "${__msg_dir}/ticket.txt"
[ "${EXIT}" -eq 0 ] && pass "check-commit-msg.sh: --ticket-prefixes PROJ accepts a matching ticket scope" || fail "check-commit-msg.sh: --ticket-prefixes PROJ should accept feat(PROJ-123): ..." "${OUT}"

run_and_capture "${MSG_SCRIPT}" --ticket-prefixes PROJ "${__msg_dir}/plain.txt"
[ "${EXIT}" -eq 1 ] && pass "check-commit-msg.sh: --ticket-prefixes PROJ rejects a message with no ticket scope" || fail "check-commit-msg.sh: --ticket-prefixes PROJ should reject a message with no ticket scope (exit 1)" "exit=${EXIT} ${OUT}"

run_and_capture "${MSG_SCRIPT}"
[ "${EXIT}" -eq 3 ] && pass "check-commit-msg.sh: missing file argument rejected with exit 3" || fail "check-commit-msg.sh: missing file argument should exit 3" "exit=${EXIT} ${OUT}"

rm -rf "${__msg_dir}"

section "run-checklist.sh"
run_and_capture "${RUN_SCRIPT}"
[ "${EXIT}" -eq 1 ] && pass "run-checklist.sh: no arguments exits 1 (usage)" || fail "run-checklist.sh: no arguments should exit 1" "exit=${EXIT} ${OUT}"

run_and_capture "${RUN_SCRIPT}" checklist-does-not-exist tests/fixtures/checklist-toml/should-pass/config.toml
[ "${EXIT}" -eq 2 ] && pass "run-checklist.sh: unknown checklist name exits 2" || fail "run-checklist.sh: unknown checklist should exit 2" "exit=${EXIT} ${OUT}"

# Defect 4: a consumer args: override on a checklist-* hook id replaces
# the baked-in checklist-name argument, so run-checklist.sh receives
# whatever the consumer put in args: (here simulated with a flag-shaped
# string) as its first argument instead. This must fail loudly, pointing
# at the actual cause, not just exit nonzero.
run_and_capture "${RUN_SCRIPT}" --some-flag tests/fixtures/checklist-toml/should-pass/config.toml
if [ "${EXIT}" -eq 2 ] && echo "${OUT}" | grep -q "docs/overrides.md" && echo "${OUT}" | grep -q "args:"; then
  pass "run-checklist.sh: an args:-shaped first argument exits 2 with a pointer to the args: hazard in docs/overrides.md"
else
  fail "run-checklist.sh: an args:-shaped first argument should exit 2 and explain the args: override hazard" "exit=${EXIT} ${OUT}"
fi

run_and_capture "${RUN_SCRIPT}" checklist-toml tests/fixtures/checklist-toml/should-pass/config.toml
[ "${EXIT}" -eq 0 ] && pass "run-checklist.sh: valid checklist against a passing fixture exits 0" || fail "run-checklist.sh: passing fixture should exit 0" "exit=${EXIT} ${OUT}"

run_and_capture "${RUN_SCRIPT}" checklist-toml tests/fixtures/checklist-toml/should-fail/config.toml
[ "${EXIT}" -ne 0 ] && pass "run-checklist.sh: valid checklist against a failing fixture exits nonzero" || fail "run-checklist.sh: failing fixture should exit nonzero" "exit=${EXIT} ${OUT}"

section "install.sh"
run_and_capture "${INSTALL_SCRIPT}"
[ "${EXIT}" -eq 1 ] && pass "install.sh: missing --target exits 1 (usage)" || fail "install.sh: missing --target should exit 1" "exit=${EXIT} ${OUT}"

run_and_capture "${INSTALL_SCRIPT}" --target /tmp/pcc-install-does-not-exist-xyz
[ "${EXIT}" -eq 2 ] && pass "install.sh: nonexistent --target exits 2" || fail "install.sh: nonexistent target directory should exit 2" "exit=${EXIT} ${OUT}"

__target=$(mktemp -d /tmp/pcc-install.XXXXXX)
run_and_capture "${INSTALL_SCRIPT}" --target "${__target}" --template does-not-exist
[ "${EXIT}" -eq 3 ] && pass "install.sh: unknown --template exits 3" || fail "install.sh: unknown template should exit 3" "exit=${EXIT} ${OUT}"
rm -rf "${__target}"

# Happy path: bootstraps a real throwaway git repo end to end. Needs
# ASDF_PRE_COMMIT_VERSION / a seeded .tool-versions since asdf resolves
# the pre-commit shim per-directory and this scratch repo has none of
# its own.
__target=$(mktemp -d /tmp/pcc-install-happy.XXXXXX)
git init -q "${__target}"
echo "pre-commit 4.5.1" >"${__target}/.tool-versions"
run_and_capture "${INSTALL_SCRIPT}" --target "${__target}" --template minimal
if [ "${EXIT}" -eq 0 ] && [ -f "${__target}/.pre-commit-config.yaml" ] && [ -f "${__target}/.secrets.baseline" ] && [ -f "${__target}/.git/hooks/pre-commit" ]; then
  pass "install.sh: happy path bootstraps .pre-commit-config.yaml, .secrets.baseline, and the git hook"
else
  fail "install.sh: happy path did not produce the expected files" "exit=${EXIT} ${OUT}"
fi

run_and_capture "${INSTALL_SCRIPT}" --target "${__target}" --template minimal
if [ "${EXIT}" -eq 0 ] && echo "${OUT}" | grep -q "already exists"; then
  pass "install.sh: re-running without --force skips existing files instead of clobbering them"
else
  fail "install.sh: re-running without --force should skip existing files and still exit 0" "exit=${EXIT} ${OUT}"
fi
rm -rf "${__target}"

summarize
