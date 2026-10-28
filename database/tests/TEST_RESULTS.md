
# Madzera — Database Security Test Results

## Test Environment

- Project: Madzera
- Database: Supabase PostgreSQL
- Environment: Development
- Test data: Synthetic
- Execution method: Supabase SQL Editor
- Initial execution date: 8 October 2026

## Manually Executed SQL Test Results

### AUTH-01 — Authentication Identity Mapping

**Status:** PASS

**Execution date:** 8 October 2026

**Test file:** `002_auth_identity_test.sql`

**Objective:** Verify that Sarah Mitchell's Madzera employee record is active, belongs to NorthStar Customs Ltd, and links to an existing Supabase Authentication identity.

**Reported SQL output:**

| test_id | result | matching_employee_records |
|---|---|---|
| AUTH-01 | PASS | 1 |

**Interpretation:**

The database query returned one matching employee record and satisfied the authentication identity mapping assertions.

**Limitations:**

- Executed using the privileged Supabase SQL Editor.
- Does not demonstrate successful browser login.
- Does not test authentication tokens or session expiry.
- Does not establish production authentication security.

### RLS-01 — Own-Organisation Employee Visibility

**Status:** PASS

**Execution date:** 8 October 2026

**Test file:** `003_rls_employee_visibility.sql`

**Objective:** Verify that Sarah Mitchell's simulated authenticated session can read the four expected NorthStar Customs employee records through PostgreSQL Row Level Security.

**Reported SQL output:**

| test_id | result | visible_employee_count |
|---|---|---|
| RLS-01 | PASS | 4 |

**Interpretation:**

The SQL assertion returned PASS. Exactly four employee records were visible, and all four expected NorthStar employee email addresses matched.

The synthetic database also contains Daniel Brooks, an employee belonging to HarbourBridge Customs Ltd. His record was not visible to Sarah under this test.

**Limitations:**

- Executed using a simulated authenticated PostgreSQL session.
- Does not establish successful login through a real application.
- Does not test INSERT, UPDATE or DELETE permissions.
- Does not establish complete tenant isolation across all database tables.


### RLS-02 — Unlinked Identity Access Denial

**Status:** PASS

**Execution date:** 8 October 2026

**Test file:** `004_rls_unlinked_identity.sql`

**Objective:** Verify that a simulated authenticated identity without an active Madzera employee mapping cannot read records from `public.users`.

**Reported SQL output:**

| test_id | result | visible_employee_count |
|---|---|---|
| RLS-02 | PASS | 0 |

**Interpretation:**

The SQL assertion returned PASS. No employee records were visible to the simulated unlinked identity.

This is consistent with the organisation-resolution helper returning NULL when no active employee mapping exists.

**Limitations:**

- The identity was simulated using PostgreSQL session claims.
- No real Supabase login was performed for this identity.
- The test covers SELECT access to `public.users` only.
- It does not establish protection for other database tables or write operations.

### RLS-03 — Cross-Organisation Employee Isolation

**Status:** PASS

**Execution date:** 8 October 2026

**Test file:** `005_rls_employee_tenant_isolation.sql`

**Objective:** Verify that Sarah Mitchell's simulated authenticated session can view NorthStar employee records without gaining visibility of HarbourBridge employee records.

**Reported SQL output:**

| test_id | result | visible_employee_count | harbourbridge_employees_visible |
|---|---|---|---|
| RLS-03 | PASS | 4 | 0 |

**Interpretation:**

The SQL assertion returned PASS.

- Four employee records were visible.
- All four visible records belonged to the organisation resolved for Sarah's simulated identity.
- No employee record matching Daniel Brooks' HarbourBridge email address was visible.

**Limitations:**

- The test used simulated PostgreSQL authentication claims.
- HarbourBridge's employee fixture was created and checked separately during development, not verified independently within this executable test.
- Only SELECT access to `public.users` was tested.
- This does not establish complete tenant isolation across all database tables or operations.

### RLS-04 — Own-Organisation Customer Visibility

**Status:** PASS

**Execution date:** 8 October 2026

**Test file:** `006_rls_customer_visibility.sql`

**Objective:** Verify that Sarah Mitchell's simulated authenticated session can read the expected NorthStar Customs customer record through PostgreSQL Row Level Security.

**Reported SQL output:**

| test_id | result | visible_customer_count | expected_customer_visible |
|---|---|---|---|
| RLS-04 | PASS | 1 | 1 |

**Interpretation:**

The corrected SQL assertion returned PASS.

- Exactly one customer record was visible.
- The visible customer matched `CUST-1001` (ABC Imports Ltd).
- The customer's organisation ID matched the organisation resolved for Sarah's simulated identity.

**Test correction:**

The initial execution failed with PostgreSQL error 42703 because the test referenced a nonexistent `customer_code` column.

The database schema was inspected and the test was corrected to use `external_customer_id` and `name`.

The corrected test executed successfully.

**Limitations:**

- Authentication was simulated using PostgreSQL session claims.
- Only SELECT access to `public.customers` was tested.
- Cross-organisation customer isolation is tested separately in RLS-05.
- No real application login or production security assessment was performed.

### RLS-05 — Cross-Organisation Customer Isolation

**Status:** PASS

**Execution date:** 8 October 2026

**Test file:** `007_rls_customer_tenant_isolation.sql`

**Objective:** Verify that Sarah Mitchell's simulated authenticated session can read NorthStar Customs customer records without gaining visibility of HarbourBridge Customs customer records.

**Reported SQL output:**

| test_id | result | visible_customer_count | harbourbridge_customers_visible |
|---|---|---|---|
| RLS-05 | PASS | 1 | 0 |

**Interpretation:**

The SQL assertion returned PASS.

- Exactly one customer record was visible.
- The visible record matched ABC Imports Ltd (`CUST-1001`).
- The visible record belonged to Sarah's resolved organisation.
- No record matching Seabrook Trading Ltd (`CUST-HB-1001`) was visible.

**Limitations:**

- Authentication was simulated using PostgreSQL session claims.
- The HarbourBridge customer fixture was created separately during development; its existence was not independently checked within this executable test.
- Only SELECT access to `public.customers` was tested.
- This does not establish tenant isolation across all Madzera tables or write operations.
- No real application login or production security assessment was performed.

### RLS-06 — Own-Organisation Case Visibility

**Status:** PASS

**Execution date:** 9 October 2026

**Test file:** `008_rls_case_visibility.sql`

**Objective:** Verify that Sarah Mitchell's simulated authenticated session can read the expected NorthStar Customs case through PostgreSQL Row Level Security.

**Reported SQL output:**

| test_id | result | visible_case_count | expected_case_visible |
|---|---|---|---|
| RLS-06 | PASS | 1 | 1 |

**Interpretation:**

The SQL assertion returned PASS.

- Exactly one case record was visible.
- The visible case matched `CASE-DEMO-001`.
- The case's organisation ID matched the organisation resolved for Sarah's simulated identity.

**Limitations:**

- Authentication was simulated using PostgreSQL session claims.
- Only SELECT access to `public.cases` was tested.
- Cross-organisation case isolation will be tested separately in RLS-07.
- Team-based access restrictions and case write permissions remain untested.
- No real application login or production security assessment was performed.

### RLS-07 — Cross-Organisation Case Isolation

**Status:** PASS

**Execution date:** 9 October 2026

**Test file:** `009_rls_case_tenant_isolation.sql`

**Objective:** Verify that Sarah Mitchell's simulated authenticated session can read NorthStar Customs case records without gaining visibility of HarbourBridge Customs case records.

**Reported SQL output:**

| test_id | result | visible_case_count | harbourbridge_cases_visible |
|---|---|---|---|
| RLS-07 | PASS | 1 | 0 |

**Interpretation:**

The SQL assertion returned PASS.

- Exactly one case record was visible.
- The visible case matched `CASE-DEMO-001`.
- The visible case belonged to Sarah's resolved organisation.
- No case matching HarbourBridge's `CASE-HB-DEMO-001` was visible.

