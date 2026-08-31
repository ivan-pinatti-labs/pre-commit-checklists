#!/usr/bin/env bash

: '
  Validates the current branch name.

  By default, any ordinary branch name is accepted: lowercase letters,
  digits, hyphens, underscores, dots and slashes (e.g. "add-login-page",
  "fix/flaky-test", "dependabot/github_actions/actions-abc123"). The
  underscore and dot are accepted because Dependabot and Renovate default
  branch names use them and neither bot lets that be reconfigured away.
  Protected branch names (main, master, develop by default) are always
  accepted too.

  Ticket-prefix enforcement is opt-in. Pass --ticket-prefixes to require
  branches to start with one of the given prefixes followed by a ticket
  number, e.g. --ticket-prefixes "PROJ" accepts "proj-123-add-login" and
  rejects an unprefixed "add-login-page".

  Exit status codes:
    0 - branch name is valid
    1 - branch name is invalid
    2 - branch name could not be determined
    3 - invalid arguments
'

if [ "${DEBUG:-false}" = true ]; then
  set -x
fi

set -o errexit
set -o pipefail
set -o nounset

# Force the C locale for the whole script. [a-z0-9] and friends are
# collation-order ranges, not fixed ASCII sets: under an accented locale
# such as en_CA.UTF-8, bash's regex engine widens [a-z] to accept letters
# like the a-with-accent in "cafe" too, so the exact same branch name is
# accepted on one developer's machine and rejected in CI (which typically
# runs under C/POSIX). Pinning LC_ALL=C here makes every [[ =~ ]] match
# below behave the same regardless of the caller's ambient locale.
export LC_ALL=C

__ticket_prefixes=""
__protected_branches="main master develop"

usage() {
  cat <<EOF
Usage: $(basename "${0}") [--ticket-prefixes "PROJ"] [--protected-branches "main master develop"]

By default, ordinary branch names are accepted with no ticket prefix
required. Pass --ticket-prefixes to require one.

Examples:
  $(basename "${0}")
  $(basename "${0}") --ticket-prefixes "PROJ ACME"
EOF
  exit 3
}

while [ $# -gt 0 ]; do
  case "${1}" in
  --ticket-prefixes)
    __ticket_prefixes="${2:-}"
    shift 2
    ;;
  --protected-branches)
    __protected_branches="${2:-}"
    shift 2
    ;;
  -h | --help)
    usage
    ;;
  *)
    echo "Unknown option: ${1}" >&2
    usage
    ;;
  esac
done

# Use GITHUB_HEAD_REF if present (GitHub Actions), else fall back to git.
__branch_name=${GITHUB_HEAD_REF:-$(git symbolic-ref --short HEAD 2>/dev/null || true)}

if [ -z "${__branch_name}" ]; then
  echo "Error: branch name could not be determined." >&2
  exit 2
fi

__protected_pattern="${__protected_branches// /|}"

if [[ ${__branch_name} =~ ^(${__protected_pattern})$ ]]; then
  echo "Branch name '${__branch_name}' is a protected branch name. OK."
  exit 0
fi

if [ -n "${__ticket_prefixes}" ]; then
  __prefix_pattern="${__ticket_prefixes// /|}"
  __prefix_pattern_lower=$(tr '[:upper:]' '[:lower:]' <<<"${__prefix_pattern}")
  __prefix_pattern_upper=$(tr '[:lower:]' '[:upper:]' <<<"${__prefix_pattern}")

  if [[ ${__branch_name} =~ ^(${__prefix_pattern_lower}|${__prefix_pattern_upper})-[0-9]+[-a-zA-Z0-9]*$ ]]; then
    echo "Branch name '${__branch_name}' is valid."
    exit 0
  fi

  cat <<EOF
Error: branch name '${__branch_name}' does not follow the required naming convention.
Branch names must either:
  - Start with one of the following prefixes (case-insensitive) followed by a ticket number: ${__ticket_prefixes}
  - Match one of the protected branch names: ${__protected_branches}
Example valid names: 'PROJ-123-feature', 'acme-321-bugfix', 'main'.
EOF
  exit 1
fi

# No ticket prefixes configured: accept ordinary lowercase slug names.
#
# The separator class includes /, hyphen, _ and . so that dependency-bot
# branches validate cleanly, not just hand-written ones: Dependabot's
# branch names embed the package-ecosystem id verbatim (e.g.
# "dependabot/github_actions/github-actions-151ba0d261",
# "dependabot/pre_commit/pre-commit-hooks-941c2d6198") and that segment
# always has an underscore, with no config option to change it. Renovate
# branches can carry a dot too (e.g. "renovate/alpine-3.x"). A leading or
# trailing separator is still rejected because every separator in the
# pattern must be followed by at least one [a-z0-9] character.
#
# `-?/` is the one place a doubled separator is tolerated, and it exists for
# a shape no consumer can avoid. When a pre-commit hook repository is named
# by URL rather than by short name, Dependabot encodes the "https://" into
# the branch, replacing the colon and one slash with a single hyphen:
#
#   dependabot/pre_commit/https-/github.com/<owner>/<repo>-<version>
#
# That "https-/" is a hyphen immediately followed by a slash, which the
# original pattern rejected, so `Pre-commit` failed on every such pull
# request and the bump could never merge. Observed on
# ivan-pinatti-labs/github-template#11. Repositories that group their
# pre-commit updates never see it, because the group name replaces the URL,
# which is why this went unnoticed for so long.
#
# Deliberately narrow: only a single optional hyphen, and only directly
# before a slash. "foo--/bar", "foo-/-bar", "double//slash", "under__score"
# and "dot..dot" are all still rejected, and each is asserted in
# tests/scripts/lint_shell.sh so this stays true.
if [[ ${__branch_name} =~ ^[a-z0-9]+((-?/|[_.-])[a-z0-9]+)*$ ]]; then
  echo "Branch name '${__branch_name}' is valid."
  exit 0
fi

cat <<EOF
Error: branch name '${__branch_name}' does not follow the required naming convention.
Branch names must be lowercase, using only letters, digits, hyphens,
underscores, dots and slashes (e.g. 'add-login-page', 'fix/flaky-test',
'dependabot/github_actions/github-actions-abc123'), or match one of the
protected branch names: ${__protected_branches}
EOF
exit 1
