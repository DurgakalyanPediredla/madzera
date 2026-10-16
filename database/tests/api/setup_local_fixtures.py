#!/usr/bin/env python3

"""Provision Madzera security-test fixtures in local Supabase only."""

import json
import subprocess
import urllib.request


LOCAL_URL = "http://127.0.0.1:54321"

TEST_EMPLOYEES = {
    "employee-a@madzera-test.example": "A",
    "employee-b@madzera-test.example": "A",
    "employee-c@madzera-test.example": "B",
}


EMPLOYEE_FIXTURES = {
    "employee-a@madzera-test.example": {
        "id": "f1af6f09-7032-428d-a176-7bbfa6dba747",
        "full_name": "Test Employee A",
        "organisation_id": "0a316877-23d4-4dc3-b0ed-350208d68fb3",
        "role": "agent",
    },
    "employee-b@madzera-test.example": {
        "id": "ba0a74da-c3e5-4346-a337-0f536115bb7c",
        "full_name": "Test Employee B",
        "organisation_id": "0a316877-23d4-4dc3-b0ed-350208d68fb3",
        "role": "agent",
    },
    "employee-c@madzera-test.example": {
        "id": "e5bce736-bcce-4a04-b720-a7b90837e371",
        "full_name": "Test Employee C",
        "organisation_id": "cbd6a8ae-adf3-4099-9352-1862e1751dea",
        "role": "agent",
    },
}


def get_local_config():
    result = subprocess.run(
        ["npx", "--yes", "supabase", "status", "-o", "json"],
        capture_output=True,
        text=True,
        check=True,
    )

    config = json.loads(result.stdout)

    if config.get("API_URL", "").rstrip("/") != LOCAL_URL:
        raise RuntimeError("STOP: Not connected to local Supabase.")

    key = config.get("SERVICE_ROLE_KEY")

    if not key:
        raise RuntimeError("STOP: Local service-role key unavailable.")

    return key


def get_existing_auth_users(key):
    users = []
    page = 1

    while True:
        request = urllib.request.Request(
            f"{LOCAL_URL}/auth/v1/admin/users?page={page}&per_page=100",
            headers={
                "apikey": key,
                "Authorization": f"Bearer {key}",
            },
            method="GET",
        )

        with urllib.request.urlopen(request, timeout=20) as response:
            data = json.load(response)

        batch = data.get("users", [])
        users.extend(batch)

        if len(batch) < 100:
            break

        page += 1

    return users


def request_fixture_password(email):
    """Request a password without displaying or saving it."""
    import getpass

    password = getpass.getpass(
        f"New local test password for {email}: "
    )
    confirmation = getpass.getpass(
        "Confirm password: "
    )

    if password != confirmation:
        raise RuntimeError("Passwords do not match.")

    if len(password) < 12:
        raise RuntimeError(
            "Use a test password of at least 12 characters."
        )

    return password


