#!/usr/bin/env python3
"""
Push extracted WhatsApp data rows to Google Sheets via the gog CLI.

Usage:
  python3 push_to_sheets.py --data '<json>'
  echo '<json>' | python3 push_to_sheets.py

JSON payload format:
  {
    "sheet_id": "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms",  // or env GOOGLE_SHEET_ID
    "tab": "WhatsApp Data",   // or env GOOGLE_SHEET_TAB (default: WhatsApp Data)
    "rows": [
      ["2025-06-01", "+237640087638", "Alice Kamga", "invoice", "5000 XAF",
       "Send receipt", "2025-06-05", "Payment confirmed for order #42", ""]
    ]
  }

Column order (A–I) matches data_schema.md:
  A=date, B=sender, C=contact_name, D=data_type, E=amount,
  F=action_item, G=due_date, H=message_preview, I=notes
"""

import argparse
import json
import os
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description="Append rows to Google Sheets via gog")
    parser.add_argument("--data", help="JSON payload as string (alternative to stdin)")
    parser.add_argument("--sheet-id", help="Google Sheet ID (overrides GOOGLE_SHEET_ID env)")
    parser.add_argument("--tab", help="Sheet tab name (overrides GOOGLE_SHEET_TAB env)")
    args = parser.parse_args()

    raw = args.data if args.data else sys.stdin.read()
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"ERROR: Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(1)

    sheet_id = args.sheet_id or payload.get("sheet_id") or os.environ.get("GOOGLE_SHEET_ID", "").strip()
    tab = args.tab or payload.get("tab") or os.environ.get("GOOGLE_SHEET_TAB", "WhatsApp Data").strip()
    rows = payload.get("rows", [])

    if not sheet_id:
        print(
            "ERROR: No sheet_id provided.\n"
            "  Set GOOGLE_SHEET_ID env var, pass it in the JSON payload, or use --sheet-id.",
            file=sys.stderr,
        )
        sys.exit(1)

    if not rows:
        print("ERROR: No rows to append.", file=sys.stderr)
        sys.exit(1)

    # Sanitise: ensure every row is a list of strings
    sanitised = []
    for row in rows:
        if not isinstance(row, list):
            print(f"ERROR: Each row must be a list, got: {type(row)}", file=sys.stderr)
            sys.exit(1)
        sanitised.append([str(v) if v is not None else "" for v in row])

    range_notation = f"{tab}!A:Z"
    values_json = json.dumps(sanitised)

    cmd = [
        "gog", "sheets", "append",
        sheet_id, range_notation,
        "--values-json", values_json,
        "--insert", "INSERT_ROWS",
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"ERROR: gog sheets append failed (exit {result.returncode}):\n{result.stderr}", file=sys.stderr)
        sys.exit(1)

    print(f"OK: Appended {len(sanitised)} row(s) to '{tab}' in sheet {sheet_id}")
    if result.stdout.strip():
        print(result.stdout)


if __name__ == "__main__":
    main()
