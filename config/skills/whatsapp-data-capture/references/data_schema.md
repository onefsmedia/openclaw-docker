# WhatsApp Data Capture — Data Schema

## Google Sheet Column Layout

Append to the sheet configured via `GOOGLE_SHEET_ID`, tab `WhatsApp Data` (or `GOOGLE_SHEET_TAB`).

| Col | Field | Example | Notes |
|-----|-------|---------|-------|
| A | `date` | `2025-06-01` | ISO 8601 (YYYY-MM-DD) |
| B | `sender` | `+237640087638` | Phone in E.164 format or contact name |
| C | `contact_name` | `Alice Kamga` | Person or company mentioned in message |
| D | `data_type` | `invoice` | See Data Types table below |
| E | `amount` | `5000 XAF` | Number + ISO currency code (or symbol) |
| F | `action_item` | `Send receipt for order #42` | The follow-up task; blank if none |
| G | `due_date` | `2025-06-05` | Deadline in YYYY-MM-DD; blank if none |
| H | `message_preview` | `Payment confirmed for inv…` | First 120 chars of the message |
| I | `notes` | `Repeat customer, 3rd order` | Extra context worth keeping |
| J | `clickup_task_id` | `abc123xyz` | Populated after ClickUp task is created |

---

## Data Types

| `data_type` | When to use |
|-------------|-------------|
| `invoice` | Invoice sent/received, billing, payment request |
| `order` | Product or service order, delivery, shipping |
| `lead` | New contact, sales prospect, business inquiry |
| `task` | General to-do, action item, follow-up |
| `meeting` | Meeting request, appointment, scheduling |
| `payment` | Confirmed transfer, deposit, receipt of payment |
| `other` | Anything else worth logging |

---

## Extraction Guidelines

### Amounts
- Normalise to `"<number> <currency>"`: `"5000 XAF"`, `"100 USD"`, `"50 EUR"`, `"2500 NGN"`
- If currency is ambiguous, use the context (country of sender, local convention)
- Omit if no monetary value is present

### Dates
- Convert relative dates to absolute: `"next Monday"` → compute actual YYYY-MM-DD
- Extract deadlines from phrases: `"by Friday"`, `"deliver in 3 days"`, `"before end of month"`
- Omit if no deadline is mentioned

### Phone numbers
- Preserve in international format: `+<country_code><number>`
- If only a local number is visible, try to resolve with known country context

### Action items
- Identify imperative phrases: `"send"`, `"call"`, `"follow up"`, `"confirm"`, `"pay"`, `"deliver"`, `"check"`, `"remind"`
- Action item = verb + object + optional deadline, e.g. `"Send invoice by Thursday"`
- Leave blank if the message is purely informational

### Multiple data points in one message
A single message can generate **multiple rows** — extract one row per distinct data point:
```
"Hi, I've paid 5000 XAF for the order. Please send the receipt and delivery by Friday."
→ Row 1: data_type=payment, amount=5000 XAF, action_item=Send receipt
→ Row 2: data_type=order, action_item=Arrange delivery, due_date=<next Friday>
```

---

## ClickUp Task Decision Rule

| Condition | Action |
|-----------|--------|
| `action_item` is non-empty | Create ClickUp task |
| `due_date` is set | Create ClickUp task (even without explicit action) |
| Purely informational message | Sheets only — no ClickUp task |

### Default ClickUp task name format
```
[<data_type>] <action_item> — <contact_name>
```
Example: `[invoice] Send receipt — Alice Kamga`

### Priority mapping
| Message urgency | Priority |
|-----------------|----------|
| Words: urgent, ASAP, emergency, immediately | 1 (urgent) |
| Words: soon, important, high priority | 2 (high) |
| Normal follow-up | 3 (normal) |
| Low urgency, FYI with action | 4 (low) |
