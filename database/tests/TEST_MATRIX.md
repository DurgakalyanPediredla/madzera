
# Madzera — Database Security Test Matrix

**Project:** Madzera
**Environment:** Supabase PostgreSQL development project
**Initial testing date:** 8 October 2026
**Test data:** Synthetic NorthStar Customs Ltd and HarbourBridge Customs Ltd records

## 1. Purpose

Document database authentication and tenant-isolation tests, their reported results, and outstanding security requirements.

Results below are based on manually executed SQL queries and reported observations. They are not yet automated regression-test results.

## 2. Completed Manual Tests

| Test ID | Test description | Expected result | Reported result | Status |
|---|---|---|---|---|
| AUTH-01 | Verify Sarah's Supabase Auth identity maps to her Madzera employee record and NorthStar organisation | Correct identity and organisation mapping | Mapping verified | Passed (manual) |
| RLS-01 | Sarah reads NorthStar employees before creating HarbourBridge employee | 4 employees | 4 employees | Passed (manual) |
| RLS-02 | Unlinked authenticated identity attempts to read employees | 0 employees | 0 employees | Passed (manual) |
| RLS-03 | Sarah reads employees after creating Daniel at HarbourBridge | 4 NorthStar employees; Daniel hidden | Cross-organisation test passed | Passed (manual) |
| RLS-04 | Sarah reads NorthStar customers before adding HarbourBridge customer | ABC Imports Ltd visible | 1 customer | Passed (manual) |
| RLS-05 | Sarah reads customers after creating Seabrook Trading at HarbourBridge | ABC Imports visible; Seabrook hidden | Customer isolation passed | Passed (manual) |
| RLS-06 | Sarah reads NorthStar cases before creating HarbourBridge case | CASE-DEMO-001 visible | 1 case | Passed (manual) |
| RLS-07 | Sarah reads cases after creating HarbourBridge case | CASE-DEMO-001 visible; HarbourBridge case hidden | Case isolation passed | Passed (manual) |

## 3. Test Execution Issues

| Issue ID | Description | Outcome |
|---|---|---|
| ISSUE-01 | Permission denied when authenticated role attempted to read a privileged temporary test table | Test harness failure; revised approach used |
| ISSUE-02 | Temporary test table could not be found in a subsequent test attempt | Test harness failure; revised approach used |

These issues do not establish a failure of tenant isolation. Their exact technical causes have not been fully investigated.

## 4. Automated Regression Testing

Status: Not yet implemented or executed.

Planned:
- Authentication mapping assertions
- Own-organisation employee visibility
- Cross-organisation employee isolation
- Unlinked identity access denial
- Own-organisation customer visibility
- Cross-organisation customer isolation
- Own-organisation case visibility
- Cross-organisation case isolation

## 5. Security Tests Still Required

- Genuine Supabase client login and authenticated API access
- Second organisation's authenticated employee access
- Insert, update and delete permissions
- Team-based case access
- Management and compliance exceptions
- Cross-organisation foreign-key integrity
- Case events and audit history permissions
- Comments and customer-visible information permissions
- Attachments and document storage access
- Conversations and messages access
- Four-eyes review authorisation
- Privileged function security review
- Account deactivation and access revocation
- Unauthenticated access checks
- Automated regression execution

## 6. Limitations

The completed tests use simulated PostgreSQL authenticated sessions and synthetic records.

The tests demonstrate selected organisation-level read restrictions for the users, customers and cases tables.

They do not establish production security readiness, complete tenant isolation across the entire database, or a finished SaaS application.

## 7. Evidence Status

Manual results: Reported and documented.
Automated tests: Pending.
Independent security review: Not performed.
Production deployment approval: Not established.

## 8. Security Regression Matrix — 15 October 2026

The following matrix records additional development verification performed after the initial SQL tests.

Earlier tests describe the database permissions at the time of execution. Later migrations intentionally replaced direct case-table access with controlled database functions.

