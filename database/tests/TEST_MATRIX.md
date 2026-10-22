
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

## 10. Optional Customer Association — 20 October 2026

**Environment:** Local Supabase PostgreSQL

**Migration:** `041_optional_customer_internal_cases.sql`

**Functional regression:** `025_optional_customer_internal_cases.sql`

**Security regression:** `026_optional_customer_rpc_security.sql`

| Test ID | Requirement | Verification | Status |
|---|---|---|---|
| OPT-01 | Internal case may reference an organisation customer | Test 025 | PASS |
| OPT-02 | Internal case may have no customer | Test 025 | PASS |
| OPT-03 | Customer enquiry requires a customer | Test 025 | PASS |
| OPT-04 | Cross-organisation customer association rejected | Test 025 | PASS |
| OPT-05 | Cross-organisation team association rejected | Test 025 | PASS |
| OPT-06 | Invalid case classification rejected | Test 025 | PASS |
| OPT-07 | Stored case classification remains independent of customer association | Test 025 | PASS |
| OPT-08 | Structured case reference generated | Test 025 and Test 026 | PASS |
| OPT-09 | Case creation audit event recorded | Test 025 and Test 026 | PASS |
| OPT-10 | Anonymous original and v2 RPC access denied | Test 026 | PASS |
| OPT-11 | Unlinked authenticated identity rejected by both RPCs | Test 026 | PASS |
| OPT-12 | Original RPC remains backward compatible | Test 026 | PASS |
| OPT-13 | Private implementation inaccessible to application roles | Local PostgreSQL privilege inspection | PASS |
| OPT-14 | Frontend TypeScript and production build | Local development checks | PASS |
| OPT-15 | Browser-level creation of all three case combinations | Not yet executed | PENDING |
| OPT-16 | Hosted migration and API security verification | Not yet deployed | PENDING |

### Evidence and limitations

Tests 025 and 026 passed locally and completed with transaction rollback.

Test 026 produced seven PASS notices covering anonymous access,
unlinked identity rejection and legacy RPC compatibility.

The frontend passed TypeScript checking and Next.js production build.
ESLint reported zero errors and one warning.

These checks do not establish hosted deployment success or
production security readiness.

Detailed assessment:

`docs/security/041_optional_customer_internal_cases.md`

## 11. Readable Case and Customer References — 20 October 2026

**Environment:** Local Supabase PostgreSQL

**Migration:** `042_case_queue_readable_references.sql`

**Regression:** `027_case_queue_readable_references.sql`

| Test ID | Requirement | Verification | Status |
|---|---|---|---|
| READ-01 | Anonymous queue execution denied | Test 027 | PASS |
| READ-02 | Authenticated queue execution permitted | Test 027 | PASS |
| READ-03 | Unlinked identity receives no cases | Test 027 | PASS |
| READ-04 | Employee A sees only Organisation A cases | Test 027 | PASS |
| READ-05 | Employee C sees only Organisation B cases | Test 027 | PASS |
| READ-06 | Queue case references match stored references | Test 027 | PASS |
| READ-07 | Customer references and names match linked customers | Test 027 | PASS |
| READ-08 | Cases without customers retain null customer details | Test 027 | PASS |
| READ-09 | Queue counts match organisation case counts | Test 027 | PASS |
| READ-10 | Regression test leaves no persistent changes | Transaction ROLLBACK | PASS |
| READ-11 | Final frontend production build | Not yet rerun | PENDING |
| READ-12 | Hosted database migration and RPC verification | Not yet deployed | PENDING |
| READ-13 | Hosted browser verification of readable references | Not yet executed | PENDING |

### Evidence and limitations

Test 027 passed on 20 October 2026 against local PostgreSQL.

The test verified one organisation-scoped case for Employee A and
one for Employee C. It completed with `ROLLBACK`.

Authenticated access used the existing queue RPC, not direct case-table
SELECT permissions.

The hosted database has not yet received Migration 042.

Detailed assessment:

`docs/security/042_readable_case_customer_references.md`

### Migration 042 — Hosted verification update

**Date:** 20 October 2026

