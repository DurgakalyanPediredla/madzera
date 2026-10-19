# Madzera — Case Workspace, Assignment, Activity and Audit

## Implementation status

Implemented and browser-tested on 19 October 2026.

This feature extends Madzera's employee case workspace with
persistent responsibility assignment, internal comments, audit
history and verified browser-refresh recovery.

## Architecture

- Frontend: Next.js, React and TypeScript.
- Authentication: Supabase Auth.
- Database: Supabase PostgreSQL.
- Security: authenticated employee identity, organisation scoping,
  row-level security and SECURITY DEFINER RPC validation.
- Lock authority: PostgreSQL, not browser state.
- Browser recovery hint: tab-scoped sessionStorage.

## Exclusive case access

Opening a case uses the existing open_case_session RPC.

The existing exclusive lock prevents another employee from entering
the case while a valid lock is held.

The existing renew_case_lock RPC maintains the lease, with its
established renewal and expiry handling unchanged.

The existing close_case_session RPC releases the lock when the
employee explicitly selects Back to cases.

The browser does not grant access merely because a saved token exists.
All protected data remains behind server-side lock verification.

## Persistent case ownership

Migration:
database/migrations/035_save_employee_case_assignment.sql

RPC: save_employee_case_assignment

An employee may save responsibility for a case while holding its
exclusive lock. This assignment persists independently of the lock.

Reassignment requires confirmation in the interface. Saving
responsibility does not release the case lock.

The case workspace displays the saved Case Owner.

## Internal case comments

Migration:
database/migrations/036_save_employee_case_comment.sql

RPC: save_employee_case_comment

Comments are validated server-side, associated with the case and
employee, and saved without releasing the lock.

Migration:
database/migrations/037_get_employee_case_comments.sql

RPC: get_employee_case_comments

The case workspace loads persisted comments with their authors.

Tests:
database/tests/020_save_employee_case_comment.sql
database/tests/021_get_employee_case_comments.sql

## Case audit history

Migration:
database/migrations/038_get_employee_case_audit_history.sql

RPC: get_employee_case_audit_history

The workspace provides Case Record and Audit History tabs.

Audit history is scoped to the authenticated employee's organisation
and requires a valid owned case lock.

The audit interface displays available event, actor, timestamp,
status and assignment information.

Test:
database/tests/022_get_employee_case_audit_history.sql

## Browser refresh recovery

Migration:
database/migrations/039_resume_employee_case_session.sql

RPC: resume_employee_case_session

The RPC verifies:
- Authenticated active employee identity.
- Organisation ownership.
- Case and lock relationship.
- Employee ownership of the existing lock.
- Exact lock-token match.
- Unexpired lease.

The RPC returns the verified expiry timestamp or NULL.
It does not create, renew or release a lock.

Frontend:
web/src/app/cases/[caseId]/caseSessionRecovery.ts
web/src/app/cases/[caseId]/CaseWorkspace.tsx

The frontend stores the case ID, authenticated user ID and lock
token in sessionStorage as a recovery hint.

On refresh, it asks PostgreSQL to validate the saved token before
loading protected case details. If recovery fails, it attempts
the normal case-opening flow.

A successful explicit Back to cases release clears the saved token.

Test:
database/tests/023_resume_employee_case_session.sql

## Loading experience

The case workspace uses a short loading grace period and a neutral
skeleton rather than briefly flashing an access-verification message.

Loading placeholders contain no client or case operational data.

## Security boundaries

- Browser storage is not an authorisation mechanism.
- Protected RPCs enforce server-side access checks.
- Lock ownership and expiry are validated in PostgreSQL.
- Assignment and comment saves do not release the exclusive lock.
- Internal comments and audit data are not exposed through
  unrestricted authenticated table access.
- A duplicated browser tab may inherit sessionStorage; browser-tab
  uniqueness is not guaranteed by this implementation.

## Known limitations

1. Unexpected navigation, browser Back, tab closure or browser
   termination may leave the database lock active until lease expiry.
   Explicit Back to cases performs a confirmed release.
2. File attachments are not implemented in the current activity editor.
3. Session recovery is limited to a valid, unexpired existing lock.
4. The frontend loading skeleton improves perceived responsiveness;
   it is not evidence of lower database latency.
5. Multi-user concurrency, unexpected-navigation recovery and
   performance under production-scale workloads require further
   dedicated testing.

## Verification completed

- Local database regression tests for migrations 036–039 passed.
- Migration 039 regression test: seven checks passed.
- Hosted SQL deployment of migrations 035–039 completed.
- Browser checks: case opening, assignment, comments, audit history,
  repeated refresh recovery and explicit Back navigation.
- TypeScript validation: npx tsc --noEmit.
- Whitespace validation: git diff --check.

## Deployment and version control

Keep migrations and tests under database/.

Do not assume local migrations are automatically deployed to hosted
Supabase. Verify each environment independently.

Commit the implementation, migrations, regression tests and this
document together.

Do not commit:
web/src/app/cases/[caseId]/page.demo.backup.txt
