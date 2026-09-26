# This repository's L2 image: where its hooks and its self-test suite run,
# with no credentials (see docs/LAYERS.md in devcontainer-airlock). It adds
# what the terraform and tofu checklists call by name to the shared L2 image.
#
# Build context is the repository root, for the vendored OpenTofu key.
ARG L2_IMAGE=ghcr.io/ivan-pinatti-labs/airlock-l2@sha256:fc340eb19b1c98dd346d4ef79c0f739668e464b40a0150ad704b6f5cb2069a43
# hadolint ignore=DL3006
FROM ${L2_IMAGE}
USER 0:0

# cosign verifies tflint below; pipx installs detect-secrets, which the
# self-test suite calls directly.
# hadolint ignore=DL3008
RUN apt-get update \
  && apt-get install -y --no-install-recommends cosign pipx \
  && rm -rf /var/lib/apt/lists/*

# DL3064 is a false positive here: it flags "SECRETS" in the argument name,
# but the value is a version number, not sensitive data.
# hadolint ignore=DL3064
ARG DETECT_SECRETS_VERSION=1.5.0
RUN HOME=/root PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin \
  PIPX_MAN_DIR=/usr/local/share/man \
  pipx install "detect-secrets==${DETECT_SECRETS_VERSION}"

# terraform from HashiCorp's signed repository; the base image already
# checked its key.
# hadolint ignore=DL3008
RUN printf '%s\n' \
      'deb [arch=amd64 signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com resolute main' \
      > /etc/apt/sources.list.d/hashicorp.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends terraform \
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
# HOME=/root on this step, as on the pipx step above. The L2 image already
# sets it, and L2 runs everything as root with /root on a per repository
# volume where pre-commit keeps its environments, so saying it here keeps
# what gpg (~/.gnupg), cosign (~/.sigstore), `tofu --version`
# (~/.terraform.d) and `tflint --version` (~/.cache/tflint) leave behind in
# the same place even if a base image ever moves HOME.
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

USER 1000:1000
WORKDIR /workspace
