# MADZERA
# ENGINEERING AND SECURITY VERIFICATION DOSSIER

## Feature 058–063
### Organisation Administration, Team Permissions and Mandatory Case Submission

**Document ID:** MADZERA-ENG-SEC-058-063

**Version:** 1.0 — Initial evidence compilation

**Date:** 26 October 2026

**Classification:** Internal engineering assurance

**Verification environment:** Local Supabase PostgreSQL

**Implementation commit:** f87f70ad2d3c53081585136bfe079f2ddc0d4f25

**Hosted Migration 063 status:** Not deployed

**Overall assurance classification:** Partially verified

**Production approval:** Not granted by this dossier

---

## 1. Executive summary

This dossier consolidates engineering and security
evidence for Madzera's organisation administration,
team permission and mandatory case-submission feature.

The reviewed implementation establishes a database-level
foundation for organisation-scoped access control.

Its principal implemented capabilities include:

- Explicit organisation administrator authority.
- Controlled initial administrator provisioning.
- Organisation-specific team creation.
- Independent submit, work and manage grants.
- Administrator-controlled permission changes.
- Transactional permission-management audit records.
- Mandatory destination-team validation.
- Database-enforced submit authorisation.
- Transactional case creation and audit attribution.

Selected controls have passed local PostgreSQL
security regression tests.

The complete work and manage permission model
has not yet been integrated and verified.

This dossier must not be interpreted as certification,
a penetration-test report or production approval.

## 2. Document governance

### 2.1 Purpose

Provide a traceable technical record of:

1. Intended requirements.
2. Implemented controls.
3. Security architecture.
4. Verification evidence.
5. Known limitations.
6. Release state.
7. Outstanding acceptance criteria.

### 2.2 Evidence principle

A requirement is not considered verified merely
because it appears in a design specification.

An implemented control is not considered
runtime-verified merely because its source exists.

A passing local regression is not equivalent
to hosted or production security assurance.

### 2.3 Evidence classifications

**DESIGNED:** Requirement or intended behaviour documented.

**IMPLEMENTED:** Relevant source or installed object inspected.

**LOCALLY TESTED:** Recorded local regression passed.

**PARTIALLY VERIFIED:** Some required controls tested,
but important integration or environment gaps remain.

**PENDING:** Required verification not completed.

**OUT OF SCOPE:** Not assessed by this feature dossier.

## 3. Feature scope

The feature covers organisation administration,
team provisioning, explicit permission grants,
permission revocation and authorised case submission.

It does not constitute the complete Madzera
access-control architecture.

Future workflows must extend the same principles
to case work, management, evidence and legacy cases.

## 4. Architecture baseline

The original design specification is preserved at:

`docs/features/058_team_permission_foundation_design.md`

The current implementation assessment is:

`docs/features/058_063_team_permission_implementation_status.md`

The security architecture and threat model are:

`docs/security/058_063_team_permission_security_architecture.md`

These documents have different evidentiary roles
and must not be treated as interchangeable.

## 5. Migration inventory

| Migration | Capability |
|---|---|
| 058 | Organisation administrators, permission schema and audit foundation |
| 059 | Controlled grant and revocation functions |
| 060 | Privileged initial administrator provisioning |
| 061 | Effective team-permission helper |
| 062 | Secure organisation-team creation |
| 063 | Mandatory destination-team submission authorisation |

The migration files are implementation evidence.

Installed database inspection and regression
execution provide additional evidence.

## 6. Security control register

