# Madzera — Feature 040: Structured Customer and Case References

**Date:** 20 October 2026
**Status:** Implemented and regression-tested locally
**Migration:** `database/migrations/040_structured_customer_case_references.sql`
**Regression test:** `database/tests/024_structured_references.sql`

## 1. Purpose

Introduce human-readable business references for customers and cases
without replacing internal UUID primary keys.

These references support operational identification, communication,
and future reporting.

## 2. Customer References

Format: `CUS000001`

- Prefix: `CUS`
- Numeric component: six digits
- Numbering is independent for each organisation
- Numbering does not reset annually
- Generated automatically during customer insertion
- Cannot be supplied manually or modified after creation

Example:

- Organisation A: `CUS000001`, `CUS000002`
- Organisation B: `CUS000001`, `CUS000002`

References are unique within an organisation, not globally.

## 3. Case References

Format: `CAS2026000001`

- Prefix: `CAS`
- Four-digit UTC creation year
- Six-digit sequential number
- Numbering is independent for each organisation and UTC year
- Numbering resets for each new UTC year
- Generated automatically during case insertion
- Cannot be supplied manually or modified after creation

Example:

- Organisation A, 2026: `CAS2026000001`
- Organisation A, 2027: `CAS2027000001`
- Organisation B, 2026: `CAS2026000001`

References are unique within an organisation, not globally.

## 4. Database Implementation

Migration 040 adds:

- `public.customers.customer_reference`
- `public.cases.case_reference`
- `madzera_internal.reference_counters`
- `madzera_internal.next_reference_number(...)`
- Customer and case reference-assignment triggers
- Reference-protection triggers
- Organisation-scoped unique indexes
- NOT NULL constraints on both reference columns

Reference allocation uses PostgreSQL INSERT ... ON CONFLICT
DO UPDATE to atomically increment the relevant counter.

Concurrent committed inserts receive distinct reference numbers.

The counter is transactional. A rolled-back allocation may be reused.
A committed allocation remains consumed even if its record is later
deleted.

## 5. Historical Data Migration

Existing customer and case records receive structured references.

Customer backfill ordering:

1. Organisation
2. Creation timestamp
3. UUID as deterministic tie-breaker

Case backfill ordering:

1. Organisation
2. UTC creation year
3. Creation timestamp
4. UUID as deterministic tie-breaker

Existing UUID primary keys remain unchanged.

The migration temporarily disables the existing case-update audit
trigger only during administrative historical backfill, while holding
an exclusive table lock. The trigger is re-enabled before COMMIT.

## 6. Existing Application Behaviour

The existing `public.create_employee_case(...)` function remains
unchanged.

It continues to:

- Validate the authenticated employee
- Resolve the employee's organisation
- Create the case
- Record the `case_created` audit event

The database trigger assigns the new case reference automatically.

The existing case-locking and session-renewal mechanisms are unchanged.

## 7. Security Boundaries

Counter state is stored in the private `madzera_internal` schema.

The migration restricts direct access to the private schema,
counter table and allocation functions.

Reference generation occurs through database triggers.

Customer and case reference values are protected against subsequent
modification.

Existing organisation-level RLS and controlled case-creation
authorisation remain separate security controls.

See `docs/security/040_structured_references.md` for the detailed
security assessment and its limitations.

## 8. Local Verification

Completed on 20 October 2026:

- Historical reference backfill verified
- Committed concurrent case inserts generated unique references
- Temporary concurrency-test cases deleted successfully
- SQL regression test 024 passed
- Authenticated case-creation RPC passed
- Case creation audit event verified
- Private counter access checks passed
- Post-test record counts and counters verified
- Existing case-update audit trigger confirmed enabled

All Test 024 changes were rolled back.

## 9. Deployment Status and Outstanding Work

Migration 040 has been applied to local Supabase PostgreSQL.

It has not yet been applied to the hosted Supabase project.

Outstanding work includes:

- Complete separate security documentation
- Record regression evidence in the test matrix and results
- Integrate business references into relevant application views
- Verify TypeScript build and application behaviour
- Review hosted deployment readiness
- Apply the migration to hosted Supabase after approval
- Verify hosted behaviour following deployment

The migration does not by itself establish production readiness.