| Test ID | Verification | Status |
|---|---|---|
| READ-11 | Final TypeScript, ESLint and production build | PASS |
| READ-12 | Hosted migration, RPC signature and permission inspection | PASS |
| READ-13 | Hosted queue and case-detail browser verification | PASS |

This update supersedes the earlier PENDING entries for READ-11
through READ-13. Hosted concurrent-lock and broader adversarial
tenant-isolation testing remain outstanding.

## 12. Case Evidence Download Security — 22 October 2026

**Environment:** Local Supabase PostgreSQL

**Migrations:** `049_restricted_case_evidence_downloads.sql`,
`055_allow_authenticated_case_evidence_metadata.sql`

**Regression:** `028_case_evidence_download_policy.sql`

| Test ID | Requirement | Verification | Status |
|---|---|---|---|
| EVD-01 | Expired case lock denies evidence download authorisation | Test 028 | PASS |
| EVD-02 | Valid employee lock permits evidence download authorisation | Test 028 | PASS |
| EVD-03 | Unlinked authenticated identity is denied | Test 028 | PASS |
| EVD-04 | Authenticated evidence object retrieval is permitted | Storage SELECT RLS, Test 028 | PASS |
| EVD-05 | Authenticated evidence metadata retrieval is permitted | Storage SELECT RLS, Test 028 | PASS |
| EVD-06 | Storage listing operation does not expose evidence | Storage SELECT RLS, Test 028 | PASS |
| EVD-07 | Storage deletion operation does not expose evidence through SELECT policy | Storage SELECT RLS, Test 028 | PASS |
| EVD-08 | Temporary lock modification is rolled back | Transaction ROLLBACK | PASS |
| EVD-09 | Hosted evidence download works after Migration 055 | Previously confirmed browser test | PASS |
| EVD-10 | Comprehensive hosted adversarial security testing | Not executed | PENDING |
| EVD-11 | Full regression coverage of evidence migrations 043–054 | Not completed | PENDING |

### Evidence and limitations

Test 028 passed locally on 22 October 2026, producing seven
PASS notices and completing with ROLLBACK.

The test uses existing synthetic employee, case, reservation and
Storage object fixtures. It temporarily extends an expired case lock
inside a transaction and restores the original state through rollback.

Storage operation checks exercise the actual SELECT RLS policy under
the authenticated PostgreSQL role, using independently evaluated
storage.operation settings.

The object.delete check verifies SELECT-policy visibility only.
It does not attempt to delete an object or independently test
DELETE privileges and policies.

Migration 055 was previously applied to the hosted Supabase project,
and evidence downloading was confirmed in the browser. This does not
establish comprehensive hosted security or concurrency coverage.

Other evidence-related migrations, including reservation creation,
upload finalisation, recovery and audit behaviour, require separate
regression coverage.

## 13. Case Evidence Upload Preparation Security — 22 October 2026

**Environment:** Local Supabase PostgreSQL

**Migrations:** `045_prepare_case_evidence_upload.sql`,
`053_prevent_overlapping_evidence_reservations.sql`

**Regression:** `029_case_evidence_upload_preparation.sql`

| Test ID | Requirement | Verification | Status |
|---|---|---|---|
| EVU-01 | Expired case lock denies upload preparation | Test 029 | PASS |
| EVU-02 | Invalid filenames are rejected | Test 029 | PASS |
| EVU-03 | Unsupported file MIME type is rejected | Test 029 | PASS |
| EVU-04 | Zero-byte file is rejected | Test 029 | PASS |
| EVU-05 | File exceeding 10 MB is rejected | Test 029 | PASS |
| EVU-06 | Valid employee lock permits reservation creation | Test 029 | PASS |
| EVU-07 | Incorrect lock token denies upload preparation | Test 029 | PASS |
| EVU-08 | Overlapping pending reservation is rejected | Test 029 | PASS |
| EVU-09 | Expired pending reservation still requires recovery | Test 029 | PASS |
| EVU-10 | Temporary database changes are rolled back | Transaction ROLLBACK and subsequent state inspection | PASS |
| EVU-11 | Hosted upload-preparation security verification | Not executed | PENDING |
| EVU-12 | Cross-organisation and concurrent reservation testing | Not executed | PENDING |
| EVU-13 | Upload finalisation, Storage INSERT and recovery lifecycle regression | Not covered by Test 029 | PENDING |