| Control ID | Control | Verification position |
|---|---|---|
| CTRL-01 | Active authenticated employee identity | Installed helper inspected |
| CTRL-02 | Explicit organisation administrator authority | Implemented; locally tested |
| CTRL-03 | Organisation-scoped permission grants | Implemented; locally tested |
| CTRL-04 | Permission-type separation | Locally tested |
| CTRL-05 | Controlled permission grant/revoke | Locally tested |
| CTRL-06 | Transactional permission audit | Locally tested |
| CTRL-07 | Controlled initial administrator provisioning | Locally tested |
| CTRL-08 | Administrator-only team creation | Locally tested |
| CTRL-09 | Transactional team creation audit | Locally tested |
| CTRL-10 | Mandatory destination team | Locally tested |
| CTRL-11 | Database-enforced submit permission | Locally tested |
| CTRL-12 | Cross-organisation submission rejection | Locally tested |
| CTRL-13 | Rejected submission rollback integrity | Locally tested |
| CTRL-14 | Complete work permission enforcement | Pending |
| CTRL-15 | Complete manage permission enforcement | Pending |
| CTRL-16 | Revocation across existing case access | Pending |
| CTRL-17 | Legacy case access compatibility | Pending |
| CTRL-18 | Existing locking and Save regression | Pending |
| CTRL-19 | Hosted API and browser security | Pending |

Detailed requirement-to-test mappings are maintained
in TEST_MATRIX.md.

## 7. Verification execution register

| Test | Primary scope | Recorded result |
|---|---|---|
| 038 | Permission helper and tenant isolation | PASS |
| 039 | Secure organisation-team provisioning and audit integrity | PASS |
| 040 | Mandatory team submission security | PASS — 11 checks |
| 041 | Administrator-to-submission integration, including a permission grant | PASS — 7 checks |

These are recorded local database regressions.

Tests 040 and 041 were source-reviewed and
fingerprinted during the evidence review.

Their execution does not establish hosted
Supabase or browser-level security.

The detailed execution history is maintained
in TEST_RESULTS.md.

### 7.1 Regression source traceability

| Test | SQL source file |
|---|---|
| 038 | `database/tests/038_team_permission_authorisation_security.sql` |
| 039 | `database/tests/039_secure_organisation_team_provisioning_security.sql` |
| 040 | `database/tests/040_mandatory_destination_team_submission_security.sql` |
| 041 | `database/tests/041_end_to_end_team_submission_integration.sql` |

**Test 039 source SHA-256:**

`372d744f17ca64d4ca96983113c01ab57801586add2e842e559597bd7f386416`

Test 039 verifies secure organisation-team provisioning,
including administrator authority, tenant isolation,
invalid-name rejection, inactive-administrator denial,
audit attribution and rollback on injected audit failure.

It does not directly test the grant_team_permission
or revoke_team_permission management RPCs.

Test 041 exercises an administrator-issued submit grant
as part of the database integration workflow.

These source inspections must not be confused with
independent re-execution of the regression tests.

## 8. Database security verification

The local database inspections covered:

- Active employee identity resolution.
- Organisation identity resolution.
- Organisation-scoped foreign keys.
- Permission constraints and uniqueness.
- Row-level security configuration.
- Application-role table privileges.
- Privileged function execution rights.
- Private schema access.
- Installed case-creation authorisation.

The inspected ordinary application roles
were denied direct access to the protected
permission-management tables.

Privileged database roles remain trusted
within the architecture.

No claim of tamper-proof audit history
is made.

## 9. Trust boundary verification

The security architecture identifies
five principal boundaries:

1. Client to authenticated application.
2. Authenticated role to privileged RPC.
3. Privileged RPC to protected database tables.
4. Organisation to organisation.
5. Trusted database operator to system data.

The database must remain authoritative
for sensitive authorisation decisions.

Frontend checks may improve usability
but must not substitute for database
validation.

## 10. Auditability assessment

The reviewed implementation records:

- Permission grants.
- Permission revocations.
- Initial administrator provisioning.
- Organisation-team creation.
- Case creation attribution.

The corresponding operations use
transactional audit insertion.

Ordinary application-role access to
the inspected audit tables is restricted.

Audit immutability against privileged
database operators has not been proven.

A future operational assurance programme
should address audit retention, access,
export, monitoring and incident review.

## 11. Privacy-first architecture assessment

The tested feature demonstrates selected
organisation-scoped access controls.

It does not independently verify the
broader proposed customer-environment
intelligence architecture.

Specifically, this dossier does not
prove that all operational customs
documents remain customer-side.

Nor does it establish complete compliance
with PAS 41201 or any other standard.

Such claims require a separate,
system-wide evidence programme.

## 12. Existing workflow compatibility

The implementation was designed not
to change the existing exclusive
case-locking mechanism.

