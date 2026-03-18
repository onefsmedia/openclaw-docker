#!/bin/sh
set -e

DATA_DIR="${OPENCLAW_STATE_DIR:-/data}"

# ── First-run initialisation ──────────────────────────────────────────────────
# If no config exists in the data directory, create a minimal bootstrap config
# so `openclaw gateway run --allow-unconfigured` has something to work with.
if [ ! -f "${DATA_DIR}/openclaw.json" ]; then
    echo "[entrypoint] No config found at ${DATA_DIR}/openclaw.json"
    echo "[entrypoint] Creating minimal bootstrap configuration..."
    mkdir -p "${DATA_DIR}"
    cat > "${DATA_DIR}/openclaw.json" <<'EOFJSON'
{
  "agents": {
    "defaults": {
      "model": { "primary": "openrouter/google/gemini-2.0-flash-001" }
    }
  },
  "gateway": {
    "mode": "local",
    "controlUi": { "allowInsecureAuth": true },
    "auth": { "mode": "token" }
  },
  "channels": {
    "whatsapp": {
      "enabled": true,
      "dmPolicy": "open",
      "allowFrom": ["*"],
      "groupPolicy": "open"
    }
  },
  "plugins": {
    "enabled": true,
    "entries": { "whatsapp": { "enabled": true } }
  }
}
EOFJSON
    echo "[entrypoint] Bootstrap config written."
    echo "[entrypoint] NOTE: You will need to run 'openclaw gateway pair' to connect your WhatsApp account."
fi

# ── Inject gateway token from env ────────────────────────────────────────────
# If OPENCLAW_GATEWAY_TOKEN is set and differs from what's in the config,
# update the config file so OpenClaw uses the env-supplied token.
if [ -n "${OPENCLAW_GATEWAY_TOKEN}" ]; then
    echo "[entrypoint] OPENCLAW_GATEWAY_TOKEN is set — gateway will use token auth."
    # OpenClaw also reads --token from CLI args (passed below), so this is a no-op
    # if you prefer not to mutate the config file.
fi

# ── Skills directory ──────────────────────────────────────────────────────────
# Ensure the managed skills directory exists inside the data volume.
mkdir -p "${DATA_DIR}/skills"

GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-9090}"

# ── Print startup summary ─────────────────────────────────────────────────────
echo ""
echo "┌──────────────────────────────────────────────────"
echo "│  OpenClaw Gateway — Docker Container"
echo "│  State dir : ${DATA_DIR}"
echo "│  Port      : ${GATEWAY_PORT}"
echo "│  Node      : $(node --version)"
echo "│  OpenClaw  : $(openclaw --version 2>/dev/null || echo unknown)"
echo "│  gog       : $(gog --version 2>/dev/null || echo 'not installed')"
echo "│  wacli     : $(wacli --version 2>/dev/null || echo 'not installed')"
echo "└──────────────────────────────────────────────────"
echo ""

# ── Start the gateway ─────────────────────────────────────────────────────────
# Pass any extra arguments from the docker-compose `command:` block.
# Default: --bind lan --port 9090 --auth token --allow-unconfigured
exec openclaw gateway run \
    ${OPENCLAW_GATEWAY_TOKEN:+--token "${OPENCLAW_GATEWAY_TOKEN}"} \
    "$@"
