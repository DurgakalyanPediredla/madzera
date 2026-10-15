#!/usr/bin/env python3

"""Verify authenticated employees cannot directly read cases."""

import getpass
import json
import os
import urllib.error
import urllib.request


def main():
    print("=== DIRECT CASE READ SECURITY TEST ===")

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

        case_request = urllib.request.Request(
            f"{url}/rest/v1/cases?select=id&limit=1",
            headers={
                "apikey": api_key,
                "Authorization": f"Bearer {token}",
            },
            method="GET",
        )

        try:
            with urllib.request.urlopen(case_request, timeout=20) as response:
                print(f"FAIL: Direct case read returned HTTP {response.status}.")
                return 1

        except urllib.error.HTTPError as error:
            if error.code == 403:
                print("PASS: Direct case read blocked with HTTP 403.")
                return 0

            print(f"FAIL: Unexpected HTTP {error.code}.")
            return 1

    except urllib.error.HTTPError as error:
        print(f"FAIL: Authentication returned HTTP {error.code}.")
        return 1

    except (urllib.error.URLError, KeyError, ValueError):
        print("FAIL: Authentication or connection error.")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
