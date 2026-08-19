#!/usr/bin/env bash

: '
  Bootstraps a target repository with this library: copies a chosen
  pre-commit-config template plus the supporting tool configs into
  --target, generates a detect-secrets baseline, and runs
  `pre-commit install`. Pass --community-files to also copy the GitHub
  community health files (issue templates, pull request template,
  CODE_OF_CONDUCT.md, CONTRIBUTING.md, SECURITY.md, a commented-out
  FUNDING.yml) from templates/community/; this is opt in, not the
  default, since plenty of consumers already have their own.

  Runs in one of two modes, detected automatically, no flag needed:
    - Local: invoked from a checkout of this repo (./scripts/install.sh,
      or bash scripts/install.sh), copies the template files straight
      off disk.
    - Remote: invoked piped into bash (curl ... | bash -s -- ...), where
      there is no checkout to copy from, so the same files are fetched
      over HTTPS from raw.githubusercontent.com instead, pinned to
      --ref.

  This is the one script in this library that reaches outside its own
  repo: it writes into whatever --target points at (or, in remote mode
  with no --target given, the current directory), never into this repo.

  Exit status codes:
    0 - success
    1 - usage/argument error
    2 - target directory not found
    3 - the template, or an expected supporting file (including a
        community file, when --community-files is given), was not
        found at the chosen --template / --ref (bad template name, bad
        ref, or a ref from before --community-files existed)
    4 - a file already exists at the destination and --force was not given
    5 - a required command (pre-commit or detect-secrets) is not installed
    6 - neither curl nor wget is installed (remote mode only)
    7 - a network fetch failed for a reason other than "not found":
        DNS, connection, or timeout (remote mode only)
    non-zero - whatever the failing command returned
'

# `set -x` alone, deliberately. A bare `export` prints every inherited
# environment variable's value, which in CI includes whatever a neighbouring
# step exported (a token, a registry credential), and someone reaching for
# DEBUG=true to troubleshoot a failed bootstrap should not risk leaking one
# into a build log. The trace already shows the resolved paths, the fetch
# URLs, and every command run, which is what is actually useful here. Same
# contract as run-checklist.sh, check-branch-name.sh, check-commit-msg.sh.
if [ "${DEBUG:-false}" = true ]; then
  set -x
fi

set -o errexit
set -o pipefail
set -o nounset

readonly GITHUB_OWNER_REPO="ivan-pinatti/pre-commit-checklists"

__template="recommended"
__target=""
__force=false
__ref=""
__community_files=false

usage() {
  cat <<EOF
Usage: $(basename "${0}") [--target <path>] [--template <name>] [--ref <tag|branch>] [--force] [--community-files]

Copies a pre-commit-config template and the supporting tool configs into
--target, generates --target/.secrets.baseline, and runs
'pre-commit install' inside --target. Works two ways, detected
automatically: run from a local clone (copies off disk), or piped into
bash (fetches from GitHub instead).

Arguments:
  --target <path>         Repository to bootstrap. Must already exist.
                          Defaults to the current directory in the piped
                          form; required when run from a local clone.
  --template <name>       One of the files in templates/pre-commit-config/,
                          without the .yaml extension. Default: recommended.
                          (minimal, recommended, full, python, shell,
                          terraform, javascript, typescript)
  --ref <tag|branch>      Piped form only: the git ref to fetch templates
                          from. Default: this repository's latest release
                          tag, falling back to 'main' if it has no release
                          yet.
  --force                 Overwrite files already present at the destination.
  --community-files       Also copy the GitHub community health files from
                          templates/community/ (issue templates, a pull
                          request template, CODE_OF_CONDUCT.md,
                          CONTRIBUTING.md, SECURITY.md, a commented-out
                          FUNDING.yml). Off by default. These land with
                          generic placeholders; search the copied files
                          for bracketed tokens (e.g. OWNER/REPO) and fill
                          them in before publishing.

Examples:
  curl -fsSL https://raw.githubusercontent.com/${GITHUB_OWNER_REPO}/main/scripts/install.sh \\
    | bash -s -- --template recommended
  $(basename "${0}") --target ../my-repo --template python
  $(basename "${0}") --target ../my-repo --community-files
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
  --ref)
    __ref="${2:-}"
    shift 2
    ;;
  --force)
    __force=true
    shift
    ;;
  --community-files)
    __community_files=true
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

# --- Mode detection: local checkout, or piped into bash -----------------

# Local mode is used when this script can find its own repo root on
# disk: it was checked out, not piped in. Piping a script into
# `bash -s --` runs it straight from stdin, which leaves BASH_SOURCE
# empty (there is no source file for a script read from a pipe), so the
# check below naturally falls through to remote mode in that case; no
# flag needed to tell the two apart.
detect_local_repo_root() {
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    __candidate=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
    if [ -d "${__candidate}/templates/pre-commit-config" ]; then
      printf '%s\n' "${__candidate}"
      return 0
    fi
  fi
  return 1
}

