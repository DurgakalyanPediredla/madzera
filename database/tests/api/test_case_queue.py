#!/usr/bin/env python3

"""Verify authenticated employees can access the authorised case queue."""

import getpass
import json
import os
import urllib.error
import urllib.request


def main():
    print("=== AUTHORISED CASE QUEUE TEST ===")

    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    api_key = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "")

    if not url or not api_key:
        print("SKIP: Supabase configuration is missing.")
        return 2

    email = input("Test employee email: ").strip()
    password = getpass.getpass("Password (hidden): ")

    login_request = urllib.request.Request(
        f"{url}/auth/v1/token?grant_type=password",
        data=json.dumps({
            "email": email,
            "password": password,
        }).encode(),
        headers={
            "apikey": api_key,
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(login_request, timeout=20) as response:
            token = json.load(response)["access_token"]

        queue_request = urllib.request.Request(
            f"{url}/rest/v1/rpc/get_case_queue",
            data=b"{}",
            headers={
                "apikey": api_key,
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            method="POST",
        )

        with urllib.request.urlopen(queue_request, timeout=20) as response:
            cases = json.load(response)

        if not isinstance(cases, list):
            print("FAIL: Case queue response is not a list.")
            return 1

        print("PASS: Authorised case queue returned HTTP 200.")
        print(f"PASS: Received {len(cases)} case queue entries.")
        return 0

    except urllib.error.HTTPError as error:
        print(f"FAIL: API returned HTTP {error.code}.")
        return 1

    except (urllib.error.URLError, KeyError, ValueError):
        print("FAIL: Authentication or API response error.")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