**Limitations:**

- Authentication was simulated using PostgreSQL session claims.
- The HarbourBridge case fixture was created separately during development and was not independently verified within this executable test.
- Only SELECT access to `public.cases` was tested.
- Team-based access, write permissions and other tables remain untested.
- No real application login or production security assessment was performed.


## Initial Executable Test Suite Summary

**Execution status:** 8 of 8 tests reported PASS.

All eight planned SQL assertions have been executed manually in the synthetic Supabase development environment.

These results provide initial evidence for authentication identity mapping and organisation-level SELECT access controls on `public.users`, `public.customers` and `public.cases`.

This is not a CI-automated suite, a penetration test or a production security certification.

Further testing is required for remaining tables, write operations, real authenticated sessions, team-based permissions and cross-tenant relationship integrity.

## Evidence Notes

Results are based on executed SQL and observations reported during development.

Passing these tests does not establish production security readiness or complete multi-tenant isolation.


## Migration 004 — Organisation and Team Read Policies

**Test date:** 9 October 2026  
**Environment:** Supabase PostgreSQL development database  
**Method:** SQL role simulation using `SET LOCAL ROLE authenticated` and a simulated JWT subject.

| Test ID | Description | Expected result | Actual result | Status |
|---|---|---|---|---|
| RLS-08 | Organisation tenant isolation | Sarah sees NorthStar only | NorthStar: 1; HarbourBridge: 0 | PASS |
| RLS-09 | Team tenant isolation | Sarah sees NorthStar teams only | 4 NorthStar teams; no HarbourBridge teams | PASS |
| RLS-10 | Team membership tenant isolation | Sarah sees NorthStar memberships only | 5 NorthStar memberships; no HarbourBridge memberships | PASS |
| RLS-11 | Unlinked authenticated identity | No organisation, team or membership visibility | 0 organisations; 0 teams; 0 memberships | PASS |

### Verification notes

- All four tests were executed manually in Supabase SQL Editor.
- Migration 004 introduced three SELECT policies for `organisations`, `teams`, and `team_members`.
- All three policies apply to the `authenticated` role and use `current_user_organisation_id()`.
- No INSERT, UPDATE or DELETE policies were introduced.
- Tests use simulated PostgreSQL authentication context, not actual client authentication.
- The unlinked identity test assumes the synthetic UUID has no active employee mapping.
- Real Supabase Auth session testing remains outstanding.

**Result:** 4 of 4 Migration 004 SQL simulation tests passed.


## Database Security Milestone — 09 October 2026

### Migration 006 — Visibility Validation
- Status: PASS
- Verified CHECK constraints on comments and attachments.
- Both constraints validated successfully.
- Allowed values: internal, customer.

### Migration 007 — Customer Tenant Integrity
- Status: PASS
- Verified UNIQUE (id, organisation_id) on customers.
- Constraint validated successfully.

### Migration 008 — Case Activity Reference Integrity
- Status: PASS
- Verified 8 composite foreign keys.
- All 8 constraints validated successfully.
- Covers case events, comments and attachments.

### Migration 009 — Least-Privilege Access
- Status: PASS
- Anonymous role has no effective table privileges on
  cases, case_events, comments or attachments.
- Authenticated role has SELECT access to cases only.
- Service-role privileges remained unchanged.
- Simulated employee access returned NorthStar's case
  and excluded HarbourBridge's case.

### Migration 010 — Case Tenant Integrity
- Status: PASS
- Preflight checked 2 existing cases.
- Found 0 invalid customer references.
- Found 0 invalid employee assignments.
- Found 0 invalid team assignments.
- Verified all 3 composite foreign keys.

### Verification Scope and Limitations
- Tests used synthetic demonstration data.
- RLS access was tested through simulated SQL sessions.
- Real browser authentication has not yet been tested.
- Case creation and update permissions are not yet implemented.
- Customer chatbot and document uploads are not yet implemented.
- Storage security and end-to-end application testing remain pending.

## Authenticated Case Creation — Migration 013

**Test date:** 10 October 2026  
**Environment:** Supabase PostgreSQL development database  
**Testing method:** SQL session simulation using the `authenticated` database role and simulated JWT subject claims.

| Test ID | Description | Expected result | Actual result | Status |
|---|---|---|---|---|
| CASE-INSERT-01 | Active NorthStar employee creates a NorthStar case | INSERT succeeds | INSERT succeeded; default status `open`, priority `medium` | PASS |
| CASE-INSERT-02 | NorthStar employee attempts to create a HarbourBridge case | INSERT rejected | PostgreSQL error `42501` — RLS violation | PASS |
| CASE-INSERT-03 | Unlinked authenticated identity attempts case creation | INSERT rejected | PostgreSQL error `42501` — RLS violation | PASS |
| CASE-PERM-01 | Verify authenticated and anonymous table privileges | Only authenticated SELECT and INSERT permitted | All eight privilege checks matched expectations | PASS |

### Security observations

- The `cases` table has Row-Level Security enabled.
- The INSERT policy restricts new cases to the authenticated employee's organisation.
- Employees without a matching active user record cannot create cases.
- Anonymous users have no direct case-table privileges.
- Authenticated users have no direct UPDATE or DELETE privileges.
- Authorised creation was tested inside a transaction using `ROLLBACK`.

### Current limitations

These tests simulate authenticated database sessions. They do not yet demonstrate real application login, browser-to-backend authentication, or end-to-end tenant isolation.

The application must derive organisation identity from a trusted authenticated session. Additional controls are required for case updates, protected fields, audit events and secure customer-facing chatbot submissions.

## Case Update Security and Audit Logging — Migrations 014–015

**Test date:** 10 October 2026  
**Environment:** Supabase PostgreSQL development database  
**Testing method:** SQL transactions, simulated Supabase Auth identities, PostgreSQL role switching and transaction rollback.

| Test ID | Description | Actual result | Status |
|---|---|---|---|
| CASE-AUDIT-01 | Verify audit trigger installation | Trigger installed, enabled and owned by `postgres` | PASS |
| CASE-AUDIT-02 | Verify automatic audit event creation | `case_updated` event created with correct employee identity and priority change | PASS |
| CASE-AUDIT-03 | Reject update without an active employee identity | PostgreSQL error `42501` | PASS |
| CASE-UPDATE-01 | Authenticated employee updates own organisation's case | UPDATE succeeded | PASS |
| CASE-UPDATE-02 | Verify authenticated update generates an audit event | Event attributed to Sarah Mitchell | PASS |
| CASE-UPDATE-03 | Attempt cross-organisation UPDATE | Zero rows updated | PASS |
| CASE-UPDATE-04 | Attempt to modify protected `organisation_id` | PostgreSQL permission error `42501` | PASS |

### Implemented controls

- Tenant-scoped UPDATE policy on `public.cases`.
- Column-level UPDATE permissions limited to `status`, `priority`, `assigned_team_id` and `assigned_user_id`.
- Automatic audit events for changes to these workflow fields.
- Employee attribution using the authenticated Supabase identity.
- Automatic maintenance of `updated_at` and resolution timestamps.
- No direct employee INSERT, UPDATE or DELETE access to `case_events`.
- Cross-organisation case updates blocked by Row-Level Security.

### Current limitations

- Tests use simulated authenticated sessions, not real application login.
- The audit trigger has not yet been tested for every status transition and assignment combination.
- Business rules such as mandatory four-eyes approval before resolution are not yet enforced.
- Employee case creation requires further field-level hardening.
- Customer-facing chatbot submission and the employee dashboard are not yet implemented.
- Production security review and end-to-end application testing remain outstanding.


## Case Security Regression Tests — October 2026

Environment: Supabase development database
Test data: Synthetic NorthStar and HarbourBridge fixtures
Authentication: Simulated JWT identity with PostgreSQL authenticated role

