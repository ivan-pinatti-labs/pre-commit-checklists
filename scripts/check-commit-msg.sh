#!/usr/bin/env bash

: '
  Validates a commit message against Conventional Commits.

  By default, checks plain Conventional Commits: "type(scope): subject",
  with the scope optional, e.g. "feat: add login page" or
  "fix(auth): handle expired token".

  Ticket enforcement is opt-in. Pass --ticket-prefixes to require the
  scope to be a ticket id from one of the given prefixes, e.g.
  --ticket-prefixes "PROJ" requires "feat(PROJ-123): add login page".

  AI attribution is refused only when asked for. Pass --no-ai-attribution
  to reject a message with a line crediting or linking an AI agent: a
  Co-Authored-By trailer naming one, a "Generated with" line, or an agent
  session link (claude.ai/code/session_..., Claude-Session:).

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
__no_ai_attribution=false

usage() {
  cat <<EOF
Usage: $(basename "${0}") [--ticket-prefixes "PROJ"] [--no-ai-attribution] <commit-message-file>

By default, checks plain Conventional Commits with an optional scope.
Pass --ticket-prefixes to require the scope to be a ticket id.
Pass --no-ai-attribution to reject lines crediting or linking an AI agent.

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
  --no-ai-attribution)
    __no_ai_attribution=true
    shift
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

if [ "${__no_ai_attribution}" = true ]; then
  # Comment lines (which git strips) do not count; everything is matched
  # case-insensitively. A co-author is an agent by its identity only: the
  # trailer is split into its name and its email, and the name must be an
  # agent's exact product name or bot account, or the email an agent's
  # domain or bot account. A person named Devin or Claude passes, and so
  # does text after the email.
  readonly AI_AGENT_NAMES="claude( code)?|chatgpt|codex|(github )?copilot|gemini( code assist)?|cursor( agent)?|devin( ai)?|aider|windsurf"
  readonly AI_AGENT_BOTS="(copilot|devin-ai-integration|cursor|claude|codex|openai)[a-z0-9-]*\[bot\]"
  readonly AI_AGENT_DOMAINS="anthropic\.com|openai\.com|cursor\.(com|sh)|cognition\.ai|aider\.chat|codeium\.com|windsurf\.com"
  readonly COAUTHOR_TRAILER="^co-authored-by:[[:space:]]*(.*[^[:space:]])[[:space:]]*<([^<>]*)>"
  readonly AI_GENERATED="generated (with|by) .*(claude|anthropic|openai|codex|chatgpt|copilot|gemini|cursor|devin|aider|windsurf)"
  readonly AI_SESSION="(^claude-session:)|(claude\.ai/code/session_)"
  __found=""
  __n=0
  shopt -s nocasematch
  while IFS= read -r __line || [ -n "${__line}" ]; do
    __n=$((__n + 1))
    [[ ${__line} == "#"* ]] && continue
    __hit=false
    if [[ ${__line} =~ ${COAUTHOR_TRAILER} ]]; then
      __name="${BASH_REMATCH[1]}"
      __email="${BASH_REMATCH[2]}"
      if [[ ${__name} =~ ^(${AI_AGENT_NAMES})$ ]] || [[ ${__name} =~ ^${AI_AGENT_BOTS}$ ]] ||
        [[ ${__email} =~ @(${AI_AGENT_DOMAINS})$ ]] || [[ ${__email} =~ ^([0-9]+\+)?${AI_AGENT_BOTS}@ ]]; then
        __hit=true
      fi
    elif [[ ${__line} =~ ${AI_GENERATED} ]] || [[ ${__line} =~ ${AI_SESSION} ]]; then
      __hit=true
    fi
    if [ "${__hit}" = true ]; then
      __found="${__found}${__n}:${__line}"$'\n'
    fi
  done <"${COMMIT_MSG_FILE}"
  shopt -u nocasematch
  if [ -n "${__found}" ]; then
    printf '%s\n%s\n%s' \
      "Error: commit message carries AI attribution, which this repository does not" \
      "allow (--no-ai-attribution). Remove these lines:" "${__found}"
    exit 1
  fi
fi

echo "Commit message is valid."
exit 0
