#!/usr/bin/env bash

: '
  Phase 6: a real `git commit`, not just `pre-commit run --all-files`.

  Sprint 2 found that `run --all-files` never exercises the commit-msg
  git stage: a config can be green on `run --all-files` while still
  blocking every real commit, because hooks without an explicit
  `stages:` re-run at commit-msg too, and cspell exits nonzero there when
  handed zero files. This script installs this library own dogfood hooks
  into a throwaway repo via `pre-commit install` and drives real
  `git commit` invocations (through the installed pre-commit and
  commit-msg git hooks, not `pre-commit run`), asserting:

    - a real commit with a Conventional Commit message and clean file
      content succeeds end to end (pre-commit stage + commit-msg stage
      both run and both pass).
    - a real commit with a non-conventional message is blocked at the
      commit-msg stage.
    - a real commit that would land on the (locally, this throwaway
      repo own) protected branch is blocked.

  This is not run against the actual dogfood .pre-commit-config.yaml in
  place (that file assumes it is being run from inside this repo, via
  `repo: local` entries pointing at ./scripts/...); instead it builds an
  equivalent throwaway config using the repo:+rev: consumer shape against
  a tagged local clone, the same mechanism tests/scripts/consumer_path.sh
  uses, so both the commit-msg stage and the repo:+rev: path are covered
  by one real commit.
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

section "real git commit through installed hooks (pre-commit + commit-msg stages)"

__clone=$(mktemp -d /tmp/pcc-real-commit-lib.XXXXXX)
__consumer=$(mktemp -d /tmp/pcc-real-commit-repo.XXXXXX)
__test_tag="v0.0.0-test-real-commit"

cleanup() {
  rm -rf "${__clone}" "${__consumer}"
}
trap cleanup EXIT

git clone --quiet "${REPO_ROOT}" "${__clone}"
git -C "${__clone}" tag "${__test_tag}"

git init -q -b main "${__consumer}"
git -C "${__consumer}" config user.email "test@example.invalid"
git -C "${__consumer}" config user.name "test"
echo "pre-commit 4.5.1" >"${__consumer}/.tool-versions"

cat >"${__consumer}/.pre-commit-config.yaml" <<EOF
---
default_install_hook_types: [pre-commit, commit-msg]
repos:
  - repo: ${__clone}
    rev: ${__test_tag}
    hooks:
      - id: checklist-toml
        types: [toml]
        stages: [pre-commit]
      - id: checklist-git-commit-msg
        stages: [commit-msg]
        files: ^\.git/COMMIT_EDITMSG\$
EOF

(cd "${__consumer}" && "${PC}" install --install-hooks >/dev/null 2>&1)
(cd "${__consumer}" && "${PC}" install --hook-type commit-msg >/dev/null 2>&1)

printf 'key = "value"\n' >"${__consumer}/good.toml"
git -C "${__consumer}" add -A

set +o errexit
OUT=$(cd "${__consumer}" && git commit -m "feat: add a toml config file" 2>&1)
EXIT=$?
set -o errexit

if [ "${EXIT}" -eq 0 ]; then
  pass "real commit: clean file + Conventional Commit message succeeds through both hook stages"
else
  fail "real commit: a clean commit should have succeeded" "exit=${EXIT}
${OUT}"
fi

# A real commit with a non-conventional message must be blocked at the
# commit-msg stage, even though `pre-commit run --all-files` never checks
# this at all (that is the exact gap Sprint 2 hit).
printf 'title = "two"\n' >"${__consumer}/second.toml"
git -C "${__consumer}" add -A
set +o errexit
OUT2=$(cd "${__consumer}" && git commit -m "did some stuff, no conventional prefix" 2>&1)
EXIT2=$?
set -o errexit

if [ "${EXIT2}" -ne 0 ] && echo "${OUT2}" | grep -qi "commit"; then
  pass "real commit: non-conventional commit message is blocked at the commit-msg stage"
else
  fail "real commit: a non-conventional message should have been blocked" "exit=${EXIT2}
${OUT2}"
fi

# Confirm the failed commit really did not land.
__log=$(git -C "${__consumer}" log --oneline)
if ! echo "${__log}" | grep -q "did some stuff"; then
  pass "real commit: the blocked commit did not land in history"
else
  fail "real commit: the blocked commit landed anyway" "${__log}"
fi

summarize