| Test file | Verification | Result |
|---|---|---|
| 014_authenticated_case_creation.sql | Same-organisation case creation | PASS |
| 015_cross_organisation_case_creation.sql | Cross-organisation INSERT rejected | PASS |
| 016_unlinked_identity_case_creation.sql | Unlinked identity INSERT rejected | PASS |
| 017_authenticated_case_audit.sql | Authenticated UPDATE generates audit event | PASS |
| 018_cross_organisation_case_update.sql | Cross-organisation UPDATE affects zero rows | PASS |
| 019_protected_case_column_update.sql | Protected organisation_id UPDATE denied | PASS |

All tests were executed against the development database.
Test transactions were rolled back.

Limitations:
- These are database-level tests, not browser-based tests.
- JWT identities were simulated in SQL.
- Cross-organisation UPDATE testing assumes the target fixture exists.
- Production authentication and application integration remain untested.

## Hosted Supabase Security Verification — 15 October 2026

### Environment and scope

- Project: Madzera_V1 development environment
- Backend: Supabase PostgreSQL and REST/RPC APIs
- Test data: Synthetic NorthStar Customs Ltd and HarbourBridge Customs Ltd records
- Authentication: Real Supabase Auth login for selected employee API tests
- Execution: Manual Terminal scripts, hosted SQL Editor queries and permission inspections
- Latest migration represented: 032_controlled_employee_case_creation.sql

These results supplement earlier SQL simulation tests. They are not evidence of a complete automated regression suite.

### Hosted verification results

| Test ID | Verification | Observed result | Status |
|---|---|---|---|
| SEC-01 | Direct authenticated case SELECT | REST request returned HTTP 403, PostgreSQL 42501 | PASS |
| SEC-02 | Controlled case queue retrieval | get_case_queue returned HTTP 200 and an authorised NorthStar case | PASS |
| SEC-03 | Exclusive case-session opening | open_case_session returned acquired=true and a lock token | PASS |
| SEC-04 | Lock-protected case detail retrieval | HTTP 200; correct case returned | PASS |
| SEC-05 | Invalid case lock token | HTTP 200 with no case details returned | PASS |
| SEC-06 | Session closing | close_case_session returned HTTP 200 and true | PASS |
| SEC-07 | Direct authenticated case INSERT | Database privilege inspection returned false | PASS |
| SEC-08 | Controlled employee case creation | RPC created a synthetic case and employee-attributed case_created event | PASS |
| SEC-09 | Direct authenticated case UPDATE and DELETE | Database privilege inspection returned false for both | PASS |
| SEC-10 | Anonymous employee case creation execution | Function privilege inspection returned false | PASS |
| SEC-11 | Case-update audit trigger review | Active employee validation, protected identifiers and audit-event insertion confirmed in function definition | CODE REVIEW |

### Case creation test cleanup

The synthetic case created during the hosted controlled-creation test and its associated test event were subsequently removed through privileged development cleanup.

This cleanup is not evidence that ordinary authenticated employees can delete cases.

### Case-lock verification

A hosted test confirmed that an authenticated employee could open a case session, retrieve details with the corresponding lock token and close the session.

A separate invalid-token request returned no case details.

The hosted database was also inspected to verify lock ownership and case-opened/case-closed audit events.

These observations do not establish concurrency correctness under simultaneous requests or prove that every database access path is protected.

### Current permission model

Following migrations 031 and 032, hosted development checks confirmed:

- Direct authenticated SELECT on public.cases: denied
- Direct authenticated INSERT on public.cases: denied
- Direct authenticated UPDATE on public.cases: denied
- Direct authenticated DELETE on public.cases: denied
- Controlled employee case creation RPC: executable by authenticated users
- Anonymous execution of employee case creation RPC: denied
- Service-role access remains privileged

Earlier test sections describing direct authenticated case-table access are historical and should not be interpreted as current permissions.

### Outstanding security requirements

- Implement a controlled case-update RPC requiring an active employee-owned case lock.
- Review whether the update trigger should independently enforce lock ownership.
- Test lock expiry, renewal, contention and concurrent update behaviour.
- Enforce appropriate status transitions and independent four-eyes approval.
- Verify cross-organisation isolation for every exposed function and relevant table.
- Complete customer-facing, attachment and storage authorisation.
- Add repeatable regression tests and CI execution.
- Perform an independent security assessment before production use.

### Evidence limitations

Results were observed during development and recorded manually.

Some tests used Python scripts outside the tracked repository. Their existence does not mean the tests are currently reproducible through GitHub or executed automatically.

No passwords, access tokens, lock tokens or private customer information are included in this report.

Production readiness has not been established.

---

## Case Workspace and Session Recovery — 19 October 2026

### Environment and scope

- Project: Madzera
- Backend: Local and hosted Supabase PostgreSQL
- Frontend: Next.js and TypeScript
- Test data: Synthetic employee, organisation and case fixtures
- Methods: SQL regression transactions, permission inspection,
  TypeScript validation and manual browser testing
- Migrations: 035–039

### Database regression test results

| Test file | Feature | Passing assertions | Status |
|---|---|---:|---|
| 020_save_employee_case_comment.sql | Internal comment creation and security | 8 | PASS |
| 021_get_employee_case_comments.sql | Protected comment retrieval | 6 | PASS |
| 022_get_employee_case_audit_history.sql | Protected audit-history retrieval | 6 | PASS |
| 023_resume_employee_case_session.sql | Verified recovery of existing lock | 7 | PASS |
| **Total** | | **27** | **PASS** |

The tests were executed against local development PostgreSQL
using synthetic fixtures and transaction rollback.

These are database-level regression assertions, not evidence of
independent production penetration testing.

### Migration deployment

The following migrations were applied to the development databases:

- 035_save_employee_case_assignment.sql
- 036_save_employee_case_comment.sql
- 037_get_employee_case_comments.sql
- 038_get_employee_case_audit_history.sql
- 039_resume_employee_case_session.sql

Hosted Supabase SQL Editor reported successful execution.
Migration 039 was additionally checked locally for restricted
function execution privileges.

Successful migration execution does not independently establish
the correctness of every runtime access path.

### Browser verification

Manual browser testing confirmed:

- An authenticated employee could open a case workspace.
- Case assignment could be saved and persisted.
- Reassignment confirmation and cancellation behaved as expected.
- Internal comments persisted after leaving and reopening.
- Case Record and Audit History loaded successfully.
- Repeated browser refreshes recovered a valid existing case lock.
- Explicit Back to cases navigation released the session and
  allowed the case to be opened again.
- The delayed loading skeleton replaced the brief access-check message.

These observations concern the tested development workflow.
They are not a load test or exhaustive multi-user concurrency test.

### Frontend and repository verification

- TypeScript: `npx tsc --noEmit` — PASS.
- Staged whitespace validation: `git diff --cached --check` — PASS.
- Commit: `5d2c16d`.
- GitHub branch: `main`.
- Remote commit verification: PASS.

### Security observations

- Database validation remains authoritative for exclusive case access.
- Session recovery requires an authenticated employee, matching
  organisation, owned lock token and unexpired lease.
- The recovery RPC does not create, renew or release a lock.
- Browser sessionStorage is only a recovery hint.
- Saving an assignment or comment does not release the lock.
- Protected comments and audit history are accessed through
  server-validated RPCs.

### Remaining limitations and required testing

1. Unexpected navigation or browser closure may leave a lock active
   until its existing lease expires.
2. Browser tab duplication may copy sessionStorage.
3. Attachments and storage authorisation are not implemented.
4. Simultaneous multi-employee contention requires dedicated testing.
5. Production-scale performance and load testing remain outstanding.
6. A comprehensive independent security review is still required.

### Evidence interpretation

These results extend the historical database security report.
Earlier sections may describe permissions that were subsequently
replaced by stricter RPC-based access controls.

The latest observed results do not establish production readiness.

---

## Structured References — 20 October 2026

