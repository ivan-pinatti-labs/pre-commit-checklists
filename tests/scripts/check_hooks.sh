#!/usr/bin/env bash

: '
  Phase 1 + Phase 2: per-checklist fixture tests.

  For every hook id that has fixtures under tests/fixtures/<id>/, this:

    Phase 1: runs checklists/<id>.yaml (the same config
    scripts/run-checklist.sh dispatches to) against the should-pass
    fixtures, expecting exit 0, and against the should-fail fixtures,
    expecting a nonzero exit. Both runs also assert the hook actually
    selected the fixture file(s) rather than silently matching nothing
    ("(no files to check)"), which is the shape of defects 2 and 3.

    Phase 2: for hook ids wired into this library own dogfood
    .pre-commit-config.yaml with a file-based selector, re-runs the
    should-pass fixtures through THAT config (not the checklist file
    directly) via pre-commit run <hook-id> --config .pre-commit-config.yaml,
    asserting the hook is not skipped there either. This is the layer
    where defects 2 and 3 actually lived: a correct checklist file wired
    up with a bad types/files selector on the consumer side still
    "passes" pre-commit, because a hook matching zero files exits 0.

  checklist-github-actions is a special case: actionlint-docker own hook
  manifest anchors files to ^\.github/workflows/ at the repo root, so
  a fixture under tests/fixtures/ can never match it there, and this repo
  real .github/workflows/ is out of scope for tests/ to write into (owned
  by a part of the build that has not landed). Phase 1 for this one hook
  therefore runs against tests/config/checklist-github-actions.override.yaml
  instead, which points the same pinned actionlint-docker hook at any
  YAML file. Phase 2 (dogfood wiring) is skipped for this hook and reported
  as a known gap; see tests/README.md.

  checklist-git-valid-branches, checklist-git-commit-msg and
  checklist-git-protected-branches are not file-content hooks (branch name
  / commit message / current branch, not file contents) and have no
  fixtures here by design; they are covered by tests/scripts/lint_shell.sh
  (the first two) and the protected-branch check in this script (the
  third, via a scratch repo on different branch names, not file fixtures).

  Exit status: 0 if every assertion passed, 1 otherwise.
'

set -o errexit
set -o pipefail
set -o nounset

HERE=$(dirname "$(realpath "${0}")")
REPO_ROOT=$(realpath "${HERE}/../..")
# shellcheck source=../lib/harness.sh
source "${HERE}/../lib/harness.sh"

cd "${REPO_ROOT}"

PC=$(resolve_pre_commit)

# Hook ids wired into the dogfood .pre-commit-config.yaml with a
# file-based selector (i.e. not always_run / not commit-msg-stage-only).
# Kept in sync by hand with .pre-commit-config.yaml; if you add a checklist
# to that file, add its id here too so Phase 2 covers it.
DOGFOOD_WIRED="checklist-basic checklist-spell checklist-json checklist-markdown checklist-toml checklist-xml checklist-yaml checklist-security-credentials checklist-dev-dotenv checklist-dev-editorconfig checklist-dev-shell checklist-dev-python checklist-dev-terraform checklist-dev-javascript checklist-dev-typescript"

is_dogfood_wired() {
  case " ${DOGFOOD_WIRED} " in
  *" ${1} "*) return 0 ;;
  *) return 1 ;;
  esac
}

