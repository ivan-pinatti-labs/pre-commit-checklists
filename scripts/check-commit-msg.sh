#!/usr/bin/env bash

# Validates a commit message against Conventional Commits.
#
# By default, checks plain Conventional Commits: "type(scope): subject",
# with the scope optional, e.g. "feat: add login page" or
# "fix(auth): handle expired token".
#
# Ticket enforcement is opt-in. Pass --ticket-prefixes to require the
# scope to be a ticket id from one of the given prefixes, e.g.
# --ticket-prefixes "PROJ" requires "feat(PROJ-123): add login page".
#
# Subjects git writes on its own pass as they are, when there is proof git
# wrote them: a merge ("Merge branch 'x'", "Merge remote-tracking branch
# ...") while a merge is in progress (MERGE_HEAD exists), and a revert or a
# revert of a revert ('Revert "..."', 'Reapply "..."') whose body carries
# git's "This reverts commit <sha>." line naming a commit whose own subject
# the revert subject quotes. A "fixup! " or "squash! " prefix
# from `git commit --fixup` is set aside and the subject after it is
# checked as usual; for "amend! ", the replacement message after the
# blank line is what lands, so that is what gets checked. Only the first
# line is matched as the subject.
#
# AI attribution is refused only when asked for. Pass --no-ai-attribution
# to reject a message with a line crediting or linking an AI agent: a
# Co-Authored-By trailer naming one, a "Generated with" line, or an agent
# session link (Claude-Session:, claude.ai/code/session_..., and the
# task or session links of Codex, Jules, Devin and the Cursor agents).
#
# Exit status codes:
#   0 - commit message is valid
#   1 - commit message is invalid
#   2 - invalid arguments
#   3 - missing commit message file

if [[ "${DEBUG:-false}" = true ]]; then
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