### Environment and scope

- Project: Madzera
- Database: Local Supabase PostgreSQL
- Migration: `040_structured_customer_case_references.sql`
- Regression test: `024_structured_references.sql`
- Execution method: Docker PostgreSQL client (`psql`)
- Hosted deployment: Not performed

### Migration execution

Migration 040 completed successfully against local PostgreSQL.

The migration added structured customer and case references,
organisation-scoped counter allocation, uniqueness constraints
and reference-protection triggers.

Historical records were backfilled.

The existing case-update audit trigger was re-enabled before
the migration transaction committed.

### Regression Test 024

**Status: PASS**

The SQL test completed successfully with no reported errors.

The execution produced the following successful notices:

| Verification | Result |
|---|---|
| Existing references populated and unique | PASS |
| Customer reference generation and tenant counters | PASS |
| Case reference generation and tenant counters | PASS |
| Annual UTC case counter reset | PASS |
| Customer reference immutable | PASS |
| Case reference immutable | PASS |
| Private counter permissions | PASS |
| Authenticated case creation RPC | PASS |
| Authenticated RPC reference and audit event | PASS |

The test completed with `ROLLBACK`.

The shell output reported exit code `0`. This was consistent with
the successful SQL execution and absence of PostgreSQL errors,
although the command printed the exit status of the final echo
rather than explicitly preserving the psql process exit status.

### Committed concurrency verification

**Status: PASS**

Two concurrent transactions inserted cases into the same
organisation and committed successfully.

Generated references:

- `CAS2026000002`
- `CAS2026000003`

The references were unique and consecutive.

Both temporary cases were subsequently deleted.

The committed counter remained at `3`.

An earlier rollback-based concurrency attempt produced the same
reference in two transactions because the first allocation was
rolled back. This is expected transactional counter behaviour,
not evidence of duplicate committed references.

### Post-regression database integrity

**Status: PASS**

| Verification | Observed result |
|---|---|
| Existing customers | 1 |
| Existing cases | 2 |
| Test 024 cases remaining | 0 |
| Test 024 customers remaining | 0 |
| Organisation A, case counter, 2026 | 3 |
| Organisation A, customer counter | 1 |
| Organisation B, case counter, 2026 | 1 |
| `trg_audit_case_update` | Enabled (`O`) |

These values matched the expected post-test state.

### Additional permission verification

Local role-based customer INSERT attempts were rejected for:

- `anon`
- `authenticated`

Private counter privilege inspection confirmed restricted direct
access for the inspected application roles.

These tests do not replace a comprehensive API-level security
assessment.

### Documentation

- `docs/features/040_structured_references.md`
- `docs/security/040_structured_references.md`
- `database/tests/TEST_MATRIX.md`

### Outstanding verification

- Hosted Supabase migration and post-deployment checks
- Frontend display and API integration of business references
- TypeScript and browser regression after frontend changes
- Broader adversarial and cross-organisation security testing
- Independent production security review

### Evidence interpretation

Migration 040 is implemented and regression-tested locally.

These results do not establish hosted deployment success,
complete security coverage or production readiness.

## Migration 041 — Optional Customer Association

**Date:** 20 October 2026
**Environment:** Local Supabase PostgreSQL
**Overall result:** PASS for completed local tests
**Hosted deployment:** Not performed

### 1. Migration application

File: `database/migrations/041_optional_customer_internal_cases.sql`

**Result: PASS**

The migration completed locally with `COMMIT`.

The existing `create_employee_case` interface was retained.

The new `create_employee_case_v2` interface accepts explicit case
classification, independently of customer association.

The shared implementation is located in the private
`madzera_internal` schema.

### 2. Functional regression — Test 025

File: `database/tests/025_optional_customer_internal_cases.sql`

**Result: PASS**

Observed successful checks:

- Transactional test fixtures prepared
- Internal case with customer created
- Internal case without customer created
- Customer enquiry with customer created
- Customer enquiry without customer rejected
- Cross-organisation customer rejected
- Cross-organisation team rejected
- Invalid case type rejected
- Stored case types and customer associations verified
- Structured case references verified
- Creation audit events verified

The test completed with `ROLLBACK`.

No permanent test-created cases, customers or teams remained.

### 3. RPC security regression — Test 026

File: `database/tests/026_optional_customer_rpc_security.sql`

**Result: PASS — seven assertions**

Observed PostgreSQL notices:

```text
PASS: Anonymous legacy RPC denied
PASS: Anonymous v2 RPC denied
PASS: Unlinked legacy RPC rejected
PASS: Unlinked v2 RPC rejected
PASS: Legacy RPC classification preserved
PASS: Legacy RPC structured reference
PASS: Legacy RPC creation audit event
```

The execution ended with:

```text
ROLLBACK
=== TEST 026 EXECUTION COMPLETED ===
```

The test created a temporary case through the original RPC
under a simulated authenticated employee session, verified
its classification, reference and audit event, and rolled
back the transaction.

### 4. Privilege verification

**Result: PASS**

Local PostgreSQL privilege inspection confirmed:

- Anonymous callers cannot execute either public RPC
- Authenticated users can execute both public RPCs
- The private implementation is not directly executable by
  anonymous, authenticated or service-role callers
- Anonymous and authenticated roles cannot directly use
  the private `madzera_internal` schema

Both public functions use SECURITY DEFINER with an empty
search_path and delegate to the shared private implementation.

### 5. Frontend checks

Updated file: `web/src/app/cases/CreateCaseForm.tsx`

**Result: PASS for completed static checks**

- `npx tsc --noEmit` — passed
- `npm run lint` — zero errors, one existing warning in
  `web/src/app/cases/[caseId]/CaseWorkspace.tsx`
- `npm run build` — passed
- `git diff --check` — passed

The frontend now sends explicit `p_case_type` through
`create_employee_case_v2`.

Browser-level creation testing has not been performed.

### 6. Deployment and remaining work

Migration 041 has been applied only to local Supabase.

Outstanding:

- Browser-level verification of all three case combinations
- Hosted migration and API verification
- Broader security and tenant-isolation review
- Production deployment approval

The hosted database must support `create_employee_case_v2`
before the updated frontend is deployed.

**Conclusion:** Migration 041 passed its completed local
functional, security and compatibility checks. Production
readiness has not yet been established.

Feature documentation:
`docs/features/041_optional_customer_internal_cases.md`

Security assessment:
`docs/security/041_optional_customer_internal_cases.md`

## Migration 042 — Readable Case and Customer References

**Execution date:** 20 October 2026

**Environment:** Local Supabase PostgreSQL

**Migration:** `database/migrations/042_case_queue_readable_references.sql`

**Test:** `database/tests/027_case_queue_readable_references.sql`

**Result:** PASS

### 1. Migration and privilege checks

Migration 042 was applied successfully to local PostgreSQL.

Function inspection confirmed:

- Original queue return columns retained
- Three readable-reference columns appended
- `SECURITY DEFINER` and `STABLE` attributes
- Organisation filtering and organisation-scoped customer join
- Anonymous EXECUTE denied
- Authenticated and service-role EXECUTE granted

### 2. Regression execution

The final Test 027 execution reported:

```text
BEGIN
NOTICE: PASS: Queue function access grants
NOTICE: PASS: Anonymous queue access denied
NOTICE: PASS: Unlinked identity sees no queue records
INSERT 0 1
INSERT 0 1
NOTICE: PASS: Employee A has 1 correctly scoped cases with valid references
NOTICE: PASS: Employee C has 1 correctly scoped cases with valid references
ROLLBACK
```

The temporary test-table permissions are limited to the test transaction.

No direct case-table SELECT grant was introduced.

### 3. Frontend checks

Completed:

- TypeScript checking passed
- ESLint reported zero errors and one pre-existing warning

Pending:

- Final Next.js production build after latest frontend changes
- Hosted browser verification of case queue, detail and creation success

### 4. Deployment status

