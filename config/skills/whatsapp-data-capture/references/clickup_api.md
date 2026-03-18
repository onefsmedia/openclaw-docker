# ClickUp REST API Reference

## Authentication

Personal API tokens use the format `pk_...`.  
Get yours at: **https://app.clickup.com/settings/apps** → _API Token_

All requests require the header:
```
Authorization: <token>
```
Note: personal tokens are passed directly — **no "Bearer" prefix**.

---

## Create Task

**POST** `https://api.clickup.com/api/v2/list/{list_id}/task`

### Headers
```
Authorization: pk_...
Content-Type: application/json
```

### Body (all fields except `name` are optional)
```json
{
  "name": "Follow up with Alice re: Invoice #42",
  "description": "WhatsApp from +237640087638 on 2025-06-01:\nPayment confirmed 5000 XAF. Send receipt.",
  "priority": 3,
  "due_date": 1748822400000,
  "due_date_time": true,
  "tags": ["whatsapp", "invoice"],
  "assignees": [12345678]
}
```

### Priority values
| Value | Label |
|-------|-------|
| 1 | Urgent |
| 2 | High |
| 3 | Normal |
| 4 | Low |

### `due_date` format
Unix millisecond timestamp. Convert from Python:
```python
import datetime
dt = datetime.datetime(2025, 6, 5)
unix_ms = int(dt.timestamp() * 1000)   # e.g., 1749081600000
```

### Response
Returns the full task object. Key fields:
```json
{
  "id": "abc123xyz",
  "name": "Follow up with Alice...",
  "url": "https://app.clickup.com/t/abc123xyz",
  "status": { "status": "to do" }
}
```

---

## Find List IDs

**Option 1 — From the URL:**  
Open a list in ClickUp → URL contains `/l/{list_id}/`

**Option 2 — API:**
```
GET https://api.clickup.com/api/v2/space/{space_id}/list
Authorization: pk_...
```

To find `space_id`: open a Space → URL contains `/s/{space_id}/`

---

## Update Task

**PUT** `https://api.clickup.com/api/v2/task/{task_id}`

Same headers. Body includes only the fields to update:
```json
{
  "name": "Updated task name",
  "status": "in progress",
  "due_date": 1749081600000
}
```

---

## Add Comment

**POST** `https://api.clickup.com/api/v2/task/{task_id}/comment`

```json
{
  "comment_text": "Receipt sent via email on 2025-06-02.",
  "notify_all": false
}
```

---

## Error Codes

| HTTP | Meaning |
|------|---------|
| 400 | Bad request — check payload fields |
| 401 | Unauthorised — invalid or missing token |
| 403 | Forbidden — token lacks permission for this list |
| 404 | List or task not found — verify list_id / task_id |
| 429 | Rate limited — wait and retry |
