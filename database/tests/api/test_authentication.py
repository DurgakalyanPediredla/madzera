#!/usr/bin/env python3

"""Madzera authenticated API smoke test."""

import getpass
import json
import os
import urllib.error
import urllib.request


def main():
    print("=== MADZERA AUTHENTICATION TEST ===")

    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    api_key = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "")

    if not url or not api_key:
        print("SKIP: Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY.")
        return 2

    email = input("Test employee email: ").strip()
    password = getpass.getpass("Password (hidden): ")

    request = urllib.request.Request(
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
        with urllib.request.urlopen(request, timeout=20) as response:
            data = json.load(response)

        if data.get("access_token") and data.get("user", {}).get("id"):
            print("PASS: Supabase authentication succeeded.")
            print("PASS: Access token and user identity returned.")
            return 0

        print("FAIL: Authentication response was incomplete.")
        return 1

    except urllib.error.HTTPError as error:
        print(f"FAIL: Authentication returned HTTP {error.code}.")
        return 1

    except urllib.error.URLError:
        print("FAIL: Unable to connect to Supabase.")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