MODE="remote"
LOCAL_REPO_ROOT=""
if LOCAL_REPO_ROOT=$(detect_local_repo_root); then
  MODE="local"
fi

STAGING_DIR=""
cleanup_staging() {
  if [ -n "${STAGING_DIR}" ] && [ -d "${STAGING_DIR}" ]; then
    rm -rf "${STAGING_DIR}"
  fi
}
trap cleanup_staging EXIT

if [ -z "${__target}" ]; then
  if [ "${MODE}" = "remote" ]; then
    __target=$(pwd)
  else
    echo "Error: --target is required." >&2
    usage
  fi
fi

if [ ! -d "${__target}" ]; then
  echo "Error: target directory '${__target}' does not exist." >&2
  exit 2
fi

__target=$(realpath "${__target}")

# --- Resolve TEMPLATES_DIR: local files, or a freshly fetched staging ---
# --- directory standing in for them -------------------------------------

TEMPLATES_DIR=""

if [ "${MODE}" = "local" ]; then
  TEMPLATES_DIR="${LOCAL_REPO_ROOT}/templates"
  if [ ! -f "${TEMPLATES_DIR}/pre-commit-config/${__template}.yaml" ]; then
    echo "Error: no template named '${__template}' in templates/pre-commit-config/." >&2
    exit 3
  fi
  if [ "${__community_files}" = true ] && [ ! -f "${TEMPLATES_DIR}/community/CONTRIBUTING.md" ]; then
    echo "Error: no templates/community/ directory found next to this checkout." >&2
    exit 3
  fi
