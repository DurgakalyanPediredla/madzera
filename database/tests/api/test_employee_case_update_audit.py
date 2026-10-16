#!/usr/bin/env python3
"""Local-only case update and audit regression test."""

import getpass
import json
import os
import subprocess
import urllib.request

URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
KEY = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "")
CASE_ID = "c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea"

if URL != "http://127.0.0.1:54321" or not KEY:
    raise SystemExit("STOP: Explicit local Supabase configuration required.")


def post(path, payload, token=None):
    headers = {"apikey": KEY, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    request = urllib.request.Request(
        URL + path,
        data=json.dumps(payload).encode(),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def database_value(sql):
    result = subprocess.run(
        [
            "docker", "exec", "supabase_db_madzera",
            "psql", "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1",
            "-U", "postgres", "-d", "postgres", "-c", sql,
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


print("=== CASE UPDATE AND AUDIT REGRESSION ===")

password = getpass.getpass("Employee A password (hidden): ")
token = post(
    "/auth/v1/token?grant_type=password",
    {"email": "employee-a@madzera-test.example", "password": password},
)["access_token"]

print("PASS: Employee A authenticated.")

initial_priority = database_value(
    f"SELECT priority FROM public.cases WHERE id = '{CASE_ID}';"
)

if initial_priority != "medium":
    raise SystemExit(
        f"STOP: Expected original priority medium, found {initial_priority!r}."
    )

initial_count = int(database_value(
    "SELECT count(*) FROM public.case_events "
    f"WHERE case_id = '{CASE_ID}' AND event_type = 'case_updated';"
))

session = post(
    "/rest/v1/rpc/open_case_session",
    {"p_case_id": CASE_ID},
    token,
)

if not session or not session[0].get("acquired"):
    raise SystemExit("FAIL: Could not acquire case lock.")

lock_token = session[0]["lock_token"]
print("PASS: Case lock acquired.")

try:
    post(
        "/rest/v1/rpc/update_employee_case",
        {
            "p_case_id": CASE_ID,
            "p_lock_token": lock_token,
            "p_priority": "high",
        },
        token,
    )

    if database_value(
        f"SELECT priority FROM public.cases WHERE id = '{CASE_ID}';"
    ) != "high":
        raise AssertionError("Priority did not change to high")

    print("PASS: Authenticated case update succeeded.")

finally:
    try:
        post(
            "/rest/v1/rpc/update_employee_case",
            {
                "p_case_id": CASE_ID,
                "p_lock_token": lock_token,
                "p_priority": "medium",
            },
            token,
        )
        print("PASS: Original priority restored to medium.")
    finally:
        post(
            "/rest/v1/rpc/close_case_session",
            {"p_case_id": CASE_ID, "p_lock_token": lock_token},
            token,
        )
        print("PASS: Case session closed.")

final_priority = database_value(
    f"SELECT priority FROM public.cases WHERE id = '{CASE_ID}';"
)

final_count = int(database_value(
    "SELECT count(*) FROM public.case_events "
    f"WHERE case_id = '{CASE_ID}' AND event_type = 'case_updated';"
))

if final_priority != "medium":
    raise SystemExit("FAIL: Original case priority was not restored.")

if final_count != initial_count + 2:
    raise SystemExit(
        f"FAIL: Expected two new audit events, found {final_count - initial_count}."
    )

print("PASS: Both priority changes recorded in audit history.")
print("PASS: Case fixture remains at medium priority.")