Migration 042 has been applied locally only.

Hosted migration and post-deployment security verification remain pending.

Feature documentation:

`docs/features/042_readable_case_customer_references.md`

Security assessment:

`docs/security/042_readable_case_customer_references.md`

### Migration 042 — Hosted deployment results

**Date:** 20 October 2026

**Result:** PASS for completed deployment and browser checks.

Hosted migration output:

```text
BEGIN
DROP FUNCTION
CREATE FUNCTION
REVOKE
GRANT
COMMIT
Migration exit code: 0
```

Hosted inspection returned:

```text
total_columns: 15
readable_reference_columns: 3
anon_can_execute: false
authenticated_can_execute: true
service_role_can_execute: true
security_definer: true
stable: true
organisation_filter_present: true
customer_tenant_join_present: true
```

Frontend validation completed with:

- TypeScript exit code 0
- ESLint exit code 0, with one existing warning
- Production build exit code 0

User-confirmed browser checks:

- Readable case and customer references in the queue
- Internal case `CAS2026000004` displays its readable reference
- Internal case without customer displays `No customer linked`
- Customer-linked case displays a readable customer reference
- Existing case opening and normal exit operate as expected

The tests did not independently verify simultaneous locking
behaviour or comprehensive hosted tenant-isolation attacks.

## Migrations 049 and 055 — Case Evidence Download Security

**Date:** 22 October 2026

**Environment:** Local Supabase PostgreSQL

**Regression:** `028_case_evidence_download_policy.sql`

**Result:** PASS — seven security checks.

### Verified results

| Check | Result |
|---|---|
| Expired lock denies evidence access | PASS |
| Active employee lock permits evidence access | PASS |
| Unlinked authenticated identity denied | PASS |
| Authenticated Storage object retrieval | PASS |
| Authenticated Storage metadata retrieval | PASS |
| Storage listing operation blocked by SELECT RLS | PASS |
| Storage deletion operation blocked by SELECT RLS | PASS |

The test returned seven PASS notices and completed with ROLLBACK.

The test temporarily extended an existing expired case lock
inside a database transaction. The rollback preserved its
original state.

### Hosted verification

Migration 055 was previously deployed successfully to hosted
Supabase. Evidence downloading was subsequently confirmed
working through the application browser.

This browser verification is separate from the local SQL test.

### Limitations

The SQL regression was executed locally, not against the
hosted database.

The deletion-operation check verifies SELECT-policy visibility.
It does not execute an actual DELETE request.

Comprehensive hosted tenant-isolation testing, concurrent-lock
testing and regression coverage for the remaining evidence
migrations are still outstanding.

**Conclusion:** All seven tested local evidence-download
security conditions passed. This does not establish complete
production security readiness.

## Migrations 045 and 053 — Case Evidence Upload Preparation Security

**Date:** 22 October 2026

**Environment:** Local Supabase PostgreSQL

**Regression:** `029_case_evidence_upload_preparation.sql`

**Result:** PASS — nine security assertions.

### Verified results

| Check | Result |
|---|---|
| Expired case lock rejects upload preparation | PASS |
| Invalid filenames rejected | PASS |
| Unsupported file MIME type rejected | PASS |
| Zero-byte file rejected | PASS |
| File exceeding 10 MB rejected | PASS |
| Valid employee lock permits upload reservation | PASS |
| Incorrect lock token rejected | PASS |
| Overlapping pending reservation rejected | PASS |
| Expired pending reservation remains blocked | PASS |

The final regression execution produced nine PASS notices
and completed with ROLLBACK.

The test exercised the existing upload-preparation RPC under the
authenticated PostgreSQL role. The lock and reservation rejection
assertions checked both the expected PostgreSQL error category
and the rejection message.

### Post-test database integrity

A separate read-only inspection after a successful regression
execution confirmed:

| Verification | Observed result |
|---|---|
| Original case lock remains expired | true |
| Original lock owner unchanged | true |
| Pending reservations for the test case | 0 |
| Completed reservations for the test case | 5 |

The regression temporarily extended the expired case lock,
created a pending reservation and simulated an expired pending
reservation. These changes were confined to the transaction
and rolled back.

### Limitations

This was a local SQL regression test, not a hosted application
or live Storage upload test.

It does not independently establish cross-organisation isolation,
concurrent reservation safety, Storage INSERT policy enforcement,
upload finalisation, recovery workflow correctness or full
production security readiness.

These areas remain pending separate verification.

**Conclusion:** All nine tested local upload-preparation
security conditions passed, with no persistent fixture changes
observed in the post-test integrity inspection.

## Migration 047 — Case Evidence Upload Finalisation Security

**Date:** 22 October 2026

**Environment:** Local Supabase PostgreSQL

**Regression:** `030_case_evidence_upload_finalisation.sql`

**Result:** PASS — 14 checks, ROLLBACK, exit status 0.

### Verified results

| Check | Result |
|---|---|
| Synthetic finalisation fixtures created | PASS |
| Nonexistent reservation rejected | PASS |
| Incorrect lock token rejected | PASS |
| Missing Storage object rejected | PASS |
| Mismatched Storage metadata rejected | PASS |
| Expired reservation rejected | PASS |
| Invalid activity association rejected | PASS |
| Valid authenticated employee finalisation | PASS |
| Repeated finalisation rejected | PASS |
| Attachment metadata and activity link verified | PASS |
| Reservation marked completed | PASS |
| Evidence-upload audit event verified | PASS |
| Exactly one attachment for the synthetic upload | PASS |
| Exactly one corresponding evidence-upload audit event | PASS |

The final execution produced 14 PASS notices, completed with
ROLLBACK and returned exit status 0.

### Post-test database integrity

An independent read-only inspection confirmed:

| Verification | Observed result |
|---|---|
| Remaining synthetic reservations | 0 |
| Remaining synthetic attachments | 0 |
| Matching synthetic Storage objects | 0 |
| Original case lock expired | true |

### Limitations

This regression uses synthetic database fixtures and invokes
the finalisation RPC under the authenticated PostgreSQL role.

It does not perform a real Storage API upload or independently
verify hosted behaviour, Storage INSERT policies, concurrency,
cross-organisation isolation or the recovery lifecycle.

**Conclusion:** All 14 local finalisation checks passed, with
no persistent synthetic fixture changes observed.

## Migration 046 — Case Evidence Storage Upload Security

**Date:** 22 October 2026

**Environment:** Local Supabase PostgreSQL

**Regression:** `031_case_evidence_storage_upload_policy.sql`

**Result:** PASS — 11 checks, ROLLBACK, exit status 0.

### Verified results

| Check | Result |
|---|---|
| Existing fixture prerequisites verified | PASS |
| Synthetic reservation created | PASS |
| Expired lock denies upload | PASS |
| Valid reservation and lock authorised | PASS |
| Authenticated reserved Storage INSERT succeeded | PASS |
| Unreserved Storage path rejected | PASS |
| Wrong Storage bucket rejected | PASS |
| Authenticated Storage UPDATE denied | PASS |
| Direct Storage DELETE rejected by protection trigger | PASS |
| Unlinked identity denied | PASS |
| Expired reservation denied | PASS |

### Post-test database integrity

| Verification | Observed result |
|---|---|
| Remaining synthetic Storage buckets | 0 |
| Remaining synthetic reservations | 0 |
| Remaining matching synthetic Storage objects | 0 |
| Original case lock expired | true |

### Limitations

The test uses local SQL fixtures rather than a real Storage API
upload. It exercises actual INSERT RLS under the authenticated
PostgreSQL role.

The direct DELETE assertion verifies Supabase's protection
trigger, not Storage API deletion authorisation.

Hosted behaviour, cross-organisation isolation, concurrent
uploads and recovery lifecycle correctness remain unverified.

**Conclusion:** All 11 local Storage upload security checks
passed, and the post-test inspection found no remaining
synthetic fixtures.

## Migrations 051–052 — Case Evidence Upload Recovery Security

