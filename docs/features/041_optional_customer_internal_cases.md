# Madzera — Feature 041: Optional Customer Association for Internal Cases

**Date:** 20 October 2026
**Status:** Implemented and regression-tested locally
**Migration:** `database/migrations/041_optional_customer_internal_cases.sql`
**Functional test:** `database/tests/025_optional_customer_internal_cases.sql`
**Security test:** `database/tests/026_optional_customer_rpc_security.sql`

## 1. Purpose

Allow employees to associate an internal case with an existing customer
without changing the case's classification to a customer enquiry.

Case classification and customer association are separate attributes.

## 2. Expected Behaviour

| Case type | Customer association | Stored case_type |
|---|---|---|
| Customer enquiry | Required | `customer_query` |
| Internal case | Optional, selected | `internal_case` |
| Internal case | Optional, blank | `internal_case` |

A selected customer must belong to the employee's organisation.

All cases continue to receive an automatically generated structured
case reference, such as `CAS2026000001`.

## 3. Database Implementation

Migration 041 introduces a shared private implementation:

`madzera_internal.create_employee_case_impl(...)`

It preserves the existing public function:

`public.create_employee_case(...)`

The existing function retains its five-argument interface and
infers case classification from the presence of a customer.

The migration also introduces:

`public.create_employee_case_v2(...)`

The new function accepts an explicit `p_case_type` argument,
allowing internal cases to reference customers without being
classified as customer enquiries.

Both public functions delegate to the shared implementation.

## 4. Validation and Authorisation

The shared implementation validates:

- An active, authenticated employee and organisation context
- A non-empty case title
- An accepted case priority
- An accepted case classification
- A customer for every customer enquiry
- Customer ownership by the employee's organisation
- Assigned-team ownership by the employee's organisation

Case creation continues through a controlled database function.

## 5. Audit and Reference Behaviour

Case creation continues to record a `case_created` event
with employee attribution.

Migration 040's database trigger continues to generate the
structured case reference.

Existing UUID primary keys remain unchanged.

## 6. Frontend Integration

Updated component:

`web/src/app/cases/CreateCaseForm.tsx`

The form now:

- Displays customer selection for both case types
- Requires a customer for customer enquiries
- Allows a blank customer for internal cases
- Displays the customer association on the review screen
- Sends explicit classification through `create_employee_case_v2`

The existing case navigation and locking mechanisms were
not intentionally modified.

## 7. Local Verification

Completed on 20 October 2026:

- Test 025 passed the functional and tenant-validation assertions
- Test 026 passed seven security and compatibility assertions
- Test 026 completed with transaction rollback
- TypeScript checking passed
- ESLint completed with zero errors and one warning in
  `CaseWorkspace.tsx`
- Next.js production build completed successfully
- Git whitespace validation passed

Browser-level end-to-end creation remains unverified.

## 8. Deployment Status

Migration 041 has been applied to local Supabase PostgreSQL.

It has not been applied to hosted Supabase.

The frontend depends on `create_employee_case_v2`, so the
database migration must be deployed before the updated frontend.

Outstanding work includes:

- Document security evidence and limitations
- Update the regression test matrix and results
- Complete browser-level creation tests
- Review hosted deployment readiness
- Apply the migration to hosted Supabase after approval
- Verify hosted API and frontend behaviour

Local regression results do not establish production readiness.
