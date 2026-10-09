
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
