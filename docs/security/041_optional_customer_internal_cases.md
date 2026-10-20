# Madzera — Security Assessment 041: Optional Customer Association

**Date:** 20 October 2026
**Environment:** Local Supabase PostgreSQL
**Status:** Local security regression passed; production review pending

## 1. Security Objective

Allow internal cases to reference customers without weakening
authentication, organisation isolation, case classification,
audit attribution or existing case-session controls.

Customer association must not grant access to another organisation.

## 2. Trust Boundaries

Case creation is performed through SECURITY DEFINER functions.

The public entry points are:

- `public.create_employee_case(...)`
- `public.create_employee_case_v2(...)`

Both delegate to:

`madzera_internal.create_employee_case_impl(...)`

The shared implementation resides in a private PostgreSQL schema.

Each public function uses an empty search_path.

The existing case-locking and session-renewal functions were
not modified by Migration 041.

## 3. Function Privileges

Local PostgreSQL privilege inspection confirmed:

| Function | anon | authenticated | service_role |
|---|---|---|---|
| Private implementation | Denied | Denied | Denied |
| Original public RPC | Denied | Allowed | Allowed |
| New public v2 RPC | Denied | Allowed | Allowed |

Direct USAGE of `madzera_internal` was denied to
anon and authenticated roles.

The functions are owned by postgres and use SECURITY DEFINER.

These findings describe the inspected local database state.

## 4. Employee Authentication

The shared implementation resolves the employee and organisation
through the existing identity functions.

It rejects requests without an active, linked employee context.

Test 026 verified rejection of an unlinked authenticated identity
for both public case-creation functions.

Test 026 also verified that anonymous callers cannot execute
either public function.

These were database-role tests, not browser or hosted REST tests.

## 5. Organisation Isolation

When a customer is provided, the implementation checks that the
customer belongs to the authenticated employee's organisation.

When an assigned team is provided, it also checks that the team
belongs to the employee's organisation.

Test 025 verified that cross-organisation customer and team
associations were rejected.

Existing composite foreign-key protections remain in place.

These checks do not constitute a comprehensive audit of all
tenant-isolation paths in the application.

## 6. Classification Integrity

The new v2 RPC accepts an explicit case type.

Allowed values are:

- `customer_query`
- `internal_case`

A customer enquiry requires a customer.

An internal case may have a customer or no customer.

Test 025 verified these cases and rejection of an invalid
case type.

The original RPC retains its existing classification inference,
preserving backward compatibility for existing callers.

## 7. Audit and Reference Integrity

The shared implementation inserts a `case_created` event
attributing creation to the authenticated employee.

The existing database trigger generates the structured case
reference introduced by Migration 040.

Test 025 verified creation events and structured references
for the new case combinations.

Test 026 verified both properties for the original RPC.

Migration 041 did not change the reference allocator,
reference-protection triggers or case-locking functions.

## 8. Regression Evidence

**Test 025: Functional and tenant validation — PASS**

Verified:

- Internal case with customer
- Internal case without customer
- Customer enquiry with customer
- Customer enquiry without customer rejected
- Cross-organisation customer rejected
- Cross-organisation team rejected
- Invalid case type rejected
- Stored classification and customer association
- Structured case references
- Creation audit events

**Test 026: RPC security and compatibility — PASS**

Seven assertions passed:

1. Anonymous original RPC denied
2. Anonymous v2 RPC denied
3. Unlinked identity original RPC rejected
4. Unlinked identity v2 RPC rejected
5. Original RPC classification preserved
6. Original RPC structured reference generated
7. Original RPC creation audit event recorded

Both regression tests use transaction rollback.

Local privilege inspections separately confirmed the expected
function EXECUTE restrictions.

## 9. Frontend Verification

The updated case-creation form calls `create_employee_case_v2`.

Completed checks:

- TypeScript compilation passed
- Next.js production build passed
- ESLint reported zero errors and one warning in an
  existing case-workspace effect
- Git whitespace validation passed

Browser-level creation and API-level integration tests remain
outstanding.

## 10. Outstanding Security Work

The following have not yet been established:

- Hosted deployment and post-migration verification
- Hosted API authentication and authorisation behaviour
- Browser-level creation for all three case combinations
- Broader adversarial tenant-isolation testing
- Complete application-level security review
- Independent production security assessment

The frontend must not be deployed before the hosted database
supports `create_employee_case_v2`.

Passing local tests does not establish production readiness.
