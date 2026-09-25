# This repository's L2 image: where its hooks and its self-test suite run,
# with no credentials (see docs/LAYERS.md in devcontainer-images). It adds
# what the terraform and tofu checklists call by name to the shared L2 image.
#
# Build context is the repository root, for the vendored OpenTofu key.
ARG L2_IMAGE=localhost/devcontainer-l2:local
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

# OpenTofu, verified against its signing key exactly as the development
# container does (.devcontainer/Dockerfile says why each step is there).
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

# tflint, cosign verified against the project's own release workflow.
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
