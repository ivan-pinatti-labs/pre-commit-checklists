#!/usr/bin/env bash

: '
  Phase: markdown-link-check config handling.

  checklists/checklist-markdown.yaml wraps markdown-link-check in a
  repo: local hook that passes --config .markdown-link-check.json only
  when that file exists. Two things make that wrapper necessary, and both
  are asserted here rather than trusted:

    - markdown-link-check does NOT auto-discover .markdown-link-check.json.
      Left to itself it ignores the file entirely, which is what
      docs/overrides.md used to promise it did not.
    - --config pointed at a missing path is a hard error
      ("ERROR: Config file not accessible.", exit 1) before any link is
      checked, so the flag cannot simply be added unconditionally without
      breaking every consumer who has no such file.

  Three cases, in a scratch repo under /tmp so the library own root config
  is never involved:

    A. no config file        -> the dead link fails the hook (the
                                behaviour every existing consumer has today,
                                which this change must not alter)
    B. config ignores it     -> passes
    C. config present, but its pattern does not match -> still fails, so a
                                config file is not a blanket rubber stamp

  The link used is a real one that is permanently dead in a useful way:
  GitHub answers 404 on /stargazers for a repository with zero stars.

  Needs network access (it resolves real URLs) and Node, same as the
  hooks phase.

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

section "markdown-link-check: .markdown-link-check.json handling"

__scratch=$(mktemp -d /tmp/pcc-mlc.XXXXXX)

cleanup() {
  rm -rf "${__scratch}"
}
trap cleanup EXIT

git init -q -b main "${__scratch}"
git -C "${__scratch}" config user.email "test@example.invalid"
git -C "${__scratch}" config user.name "test"
cp "${REPO_ROOT}/.tool-versions" "${__scratch}/.tool-versions"
cp "${REPO_ROOT}/checklists/checklist-markdown.yaml" "${__scratch}/cfg.yaml"
cp "${REPO_ROOT}/templates/.markdownlint.yaml" "${__scratch}/.markdownlint.yaml"

# GitHub returns 404 for /stargazers on a repo with zero stars.
__dead_link="https://github.com/ivan-pinatti/rsync-crypt/stargazers"
printf '# Title\n\nSome prose here.\n\n[stars](%s)\n' "${__dead_link}" \
  >"${__scratch}/doc.md"
git -C "${__scratch}" add -A -f

# Runs the checklist against doc.md and returns pre-commit's own exit
# status. Deliberately does NOT toggle errexit itself: `set -o errexit` as
# the last statement in a function makes the function always return 0, which
# silently turned two of the three assertions below into no-ops. The callers
# wrap the command substitution instead.
run_case() {
  (cd "${__scratch}" && "${PC}" run --config cfg.yaml --files doc.md 2>&1)
}

# --- A. no config file: unchanged behaviour for every existing consumer ---
set +o errexit
OUT_A=$(run_case)
EXIT_A=$?
set -o errexit

if [ "${EXIT_A}" -ne 0 ] && echo "${OUT_A}" | grep -q "dead link"; then
  pass "markdown-link-check: no config file, a dead link still fails the hook"
else
  fail "markdown-link-check: expected a dead link to fail with no config present" "exit=${EXIT_A}
${OUT_A}"
fi

# --- B. config whose pattern matches: the link is ignored ---
cat >"${__scratch}/.markdown-link-check.json" <<'EOF'
{
  "ignorePatterns": [{ "pattern": "^https://github\\.com/[^/]+/[^/]+/stargazers/?$" }]
}
EOF
git -C "${__scratch}" add -A -f

set +o errexit
OUT_B=$(run_case)
EXIT_B=$?
set -o errexit

if [ "${EXIT_B}" -eq 0 ]; then
  pass "markdown-link-check: .markdown-link-check.json is read, matching link ignored"
else
  fail "markdown-link-check: config with a matching ignorePattern should have passed" "exit=${EXIT_B}
${OUT_B}"
fi

# --- C. config present but not matching: still fails, not a rubber stamp ---
cat >"${__scratch}/.markdown-link-check.json" <<'EOF'
{
  "ignorePatterns": [{ "pattern": "^https?://example\\.invalid/" }]
}
EOF
git -C "${__scratch}" add -A -f

set +o errexit
OUT_C=$(run_case)
EXIT_C=$?
set -o errexit

if [ "${EXIT_C}" -ne 0 ] && echo "${OUT_C}" | grep -q "dead link"; then
  pass "markdown-link-check: a non-matching config is not a blanket rubber stamp"
else
  fail "markdown-link-check: non-matching ignorePattern should still have failed" "exit=${EXIT_C}
${OUT_C}"
fi

summarize
