# MADZERA SECURITY ARCHITECTURE
## Organisation Administration, Team Permissions and Case Submission

**Security record:** SEC-058-063

**Assessment date:** 26 October 2026

**Classification:** Internal engineering and security assurance

**Implementation reference:** Migrations 058–063

**Source commit:** f87f70ad2d3c53081585136bfe079f2ddc0d4f25

**Verification environment:** Local Supabase PostgreSQL

**Deployment status:** Migration 063 not deployed to hosted Supabase

**Assurance status:** Partially verified; outstanding controls documented

---

## 1. Executive security summary

Madzera implements an organisation-scoped permission
foundation for configurable customs intermediary teams.

The architecture uses database-level controls to
restrict organisation administration, permission
management and case submission.

The reviewed implementation provides:

- Explicit organisation administrator authority.
- Active authenticated employee identity checks.
- Organisation-scoped team permission grants.
- Independent submit, work and manage permission types.
- Controlled administrator operations.
- Transactional permission and team creation audits.
- Mandatory destination-team validation.
- Database-enforced submit permission.
- Restricted direct application-role access to
  permission-management tables.

These controls have been inspected and selectively
tested in the local PostgreSQL environment.

This assessment does not establish complete
production readiness or system-wide tenant isolation.

## 2. Scope and boundaries

### In scope

- Organisation administrator provisioning.
- Team permission data model.
- Permission grant and revocation.
- Team provisioning.
- Effective submit permission checks.
- Case creation authorisation.
- Associated audit records.
- Relevant database privileges and constraints.

### Out of scope

- Complete case work authorisation.
- Complete manage permission enforcement.
- Existing case access after revocation.
- Evidence download authorisation after revocation.
- Full browser/API security testing.
- Supabase Storage object-level security.
- Infrastructure and network security.
- Production secret management.
- Customer-hosted intelligence processing.
- Full PAS 41201 compliance assessment.

## 3. Protected assets

The relevant protected assets include:

1. Organisation administrator authority.
2. Team membership and permission assignments.
3. Organisation-specific team configuration.
4. Case creation authority.
5. Case and employee attribution.
6. Permission and administration audit history.
7. Organisation boundaries and identifiers.
8. Employee authentication-to-identity mappings.

Unauthorised modification or disclosure of these
assets could undermine tenant isolation,
operational accountability or case integrity.

## 4. Trust boundaries

### Boundary A — Client to authenticated application

The frontend may display available teams and
filter destinations using submit permission.

Frontend filtering is not trusted as the
authoritative access-control mechanism.

Requests must be revalidated by the database.

### Boundary B — Authenticated role to privileged RPC

Authenticated users may execute selected public
management functions.

These functions use SECURITY DEFINER and therefore
cross a database privilege boundary.

Their internal validation must establish:

- Active authenticated employee identity.
- Organisation identity.
- Required administrator authority.
- Same-organisation resource ownership.
- Valid operation parameters.

EXECUTE permission alone does not establish
authorisation to complete a privileged operation.

### Boundary C — Privileged function to protected tables

The inspected permission-management tables deny
direct access to ordinary application roles.

Privileged functions perform controlled mutations
and record associated audit events.

Database ownership and privileged operational
roles remain separate trust assumptions.

### Boundary D — Organisation to organisation

Team and employee relationships are constrained
by organisation identifiers.

Privileged functions independently validate
organisation ownership.

The submit permission helper denies access
without a matching explicit grant.

These controls must also be applied to future
work, manage and evidence operations.

### Boundary E — Trusted database operator

Initial administrator provisioning requires
the postgres execution identity.

The private provisioning function is not
executable by anonymous, authenticated or
service_role application roles in the inspected
local configuration.

Trusted database operators remain powerful
and require operational controls outside
the scope of these migrations.

## 5. Authentication and identity

The reviewed identity helpers derive the
employee and organisation from auth.uid().

They require an active employee record
linked to the authenticated identity.

