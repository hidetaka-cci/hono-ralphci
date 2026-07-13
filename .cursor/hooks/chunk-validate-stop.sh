#!/usr/bin/env bash
# Cursor stop hook: drain stdin JSON, then run sidecar validation remotely.
set -euo pipefail

# Drain Cursor stop-hook stdin so a bare `chunk validate` never blocks.
cat >/dev/null

if [[ -n "${CHUNK_HOOKS_DISABLED:-}" ]] || [[ -f .chunk/hooks-disabled ]]; then
  exit 0
fi

if [[ -z "$(git status --porcelain 2>/dev/null)" ]]; then
  exit 0
fi

export PATH="${HOME}/.local/bin:${PATH}"

chunk_bin="${CHUNK_BIN:-chunk}"
if ! command -v "${chunk_bin}" >/dev/null 2>&1; then
  echo "chunk-validate-stop: chunk CLI not found; run bash .cursor/setup-chunk.sh" >&2
  exit 2
fi

identity="${HOME}/.ssh/chunk_ai"
if [[ ! -f "${identity}" ]]; then
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"
  ssh-keygen -t ed25519 -f "${identity}" -N "" -C "chunk-sidecar" >/dev/null
fi

set +e
"${chunk_bin}" validate --remote --identity-file "${identity}"
status=$?
set -e

if [[ "${status}" -eq 0 ]]; then
  exit 0
fi

cat <<'EOF'
{"followup_message":"Chunk sidecar validation failed. Read the errors above, fix the code, and continue until remote validation passes."}
EOF
exit 2
