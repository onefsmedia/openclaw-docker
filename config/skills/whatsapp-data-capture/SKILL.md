---
name: whatsapp-data-capture
description: >
  Monitor WhatsApp conversations and extract structured data points to record in Google
  Sheets and/or ClickUp. Use when: (1) a WhatsApp message contains actionable data such
  as amounts, invoices, orders, lead info, dates, tasks, or contact details; (2) the user
  asks to log, capture, record, sync, or track data from WhatsApp; (3) a WhatsApp
  conversation contains information that should be organised and stored.
  Triggers on phrases like: "log this", "capture from WhatsApp", "add to sheet",
  "create task from WhatsApp", "record this conversation", "track this data",
  "save to ClickUp", "sync WhatsApp data". Also triggers when messages contain invoice
  amounts, order confirmations, payment receipts, meeting requests, or lead information
  received via WhatsApp.
---

# WhatsApp Data Capture

Extract structured data from WhatsApp messages and push to Google Sheets and/or ClickUp.

## Prerequisites (one-time setup)

**Google Sheets** — uses `gog` CLI (see `gog` skill for full OAuth setup):
```bash
brew install steipete/tap/gogcli
gog auth credentials /path/to/client_secret.json
gog auth add you@gmail.com --services sheets
export GOOGLE_SHEET_ID=<your-sheet-id>
export GOOGLE_SHEET_TAB="WhatsApp Data"   # optional, default: WhatsApp Data
```

**ClickUp** — REST API, no extra binary needed:
- Personal API token: https://app.clickup.com/settings/apps → _API Token_
```bash
export CLICKUP_API_TOKEN=pk_...
export CLICKUP_LIST_ID=<list-id>   # from ClickUp list URL: /l/{list_id}/
```

**WhatsApp history search** (batch/historical only):
```bash
brew install steipete/tap/wacli && wacli auth
```
Inbound WhatsApp messages arrive automatically via OpenClaw — no extra setup needed.

---

## Workflow

### Step 1 — Identify messages to process

**Real-time (inbound):** Message content is already in context — use it directly.

**Historical / batch:**
```bash
wacli messages search "invoice" --chat <jid> --limit 20 --json
wacli chats list --limit 20 --query "name"   # find JIDs
```

### Step 2 — Extract data points

Read `references/data_schema.md` for full field definitions and extraction guidelines.

Extract these fields from each relevant message:

| Field | Description |
|---|---|
| `date` | Message date (YYYY-MM-DD) |
| `sender` | Phone number or contact name |
| `contact_name` | Person or company name mentioned |
| `data_type` | `invoice` / `order` / `lead` / `task` / `meeting` / `payment` / `other` |
| `amount` | Monetary value with currency (e.g., `5000 XAF`) |
| `action_item` | Specific action required, if any |
| `due_date` | Deadline from text (YYYY-MM-DD), if any |
| `message_preview` | First 120 characters of message |
| `notes` | Additional relevant context |

One message can yield multiple rows (e.g., an invoice with a delivery task).

### Step 3 — Append to Google Sheets

```bash
python3 ~/.openclaw/skills/whatsapp-data-capture/scripts/push_to_sheets.py \
  --data '{"rows":[["<date>","<sender>","<contact_name>","<data_type>","<amount>","<action_item>","<due_date>","<message_preview>","<notes>"]]}'
```

Pass all rows in one call for batch appends: `"rows": [[...], [...], [...]]`

### Step 4 — Create ClickUp task (when action item is present)

Only create a task when there is a concrete follow-up action or deadline.  
Skip for purely informational messages.

```bash
python3 ~/.openclaw/skills/whatsapp-data-capture/scripts/push_to_clickup.py \
  --data '{"name":"<task title>","description":"<context>","due_date":<unix-ms>,"priority":3,"tags":["whatsapp"]}'
```

Priority: `1` = urgent · `2` = high · `3` = normal · `4` = low  
`due_date` is optional (Unix millisecond timestamp).

Record the returned ClickUp task ID in column J of the corresponding sheet row.

### Step 5 — Confirm (optional)

When the user is chatting on WhatsApp and expects a reply:
> "Logged — [brief summary]. Sheet row added[, ClickUp task created: _name_]."

---

## Tips

- **Sheets only** for passive/informational data (no action needed).
- **Sheets + ClickUp** when there is a follow-up, deadline, or assignment.
- Normalise amounts: always include currency (`"5000 XAF"`, `"100 USD"`).
- Convert relative dates ("next Monday", "in 3 days") to absolute YYYY-MM-DD.
- Both scripts accept JSON via `--data` flag or stdin: `echo '<json>' | python3 ...`
- See `references/clickup_api.md` for full ClickUp REST API reference.
