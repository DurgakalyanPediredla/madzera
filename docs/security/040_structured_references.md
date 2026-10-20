# Madzera — Security Assessment 040: Structured References

**Date:** 20 October 2026
**Environment:** Local Supabase PostgreSQL
**Status:** Local security regression checks passed; production review pending

## 1. Security Objective

Provide organisation-scoped customer and case business references
without weakening existing authentication, tenant isolation,
audit logging or exclusive case-session controls.

Business references are operational identifiers, not authentication
credentials or authorisation tokens.

## 2. Trust Boundaries

The reference-allocation infrastructure is stored in the private
`madzera_internal` PostgreSQL schema.

The counter table is:

`madzera_internal.reference_counters`

The allocator is:

`madzera_internal.next_reference_number(uuid, text, integer)`

Customer and case inserts invoke database triggers that generate
references automatically.

Application users do not need direct access to the counter table
or allocation functions.

## 3. Database Privileges

The migration explicitly revokes direct privileges from PUBLIC,
anon and authenticated on relevant internal objects.

Local PostgreSQL privilege inspection also confirmed that:

| Role | Private schema USAGE | Counter SELECT | Counter UPDATE |
|---|---|---|---|
| anon | Denied | Denied | Denied |
| authenticated | Denied | Denied | Denied |
| service_role | Denied | Denied | Denied |

These checks concern direct access to the private counter
infrastructure. They do not constitute a complete audit of every
database function or possible indirect access path.

## 4. Reference Integrity

The migration implements:

- Database-generated customer references
- Database-generated case references
- NOT NULL constraints
- Organisation-scoped unique indexes
- Protection against manually supplied references on INSERT
- Protection against reference modification on UPDATE
- Transactional counter allocation

A committed counter increment remains consumed even if its
corresponding record is later deleted.

A rolled-back allocation may be reused because the transaction
did not commit.

## 5. Concurrency Verification

A local test executed two concurrent transactions inserting cases
into the same organisation.

Both transactions committed successfully.

Generated references:

- CAS2026000002
- CAS2026000003

The references were unique and consecutive.

Both temporary cases were subsequently deleted.

The counter remained at 3, demonstrating that committed numbers
were not reused after deletion.

This test verifies the exercised concurrency scenario, not every
possible production workload or failure condition.

## 6. Application-Role INSERT Restrictions

Local PostgreSQL tests attempted direct customer INSERT operations
under both anon and authenticated roles.

Both operations were rejected.

The tests were rolled back.

The customers table has a SELECT RLS policy for authenticated
employees but no customer INSERT RLS policy in the inspected
local database state.

Authenticated employees cannot directly insert into public.cases
under the inspected table-level permissions.

Controlled case creation uses:

`public.create_employee_case(...)`

This SECURITY DEFINER function validates the employee identity,
resolves their organisation and records a case-created audit event.

Test 024 verified that this function still creates a case with a
structured reference and an associated creation audit event.

## 7. Tenant Isolation

Customer counters are separated by organisation.

Case counters are separated by organisation and UTC creation year.

The unique indexes use the organisation ID together with the
business reference.

Consequently, the same reference may legitimately exist in
different organisations.

Business references must not be treated as globally unique IDs.

Application queries and future APIs must continue to enforce
organisation-level authorisation rather than rely on reference
values alone.

## 8. Historical Backfill and Audit Controls

Migration 040 uses exclusive locks on the customers and cases
tables while backfilling historical references.

The existing case-update audit trigger is temporarily disabled
inside the migration transaction because historical administrative
updates do not have an authenticated employee context.

The migration re-enables that trigger before COMMIT.

After migration and regression testing, PostgreSQL inspection
confirmed that `trg_audit_case_update` remained enabled.

The existing case-locking and renewal functions were not modified.

## 9. Regression Verification

On 20 October 2026, local Test 024 passed assertions covering:

- Existing reference population and uniqueness
- Customer reference generation
- Organisation-specific customer numbering
- Case reference generation
- Organisation-specific case numbering
- Annual UTC case counter reset
- Customer reference immutability
- Case reference immutability
- Private counter privilege restrictions
- Authenticated case creation
- Case creation audit event

The test completed with ROLLBACK.

Subsequent inspection confirmed:

- One original customer remained
- Two original cases remained
- No Test 024 customer or case records remained
- Persistent reference counters were unchanged
- The case-update audit trigger was enabled

## 10. Limitations and Outstanding Security Work

The following have not been established by Test 024 alone:

- Complete security of every SECURITY DEFINER function
- Exhaustive API-level access control verification
- Complete tenant isolation across all database objects
- All possible malicious INSERT and UPDATE payloads
- All concurrency and failure scenarios
- Hosted Supabase migration success
- Hosted API and browser regression results
- Independent penetration testing
- Production security approval

Existing case organisation_id protections must continue to be
verified through the broader case-security regression suite.

Any future lookup by business reference must include appropriate
organisation-level authorisation.

## 11. Deployment Position

Migration 040 has been applied and tested locally.

It has not yet been deployed to hosted Supabase.

Before hosted deployment:

1. Review the migration and its dependencies.
2. Confirm a suitable hosted backup and rollback strategy.
3. Verify compatibility with existing application queries.
4. Execute appropriate regression and security tests.
5. Review deployment impact and maintenance requirements.
6. Deploy through the approved migration process.
7. Verify hosted data, permissions and application behaviour.

**Conclusion:** The tested local security controls passed.
This does not establish production security readiness.
