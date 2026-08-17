#!/usr/bin/env bash

: '
  Dispatcher for the checklist YAML files in checklists/.
  Resolves a checklist name to its config file and hands off to
  `pre-commit run`, passing through the file arguments pre-commit
  itself supplied to the calling hook.

  Exit status codes:
    0 - success (pre-commit run passed)
    1 - non-zero exit from usage/argument errors
    2 - checklist file not found
    non-zero - whatever `pre-commit run` returns

  A checklist-file-not-found error (exit 2) is almost always a consumer
  args: override on a checklist-* hook id in their own
  .pre-commit-config.yaml, not a typo here: every checklist-* id except
  checklist-git-valid-branches and checklist-git-commit-msg calls this
  script with the checklist name as its first argument, and a consumer
  args: entry replaces that argument instead of adding to it. See
  docs/overrides.md, "Do not put args: on a checklist-* id that routes
  through run-checklist.sh".
'

# Print commands as they run, and dump the environment, when DEBUG=true.
if [ "${DEBUG:-false}" = true ]; then
  set -x
  export
fi

set -o errexit
set -o pipefail
set -o nounset

HERE=$(dirname "$(realpath "${0}")")
CHECKLISTS_DIR="${HERE}/../checklists"

usage() {
  cat <<EOF
Usage: $(basename "${0}") <checklist-name> [files...]

Runs pre-commit against one of the checklist YAML files in checklists/,
using the given checklist name (without the .yaml extension).

Arguments:
  <checklist-name>   Name of a file under checklists/, without extension
  [files...]         Files to pass to pre-commit (usually supplied by
                      pre-commit itself when this runs as a hook)

Examples:
  $(basename "${0}") checklist-basic file1.py file2.py
EOF
  exit 1
}

if [ $# -lt 1 ]; then
  usage
fi

CHECKLIST_NAME="${1}"
CONFIG_PATH="${CHECKLISTS_DIR}/${CHECKLIST_NAME}.yaml"

if [ ! -f "${CONFIG_PATH}" ]; then
  echo "Error: checklist '${CHECKLIST_NAME}' not found at '${CONFIG_PATH}'." >&2
  echo "" >&2
  echo "This usually means the args: of a checklist-* hook id were" >&2
  echo "overridden in your .pre-commit-config.yaml. Every checklist-* hook" >&2
  echo "id except checklist-git-valid-branches and checklist-git-commit-msg" >&2
  echo "calls this script with the checklist name as its first argument;" >&2
  echo "an args: entry on one of those ids in your own config replaces that" >&2
  echo "name instead of adding to it. See docs/overrides.md, \"Do not put" >&2
  echo "args: on a checklist-* id that routes through run-checklist.sh\"." >&2
  exit 2
fi

shift

exec pre-commit run --config "${CONFIG_PATH}" --files "$@"
