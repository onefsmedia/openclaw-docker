# WhatsApp Data Capture — Setup Guide

Follow these steps in order before using the `whatsapp-data-capture` skill.

---

## Step 1 — Install the `gog` CLI (Google Sheets)

```bash
brew install steipete/tap/gogcli
gog --version   # confirm install
```

---

## Step 2 — Set up Google OAuth for Sheets

### 2a. Create a Google Cloud project and OAuth credentials

1. Go to https://console.cloud.google.com/
2. Create a new project (or select an existing one)
3. Navigate to **APIs & Services → Library**
4. Enable the **Google Sheets API**
5. Navigate to **APIs & Services → Credentials**
6. Click **Create Credentials → OAuth client ID**
   - Application type: **Desktop app**
   - Download the JSON file (e.g. `client_secret.json`)

### 2b. Authenticate gog

```bash
gog auth credentials /path/to/client_secret.json
gog auth add you@gmail.com --services sheets
gog auth list   # confirm account is listed
```

### 2c. Test Sheets access

```bash
gog sheets metadata <your-sheet-id> --json
```

---

## Step 3 — Create the Google Sheet

1. Open Google Sheets and create a new spreadsheet
2. Rename the first tab to: **`WhatsApp Data`**
3. Add these headers in row 1 (columns A–J):

| A | B | C | D | E | F | G | H | I | J |
|---|---|---|---|---|---|---|---|---|---|
| Date | Sender | Contact Name | Data Type | Amount | Action Item | Due Date | Message Preview | Notes | ClickUp Task ID |

4. Copy the Sheet ID from the URL:
   `https://docs.google.com/spreadsheets/d/**<SHEET_ID>**/edit`

---

## Step 4 — Set Google Sheets environment variables

```bash
export GOOGLE_SHEET_ID=<paste-your-sheet-id-here>
export GOOGLE_SHEET_TAB="WhatsApp Data"
```

To make these permanent, add them to your shell profile (`~/.zshrc`):

```bash
echo 'export GOOGLE_SHEET_ID=<your-sheet-id>' >> ~/.zshrc
echo 'export GOOGLE_SHEET_TAB="WhatsApp Data"' >> ~/.zshrc
source ~/.zshrc
```

---

## Step 5 — Get your ClickUp API token

1. Log in to ClickUp → go to https://app.clickup.com/settings/apps
2. Under **API Token**, click **Generate** (or copy the existing token)
3. The token starts with `pk_...`

---

## Step 6 — Find your ClickUp List ID

1. Open the ClickUp list where tasks should be created
2. Look at the URL: `https://app.clickup.com/<workspace>/l/**<LIST_ID>**/`
3. Copy the number after `/l/`

---

## Step 7 — Set ClickUp environment variables

```bash
export CLICKUP_API_TOKEN=pk_...
export CLICKUP_LIST_ID=<your-list-id>
```

Add to `~/.zshrc` to make permanent:

```bash
echo 'export CLICKUP_API_TOKEN=pk_...' >> ~/.zshrc
echo 'export CLICKUP_LIST_ID=<your-list-id>' >> ~/.zshrc
source ~/.zshrc
```

---

## Step 8 — Install `wacli` (WhatsApp history search)

> Skip this step if you only need real-time message capture (not historical search).

```bash
brew install steipete/tap/wacli
wacli auth       # scan QR code with your phone
wacli doctor     # verify connection
```

---

## Step 9 — Test the scripts

### Test Google Sheets append

```bash
python3 ~/.openclaw/skills/whatsapp-data-capture/scripts/push_to_sheets.py \
  --data '{
    "rows": [[
      "2026-03-11",
      "+237640087638",
      "Test Contact",
      "task",
      "",
      "Verify sheet write works",
      "2026-03-15",
      "Setup test message preview",
      "Skill setup test"
    ]]
  }'
```

Expected output:
```
OK: Appended 1 row(s) to 'WhatsApp Data' in sheet <sheet-id>
```

### Test ClickUp task creation

```bash
python3 ~/.openclaw/skills/whatsapp-data-capture/scripts/push_to_clickup.py \
  --data '{
    "name": "[test] WhatsApp skill setup verification",
    "description": "Test task created during skill setup.",
    "priority": 4,
    "tags": ["whatsapp", "test"]
  }'
```

Expected output:
```
OK: Created ClickUp task '[test] WhatsApp skill setup verification' (id=...)
URL: https://app.clickup.com/t/...
```

---

## Step 10 — Verify skill is active in OpenClaw

```bash
openclaw skills info whatsapp-data-capture
```

Expected output: `📦 whatsapp-data-capture ✓ Ready`

---

## Quick-Reference Checklist

- [ ] `gog` CLI installed (`gog --version`)
- [ ] Google Cloud project created with Sheets API enabled
- [ ] OAuth credentials downloaded and added via `gog auth credentials`
- [ ] Gmail account added for Sheets (`gog auth add`)
- [ ] Google Sheet created with headers in row 1, tab named "WhatsApp Data"
- [ ] `GOOGLE_SHEET_ID` env var set
- [ ] `GOOGLE_SHEET_TAB` env var set (or using default)
- [ ] ClickUp API token obtained (`pk_...`)
- [ ] ClickUp List ID identified
- [ ] `CLICKUP_API_TOKEN` env var set
- [ ] `CLICKUP_LIST_ID` env var set
- [ ] `wacli` installed and authenticated (optional — for history search)
- [ ] Sheet append test passed
- [ ] ClickUp task creation test passed
- [ ] `openclaw skills info whatsapp-data-capture` shows ✓ Ready
