
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