An inactive or unlinked identity does not
resolve to an authorised employee.

Privileged functions reject requests when
the required identity cannot be resolved.

This design avoids trusting caller-supplied
employee or organisation identifiers as
the primary authority source.

## 6. Administrator authority

Organisation administrator authority is
represented independently of users.role.

The grant, revoke and team-creation RPCs
verify the actor against the organisation
administrator relationship.

Initial provisioning requires a privileged
database operator, an active authenticated
target employee and a recorded reason.

The provisioning function locks the
organisation row before checking whether
an initial administrator already exists.

This provides a serialisation mechanism
for initial provisioning attempts.

Concurrent behaviour has not been
independently stress-tested.

Administrator succession, removal and
recovery are not covered by this feature.

## 7. Permission model

The foundation recognises:

| Permission | Intended capability | Established enforcement |
|---|---|---|
| submit | Submit cases to a team | Database-enforced in Migration 063 |
| work | Work on cases assigned to a team | Not comprehensively integrated |
| manage | Perform authorised team-management activities | Not comprehensively integrated |

Permissions are explicit and organisation-scoped.

The existence of a work or manage grant
does not automatically establish effective
authorisation in every downstream workflow.

Permission revocation is effective for
subsequent checks using the permission helper.

Its effect on all existing sessions, locks,
case reads and evidence operations remains
an outstanding integration requirement.

## 8. Case submission authorisation

The installed case-creation implementation
performs database-side validation.

Relevant controls include:

- Active authenticated employee resolution.
- Organisation identity resolution.
- Mandatory destination team.
- Destination-team organisation validation.
- Explicit submit permission.
- Existing case input validation.
- Customer organisation validation.
- Transactional case and audit insertion.

A rejected submission must not leave a
corresponding persisted case or creation
audit event.

Local Tests 040–041 provide regression
evidence for selected positive and
negative submission scenarios.

## 9. Data isolation and relational integrity

The permission schema uses composite
organisation-scoped foreign keys.

Relevant relationships include:

- Organisation administrators to employees.
- Permission grants to teams and employees.
- Permission audit actors and targets.
- Team creation audit actors and teams.

These constraints reduce the risk of
cross-organisation relationships being
created accidentally or maliciously.

They complement, but do not replace,
runtime authorisation checks.

## 10. Row-level security and table privileges

The inspected administration and permission
tables have RLS enabled.

No RLS policies were installed on the
four inspected tables.

Anonymous and authenticated roles lacked
direct SELECT, INSERT, UPDATE and DELETE
privileges on those tables.

The service_role retained inspected direct
privileges on three tables, while the
organisation administration audit table
did not expose those privileges to service_role.

The tables were owned by postgres and
did not use FORCE ROW LEVEL SECURITY.

Therefore RLS configuration alone must not
be described as a guarantee against
privileged database access.

## 11. Privileged function hardening

The reviewed management functions use:

- SECURITY DEFINER.
- postgres function ownership.
- An explicitly empty search_path.
- Schema-qualified object references.
- Explicit authenticated EXECUTE grants.
- Internal identity and administrator checks.

The initial administrator provisioning
function instead uses SECURITY INVOKER
and restricts execution to postgres.

The privileged function boundary requires
ongoing regression testing whenever
identity helpers, grants or schema
relationships change.

## 12. Audit architecture

Permission grant and revocation operations
insert corresponding permission audit events.

Initial administrator provisioning records
an administrator-grant event.

Organisation-team creation records a
team-created administration event.

Case creation records a case_created event.

The relevant business operation and audit
insert occur within the same transaction.

An audit insertion failure therefore
prevents successful completion of the
corresponding transaction.

Direct ordinary application-role access
to the inspected administration and
permission audit tables is restricted.

The audit records are not independently
demonstrated immutable against privileged
database operators.

## 13. Threat model

