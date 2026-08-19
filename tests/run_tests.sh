#!/usr/bin/env bash

: '
  Single entry point for this library own test suite. Run from anywhere;
  it cds to the repo root itself.

  Usage:
    tests/run_tests.sh              # run everything
    tests/run_tests.sh <phase>...   # run only the named phase(s)

  Phases (also the names to pass on the command line):
    selectors:  static guard, no hook combines types/types_or with files
                (the defect-2/3 shape), across .pre-commit-hooks.yaml,
                checklists/*.yaml and templates/pre-commit-config/*.yaml
    hooks:      per-checklist fixture tests (should-pass/should-fail)
                plus the dogfood-wiring selection guard for defects 2/3
    shell:      shellcheck plus behavioral tests of scripts/*.sh
    links:      how checklist-markdown handles a .markdown-link-check.json
                (absent / matching / non-matching), in a scratch repo
    consumer:   offline repo:+rev: consumer-path test via a tagged
                local clone under /tmp
    commit:     a real `git commit` through installed hooks, covering
                the commit-msg stage that `pre-commit run --all-files`
                never exercises

  Exit status: 0 if every phase passed, 1 if any phase failed.

  CI: the one command to wire in is `tests/run_tests.sh` with no
  arguments. It requires network access (checklist hook environments,
  actionlint-docker image, npm-installed prettier) and Docker; see
  tests/README.md for what each phase needs.
'

set -o errexit
set -o pipefail
set -o nounset

HERE=$(dirname "$(realpath "${0}")")
cd "${HERE}/.."

ALL_PHASES="selectors hooks shell links consumer commit"
PHASES="${*:-${ALL_PHASES}}"

OVERALL_EXIT=0

run_phase() {
  __phase="${1}"
  __label="${2}"
  __cmd="${3}"
  echo ""
  echo "##################################################################"
  echo "# ${__label}"
  echo "##################################################################"
  if ! bash -c "${__cmd}"; then
    OVERALL_EXIT=1
    echo ">>> phase '${__phase}' FAILED"
  else
    echo ">>> phase '${__phase}' passed"
  fi
}

for phase in ${PHASES}; do
  case "${phase}" in
  selectors)
    run_phase selectors "Phase: selector lint (static AND-selector guard)" "python3 tests/scripts/test_selector_lint.py"
    ;;
  hooks)
    run_phase hooks "Phase: checklist fixtures + dogfood-wiring guard" "tests/scripts/check_hooks.sh"
    ;;
  shell)
    run_phase shell "Phase: shellcheck + scripts/*.sh behavior" "tests/scripts/lint_shell.sh"
    ;;
  links)
    run_phase links "Phase: markdown-link-check config handling" "tests/scripts/markdown_link_config.sh"
    ;;
  consumer)
    run_phase consumer "Phase: consumer path (repo: + rev:, offline)" "tests/scripts/consumer_path.sh"
    ;;
  commit)
    run_phase commit "Phase: real git commit (commit-msg stage)" "tests/scripts/real_commit.sh"
    ;;
  *)
    echo "Unknown phase: ${phase}" >&2
    echo "Known phases: ${ALL_PHASES}" >&2
    OVERALL_EXIT=1
    ;;
  esac
done

echo ""
if [ "${OVERALL_EXIT}" -eq 0 ]; then
  echo "All phases passed."
else
  echo "One or more phases failed. See output above."
fi

exit "${OVERALL_EXIT}"
