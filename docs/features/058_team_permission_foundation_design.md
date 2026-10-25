# MADZERA FEATURE 058
## Organisation Administration and Team Permission Foundation

Status: Proposed — not implemented or security verified.

### 1. Objective

Introduce tenant-isolated, default-deny team permissions
without changing the existing case locking mechanism.

### 2. Organisation administration

Maintain an explicit organisation administrator authority
independent of the existing users.role field.

Administrators must be active employees of their organisation.

Initial administrator provisioning must use a controlled,
privileged setup process. No self-promotion is permitted.

### 3. Team permissions

Support independent permission types:

- submit: Create or route cases to a team.
- work: Access and work cases assigned to a team.
- manage: Manage the team's membership and permissions,
  subject to the final administration policy.

Employees may have permissions across multiple teams.

All permissions must be organisation-scoped.

### 4. Effective permission enforcement

Permission checks must execute in the database.

Default deny when no valid permission exists.

Revocation must take effect on subsequent authorised
operations, including existing case access and evidence
download checks.

Existing case lock ownership alone must never establish
team authorisation.

### 5. Permission audit

Record:

- Organisation
- Acting administrator
- Affected employee
- Affected team
- Permission type
- Grant or revocation action
- Timestamp
- Optional reason and approval reference

Audit records must be written transactionally with
permission changes.

Ordinary employees must not be able to modify or delete
audit history.

### 6. Future approval workflow

Reserve architectural compatibility for:

Supervisor request -> Manager review ->
Organisation administrator decision -> Permission grant.

Requests and approvals must not themselves create
effective permissions.

Approval workflow implementation is outside MVP scope.

### 7. Legacy case compatibility

Existing cases without assigned teams must not be
arbitrarily assigned or exposed.

A separate, explicitly tested legacy-access policy
must be established before enforcement is enabled.

### 8. Security verification requirements

Test:

- Cross-organisation access rejection
- Unauthorised permission grants
- Unauthorised permission revocations
- Self-promotion rejection
- Permission revocation effectiveness
- Audit completeness and rollback
- Multiple team memberships
- Existing case locking regression
- Existing case creation regression
- Legacy cases without assigned teams

### 9. Implementation sequencing

058: Permission schema and administration foundation.
Subsequent migrations: Integrate permissions into case
creation, queue, case sessions, comments and evidence.

No production-readiness claim until negative security
tests and regression tests pass.
