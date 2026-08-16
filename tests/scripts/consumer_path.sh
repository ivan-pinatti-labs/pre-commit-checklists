#!/usr/bin/env bash

: '
  Phase 5: the consumer path gate.

  The dogfood .pre-commit-config.yaml in this repo uses `repo: local`,
  and no throwaway repo has ever consumed this library the way a real
  user would: `repo: <url>` plus `rev: vX.Y.Z`, resolved through a tagged
  clone rather than a same-directory local hook. This script exercises
  that path as far as is possible before the repo is published, using a
  tagged clone under /tmp rather than the real GitHub URL.

  What this proves:
    - .pre-commit-hooks.yaml entry paths (entry: ./scripts/run-checklist.sh)
      resolve correctly when pre-commit clones the repo into its own cache
      at a pinned rev, rather than running from a checkout that happens to
      already be the current working directory (which is all `repo: local`
      or a same-directory `repo: ./` ever exercises).
    - a consumer .pre-commit-config.yaml written the way
      templates/pre-commit-config/*.yaml instruct (repo: <url>, rev: <tag>,
      selecting hook ids by name) actually finds those hook ids in the
      cloned .pre-commit-hooks.yaml and runs them successfully end to end.
    - the selector guidance in docs/hook-catalogue.md, applied by hand in a
      throwaway consumer config, produces a hook that is neither skipped
      nor mis-selected.

  What this does NOT prove:
    - that the real https://github.com/ivan-pinatti/pre-commit-checklists
      URL is reachable, authenticates correctly, or serves the same
      content pre-commit would clone (this repo is not published yet).
    - anything about GitHub release mechanics, tag signing, or the
      `gh repo create`/push flow in Sprint 6.
    - behavior over an actual network (the clone target is a local path;
      pre-commit treats it exactly like any other git remote, but no
      packets leave this machine).

  The throwaway clone and consumer repo are created under /tmp, never
  under ~/wo/personal, and are deleted at the end of the run regardless
  of outcome.
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

section "consumer path: repo: <url> + rev: <tag>, via a tagged local clone"

__clone=$(mktemp -d /tmp/pcc-consumer-lib.XXXXXX)
__consumer=$(mktemp -d /tmp/pcc-consumer-repo.XXXXXX)
__test_tag="v0.0.0-test-consumer-path"

cleanup() {
  rm -rf "${__clone}" "${__consumer}"
}
trap cleanup EXIT

# Clone the library itself (read-only from this script's point of view --
# a plain `git clone` never writes back into REPO_ROOT) and tag the clone,
# not the real repo. Tags do not travel backwards through a clone, so
# REPO_ROOT is untouched by this.
git clone --quiet "${REPO_ROOT}" "${__clone}"
git -C "${__clone}" tag "${__test_tag}"

git init -q -b main "${__consumer}"
git -C "${__consumer}" config user.email "test@example.invalid"
git -C "${__consumer}" config user.name "test"
echo "pre-commit 4.5.1" >"${__consumer}/.tool-versions"

cat >"${__consumer}/.pre-commit-config.yaml" <<EOF
---
repos:
  - repo: ${__clone}
    rev: ${__test_tag}
    hooks:
      - id: checklist-toml
        types: [toml]
      - id: checklist-dev-dotenv
        files: '(^|/)\.env(\..+)?\$'
EOF

printf 'key = "value"\n' >"${__consumer}/good.toml"
printf 'API_KEY=abc123\n' >"${__consumer}/.env"
git -C "${__consumer}" add -A -f

set +o errexit
OUT=$(cd "${__consumer}" && "${PC}" run --config .pre-commit-config.yaml --all-files --verbose 2>&1)
EXIT=$?
set -o errexit

if [ "${EXIT}" -eq 0 ] && echo "${OUT}" | grep -q "checklist-toml" && echo "${OUT}" | grep -q "checklist-dev-dotenv"; then
  pass "consumer path: repo:+rev: clone resolves .pre-commit-hooks.yaml and runs both hook ids"
else
  fail "consumer path: expected both hook ids to run successfully" "exit=${EXIT}
${OUT}"
fi

# shellcheck disable=SC2034 # read by assert_selected in tests/lib/harness.sh
HOOK_OUTPUT="${OUT}"
assert_selected "consumer path/selection"

# Negative control: a bad fixture through the same repo:+rev: path must
# still fail, proving this is not just "everything passes once cloned".
printf 'key = "value\n' >"${__consumer}/bad.toml"
git -C "${__consumer}" add -A -f
set +o errexit
OUT2=$(cd "${__consumer}" && "${PC}" run --config .pre-commit-config.yaml --all-files --verbose 2>&1)
EXIT2=$?
set -o errexit

if [ "${EXIT2}" -ne 0 ]; then
  pass "consumer path: invalid TOML through repo:+rev: still fails (not a rubber stamp)"
else
  fail "consumer path: invalid TOML through repo:+rev: should have failed" "${OUT2}"
fi

summarize
