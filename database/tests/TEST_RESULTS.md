
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