# test_checklist <hook-id> [config-file]
test_checklist() {
  __id="${1}"
  __config="${2:-checklists/${__id}.yaml}"
  __fix_dir="tests/fixtures/${__id}"

  if [ ! -d "${__fix_dir}" ]; then
    fail "${__id}: no fixtures directory at ${__fix_dir}"
    return
  fi

  section "${__id}"

  for __kind in should-pass should-fail; do
    __dir="${__fix_dir}/${__kind}"
    if [ ! -d "${__dir}" ]; then
      fail "${__id}/${__kind}: missing fixture directory"
      continue
    fi
    mapfile -t __files < <(find "${__dir}" -type f | sort)
    if [ "${#__files[@]}" -eq 0 ]; then
      fail "${__id}/${__kind}: no fixture files found"
      continue
    fi

    run_hook "${PC}" "${__config}" "" "${__files[@]}"
    __exit="${HOOK_EXIT}"
    __output="${HOOK_OUTPUT}"

    HOOK_OUTPUT="${__output}"
    assert_selected "${__id}/${__kind}"

    HOOK_OUTPUT="${__output}"
    if [ "${__kind}" = "should-pass" ]; then
      assert_exit "${__id}/${__kind}" pass "${__exit}"
    else
      assert_exit "${__id}/${__kind}" fail "${__exit}"
    fi

    restore_fixtures "${__files[@]}"
  done

  # Phase 2: dogfood wiring guard (defects 2/3 shape). Should-pass fixtures
  # only; the point is purely "was the hook selected", not re-testing
  # tool behavior a second time.
  if is_dogfood_wired "${__id}"; then
    __dir="${__fix_dir}/should-pass"
    mapfile -t __files < <(find "${__dir}" -type f | sort)
    if [ "${#__files[@]}" -gt 0 ]; then
      run_hook "${PC}" ".pre-commit-config.yaml" "${__id}" "${__files[@]}"
      HOOK_OUTPUT="${HOOK_OUTPUT}"
      assert_selected "${__id}/dogfood-wiring"
      restore_fixtures "${__files[@]}"
    fi
  else
    echo "  (skip dogfood-wiring check for ${__id}: not file-selector-based, or a known gap, see tests/README.md)"
  fi
}

test_protected_branches() {
  section "checklist-git-protected-branches (branch-state, not file-content)"
  __scratch=$(mktemp -d /tmp/pcc-protected.XXXXXX)
  git init -q -b main "${__scratch}"
  git -C "${__scratch}" config user.email "test@example.invalid"
  git -C "${__scratch}" config user.name "test"
  echo "pre-commit ${PC_VERSION:-4.5.1}" >"${__scratch}/.tool-versions" 2>/dev/null || true
  echo "hello" >"${__scratch}/f.txt"
  git -C "${__scratch}" add -A

  __config="${REPO_ROOT}/checklists/checklist-git-protected-branches.yaml"

  set +o errexit
  (cd "${__scratch}" && "${PC}" run --config "${__config}" --files f.txt --verbose) >/tmp/pcc-protected-main.log 2>&1
  __exit_main=$?
  set -o errexit
  if [ "${__exit_main}" -ne 0 ]; then
    pass "checklist-git-protected-branches/on-main: blocked as expected"
  else
    fail "checklist-git-protected-branches/on-main: expected a block, got exit 0" "$(cat /tmp/pcc-protected-main.log)"
  fi

  git -C "${__scratch}" checkout -q -b feature/allowed-change
  set +o errexit
  (cd "${__scratch}" && "${PC}" run --config "${__config}" --files f.txt --verbose) >/tmp/pcc-protected-feature.log 2>&1
  __exit_feature=$?
  set -o errexit
  if [ "${__exit_feature}" -eq 0 ]; then
    pass "checklist-git-protected-branches/on-feature-branch: allowed as expected"
  else
    fail "checklist-git-protected-branches/on-feature-branch: expected exit 0" "$(cat /tmp/pcc-protected-feature.log)"
  fi

  rm -f /tmp/pcc-protected-main.log /tmp/pcc-protected-feature.log
  rm -rf "${__scratch}"
}

for id in checklist-basic checklist-spell checklist-markdown checklist-json checklist-toml checklist-xml checklist-yaml checklist-security-credentials checklist-dev-dotenv checklist-dev-editorconfig checklist-dev-shell checklist-dev-python checklist-dev-terraform checklist-dev-javascript checklist-dev-typescript; do
  test_checklist "${id}"
done

test_checklist "checklist-github-actions" "tests/config/checklist-github-actions.override.yaml"

test_protected_branches

summarize
