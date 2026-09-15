# Development container for pre-commit-checklists: everything this
# repository's hooks and self-test suite (tests/run_tests.sh) need, on top of
# the organization's shared base image. See .devcontainer/README.md for how to
# start it and why each run argument is there.
#
# The base image is pinned by digest. BASE_IMAGE is a build argument only so a
# change to the base image can be tested against this repository before it is
# published.
ARG BASE_IMAGE=ghcr.io/ivan-pinatti-labs/devcontainer-base@sha256:254847ed4c81b8480c94a91d8d8ca7001c2a99cc868df2ac3e5d69e66d750ae0
FROM ${BASE_IMAGE}

USER 0:0

# python3-yaml: the selectors phase of tests/run_tests.sh imports yaml. It
#   comes from apt because Ubuntu marks its Python as externally managed, so
#   pip refuses to install into it.
# pipx: detect-secrets is not packaged by Ubuntu at all (checked 2026-09-15).
#
# Versions are unpinned for the same reason as in the base image: Ubuntu ships
# security fixes by moving a package's version within a release.
# hadolint ignore=DL3008
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    pipx \
    python3-yaml \
  && rm -rf /var/lib/apt/lists/*

# The shell and commit phases call the detect-secrets CLI directly. Pinned to
# the same version as the Yelp/detect-secrets rev in
# checklists/checklist-security-credentials.yaml, so the CLI the tests run and
# the hook the checklist runs agree.
#
# HOME is set to root's own for this one step. The base image sets HOME to
# /home/dev for every step, so pipx running as root otherwise creates
# /home/dev/.local owned by root, and podman, running as dev, can then no
# longer create its storage there ("mkdir /home/dev/.local/share/containers:
# permission denied"), which breaks every hook that starts a container.
#
# DL3064 is a false positive here: it flags "SECRETS" in the argument name,
# but the value is a version number, not sensitive data.
# hadolint ignore=DL3064
ARG DETECT_SECRETS_VERSION=1.5.0
RUN HOME=/root PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin \
  PIPX_MAN_DIR=/usr/local/share/man \
  pipx install "detect-secrets==${DETECT_SECRETS_VERSION}"

USER 1000:1000

# Every tool .tool-versions pins, installed from that file. It is copied to a
# scratch directory and removed afterwards rather than left in the home
# directory, where asdf would treat it as a global fallback: a tool this
# repository does not pin should be missing in this container, not silently
# supplied.
COPY --chown=1000:1000 .tool-versions /tmp/tool-versions/.tool-versions
WORKDIR /tmp/tool-versions
RUN while read -r tool _; do asdf plugin add "${tool}"; done < .tool-versions \
  && asdf install \
  && rm -rf /tmp/tool-versions

WORKDIR /workspace
