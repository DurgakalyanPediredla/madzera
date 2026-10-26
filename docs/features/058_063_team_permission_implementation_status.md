# MADZERA ENGINEERING FEATURE RECORD
## Organisation Administration and Team Permission Foundation

**Feature reference:** 058–063

**Document classification:** Engineering implementation status

**Assessment date:** 26 October 2026

**Status:** Partially implemented; locally verified within stated scope

**Source commit:** f87f70ad2d3c53081585136bfe079f2ddc0d4f25

**Deployment status:** Migration 063 installed locally; hosted deployment not performed

---

## 1. Document purpose

This document records the implementation status of the
organisation administration and team permission foundation.

It supplements, rather than replaces, the original design:

`docs/features/058_team_permission_foundation_design.md`

The original document represents the design requirements
at the time they were proposed.

This document distinguishes implemented controls,
locally verified behaviour, incomplete integration,
and deferred functionality.

It does not certify the system as production-ready.

## 2. Business and architectural objective

Madzera is designed as a configurable multi-tenant
operational assurance platform.

Different organisations may have different teams,
structures, responsibilities and workflows.

The application must not assume a universal team
hierarchy or hardcoded department structure.

Each organisation requires independent administration
and explicit permission management.

Permission enforcement must occur at the database
boundary rather than depend exclusively on the UI.

## 3. Implementation inventory

| Migration | Responsibility |
|---|---|
| 058 | Organisation administrators, team permission grants, audit records and relational constraints |
| 059 | Secure permission granting and revocation |
| 060 | Controlled initial organisation-administrator provisioning |
| 061 | Effective team-permission authorisation helper |
| 062 | Secure organisation-team provisioning and audit |
| 063 | Mandatory destination-team submission authorisation |

These migrations form a related security capability
but have distinct responsibilities.

## 4. Organisation administration

Organisation administrator authority is represented
independently of the existing users.role field.

Initial administrator provisioning is performed
through a privileged database function.

Application roles cannot directly execute that
initial provisioning function.

Team provisioning and permission-management functions
validate the acting employee and their organisation
administrator authority.

Active employee identity is resolved using database
helpers that require a linked authenticated user
and an active employee record.

**Status:** Implemented and locally tested.

## 5. Team permission model

The foundation defines three independent permissions:

- `submit`: Authorise submission to a destination team.
- `work`: Intended to authorise working on team cases.
- `manage`: Intended to authorise permitted team-management actions.

Permissions are explicitly granted.

No implicit permission inheritance is established
merely through colleague relationships or other
permission types.

Database constraints bind team and employee
relationships to their organisation.

The authorisation helper returns a denial when
a valid explicit permission is absent.

**Status:** Permission storage and checking implemented.

**Limitation:** Complete downstream enforcement of
`work` and `manage` is not established by this feature.

## 6. Case submission workflow

The case creation workflow requires an explicit
destination team.

The frontend retrieves teams and checks whether
the current employee has `submit` permission.

The database independently validates:

1. The employee is authenticated and active.
2. The employee belongs to an organisation.
3. The destination team is supplied.
4. The destination team belongs to that organisation.
5. The employee has explicit `submit` permission.
6. Other case input and customer ownership rules pass.

Successful creation inserts the case and its
creation audit event transactionally.

The frontend permission filter is a usability
control, not the authoritative security boundary.

**Status:** Implemented and locally tested.

## 7. Permission administration and auditing

Permission grants and revocations are performed
through controlled database functions.

The functions validate organisation administrator
authority and relevant organisation relationships.

Permission changes create corresponding audit
records within the database transaction.

Team creation also creates an administration
audit event.

The inspected permission and administration tables
deny direct access to ordinary anonymous and
authenticated application roles.

**Status:** Implemented and locally tested.

**Limitation:** Audit immutability against privileged
database operators has not been established.

## 8. Tenant isolation

The implementation uses multiple complementary
tenant-isolation controls:

- Organisation-scoped relational constraints.
- Organisation-aware employee identity helpers.
- Explicit permission checks.
- Organisation validation inside privileged RPCs.
- Restricted direct application-role table privileges.
- Database-side case submission authorisation.

These controls provide defence in depth for
the tested operations.

They do not establish that every current and
future application workflow is tenant-isolated.

## 9. Existing case locking and Save behaviour

The existing case workflow uses an exclusive lock
when an employee enters a case.

The Save action records responsibility without
intentionally releasing the existing lock.

Migrations 058–063 were not intended to redesign
the existing lock acquisition, renewal, release
or expiry behaviour.

Lock ownership must not substitute for team
authorisation in future access enforcement.

**Status:** Existing behaviour preserved by design.

**Verification gap:** A dedicated regression is
required before claiming complete compatibility.

## 10. Legacy case compatibility

Historical cases without assigned teams must not
be arbitrarily reassigned or exposed.

A separately designed and tested access policy
is required before introducing mandatory
team-work enforcement over legacy records.

**Status:** Outstanding integration requirement.

## 11. Future approval workflow

The intended future workflow is:

Supervisor request
-> Manager review
-> Organisation administrator decision
-> Permission grant.

Requests and approvals must not independently
create effective permissions.

The permission foundation should remain compatible
with such an auditable workflow.

**Status:** Deferred beyond the current MVP scope.

## 12. Verification evidence

Primary evidence:

- `database/tests/TEST_MATRIX.md`
- `database/tests/TEST_RESULTS.md`
- Tests 038–041
- Migrations 058–063
- Installed local database inspections
- Git commit f87f70a

Tests 040 and 041 cover mandatory team submission
and the administrator-to-submission integration.

Recorded results:

- Test 038: PASS
- Test 039: PASS
- Test 040: PASS — 11 checks
- Test 041: PASS — 7 checks

These results relate to local PostgreSQL
regression execution.

## 13. Outstanding security and engineering work

The following items remain outside the
established verification scope:

- Full `work` permission integration.
- Full `manage` permission integration.
- Existing-case access after permission revocation.
- Evidence access after permission revocation.
- Legacy unassigned-case access policy.
- Existing lock and Save regression testing.
- Browser-based end-to-end security testing.
- Hosted authenticated API testing.
- Concurrent submission and idempotency testing.
- Full backup restoration testing.
- Independent security assessment.
- Hosted Migration 063 deployment.

## 14. Privacy-first architecture assessment

The inspected controls demonstrate organisation
isolation and restricted access to the
permission-management and case-submission operations
covered by this feature.

They do not independently demonstrate that all
operational customs data remains in the customer's
environment, or that the entire platform meets
a particular regulatory or certification standard.

Those broader architectural claims require
separate system-wide evidence.

## 15. Engineering conclusion

Migrations 058–063 establish a locally tested
foundation for organisation administration,
explicit team permissions, audited administration
and mandatory authorised case submission.

This is a meaningful security capability,
but it is not the complete team-access model.

The remaining work must be verified before
claiming full team-work authorisation,
production readiness or certification compliance.