else
  FETCHER=""
  if command -v curl >/dev/null 2>&1; then
    FETCHER="curl"
  elif command -v wget >/dev/null 2>&1; then
    FETCHER="wget"
  else
    echo "Error: neither curl nor wget is installed; install one and re-run." >&2
    exit 6
  fi

  # Fetches $1 (a URL) into $2. Returns 0 on success, 2 if the server
  # reported the resource does not exist (HTTP 404, the shape of a bad
  # --template or --ref), 1 for any other fetch failure (DNS,
  # connection, timeout, ...).
  # Reports the HTTP status for a URL, or 000 if the request never got
  # one. Only consulted on the failure path, so the happy path still costs
  # a single request.
  http_status() {
    __code=""
    if [ "${FETCHER}" = "curl" ]; then
      __code=$(curl -sSL -o /dev/null -w '%{http_code}' "${1}" 2>/dev/null) || __code=""
    else
      __code=$(wget --spider -S "${1}" 2>&1 |
        awk '/^[[:space:]]*HTTP\//{code=$2} END{print code}')
    fi
    # Normalize to exactly three digits. curl's %{http_code} already prints
    # 000 when it never got a response, but it prints nothing at all if it
    # fails before writing, and a doubled fallback would emit "000000".
    case "${__code}" in
    [0-9][0-9][0-9]) printf '%s' "${__code}" ;;
    *) printf '000' ;;
    esac
  }

  # Returns 0 on success, 2 only when the server specifically answered 404,
  # and 1 for everything else: a network failure, or any other HTTP error.
  #
  # The 404 has to be identified precisely, because fetch_optional treats a
  # 2 as "this ref does not carry that file, skip it" while everything else
  # stays fatal. Neither curl's exit 22 nor wget's exit 8 is specific enough
  # on its own: both mean "some HTTP status at or above 400", so a 403, a
  # 429 from rate limiting, or a 500 would all have been read as a missing
  # file and silently skipped, producing a quietly incomplete install out of
  # a transient failure. Hence the extra status probe, on the failure path
  # only.
  fetch_url() {
    __url="${1}"
    __dest="${2}"
    __status=0
    if [ "${FETCHER}" = "curl" ]; then
      # An `if cmd; then ...; fi` with no `else` returns exit status 0
      # when cmd fails, not cmd's own status, so the real status is
      # captured via `||` before that ever runs.
      curl -fsSL "${__url}" -o "${__dest}" || __status=$?
      [ "${__status}" -eq 0 ] && return 0
      rm -f "${__dest}"
      if [ "${__status}" -eq 22 ] && [ "$(http_status "${__url}")" = "404" ]; then
        return 2
      fi
      return 1
    fi
    wget -q "${__url}" -O "${__dest}" || __status=$?
    [ "${__status}" -eq 0 ] && return 0
    rm -f "${__dest}"
    if [ "${__status}" -eq 8 ] && [ "$(http_status "${__url}")" = "404" ]; then
      return 2
    fi
    return 1
  }

  # Only used to pick a default --ref: the latest GitHub release tag, or
  # empty if this repository has no release yet, in which case the
  # caller falls back to 'main'. Any failure here (no releases, rate
  # limiting, a network blip) is swallowed on purpose: this is a
  # convenience default, and a release-less repo is an expected state,
  # not an error. A hard fetch failure still surfaces later, when the
  # actual template files are fetched against whichever ref was chosen.
  latest_release_tag() {
    __api_url="https://api.github.com/repos/${GITHUB_OWNER_REPO}/releases/latest"
    __body=""
    if [ "${FETCHER}" = "curl" ]; then
      __body=$(curl -fsSL "${__api_url}" 2>/dev/null) || true
    else
      __body=$(wget -qO- "${__api_url}" 2>/dev/null) || true
    fi
    printf '%s' "${__body}" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' || true
  }

  if [ -z "${__ref}" ]; then
    __resolved_ref=$(latest_release_tag)
    if [ -n "${__resolved_ref}" ]; then
      __ref="${__resolved_ref}"
    else
      __ref="main"
      echo "No published release found for ${GITHUB_OWNER_REPO}; falling back to --ref main. Pass --ref <tag> once a release exists, for a reproducible install." >&2
    fi
  fi

  REMOTE_BASE_URL="https://raw.githubusercontent.com/${GITHUB_OWNER_REPO}/${__ref}/templates"
  STAGING_DIR=$(mktemp -d)
  TEMPLATES_DIR="${STAGING_DIR}"
  mkdir -p "${TEMPLATES_DIR}/pre-commit-config"

  # Fetches templates/$1 into TEMPLATES_DIR/$1, exiting with a clear
  # message on either failure shape described above.
  fetch_required() {
    __rel="${1}"
    __not_found_message="${2}"
    __dest="${TEMPLATES_DIR}/${__rel}"
    __rc=0
    fetch_url "${REMOTE_BASE_URL}/${__rel}" "${__dest}" || __rc=$?
    if [ "${__rc}" -eq 2 ]; then
      echo "Error: ${__not_found_message}" >&2
      exit 3
    elif [ "${__rc}" -ne 0 ]; then
      echo "Error: failed to fetch ${REMOTE_BASE_URL}/${__rel} (ref '${__ref}'). Check your network connection." >&2
      exit 7
    fi
  }

  # Same as fetch_required, but a 404 is not fatal: the file is simply not
  # present at this ref. Used for templates added after some published
  # release, so that `--ref <older tag>` still installs everything that ref
  # does have instead of aborting on the one file it predates. A network
  # failure is still fatal, because that is not the same thing as absence.
  fetch_optional() {
    __rel="${1}"
    __dest="${TEMPLATES_DIR}/${__rel}"
    __rc=0
    fetch_url "${REMOTE_BASE_URL}/${__rel}" "${__dest}" || __rc=$?
    if [ "${__rc}" -eq 2 ]; then
      echo "Note: templates/${__rel} does not exist at ref '${__ref}'; skipping it." >&2
      rm -f "${__dest}"
      return 0
    elif [ "${__rc}" -ne 0 ]; then
      echo "Error: failed to fetch ${REMOTE_BASE_URL}/${__rel} (ref '${__ref}'). Check your network connection." >&2
      exit 7
    fi
  }

  fetch_required "pre-commit-config/${__template}.yaml" \
    "no template named '${__template}' at ref '${__ref}' (checked ${REMOTE_BASE_URL}/pre-commit-config/${__template}.yaml). Pass --ref <tag|branch> to fetch a different revision."
  fetch_required ".editorconfig" "could not find templates/.editorconfig at ref '${__ref}'."
  fetch_required ".cspell.json" "could not find templates/.cspell.json at ref '${__ref}'."
  fetch_required ".yamllint.yml" "could not find templates/.yamllint.yml at ref '${__ref}'."
  fetch_required ".markdownlint.yaml" "could not find templates/.markdownlint.yaml at ref '${__ref}'."
  fetch_optional ".markdown-link-check.json"
  fetch_required ".lycheeignore" "could not find templates/.lycheeignore at ref '${__ref}'."
  fetch_required "gitignore.fragment" "could not find templates/gitignore.fragment at ref '${__ref}'."

  if [ "${__community_files}" = true ]; then
    mkdir -p "${TEMPLATES_DIR}/community/.github/ISSUE_TEMPLATE"
    __not_found_suffix="at ref '${__ref}'. --community-files needs a ref that includes templates/community/; pass --ref <tag|branch> to pick a newer one."
    fetch_required "community/.github/ISSUE_TEMPLATE/bug_report.md" "could not find templates/community/.github/ISSUE_TEMPLATE/bug_report.md ${__not_found_suffix}"
    fetch_required "community/.github/ISSUE_TEMPLATE/feature_request.md" "could not find templates/community/.github/ISSUE_TEMPLATE/feature_request.md ${__not_found_suffix}"
    fetch_required "community/.github/ISSUE_TEMPLATE/question.md" "could not find templates/community/.github/ISSUE_TEMPLATE/question.md ${__not_found_suffix}"
    fetch_required "community/.github/ISSUE_TEMPLATE/config.yml" "could not find templates/community/.github/ISSUE_TEMPLATE/config.yml ${__not_found_suffix}"
    fetch_required "community/.github/PULL_REQUEST_TEMPLATE.md" "could not find templates/community/.github/PULL_REQUEST_TEMPLATE.md ${__not_found_suffix}"
    fetch_required "community/.github/FUNDING.yml" "could not find templates/community/.github/FUNDING.yml ${__not_found_suffix}"
    fetch_required "community/CODE_OF_CONDUCT.md" "could not find templates/community/CODE_OF_CONDUCT.md ${__not_found_suffix}"
    fetch_required "community/CONTRIBUTING.md" "could not find templates/community/CONTRIBUTING.md ${__not_found_suffix}"
    fetch_required "community/SECURITY.md" "could not find templates/community/SECURITY.md ${__not_found_suffix}"
  fi
