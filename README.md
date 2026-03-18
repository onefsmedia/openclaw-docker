# OpenClaw Docker

A production-ready Docker deployment for [OpenClaw](https://openclaw.ai) — an AI agent gateway with WhatsApp integration, Google Sheets sync, and ClickUp task automation. Designed to run on a VPS with a subdomain and automatic Let's Encrypt TLS via Caddy.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Repository Structure](#repository-structure)
3. [Services](#services)
4. [Prerequisites](#prerequisites)
5. [VPS Deployment](#vps-deployment)
6. [Environment Variables](#environment-variables)
7. [openclaw.json — Gateway Configuration](#openclawjson--gateway-configuration)
8. [WhatsApp Channel Setup](#whatsapp-channel-setup)
9. [Agents](#agents)
10. [Skills — whatsapp-data-capture](#skills--whatsapp-data-capture)
11. [ClickUp Integration](#clickup-integration)
12. [Google Sheets Integration](#google-sheets-integration)
13. [Mission Control Dashboard](#mission-control-dashboard)
14. [Watchdog Script](#watchdog-script)
15. [Updating](#updating)
16. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
Internet
    │
    ▼
Caddy (TLS termination — Let's Encrypt via subdomain)
 ├── :443   → Studio (Next.js web dashboard)
 └── :9443  → Gateway (OpenClaw API + WebSocket)
                │
                ├── WhatsApp Plugin (Baileys — multi-device)
                │       └── Inbound messages → Agent routing
                │
                └── Agent Runtime
                        ├── main agent  ← receives all WhatsApp DMs & groups
                        └── test-agent  ← isolated sandbox
                                │
                                └── Skills
                                      └── whatsapp-data-capture
                                            ├── push_to_sheets.py  → Google Sheets (via gog CLI)
                                            └── push_to_clickup.py → ClickUp REST API
```

All services run inside an isolated Docker bridge network (`openclaw-net`). The gateway and studio are hardened with non-root users, dropped capabilities, and read-only root filesystems.

---

## Repository Structure

```
openclaw-docker/
├── Dockerfile                  # Gateway image (Node 22 + Python 3 + gog + wacli)
├── docker-compose.yml          # All services: gateway, studio, caddy
├── Caddyfile                   # Reverse proxy — auto TLS for subdomain
├── entrypoint.sh               # Container startup + first-run bootstrap
├── .env.example                # Template for all required environment variables
├── .dockerignore               # Excludes config/ and workspace/ from build context
│
├── dashboard/
│   └── index.html              # Mission Control — real-time gateway status UI
│
└── config/                     # Runtime state (gitignored except skills/scripts)
    ├── openclaw.json            # Main gateway + agent + channel configuration
    ├── agents/                  # Per-agent auth and session data (gitignored)
    ├── credentials/             # WhatsApp E2E keys (gitignored)
    ├── identity/                # Device identity (gitignored)
    ├── devices/                 # Paired/pending devices (gitignored)
    ├── memory/                  # Agent memory SQLite database (gitignored)
    ├── logs/                    # Gateway, error, and watchdog logs (gitignored)
    ├── media/inbound/           # Received media files (gitignored)
    ├── cron/jobs.json           # Scheduled job definitions
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
            │   ├── clickup_api.md    # ClickUp REST API reference
            │   └── data_schema.md   # Extracted field definitions
            └── scripts/
                ├── push_to_sheets.py   # Appends rows to Google Sheets
                └── push_to_clickup.py  # Creates tasks via ClickUp API
```

---

## Services

### `openclaw` — Gateway

The core AI agent runtime. Handles all incoming WhatsApp messages, routes them to the configured agent, executes skills, and exposes a REST/WebSocket API on port `9090`.

- **Image:** Built from `Dockerfile` (Node 22 slim + Python 3 + `gog` + `wacli`)
- **Internal port:** `9090`
- **State directory:** `./config` mounted at `/data`
- **User:** `node` (uid 1000) — non-root
- **Memory limit:** 2 GB / 1 CPU

### `studio` — Web Dashboard

The OpenClaw Studio UI — a Next.js app for managing agents, viewing conversations, handling approvals, and configuring the gateway from a browser.

- **Image:** Built from `~/openclaw-studio` (separate repo)
- **Internal port:** `3000`
- **User:** uid 1000 — non-root
- **Memory limit:** 1 GB / 1 CPU

### `caddy` — Reverse Proxy

Caddy handles TLS termination using automatic Let's Encrypt certificates. It reads the subdomain from the `DOMAIN` environment variable.

- **Image:** `caddy:2-alpine`
- **Ports:** `80` (redirect to HTTPS), `443` (Studio), `9443` (Gateway WSS)
- **Routes:**
  - `https://{DOMAIN}` → Studio on port 3000
  - `https://{DOMAIN}:9443` → Gateway on port 9090
  - `https://{DOMAIN}:9443/dashboard/` → Mission Control static dashboard

---

## Prerequisites

On the **VPS**:
- Docker Engine ≥ 24 and Docker Compose V2
- Ports `80`, `443`, `9443` open in your firewall
- A subdomain DNS `A` record pointing to the server's public IP (e.g. `app.yourdomain.com`)
- The `openclaw-studio` source cloned alongside this repo (or set `OPENCLAW_STUDIO_DIR` in `.env`)

On your **local machine** (for pairing WhatsApp):
- `openclaw` CLI installed (`npm install -g openclaw`)

---

## VPS Deployment

### 1. Clone the repos

```bash
git clone https://github.com/onefsmedia/openclaw-docker.git
cd openclaw-docker
```

If you also need to build Studio locally:
```bash
git clone https://github.com/onefsmedia/openclaw-studio.git ~/openclaw-studio
```

### 2. Create your `.env` file

```bash
cp .env.example .env
nano .env
```

Fill in every value — at minimum `DOMAIN`, `OPENCLAW_GATEWAY_TOKEN`, and `STUDIO_ACCESS_TOKEN`. See [Environment Variables](#environment-variables) for details.

### 3. Point DNS

Create an `A` record for your subdomain pointing to the VPS public IP **before** starting Caddy, so Let's Encrypt can issue the certificate.

### 4. Start all services

```bash
docker compose up -d --build
```

Caddy will automatically obtain a TLS certificate for your subdomain on first start (requires port 80 to be reachable for the ACME HTTP-01 challenge).

### 5. Verify

```bash
docker compose ps          # all three services should be Up
docker compose logs caddy  # watch for "certificate obtained successfully"
docker compose logs openclaw --tail 50
```

Visit `https://your-subdomain.com` — the Studio login screen should appear.

### 6. Pair WhatsApp

```bash
docker exec -it openclaw-gateway openclaw gateway pair
```

Scan the printed QR code with your WhatsApp phone → **Linked Devices → Link a Device**.

After pairing, the gateway is fully operational and all inbound WhatsApp messages are routed to the configured agent.

---

## Environment Variables

Copy `.env.example` to `.env` and fill in the values below.

| Variable | Required | Description |
|----------|----------|-------------|
| `DOMAIN` | **Yes** | Your subdomain (e.g. `app.yourdomain.com`). Caddy uses this for TLS. |
| `OPENCLAW_GATEWAY_TOKEN` | **Yes** | Auth token for the gateway API. Generate with `openssl rand -hex 24`. Must match `gateway.auth.token` in `openclaw.json`. |
| `STUDIO_ACCESS_TOKEN` | **Yes** | Protects the Studio UI when bound to `0.0.0.0`. Generate with `openssl rand -hex 24`. |
| `OPENCLAW_STUDIO_DIR` | No | Path to the openclaw-studio source. Default: `~/openclaw-studio`. |
| `OPENCLAW_GATEWAY_URL` | No | WebSocket URL the Studio browser uses to reach the gateway. Default: `wss://${DOMAIN}:9443`. |
| `GOOGLE_SHEET_ID` | No | Google Sheet ID for the WhatsApp data capture skill. |
| `GOOGLE_SHEET_TAB` | No | Tab name in the Sheet. Default: `WhatsApp Data`. |
| `GOG_ACCOUNT` | No | Gmail address for the `gog` CLI (avoids `--account` flag). |
| `CLICKUP_API_TOKEN` | No | ClickUp personal API token (`pk_...`). |
| `CLICKUP_LIST_ID` | No | ClickUp list ID where tasks are created. |

> **Security:** Never commit `.env` to git. The `.gitignore` already excludes it.

---

## openclaw.json — Gateway Configuration

`config/openclaw.json` is the main configuration file. It is created automatically on first container start by `entrypoint.sh` if missing. Edit it to customise agents, channels, and gateway behaviour.

Key sections:

### `agents`

```json
"agents": {
  "defaults": {
    "model": { "primary": "openrouter/qwen/qwen3-coder:free" },
    "compaction": { "mode": "safeguard" }
  },
  "list": [
    { "id": "main" },
    {
      "id": "test-agent",
      "name": "Test Agent",
      "tools": {
        "alsoAllow": ["group:runtime", "group:web", "group:fs"]
      }
    }
  ]
}
```

Each agent has an `id`. The `main` agent is the default and handles all whatsapp messages unless a binding routes to another agent.

### `channels`

```json
"channels": {
  "whatsapp": {
    "enabled": true,
    "dmPolicy": "open",
    "allowFrom": ["*"],
    "groupPolicy": "open",
    "debounceMs": 0,
    "mediaMaxMb": 1
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
  "auth": {
    "mode": "trusted-proxy",
    "token": "<your-token>",
    "trustedProxy": { "userHeader": "X-Remote-User" }
  },
  "trustedProxies": ["172.24.0.0/16"]
}
```

`mode: "trusted-proxy"` means Caddy injects the `X-Remote-User` header — no bearer token needed from the browser side.

### `bindings`

```json
"bindings": [
  {
    "type": "route",
    "agentId": "main",
    "match": { "channel": "whatsapp" }
  }
]
```

All whatsapp messages are routed to the `main` agent. You can add additional bindings to route specific phone numbers or groups to different agents.

---

## WhatsApp Channel Setup

### First-time pairing

```bash
# Inside the running container
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

### Re-pair after logout

If rejected or logged out, unpair first then re-pair:

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
| `configWrites` | bool | Allow the agent to write back to this config |

---

## Agents

An **agent** in OpenClaw is an autonomous AI worker with its own workspace, memory, tool permissions, and skills. Each agent processes messages routed to it, uses its configured LLM, and can execute skills.

### Agent directory layout (inside the container at `/data`)

```
/data/
├── agents/
│   └── main/
│       ├── agent/
│       │   ├── models.json       # Override model for this agent
│       │   └── auth.json         # API keys for this agent's LLM calls
│       └── sessions/
│           └── sessions.json     # Conversation session index
├── workspace/                    # Agent's working directory for file operations
└── skills/                       # Skill definitions loaded by agents
    └── whatsapp-data-capture/
        └── SKILL.md              # The skill prompt loaded into agent context
```

### Creating a new agent

Add an entry to `agents.list` in `openclaw.json`:

```json
{
  "id": "sales-agent",
  "name": "Sales Agent",
  "tools": {
    "alsoAllow": ["group:fs", "group:web"],
    "deny": ["tool:exec"]
  }
}
```

Then add a binding to route specific messages to it:

```json
{
  "type": "route",
  "agentId": "sales-agent",
  "match": {
    "channel": "whatsapp",
    "from": "+2376XXXXXXXX"
  }
}
```

### Changing the LLM model

Edit `agents.defaults.model.primary` in `openclaw.json`. The value is an OpenRouter model string:

```json
"model": { "primary": "openrouter/anthropic/claude-3.5-sonnet" }
```

Browse available models at [openrouter.ai/models](https://openrouter.ai/models).

### Agent memory

Each agent has persistent memory stored in `/data/memory/main.sqlite`. Memory search can be enabled per agent:

```json
"agents": {
  "defaults": {
    "memorySearch": { "enabled": true }
  }
}
```

---

## Skills — whatsapp-data-capture

A **skill** is a markdown file (`SKILL.md`) that the agent loads into its context. It tells the agent when to activate, what to extract, and which scripts to call.

The `whatsapp-data-capture` skill listens for WhatsApp messages containing structured data (invoices, payments, orders, leads, meetings) and automatically:
1. Extracts structured fields using AI reasoning
2. Appends rows to a Google Sheet
3. Creates ClickUp tasks when action items are present

### How it triggers

The agent activates the skill automatically when it detects:
- Monetary amounts (invoices, payments, sales figures)
- Order or delivery confirmations
- Task or follow-up requests
- Meeting or appointment requests
- Lead or contact enquiries

Or when you explicitly say phrases like:
- `"Log this to the sheet"`
- `"Create a task from this message"`
- `"Capture this from WhatsApp"`
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

Install `gog` inside the container (or add to `Dockerfile`):
```bash
docker exec -it openclaw-gateway pip3 install gog  # or via brew during local setup
```

Authenticate `gog` once:
```bash
gog auth credentials /path/to/client_secret.json
gog auth add you@gmail.com --services sheets
```

### Manual script usage

**Append to Google Sheets:**
```bash
python3 /data/skills/whatsapp-data-capture/scripts/push_to_sheets.py \
  --data '{
    "rows": [[
      "2026-03-18", "+237640087638", "Alice Kamga",
      "payment", "5000 XAF", "Send receipt", "2026-03-20",
      "Hi, I have made the payment for order 42", "Regular customer"
    ]]
  }'
```

**Create a ClickUp task:**
```bash
python3 /data/skills/whatsapp-data-capture/scripts/push_to_clickup.py \
  --data '{
    "name": "[invoice] Send receipt — Alice Kamga",
    "description": "WhatsApp from +237640087638 on 2026-03-18:\nPayment confirmed 5000 XAF for order #42.",
    "due_date": 1742083200000,
    "priority": 3,
    "tags": ["whatsapp", "invoice"]
  }'
```

---

## ClickUp Integration

### Authentication

ClickUp uses personal API tokens. No OAuth flow is required.

1. Log in to ClickUp
2. Go to **Settings → Apps → API Token**
3. Copy the token (format: `pk_XXXXX_...`)
4. Set it in `.env`: `CLICKUP_API_TOKEN=pk_...`

### Finding your List ID

1. Open the list in ClickUp where tasks should land
2. The URL will look like: `https://app.clickup.com/<workspace>/l/<LIST_ID>/`
3. Copy the numeric `LIST_ID`
4. Set it in `.env`: `CLICKUP_LIST_ID=901234567`

### API reference — Create Task

**Endpoint:** `POST https://api.clickup.com/api/v2/list/{list_id}/task`

**Headers:**
```
Authorization: pk_...
Content-Type: application/json
```

**Body:**
```json
{
  "name": "[invoice] Send receipt — Alice Kamga",
  "description": "Context from WhatsApp conversation...",
  "priority": 3,
  "due_date": 1742083200000,
  "due_date_time": true,
  "tags": ["whatsapp", "invoice"],
  "assignees": [12345678]
}
```

**Priority values:**

| Value | Label |
|-------|-------|
| `1` | Urgent |
| `2` | High |
| `3` | Normal |
| `4` | Low |

**Converting a date to Unix milliseconds (Python):**
```python
import datetime
dt = datetime.datetime(2026, 3, 20)
unix_ms = int(dt.timestamp() * 1000)  # e.g. 1742428800000
```

**Response:**
```json
{
  "id": "abc123xyz",
  "name": "[invoice] Send receipt — Alice Kamga",
  "url": "https://app.clickup.com/t/abc123xyz"
}
```

### Task naming convention

Tasks created by the skill follow this format:
```
[<data_type>] <action_item> — <contact_name>
```
Example: `[payment] Send receipt — Alice Kamga`

### When tasks are created vs skipped

| Message type | Sheet row | ClickUp task |
|---|---|---|
| Contains action item or deadline | ✅ | ✅ |
| Informational only (no action) | ✅ | ❌ |

---

## Google Sheets Integration

### Setup

The skill uses the `gog` CLI to write to Google Sheets without requiring a service account.

**Step 1 — Enable the Sheets API in Google Cloud:**
1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Create or select a project
3. **APIs & Services → Library** → enable **Google Sheets API**
4. **APIs & Services → Credentials → Create Credentials → OAuth client ID**
   - Application type: **Desktop app**
5. Download `client_secret.json`

**Step 2 — Authenticate gog:**
```bash
gog auth credentials /path/to/client_secret.json
gog auth add you@gmail.com --services sheets
gog auth list   # verify account is listed
```

**Step 3 — Create the Google Sheet:**
1. Create a new spreadsheet
2. Rename the tab to `WhatsApp Data`
3. Add these headers in row 1 (A–J):

| A | B | C | D | E | F | G | H | I | J |
|---|---|---|---|---|---|---|---|---|---|
| Date | Sender | Contact Name | Data Type | Amount | Action Item | Due Date | Message Preview | Notes | ClickUp Task ID |

4. Copy the Sheet ID from the URL:  
   `https://docs.google.com/spreadsheets/d/<SHEET_ID>/edit`

**Step 4 — Set env vars:**
```bash
GOOGLE_SHEET_ID=<paste-here>
GOOGLE_SHEET_TAB=WhatsApp Data
```

### How rows are appended

The script calls `gog sheets append` which always **adds new rows** — it never overwrites existing data. Multiple rows from one message are written in a single call.

---

## Mission Control Dashboard

A real-time terminal-style status dashboard is served at:

```
https://<your-domain>:9443/dashboard/
```

It displays:
- Gateway connection status (WebSocket live)
- Agent list and activity
- WhatsApp channel health
- Inbound/outbound message counters
- Memory and session statistics

The dashboard connects directly to the gateway API using the `OPENCLAW_GATEWAY_TOKEN` — enter it in the token field on first load.

---

## Watchdog Script

`config/scripts/watchdog.sh` is a shell script that monitors the WhatsApp connection and automatically restarts the gateway if it becomes disconnected.

It runs as a background loop (every 60 seconds) and:
1. Checks if the gateway process is running
2. Polls `openclaw channels status` for WhatsApp connection health
3. Attempts up to 3 reconnects via `launchctl` (macOS) or Docker restart
4. Logs all events to `config/logs/watchdog.log`

**To run on the VPS inside the container:**
```bash
docker exec -d openclaw-gateway bash /data/scripts/watchdog.sh
```

---

## Updating

### Update the gateway image

```bash
docker compose pull openclaw     # if using a registry image
# or rebuild from source:
docker compose build openclaw --no-cache
docker compose up -d openclaw
```

### Update Studio

```bash
cd ~/openclaw-studio
git pull
docker compose build studio --no-cache
docker compose up -d studio
```

### Update Caddy

```bash
docker compose pull caddy
docker compose up -d caddy
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
- Check Caddy logs: `docker compose logs caddy`

### Studio can't reach the gateway

- Check `OPENCLAW_GATEWAY_URL` in `.env` — should be `wss://<your-domain>:9443`
- Check `OPENCLAW_GATEWAY_TOKEN` matches `gateway.auth.token` in `openclaw.json`

### 401 errors on gateway API

The token in `.env` (`OPENCLAW_GATEWAY_TOKEN`) must match the value in `config/openclaw.json` under `gateway.auth.token`.

### ClickUp tasks not created

```bash
# Test the script directly:
docker exec -it openclaw-gateway python3 /data/skills/whatsapp-data-capture/scripts/push_to_clickup.py \
  --data '{"name":"test task","priority":4}'
```

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

### Gateway out of memory

Increase the memory limit in `docker-compose.yml`:
```yaml
deploy:
  resources:
    limits:
      memory: 4g
```

Then restart: `docker compose up -d openclaw`

### View live logs

```bash
docker compose logs -f openclaw       # gateway logs
docker compose logs -f studio         # studio logs
docker compose logs -f caddy          # caddy/TLS logs
tail -f config/logs/gateway.log       # direct gateway log file
tail -f config/logs/watchdog.log      # watchdog events
```