**Date:** 22 October 2026

**Environment:** Local Supabase PostgreSQL

**Regression:** `032_case_evidence_upload_recovery_security.sql`

**Result:** PASS — 11 checks, ROLLBACK, exit status 0.

### Verified results

| Check | Result |
|---|---|
| Synthetic recovery fixtures created | PASS |
| Pending recovery status verified | PASS |
| Expired recovery status verified | PASS |
| Completed recovery status and attachment verified | PASS |
| Own reservation listing and statuses verified | PASS |
| Incorrect token denied by recovery-status function | PASS |
| Incorrect token denied by reservation-listing function | PASS |
| Unlinked identity denied recovery status | PASS |
| Unlinked identity denied reservation listing | PASS |
| Expired lock denied recovery status | PASS |
| Expired lock denied reservation listing | PASS |

### Post-test database integrity

| Verification | Observed result |
|---|---|
| SQL exit status | 0 |
| Transaction ended with ROLLBACK | Yes |
| Remaining synthetic reservations | 0 |
| Remaining synthetic attachments | 0 |
| Original case lock expired | true |

### Limitations

The initial execution failed because of a malformed employee UUID
in the test fixture. PostgreSQL rolled back the transaction,
and independent inspection confirmed no remaining synthetic records.
The fixture was corrected and the subsequent execution passed.

This test validates recovery-status reporting and reservation
listing under selected authentication and lock conditions.
It does not verify cross-employee or cross-organisation isolation,
missing-attachment handling, concurrent recovery, actual upload
resolution or hosted-environment behaviour.


## Test 033 — Case Evidence Recovery Isolation Security

**Date:** 22 October 2026

**Environment:** Local Supabase PostgreSQL

**Regression:** `033_case_evidence_recovery_isolation.sql`

**Result:** PASS — 10 checks, ROLLBACK, exit status 0.

### Verified results

| Check | Result |
|---|---|
| Synthetic isolation fixtures and valid locks created | PASS |
| Employee A recovered own reservation | PASS |
| Employee A listed own reservation | PASS |
| Employee B valid-lock positive control | PASS |
| Cross-employee recovery denied despite valid lock | PASS |
| Cross-employee reservation listing isolated | PASS |
| Organisation B valid-lock positive control | PASS |
| Cross-organisation recovery denied | PASS |
| Cross-organisation reservation listing denied | PASS |
| Organisation B listing excluded Organisation A reservation | PASS |

### Post-test database integrity

| Verification | Observed result |
|---|---|
| SQL exit status | 0 |
| Transaction ended with ROLLBACK | Yes |
| Remaining Test 033 reservations | 0 |
| Remaining temporary Organisation B locks | 0 |
| Original Organisation A lock restored | true |

### Limitations

The regression uses synthetic database reservations and
transaction-scoped case locks under the authenticated
PostgreSQL role.

Same-organisation employee isolation is verified with a valid
case lock, distinguishing reservation ownership enforcement
from lock rejection.

Cross-organisation requests are rejected at the case-access
boundary. The test does not independently exercise the
reservation-organisation predicate after passing that boundary.

Concurrent requests, completed reservations without attachments,
interrupted upload resolution, real Storage API behaviour and
hosted deployment remain outside this test's coverage.

**Conclusion:** All 10 local isolation assertions passed, and
independent inspection confirmed that temporary fixtures were
rolled back.


## Test 034 — Case Evidence Missing Attachment Recovery Security

**Date:** 22 October 2026

**Environment:** Local Supabase PostgreSQL

**Regression:** `034_case_evidence_missing_attachment_recovery.sql`

**Result:** PASS — five assertions, ROLLBACK, exit status 0.

### Verified results

| Check | Result |
|---|---|
| Completed reservation without attachment created | PASS |
| Valid case lock established | PASS |
| Missing attachment rejected with SQLSTATE 22023 | PASS |
| Own reservation listing reports completed status | PASS |
| Matching attachment returns completed status and expected ID | PASS |

### Post-test database integrity

| Verification | Observed result |
|---|---|
| SQL exit status | 0 |
| Transaction ended with ROLLBACK | Yes |
| Remaining synthetic reservations | 0 |
| Remaining synthetic attachments | 0 |
| Original case lock expired | true |

### Execution history

The first execution stopped with a permission error because the
test attempted to read case_locks directly under the authenticated
role. The transaction was rolled back and independent inspection
confirmed no remaining synthetic fixtures.

The regression was corrected to capture the existing lock token
before switching roles. No database permissions or production
functions were modified.

The subsequent execution passed all five assertions.

### Limitations

The regression verifies database recovery-status behaviour using
synthetic reservation and attachment records. It does not verify
that an actual Storage object exists or that an interrupted
upload can be resumed, cancelled or resolved.

Concurrent requests and hosted deployment remain untested.

**Conclusion:** The recovery-status function rejected a completed
reservation without a matching attachment and returned the expected
attachment ID once a matching record existed.

## Test 035 — Case Evidence Download Path Security

**Date:** 23 October 2026

**Environment:** Local Supabase PostgreSQL (`supabase_db_madzera`)

**Regression:** `035_case_evidence_download_path_security.sql`

**Function:** `public.get_employee_case_evidence_download_path(uuid, uuid, uuid)`

**Result:** PASS — 10 security assertions, ROLLBACK, exit status 0.

### Verified results

| Check | Result |
|---|---|
| Valid employee receives correct completed-evidence Storage path | PASS |
| Incorrect lock token denied | PASS |
| Unknown attachment denied | PASS |
| Expired case lock denied | PASS |
| Unlinked authenticated identity denied | PASS |
| Different employee denied | PASS |
| Cross-organisation request denied | PASS |
| Attachment requested against wrong case denied | PASS |
| Attachment with pending reservation denied | PASS |
| Anonymous RPC execution denied | PASS |

Fixture validation and creation of the synthetic pending-evidence
record also completed successfully.

### Post-test database integrity

| Verification | Observed result |
|---|---|
| SQL exit status | 0 |
| Transaction ended with ROLLBACK | Yes |
| Original Organisation A case lock remains expired | Yes |
| Temporary Organisation B case lock remains | No |
| Remaining Test 035 synthetic attachments | 0 |
| Remaining Test 035 synthetic reservations | 0 |

### Execution history

The first execution stopped when the expired-lock test fixture
violated the existing `chk_case_locks_expiry` constraint.
Post-test inspection confirmed the original lock state and
zero synthetic attachments or reservations.

The test fixture was corrected to set `locked_at` earlier than
`expires_at`, while keeping both timestamps in the past.
No database constraint, migration, RPC or locking function
was changed.

The subsequent execution passed all 10 security assertions,
returned exit status 0 and completed with ROLLBACK.

### Limitations

This is a local database-RPC regression using simulated
authenticated PostgreSQL roles and transaction-scoped fixtures.
It does not execute actual Supabase Storage API downloads,
deletions or hosted adversarial requests.

The cross-organisation request is rejected at the case-access
boundary; this does not independently isolate every downstream
organisation predicate.

The wrong-case test also fails at the case-access boundary,
rather than testing attachment mismatch after obtaining a
valid lock on a different case.

Concurrent access, hosted deployment and comprehensive
end-to-end evidence security remain unverified.

**Conclusion:** The evidence download-path RPC passed all
10 tested local authorisation and metadata scenarios, and
independent post-test inspection confirmed rollback integrity.

## Tests 036–038 — Customs Context and Team Permission Security — 25 October 2026

**Environment:** Local Supabase PostgreSQL Docker container
**Database:** postgres
**Execution:** `psql -X -P pager=off -v ON_ERROR_STOP=1`
**Date:** 25 October 2026

### Test 036 — Customs context and operational references

**File:** `036_customs_context_reference_security.sql`

