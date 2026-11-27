#!/usr/bin/env bash

# cspell:words zizmor

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
  manifest anchors files to ^\.github/workflows/ at the repo root, and the
  zizmor local hook in the same checklist file anchors its own files to
  ^\.github/workflows/.*\.ya?ml$ for the identical reason, so a fixture
  under tests/fixtures/ can never match either hook there. Phase 1 for
  this one hook therefore runs against
  tests/config/checklist-github-actions.override.yaml instead, which
  re-points both pinned hooks at any YAML file. Phase 2 (dogfood wiring,
  against this repo own real .github/workflows/) is handled separately by
  test_github_actions_dogfood_wiring below, against real files rather
  than fixtures, since a fixture cannot satisfy either hook own real
  selector; see tests/README.md.

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
DOGFOOD_WIRED="checklist-basic checklist-spell checklist-json checklist-markdown checklist-toml checklist-xml checklist-yaml checklist-security-credentials checklist-dev-dotenv checklist-dev-editorconfig checklist-dev-shell checklist-dev-python checklist-dev-terraform checklist-dev-tofu checklist-dev-javascript checklist-dev-typescript checklist-dev-docker checklist-dev-make checklist-dev-cpp"

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

  if [[ ! -d "${__fix_dir}" ]]; then
    fail "${__id}: no fixtures directory at ${__fix_dir}"
    return
  fi

  section "${__id}"

  for __kind in should-pass should-fail; do
    __dir="${__fix_dir}/${__kind}"
    if [[ ! -d "${__dir}" ]]; then
      fail "${__id}/${__kind}: missing fixture directory"
      continue
    fi
    mapfile -t __files < <(find "${__dir}" -type f | sort)
    if [[ "${#__files[@]}" -eq 0 ]]; then
      fail "${__id}/${__kind}: no fixture files found"
      continue
    fi

    run_hook "${PC}" "${__config}" "" "${__files[@]}"
    __exit="${HOOK_EXIT}"
    __output="${HOOK_OUTPUT}"

    HOOK_OUTPUT="${__output}"
    assert_selected "${__id}/${__kind}"

    HOOK_OUTPUT="${__output}"
    if [[ "${__kind}" = "should-pass" ]]; then
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
    if [[ "${#__files[@]}" -gt 0 ]]; then
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
  echo "hello" >"${__scratch}/f.txt"
  git -C "${__scratch}" add -A

  __config="${REPO_ROOT}/checklists/checklist-git-protected-branches.yaml"

  set +o errexit
  (cd "${__scratch}" && "${PC}" run --config "${__config}" --files f.txt --verbose) >/tmp/pcc-protected-main.log 2>&1
  __exit_main=$?
  set -o errexit
  if [[ "${__exit_main}" -ne 0 ]]; then
    pass "checklist-git-protected-branches/on-main: blocked as expected"
  else
    fail "checklist-git-protected-branches/on-main: expected a block, got exit 0" "$(cat /tmp/pcc-protected-main.log)"
  fi

  git -C "${__scratch}" checkout -q -b feature/allowed-change
  set +o errexit
  (cd "${__scratch}" && "${PC}" run --config "${__config}" --files f.txt --verbose) >/tmp/pcc-protected-feature.log 2>&1
  __exit_feature=$?
  set -o errexit
  if [[ "${__exit_feature}" -eq 0 ]]; then
    pass "checklist-git-protected-branches/on-feature-branch: allowed as expected"
  else
    fail "checklist-git-protected-branches/on-feature-branch: expected exit 0" "$(cat /tmp/pcc-protected-feature.log)"
  fi

  rm -f /tmp/pcc-protected-main.log /tmp/pcc-protected-feature.log
  rm -rf "${__scratch}"
}

# checklist-github-actions dogfood-wiring, against this repo's own real
# .github/workflows/*.yml. actionlint-docker's own hook manifest anchors
# `files:` to ^\.github/workflows/ at the repo root, which a fixture
# under tests/fixtures/ can never satisfy (see the module docstring above
# and tests/README.md); this repo's real workflow files can. Only the
# selector wiring is asserted here (the hook was not skipped), not the
# workflow files' own lint cleanliness: those files are owned by a
# different part of this build and their content is out of scope for
# tests/ to gate on. Skips gracefully if no workflow exists yet.
test_github_actions_dogfood_wiring() {
  section "checklist-github-actions (dogfood wiring, real .github/workflows)"
  mapfile -t __wf_files < <(find "${REPO_ROOT}/.github/workflows" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | sort)
  if [[ "${#__wf_files[@]}" -eq 0 ]]; then
    echo "  (skip: no .github/workflows/*.yml in this repo yet)"
    return
  fi
  __rel_files=()
  for __f in "${__wf_files[@]}"; do
    __rel_files+=("${__f#"${REPO_ROOT}"/}")
  done
  run_hook "${PC}" ".pre-commit-config.yaml" "checklist-github-actions" "${__rel_files[@]}"
  HOOK_OUTPUT="${HOOK_OUTPUT}"
  assert_selected "checklist-github-actions/dogfood-wiring"
}

