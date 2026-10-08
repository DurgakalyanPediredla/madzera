
# Madzera — Database Security Test Results

## Test Environment

- Project: Madzera
- Database: Supabase PostgreSQL
- Environment: Development
- Test data: Synthetic
- Execution method: Supabase SQL Editor
- Initial execution date: 8 October 2026

## Automated SQL Test Execution Results

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

## Pending Executable Tests

- RLS-04 — Own-organisation customer visibility
- RLS-05 — Cross-organisation customer isolation
- RLS-06 — Own-organisation case visibility
- RLS-07 — Cross-organisation case isolation

## Evidence Notes

Results are based on executed SQL and observations reported during development.

Passing these tests does not establish production security readiness or complete multi-tenant isolation.
