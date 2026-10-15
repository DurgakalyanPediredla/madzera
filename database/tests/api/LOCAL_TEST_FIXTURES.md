# Madzera — Local API Security Test Fixtures

## Purpose

These fixtures support API authentication, case queue, and
cross-organisation access-control regression tests.

They are for LOCAL Supabase only.

Local API URL: http://127.0.0.1:54321

## Organisations

| Fixture | Organisation ID |
|---|---|
| Organisation A | 0a316877-23d4-4dc3-b0ed-350208d68fb3 |
| Organisation B | cbd6a8ae-adf3-4099-9352-1862e1751dea |

## Employees

| Fixture | Email | Organisation |
|---|---|---|
| Employee A | employee-a@madzera-test.example | A |
| Employee B | employee-b@madzera-test.example | A |
| Employee C | employee-c@madzera-test.example | B |

Passwords are deliberately excluded from this document.
Never commit passwords, access tokens, or API secrets.

## Cases

### Organisation A

- Case ID: c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea
- Title: Import declaration awaiting clearance
- Status: open
- Organisation: A

### Organisation B

- Case ID: a1d410f6-0521-4d25-a1f1-9e0023423a14
- Title: TENANT ISOLATION TEST - Organisation B
- Status: open
- Organisation: B

## Security expectations

1. Employee A can authenticate against local Supabase.
2. Employee A can access their authorised case queue.
3. Employee A's queue must not expose Organisation B's case.
4. Employee A must not be able to open a session for
   Organisation B's case.
5. A rejected cross-organisation session must not create
   an unauthorised case lock.
6. Direct authenticated reads from public.cases are denied.

## Running the tests

Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in the
Terminal environment.

Run the Python scripts from database/tests/api/.
Authentication tests prompt for passwords without echoing them.

## Reproducibility limitation

These UUIDs describe records verified in the existing local
database. They are not automatically recreated by this document.

A fresh database will require equivalent fixture provisioning,
or a future deterministic fixture setup script.

Do not run fixture provisioning against the hosted database.
