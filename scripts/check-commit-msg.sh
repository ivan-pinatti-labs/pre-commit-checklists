#!/usr/bin/env bash

: '
  Validates a commit message against Conventional Commits.

  By default, checks plain Conventional Commits: "type(scope): subject",
  with the scope optional, e.g. "feat: add login page" or
  "fix(auth): handle expired token".

  Ticket enforcement is opt-in. Pass --ticket-prefixes to require the
  scope to be a ticket id from one of the given prefixes, e.g.
  --ticket-prefixes "PROJ" requires "feat(PROJ-123): add login page".

  Exit status codes:
    0 - commit message is valid
    1 - commit message is invalid
    2 - invalid arguments
    3 - missing commit message file
'

if [ "${DEBUG:-false}" = true ]; then
  set -x
fi

set -o errexit
set -o pipefail
set -o nounset

__ticket_prefixes=""

usage() {
  cat <<EOF
Usage: $(basename "${0}") [--ticket-prefixes "PROJ"] <commit-message-file>

By default, checks plain Conventional Commits with an optional scope.
Pass --ticket-prefixes to require the scope to be a ticket id.

Examples:
  $(basename "${0}") .git/COMMIT_EDITMSG
  $(basename "${0}") --ticket-prefixes "PROJ ACME" .git/COMMIT_EDITMSG
EOF
}

while [ $# -gt 0 ]; do
  case "${1}" in
  --ticket-prefixes)
    __ticket_prefixes="${2:-}"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    break
    ;;
  -*)
    echo "Unknown option: ${1}" >&2
    usage
    exit 2
    ;;
  *)
    break
    ;;
  esac
done

if [ $# -lt 1 ]; then
  echo "Error: missing commit message file argument." >&2
  usage
  exit 3
fi

COMMIT_MSG_FILE="${1}"
COMMIT_MSG=$(cat "${COMMIT_MSG_FILE}")

readonly COMMIT_TYPES="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"

if [ -n "${__ticket_prefixes}" ]; then
  IFS=' ' read -r -a __prefix_array <<<"${__ticket_prefixes}"
  IFS='|'
  __prefix_pattern="${__prefix_array[*]}"
  unset IFS
  readonly CONVENTIONAL_COMMIT_REGEX="^(${COMMIT_TYPES})\((${__prefix_pattern})-[0-9]+\): .+"

  if [[ ! ${COMMIT_MSG} =~ ${CONVENTIONAL_COMMIT_REGEX} ]]; then
    cat <<EOF
Error: commit message does not follow the required format.
Expected format: 'type(TICKET-ID): description'
Examples: 'feat(PROJ-1234): new form'
          'fix(ACME-4321): fix login issue'
EOF
    exit 1
  fi
else
  readonly CONVENTIONAL_COMMIT_REGEX="^(${COMMIT_TYPES})(\([a-zA-Z0-9_.-]+\))?: .+"

  if [[ ! ${COMMIT_MSG} =~ ${CONVENTIONAL_COMMIT_REGEX} ]]; then
    cat <<EOF
Error: commit message does not follow Conventional Commits.
Expected format: 'type(optional-scope): description'
Examples: 'feat: add login page'
          'fix(auth): handle expired token'
Valid types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
EOF
    exit 1
  fi
fi

echo "Commit message is valid."
exit 0