### Evidence and limitations

Test 029 passed locally on 22 October 2026, producing nine
PASS notices and completing with ROLLBACK.

The regression exercises the upload-preparation RPC under the
authenticated PostgreSQL role using an existing synthetic employee,
case and expired-lock fixture.

It validates file names, permitted MIME types, file-size limits,
lock ownership and expiry, and prevention of overlapping pending
reservations, including pending reservations past their expiry.

The negative lock and reservation checks also verify the expected
PostgreSQL error category and rejection message.

The test temporarily extends the case lock and creates a reservation
inside a transaction. A separate database inspection confirmed the
original lock remained expired, its owner was unchanged, no pending
reservations remained, and five completed reservations were preserved.

This is local SQL regression evidence only. It does not verify actual
Storage uploads, hosted deployment behaviour, cross-organisation
isolation, simultaneous requests, finalisation or recovery workflows.

## 14. Case Evidence Upload Finalisation Security — 22 October 2026

**Environment:** Local Supabase PostgreSQL

**Migration:** `047_finalise_case_evidence_upload.sql`

**Regression:** `030_case_evidence_upload_finalisation.sql`

| Test ID | Requirement | Verification | Status |
|---|---|---|---|
| EVF-01 | Synthetic finalisation fixtures can be established | Test 030 | PASS |
| EVF-02 | Nonexistent reservation is rejected | Test 030 | PASS |
| EVF-03 | Incorrect case-lock token is rejected | Test 030 | PASS |
| EVF-04 | Missing Storage object is rejected | Test 030 | PASS |
| EVF-05 | Mismatched Storage metadata is rejected | Test 030 | PASS |
| EVF-06 | Expired reservation is rejected | Test 030 | PASS |
| EVF-07 | Invalid activity association is rejected | Test 030 | PASS |
| EVF-08 | Valid employee finalisation succeeds | Test 030 | PASS |
| EVF-09 | Repeated finalisation is rejected | Test 030 | PASS |
| EVF-10 | Attachment metadata and activity link are correct | Test 030 | PASS |
| EVF-11 | Reservation is marked completed | Test 030 | PASS |
| EVF-12 | Evidence-upload audit event is recorded | Test 030 | PASS |
| EVF-13 | Duplicate attachment is not created | Test 030 | PASS |
| EVF-14 | Duplicate evidence-upload audit event is not created | Test 030 | PASS |
| EVF-15 | Synthetic changes are rolled back | Transaction ROLLBACK and independent database inspection | PASS |
| EVF-16 | Hosted finalisation and real Storage upload verification | Not executed | PENDING |
| EVF-17 | Cross-organisation, concurrency and full recovery testing | Not executed | PENDING |

### Evidence and limitations

Test 030 passed locally on 22 October 2026, producing 14 PASS
notices and completing with ROLLBACK and exit status 0.

The regression exercises the existing finalisation RPC under the
authenticated PostgreSQL role. Privileged setup creates synthetic
reservations and Storage object metadata within the transaction.

The successful path verifies attachment creation, an internal
activity association, reservation completion and audit recording.
Negative cases verify the expected PostgreSQL rejection category
and message.

Repeated finalisation is rejected, and the test verifies exactly
one attachment and one corresponding audit event for the synthetic
successful upload.

An independent post-test inspection confirmed zero remaining test
reservations, test attachments and matching synthetic Storage
objects. The original case lock remained expired.

This is local SQL regression evidence. It does not establish
hosted deployment behaviour, real Storage API uploads, Storage
INSERT policy enforcement, cross-organisation isolation,
concurrent-request safety or recovery workflow correctness.

## 15. Case Evidence Storage Upload Security — 22 October 2026

**Environment:** Local Supabase PostgreSQL

**Migration:** `046_case_evidence_storage_upload_policy.sql`

**Regression:** `031_case_evidence_storage_upload_policy.sql`