| Test ID | Security requirement | Verification | Status |
|---|---|---|---|
| SEC-01 | Authenticated employees cannot directly read cases | Hosted REST SELECT returned HTTP 403 | PASS |
| SEC-02 | Authenticated employees can retrieve an authorised case queue | Hosted get_case_queue RPC returned HTTP 200 | PASS |
| SEC-03 | Active employees can open an exclusive case session | Hosted open_case_session RPC acquired a lock | PASS |
| SEC-04 | Case details require a valid session token | Hosted get_locked_case_details returned the correct case | PASS |
| SEC-05 | Invalid lock tokens do not disclose case details | Invalid-token request returned an empty result | PASS |
| SEC-06 | Case sessions can be closed | Hosted close_case_session returned true | PASS |
| SEC-07 | Authenticated employees cannot directly insert cases | Hosted privilege inspection confirmed INSERT denied | PASS |
| SEC-08 | Controlled case creation records employee attribution | Hosted RPC creation and audit event inspected | PASS |
| SEC-09 | Authenticated employees cannot directly update or delete cases | Hosted privilege inspection confirmed UPDATE and DELETE denied | PASS |
| SEC-10 | Anonymous users cannot execute employee case creation | Hosted function privilege inspection confirmed EXECUTE denied | PASS |
| SEC-11 | Case-update audit trigger validates active employee identity | Hosted function definition inspected | CODE REVIEW |
| SEC-12 | Case updates require ownership of an active lock | Controlled update function not yet implemented | PENDING |
| SEC-13 | Independent four-eyes approval is enforced | Full authorisation workflow not yet implemented | PENDING |
| SEC-14 | Complete tenant isolation across all database functions | Comprehensive regression suite not yet completed | PENDING |

### Evidence Classification

- PASS: Reported successful development test or permission inspection.
- CODE REVIEW: Function definition inspected, without claiming an end-to-end test.
- PENDING: Requirement not yet fully implemented or verified.

These results apply to the development environment and do not establish production security readiness.

## 9. Structured References — 20 October 2026

**Environment:** Local Supabase PostgreSQL

**Migration:** `040_structured_customer_case_references.sql`

**Regression test:** `024_structured_references.sql`

| Test ID | Security or integrity requirement | Verification | Status |
|---|---|---|---|
| REF-01 | Existing customer and case references populated and unique | Post-migration SQL assertions | PASS |
| REF-02 | Customer numbering isolated by organisation | Test 024 inserted customers in two organisations | PASS |
| REF-03 | Case numbering isolated by organisation | Test 024 inserted cases in two organisations | PASS |
| REF-04 | Case numbering resets by UTC year | Test 024 inserted a case in the following year | PASS |
| REF-05 | Customer references cannot be modified | Test 024 rejected a reference UPDATE | PASS |
| REF-06 | Case references cannot be modified | Test 024 rejected a reference UPDATE | PASS |
| REF-07 | Private reference counters are inaccessible to application roles | PostgreSQL privilege inspection and Test 024 | PASS |
| REF-08 | Authenticated case creation generates a reference and audit event | Test 024 exercised create_employee_case RPC | PASS |
| REF-09 | Concurrent committed case inserts receive distinct references | Two concurrent committed inserts | PASS |
| REF-10 | Regression tests leave no persistent test records | Post-test database count and counter inspection | PASS |
| REF-11 | Existing case-update audit trigger remains enabled | PostgreSQL trigger inspection returned O | PASS |
| REF-12 | Hosted migration and API behaviour | Not yet deployed or tested | PENDING |
| REF-13 | Frontend business-reference integration | Not yet implemented or verified | PENDING |

### Evidence and limitations

Test 024 completed successfully with transaction rollback.

Post-test verification confirmed one original customer, two original
cases, no Test 024 records, unchanged counters and an enabled
case-update audit trigger.

A separate concurrency test committed two case inserts, generating
CAS2026000002 and CAS2026000003. Both test cases were subsequently
deleted; their committed counter values remained consumed.

These checks apply to the local development database. They do not
establish hosted deployment success or production security readiness.

Detailed assessment:
`docs/security/040_structured_references.md`
