#!/usr/bin/env bash
# Cursor Cloud Agent stop hook for chunk-sidecar validation.
# Cursor feeds JSON on stdin; draining it prevents the chunk CLI from blocking.
set -euo pipefail

cat >/dev/null

ROOT="${CURSOR_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}"
cd "$ROOT"

if ! command -v chunk >/dev/null 2>&1; then
  echo "chunk CLI not found. Run .cursor/setup-chunk.sh in the Cloud Agent install step." >&2
  exit 2
fi

SSH_KEY="${HOME}/.ssh/chunk_ai"
if [[ ! -f "$SSH_KEY" ]]; then
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -q
fi

# Ensure an active sidecar exists so --remote has a target.
if ! chunk sidecar current >/dev/null 2>&1; then
  SNAPSHOT_ID="$(
    python3 - <<'PY'
import json
from pathlib import Path
cfg = json.loads(Path(".chunk/config.json").read_text())
print(cfg.get("validation", {}).get("sidecarImage", "") or "")
PY
  )"
  if [[ -z "$SNAPSHOT_ID" ]]; then
    echo "No active sidecar and .chunk/config.json has no validation.sidecarImage." >&2
    exit 2
  fi
  chunk sidecar create --name "cursor-cloud-validate" --image "$SNAPSHOT_ID"
fi

# Register the SSH key with the active sidecar (needed for sync/validate).
chunk sidecar add-ssh-key --public-key-file "${SSH_KEY}.pub"

if ! chunk validate --remote; then
  # Exit 2 keeps the Cloud Agent turn open so it can fix failures.
  exit 2
fi

exit 0
