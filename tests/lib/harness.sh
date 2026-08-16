#!/usr/bin/env bash

: '
  Shared helpers for the scripts under tests/scripts/. Sourced, not
  executed directly.

  Provides:
    - resolve_pre_commit(): finds a working `pre-commit` binary even when
      asdf has not activated one for the current directory (relevant for
      throwaway repos under /tmp).
    - run_hook(): invokes `pre-commit run` for one hook id/config against a
      set of files and captures output + exit code without letting
      `set -e` abort the caller.
    - assert_selected(): fails if the hook was silently skipped ("no files
      to check") when files were actually given to it. This is the check
      that stops defects 2 and 3 from recurring unnoticed: a hook that
      matches zero files still exits 0, so exit-code-only assertions pass
      against that bug. This helper is what would have caught it.
    - assert_exit(): compares an actual exit code against an expected one.
    - pass()/fail()/section(): reporting + counters.
    - on_exit_restore(): restores any fixture files a "fixer" hook
      (end-of-file-fixer, prettier, ruff --fix, ...) modified in place, so
      re-running the suite against the same working tree stays
      deterministic. Fixtures are git-tracked, so `git checkout --` puts
      them back to the committed "bad"/"good" content.
'

TESTS_TOTAL=0
TESTS_FAILED=0
FAILED_NAMES=()

resolve_pre_commit() {
  if [ -n "${PRE_COMMIT_BIN:-}" ] && command -v "${PRE_COMMIT_BIN}" >/dev/null 2>&1; then
    echo "${PRE_COMMIT_BIN}"
    return 0
  fi
  if command -v pre-commit >/dev/null 2>&1; then
    echo "pre-commit"
    return 0
  fi
  # asdf shims resolve per-directory via .tool-versions; fall back to the
  # installed version directly so tests can run from a throwaway /tmp repo
  # that has no .tool-versions of its own.
  if command -v asdf >/dev/null 2>&1; then
    __v=$(asdf list pre-commit 2>/dev/null | tr -d ' *' | tail -n1)
    if [ -n "${__v}" ]; then
      __bin="${HOME}/.asdf/installs/pre-commit/${__v}/bin/pre-commit"
      if [ -x "${__bin}" ]; then
        echo "${__bin}"
        return 0
      fi
    fi
  fi
  echo "Error: no working pre-commit binary found." >&2
  return 1
}

section() {
  echo ""
  echo "=== ${1} ==="
}

pass() {
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  echo "  ok  : ${1}"
}

fail() {
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILED_NAMES+=("${1}")
  echo "  FAIL: ${1}"
  if [ -n "${2:-}" ]; then
    echo "${2}" | sed 's/^/         /'
  fi
}

# run_hook <pre-commit-bin> <config-file> <hook-id-or-empty> <file>...
# Sets globals: HOOK_OUTPUT, HOOK_EXIT
run_hook() {
  __pc="${1}"
  __config="${2}"
  __hook_id="${3}"
  shift 3
  # A should-fail fixture is *expected* to make pre-commit exit nonzero, so
  # errexit must be off for the duration of this call or the caller's
  # script would abort on the first expected failure.
  set +o errexit
  if [ -n "${__hook_id}" ]; then
    HOOK_OUTPUT=$("${__pc}" run --config "${__config}" "${__hook_id}" --hook-stage pre-commit --files "$@" --verbose 2>&1)
  else
    HOOK_OUTPUT=$("${__pc}" run --config "${__config}" --files "$@" --verbose 2>&1)
  fi
  # shellcheck disable=SC2034 # read by callers after run_hook returns
  HOOK_EXIT=$?
  set -o errexit
  return 0
}

# assert_exit <name> <expected: pass|fail> <actual-exit-code>
assert_exit() {
  __name="${1}"
  __expect="${2}"
  __exit="${3}"
  if [ "${__expect}" = "pass" ]; then
    if [ "${__exit}" -eq 0 ]; then
      pass "${__name}: exit 0 as expected"
    else
      fail "${__name}: expected exit 0, got ${__exit}" "${HOOK_OUTPUT}"
    fi
  else
    if [ "${__exit}" -ne 0 ]; then
      pass "${__name}: nonzero exit as expected (${__exit})"
    else
      fail "${__name}: expected a nonzero exit, got 0" "${HOOK_OUTPUT}"
    fi
  fi
}

# assert_selected <name>
# Fails only if EVERY hook in the run reported "(no files to check)" i.e.
# the whole checklist's selector matched none of the files it was given.
# This is the guard against defects 2 and 3: a hook that silently matches
# nothing still reports exit 0, so this check does not rely on the exit
# code at all. A checklist with several sub-hooks (e.g. checklist-basic)
# legitimately has *some* sub-hooks skip a given file type while others
# run, and that is normal and must not be flagged. Only "every sub-hook
# skipped" means the outer selector itself never let the file through.
assert_selected() {
  __name="${1}"
  __total=$(echo "${HOOK_OUTPUT}" | grep -cE '\.{3,}(Passed|Failed|\(no files to check\)Skipped)$' || true)
  __skipped=$(echo "${HOOK_OUTPUT}" | grep -cE '\.{3,}\(no files to check\)Skipped$' || true)
  if [ "${__total}" -gt 0 ] && [ "${__total}" -eq "${__skipped}" ]; then
    fail "${__name}: every hook reported (no files to check); the selector did not match the fixture, this is the defect-2/3 shape" "${HOOK_OUTPUT}"
  else
    pass "${__name}: hook selected the fixture file(s) (not skipped)"
  fi
}

# restore_fixtures <path>...
# Reset git-tracked fixture files back to their committed content after a
# "fixer" hook (end-of-file-fixer, prettier, ruff-format, ...) modifies
# them in place, so the suite is idempotent across repeated runs.
restore_fixtures() {
  git -C "${REPO_ROOT}" checkout --quiet -- "$@" 2>/dev/null || true
}

summarize() {
  echo ""
  echo "=== Summary ==="
  echo "${TESTS_TOTAL} assertions, $((TESTS_TOTAL - TESTS_FAILED)) passed, ${TESTS_FAILED} failed."
  if [ "${TESTS_FAILED}" -gt 0 ]; then
    echo "Failed:"
    for n in "${FAILED_NAMES[@]}"; do
      echo "  - ${n}"
    done
    return 1
  fi
  return 0
}