| Test ID | Requirement | Verification | Status |
|---|---|---|---|
| EVS-01 | Existing fixture prerequisites verified | Test 031 | PASS |
| EVS-02 | Synthetic upload reservation created | Test 031 | PASS |
| EVS-03 | Expired case lock denies upload | Test 031 | PASS |
| EVS-04 | Valid reservation and lock authorise upload | Test 031 | PASS |
| EVS-05 | Authenticated Storage INSERT succeeds | Test 031 | PASS |
| EVS-06 | Unreserved Storage path rejected | Test 031 | PASS |
| EVS-07 | Wrong Storage bucket rejected | Test 031 | PASS |
| EVS-08 | Authenticated Storage UPDATE affects zero rows | Test 031 | PASS |
| EVS-09 | Direct Storage DELETE rejected by protection trigger | Test 031 | PASS |
| EVS-10 | Unlinked authenticated identity denied | Test 031 | PASS |
| EVS-11 | Expired upload reservation denied | Test 031 | PASS |
| EVS-12 | Transaction rollback and fixture integrity | Independent inspection | PASS |
| EVS-13 | Storage API upload and deletion security | Not executed | PENDING |
| EVS-14 | Cross-organisation and concurrent uploads | Not executed | PENDING |

### Evidence and limitations

Test 031 passed locally on 22 October 2026 with 11 PASS
notices, ROLLBACK and exit status 0.

The regression exercises actual Storage INSERT row-level security
under the authenticated PostgreSQL role, alongside checks of
the existing upload-authorisation helper.

A temporary Storage bucket and synthetic upload reservation
are created inside the transaction.

An independent post-test inspection confirmed zero remaining
test buckets, test reservations and matching synthetic Storage
objects. The original case lock remained expired.

The direct DELETE check is blocked by Supabase's Storage
protection trigger. It does not independently establish
Storage API deletion permissions.

This regression does not establish hosted Storage API behaviour,
cross-organisation isolation, concurrent-request safety or
full production security readiness.

## 16. Case Evidence Upload Recovery Security — 22 October 2026

**Environment:** Local Supabase PostgreSQL

**Migrations:** `051_get_case_evidence_upload_recovery_status.sql`,
`052_list_employee_case_evidence_upload_reservations.sql`

**Regression:** `032_case_evidence_upload_recovery_security.sql`

| Test ID | Requirement | Verification | Status |
|---|---|---|---|
| EVR-01 | Synthetic recovery fixtures created | Test 032 | PASS |
| EVR-02 | Pending reservation reports pending | Test 032 | PASS |
| EVR-03 | Expired pending reservation reports expired | Test 032 | PASS |
| EVR-04 | Completed reservation returns matching attachment | Test 032 | PASS |
| EVR-05 | Employee reservation listing returns expected statuses | Test 032 | PASS |
| EVR-06 | Incorrect lock token denied by recovery status | Test 032 | PASS |
| EVR-07 | Incorrect lock token denied by reservation listing | Test 032 | PASS |
| EVR-08 | Unlinked identity denied recovery status | Test 032 | PASS |
| EVR-09 | Unlinked identity denied reservation listing | Test 032 | PASS |
| EVR-10 | Expired lock denies recovery status | Test 032 | PASS |
| EVR-11 | Expired lock denies reservation listing | Test 032 | PASS |
| EVR-12 | Transaction rollback and fixture integrity | Independent inspection | PASS |
| EVR-13 | Cross-employee and cross-organisation isolation | Not executed | PENDING |
| EVR-14 | Completed reservation without matching attachment | Not executed | PENDING |
| EVR-15 | Concurrent recovery and upload-resolution workflows | Not executed | PENDING |

### Evidence and limitations

Test 032 passed locally on 22 October 2026 with 11 PASS notices,
ROLLBACK and exit status 0.

The regression exercises the existing recovery-status and
employee-reservation-listing functions under the authenticated
PostgreSQL role using transaction-scoped synthetic fixtures.

An independent post-test inspection confirmed zero remaining
synthetic reservations and attachments. The original case lock
remained expired.

The test verifies read-only recovery reporting and access checks.
It does not establish that an interrupted upload can be resumed,
cancelled or otherwise resolved.

Cross-employee isolation, cross-organisation isolation, concurrent
requests and hosted-environment behaviour remain unverified.