Observed PASS notices:
- RLS enabled and direct application-role privileges denied.
- Authenticated direct reads rejected.
- Valid customs contexts.
- Cross-organisation foreign keys.
- Operation and reference-type constraints.
- Duplicate-reference prevention.
- Multiple references and independent cases.

**Exit status:** 0.
**Transaction:** BEGIN followed by ROLLBACK.

### Test 037 — Context-first case creation

**File:** `037_context_first_case_creation_security.sql`

Observed PASS notices:
- Employee and organisation fixtures available.
- Anonymous execution denied.
- Unlinked identity rejected.
- Case, context, references and audit attribution.
- Invalid reference and operation inputs rejected.
- Twenty references accepted; twenty-one rejected.
- Invalid issue categories rejected.
- Reference-count and rejected-case integrity.
- Cross-organisation customer and team rejected.
- Cross-organisation requests left no cases.
- Controlled reference-insertion failure captured.
- Injected failure rolled back case, context, references and audit.
- Rejected requests left no case records.

The test created and removed a transaction-scoped failure-injection
trigger and function to exercise atomicity.

**Exit status:** 0.
**Transaction:** BEGIN followed by ROLLBACK.

### Test 038 — Team permission authorisation

**File:** `038_team_permission_authorisation_security.sql`

Observed PASS notices:
- Migration 061 helper installed.
- Function execution privileges.
- Dynamic employee fixtures discovered.
- Isolated test teams created.
- Explicit grant and permission separation.
- Cross-organisation team denied.
- Invalid permission denied.
- Colleague permission isolation.
- Cross-tenant employee isolation.
- Unlinked authenticated identity denied.
- Granted employee access confirmed.
- Exactly one employee deactivated and subsequently reactivated.
- Inactive employee denied.
- Exactly one permission grant revoked.
- Revoked permission denied.

**Exit status:** 0.
**Transaction:** BEGIN followed by ROLLBACK.

### Scope and limitations

All results above are based on observed local PostgreSQL execution
output with ON_ERROR_STOP enabled.

The ROLLBACK statements establish transactional cleanup by design,
but an independent post-test database-integrity inspection has not
yet been recorded for these latest executions.

Hosted Supabase deployment, browser/API workflows, concurrency,
and complete application-level permission enforcement remain
unverified by these three regressions.

This record does not claim independent functional verification of
administrator provisioning or the grant/revoke management RPCs
introduced by migrations 059–060.

## Migrations 058–063 — Organisation Administration and Mandatory Team Submission

**Verification date:** 26 October 2026

**Environment:** Local Supabase PostgreSQL, Docker

**Database:** postgres

**Container:** supabase_db_madzera

**Source commit:** f87f70ad2d3c53081585136bfe079f2ddc0d4f25

**GitHub status:** Commit pushed to origin/main

**Hosted Migration 063 deployment:** Not performed

### 1. Implementation scope

The reviewed migrations establish the following components:

| Migration | Implementation |
|---|---|
| 058 | Organisation administrators, team permission grants, permission audit events and relational constraints |
| 059 | Controlled team-permission grant and revocation functions |
| 060 | Privileged initial organisation-administrator provisioning |
| 061 | Explicit team-permission authorisation helper |
| 062 | Controlled organisation-team provisioning and audit events |
| 063 | Mandatory destination-team and submit-permission enforcement during case creation |

The permissions submit, work and manage are represented as
independent permission types.

Implementation of these permission types does not by itself
establish enforcement throughout every downstream workflow.

### 2. Regression test execution

The following local regression results were recorded during
development and reviewed in the current verification sequence.

| Test | Description | Recorded outcome |
|---|---|---|
| 038 | Team permission authorisation and isolation | PASS |
| 039 | Secure organisation-team provisioning, administrator isolation and audit rollback | PASS |
| 040 | Mandatory destination-team submission security | PASS — 11 checks |
| 041 | Administrator-to-case-submission integration | PASS — 7 checks |

The tests were executed against local PostgreSQL using
transaction-scoped synthetic fixtures and ROLLBACK.

These are database-level regression results, not browser-level
or hosted Supabase API penetration tests.

### 3. Test 040 — Mandatory submission authorisation

**File:** database/tests/040_mandatory_destination_team_submission_security.sql

**SHA-256:**
d1e4710e6925cde6d25b08f0b69c60aeb71c6201e121f13b7cf8d4fb2e755540

The reviewed test source covers:

- Missing destination-team rejection.
- Cross-organisation destination-team rejection.
- Rejection without an explicit submit permission.
- Separation of submit from work and manage.
- Successful authorised case creation.
- Organisation, team and employee attribution.
- Colleague permission isolation.
- Effective revocation of submit permission.
- Absence of corresponding persisted case and audit records
  for rejected submissions.

**Recorded execution:** PASS — 11 checks.

**Important distinction:** This test uses privileged setup
to manipulate transaction-scoped permission grants. It does
not independently exercise the administrator management RPCs.

### 4. Test 041 — Administrator-to-submission integration

**File:** database/tests/041_end_to_end_team_submission_integration.sql

**SHA-256:**
a3dd972609b68893b1440989b74eab8f1079a42c901bc5924234131e37807a0b

The reviewed test source covers:

- Initial administrator provisioning.
- Administrator-created organisation team.
- Administrator-issued submit permission.
- Successful case submission by an authorised employee.
- Case and audit attribution.
- Rejection of an unauthorised colleague.

**Recorded execution:** PASS — 7 checks.

This is an end-to-end database workflow test, not an
end-to-end browser or hosted API test.

### 5. Installed database security inspection

The following inspections were performed against the
installed local PostgreSQL database.

**Step 2477 — Employee identity resolution**

The current_employee_id and current_user_organisation_id
helpers require an authenticated identity linked to an
active employee record.

**Step 2478 — Relational integrity and RLS**

The installed permission tables were inspected for
organisation-scoped foreign keys, permission constraints,
uniqueness restrictions and enabled RLS.

**Step 2479 — Direct table privileges**

Anonymous and authenticated roles lacked direct SELECT,
INSERT, UPDATE and DELETE privileges on the four inspected
permission-management and administration audit tables.

The service_role retained privileged direct access to
three inspected tables, but lacked the inspected privileges
on organisation_admin_audit_events.

No RLS policies were installed on those four tables.
Their RLS configuration did not use FORCE ROW LEVEL SECURITY.

**Step 2480 — Function execution privileges**

Anonymous callers lacked EXECUTE permission on the
inspected management and authorisation functions.

Authenticated callers could execute the public
management functions, subject to their internal
administrator and employee validation.

The initial administrator-provisioning function was
not executable by application roles.

**Step 2481 — Installed case-creation implementation**

The installed private case-creation function was inspected.

The implementation requires a destination team belonging
to the caller's organisation and an explicit submit grant.

It independently validates authorisation at the database
boundary rather than trusting frontend team filtering.

The function uses SECURITY DEFINER, postgres ownership
and an empty search_path.

### 6. Frontend integration review

The CreateCaseForm.tsx source was reviewed.

The form retrieves organisation teams, evaluates submit
permission, filters available destinations and requires
a destination-team selection.

It invokes create_employee_case_v2.

Database authorisation remains authoritative even if
frontend validation is bypassed.

This review does not constitute a complete browser
regression or prove protection against simultaneous
duplicate submissions.

### 7. Auditability and integrity

The implementation records permission-management and
team-provisioning actions in dedicated audit tables.

Successful case creation records a case_created event
with employee and destination-team attribution.

The case and associated creation event are inserted
within the same database transaction.

Direct application-role access to the inspected
administration and permission audit tables is restricted.

These observations do not prove audit-log immutability
against database owners or other privileged operators.

### 8. Release and repository evidence

Migration 063 was installed in the local database.

The recorded local regression suite passed its selected
post-installation tests.

A pre-migration local database backup was created and
its archive structure inspected. A full restore test
has not been performed.

Commit f87f70a was pushed to GitHub main.

GitHub publication does not imply deployment to hosted
Supabase.

