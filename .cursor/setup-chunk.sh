#!/usr/bin/env bash
# Idempotent Cloud Agent setup for Chunk CLI + SSH key used by sidecar sync.
# Wire this into .cursor/environment.json "install" (or the dashboard Update script).
set -euo pipefail

CHUNK_VERSION="${CHUNK_VERSION:-0.7.113}"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) CHUNK_ARCH="x86_64" ;;
  aarch64|arm64) CHUNK_ARCH="arm64" ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

install_chunk() {
  if command -v chunk >/dev/null 2>&1; then
    local current
    current="$(chunk --version 2>/dev/null || true)"
    if [[ "$current" == *"$CHUNK_VERSION"* ]]; then
      echo "chunk CLI already installed: $current"
      return 0
    fi
  fi

  local url="https://github.com/CircleCI-Public/chunk-cli/releases/download/v${CHUNK_VERSION}/chunk-cli_Linux_${CHUNK_ARCH}.tar.gz"
  local tmp
  tmp="$(mktemp -d)"
  echo "Installing chunk CLI v${CHUNK_VERSION} (${CHUNK_ARCH})..."
  curl -fsSL "$url" -o "${tmp}/chunk-cli.tar.gz"
  tar -xzf "${tmp}/chunk-cli.tar.gz" -C "$tmp"
  if [[ -w /usr/local/bin ]]; then
    install -m 755 "${tmp}/chunk" /usr/local/bin/chunk
  else
    sudo install -m 755 "${tmp}/chunk" /usr/local/bin/chunk
  fi
  rm -rf "$tmp"
  chunk --version
}

ensure_ssh_key() {
  local key="${HOME}/.ssh/chunk_ai"
  if [[ -f "$key" ]]; then
    echo "SSH key already exists: $key"
    return 0
  fi
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"
  ssh-keygen -t ed25519 -f "$key" -N "" -q
  echo "Generated SSH key: $key"
}

install_chunk
ensure_ssh_key

if [[ -z "${CIRCLECI_TOKEN:-${CIRCLE_TOKEN:-}}" ]]; then
  echo "Warning: CIRCLECI_TOKEN / CIRCLE_TOKEN is not set. chunk sidecar auth will fail until it is provided as a Cloud Agent secret." >&2
else
  echo "CircleCI token detected in environment."
fi

echo "Chunk Cloud Agent setup complete."