fi

# --- Provision the target repo, identically regardless of mode ----------

copy_file() {
  __src="${1}"
  __dest="${2}"

  # A source that is not here at all comes from fetch_optional declining to
  # fetch a template this ref predates. Report it and move on; letting cp
  # fail into the caller's `|| true` would hide it behind a bare cp error.
  if [ ! -e "${__src}" ]; then
    echo "Skipping ${__dest}: $(basename "${__src}") is not part of this ref." >&2
    return 5
  fi

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
copy_file "${TEMPLATES_DIR}/pre-commit-config/${__template}.yaml" "${__target}/.pre-commit-config.yaml" || true
copy_file "${TEMPLATES_DIR}/.editorconfig" "${__target}/.editorconfig" || true
copy_file "${TEMPLATES_DIR}/.cspell.json" "${__target}/.cspell.json" || true
copy_file "${TEMPLATES_DIR}/.yamllint.yml" "${__target}/.yamllint.yml" || true
copy_file "${TEMPLATES_DIR}/.markdownlint.yaml" "${__target}/.markdownlint.yaml" || true
copy_file "${TEMPLATES_DIR}/.markdown-link-check.json" "${__target}/.markdown-link-check.json" || true
copy_file "${TEMPLATES_DIR}/.lycheeignore" "${__target}/.lycheeignore" || true

if [ "${__community_files}" = true ]; then
  mkdir -p "${__target}/.github/ISSUE_TEMPLATE"
  copy_file "${TEMPLATES_DIR}/community/.github/ISSUE_TEMPLATE/bug_report.md" "${__target}/.github/ISSUE_TEMPLATE/bug_report.md" || true
  copy_file "${TEMPLATES_DIR}/community/.github/ISSUE_TEMPLATE/feature_request.md" "${__target}/.github/ISSUE_TEMPLATE/feature_request.md" || true
  copy_file "${TEMPLATES_DIR}/community/.github/ISSUE_TEMPLATE/question.md" "${__target}/.github/ISSUE_TEMPLATE/question.md" || true
  copy_file "${TEMPLATES_DIR}/community/.github/ISSUE_TEMPLATE/config.yml" "${__target}/.github/ISSUE_TEMPLATE/config.yml" || true
  copy_file "${TEMPLATES_DIR}/community/.github/PULL_REQUEST_TEMPLATE.md" "${__target}/.github/PULL_REQUEST_TEMPLATE.md" || true
  copy_file "${TEMPLATES_DIR}/community/.github/FUNDING.yml" "${__target}/.github/FUNDING.yml" || true
  copy_file "${TEMPLATES_DIR}/community/CODE_OF_CONDUCT.md" "${__target}/CODE_OF_CONDUCT.md" || true
  copy_file "${TEMPLATES_DIR}/community/CONTRIBUTING.md" "${__target}/CONTRIBUTING.md" || true
  copy_file "${TEMPLATES_DIR}/community/SECURITY.md" "${__target}/SECURITY.md" || true
fi

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

if [ "${__community_files}" = true ]; then
  cat <<EOF
  4. The community files carry generic placeholders (e.g. OWNER/REPO,
    [INSERT CONTACT METHOD]). Search CODE_OF_CONDUCT.md and SECURITY.md
    for bracketed tokens and fill them in before publishing.
EOF
fi
