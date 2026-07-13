#!/usr/bin/env bash
# Install Chunk CLI and SSH identity for sidecar validation on Cursor Cloud Agent VMs.
set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin"
mkdir -p "${INSTALL_DIR}"

case "$(uname -m)" in
  x86_64) PLATFORM="Linux_x86_64" ;;
  aarch64|arm64) PLATFORM="Linux_arm64" ;;
  *)
    echo "setup-chunk: unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "setup-chunk: jq is required" >&2
  exit 1
fi

VERSION="$(curl -fsSL https://api.github.com/repos/CircleCI-Public/chunk-cli/releases/latest | jq -r .tag_name)"
TARBALL="chunk-cli_${PLATFORM}.tar.gz"
URL="https://github.com/CircleCI-Public/chunk-cli/releases/download/${VERSION}/${TARBALL}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

curl -fsSL "${URL}" | tar -xzf - -C "${tmpdir}"
install -m 755 "${tmpdir}/chunk" "${INSTALL_DIR}/chunk"

export PATH="${INSTALL_DIR}:${PATH}"

identity="${HOME}/.ssh/chunk_ai"
if [[ ! -f "${identity}" ]]; then
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"
  ssh-keygen -t ed25519 -f "${identity}" -N "" -C "chunk-sidecar" >/dev/null
fi

chunk config set useSSHIdentityFile true

echo "chunk $(chunk --version 2>/dev/null || true)"
echo "ssh key: ${identity}"
