#!/usr/bin/env python3

"""Verify an employee cannot open another organisation's case."""

import getpass
import json
import os
import urllib.error
import urllib.request


def main():
    print("=== CROSS-TENANT CASE SESSION TEST ===")

    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "")

    if url != "http://127.0.0.1:54321" or not key:
        print("STOP: Local Supabase configuration required.")
        return 2

    other_case_id = "a1d410f6-0521-4d25-a1f1-9e0023423a14"

    password = getpass.getpass("Employee A password (hidden): ")

    def post(path, payload, token=None):
        headers = {
            "apikey": key,
            "Content-Type": "application/json",
        }

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

    try:
        auth = post(
            "/auth/v1/token?grant_type=password",
            {
                "email": "employee-a@madzera-test.example",
                "password": password,
            },
        )

        token = auth["access_token"]
        print("PASS: Employee A authenticated.")

        try:
            result = post(
                "/rest/v1/rpc/open_case_session",
                {"p_case_id": other_case_id},
                token,
            )

        except urllib.error.HTTPError as error:
            try:
                details = json.loads(error.read().decode())
            except (ValueError, UnicodeDecodeError):
                print("FAIL: Unrecognised API error response.")
                return 1

            if (
                error.code == 400
                and details.get("code") == "P0001"
                and details.get("message")
                    == "Case not found or access denied"
            ):
                print("PASS: Cross-tenant session access denied.")
                print("PASS: Expected PostgreSQL error P0001.")
                return 0

            print(
                f"FAIL: Unexpected rejection "
                f"(HTTP {error.code}, code {details.get('code')})."
            )
            return 1

        print("FAIL: Cross-tenant session request was accepted.")
        print("Response type:", type(result).__name__)
        return 1

    except urllib.error.HTTPError as error:
        print(f"FAIL: Authentication returned HTTP {error.code}.")
        return 1

    except (urllib.error.URLError, KeyError, ValueError) as error:
        print(f"FAIL: {type(error).__name__}.")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