# The flake8-bandit floor in checklist-dev-python is the whole reason that
# checklist carries args at all, and a should-fail fixture alone cannot prove
# it: the fixtures directory already fails for an unrelated reason (a leftover
# pdb call), so the suite would stay green if --extend-select S were deleted
# tomorrow. This asserts the rule by name against the one fixture that is
# clean under ruff's own defaults.
test_python_security_floor() {
  section "checklist-dev-python: flake8-bandit floor"

  __fixture="tests/fixtures/checklist-dev-python/should-fail/insecure_sample.py"
  if [[ ! -f "${__fixture}" ]]; then
    fail "python security floor: fixture missing at ${__fixture}"
    return
  fi

  __asserting="tests/fixtures/checklist-dev-python/should-pass/test_asserting.py"
  if [[ ! -f "${__asserting}" ]]; then
    fail "python security floor: fixture missing at ${__asserting}"
    return
  fi

  # Both fixtures in one invocation. The S101 half needs a file that actually
  # contains an assert: insecure_sample.py has none, so on its own the "no
  # S101" assertion passes whether or not the exemption is configured, which
  # is a test that cannot fail and therefore proves nothing.
  run_hook "${PC}" "checklists/checklist-dev-python.yaml" "" "${__fixture}" "${__asserting}"
  __out="${HOOK_OUTPUT}"
  restore_fixtures "${__fixture}" "${__asserting}"

  if printf '%s' "${__out}" | grep -q "S602"; then
    pass "python security floor: S602 reported, so --extend-select S is live"
  else
    fail "python security floor: no S602 in output; the security rules are not running" "${__out}"
  fi

  if printf '%s' "${__out}" | grep -q "S101"; then
    fail "python security floor: S101 reported against a test path; the per-file ignore is not applied" "${__out}"
  else
    pass "python security floor: assert-bearing test file is exempt from S101"
  fi
}

# checklist-dev-cpp passes --check-level=exhaustive only to a cppcheck whose
# --help lists the flag (2.11 and later; 2.10 rejects it). No fixture can
# guard this against the real cppcheck in this suite's image: 2.19 takes the
# flag but no longer prints the note that makes it matter. So a stub on PATH
# plays both kinds of cppcheck and records the arguments the hook's entry
# hands it, through the real checklist file and the real pre-commit.
test_cpp_check_level() {
  section "checklist-dev-cpp: --check-level only where cppcheck has it"
  __stub=$(mktemp -d /tmp/pcc-cppcheck.XXXXXX)
  cat >"${__stub}/cppcheck" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" = --help ]]; then
  if [[ "${STUB_HAS_CHECK_LEVEL}" = 1 ]]; then echo "    --check-level=<level>"; fi
  exit 0
fi
printf '%s\n' "$@" >"${STUB_ARGS}"
STUB
  chmod +x "${__stub}/cppcheck"

  for __has in 1 0; do
    rm -f "${__stub}/args"
    set +o errexit
    __out=$(PATH="${__stub}:${PATH}" STUB_HAS_CHECK_LEVEL="${__has}" STUB_ARGS="${__stub}/args" "${PC}" run --config checklists/checklist-dev-cpp.yaml cppcheck-cpp --files tests/fixtures/checklist-dev-cpp/should-pass/greeter.cpp 2>&1)
    set -o errexit
    __name="checklist-dev-cpp/check-level (cppcheck --help lists it: ${__has})"
    if [[ ! -f "${__stub}/args" ]]; then
      fail "${__name}: the stub cppcheck was never called" "${__out}"
      continue
    fi
    if grep -qx -- '--check-level=exhaustive' "${__stub}/args"; then __got=1; else __got=0; fi
    if [[ "${__got}" = "${__has}" ]]; then
      pass "${__name}: --check-level=exhaustive passed: ${__got}"
    else
      fail "${__name}: --check-level=exhaustive passed: ${__got}, expected ${__has}" "$(cat "${__stub}/args")"
    fi
  done
  rm -rf "${__stub}"
}

