#!/usr/bin/env python3

"""Verify that an employee cannot see another organisation's cases."""

import getpass
import json
import os
import urllib.error
import urllib.request


def main():
    print("=== CASE QUEUE TENANT ISOLATION TEST ===")

    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "")

    if url != "http://127.0.0.1:54321" or not key:
        print("STOP: This test requires local Supabase.")
        return 2

    own_case_id = "c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea"
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

        print("PASS: Employee A authenticated.")

        cases = post(
            "/rest/v1/rpc/get_case_queue",
            {},
            auth["access_token"],
        )

        if not isinstance(cases, list):
            print("FAIL: Unexpected queue response.")
            return 1

        case_ids = {case["case_id"] for case in cases}

        own_visible = own_case_id in case_ids
        other_hidden = other_case_id not in case_ids

        print("Queue entries:", len(cases))
        print(
            ("PASS" if own_visible else "FAIL")
            + ": Own organisation case visible."
        )
        print(
            ("PASS" if other_hidden else "FAIL")
            + ": Other organisation case hidden."
        )

        if not (own_visible and other_hidden):
            return 1

        print("PASS: Queue tenant isolation verified.")
        return 0

    except urllib.error.HTTPError as error:
        print(f"FAIL: API returned HTTP {error.code}.")
        return 1

    except (urllib.error.URLError, KeyError, ValueError) as error:
        print(f"FAIL: {type(error).__name__}.")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
