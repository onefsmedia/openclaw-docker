#!/usr/bin/env python3
"""
Create a ClickUp task from extracted WhatsApp data via the ClickUp REST API.

Usage:
  python3 push_to_clickup.py --data '<json>'
  echo '<json>' | python3 push_to_clickup.py

JSON payload format:
  {
    "list_id":    "901234567",          // or env CLICKUP_LIST_ID
    "api_token":  "pk_...",             // or env CLICKUP_API_TOKEN
    "name":       "Follow up with Alice re: Invoice #42",
    "description": "WhatsApp from +237640087638 on 2025-06-01:\\nPayment confirmed 5000 XAF.",
    "due_date":   1748822400000,        // Unix ms timestamp (optional)
    "priority":   3,                    // 1=urgent 2=high 3=normal 4=low (optional)
    "tags":       ["whatsapp"],         // optional
    "assignees":  [123456]              // optional ClickUp user IDs
  }

Prints the created task ID and URL on success.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request


CLICKUP_API_BASE = "https://api.clickup.com/api/v2"


def main():
    parser = argparse.ArgumentParser(description="Create a ClickUp task from WhatsApp data")
    parser.add_argument("--data", help="JSON payload as string (alternative to stdin)")
    parser.add_argument("--list-id", help="ClickUp list ID (overrides CLICKUP_LIST_ID env)")
    parser.add_argument("--api-token", help="ClickUp API token (overrides CLICKUP_API_TOKEN env)")
    args = parser.parse_args()

    raw = args.data if args.data else sys.stdin.read()
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"ERROR: Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(1)

    list_id = args.list_id or payload.get("list_id") or os.environ.get("CLICKUP_LIST_ID", "").strip()
    api_token = args.api_token or payload.get("api_token") or os.environ.get("CLICKUP_API_TOKEN", "").strip()

    if not list_id:
        print(
            "ERROR: No list_id provided.\n"
            "  Set CLICKUP_LIST_ID env var, pass it in the JSON payload, or use --list-id.",
            file=sys.stderr,
        )
        sys.exit(1)

    if not api_token:
        print(
            "ERROR: No api_token provided.\n"
            "  Set CLICKUP_API_TOKEN env var, pass it in the JSON payload, or use --api-token.",
            file=sys.stderr,
        )
        sys.exit(1)

    # Build task body — only include fields that were provided
    task: dict = {
        "name": payload.get("name") or "WhatsApp capture",
        "description": payload.get("description") or "",
    }

    if "due_date" in payload and payload["due_date"] is not None:
        task["due_date"] = int(payload["due_date"])
        task["due_date_time"] = True

    if "priority" in payload and payload["priority"] is not None:
        priority = int(payload["priority"])
        if priority not in (1, 2, 3, 4):
            print("ERROR: priority must be 1 (urgent), 2 (high), 3 (normal), or 4 (low).", file=sys.stderr)
            sys.exit(1)
        task["priority"] = priority

    if payload.get("tags"):
        task["tags"] = [str(t) for t in payload["tags"]]

    if payload.get("assignees"):
        task["assignees"] = [int(uid) for uid in payload["assignees"]]

    url = f"{CLICKUP_API_BASE}/list/{list_id}/task"
    body = json.dumps(task).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Authorization": api_token,
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req) as resp:
            result = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8", errors="replace")
        print(f"ERROR: ClickUp API returned HTTP {e.code}:\n{error_body}", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"ERROR: Network error: {e.reason}", file=sys.stderr)
        sys.exit(1)

    task_id = result.get("id", "?")
    task_name = result.get("name", task["name"])
    task_url = result.get("url", "")

    print(f"OK: Created ClickUp task '{task_name}' (id={task_id})")
    if task_url:
        print(f"URL: {task_url}")

    # Output JSON for downstream parsing (agent can extract task_id for the sheet)
    print(json.dumps({"id": task_id, "name": task_name, "url": task_url}))


if __name__ == "__main__":
    main()
