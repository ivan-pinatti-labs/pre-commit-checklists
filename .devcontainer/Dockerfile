# Development container for pre-commit-checklists: everything this
# repository's hooks and self-test suite (tests/run_tests.sh) need, on top of
# the organization's shared base image. See .devcontainer/README.md for how to
# start it and why each run argument is there.
#
# The base image is pinned by digest. BASE_IMAGE is a build argument only so a
# change to the base image can be tested against this repository before it is
# published.
ARG BASE_IMAGE=ghcr.io/ivan-pinatti-labs/devcontainer-base@sha256:db75fbbf8972f6f1d7746c06238fbf15a387e224947e0e0dd5bf4d5fe3844d0b
FROM ${BASE_IMAGE}

USER 0:0

# python3-yaml: the selectors phase of tests/run_tests.sh imports yaml. It
#   comes from apt because Ubuntu marks its Python as externally managed, so
#   pip refuses to install into it.
# pipx: detect-secrets is not packaged by Ubuntu at all (checked 2026-09-15).
# cosign: verifies tflint's keyless signature further down. Ubuntu packages
#   it (2.6.2 on 26.04), which is what makes that verification possible
#   without a chicken and egg problem: verifying a downloaded cosign would
#   itself need a cosign.
#
# Versions are unpinned for the same reason as in the base image: Ubuntu ships
# security fixes by moving a package's version within a release.
# hadolint ignore=DL3008
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    cosign \
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