def create_local_auth_user(key, email, password):
    """Create a missing test account using local Supabase Admin Auth."""
    if LOCAL_URL != "http://127.0.0.1:54321":
        raise RuntimeError("STOP: Local Supabase required.")

    payload = json.dumps({
        "email": email,
        "password": password,
        "email_confirm": True,
    }).encode("utf-8")

    request = urllib.request.Request(
        f"{LOCAL_URL}/auth/v1/admin/users",
        data=payload,
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    with urllib.request.urlopen(request, timeout=20) as response:
        user = json.load(response)

    if not user.get("id"):
        raise RuntimeError("Auth API did not return a user ID.")

    return user["id"]


def provision_missing_auth_users(key):
    """Create missing local test Auth accounts only."""
    verified_key = get_local_config()

    if key != verified_key:
        raise RuntimeError(
            "STOP: Local service-role credentials do not match."
        )

    existing_users = get_existing_auth_users(key)

    existing_emails = {
        user.get("email", "").lower()
        for user in existing_users
    }

    missing = [
        email for email in EMPLOYEE_FIXTURES
        if email not in existing_emails
    ]

    if not missing:
        print("PASS: All test Auth accounts already exist.")
        print("No Auth accounts were modified.")
        return

    print(f"Missing local Auth accounts: {len(missing)}")

    for email in missing:
        password = request_fixture_password(email)
        create_local_auth_user(key, email, password)
        print(f"CREATED: {email}")

    print("PASS: Missing local Auth accounts created.")


def main():
    import sys

    print("=== MADZERA LOCAL FIXTURE SETUP ===")

    if len(sys.argv) > 2 or (
        len(sys.argv) == 2 and sys.argv[1] != "--provision"
    ):
        raise SystemExit("Usage: setup_local_fixtures.py [--provision]")

    if len(sys.argv) == 2:
        print("Mode: LOCAL AUTH PROVISIONING")
        key = get_local_config()
        provision_missing_auth_users(key)
        print("Application fixture provisioning is not implemented yet.")
        return

    print("Mode: READ-ONLY PREPARATION")

    key = get_local_config()
    print("PASS: Local Supabase verified.")

    users = get_existing_auth_users(key)

    existing_emails = {
        user.get("email", "").lower()
        for user in users
    }

    for email, organisation in TEST_EMPLOYEES.items():
        if email in existing_emails:
            print(f"EXISTS: Employee {email} (Organisation {organisation})")
        else:
            print(f"MISSING: Employee {email} (Organisation {organisation})")

    print("PASS: Authentication fixture discovery completed.")

    print("=== APPLICATION EMPLOYEE LINK VERIFICATION ===")

    auth_ids = {
        user.get("email", "").lower(): user.get("id")
        for user in users
    }

    request = urllib.request.Request(
        f"{LOCAL_URL}/rest/v1/users?select=email,organisation_id,auth_user_id,is_active",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
        },
        method="GET",
    )

    with urllib.request.urlopen(request, timeout=20) as response:
        application_users = json.load(response)

    expected_organisations = {
        "A": "0a316877-23d4-4dc3-b0ed-350208d68fb3",
        "B": "cbd6a8ae-adf3-4099-9352-1862e1751dea",
    }

    records = {
        user["email"].lower(): user
        for user in application_users
    }

    all_valid = True

    for email, organisation in TEST_EMPLOYEES.items():
        record = records.get(email)
        expected_org = expected_organisations[organisation]

        valid = (
            record is not None
            and auth_ids.get(email) is not None
            and record.get("auth_user_id") == auth_ids[email]
            and record.get("organisation_id") == expected_org
            and record.get("is_active") is True
        )

        print(
            f"{'PASS' if valid else 'FAIL'}: "
            f"{email} — organisation {organisation}, Auth linkage"
        )

        if not valid:
            all_valid = False

    if not all_valid:
        raise RuntimeError("Application employee fixtures need review.")

    print("PASS: All application employee links verified.")

    print("=== CASE FIXTURE VERIFICATION ===")

    expected = {
        "c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea":
            "0a316877-23d4-4dc3-b0ed-350208d68fb3",
        "a1d410f6-0521-4d25-a1f1-9e0023423a14":
            "cbd6a8ae-adf3-4099-9352-1862e1751dea",
    }

    request = urllib.request.Request(
        LOCAL_URL + "/rest/v1/cases?select=id,organisation_id,status",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
        },
    )

    with urllib.request.urlopen(request, timeout=20) as response:
        cases = {c["id"]: c for c in json.load(response)}

    for case_id, organisation_id in expected.items():
        case = cases.get(case_id)
        if not case or case["organisation_id"] != organisation_id:
            raise RuntimeError("Missing or incorrectly assigned case fixture.")
        if case["status"] != "open":
            raise RuntimeError("Case fixture is not open.")

    print("PASS: Both case fixtures verified.")

    print("No database records were modified.")


if __name__ == "__main__":
    main()
