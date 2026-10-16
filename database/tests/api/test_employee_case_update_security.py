#!/usr/bin/env python3
"""Local-only security regression tests for controlled case updates."""

import getpass
import json
import os
import urllib.error
import urllib.request

CASE_ID = "c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea"
OTHER_ORG_EMPLOYEE_ID = "e5bce736-bcce-4a04-b720-a7b90837e371"
EMPLOYEE_A_ID = "f1af6f09-7032-428d-a176-7bbfa6dba747"


def main():
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "")

    if url != "http://127.0.0.1:54321" or not key:
        print("STOP: Explicit local Supabase configuration required.")
        return 2

    def post(path, payload, token=None):
        headers = {"apikey": key, "Content-Type": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"

        request = urllib.request.Request(
            url + path,
            data=json.dumps(payload).encode(),
            headers=headers,
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response)

    def login(email):
        password = getpass.getpass(f"{email} password (hidden): ")
        return post(
            "/auth/v1/token?grant_type=password",
            {"email": email, "password": password},
        )["access_token"]

    def expect_rejection(label, payload, token, expected_codes):
        try:
            post("/rest/v1/rpc/update_employee_case", payload, token)
        except urllib.error.HTTPError as error:
            details = json.loads(error.read().decode())
            if details.get("code") in expected_codes:
                print(f"PASS: {label}")
                return
            raise AssertionError(
                f"{label}: unexpected HTTP {error.code}, "
                f"SQLSTATE {details.get('code')}"
            ) from error
        raise AssertionError(f"{label}: request was unexpectedly accepted")

    print("=== EMPLOYEE CASE UPDATE SECURITY REGRESSION ===")

    token_a = None
    lock_token = None

    try:
        token_a = login("employee-a@madzera-test.example")
        token_b = login("employee-b@madzera-test.example")
        print("PASS: Both employees authenticated.")

        expect_rejection(
            "Invalid lock token rejected",
            {
                "p_case_id": CASE_ID,
                "p_lock_token": "00000000-0000-0000-0000-000000000000",
                "p_priority": "high",
            },
            token_a,
            {"42501"},
        )

        session = post(
            "/rest/v1/rpc/open_case_session",
            {"p_case_id": CASE_ID},
            token_a,
        )

        if not session or not session[0].get("acquired"):
            raise AssertionError("Employee A could not acquire the case lock")

        lock_token = session[0]["lock_token"]
        print("PASS: Employee A acquired the case lock.")

        base = {"p_case_id": CASE_ID, "p_lock_token": lock_token}

        expect_rejection(
            "Another employee cannot use the lock",
            {**base, "p_priority": "high"},
            token_b,
            {"42501"},
        )

        expect_rejection(
            "Contradictory assignment rejected",
            {
                **base,
                "p_assigned_user_id": EMPLOYEE_A_ID,
                "p_clear_user": True,
            },
            token_a,
            {"22023"},
        )

        expect_rejection(
            "Cross-organisation assignment rejected",
            {**base, "p_assigned_user_id": OTHER_ORG_EMPLOYEE_ID},
            token_a,
            {"23503"},
        )

    except (AssertionError, urllib.error.URLError, KeyError, ValueError) as error:
        print(f"FAIL: {type(error).__name__}: {error}")
        return 1

    finally:
        if token_a and lock_token:
            try:
                post(
                    "/rest/v1/rpc/close_case_session",
                    {"p_case_id": CASE_ID, "p_lock_token": lock_token},
                    token_a,
                )
                print("PASS: Case session closed.")
            except Exception as error:
                print(f"FAIL: Session cleanup failed: {type(error).__name__}")
                return 1

    print("PASS: All case-update security checks completed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