| Threat | Existing mitigation | Residual risk |
|---|---|---|
| Anonymous caller attempts management RPC | EXECUTE restrictions | Other exposed endpoints require separate review |
| Employee attempts unauthorised grant | Administrator validation | Future management paths require equivalent checks |
| Employee targets another organisation | Organisation validation and relational constraints | System-wide enforcement not established |
| Inactive employee attempts privileged action | Active identity helpers | Existing sessions and external integrations require review |
| Employee submits without submit grant | Database permission check | Concurrency and idempotency remain unverified |
| Employee uses work grant to submit | Independent permission types | Other workflows must enforce intended permissions |
| Employee continues work after revocation | Future work-authorisation checks required | Not comprehensively implemented |
| Frontend permission check bypassed | Database-side submit validation | All future RPCs need equivalent enforcement |
| Audit modification by ordinary employee | Restricted direct table privileges | Privileged operators remain trusted |
| Compromised service credentials | Privilege restrictions vary by table | Service-role access and secret protection require operational controls |
| Concurrent administrator provisioning | Organisation row lock | Concurrency regression not recorded |
| Duplicate case submissions | Existing case validation | Idempotency not comprehensively established |

## 14. Privacy-first architecture boundaries

This feature provides database-level
organisation isolation and access controls
for the inspected administrative and
case-submission operations.

It does not establish that operational
customs documents remain entirely within
a customer's infrastructure.

It does not establish the complete
customer-environment intelligence architecture.

Such claims require separate evidence
covering data flows, storage locations,
retention, encryption, integrations,
access logs and infrastructure controls.

## 15. Security verification evidence

Primary evidence sources:

- Migrations 058–063.
- Tests 038–041.
- TEST_MATRIX.md.
- TEST_RESULTS.md.
- Feature implementation-status document.
- Installed database inspections, Steps 2477–2481.
- Test source inspection, Step 2482.
- Source commit f87f70a.

Recorded local regression outcomes:

- Test 038: PASS.
- Test 039: PASS.
- Test 040: PASS — 11 checks.
- Test 041: PASS — 7 checks.

These outcomes do not establish hosted
deployment or browser-level penetration testing.

## 16. Residual risk register

| ID | Risk | Status |
|---|---|---|
| SEC-R01 | Incomplete work permission enforcement | Open |
| SEC-R02 | Incomplete manage permission enforcement | Open |
| SEC-R03 | Revocation not verified across existing case sessions | Open |
| SEC-R04 | Legacy unassigned-case policy incomplete | Open |
| SEC-R05 | Evidence access not comprehensively integrated | Open |
| SEC-R06 | Hosted Migration 063 not deployed | Open |
| SEC-R07 | Browser/API adversarial testing incomplete | Open |
| SEC-R08 | Concurrent requests and idempotency not verified | Open |
| SEC-R09 | Privileged database operators can affect audit integrity | Open |
| SEC-R10 | Administrator succession and recovery not designed | Open |
| SEC-R11 | Existing case locking and Save regression outstanding | Open |
| SEC-R12 | Customer-side data processing architecture not verified here | Out of scope |

Risk severity and ownership require a
separate formal assessment.

## 17. Security acceptance criteria

Before production acceptance, the team
should establish evidence that:

1. Every sensitive operation enforces
   the appropriate effective permission.
2. Revocation is effective across all
   relevant subsequent operations.
3. Existing locking and Save behaviour
   remains correct.
4. Legacy cases have an explicit
   tested access policy.
5. Hosted database permissions match
   the approved migration state.
6. Authenticated API and browser
   adversarial tests pass.
7. Audit events are complete and
   protected to the required assurance level.
8. Operational access, backups,
   secrets and incident procedures
   have been reviewed.

## 18. Security conclusion

The inspected implementation establishes
a meaningful database-enforced foundation
for tenant-scoped administration,
permission management and authorised
case submission.

The recorded local regression results
support the specific tested scenarios.

This is not a complete security assessment
of the Madzera platform.

The documented residual risks must be
addressed or formally accepted before
production deployment.