Migration 063 has not been deployed to the hosted
Supabase database in this verification sequence.

### 9. Outstanding verification

- Hosted migration deployment and post-deployment inspection.
- Real authenticated API tests for the latest permission model.
- Browser-level administrator and case-submission workflows.
- Complete enforcement of work and manage permissions.
- Cross-team access and revocation behaviour for existing cases.
- Concurrency, duplicate submission and idempotency.
- Comprehensive downstream evidence and audit authorisation.
- Independent post-test fixture-integrity checks where absent.
- Independent security assessment.
- Production deployment approval.

### 10. Verification conclusion

Migrations 058–063 establish an organisation-scoped
permission foundation and database-enforced mandatory
destination-team submission.

The reviewed implementation and recorded local regression
results support the specific controls described above.

The evidence does not establish complete production
security, certification against PAS 41201, or hosted
deployment of Migration 063.

Earlier test results remain historical evidence and
must not be interpreted as current database privileges
where later migrations changed those privileges.

## Test 060 — Evidence Recovery-Status Team-Work Revocation Security

**Verification date:** 28 October 2026.

**Environment:** Local Docker Supabase PostgreSQL database. No hosted Supabase execution.

**Feature:** Evidence upload recovery-status authorisation after team-work permission revocation.

**Protected function:** `public.get_case_evidence_upload_recovery_status(uuid, uuid, uuid)`.

**Migration:** `database/migrations/067_operational_case_work_authorisation.sql`.

**Regression source:** `database/tests/060_case_evidence_recovery_status_work_revocation_security.sql`.

**Execution evidence:** `database/test-results/test060_recovery_status_work_revocation.log`.

**Execution result:** PASS — PostgreSQL exit status 0; required behavioural assertions present; no logged SQL errors or failures.

### Execution method

The local test runner assembled a single transaction containing:

1. Migration 066, with its outer `BEGIN` and `COMMIT` statements removed in memory.
2. The current Migration 067 source.
3. Test 044's synthetic fixture setup and integrity assertions.
4. Test 060's authorisation, revocation and integrity assertions.
5. An explicit outer `ROLLBACK`.

Migration files and existing tests were not modified by this execution. Test 044's subsequent original assertions were intentionally excluded because Test 060 revokes the fixture employee's work permission.

### Verified security assertions

| Control | Recorded result |
|---|---|
| Authorised employee retrieves own pending recovery status | PASS |
| Employee's team-work permission revoked while valid exclusive lock remains | PASS |
| Revoked employee denied recovery status despite original valid lock | PASS |
| Denial matches SQLSTATE `42501` and `Case work permission required` | PASS |
| Exclusive lock row preserved exactly after denied request | PASS |
| Evidence reservation row preserved exactly after denied request | PASS |
| No additional attachment created by denied request | PASS |
| No additional case audit event created by denied request | PASS |
| Transaction ended with `ROLLBACK` | PASS |

### Evidence integrity

| Artifact | SHA-256 |
|---|---|
| Migration 067 | `7d32da0aa17fd2646bed48b7f5dd1c414194102b3212ac0eea05e51c077ef5f3` |
| Test 060 | `22a8e9d8607ea95ec6fd966064b087cac05c32d585aa9292cf5cecc4454765c2` |
| Execution log | `c991373c2b79f9a1fe5fb796ba91d8286be18dd31d17cab97ef6fb874099f929` |

The execution log contains 89 lines and one recorded `ROLLBACK`. Its recorded behavioural assertions completed successfully.

### Security interpretation

This regression demonstrates that an existing valid exclusive lock does not override revoked team-work authorisation for the evidence recovery-status function in the tested local database transaction.

The denied request did not alter the original lock or reservation, create an attachment, or create a case audit event.

### Scope and limitations

This is a synthetic, database-level regression test. It does not independently establish:

- Hosted Supabase deployment or hosted API enforcement.
- Browser-level behaviour after permission revocation.
- Concurrent access or race-condition resistance.
- Complete authorisation coverage across every Madzera function.
- Actual Storage-object recovery or end-to-end upload recovery.
- Independent penetration testing or regulatory certification.

The test provides evidence for this specific authorisation boundary only. Earlier test results must be interpreted against their respective migration versions.

**Verification classification:** Locally executed and passed; rollback confirmed; source and log fingerprints recorded.

**Independent security sign-off:** Not recorded.

**Production deployment approval:** Not established.

## Tests 057–059 — Operational Work Revocation Security

**Verification date:** 28 October 2026.

**Environment:** Local Docker Supabase PostgreSQL.

**Implementation:** `database/migrations/067_operational_case_work_authorisation.sql`.

**Execution classification:** Local database-level security regression; not hosted or production verification.

### Execution evidence

| Test | Security scope | PASS markers | FAIL | ERROR | Rollback |
|---|---|---:|---:|---:|---|
| 057 | Case operations, evidence access and Storage RLS | 91 | 0 | 0 | Confirmed |
| 058 | Active-lock visibility and team-work authorisation | 7 | 0 | 0 | Confirmed |
| 059 | Evidence-reservation listing after work revocation | 8 | 0 | 0 | Confirmed |

**Total:** 106 PASS markers across three executions, zero reported failures or SQL errors, and three confirmed rollbacks. PASS markers are not necessarily independent security controls.

### Test 057 — Case operations and Storage RLS

The recorded regression verified that revoked team-work permission prevents protected case operations, including assignment Save, case updates, comments, audit-history retrieval, evidence operations and Storage access.

The tested employee's existing valid exclusive lock did not override revoked work authorisation. Denied operations preserved the relevant case, assignment, reservation, attachment, audit and lock state.

The test also verified controlled session closure and removal of the employee's owned lock.

**Source:** `database/tests/057_case_evidence_storage_rls_revocation_security.sql`.

**Execution log:** `database/test-results/test057_regression_20261028T015920Z.log`.

**Log SHA-256:** `f024d4e9248a465655628f29c2ffc70ced2f52b537bd3f456c30971075eb7a8d`.

### Test 058 — Active case-lock visibility

The recorded regression verified that authenticated employees see active locks only where they possess the required team-work permission.

Submit/manage permissions alone did not expose active locks. An explicit second-team work grant enabled visibility, and revocation immediately removed that visibility.

**Source:** `database/tests/058_active_case_lock_visibility_security.sql`.

**Execution log:** `database/test-results/test058_regression_20261028T020105Z.log`.

**Log SHA-256:** `24a6321a65e31ecffa498e940ed22431585efafbda7e5bb235a050de49308015`.

### Test 059 — Evidence reservation listing

The recorded regression verified that an authorised employee could list an owned evidence reservation while holding a valid case lock.

After team-work permission was revoked, reservation listing was denied despite the original valid lock. The denial preserved the existing lock and reservation.

**Source:** `database/tests/059_evidence_reservation_work_revocation_security.sql`.

**Execution log:** `database/test-results/test059_regression_20261028T020156Z.log`.

**Log SHA-256:** `a8c7d714f5e204313d0ccb08083f5a0b22f48cda65c0a99745079a7c9ec7713e`.

### Execution method and evidence limitations

Test 057 executed within its own rollback-only transaction.

Tests 058 and 059 each executed in a separate outer transaction assembled from Migration 066 (transaction wrapper removed in memory), Migration 067, Test 044's synthetic fixture setup and the respective targeted test. Each transaction ended with an explicit ROLLBACK.

These tests use synthetic fixtures and simulated authenticated database-role contexts. They provide evidence for the specific local security scenarios exercised.

They do not independently establish hosted Supabase enforcement, authenticated HTTP API behaviour, browser-level integration, concurrency safety, independent penetration testing, regulatory certification or production deployment approval.

Test 060 has a separate existing entry in this document and is not duplicated here.

**Verification classification:** Locally executed and passed; rollback confirmed; log fingerprints retained.

**Independent security sign-off:** Not recorded.

**Production deployment approval:** Not established.