# checklist-dev-cpp checks every .h as C++ unless .cppcheck-c-headers exists
# at the repo root, which routes them to the C hook instead. Real cppcheck,
# three cases: without the marker a bug in a .h is reported by the C++ hook
# alone; with it, a header that is valid C but not C++ passes with the C hook
# running, and the same bug is reported by the C hook alone. The headers are
# written at run time, outside tests/fixtures/, because the dogfood config
# runs the default configuration over committed files.
test_cpp_c_headers() {
  section "checklist-dev-cpp: .cppcheck-c-headers checks .h as C"
  __dir=$(mktemp -d "${REPO_ROOT}/tests/.cpp-c-headers.XXXXXX")
  printf 'struct namespace {\n  int x;\n};\n' >"${__dir}/c_only.h"
  printf 'static int last(void) {\n  int v[4] = {1, 2, 3, 4};\n  return v[4];\n}\n' >"${__dir}/c_bug.h"
  __cfg="checklists/checklist-dev-cpp.yaml"

  # A checkout of a consumer, or a developer trying the switch, may already
  # have its own marker: set it aside and put it back at the end.
  if [[ -e .cppcheck-c-headers ]]; then mv .cppcheck-c-headers "${__dir}/marker.orig"; fi
  # Routing, not parser behaviour: whether C++ mode rejects c_only.h depends
  # on the cppcheck release (2.19 does, 2.13 does not), but an out of bounds
  # read is reported by all of them, so which hook fails says where the .h went.
  run_hook "${PC}" "${__cfg}" "" "${__dir}/c_bug.h"
  if [[ "${HOOK_EXIT}" -ne 0 ]] && printf '%s' "${HOOK_OUTPUT}" | grep -q arrayIndexOutOfBounds &&
    printf '%s' "${HOOK_OUTPUT}" | grep -qE '^cppcheck \(C\+\+\)\.+Failed$' &&
    printf '%s' "${HOOK_OUTPUT}" | grep -qE '^cppcheck \(C\)\.+Passed$'; then
    pass "c-headers/no marker: a .h is checked by cppcheck-cpp, not cppcheck-c (the default)"
  else
    fail "c-headers/no marker: expected arrayIndexOutOfBounds from cppcheck-cpp only (exit ${HOOK_EXIT})" "${HOOK_OUTPUT}"
  fi

  : >.cppcheck-c-headers
  run_hook "${PC}" "${__cfg}" "" "${__dir}/c_only.h"
  if [[ "${HOOK_EXIT}" -eq 0 ]] && printf '%s' "${HOOK_OUTPUT}" | grep -qE '^cppcheck \(C\)\.+Passed$'; then
    pass "c-headers/marker: the C only .h passes, checked by cppcheck-c"
  else
    fail "c-headers/marker: expected exit 0 with cppcheck (C) Passed (exit ${HOOK_EXIT})" "${HOOK_OUTPUT}"
  fi

  run_hook "${PC}" "${__cfg}" "" "${__dir}/c_bug.h"
  # The C++ hook would report this bug too, so the C hook has to be the one
  # that failed and the C++ hook the one that dropped the file and passed.
  if [[ "${HOOK_EXIT}" -ne 0 ]] && printf '%s' "${HOOK_OUTPUT}" | grep -q arrayIndexOutOfBounds &&
    printf '%s' "${HOOK_OUTPUT}" | grep -qE '^cppcheck \(C\)\.+Failed$' &&
    printf '%s' "${HOOK_OUTPUT}" | grep -qE '^cppcheck \(C\+\+\)\.+Passed$'; then
    pass "c-headers/marker: a bug in a C .h is reported by cppcheck-c, not cppcheck-cpp"
  else
    fail "c-headers/marker: expected arrayIndexOutOfBounds from cppcheck-c only (exit ${HOOK_EXIT})" "${HOOK_OUTPUT}"
  fi

  rm -f .cppcheck-c-headers
  if [[ -e "${__dir}/marker.orig" ]]; then mv "${__dir}/marker.orig" .cppcheck-c-headers; fi
  rm -rf "${__dir}"
}

for id in checklist-basic checklist-spell checklist-markdown checklist-json checklist-toml checklist-xml checklist-yaml checklist-security-credentials checklist-dev-dotenv checklist-dev-editorconfig checklist-dev-shell checklist-dev-python checklist-dev-terraform checklist-dev-tofu checklist-dev-javascript checklist-dev-typescript checklist-dev-docker checklist-dev-make checklist-dev-cpp; do
  test_checklist "${id}"
done

test_checklist "checklist-github-actions" "tests/config/checklist-github-actions.override.yaml"

test_github_actions_dogfood_wiring

test_python_security_floor

test_cpp_check_level

test_cpp_c_headers

test_protected_branches

summarize
