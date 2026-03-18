# WhatsApp Data Capture Agent — User Documentation

> **Agent:** OpenClaw + `whatsapp-data-capture` skill  
> **Purpose:** Listen to WhatsApp conversations, extract structured data points, and automatically record them to Google Sheets and ClickUp.

---

## Table of Contents

1. [Overview](#overview)
2. [How the Agent Works](#how-the-agent-works)
3. [Prerequisites & Setup](#prerequisites--setup)
4. [Triggering the Agent](#triggering-the-agent)
5. [What Data Gets Extracted](#what-data-gets-extracted)
6. [Google Sheets Output](#google-sheets-output)
7. [ClickUp Task Creation](#clickup-task-creation)
8. [Searching WhatsApp History](#searching-whatsapp-history)
9. [Example Scenarios](#example-scenarios)
10. [Environment Variables Reference](#environment-variables-reference)
11. [Script Reference](#script-reference)
12. [Troubleshooting](#troubleshooting)
13. [Limitations](#limitations)

---

## Overview

The WhatsApp Data Capture Agent is an OpenClaw skill that bridges WhatsApp and your productivity tools. When you receive a WhatsApp message containing actionable information — an invoice, a payment confirmation, a sales lead, a meeting request, or any task — the agent can:

- **Extract** structured fields from the message text using AI reasoning
- **Append a row** to a configured Google Sheet for record-keeping
- **Create a ClickUp task** when there is a follow-up action or deadline
- **Reply** on WhatsApp to confirm what was captured (optional)

OpenClaw routes your WhatsApp messages automatically. No polling or manual triggering is needed for real-time message capture.

---

## How the Agent Works

```
WhatsApp Message
      │
      ▼
OpenClaw receives inbound message (automatic)
      │
      ▼
Agent reads message + activates whatsapp-data-capture skill
      │
      ▼
Step 1: Extract structured fields
  (date, sender, contact, type, amount, action, due date, preview, notes)
      │
      ├──────────────────────────────────────────────┐
      ▼                                              ▼
Append row(s) to Google Sheets          Create ClickUp task (if action item exists)
via push_to_sheets.py + gog CLI         via push_to_clickup.py + ClickUp REST API
      │                                              │
      └──────────────────────────────────────────────┘
                          │
                          ▼
              (Optional) Confirm via WhatsApp reply
```

---

## Prerequisites & Setup

### Required

| Tool | Purpose | Install |
|------|---------|---------|
| OpenClaw | Core agent runtime | Already installed |
| `gog` CLI | Google Sheets writes | `brew install steipete/tap/gogcli` ✅ |
| Google OAuth credentials | Authenticate gog with your Sheet | See SETUP.md Step 2 |
| ClickUp API token | Create tasks | From app.clickup.com/settings/apps |

### Optional

| Tool | Purpose | Install |
|------|---------|---------|
| `wacli` | Search/sync WhatsApp history | `brew install steipete/tap/wacli` ✅ |

### Environment Variables

These must be set before the scripts will work:

```bash
export GOOGLE_SHEET_ID=<your-google-sheet-id>
export GOOGLE_SHEET_TAB="WhatsApp Data"     # optional, this is the default
export CLICKUP_API_TOKEN=pk_...
export CLICKUP_LIST_ID=<your-list-id>
```

Add to `~/.zshrc` to persist across sessions.

---

## Triggering the Agent

### Automatic (real-time inbound)

The agent activates automatically when OpenClaw receives a WhatsApp message that contains recognisable data patterns. No action required.

### Manual (you ask in a conversation)

You can instruct the agent directly in any conversation. Trigger phrases include:

| What you say | What happens |
|---|---|
| `"Log this to the sheet"` | Extracts data from current context → Sheets |
| `"Capture this from WhatsApp"` | Extracts + logs to Sheets |
| `"Create a task from this message"` | Extracts + creates ClickUp task |
| `"Record this conversation"` | Logs entire conversation data points |
| `"Add to Google Sheet"` | Appends extracted data to Sheets |
| `"Save to ClickUp"` | Creates ClickUp task from message content |
| `"Track this data"` | Sheets + ClickUp (if action item present) |
| `"Sync WhatsApp data"` | Batch-processes recent messages |

### Batch / Historical

Use `wacli` to pull historical messages and pass them to the agent:

```bash
# Search for invoices from the last 3 months
wacli messages search "invoice" --after 2025-12-01 --limit 50 --json

# Search a specific chat
wacli chats list --limit 20 --query "Alice"     # find the JID
wacli messages search "payment" --chat 237640087638@s.whatsapp.net --limit 20 --json
```

Paste the results into a conversation with the agent and ask: *"Log all of these to the sheet."*

---

## What Data Gets Extracted

The agent extracts the following fields from each message:

| Field | Column | Description | Example |
|-------|--------|-------------|---------|
| `date` | A | Message date (YYYY-MM-DD) | `2026-03-11` |
| `sender` | B | Phone number or name | `+237640087638` |
| `contact_name` | C | Person/company in message | `Alice Kamga` |
| `data_type` | D | Category of data | `invoice` |
| `amount` | E | Monetary value + currency | `5000 XAF` |
| `action_item` | F | Follow-up action required | `Send receipt` |
| `due_date` | G | Deadline (YYYY-MM-DD) | `2026-03-15` |
| `message_preview` | H | First 120 chars of message | `Hi, payment done…` |
| `notes` | I | Extra context | `Repeat customer` |
| `clickup_task_id` | J | Created task ID (if any) | `abc123xyz` |

### Data Types

| Type | Used for |
|------|---------|
| `invoice` | Invoice sent/received, billing request |
| `order` | Product or service order, delivery |
| `lead` | New contact, sales inquiry, prospect |
| `task` | General to-do, follow-up |
| `meeting` | Appointment, scheduling, calendar request |
| `payment` | Confirmed transfer, deposit, receipt |
| `other` | Anything else worth logging |

### Extraction rules

- **One message → multiple rows** when it contains multiple distinct data points
- **Amounts** are normalised with currency: `"5000 XAF"`, `"100 USD"`
- **Relative dates** are resolved to absolute: `"next Friday"` → `"2026-03-13"`
- **Action items** are identified from imperative phrases: send, call, confirm, pay, deliver, follow up

---

## Google Sheets Output

### Sheet structure

Create a sheet with tab name **`WhatsApp Data`** and these headers in row 1:

| A | B | C | D | E | F | G | H | I | J |
|---|---|---|---|---|---|---|---|---|---|
| Date | Sender | Contact Name | Data Type | Amount | Action Item | Due Date | Message Preview | Notes | ClickUp Task ID |

### How rows are added

The agent calls `push_to_sheets.py` which runs:

```bash
gog sheets append <SHEET_ID> "WhatsApp Data!A:Z" \
  --values-json '[["2026-03-11","+237640087638","Alice","invoice","5000 XAF","Send receipt","2026-03-15","Payment confirmed...","Repeat client"]]' \
  --insert INSERT_ROWS
```

Rows are always **appended** — existing data is never overwritten.

### Manual script usage

```bash
python3 ~/.openclaw/skills/whatsapp-data-capture/scripts/push_to_sheets.py \
  --data '{
    "rows": [[
      "2026-03-11",
      "+237640087638",
      "Alice Kamga",
      "payment",
      "5000 XAF",
      "Send receipt",
      "2026-03-15",
      "Hi, I have made the payment for order 42",
      "Regular customer"
    ]]
  }'
```

---

## ClickUp Task Creation

A ClickUp task is created **only when** the message contains:
- A concrete **action item** (something to do), OR
- A **deadline** or time-sensitive instruction

Purely informational messages (e.g., "FYI payment received") are logged to Sheets only — no task created.

### Task naming convention

```
[<data_type>] <action_item> — <contact_name>
```

Example: `[invoice] Send receipt — Alice Kamga`

### Priority mapping

| Message urgency signals | ClickUp Priority |
|------------------------|------------------|
| urgent, ASAP, immediately, emergency | 1 — Urgent |
| soon, important, high priority | 2 — High |
| Normal follow-up | 3 — Normal |
| Low urgency, optional | 4 — Low |

### Manual script usage

```bash
python3 ~/.openclaw/skills/whatsapp-data-capture/scripts/push_to_clickup.py \
  --data '{
    "name": "[invoice] Send receipt — Alice Kamga",
    "description": "WhatsApp from +237640087638 on 2026-03-11:\nPayment confirmed 5000 XAF for order #42.",
    "due_date": 1742083200000,
    "priority": 3,
    "tags": ["whatsapp", "invoice"]
  }'
```

The script prints the task ID and URL on success:
```
OK: Created ClickUp task '[invoice] Send receipt — Alice Kamga' (id=abc123xyz)
URL: https://app.clickup.com/t/abc123xyz
```

---

## Searching WhatsApp History

`wacli` is used to query historical messages (not needed for real-time capture).

### Find a contact's JID

```bash
wacli chats list --limit 20 --query "Alice"
# Returns: 237640087638@s.whatsapp.net
```

### Search messages by keyword

```bash
wacli messages search "invoice" --limit 20 --json
wacli messages search "payment" --after 2026-01-01 --json
wacli messages search "order" --chat 237640087638@s.whatsapp.net --limit 10 --json
```

### Backfill older history

```bash
wacli history backfill --chat 237640087638@s.whatsapp.net --requests 3 --count 100
```

> Your phone must be online and connected for backfill to work.

### Check connection status

```bash
wacli doctor
```

Expected healthy output:
```
STORE          /Users/mac/.wacli
LOCKED         false
AUTHENTICATED  true
CONNECTED      true
FTS5           true
```

---

## Example Scenarios

### Scenario 1 — Payment confirmation

**Incoming WhatsApp message:**
> "Hi, I've sent 5000 XAF for invoice #42. Please confirm receipt and send me the delivery date."

**Agent extracts:**

| Field | Value |
|-------|-------|
| data_type | `payment` |
| amount | `5000 XAF` |
| action_item | `Confirm receipt and send delivery date` |
| due_date | _(none specified)_ |

**Result:** 1 Sheet row + 1 ClickUp task (because action item exists)

---

### Scenario 2 — Sales lead

**Incoming WhatsApp message:**
> "Hello, I'm interested in buying 50 units of your product. Can you send me a quote by Friday?"

**Agent extracts:**

| Field | Value |
|-------|-------|
| data_type | `lead` |
| contact_name | _(sender's number/name)_ |
| action_item | `Send quote for 50 units` |
| due_date | `2026-03-13` (next Friday) |

**Result:** 1 Sheet row + 1 ClickUp task (priority: High, due Friday)

---

### Scenario 3 — Meeting request

**Incoming WhatsApp message:**
> "Can we meet on Thursday at 10am to discuss the contract?"

**Agent extracts:**

| Field | Value |
|-------|-------|
| data_type | `meeting` |
| action_item | `Schedule meeting to discuss contract` |
| due_date | `2026-03-12` (Thursday) |

**Result:** 1 Sheet row + 1 ClickUp task

---

### Scenario 4 — Informational only

**Incoming WhatsApp message:**
> "Just letting you know the package was delivered successfully."

**Agent extracts:**

| Field | Value |
|-------|-------|
| data_type | `order` |
| action_item | _(none)_ |

**Result:** 1 Sheet row only — no ClickUp task

---

### Scenario 5 — Multiple data points in one message

**Incoming WhatsApp message:**
> "I paid 10,000 XAF for the order. Please send the receipt and arrange delivery by Monday."

**Agent extracts 2 rows:**

| Row | data_type | amount | action_item | due_date |
|-----|-----------|--------|-------------|---------|
| 1 | `payment` | `10000 XAF` | `Send receipt` | — |
| 2 | `order` | — | `Arrange delivery` | `2026-03-16` (Monday) |

**Result:** 2 Sheet rows + 2 ClickUp tasks

---

## Environment Variables Reference

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `GOOGLE_SHEET_ID` | Yes (Sheets) | ID from the Sheet URL | `1BxiMVs0XRA5nFMd…` |
| `GOOGLE_SHEET_TAB` | No | Tab name (default: `WhatsApp Data`) | `"WhatsApp Data"` |
| `CLICKUP_API_TOKEN` | Yes (ClickUp) | Personal API token | `pk_12345_ABC…` |
| `CLICKUP_LIST_ID` | Yes (ClickUp) | List ID from ClickUp URL | `901234567` |
| `GOG_ACCOUNT` | No | Default gog account (avoids `--account` flag) | `you@gmail.com` |

---

## Script Reference

### `push_to_sheets.py`

Appends one or more rows to Google Sheets via the `gog` CLI.

```
~/.openclaw/skills/whatsapp-data-capture/scripts/push_to_sheets.py
```

**Flags:**

| Flag | Description |
|------|-------------|
| `--data '<json>'` | JSON payload as a string |
| `--sheet-id <id>` | Override `GOOGLE_SHEET_ID` env var |
| `--tab <name>` | Override `GOOGLE_SHEET_TAB` env var |

**JSON payload:**
```json
{
  "sheet_id": "optional-override",
  "tab": "optional-override",
  "rows": [
    ["date", "sender", "contact", "type", "amount", "action", "due_date", "preview", "notes"]
  ]
}
```

---

### `push_to_clickup.py`

Creates a task in ClickUp via the REST API.

```
~/.openclaw/skills/whatsapp-data-capture/scripts/push_to_clickup.py
```

**Flags:**

| Flag | Description |
|------|-------------|
| `--data '<json>'` | JSON payload as a string |
| `--list-id <id>` | Override `CLICKUP_LIST_ID` env var |
| `--api-token <token>` | Override `CLICKUP_API_TOKEN` env var |

**JSON payload:**
```json
{
  "name": "Task name",
  "description": "Task details",
  "due_date": 1742083200000,
  "priority": 3,
  "tags": ["whatsapp"],
  "assignees": [12345678]
}
```

**Output:**
```json
{"id": "abc123xyz", "name": "Task name", "url": "https://app.clickup.com/t/abc123xyz"}
```

---

## Troubleshooting

### `gog: command not found`
```bash
brew install steipete/tap/gogcli
```

### `wacli: AUTHENTICATED false`
```bash
wacli auth    # scan the QR code with your phone
```

### `ERROR: No sheet_id provided`
```bash
export GOOGLE_SHEET_ID=<your-sheet-id>
```

### `ERROR: ClickUp API returned HTTP 401`
Your `CLICKUP_API_TOKEN` is missing or invalid. Re-copy it from:  
https://app.clickup.com/settings/apps

### `ERROR: ClickUp API returned HTTP 404`
Your `CLICKUP_LIST_ID` is wrong. Re-check the ClickUp list URL:  
`https://app.clickup.com/<workspace>/l/**<LIST_ID>**/`

### `gog sheets append` fails with auth error
Re-run gog OAuth:
```bash
gog auth add you@gmail.com --services sheets
```

### Agent doesn't trigger automatically
- Confirm OpenClaw gateway is running: `openclaw gateway status`
- Confirm the skill is ready: `openclaw skills info whatsapp-data-capture`
- Confirm your WhatsApp number is connected in OpenClaw

---

## Limitations

- **Real-time capture** requires the OpenClaw gateway to be running at all times
- **wacli history search** requires your phone to be online for backfill operations
- **Google Sheets** requires `gog` CLI to be installed and authenticated
- **ClickUp** requires a valid personal API token and an existing list
- **Amount extraction** may be imprecise for ambiguous or mixed-currency messages; always verify high-value entries
- The skill captures data from **text messages only** — images, voice notes, and documents are not parsed (message preview will note their presence)