The existing Save action remains a
separate responsibility-claim operation.

However, the present evidence does
not constitute a complete regression
of locking, renewal, release, expiry
and Save behaviour.

This remains an explicit release gate.

## 13. Release evidence

**Local database:** Migration 063 installed.

**Local regression:** Selected post-installation
security tests recorded as passing.

**Backup:** Pre-migration database archive
created and structurally inspected.

**Backup restore:** Not independently tested.

**Git:** Commit f87f70a created and pushed
to origin/main.

**Hosted Supabase:** Migration 063 not deployed.

**Production release:** Not approved by
this verification dossier.

Source control publication and database
deployment are distinct release activities.

## 14. Residual risk and limitations

The authoritative risk register is
maintained in the security architecture
document as SEC-R01 through SEC-R12.

Principal outstanding areas include:

- Work and manage permission integration.
- Revocation across existing case sessions.
- Legacy unassigned-case handling.
- Evidence-access enforcement.
- Hosted deployment verification.
- Authenticated API and browser testing.
- Concurrency and idempotency.
- Privileged audit access.
- Administrator succession and recovery.
- Locking and Save regression.

No numerical severity assessment
has yet been approved.

## 15. Production acceptance gates

Before production approval, the following
evidence should be obtained:

| Gate | Requirement | Current position |
|---|---|---|
| GATE-01 | Complete intended permission enforcement | Open |
| GATE-02 | Revocation across relevant workflows | Open |
| GATE-03 | Locking and Save regression | Open |
| GATE-04 | Legacy case policy | Open |
| GATE-05 | Hosted migration and privilege verification | Open |
| GATE-06 | Authenticated API adversarial testing | Open |
| GATE-07 | Browser integration testing | Open |
| GATE-08 | Concurrency and idempotency testing | Open |
| GATE-09 | Operational security and recovery review | Open |
| GATE-10 | Formal release approval | Open |

A release decision must distinguish
critical launch requirements from
deliberately deferred functionality.

This dossier does not independently
make that release decision.

## 16. Evidence register

| Evidence ID | Artifact | Role |
|---|---|---|
| EVD-001 | Feature 058 original design | Requirements baseline |
| EVD-002 | Feature 058–063 implementation status | Implementation assessment |
| EVD-003 | Security architecture document | Trust boundaries and threat model |
| EVD-004 | TEST_MATRIX.md | Requirement-to-test traceability |
| EVD-005 | TEST_RESULTS.md | Execution history |
| EVD-006 | Migrations 058–063 | Implementation source |
| EVD-007 | Tests 038–041 | Regression source |
| EVD-008 | Git commit f87f70a | Source release reference |
| EVD-009 | Local installed-object inspections | Configuration evidence |
| EVD-010 | Pre-Migration 063 backup | Recovery preparation evidence |

Evidence availability and completeness
vary by item.

The presence of an evidence reference
does not imply independent verification
of every associated claim.

## 17. Document integrity register

The initial source documents were
SHA-256 verified on 26 October 2026.

Their recorded checksums are:

**TEST_MATRIX.md**

47ab244b91a9f0c6b4924fd095fe523c1c77d4c315ff74710d15ad3e8a0cf484

**TEST_RESULTS.md**

6798cf1489d33919af838e844f83cad458740a56601ccf2234067254d8b1fafc

**Feature implementation status**

cac68f3f24204c05e4ff0112c69b781fecd1ec150779d4f63f07077277ec5a9a

**Security architecture**

7a30ae8314c1f54cd68a71f53c1a3737589fc274c21a9efe24300acdea1dedcd

These checksums identify the reviewed
documentation snapshots.

They do not independently attest to
the truth of every technical claim.

## 18. Verification statement

The evidence supports a locally tested
organisation administration and
mandatory case-submission security foundation.

It does not establish comprehensive
permission enforcement, production
security, hosted deployment or
regulatory certification.

The outstanding security requirements
must be addressed or explicitly
accepted through an authorised
release governance process.

**Document status:** Initial evidence compilation.
**Independent technical sign-off:** Not recorded.
**Production security sign-off:** Not recorded.