# The tools this repository's checklists shell out to, from signed
# repositories.
#
# gh and pre-commit and shellcheck: gh from GitHub's own repository, whose
# signing key the base image checks against a fingerprint and installs
# without enabling, so the source entry below is what opts in. pre-commit and
# shellcheck come from Ubuntu, which packages both.
#
# terraform from HashiCorp's own repository, for checklist-dev-terraform's
# terraform-fmt and terraform-validate hooks. `resolute` is Ubuntu 26.04's
# codename, which HashiCorp publishes a component for; a base image moving to
# a newer Ubuntu has to check that the component exists first, because apt
# fails closed on a missing one rather than falling back.
#
# Versions are deliberately unpinned, and this layer is therefore rolling
# rather than reproducible. The digest above fixes what this builds on and
# says nothing about what apt resolves on top.
# hadolint ignore=DL3008
RUN printf '%s\n' \
      'deb [arch=amd64 signed-by=/usr/share/keyrings/github-cli.gpg] https://cli.github.com/packages stable main' \
      > /etc/apt/sources.list.d/github-cli.list \
  && printf '%s\n' \
      'deb [arch=amd64 signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com resolute main' \
      > /etc/apt/sources.list.d/hashicorp.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    gh \
    pre-commit \
    shellcheck \
    terraform \
  && rm -rf /var/lib/apt/lists/*

# OpenTofu, for checklist-dev-tofu, alongside Terraform for
# checklist-dev-terraform. Both ship, because a consumer uses one or the
# other and this library should not decide which.
#
# This is the one place in the organization that installs a release archive
# rather than a package, and it is a deliberate exception rather than drift.
# OpenTofu's apt repository exists, but its index is signed by packagecloud,
# the hosting provider, and not by OpenTofu: measured 2026-09-20, the
# InRelease file verifies against the packagecloud key and OpenTofu's own key
# cannot check it at all. Listing both keys in signed-by=, which OpenTofu's
# own instructions do, would only widen what apt accepts, since apt takes a
# signature from any listed key and OpenTofu's provably never signs that
# index.
#
# The release archive is the one path where OpenTofu itself vouches for the
# bytes: the project signs SHA256SUMS with the key vendored under
# .devcontainer/keyrings/, and the archive is checked against that file. So
# the trust root here is OpenTofu, not its hosting provider, which is the
# whole reason this exception is worth making.
#
# The cost, stated rather than hidden: tofu is not a dpkg entry, so it does
# not appear in this image's SBOM and no vulnerability scanner here reports
# on it. The same is true of tflint below, for a different reason.
#
# The key is vendored and checked against its fingerprint before anything is
# executed, exactly as the base image does for its apt keys, so a swapped key
# file fails the build rather than signing whatever arrives.
#
# HOME=/root on this step, for the same reason the pipx step above sets it:
# the base image sets HOME=/home/dev for every build step, so anything run as
# root that touches its home directory leaves a root owned directory there
# that the dev account cannot then write. gpg creates ~/.gnupg, cosign
# creates ~/.sigstore, `tofu --version` creates ~/.terraform.d and
# `tflint --version` creates ~/.cache/tflint. Any one of them is enough to
# break pre-commit, which needs ~/.cache/pre-commit.
# renovate: datasource=github-releases depName=opentofu/opentofu
ARG TOFU_VERSION=1.12.6
COPY .devcontainer/keyrings/opentofu.asc /tmp/keyrings/opentofu.asc
WORKDIR /tmp
# hadolint ignore=DL4006
RUN set -eu; \
  export HOME=/root; \
  want="E3E6E43D84CB852EADB0051D0C0AF313E5FD9F80"; \
  got="$(gpg --show-keys --with-colons /tmp/keyrings/opentofu.asc \
    | awk -F: '$1=="pub"{p=1;next} $1=="fpr"&&p{print $10;p=0;next} {p=0}' \
    | sort | paste -sd, -)"; \
  if [ "${got}" != "${want}" ]; then \
    echo "opentofu.asc: primary certificates ${got:-none} do not match the reviewed set ${want}" >&2; \
    exit 1; \
  fi; \
  gpg --dearmor < /tmp/keyrings/opentofu.asc > /tmp/keyrings/opentofu.gpg; \
  base="https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}"; \
  curl -fsSL -o SHA256SUMS "${base}/tofu_${TOFU_VERSION}_SHA256SUMS"; \
  curl -fsSL -o SHA256SUMS.gpgsig "${base}/tofu_${TOFU_VERSION}_SHA256SUMS.gpgsig"; \
  curl -fsSL -o "tofu_${TOFU_VERSION}_linux_amd64.tar.gz" \
    "${base}/tofu_${TOFU_VERSION}_linux_amd64.tar.gz"; \
  gpg --no-default-keyring --keyring /tmp/keyrings/opentofu.gpg \
    --verify SHA256SUMS.gpgsig SHA256SUMS; \
  grep "tofu_${TOFU_VERSION}_linux_amd64.tar.gz" SHA256SUMS \
    | sha256sum --check --strict -; \
  tar -xzf "tofu_${TOFU_VERSION}_linux_amd64.tar.gz" -C /usr/local/bin tofu; \
  chmod 0755 /usr/local/bin/tofu; \
  rm -rf /tmp/keyrings /tmp/SHA256SUMS /tmp/SHA256SUMS.gpgsig \
    "/tmp/tofu_${TOFU_VERSION}_linux_amd64.tar.gz"; \
  tofu --version

# tflint, from its release archive, verified against the signature its own
# project publishes.
#
# No distribution packages tflint and its project publishes no apt
# repository, so this is the second and last release download in this
# organization, alongside OpenTofu above. It earns the exception the same
# way: the project itself vouches for the bytes.
#
# tflint signs with cosign keyless rather than GPG, which is stronger than a
# detached GPG signature rather than weaker. The signature is bound to the
# GitHub Actions workflow identity that produced it, through a Fulcio issued
# certificate and a Rekor transparency log entry, so verification asserts
# which workflow in which repository built this artifact rather than only
# that somebody holding a key signed it. The identity is pinned below rather
# than left open: without --certificate-identity-regexp and
# --certificate-oidc-issuer, cosign would accept a valid signature from any
# identity at all, which verifies nothing useful.
#
# Extraction uses python3 rather than unzip, because the base image dropped
# unzip along with asdf and tflint ships only a zip. python3's zipfile does
# not preserve the executable bit, hence the chmod.
#
# HOME=/root for the same reason as the OpenTofu step above.
# renovate: datasource=github-releases depName=terraform-linters/tflint
ARG TFLINT_VERSION=0.64.0
# hadolint ignore=DL4006
RUN set -eu; \
  export HOME=/root; \
  base="https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}"; \
  for f in checksums.txt checksums.txt.keyless.sig checksums.txt.pem tflint_linux_amd64.zip; do \
    curl -fsSL -o "${f}" "${base}/${f}"; \
  done; \
  cosign verify-blob \
    --certificate checksums.txt.pem \
    --signature checksums.txt.keyless.sig \
    --certificate-identity-regexp "^https://github.com/terraform-linters/tflint" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    checksums.txt; \
  grep "tflint_linux_amd64.zip" checksums.txt | sha256sum --check --strict -; \
  python3 -m zipfile -e tflint_linux_amd64.zip /tmp/tflint-out/; \
  install -m 0755 /tmp/tflint-out/tflint /usr/local/bin/tflint; \
  rm -rf /tmp/tflint-out /tmp/checksums.txt /tmp/checksums.txt.keyless.sig \
    /tmp/checksums.txt.pem /tmp/tflint_linux_amd64.zip; \
  tflint --version

# Nothing root owned may survive under the dev account's home. The steps
# above all set HOME=/root, so this should find nothing; it runs anyway,
# because a step added later that forgets would otherwise produce a container
# that only fails when somebody tries to use it.
# The grep is the last command in its pipeline, so its exit status is the
# pipeline's with or without pipefail, which Podman's default OCI format
# ignores anyway because it ignores SHELL. See the base image's Dockerfile.
#
# The first version of this ended `&& ... && exit 1 || true`, where the
# trailing `|| true` swallowed its own `exit 1` along with everything else,
# so the guard always succeeded and a root owned path would still have
# shipped. A guard that cannot fail is worse than no guard, because it reads
# as protection. CodeRabbit caught it on pull request 53.
# hadolint ignore=DL4006
RUN set -eu; \
  find /home/dev ! -user dev -exec chown dev:dev {} + ; \
  if find /home/dev ! -user dev | grep -q .; then \
    echo "root owned paths survived under /home/dev:" >&2; \
    find /home/dev ! -user dev -printf '  %u %p\n' >&2; \
    exit 1; \
  fi

USER 1000:1000

WORKDIR /workspace
