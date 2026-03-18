# OpenClaw Docker

A production-ready Docker deployment for [OpenClaw](https://openclaw.ai) — an AI agent gateway with WhatsApp integration, Google Sheets sync, and ClickUp task automation. Runs on a VPS behind host nginx with Let's Encrypt TLS via certbot.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Repository Structure](#repository-structure)
3. [Prerequisites](#prerequisites)
4. [VPS Deployment](#vps-deployment)
5. [Environment Variables](#environment-variables)
6. [openclaw.json — Gateway Configuration](#openclawjson--gateway-configuration)
7. [AI Model Selection](#ai-model-selection)
8. [OpenRouter Auth Profiles](#openrouter-auth-profiles)
9. [WhatsApp Channel Setup](#whatsapp-channel-setup)
10. [Agents](#agents)
11. [Skills — whatsapp-data-capture](#skills--whatsapp-data-capture)
12. [ClickUp Integration](#clickup-integration)
13. [Google Sheets Integration](#google-sheets-integration)
14. [Mission Control Dashboard](#mission-control-dashboard)
15. [Watchdog Script](#watchdog-script)
16. [Updating](#updating)
17. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
Internet
    │
    ▼
nginx (TLS termination — Let's Encrypt via certbot)
 ├── :80    → 301 redirect to HTTPS
 ├── :443   → Gateway (OpenClaw API + WebSocket + Control UI)
 └── :9443  → Gateway (alternate port, same upstream)
                │
                ├── WhatsApp Plugin (Baileys — multi-device)
                │       └── Inbound messages → Agent routing
                │
                └── Agent Runtime
                        └── main agent  ← receives all WhatsApp DMs & groups
                                │
                                └── Skills
                                      └── whatsapp-data-capture
                                            ├── push_to_sheets.py  → Google Sheets (via gog CLI)
                                            └── push_to_clickup.py → ClickUp REST API
```

- TLS is handled by host **nginx** (certbot Let's Encrypt), not by the container.
- The gateway container binds to `127.0.0.1:9090` only — never exposed directly to the internet.
- The Control UI is served by the gateway itself at `https://<domain>/`.
- No Studio container — agent management is done via the gateway Control UI or CLI.

---

## Repository Structure

```
openclaw-docker/
├── Dockerfile                   # Gateway image (Node 22 + Python 3 + gog + wacli)
├── docker-compose.yml           # Gateway service only
├── entrypoint.sh                # Container startup + first-run bootstrap
├── .env.example                 # Template for all required environment variables
├── .dockerignore                # Excludes config/ and workspace/ from build context
│
├── nginx/
│   └── openclaw.conf                  # nginx reverse-proxy example config
│
├── dashboard/
│   └── index.html               # Mission Control — real-time gateway status UI
│
└── config/                      # Runtime state (gitignored except example files)
    ├── openclaw.json.example    # Gateway config template (copy to openclaw.json)
    ├── auth-profiles.json.example  # OpenRouter API key template
    ├── agents/                  # Per-agent auth and session data (gitignored)
    ├── credentials/             # WhatsApp E2E keys (gitignored)
    ├── identity/                # Device identity (gitignored)
    ├── devices/                 # Paired/pending devices (gitignored)
    ├── memory/                  # Agent memory SQLite database (gitignored)
    ├── logs/                    # Gateway, error, and watchdog logs (gitignored)
    ├── media/inbound/           # Received media files (gitignored)
    ├── completions/             # Shell completions for the openclaw CLI
    ├── canvas/index.html        # Canvas UI served by the gateway
    ├── scripts/
    │   └── watchdog.sh          # WhatsApp connection monitor + auto-restart
    └── skills/
        └── whatsapp-data-capture/
            ├── SKILL.md         # Skill definition loaded by the agent
            ├── SETUP.md         # One-time setup instructions
            ├── DOCUMENTATION.md # Full user guide
            ├── references/
            │   ├── clickup_api.md
            │   └── data_schema.md
            └── scripts/
                ├── push_to_sheets.py
                └── push_to_clickup.py
```

---

## Prerequisites

On the **VPS** (Ubuntu 24.04 recommended):
- Docker Engine ≥ 24 and Docker Compose V2
- nginx installed (`apt install nginx`)
- certbot installed (`apt install certbot python3-certbot-nginx`)
- Ports `80`, `443`, `9443` open in your firewall
- A subdomain DNS `A` record pointing to the server's public IP
- An [OpenRouter](https://openrouter.ai) account and API key

On your **local machine** (for pairing WhatsApp):
- `openclaw` CLI installed (`npm install -g openclaw`)

---

## VPS Deployment

### 1. Clone the repo

```bash
git clone https://github.com/onefsmedia/openclaw-docker.git /opt/openclaw-docker
cd /opt/openclaw-docker
```

### 2. Create your `.env` file

```bash
cp .env.example .env
nano .env
```

Fill in at minimum `DOMAIN`, `OPENCLAW_GATEWAY_TOKEN`, and `OPENROUTER_API_KEY`.

### 3. Create the gateway config

```bash
cp config/openclaw.json.example config/openclaw.json
nano config/openclaw.json
```

Replace `<your-domain>` in `allowedOrigins` with your actual subdomain.

### 4. Set correct permissions

The container runs as uid 1000. Set ownership before starting:

```bash
mkdir -p /opt/openclaw-docker/config
chown -R 1000:1000 /opt/openclaw-docker/config
```

### 5. Build and start the gateway

```bash
docker compose up -d --build
docker compose ps          # status should be "healthy"
docker compose logs openclaw --tail 50
```

### 6. Issue a TLS certificate with certbot

```bash
certbot --nginx -d <your-subdomain.yourdomain.com>
```

Certbot automatically modifies the nginx config to add SSL. Alternatively, set up the config manually using the template in `nginx/`.

### 7. Configure nginx

Copy the nginx example config into place:

```bash
cp nginx/openclaw.conf \
   /etc/nginx/sites-available/<your-domain>.conf

# Edit: replace all <domain> placeholders with your actual domain
nano /etc/nginx/sites-available/<your-domain>.conf

ln -s /etc/nginx/sites-available/<your-domain>.conf \
      /etc/nginx/sites-enabled/

nginx -t && systemctl reload nginx
```

### 8. Set up the OpenRouter API key

```bash
mkdir -p /opt/openclaw-docker/config/agents/main/agent
cp config/auth-profiles.json.example \
   config/agents/main/agent/auth-profiles.json

# Replace the placeholder with your real OpenRouter API key
nano config/agents/main/agent/auth-profiles.json

chown -R 1000:1000 /opt/openclaw-docker/config/agents
docker compose restart
```

### 9. Pair WhatsApp

```bash
docker exec -it openclaw-gateway openclaw gateway pair
```

Scan the QR code with your WhatsApp phone:  
**Settings → Linked Devices → Link a Device**

### 10. Verify

Open `https://<your-domain>/` — the Control UI should load. Enter your `OPENCLAW_GATEWAY_TOKEN` when prompted.

---

## Environment Variables

Copy `.env.example` to `.env` and fill in the values.

| Variable | Required | Description |
|----------|----------|-------------|
| `DOMAIN` | **Yes** | Your subdomain (e.g. `app.yourdomain.com`). Must match your DNS A record. |
| `OPENCLAW_GATEWAY_TOKEN` | **Yes** | Auth token for the gateway API and Control UI. Generate with `openssl rand -hex 24`. |
| `OPENROUTER_API_KEY` | **Yes** | API key from [openrouter.ai/keys](https://openrouter.ai/keys). Used in `auth-profiles.json`. |
| `OPENCLAW_GATEWAY_PORT` | No | Internal gateway port. Default: `9090`. |
| `GOOGLE_SHEET_ID` | No | Google Sheet ID for the WhatsApp data capture skill. |
| `GOOGLE_SHEET_TAB` | No | Tab name in the Sheet. Default: `WhatsApp Data`. |
| `GOG_ACCOUNT` | No | Gmail address for the `gog` CLI (avoids `--account` flag). |
| `CLICKUP_API_TOKEN` | No | ClickUp personal API token (`pk_...`). |
| `CLICKUP_LIST_ID` | No | ClickUp list ID where tasks are created. |

> **Security:** Never commit `.env` to git. The `.gitignore` already excludes it.

---

## openclaw.json — Gateway Configuration

`config/openclaw.json` is the main gateway config file. Copy from `config/openclaw.json.example` and adjust for your deployment.

Key sections:

### `agents`

```json
"agents": {
  "defaults": {
    "model": { "primary": "openrouter/<model-id>" }
  }
}
```

Model is an OpenRouter model ID string. See [AI Model Selection](#ai-model-selection) below.

### `channels`

```json
"channels": {
  "whatsapp": {
    "enabled": true,
    "dmPolicy": "open",
    "allowFrom": ["*"],
    "groupPolicy": "open",
    "debounceMs": 0,
    "mediaMaxMb": 50
  }
}
```

- `dmPolicy`: `"open"` (accept from everyone), `"contacts"` (contacts only), `"deny"` (block all DMs)
- `allowFrom`: phone number whitelist, or `["*"]` for all
- `groupPolicy`: `"open"`, `"invited"`, or `"deny"`

### `gateway`

```json
"gateway": {
  "mode": "local",
  "controlUi": {
    "allowedOrigins": ["https://<your-domain>"],
    "allowInsecureAuth": true
  },
  "auth": { "mode": "token" },
  "trustedProxies": ["172.19.0.0/16", "172.18.0.0/16", "127.0.0.1"]
}
```

- `auth.mode: "token"` — all API calls require `Authorization: Bearer <token>` header
- `trustedProxies` — Docker bridge network CIDRs + localhost (for nginx)
- `allowedOrigins` — must include your HTTPS domain for the Control UI to load

---

## AI Model Selection

The model is set in `config/openclaw.json` under `agents.defaults.model.primary`.  
Format: `openrouter/<provider>/<model-slug>` or `openrouter/<model-slug>`.

### Current production model

```json
"model": { "primary": "openrouter/nvidia/nemotron-3-super-120b-a12b:free" }
```

This model is **completely free** ($0 per token), with 262K context window.

### Other recommended free models on OpenRouter

| Model ID | Context | Notes |
|----------|---------|-------|
| `openrouter/nvidia/nemotron-3-super-120b-a12b:free` | 262K | Current production — large, capable |
| `openrouter/microsoft/mai-ds-r1:free` | 163K | Strong reasoning |
| `openrouter/deepseek/deepseek-r1:free` | 164K | Excellent reasoning |
| `openrouter/qwen/qwen3-235b-a22b:free` | 131K | High quality |
| `openrouter/meta-llama/llama-4-maverick:free` | 1M | Massive context |

Browse all models: [openrouter.ai/models](https://openrouter.ai/models)

### Applying a model change

Edit `config/openclaw.json` then:

```bash
docker compose restart
```

> **Important:** The model string must exactly match the OpenRouter slug. An invalid model ID returns a `400` error.

---

## OpenRouter Auth Profiles

The gateway reads API keys from `config/agents/main/agent/auth-profiles.json`.  
This file is **gitignored** — it must be created manually on each server.

### Format

```json
{
  "version": 1,
  "profiles": {
    "openrouter-default": {
      "type": "api_key",
      "provider": "openrouter",
      "key": "<sk-or-v1-your-openrouter-api-key>"
    }
  }
}
```

See `config/auth-profiles.json.example` for the full template.

### Setup commands

```bash
mkdir -p /opt/openclaw-docker/config/agents/main/agent
cp config/auth-profiles.json.example \
   /opt/openclaw-docker/config/agents/main/agent/auth-profiles.json
nano /opt/openclaw-docker/config/agents/main/agent/auth-profiles.json
# Paste your OpenRouter API key

# Fix ownership (container runs as uid 1000)
chown -R 1000:1000 /opt/openclaw-docker/config/agents
docker compose restart
```

### Troubleshooting auth errors

| Error | Cause | Fix |
|-------|-------|-----|
| `No API key found for provider openrouter` | `auth-profiles.json` missing or wrong path | Place file at `config/agents/main/agent/auth-profiles.json` |
| `EACCES permission denied` | File owned by root, container is uid 1000 | `chown -R 1000:1000 config/agents` |
| `400 Invalid model` | Model ID doesn't exist on OpenRouter | Verify exact slug at openrouter.ai/models |
| `402 billing error` | OpenRouter credits exhausted | Switch to a `:free` model or top up credits |

---

## WhatsApp Channel Setup

### First-time pairing

```bash
docker exec -it openclaw-gateway openclaw gateway pair
```

Scan the QR code within 60 seconds using WhatsApp on your phone:  
**Settings → Linked Devices → Link a Device**

### Check connection status

```bash
docker exec -it openclaw-gateway openclaw channels status
```

Expected output:
```
whatsapp  connected  +237XXXXXXXXX
```

### List and approve devices

```bash
docker exec -it openclaw-gateway openclaw devices list
docker exec -it openclaw-gateway openclaw devices approve <device-id>
```

### Re-pair after logout

```bash
docker exec -it openclaw-gateway openclaw gateway unpair
docker exec -it openclaw-gateway openclaw gateway pair
```

### Channel configuration options

In `config/openclaw.json` under `channels.whatsapp`:

| Field | Type | Description |
|-------|------|-------------|
| `enabled` | bool | Enable/disable the WhatsApp channel entirely |
| `dmPolicy` | `open` / `contacts` / `deny` | Who can message the agent in DMs |
| `allowFrom` | `["*"]` or `["+2376..."]` | Phone number whitelist |
| `groupPolicy` | `open` / `invited` / `deny` | Group message handling |
| `debounceMs` | number | Wait N ms for follow-up messages before processing (0 = instant) |
| `mediaMaxMb` | number | Maximum incoming media file size to process |

---

## Agents

An **agent** in OpenClaw is an autonomous AI worker with its own workspace, memory, tool permissions, and skills. The `main` agent handles all WhatsApp messages by default.

### Agent directory layout (inside the container at `/data`)

```
/data/
├── agents/
│   └── main/
│       └── agent/
│           ├── auth-profiles.json   # OpenRouter API key (gitignored)
│           └── models.json          # Optional per-agent model override
├── workspace/                       # Agent's working directory for file operations
└── skills/                       # Skill definitions loaded by agents
    └── whatsapp-data-capture/
        └── SKILL.md              # The skill prompt loaded into agent context
```

### Changing the LLM model

Edit `agents.defaults.model.primary` in `config/openclaw.json`:

```json
"model": { "primary": "openrouter/nvidia/nemotron-3-super-120b-a12b:free" }
```

Then restart: `docker compose restart`

---

## Skills — whatsapp-data-capture

A **skill** is a markdown file (`SKILL.md`) that the agent loads into its context. It tells the agent when to activate, what to extract, and which scripts to call.

The `whatsapp-data-capture` skill listens for WhatsApp messages containing structured data (invoices, payments, orders, leads, meetings) and automatically:
1. Extracts structured fields using AI reasoning
2. Appends rows to a Google Sheet
3. Creates ClickUp tasks when action items are present

### How it triggers

The agent activates the skill when it detects:
- Monetary amounts (invoices, payments, sales figures)
- Order or delivery confirmations
- Task or follow-up requests
- Meeting or appointment requests

Or when you explicitly say:
- `"Log this to the sheet"`
- `"Create a task from this message"`
- `"Save to ClickUp"`

### Data fields extracted per message

| Field | Column | Example |
|-------|--------|---------|
| `date` | A | `2026-03-18` |
| `sender` | B | `+237640087638` |
| `contact_name` | C | `Alice Kamga` |
| `data_type` | D | `invoice` / `payment` / `lead` / `order` / `meeting` / `task` / `other` |
| `amount` | E | `5000 XAF` |
| `action_item` | F | `Send receipt by Friday` |
| `due_date` | G | `2026-03-20` |
| `message_preview` | H | First 120 characters |
| `notes` | I | Additional context |
| `clickup_task_id` | J | `abc123xyz` (if task created) |

### Skill setup (one-time on VPS)

Ensure the following environment variables are set in `.env`:

```
GOOGLE_SHEET_ID=<your-sheet-id>
GOOGLE_SHEET_TAB=WhatsApp Data
CLICKUP_API_TOKEN=pk_...
CLICKUP_LIST_ID=<your-list-id>
```

---

## ClickUp Integration

1. Log in to ClickUp → **Settings → Apps → API Token** → copy token (`pk_...`)
2. Set in `.env`: `CLICKUP_API_TOKEN=pk_...`
3. Get your list's ID from its URL: `/l/<LIST_ID>/`
4. Set in `.env`: `CLICKUP_LIST_ID=<id>`

### When tasks are created vs skipped

| Message type | Sheet row | ClickUp task |
|---|---|---|
| Contains action item or deadline | ✅ | ✅ |
| Informational only (no action) | ✅ | ❌ |

---

## Google Sheets Integration

### Setup

The skill uses the `gog` CLI to write to Google Sheets without requiring a service account.

**One-time setup:**

```bash
# 1. Enable Google Sheets API in Google Cloud console
# 2. Create OAuth client ID (Desktop app), download client_secret.json

# 3. Authenticate gog
gog auth credentials /path/to/client_secret.json
gog auth add you@gmail.com --services sheets

# 4. Create spreadsheet, rename tab to "WhatsApp Data"
#    Add headers in row 1: Date | Sender | Contact Name | Data Type |
#    Amount | Action Item | Due Date | Message Preview | Notes | ClickUp Task ID
```

Set in `.env`:
```
GOOGLE_SHEET_ID=<id-from-sheet-url>
GOOGLE_SHEET_TAB=WhatsApp Data
GOG_ACCOUNT=you@gmail.com
```

---

## Mission Control Dashboard

A real-time status dashboard is served at `https://<your-domain>/dashboard/`.

It displays gateway connection status, agent activity, WhatsApp channel health, and message counters. Enter `OPENCLAW_GATEWAY_TOKEN` when prompted on first load.

---

## Watchdog Script

`config/scripts/watchdog.sh` monitors the WhatsApp connection and restarts the gateway if disconnected.

```bash
# Run inside the container (background)
docker exec -d openclaw-gateway bash /data/scripts/watchdog.sh
```

Logs: `config/logs/watchdog.log`

---

## Updating

### Update the gateway image

```bash
docker compose build openclaw --no-cache
docker compose up -d openclaw
```

### Update nginx config

Edit the file in `/etc/nginx/sites-available/` then:

```bash
nginx -t && systemctl reload nginx
```

### Renew TLS certificates

Certbot renews automatically via a systemd timer. To renew manually:

```bash
certbot renew
systemctl reload nginx
```

---

## Troubleshooting

### WhatsApp not connecting after deploy

```bash
docker exec -it openclaw-gateway openclaw channels status
# If not connected:
docker exec -it openclaw-gateway openclaw gateway pair
```

### TLS certificate not issued

- Confirm DNS A record points to the correct VPS IP
- Confirm port 80 is open (Let's Encrypt HTTP-01 challenge)
- Run: `certbot --nginx -d <your-domain>` and check output

### No API key found for provider openrouter

- Ensure `config/agents/main/agent/auth-profiles.json` exists with the correct format
- Check file ownership: `ls -la config/agents/main/agent/`
- Fix: `chown -R 1000:1000 /opt/openclaw-docker/config/agents`

### 400 Invalid model

The model ID in `openclaw.json` does not match exactly. Verify at [openrouter.ai/models](https://openrouter.ai/models) and update:

```json
"primary": "openrouter/nvidia/nemotron-3-super-120b-a12b:free"
```

### 402 billing error

OpenRouter credits exhausted. Switch to a free model:

```json
"primary": "openrouter/nvidia/nemotron-3-super-120b-a12b:free"
```

### 401 errors on gateway API

The `OPENCLAW_GATEWAY_TOKEN` in `.env` must match the token the gateway was started with. Regenerate with `openssl rand -hex 24`, update `.env` and restart.

### ClickUp tasks not created

Common causes:
- `CLICKUP_API_TOKEN` not set or expired → re-copy from [app.clickup.com/settings/apps](https://app.clickup.com/settings/apps)
- `CLICKUP_LIST_ID` wrong → re-check the ClickUp list URL

### Google Sheets not updating

```bash
docker exec -it openclaw-gateway gog auth list
# If not authenticated:
docker exec -it openclaw-gateway gog auth add you@gmail.com --services sheets
```

Check `GOOGLE_SHEET_ID` is the correct ID from the spreadsheet URL.

### View live logs

```bash
docker compose logs -f openclaw         # gateway logs
tail -f config/logs/gateway.log         # direct gateway log
tail -f config/logs/watchdog.log        # watchdog events
```

### Check nginx proxy

```bash
nginx -t                                # test config syntax
systemctl status nginx                  # service status
tail -f /var/log/nginx/error.log        # nginx errors
```
