#!/usr/bin/env bash

: '
  Bootstraps a target repository with this library: copies a chosen
  pre-commit-config template plus the supporting tool configs into
  --target, generates a detect-secrets baseline, and runs
  `pre-commit install`.

  This is the one script in this library that reaches outside its own
  repo: it writes into whatever --target points at, never into this repo.

  Exit status codes:
    0 - success
    1 - usage/argument error
    2 - target directory not found
    3 - template not found
    4 - a file already exists at the destination and --force was not given
    5 - a required command (pre-commit or detect-secrets) is not installed
    non-zero - whatever the failing command returned
'

if [ "${DEBUG:-false}" = true ]; then
  set -x
  export
fi

set -o errexit
set -o pipefail
set -o nounset

HERE=$(dirname "$(realpath "${0}")")
TEMPLATES_DIR="${HERE}/../templates"

__template="recommended"
__target=""
__force=false

usage() {
  cat <<EOF
Usage: $(basename "${0}") --target <path> [--template <name>] [--force]

Copies a pre-commit-config template and the supporting tool configs from
templates/ into --target, generates --target/.secrets.baseline, and runs
'pre-commit install' inside --target.

Arguments:
  --target <path>     Repository to bootstrap. Must already exist.
  --template <name>   One of the files in templates/pre-commit-config/,
                      without the .yaml extension. Default: recommended.
                      (minimal, recommended, full, python, shell,
                      terraform, javascript, typescript)
  --force              Overwrite files already present at the destination.

Examples:
  $(basename "${0}") --target ../my-repo
  $(basename "${0}") --target ../my-repo --template python
EOF
  exit 1
}

while [ $# -gt 0 ]; do
  case "${1}" in
  --target)
    __target="${2:-}"
    shift 2
    ;;
  --template)
    __template="${2:-}"
    shift 2
    ;;
  --force)
    __force=true
    shift
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

if [ -z "${__target}" ]; then
  echo "Error: --target is required." >&2
  usage
fi

if [ ! -d "${__target}" ]; then
  echo "Error: target directory '${__target}' does not exist." >&2
  exit 2
fi

__target=$(realpath "${__target}")

__config_template="${TEMPLATES_DIR}/pre-commit-config/${__template}.yaml"
if [ ! -f "${__config_template}" ]; then
  echo "Error: no template named '${__template}' in templates/pre-commit-config/." >&2
  exit 3
fi

copy_file() {
  __src="${1}"
  __dest="${2}"

  if [ -e "${__dest}" ] && [ "${__force}" != true ]; then
    echo "Skipping ${__dest}: already exists (pass --force to overwrite)." >&2
    return 4
  fi

  cp "${__src}" "${__dest}"
  echo "Wrote ${__dest}"
}

echo "Bootstrapping '${__target}' from the '${__template}' template."

# copy_file returns 4 for an intentional skip (destination exists, no
# --force). That is not a fatal condition here, just per-file, so it is
# swallowed with `|| true` rather than letting errexit abort the run.
copy_file "${__config_template}" "${__target}/.pre-commit-config.yaml" || true
copy_file "${TEMPLATES_DIR}/.editorconfig" "${__target}/.editorconfig" || true
copy_file "${TEMPLATES_DIR}/.cspell.json" "${__target}/.cspell.json" || true
copy_file "${TEMPLATES_DIR}/.yamllint.yml" "${__target}/.yamllint.yml" || true
copy_file "${TEMPLATES_DIR}/.markdownlint.yaml" "${__target}/.markdownlint.yaml" || true
copy_file "${TEMPLATES_DIR}/.lycheeignore" "${__target}/.lycheeignore" || true
copy_file "${TEMPLATES_DIR}/.mega-linter.yml" "${__target}/.mega-linter.yml" || true

# Append the gitignore fragment once, marked so re-running is idempotent.
__marker="# --- pre-commit-checklists (scripts/install.sh) ---"
if [ ! -f "${__target}/.gitignore" ] || ! grep -qF "${__marker}" "${__target}/.gitignore"; then
  {
    echo ""
    echo "${__marker}"
    tail -n +2 "${TEMPLATES_DIR}/gitignore.fragment"
  } >>"${__target}/.gitignore"
  echo "Appended gitignore entries to ${__target}/.gitignore"
else
  echo "Skipping .gitignore: already has the pre-commit-checklists section."
fi

if ! command -v detect-secrets >/dev/null 2>&1; then
  echo "Error: detect-secrets is not installed. Install it with 'pip install detect-secrets' or 'pipx install detect-secrets' and re-run." >&2
  exit 5
fi

if [ -f "${__target}/.secrets.baseline" ] && [ "${__force}" != true ]; then
  echo "Skipping .secrets.baseline: already exists (pass --force to regenerate)."
else
  (cd "${__target}" && detect-secrets scan --exclude-files '\.git/' >.secrets.baseline)
  chmod 600 "${__target}/.secrets.baseline"
  echo "Wrote ${__target}/.secrets.baseline"
fi

if ! command -v pre-commit >/dev/null 2>&1; then
  echo "Error: pre-commit is not installed. Install it with 'pip install pre-commit' and re-run." >&2
  exit 5
fi

(cd "${__target}" && pre-commit install)

cat <<EOF

Done. Next steps in '${__target}':
  1. Update the 'rev:' pin in .pre-commit-config.yaml to a published tag.
  2. Review .secrets.baseline and commit it.
  3. Run: pre-commit run --all-files
EOF