while [[ $# -gt 0 ]]; do
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

if [[ $# -lt 1 ]]; then
  echo "Error: missing commit message file argument." >&2
  usage
  exit 3
fi

COMMIT_MSG_FILE="${1}"
COMMIT_MSG=$(cat "${COMMIT_MSG_FILE}")

readonly COMMIT_TYPES="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"

# git's own merge and revert subjects (see the header).
# A merge names what it merges; pulling a repository's HEAD with no branch
# named gives "Merge <url>", hence the bare URL or path form.
# A quoted name is '<no whitespace>': a ref name can't hold whitespace but
# can hold an apostrophe (fix/o'clock), which git writes as it is. Keep an
# even number of quote characters in these patterns: kcov reads bash's
# trace of the match, and an odd count throws its line attribution off for
# the rest of the file. The whole subject is anchored: one or more groups
# of a kind and its names ("branch 'a', remote-tracking branch 'b'",
# "branches 'a', 'b' and 'c'"), then only git's own suffixes, " of <url>"
# and " into <branch>".
readonly GIT_MERGE_NAME="'[^[:space:]]+'"
readonly GIT_MERGE_GROUP="(branch(es)?|remote-tracking branch(es)?|tags?|commits?) ${GIT_MERGE_NAME}((, | and )${GIT_MERGE_NAME})*"
readonly GIT_MERGE_SUBJECT="^Merge (${GIT_MERGE_GROUP}((, |; | and )${GIT_MERGE_GROUP})*( of [^ ]+)?|[^ ]*[/:][^ ]*)( into [^ ]+)?$"
readonly GIT_REVERT_SUBJECT='^(Revert|Reapply) "(.+)"$'
# "<sha>." for a commit, "<sha>, reversing" (then a new line) for a merge.
readonly GIT_REVERT_BODY=$'(^|\n)This reverts commit ([0-9a-f]{40}([0-9a-f]{24})?)(\\.|, reversing)(\n|$)'

__subject_msg="${COMMIT_MSG}"

# `git commit --fixup=amend:<commit>` (or reword:) writes "amend! <old
# subject>", a blank line, then the replacement message, which is what
# `git rebase -i` keeps. Check the replacement: its first line that is neither
# blank nor a comment. With no replacement at all, the squash would leave
# the target with an empty message, so that fails.
if [[ ${__subject_msg} == "amend! "* ]]; then
  if [[ ${__subject_msg} == *$'\n\n'* ]]; then
    __subject_msg="${__subject_msg#*$'\n\n'}"
  else
    __subject_msg=""
  fi
  while [[ ${__subject_msg} == $'\n'* || ${__subject_msg} == "#"* ]]; do
    if [[ ${__subject_msg} == *$'\n'* ]]; then
      __subject_msg="${__subject_msg#*$'\n'}"
    else
      __subject_msg=""
    fi
  done
fi

# Set aside any fixup!, squash! or amend! prefixes; what follows is the
# subject of the commit they target.
while [[ ${__subject_msg} == "fixup! "* || ${__subject_msg} == "squash! "* || ${__subject_msg} == "amend! "* ]]; do
  __subject_msg="${__subject_msg#*! }"
done

# The subject is the first line; in bash's regex `.` matches a newline too.
__subject_msg="${__subject_msg%%$'\n'*}"

__git_subject=false
if [[ ${__subject_msg} =~ ${GIT_MERGE_SUBJECT} ]]; then
  __git_dir=$(git rev-parse --git-dir 2>/dev/null || true)
  if [[ -n "${__git_dir}" ]] && [[ -f "${__git_dir}/MERGE_HEAD" ]]; then
    __git_subject=true
  fi
elif [[ ${__subject_msg} =~ ${GIT_REVERT_SUBJECT} ]]; then
  __verb="${BASH_REMATCH[1]}"
  __quoted="${BASH_REMATCH[2]}"
  if [[ ${COMMIT_MSG} =~ ${GIT_REVERT_BODY} ]]; then
    # The reverted commit must exist, and its subject must be the one
    # quoted: 'Revert "S"' undoes a commit with subject S, and
    # 'Reapply "S"' undoes a commit with subject 'Revert "S"'. git quotes
    # the first line of a subject that wraps onto more lines, so that line
    # is what is compared.
    __target=$(git log -1 --format=%B "${BASH_REMATCH[2]}" 2>/dev/null || true)
    __target="${__target%%$'\n'*}"
    if [[ "${__verb}" = Revert && "${__target}" = "${__quoted}" ]] ||
      [[ "${__verb}" = Reapply && "${__target}" = "Revert \"${__quoted}\"" ]]; then
      __git_subject=true
    fi
  fi
fi

if [[ "${__git_subject}" = true ]]; then
  : # written by git itself, accepted as it is
elif [[ -n "${__ticket_prefixes}" ]]; then
  IFS=' ' read -r -a __prefix_array <<<"${__ticket_prefixes}"
  IFS='|'
  __prefix_pattern="${__prefix_array[*]}"
  unset IFS
  readonly CONVENTIONAL_COMMIT_REGEX="^(${COMMIT_TYPES})\((${__prefix_pattern})-[0-9]+\)!?: .+"

  if [[ ! ${__subject_msg} =~ ${CONVENTIONAL_COMMIT_REGEX} ]]; then
    cat <<EOF
Error: commit message does not follow the required format.
Expected format: 'type(TICKET-ID): description'
Examples: 'feat(PROJ-1234): new form'
          'fix(ACME-4321): fix login issue'
EOF
    exit 1
  fi
else
  # An optional "!" before the colon marks a breaking change.
  readonly CONVENTIONAL_COMMIT_REGEX="^(${COMMIT_TYPES})(\([a-zA-Z0-9_.-]+\))?!?: .+"

  if [[ ! ${__subject_msg} =~ ${CONVENTIONAL_COMMIT_REGEX} ]]; then
    cat <<EOF
Error: commit message does not follow Conventional Commits.
Expected format: 'type(optional-scope): description', with '!' before the
colon for a breaking change
Examples: 'feat: add login page'
          'fix(auth): handle expired token'
Valid types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
EOF
    exit 1
  fi
fi

if [[ "${__no_ai_attribution}" = true ]]; then
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
  # Links to an agent's own session or task, which harnesses append on
  # their own: Claude Code, OpenAI Codex, Google Jules, Devin, Cursor's
  # background agents.
  readonly AI_SESSION="(^claude-session:)|(claude\.ai/code/session_)|(chatgpt\.com/codex/tasks/)|(jules\.google\.com/task/)|(app\.devin\.ai/sessions/)|(cursor\.com/agents/)"
  __found=""
  __n=0
  # The loop reads the file through descriptor 3 rather than a redirect on
  # its `done`, which kcov never counts as run. read -u is in bash 3.2 too.
  exec 3<"${COMMIT_MSG_FILE}"
  shopt -s nocasematch
  while IFS= read -r -u 3 __line || [[ -n "${__line}" ]]; do
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
    if [[ "${__hit}" = true ]]; then
      __found="${__found}${__n}:${__line}"$'\n'
    fi
  done
  exec 3<&-
  shopt -u nocasematch
  if [[ -n "${__found}" ]]; then
    printf '%s\n%s\n%s' \
      "Error: commit message carries AI attribution, which this repository does not" \
      "allow (--no-ai-attribution). Remove these lines:" "${__found}"
    exit 1
  fi
fi

echo "Commit message is valid."
exit 0
