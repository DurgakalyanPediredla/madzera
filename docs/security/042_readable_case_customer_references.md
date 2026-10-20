# Madzera — Security Assessment 042: Readable References

**Date:** 20 October 2026
**Environment:** Local Supabase PostgreSQL
**Status:** Local regression passed; hosted verification pending

## 1. Security Objective

Expose readable case and customer references to authorised employees
without weakening organisation isolation, protected-table access,
case-lock controls or audit behaviour.

## 2. Trust Boundaries

`public.get_case_queue()` is a `SECURITY DEFINER`, `STABLE` SQL function
with an empty `search_path`.

The function filters cases using
`public.current_user_organisation_id()`.

Customer joins require both the customer ID and the case organisation ID.

The active-lock join remains organisation-scoped and excludes expired locks.

The function returns queue metadata, not unrestricted case-table access.

## 3. Permissions

Migration 042 revokes function execution from `PUBLIC` and `anon`.

Execution is granted to `authenticated` and `service_role`.

Authenticated users do not require direct `SELECT` permission on
`public.cases` to use the queue RPC.

The migration does not add direct application-table permissions.

## 4. Regression Evidence

**Test:** `database/tests/027_case_queue_readable_references.sql`

**Result:** PASS — 20 October 2026, local PostgreSQL.

Verified:

1. Anonymous function execution privilege absent
2. Authenticated function execution privilege present
3. Anonymous RPC invocation rejected
4. Unlinked authenticated identity receives no queue rows
5. Employee A receives only Organisation A cases
6. Employee C receives only Organisation B cases
7. Queue case references match protected database records
8. Queue customer references and names match organisation-owned customers
9. Cases without customers have null customer-reference fields
10. Queue record counts match the corresponding organisation's case count

The test executes the RPC under simulated authenticated identities.
Results are captured in a transaction-local temporary table, then
compared with protected records using the privileged test role.

The transaction finishes with `ROLLBACK`.

## 5. Frontend Security Considerations

UUIDs remain internal identifiers for navigation and case operations.

Readable references do not grant access to case details.

Case details continue to require the existing exclusive-lock workflow.

The customer-reference lookup matches both case UUID and customer UUID
before rendering its result.

The frontend does not bypass the existing case-detail RPC.

## 6. Limitations

The completed test uses existing local fixtures, with one case per
organisation at execution time.

It does not establish:

- Hosted RPC privilege behaviour
- Browser-level end-to-end correctness
- Security under concurrent queue or lock changes
- Comprehensive adversarial testing
- Independent production security approval

Migration 042 has not yet been deployed to hosted Supabase.

No changes to existing case-lock functions or audit triggers were
required for this feature.

## 7. Hosted Security Verification

**Date:** 20 October 2026

**Status:** Completed checks passed.

Hosted PostgreSQL inspection confirmed:

- 15 queue return columns
- All three readable-reference columns present
- Anonymous function EXECUTE denied
- Authenticated function EXECUTE granted
- Service-role function EXECUTE granted
- SECURITY DEFINER enabled
- STABLE function attribute retained
- Organisation filter present
- Organisation-scoped customer join present

Browser checks confirmed that an existing internal case and an
existing customer-linked case could be opened and exited normally.

No changes were made to existing case-lock functions.

Outstanding security work includes adversarial cross-tenant testing
against hosted data, concurrent-lock testing and independent review.
