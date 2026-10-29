# MADZERA
# ENGINEERING AND SECURITY VERIFICATION DOSSIER

## Feature 067
### Operational Case Work Authorisation and Immediate Permission Revocation

**Document ID:** MADZERA-ENG-SEC-067

**Version:** 0.1 — Controlled evidence compilation

**Date:** 28 October 2026

**Classification:** Internal engineering and security assurance

**Implementation:** `database/migrations/067_operational_case_work_authorisation.sql`

**Verification environment:** Local Docker Supabase PostgreSQL

**Hosted deployment:** Not established by this dossier

**Assurance classification:** Selected database-level security controls locally verified

**Document status:** In progress — additional technical sections pending

**Independent security sign-off:** Not recorded

**Production approval:** Not granted

---

## 1. Executive summary

Migration 067 extends Madzera's organisation-scoped team-permission
foundation into operational case workflows.

The principal security objective is to require effective team-work
authorisation for protected case activities, including when an
employee already possesses a valid exclusive case lock.

The feature addresses case access, assignment Save, updates,
comments, audit-history retrieval, evidence operations, Storage
authorisation and active-lock visibility.

The implementation must preserve Madzera's existing automatic
exclusive locking and assignment workflow while preventing a
revoked employee from continuing protected operations.

Selected local PostgreSQL security regressions have passed.
The retained executions of Tests 057–060 report 116 PASS
markers, zero reported failures, zero SQL errors and four
confirmed transaction rollbacks.

These results support the tested database security boundaries.
They do not independently establish complete production
security, hosted deployment, browser integration, concurrent
access safety or regulatory certification.

## 2. Document governance

### 2.1 Purpose

Provide a controlled, traceable record of the feature's
requirements, implementation, security architecture,
verification evidence, limitations and release conditions.

### 2.2 Evidence classification

This dossier distinguishes:

1. **Implemented:** Behaviour established by reviewed source.
2. **Locally verified:** Behaviour demonstrated by a recorded
   local test or inspection.
3. **Pending verification:** A requirement without sufficient
   execution evidence.
4. **Deferred:** Functionality deliberately excluded from
   this implementation scope.
5. **Not approved:** Production or security acceptance that
   has not been formally granted.

A function reference or design intention alone does not
constitute independent behavioural verification.

### 2.3 Source-of-truth hierarchy

- SQL migrations establish the reviewed database implementation.
- Regression SQL establishes the scenarios and assertions.
- Execution logs establish recorded local test outcomes.
- `TEST_MATRIX.md` maps requirements to evidence.
- `TEST_RESULTS.md` retains execution history.
- Feature and security architecture documents provide context.
- Git history establishes source revision and publication state,
  where separately verified.

### 2.4 Change control

Changes to this dossier must preserve historical evidence
and distinguish new verification from earlier assessments.

Evidence fingerprints identify source and log snapshots.
They do not independently certify the correctness of the
underlying implementation.

## 3. Feature scope and architectural context

### 3.1 Business context

Madzera provides a privacy-first operational assurance and
case-management layer for customs intermediaries.

It is not a customs declaration submission system.

Organisations may have different team structures and
operating models. Team names, membership and authorisation
must therefore remain configurable by organisation.

### 3.2 Existing permission foundation

Migrations 058–063 established the earlier foundation for
organisation administration, team permissions and mandatory
destination-team submission.

Migration 067 extends operational enforcement of the
`work` permission.

The `submit`, `work` and `manage` permission types are
distinct and must not be treated as interchangeable.

### 3.3 Protected workflow

The relevant operational sequence is:

1. An authenticated employee accesses an authorised case.
2. The existing session mechanism acquires an exclusive lock.
3. The employee may Save/claim responsibility and perform
   permitted case operations.
4. Permission checks must continue to apply after the lock
   has been acquired.
5. Revocation must prevent subsequent protected operations.
6. Denied operations must not create unintended changes.
7. Controlled session closure must remain available where
   required to release an owned lock safely.

### 3.4 Privacy and tenant-isolation principles

- Authorisation is organisation-scoped.
- Team-work permission is evaluated for the relevant case.
- Possession of a lock is not a substitute for permission.
- Protected evidence access must respect database and
  Storage security boundaries.
- Revocation should take effect on subsequent protected
  operations without relying solely on frontend controls.
- Audit and case integrity must be preserved when access
  is denied.

These are feature security principles; individual
implementation claims require the function-level evidence
recorded in subsequent sections.

## 4. Initial evidence baseline

### 4.1 Implementation fingerprint

**Migration 067 SHA-256:**

`7d32da0aa17fd2646bed48b7f5dd1c414194102b3212ac0eea05e51c077ef5f3`

### 4.2 Verification register

| Test | Focus | Recorded result |
|---|---|---|
| 057 | Operational case and Storage RLS revocation | 91 PASS; rollback confirmed |
| 058 | Active-lock visibility authorisation | 7 PASS; rollback confirmed |
| 059 | Evidence-reservation listing revocation | 8 PASS; rollback confirmed |
| 060 | Evidence recovery-status revocation | 10 PASS; rollback confirmed |

All four executions used local PostgreSQL test transactions.
No hosted deployment is established by these results.

### 4.3 Primary evidence references

- `database/tests/TEST_MATRIX.md`, Section 21.
- `database/tests/TEST_RESULTS.md`, Tests 057–060.
- `database/tests/045_case_work_authorisation_helper_security.sql`
  through Test 060, as applicable.
- `database/migrations/067_operational_case_work_authorisation.sql`.
- `docs/security/058_063_team_permission_security_architecture.md`.
- `docs/security/058_063_engineering_verification_dossier.md`.

### 4.4 Initial limitations

The current evidence does not independently establish
authenticated HTTP API enforcement, frontend compatibility,
concurrent revocation safety, hosted database deployment,
independent penetration testing or production approval.

---

## 5. Function-level security control register

### 5.1 Inspection methodology

Migration 067 was inspected at source level on 28 October 2026.

The inspection identified 16 function definitions. All 16 specify
`SECURITY DEFINER`, set an empty `search_path` and reference
`public.can_work_on_case`.

These are source-level findings. They do not independently prove
the correctness of every SQL predicate or every possible execution path.

The local database's installed Storage policies, RLS status and
three security-function privilege configurations were separately
inspected in Step 3080.

### 5.2 Central authorisation helper

**Function:** `public.can_work_on_case(uuid)`

**Migration source:** Lines 18–47.

The helper evaluates the current user's effective `work`
permission for the case's assigned team.

Its qualifying case lookup requires:

- The requested case identifier.
- A case belonging to `current_user_organisation_id()`.
- A non-null assigned team.
- A positive result from
  `has_team_permission(assigned_team_id, 'work')`.

`COALESCE(..., FALSE)` provides a false result where the
qualifying lookup does not produce an authorisation result.

The function is `SECURITY DEFINER`, uses an empty `search_path`
and has explicit execution grants to `authenticated` and
`service_role`, with `PUBLIC` and `anon` revoked.

**Security interpretation:** Current team-work permission is
a separate requirement from exclusive lock ownership.

### 5.3 Operational function register

| Function | Primary protected operation | Authorisation mechanism | Evidence |
|---|---|---|---|
| `can_work_on_case` | Case work eligibility | Organisation-scoped `has_team_permission(..., 'work')` | Source inspection; Test 057 |
| `get_locked_case_details` | Locked case details | Organisation, lock join, work eligibility | Source inspection; Test 057 |
| `save_employee_case_assignment` | Save/claim assignment | Employee identity, lock token, organisation, work eligibility | Source inspection; Test 057 |
| `update_employee_case` | Protected case updates | Employee identity, lock token, organisation, work eligibility | Source inspection; Test 057 |
| `save_employee_case_comment` | Save case comment | Employee identity, lock token, organisation, work eligibility | Source inspection; Test 057 |
| `get_employee_case_comments` | Retrieve case comments | Employee identity, case scope, lock, work eligibility | Source inspection; Test 057 |
| `get_employee_case_audit_history` | Retrieve case audit history | Employee identity, case scope, lock, work eligibility | Source inspection; Test 057 |
| `get_employee_case_evidence` | Retrieve evidence metadata | Employee identity, organisation, lock, work eligibility | Source inspection; Test 057 |
| `get_employee_case_evidence_download_path` | Retrieve evidence path | Employee identity, organisation, lock, work eligibility | Source inspection; Test 057 |
| `prepare_case_evidence_upload` | Create upload reservation | Employee identity, lock, organisation, work eligibility | Source inspection; Test 057 |
| `finalise_case_evidence_upload` | Finalise evidence upload | Reservation, employee identity, lock, work eligibility | Source inspection; Test 057 |
| `can_upload_reserved_case_evidence` | Storage upload predicate | Pending reservation, active employee, lock, work eligibility | Source inspection; Test 057 |
| `can_download_locked_case_evidence` | Storage download predicate | Completed reservation, internal attachment, active employee, lock, work eligibility | Source inspection; Test 057 |
| `get_case_evidence_upload_recovery_status` | Evidence recovery status | Employee identity, organisation, lock, work eligibility | Source inspection; Test 060 |
| `list_employee_case_evidence_upload_reservations` | List evidence reservations | Employee identity, organisation, lock, work eligibility | Source inspection; Test 059 |
| `get_active_case_locks` | Active-lock visibility | Organisation scope and work eligibility | Source inspection; Test 058 |

The evidence column identifies relevant inspected or executed
material; it does not assert exhaustive branch coverage.

### 5.4 Storage RLS trust boundary

**Inspected relation:** `storage.objects`.

The local database reports:

- Row-level security enabled.
- `FORCE ROW LEVEL SECURITY` disabled.
- Table owner: `supabase_storage_admin`.
- Exactly two installed policies.
- Both policies are permissive and target `authenticated`.

**INSERT policy:**
`case_evidence_reserved_employee_insert`

The policy restricts the `case-evidence` bucket and invokes
`can_upload_reserved_case_evidence(name)`.

**SELECT policy:**
`case_evidence_locked_employee_download`

The policy restricts the same bucket, invokes
`can_download_locked_case_evidence(name)` and restricts
Storage operations to authenticated object retrieval and
authenticated object metadata retrieval.

No additional policy was returned for `storage.objects`
in the inspected local database state.

### 5.5 Storage authorisation predicates

The upload helper checks:

1. A matching Storage path.
2. A pending, unexpired reservation.
3. An active employee matching `auth.uid()`.
4. An unexpired case lock owned by that employee.
5. Effective work permission for the reservation's case.

The download helper checks:

1. A matching attachment Storage reference.
2. Internal attachment visibility.
3. A completed evidence reservation.
4. Organisation-consistent case, lock, employee and reservation joins.
5. An active authenticated employee holding an unexpired lock.
6. Effective work permission for the attachment's case.

These conditions are evaluated by the database helper functions.
They are not merely frontend eligibility checks.

### 5.6 Function privilege inspection

The installed local database reports that:

- `can_work_on_case`
- `can_upload_reserved_case_evidence`
- `can_download_locked_case_evidence`

are owned by `postgres`, use `SECURITY DEFINER` and have an
empty `search_path`.

For all three, effective `EXECUTE` privileges were:

| Database role | Execute |
|---|---|
| `anon` | No |
| `authenticated` | Yes |
| `service_role` | Yes |

This privilege inspection covered these three functions,
not the complete set of 16.

### 5.7 Security interpretation and boundaries

The installed authenticated-user Storage policies and
authorisation helpers provide a database-side enforcement
path for the tested evidence operations.

A previously acquired exclusive lock does not, by itself,
satisfy the current work-permission requirement.

Test 057 supplies local execution evidence for selected
Storage RLS denial scenarios following permission revocation.

The inspection does not establish that privileged database
roles, table owners, service-role requests or hosted Storage
infrastructure are subject to identical restrictions.

The absence of additional policies in the inspected local
database does not establish that future or hosted
configurations will remain unchanged.

**Control status:** Source inspected, installed local
configuration inspected and selected regression scenarios
passed. Production acceptance remains pending.

## 6. Threat scenarios and trust boundaries

### 6.1 Threat-modelling scope

This assessment considers the operational authorisation
boundaries introduced or modified by Migration 067.

The protected assets include:

- Organisation-scoped case records.
- Case assignments, updates and comments.
- Case audit history.
- Evidence metadata and attachment references.
- Evidence upload reservations.
- Private evidence objects in Supabase Storage.
- Active case-lock information.
- Employee and team-permission relationships.

The assessment is based on inspected migration source,
installed local database configuration and recorded local
regression executions.

It is not an independent penetration test.

### 6.2 Trust boundaries

| Boundary | Trust transition | Required control |
|---|---|---|
| TB-01 | Authenticated employee to operational RPC | Resolve active employee and organisation identity |
| TB-02 | Employee to organisation-scoped case | Reject cases outside the employee's organisation |
| TB-03 | Employee to assigned-team case | Require effective `work` permission |
| TB-04 | Employee to locked case operation | Validate current exclusive lock ownership and expiry |
| TB-05 | Previously authorised employee to revoked employee | Re-evaluate work permission on subsequent protected operations |
| TB-06 | Application request to Storage object | Enforce authenticated Storage RLS and evidence-specific predicates |
| TB-07 | Evidence reservation to final attachment | Validate reservation, lock, case and relevant evidence state |
| TB-08 | Authenticated role to `SECURITY DEFINER` function | Restrict execution privileges and enforce identity and scope inside function |
| TB-09 | Privileged database or service role to protected data | Separate administrative trust and operational controls |
| TB-10 | Concurrent requests to mutable case state | Preserve integrity under overlapping operations; verification pending |

### 6.3 Threat and control register

| ID | Threat scenario | Intended or inspected mitigation | Evidence classification | Residual concern |
|---|---|---|---|---|
| TH-01 | Employee attempts to access another organisation's case | Organisation-scoped case predicates and identity helpers | Source inspected; selected local regressions | Full API and tenant-isolation matrix not established here |
| TH-02 | Employee has `submit` or `manage` but not `work` | `can_work_on_case` requires `work` | Source inspected; Test 058 local PASS | Other endpoints require separate review |
| TH-03 | Employee's work permission is revoked while their lock remains valid | Protected functions re-evaluate `can_work_on_case` | Tests 057, 059 and 060 local PASS | Concurrent revocation timing not established |
| TH-04 | Revoked employee attempts to Save or modify a case | Lock and current work-permission checks | Test 057 local PASS | Frontend behaviour pending |
| TH-05 | Revoked employee attempts to read comments or audit history | Identity, organisation, lock and work checks | Test 057 local PASS | Authenticated HTTP API pending |
| TH-06 | Revoked employee attempts evidence metadata or download-path access | Lock and current work-permission checks | Test 057 local PASS | End-to-end Storage download pending |
| TH-07 | Revoked employee attempts evidence upload or finalisation | Reservation, lock and work checks | Test 057 local PASS | Real Storage API behaviour pending |
| TH-08 | Revoked employee attempts direct Storage object access | Storage RLS calls work-aware authorisation helpers | Source and installed policies inspected; Test 057 local PASS | Hosted policies and privileged bypass pending |
| TH-09 | Revoked employee attempts to enumerate active locks | Organisation and work-filtered lock query | Test 058 local PASS | Other information-disclosure paths pending |
| TH-10 | Revoked employee attempts to enumerate upload reservations | Lock and work-permission checks | Test 059 local PASS | Concurrent reservation changes pending |
| TH-11 | Revoked employee attempts evidence recovery-status lookup | Lock and work-permission checks | Test 060 local PASS | API integration pending |
| TH-12 | Denied request unexpectedly changes case or evidence state | Fail-closed exceptions and regression state assertions | Selected Tests 057, 059 and 060 local PASS | Exhaustive side-effect coverage not established |
| TH-13 | Revoked employee cannot release an owned lock, causing operational blockage | Controlled session closure retained | Test 057 local PASS | Frontend release workflow pending |
| TH-14 | Caller exploits elevated `SECURITY DEFINER` privileges | Explicit identity, organisation and permission predicates; restricted function execution | Source and three-function privileges inspected | Full privilege and dependency audit pending |
| TH-15 | Privileged service-role or owner bypasses RLS | Administrative trust separation required | RLS configuration inspected | Privileged-access governance not verified |
| TH-16 | Concurrent revocation and case operation race | Transactional consistency and revalidation required | Not independently established | Concurrency tests pending |
| TH-17 | Future migration adds broader permissive Storage policy | Policy inventory and deployment review required | Local inventory found two policies | Future and hosted drift monitoring pending |
| TH-18 | UI relies on stale authorisation state | Backend must remain enforcement authority | Source-level backend controls inspected | Browser-level revocation tests pending |

### 6.4 Permission revocation with a surviving lock

A case lock and a team-work grant represent different
authorisation conditions.

The lock establishes temporary exclusive operational access.
The work grant establishes whether the employee is currently
authorised to perform protected case work.

The existence of one must not substitute for the other.

Migration 067's inspected protected functions use current
work-permission checks alongside their relevant lock checks.

The recorded local regression tests demonstrate selected
denials after permission revocation while the employee's
existing lock remains valid.

Controlled closure of an owned session is a deliberate
exception to the prohibition on continuing protected work.
Its purpose is safe resource release, not renewed access
to protected case information.

### 6.5 Fail-closed behaviour

The central `can_work_on_case` helper returns `FALSE`
where no qualifying authorisation result is available.

Several protected RPC functions raise SQLSTATE `42501`
when identity, lock or work-authorisation requirements
are not met.

Storage authorisation helpers return boolean predicates
used by the installed RLS policies.

Recorded local regressions verify selected denials and
preservation of relevant state.

These findings must not be interpreted as proof that
every possible error path is free of side effects.

### 6.6 Storage policy composition

The inspected local `storage.objects` relation has RLS
enabled and exactly two installed policies.

Both policies are permissive and restricted to
`authenticated`.

The INSERT policy delegates to
`can_upload_reserved_case_evidence(name)`.

The SELECT policy delegates to
`can_download_locked_case_evidence(name)` and restricts
the permitted authenticated Storage operations.

No additional Storage object policy was returned by
the local inspection.

PostgreSQL permissive policy composition means future
policies must be reviewed for unintended alternative
access paths.

`FORCE ROW LEVEL SECURITY` is disabled. Privileged roles
and service-role access are outside the established
authenticated-user assurance boundary.

### 6.7 Security-definer execution boundary

All 16 Migration 067 function definitions specify
`SECURITY DEFINER` and an empty `search_path`.

The installed privilege inspection established that
the three selected authorisation functions are not
executable by `anon` but are executable by
`authenticated` and `service_role`.

The remaining functions require their own installed
privilege and dependency review before claiming a
complete least-privilege assessment.

### 6.8 Residual threats and verification gaps

The following remain open:

- Authenticated HTTP API enforcement.
- Browser-level permission revocation and user experience.
- Concurrent revocation, lock renewal and case mutation.
- Full function-level privilege and dependency inspection.
- Privileged service-role and administrative access governance.
- Hosted Storage policy and database configuration parity.
- Future migration policy-composition controls.
- Independent security testing and formal approval.

### 6.9 Threat-model conclusion

The inspected architecture implements multiple database-side
authorisation conditions rather than relying solely on
frontend visibility or exclusive lock ownership.

Selected local regression tests support the effectiveness
of those controls for the tested revocation scenarios.

The evidence is sufficient to record local implementation
and regression findings, but not sufficient to declare
production-wide security assurance or certification.

**Threat assessment status:** Partially verified in local
database tests; residual risks and production acceptance
remain open.

## 7. Regression evidence and assertion traceability

### 7.1 Evidence methodology

This section traces the operational case-work authorisation
requirements to retained SQL test sources, execution logs
and observed local regression results.

The evidence baseline is dated 28 October 2026.

PASS markers are emitted test assertions or milestones.
They are not equivalent to independently certified
security controls or exhaustive behavioural coverage.

Tests used synthetic local PostgreSQL/Supabase fixtures.
Their execution transactions were rolled back.

### 7.2 Executed regression inventory

| Test | Scope | PASS markers | FAIL/ERROR | Actual ROLLBACK |
|---|---|---:|---:|---:|
| 057 | Case work, revocation, Storage RLS, safe exit | 91 | 0 | 1 |
| 058 | Active-lock visibility and team permissions | 7 | 0 | 1 |
| 059 | Evidence-reservation listing after revocation | 8 | 0 | 1 |
| 060 | Evidence recovery-status access after revocation | 10 | 0 | 1 |
| **Total** | **Selected local regressions** | **116** | **0** | **4** |

Test 060's log includes three textual occurrences of
`ROLLBACK`, but only one standalone PostgreSQL rollback
result. The other occurrences are informational labels.

### 7.3 Evidence file register

| Test | SQL source | Retained execution log |
|---|---|---|
| 057 | `database/tests/057_case_evidence_storage_rls_revocation_security.sql` | `database/test-results/test057_regression_20261028T015920Z.log` |
| 058 | `database/tests/058_active_case_lock_visibility_security.sql` | `database/test-results/test058_regression_20261028T020105Z.log` |
| 059 | `database/tests/059_evidence_reservation_work_revocation_security.sql` | `database/test-results/test059_regression_20261028T020156Z.log` |
| 060 | `database/tests/060_case_evidence_recovery_status_work_revocation_security.sql` | `database/test-results/test060_recovery_status_work_revocation.log` |

Additional result summaries are retained in
`database/tests/TEST_RESULTS.md`.

The requirement classifications are maintained in
Section 21 of `database/tests/TEST_MATRIX.md`.

### 7.4 Requirement-to-test traceability

| Requirement | Local assertion coverage | Test | Related threat |
|---|---|---|---|
| WORK-01 | Effective work permission for protected operations | 057 | TH-02, TH-03 |
| WORK-02 | Valid lock does not bypass revoked work permission | 057 | TH-03 |
| WORK-03 | Revoked employee denied assignment Save | 057 | TH-04 |
| WORK-04 | Revoked employee denied protected case update | 057 | TH-04 |
| WORK-05 | Revoked employee denied comment creation and retrieval | 057 | TH-05 |
| WORK-06 | Revoked employee denied audit-history retrieval | 057 | TH-05 |
| WORK-07 | Revoked employee denied evidence and download-path retrieval | 057 | TH-06 |
| WORK-08 | Revoked employee denied evidence preparation and finalisation | 057 | TH-07 |
| WORK-09 | Tested Storage RLS upload and download denial | 057 | TH-08 |
| WORK-10 | Selected denied operations preserve protected state | 057 | TH-12 |
| WORK-11 | Revoked employee denied session resume and renewal | 057 | TH-03 |
| WORK-12 | Revoked employee safely closes owned session | 057 | TH-13 |
| WORK-13 | Active-lock visibility requires work permission | 058 | TH-09 |
| WORK-14 | Submit/manage permissions alone do not expose locks | 058 | TH-02, TH-09 |
| WORK-15 | Revoking second-team work removes its lock visibility | 058 | TH-09 |
| WORK-16 | Reservation listing requires effective work permission | 059 | TH-10 |
| WORK-17 | Reservation denial preserves lock and reservation | 059 | TH-10, TH-12 |
| WORK-18 | Recovery-status access denied after work revocation | 060 | TH-11 |
| WORK-19 | Recovery denial preserves lock, reservation and related state | 060 | TH-11, TH-12 |

**Evidence classification:** WORK-01 through WORK-19
have supporting local regression evidence for their
documented test scenarios.

These results do not establish every possible input,
execution path, role configuration or concurrent state.

### 7.5 Test 057 — Case-work and Storage security

The execution log records authorised operations before
revocation, including:

- Exclusive session acquisition, resumption and renewal.
- Protected case-detail retrieval.
- Internal comment creation and retrieval.
- Attributed audit-history retrieval.
- Evidence retrieval and completed download-path access.
- Evidence upload preparation and finalisation.
- Assignment Save and case status/priority updates.
- Permitted authenticated Storage object retrieval.
- Permitted reserved Storage INSERT.

The same local test subsequently revokes the employee's
effective team-work permission while the exclusive
case lock remains valid.

Its PASS markers report denial of protected case
operations, evidence operations, Storage access,
session resumption and session renewal.

The test also reports preservation of relevant case,
assignment, comment, reservation, attachment, audit
and lock state following selected denied operations.

Safe closure of the owned session is separately
observed, including lock removal and an attributed
exit audit event.

These are local SQL regression observations, not
browser, hosted or independent audit findings.

### 7.6 Test 058 — Active-lock visibility

The executed test reports that:

1. A work-authorised employee sees the permitted
   team's active lock.
2. Unauthorised team and foreign-organisation locks
   are not exposed in the tested fixture.
3. Submit/manage permissions alone do not expose locks.
4. Explicit work grants permit visibility across
   authorised teams.
5. Revocation of a second-team work grant removes
   that team's lock visibility while preserving
   visibility permitted by the remaining grant.

**Result:** Seven PASS markers, zero FAIL/ERROR
markers and one rollback result.

### 7.7 Test 059 — Reservation listing

The executed test reports that:

1. A work-authorised employee can list an owned
   evidence-upload reservation.
2. The work grant can be revoked while the original
   exclusive lock and reservation remain present.
3. The revoked employee cannot list the reservation,
   even while retaining the valid lock.
4. The denied listing does not change the original
   lock or reservation in the tested scenario.

**Result:** Eight PASS markers, zero FAIL/ERROR
markers and one rollback result.

### 7.8 Test 060 — Recovery-status access

The executed test reports that:

1. An authorised employee retrieves pending evidence
   recovery status.
2. Work permission is revoked while the original
   exclusive lock remains valid.
3. The revoked employee is denied recovery-status access.
4. The denial preserves the original lock and reservation.
5. The denied operation creates no attachment
   or audit event.

**Result:** Ten PASS markers, zero FAIL/ERROR
markers and one actual rollback result.

### 7.9 Outstanding requirement coverage

| Requirement | Outstanding evidence | Status |
|---|---|---|
| WORK-20 | Independent behavioural coverage for all 16 Migration 067 functions | NOT ESTABLISHED |
| WORK-21 | Frontend locking and Save compatibility regression | PENDING |
| WORK-22 | Real authenticated HTTP API verification | PENDING |
| WORK-23 | Browser-level permission revocation | PENDING |
| WORK-24 | Concurrent lock, revocation and evidence tests | PENDING |
| WORK-25 | Hosted migration and deployment verification | PENDING |
| WORK-26 | Independent security assessment and production approval | PENDING |

Earlier test sources were compared with Migration 067
function definitions during development. This does
not mean that every earlier test was freshly executed
as part of this regression evidence set.

### 7.10 Test-source documentation discrepancy

The opening comments in Test 057 contain historical
statements suggesting Storage RLS assertions have
not yet been implemented.

Those comments are inconsistent with the retained
Storage-specific execution assertions.

They should be corrected in a separate, reviewed,
documentation-only change without altering test
behaviour or security logic.

### 7.11 Evidence limitations

The recorded tests do not establish:

- Hosted or production deployment correctness.
- Browser and real authenticated HTTP API behaviour.
- Race-condition safety under concurrent execution.
- Exhaustive function and branch coverage.
- Privileged-role and service-role bypass resistance.
- Independent penetration testing or certification.

The absence of FAIL/ERROR markers in these logs does
not prove the absence of vulnerabilities.

### 7.12 Regression evidence conclusion

The four retained local regression logs contain
116 PASS markers, zero FAIL/ERROR markers and four
actual PostgreSQL rollback results.

Nineteen requirements have supporting local test
evidence, one remains not established and six
remain pending.

**Verification status:** Local regression evidence
recorded; broader assurance and production acceptance
remain open.

## 8. Locking, Save and audit compatibility

### 8.1 Compatibility objective

Migration 067 strengthens current team-work authorisation
for protected case operations.

It must not unintentionally change the existing exclusive
case-lock lifecycle, persistent responsibility assignment,
reassignment confirmation or audit attribution.

The source review covered:

- `web/src/app/cases/[caseId]/CaseWorkspace.tsx`
- `database/migrations/064_team_work_session_authorisation.sql`
- `database/migrations/067_operational_case_work_authorisation.sql`
- `database/migrations/024_close_case_session.sql`
- `database/migrations/020_release_case_lock.sql`
- `database/migrations/023_record_case_exit.sql`
- `database/migrations/014_case_update_audit_trigger.sql`
- `database/migrations/028_audit_case_update.sql`

The findings below distinguish source inspection from
executed local tests and pending integration verification.

### 8.2 Automatic exclusive case entry

The frontend calls `open_case_session` when opening the
case workspace, or first attempts to resume a previously
saved session token.

There is no separate Start Work requirement in this
inspected workflow.

Migration 064 requires an active employee identity,
matching organisation and effective destination-team
`work` permission before acquiring a case lock.

Its acquisition function uses a single case-lock record,
a generated lock token and a five-minute expiry.

An existing unexpired lock cannot be overwritten through
the inspected conflict-handling path.

Successful new session acquisition invokes
`record_case_opened`.

**Evidence:** Source inspected; selected local
regression assertions available.

**Outstanding:** Browser-level competing-employee
entry and concurrency verification.

### 8.3 Lease renewal and session resumption

The frontend schedules normal renewal approximately
60 seconds before the recorded expiry.

A failed renewal is retried only while the previous
lease may remain valid. Otherwise, the workspace
enters a verification-required state and protected
activity access is invalidated.

Migration 064 checks employee identity, organisation,
current work permission, lock ownership, token and
expiry for renewal or resumption.

Renewal extends the existing lease by five minutes.
It does not transfer case responsibility.

Test 057 reports denial of renewal and resumption
after work permission is revoked, despite a previously
valid lock.

**Evidence:** Source inspected and local SQL
revocation regression recorded.

**Outstanding:** Browser timing, network failure,
multi-tab and concurrent revocation tests.

### 8.4 Persistent assignment through Save

The Save button calls
`save_employee_case_assignment` with the case ID,
existing lock token, expected assignee and explicit
reassignment-confirmation value.

Migration 067 requires:

1. An authenticated active employee.
2. A valid, unexpired lock owned by that employee.
3. Current effective team-work permission.
4. A matching expected assignment state.
5. Explicit confirmation when transferring an
   existing assignment from another employee.

When an assignment change is authorised, the function
updates `cases.assigned_user_id`.

The Save function does not delete, release, replace
or renew the exclusive lock.

For an unassigned case, Save can claim responsibility
without a reassignment confirmation.

For a case already assigned to the current employee,
Save does not require transfer confirmation.

**Evidence:** Frontend and SQL source inspected;
selected local Test 057 assertions recorded.

**Outstanding:** Browser-level Save and reassignment
regression under Migration 067.

### 8.5 Reassignment confirmation and stale-state defence

The frontend displays the existing assignee's name
and asks whether the employee wishes to reassign
the case to themselves.

Cancel closes the confirmation interface without
submitting a confirmed reassignment.

The backend separately requires
`p_confirm_reassignment = TRUE` when another
employee currently holds responsibility.

It also compares the current database assignee
with `p_expected_assigned_user_id`.

If the assignment has changed since the frontend
loaded its record, the function raises a
refresh-before-saving error.

This provides a database-side safeguard against
stale assignment confirmation.

**Evidence:** Source inspected.

**Outstanding:** End-to-end stale-assignment and
confirmation-cancellation tests.

### 8.6 Assignment and workflow audit attribution

The existing `audit_case_update` trigger obtains
the active employee identity from the authenticated
user and the case organisation.

It records changes to status, priority, assigned
team and assigned employee in `case_events`.

Migration 028 also records selected case-information
changes using the same audit mechanism.

Migration 067 preserves assignment updates through
the existing `cases` update path, allowing the
existing trigger to capture authorised changes.

The inspected Save function does not introduce
a parallel assignment-audit mechanism.

Test 057 reports selected attributed audit events
and preservation of audit state after denied
operations.

**Evidence:** Audit-trigger source inspected and
selected local SQL regression recorded.

**Outstanding:** Independent audit-event completeness
review and browser/API-level attribution testing.

### 8.7 Controlled session closure

The frontend's explicit Back action ultimately calls
`close_case_session`.

The database closure function checks active employee
identity, organisation, lock ownership and lock token.

It invokes the token-aware release function and
records `case_closed_view` only after successful
lock release.

The release function deletes only a matching
organisation-, employee- and token-scoped lock.

It does not require current destination-team
`work` permission.

This distinction allows a revoked employee to
release a lock they still own without regaining
permission to perform protected case work.

Test 057 reports successful safe closure after
revocation, including removal of the lock and
attributed exit auditing.

**Evidence:** Source inspected and local SQL
regression recorded.

**Outstanding:** End-to-end frontend exit after
revocation.

### 8.8 Browser refresh and cleanup behaviour

The inspected frontend intentionally avoids releasing
the database lock during ordinary React cleanup
or browser refresh.

Instead, it retains a session token for subsequent
verification and possible resumption.

Explicit Back navigation is the intended normal
release path.

This means browser refresh must not be described
as immediate lock release.

If a lock is not explicitly released, expiry and
subsequent authorised acquisition govern recovery.

**Evidence:** Frontend source inspected.

**Outstanding:** Browser refresh, multi-tab recovery,
abandoned-session and expiry integration tests.

### 8.9 Evidence-reservation exit dependency

Before normal Back navigation, the frontend requests
the employee's evidence-upload reservations.

If unresolved reservations exist, it requests
confirmation before leaving.

If the reservation-listing request fails, the
frontend stops normal navigation and displays
an error rather than proceeding without checking
outstanding evidence state.

Migration 067 requires current work permission
for reservation listing.

Therefore, after permission revocation, the
preliminary listing request may fail even though
the database still permits safe owned-lock closure.

This is a potential frontend integration gap,
not a confirmed production defect.

The required test is:

1. Open a case with valid work permission.
2. Acquire its exclusive lock.
3. Revoke the employee's work permission.
4. Attempt normal Back navigation.
5. Verify whether the owned lock can be safely
   released and the exit event attributed.
6. Verify unresolved evidence reservations
   remain intact and recoverable.

**Status:** Pending browser-level verification.
Do not claim this path is end-to-end validated.

### 8.9A R067-01 corrective implementation and local regression verification

**Evidence update date:** 29 October 2026.

**Change classification:** Narrowly scoped frontend corrective implementation;
local behavioural regression verification; database security regression
re-execution. This addendum supplements the earlier Section 8.9 assessment
without replacing the historical baseline.

**Issue addressed:** The original normal Back workflow blocked navigation
when evidence-upload reservation discovery failed. After effective team-work
permission was revoked, reservation discovery could be denied even while the
employee retained a valid exclusive lock that the database permitted them
to close safely.

**Corrective implementation:** In
`web/src/app/cases/[caseId]/CaseWorkspace.tsx`, the `handleBack()` reservation
discovery exception path now calls `can_work_on_case` for the current case.
Only an error-free, explicit `false` result permits progression to the
existing session-release pathway. A `true` result, RPC error, thrown
exception or unexpected result retains the existing fail-closed navigation
block. Successful navigation still requires the existing session-release
function to return success.

An explicit `false` result does not independently establish that permission
revocation caused the reservation-listing failure. The existing backend
lock-owner, organisation, identity and token checks remain the authority
for actual release. The change does not grant evidence visibility, resolve
reservations, modify Save assignment or alter lock acquisition and renewal
mechanics.

**Frontend regression evidence:**

- Test source:
  `web/tests/case-exit-permission-revocation.test.cjs`.
- Execution:
  `node --test web/tests/case-exit-permission-revocation.test.cjs`.
- Recorded result: six tests passed, zero failed, on 29 October 2026.
- Covered scenarios: normal exit; unresolved-reservation cancellation;
  revoked-work-permission fallback and successful release; unexpected
  reservation error while work permission remains valid; failed permission
  verification; and unsuccessful release preventing navigation.
- The harness extracts and executes the actual `handleBack()` function
  using mocked dependencies. This is not a browser integration test and
  does not execute actual authenticated HTTP requests.

**Database regression evidence:**

- Test source:
  `database/tests/042_team_work_session_authorisation_security.sql`.
- Execution environment: local Docker container
  `supabase_db_madzera`, PostgreSQL database `postgres`.
- Execution command: `docker exec -i supabase_db_madzera psql -X -P
  pager=off -v ON_ERROR_STOP=1 -U postgres -d postgres <
  database/tests/042_team_work_session_authorisation_security.sql`.
- Recorded result: exit code 0; 27 reported PASS assertions; no reported
  FAIL or ERROR assertions; transaction ended with `ROLLBACK`.
- Verified scenarios include immediate denial of session resume and
  renewal after work-permission revocation, continued safe release by
  the legitimate lock owner, duplicate-closure rejection, removal of
  the exclusive lock and exactly one employee-attributed exit audit.
- This is a local SQL-level test, not a browser-to-database end-to-end test.

**Additional verification:** TypeScript type checking and the Next.js
production build passed after the frontend change. ESLint reported zero
errors and one existing React hook dependency warning. The tracked source
diff was confined to `CaseWorkspace.tsx` at the time of inspection.

**Remaining limitations and risks:**

1. Browser-level reproduction and verification of permission revocation
   during an active case session remain pending under WORK-23 and G067-04.
2. Real authenticated HTTP RPC and evidence-reservation state verification
   remain pending; mocked frontend behaviour and direct SQL execution
   must not be represented as an end-to-end integration result.
3. The existing release lifecycle stops renewal and expiry timers before
   `close_case_session` confirms release. A failed release can therefore
   leave the page active without its normal renewal timer. This is a
   separately identified lifecycle risk requiring targeted assessment;
   the R067-01 correction does not change that behaviour.
4. Full frontend locking, Save and reassignment compatibility verification
   remains pending under WORK-21 and G067-02.
5. No hosted deployment, independent security approval or production
   acceptance is established by this addendum.

**Risk disposition:** R067-01 remains OPEN, with corrective implementation
and focused local regression evidence recorded. The original Section 9.3
risk description represents the pre-correction assessment and must be
read together with this addendum. Production release remains NOT APPROVED.

### 8.10 Compatibility evidence matrix

| Behaviour | Source review | Local SQL evidence | Frontend integration |
|---|---|---|---|
| Automatic exclusive case entry | Confirmed | Selected scenarios | Pending |
| Five-minute lease and renewal | Confirmed | Selected scenarios | Pending |
| Revocation blocks resume/renew | Confirmed | Test 057 | Pending |
| Save claims responsibility | Confirmed | Test 057 selected scenarios | Pending |
| Save preserves exclusive lock | Confirmed | Test 057 selected scenarios | Pending |
| Reassignment confirmation | Confirmed | Selected SQL assertions | Pending |
| Stale-assignee protection | Confirmed | Not independently established here | Pending |
| Assignment audit trigger | Confirmed | Test 057 selected scenarios | Pending |
| Safe release after revocation | Confirmed | Test 057 | Pending |
| Refresh preserves recovery token | Confirmed | Not established here | Pending |
| Back navigation after revocation | Potential dependency identified | Database release tested | Pending |
| Concurrent employee interaction | Source mechanisms inspected | Not established | Pending |

### 8.10A Frontend case-creation authorisation verification

**Verification date:** 28 October 2026.

**Implementation reviewed:**
`web/src/app/cases/CasesWorkspace.tsx`.

The case-creation confirmation retains the trusted submission-receipt
lookup through `get_case_submission_receipt(p_case_id)`. The receipt
provides the creator with their case reference independently of
operational case-work permission.

The confirmation's **Open Case Record** action is now conditionally
displayed using the result of
`can_work_on_case(p_case_id)`, rather than using membership in
`get_case_queue()` as a substitute for work authorisation.

A failed authorisation request or a result other than boolean `true`
leaves the Open action hidden. This is a frontend eligibility measure;
the protected backend case-session and detail functions remain the
authoritative enforcement boundary.

A `useRef` request-generation counter guards asynchronous confirmation
updates. Older submission-receipt, queue-refresh and work-authorisation
responses cannot overwrite the current case-creation confirmation
after a newer creation or form-close action.

Queue refresh remains separate from work-authorisation evaluation.
Failure to refresh the queue does not grant permission to open a case.

**Local frontend verification results:**

| Verification | Recorded result | Scope |
|---|---|---|
| ESLint on `CasesWorkspace.tsx` | PASS | Step 3150 |
| TypeScript `tsc --noEmit --incremental false` | PASS | Step 3150 |
| Next.js `npm run build` | PASS | Step 3152 |
| Source-level callback and state review | COMPLETED | Steps 3148–3149 |
| Automated frontend behavioural tests | NOT EXECUTED | No test framework configured |
| Browser-level case-creation and revocation tests | PENDING | Not established by static checks |

The successful production build confirms local frontend compilation,
not deployment approval or end-to-end runtime correctness.

**Outstanding acceptance work:** Test case creation by an employee
with `submit` but without `work` permission; verify the submission
receipt remains available while the Open action is hidden; test
authorised case opening, permission revocation, stale-response
handling and relevant locking, Save and reassignment interactions
through authenticated browser/API workflows.

The separate R067-01 concern about normal Back navigation after
work-permission revocation is not resolved by this amendment.

**Release-gate impact:** None. G067-02 and G067-04 remain PENDING.
All other Section 10 gate statuses and Section 9 residual-risk
statuses remain unchanged. Production release remains NOT APPROVED.

### 8.11 Compatibility conclusion

The inspected source supports the intended separation
between exclusive lock ownership, persistent case
assignment and effective team-work permission.

Selected local SQL regressions support the claim
that revoked work permission blocks protected
operations without necessarily preventing safe
owned-lock release.

However, frontend behaviour has not yet been
independently verified end to end against
Migration 067.

The evidence-reservation check before Back navigation
requires particular attention.

**Compatibility status:** Source reviewed; selected
local database regressions passed; frontend and
concurrency acceptance remain pending.

## 9. Residual risks and limitations

### 9.1 Risk assessment methodology

This register records residual risks identified during
Migration 067 source review and local regression testing.

Risk ratings are provisional engineering judgements,
not independently validated probability estimates.

**Severity definitions:**

| Severity | Interpretation |
|---|---|
| Critical | Potential cross-tenant compromise, uncontrolled privileged access or material loss of confidentiality/integrity |
| High | Significant authorisation, evidence, audit or operational-control failure |
| Medium | Bounded workflow disruption, assurance gap or recoverable control weakness |
| Low | Limited documentation, observability or maintenance weakness |

**Evidence classifications:**

- **Local PASS:** A defined synthetic local regression
  scenario produced the expected result.
- **Source inspected:** Implementation was reviewed,
  without independently establishing runtime behaviour.
- **Pending:** Required verification has not been completed.
- **Potential:** A plausible failure path has been identified,
  but no defect has yet been reproduced.

Risk status is **OPEN** until the specified acceptance
evidence is recorded and reviewed.

No risk in this section is represented as formally
accepted by a production security authority.

### 9.2 Residual risk register

| ID | Risk | Provisional severity | Evidence | Status |
|---|---|---|---|---|
| R067-01 | Frontend Back navigation after work-permission revocation requires end-to-end verification | High | Corrective frontend implementation; six local Node tests PASS; SQL Test 042 PASS with ROLLBACK; browser verification pending | OPEN |
| R067-02 | Concurrent revocation and protected operation may expose a timing race | High | Concurrency tests not established | OPEN |
| R067-03 | Authenticated HTTP RPC behaviour may differ from direct SQL regression scenarios | High | Local SQL PASS; HTTP testing pending | OPEN |
| R067-04 | Real Storage API upload/download behaviour may differ from local Storage RLS assertions | High | Local RLS PASS; API testing pending | OPEN |
| R067-05 | Privileged database or service-role access may bypass ordinary employee RLS boundaries | Critical | Privileged-role governance not verified | OPEN |
| R067-06 | Hosted schema, grants or Storage policies may drift from the inspected local installation | High | Hosted verification not established | OPEN |
| R067-07 | Not all 16 Migration 067 functions have independent behavioural coverage | High | WORK-20 not established | OPEN |
| R067-08 | Browser session recovery, expiry and multi-tab behaviour may diverge from intended locking semantics | Medium | Source inspected; integration pending | OPEN |
| R067-09 | Save, reassignment confirmation or stale-assignee handling may regress in the frontend | High | Source inspected; browser regression pending | OPEN |
| R067-10 | Audit-event attribution or denied-operation side effects may be incomplete in untested paths | High | Selected local PASS; exhaustive review pending | OPEN |
| R067-11 | Future permissive Storage policies or changed function grants may weaken authorisation | High | Local policy inventory only; future drift possible | OPEN |
| R067-12 | Independent assessment and production security approval remain incomplete | High | WORK-26 pending | OPEN |

### 9.3 R067-01 — Revoked employee's normal exit path

**Threats:** TH-03, TH-10, TH-13, TH-18.

**Scenario:** An employee opens a case, acquires its
exclusive lock and subsequently loses effective
team-work permission.

The frontend's normal Back action first requests
evidence-upload reservations.

Migration 067 requires effective work permission
for that reservation-listing function.

The request may therefore fail before the frontend
calls `close_case_session`, despite the database
permitting safe closure of an owned lock.

**Potential impact:** Temporary lock retention,
blocked normal navigation and operational disruption.

**Existing control:** Test 057 reports successful
database-level safe release after revocation.

**Mitigation implemented:** A narrowly scoped frontend
safe-exit fallback now permits progression to the existing
owner-verified release pathway only when `can_work_on_case`
returns an error-free, explicit `false`. The fallback does
not restore protected evidence visibility or modify
unresolved evidence reservations.

**Verification completed:** Six focused frontend Node
regression tests passed. Local SQL Test 042 passed with
transaction rollback, including safe owned-lock release,
duplicate-release rejection and exit-audit attribution.

**Verification outstanding:** Reproduce and verify the
revocation-and-exit sequence in a browser using authenticated
HTTP requests, including reservation integrity and
before/after lock and audit state. Assess the separate
failed-release timer lifecycle concern recorded in
Section 8.9A.

**Acceptance:** Revoked employee can safely leave;
owned lock is released; exit audit is attributed;
unresolved reservations remain intact; protected
case and evidence operations remain denied.

**Owner:** Application engineering and security review.

**Status:** OPEN — corrective implementation and focused local tests passed; browser-level acceptance and formal risk closure pending.

### 9.4 R067-02 — Concurrent authorisation changes

**Threats:** TH-03, TH-12, TH-16.

**Scenario:** A protected operation overlaps a
team-permission revocation, lock expiry, reassignment
or evidence finalisation.

**Potential impact:** An operation may complete under
an unexpected authorisation state or create inconsistent
case/evidence state.

**Existing control:** Protected functions re-evaluate
current work permission and relevant lock conditions.
Selected sequential local tests passed.

**Required mitigation:** Test controlled concurrent
transactions under defined isolation levels, including
revocation before, during and after protected operations.

**Acceptance:** Documented linearisation/transaction
semantics; no unauthorised post-revocation operation
in the agreed threat model; consistent lock, reservation,
attachment and audit state.

**Owner:** Database engineering and security review.

**Status:** OPEN — concurrency not established.

### 9.5 R067-03 — Authenticated HTTP RPC enforcement

**Threats:** TH-01, TH-02, TH-03, TH-14.

**Scenario:** PostgREST role handling, JWT claims,
function execution grants or API exposure differ from
the assumptions used in direct SQL tests.

**Potential impact:** Unauthorised RPC access or
unexpected denial of legitimate work.

**Existing control:** Function-level identity,
organisation, lock and work-permission checks were
inspected. Selected local SQL regressions passed.

**Required mitigation:** Exercise actual authenticated
HTTP requests using distinct employee, organisation,
team and permission identities.

**Acceptance:** Expected allow/deny responses and
unchanged protected state verified across the
documented role matrix.

**Owner:** API and security engineering.

**Status:** OPEN — HTTP verification pending.

### 9.6 R067-04 — Storage API enforcement

**Threats:** TH-06, TH-07, TH-08, TH-17.

**Scenario:** Real Storage object operations or policy
evaluation differ from the local SQL predicate tests.

**Potential impact:** Unauthorised evidence upload,
download, disclosure or inconsistent reservation state.

**Existing control:** Local Storage RLS policies and
work-aware helper functions were inspected. Test 057
reports selected Storage RLS PASS assertions.

**Required mitigation:** Execute authenticated Storage
API upload/download tests before and after permission
revocation, including expired locks, foreign tenants
and invalid reservations.

**Acceptance:** Unauthorised Storage operations denied;
authorised operations succeed; no unexpected object,
reservation or attachment mutation.

**Owner:** Storage and security engineering.

**Status:** OPEN — real Storage API testing pending.

### 9.7 R067-05 — Privileged-role trust boundary

**Threats:** TH-14, TH-15.

**Scenario:** A service role, function owner or other
privileged principal operates outside ordinary
employee RLS restrictions.

**Potential impact:** Material cross-tenant disclosure
or modification if privileged credentials or functions
are misused.

**Existing control:** Selected function privileges,
SECURITY DEFINER settings and local RLS configuration
were inspected.

These checks do not prove that privileged roles are
subject to ordinary employee restrictions.

**Required mitigation:** Inventory privileged
credentials, function ownership, EXECUTE grants,
administrative access paths, secret handling and
service-role usage.

**Acceptance:** Documented privileged trust model,
least-privilege grants, credential controls, monitoring
and independent security approval.

**Owner:** Security architecture and platform operations.

**Status:** OPEN — privileged governance not verified.

### 9.8 R067-06 — Hosted deployment and configuration drift

**Threats:** TH-08, TH-14, TH-17.

**Scenario:** Hosted migrations, function definitions,
grants, extensions or Storage policies differ from
the verified local environment.

**Potential impact:** Controls behave differently
after deployment.

**Existing control:** Local migration fingerprint
and installed-policy inventory are recorded.

**Required mitigation:** Perform controlled hosted
migration deployment, compare installed definitions
and policy/grant inventories, and execute approved
post-deployment verification.

**Acceptance:** Hosted configuration matches the
approved baseline, or every difference is documented,
reviewed and accepted.

**Owner:** Platform engineering and security review.

**Status:** OPEN — hosted deployment not established.

### 9.9 R067-07 — Incomplete behavioural coverage

**Threats:** TH-01 through TH-14, as applicable.

**Scenario:** A Migration 067 function or branch
contains an untested authorisation or integrity path.

**Potential impact:** An undiscovered bypass or
workflow regression remains undetected.

**Existing control:** Sixteen function definitions
were inventoried and inspected; selected local
regression scenarios passed.

**Required mitigation:** Build a function-by-function
test inventory covering success, denial, revocation,
tenant isolation, lock mismatch, expired lock and
state-preservation behaviour where applicable.

**Acceptance:** Every function has documented
applicable test cases, execution evidence and
reviewed exclusions.

**Owner:** Database engineering and QA.

**Status:** OPEN — WORK-20 not established.

### 9.10 R067-08 — Session recovery and expiry

**Threats:** TH-03, TH-13, TH-18.

**Scenario:** Refresh, multi-tab operation, network
failure or lease expiry causes unexpected session
recovery or lock retention.

**Potential impact:** Temporary operational blockage
or inconsistent frontend lock state.

**Existing control:** Source contains saved-token
recovery, renewal scheduling, expiry checks and
explicit release behaviour.

**Required mitigation:** Browser tests for refresh,
multi-tab use, abandoned sessions, renewal failure
and lease expiry.

**Acceptance:** Protected actions remain unavailable
without verified access; recovery and expiry behave
according to documented policy.

**Owner:** Frontend engineering and QA.

**Status:** OPEN — integration verification pending.

### 9.11 R067-09 — Save and reassignment compatibility

**Threats:** TH-04, TH-12, TH-18.

**Scenario:** Frontend state becomes stale, a user
cancels confirmation, or assignment changes during
an active session.

**Potential impact:** Incorrect responsibility
assignment, confusing UI or missing audit evidence.

**Existing control:** Source contains named
confirmation, expected-assignee comparison and
database-side reassignment enforcement.

**Required mitigation:** Browser tests for unassigned,
self-assigned, other-assigned, cancelled confirmation,
stale expected assignee and revoked permission.

**Acceptance:** No unauthorised reassignment;
confirmation behaves correctly; Save preserves lock;
assignment audit records actual changes.

**Owner:** Frontend, database and QA teams.

**Status:** OPEN — browser regression pending.

### 9.12 R067-10 — Audit and state integrity

**Threats:** TH-12, TH-13, TH-14.

**Scenario:** An untested denied request changes
protected state or an authorised operation fails
to produce an expected audit event.

**Potential impact:** Incomplete accountability,
incorrect evidence history or operational inconsistency.

**Existing control:** Selected local tests assert
state preservation and attributed events.

**Required mitigation:** Review event coverage and
transaction boundaries for all protected functions;
test authorised and denied paths.

**Acceptance:** Expected audit events are attributable
and complete for agreed workflows; denied operations
have no prohibited side effects.

**Owner:** Database engineering and security review.

**Status:** OPEN — exhaustive review pending.

### 9.13 R067-11 — Future policy and privilege drift

**Threats:** TH-14, TH-17.

**Scenario:** A future migration adds an overly broad
permissive Storage policy or EXECUTE grant.

**Potential impact:** Previously enforced
authorisation boundaries become ineffective.

**Existing control:** Local policy inventory and
selected function grants were inspected.

**Required mitigation:** Add policy/grant inventory
checks to migration review and deployment verification.

**Acceptance:** Every policy or grant change has
documented rationale, regression tests and review.

**Owner:** Database and platform engineering.

**Status:** OPEN — continuous control required.

### 9.14 R067-12 — Independent assessment and release approval

**Threats:** All material residual threat scenarios.

**Scenario:** Local regression evidence is incorrectly
treated as sufficient for production security approval.

**Potential impact:** Unreviewed vulnerabilities,
operational failures or inaccurate external assurance.

**Existing control:** The dossier explicitly
distinguishes local evidence from independent assurance.

**Required mitigation:** Complete the outstanding
acceptance gates, commission proportionate independent
security review and record authorised release decisions.

**Acceptance:** Signed security review, risk disposition,
deployment evidence and formal production approval.

**Owner:** Product owner and designated security approver.

**Status:** OPEN — no approval established.

### 9.15 Risk prioritisation

**Priority 1 — Resolve before production acceptance:**

R067-01, R067-02, R067-03, R067-04, R067-05,
R067-06, R067-07, R067-09, R067-10 and R067-12.

**Priority 2 — Verify and disposition before release:**

R067-08 and R067-11.

Priority does not replace formal risk acceptance.
A lower-priority risk may still block release if its
actual impact or likelihood proves material.

### 9.16 Risk ownership and closure rules

Risk owners listed above are responsible functions,
not evidence that individuals have accepted ownership.

Before closing any risk, record:

1. The remediation or accepted design decision.
2. The relevant code, migration or policy reference.
3. The test method and reproducible execution evidence.
4. Any remaining limitations or exclusions.
5. Reviewer's identity, date and approval decision.

No risk may be marked CLOSED solely because a
mitigation has been proposed or source code inspected.

Any formal risk acceptance must identify the authorised
decision-maker, rationale, scope and review date.

### 9.17 Residual-risk conclusion

Migration 067 has supporting local regression evidence
for selected operational authorisation scenarios.

However, the current evidence does not establish
complete production assurance.

The twelve risks above remain OPEN pending the
specified verification, mitigation or formal disposition.

**Release interpretation:** This register documents
unresolved engineering and assurance work. It does
not constitute production approval, independent
certification or a claim of zero residual risk.

## 10. Production acceptance gates

### 10.1 Acceptance purpose and authority

These gates define the minimum verification evidence
required before Migration 067 may be considered for
production deployment.

They do not authorise deployment automatically.

A successful local test, source review or completed
document is not equivalent to production acceptance.

**Current overall status: NOT APPROVED FOR PRODUCTION.**

The product owner and designated security approver
must explicitly review the completed evidence,
remaining risks and deployment decision.

### 10.2 Acceptance status definitions

| Status | Meaning |
|---|---|
| PASS | Required test executed, evidence retained and acceptance criterion satisfied |
| FAIL | Executed test demonstrates an unmet acceptance criterion |
| PENDING | Required verification has not been executed or completed |
| NOT ESTABLISHED | Existing evidence is insufficient to support the claimed control |
| ACCEPTED EXCEPTION | Authorised, documented and time-bounded exception approved through formal risk governance |

An ACCEPTED EXCEPTION does not convert a failed
technical control into a PASS.

No acceptance status should be inferred solely
from source inspection or a proposed mitigation.

### 10.3 Gate register

| Gate | Acceptance area | Related requirement | Related risks | Current status |
|---|---|---|---|---|
| G067-01 | Complete function-level behavioural coverage | WORK-20 | R067-07, R067-10 | NOT ESTABLISHED |
| G067-02 | Frontend locking and Save compatibility | WORK-21 | R067-01, R067-08, R067-09 | PENDING |
| G067-03 | Authenticated HTTP RPC enforcement | WORK-22 | R067-03, R067-05 | PENDING |
| G067-04 | Browser-level permission revocation | WORK-23 | R067-01, R067-08, R067-09 | PENDING |
| G067-05 | Concurrency and transaction safety | WORK-24 | R067-02, R067-10 | PENDING |
| G067-06 | Hosted migration and configuration verification | WORK-25 | R067-06, R067-11 | PENDING |
| G067-07 | Independent security assessment and approval | WORK-26 | R067-05, R067-12 | PENDING |
| G067-08 | Real authenticated Storage API verification | WORK-22, WORK-23 | R067-04, R067-11 | PENDING |
| G067-09 | Audit, denial and evidence integrity reconciliation | WORK-20, WORK-24 | R067-10 | NOT ESTABLISHED |
| G067-10 | Residual-risk disposition and release decision | WORK-26 | R067-01 through R067-12 | PENDING |

These are proposed release gates.
Their current statuses describe the evidence available
in this dossier, not a live deployment dashboard.

### 10.4 G067-01 — Function-level behavioural coverage

**Objective:** Independently verify the applicable
authorisation and integrity behaviour of all sixteen
Migration 067 functions.

**Required scenarios:** Successful authorised use,
revoked permission, foreign organisation, missing
work permission, invalid or expired lock, incorrect
employee identity and denied-operation state
preservation, where applicable.

**Evidence required:** Function-to-test matrix,
test source, reproducible execution logs,
assertion outcomes and documented exclusions.

**Pass criterion:** Every applicable function and
security-relevant branch has reviewed evidence;
all blocking failures resolved.

**Current status:** NOT ESTABLISHED.

### 10.5 G067-02 — Frontend locking and Save compatibility

**Objective:** Preserve existing exclusive-lock and
persistent-assignment behaviour.

**Required scenarios:** Automatic lock acquisition,
five-minute lease, renewal, expiry, refresh recovery,
Save without lock release, reassignment confirmation,
cancellation and stale-assignee protection.

**Evidence required:** Browser test records, expected
versus actual results and relevant application logs.

**Pass criterion:** No unauthorised case entry or
assignment; expected lock lifecycle and audit behaviour
remain intact.

**Current status:** PENDING.

### 10.6 G067-03 — Authenticated HTTP RPC enforcement

**Objective:** Confirm that actual authenticated
application requests enforce database authorisation.

**Required scenarios:** Valid employee, revoked
employee, submit-only, manage-only, foreign tenant,
missing/invalid lock and unauthenticated caller.

**Evidence required:** Sanitised HTTP requests,
response status and body, authenticated role context
and database state assertions.

**Pass criterion:** Authorised requests succeed;
unauthorised requests fail without prohibited
side effects or cross-tenant disclosure.

**Current status:** PENDING.

### 10.7 G067-04 — Browser-level permission revocation

**Objective:** Confirm that stale frontend state
cannot bypass revoked work permission.

**Required scenarios:** Revoke work permission
while a case is open; attempt Save, update,
comment, audit access, evidence access, renewal,
session recovery and normal Back navigation.

**Special acceptance requirement:** The potential
evidence-reservation exit dependency identified in
Section 8.9 and R067-01 must be reproduced or
disproved through browser testing.

**Evidence required:** Reproducible browser test
records, authenticated request outcomes, before/after
lock and reservation state comparisons, and audit-event
attribution evidence for the revocation-and-exit path.

**Pass criterion:** Protected actions are denied
after effective revocation; safe owned-lock closure
remains possible; unresolved evidence reservations
are preserved; no unintended audit or state mutation.

**Current status:** PENDING.

### 10.8 G067-05 — Concurrency and transaction safety

**Objective:** Verify consistent authorisation
and state integrity under overlapping transactions.

**Required scenarios:** Permission revocation
overlapping Save, comment creation, evidence
finalisation, reservation listing, lock renewal,
lock expiry and competing case access.

**Evidence required:** Controlled concurrent
transaction scripts, isolation settings, timing
records and resulting state comparisons.

**Pass criterion:** Behaviour matches documented
transaction semantics; no unauthorised operation
or inconsistent protected state under the agreed
concurrency threat model.

**Current status:** PENDING.

### 10.9 G067-06 — Hosted deployment verification

**Objective:** Verify the approved implementation
in the intended hosted environment.

**Required scenarios:** Controlled migration
application, function-definition comparison,
EXECUTE grant review, Storage policy inventory,
RLS configuration review and smoke tests.

**Evidence required:** Approved deployment record,
migration identifiers, installed-definition
fingerprints, policy/grant inventories and
post-deployment test results.

**Pass criterion:** Hosted configuration matches
the approved baseline or documented differences
have authorised dispositions.

**Current status:** PENDING.

No hosted deployment has been established
by the local evidence in this dossier.

### 10.10 G067-07 — Independent security assessment

**Objective:** Obtain proportionate independent
review of the operational authorisation design
and implementation.

**Required scope:** Tenant isolation, SECURITY
DEFINER execution, role privileges, service-role
trust, Storage RLS, revocation, concurrency and
evidence integrity.

**Evidence required:** Review scope, assessor
identity, findings, remediation evidence,
remaining risks and approval record.

**Pass criterion:** Material findings remediated
or formally dispositioned by an authorised
security decision-maker.

**Current status:** PENDING.

### 10.11 G067-08 — Real Storage API verification

**Objective:** Confirm end-to-end evidence
authorisation through the actual Storage API.

**Required scenarios:** Authorised upload/download,
revoked employee, foreign tenant, expired lock,
invalid reservation, pending upload, completed
attachment and object-path mismatch.

**Evidence required:** Sanitised authenticated
Storage requests, responses, policy outcomes,
object-state comparisons and attachment records.

**Pass criterion:** Authorised operations work;
unauthorised operations fail; no unexpected
object or reservation mutation.

**Current status:** PENDING.

### 10.12 G067-09 — Audit and denial integrity

**Objective:** Verify that protected actions
produce the expected audit history and that
denied actions preserve protected state.

**Required scenarios:** Case open, Save, reassignment,
comment/evidence operations, safe close after
revocation, failed protected operations and
transaction rollback.

**Evidence required:** Before/after case, lock,
reservation, attachment and audit comparisons;
actor attribution and event timestamps.

**Pass criterion:** Required audit events are
complete and attributable; denied operations
produce no prohibited state changes.

**Current status:** NOT ESTABLISHED for exhaustive
coverage, notwithstanding selected local PASS results.

### 10.13 G067-10 — Risk disposition and release decision

**Objective:** Ensure all material residual risks
have an explicit, authorised disposition.

**Required review:** R067-01 through R067-12,
including the Critical privileged-role risk,
all High risks and any unresolved Medium risks.

**Evidence required:** Final risk register,
remediation references, acceptance evidence,
authorised exception records where applicable
and signed release decision.

**Pass criterion:** No unresolved blocking risk;
all exceptions formally approved; required
technical gates satisfied or validly dispositioned;
designated approvers explicitly authorise release.

**Current status:** PENDING.

### 10.14 MVP demonstration versus production release

An internal or controlled MVP demonstration
may use the locally verified environment
without implying that these production
acceptance gates have passed.

Any demonstration must accurately describe
its limitations, avoid real customer-sensitive
data unless separately authorised and protected,
and avoid representing the system as certified
or independently security-approved.

A hosted customer pilot or production deployment
requires its own environment-specific assessment,
data-protection controls and authorised decision.

This dossier does not grant those approvals.

### 10.15 Required evidence package

Before a production decision, the release
package should contain:

1. Approved Migration 067 implementation fingerprint.
2. Complete function-level test inventory and logs.
3. Authenticated HTTP and Storage API evidence.
4. Browser locking, Save and revocation test results.
5. Concurrency and transaction-safety evidence.
6. Audit and state-preservation reconciliation.
7. Hosted migration, RLS and grant verification.
8. Updated residual-risk register and dispositions.
9. Independent security review findings.
10. Named, dated and authorised release decision.

All evidence must be reproducible, traceable
to a specific implementation version and
retained under the project's document controls.

### 10.16 Release decision statement

**Current decision: NOT APPROVED FOR PRODUCTION.**

The local regression evidence supports selected
Migration 067 authorisation behaviours, but the
required production acceptance evidence remains
incomplete.

This status is an evidence-based documentation
assessment, not a claim that production deployment
has been attempted or rejected by a formal
release authority.

No production approval, certification or
independent security sign-off is asserted.

## 11. Evidence and document integrity register

### 11.1 Evidence integrity objective

This register identifies the implementation,
test sources, execution logs and supporting
documents used to substantiate the selected
Migration 067 engineering claims.

SHA-256 fingerprints identify exact file bytes
at the time of verification.

A matching fingerprint demonstrates file
identity against the recorded baseline.
It does not independently prove that the
file's contents are correct, secure or complete.

**Verification date:** 28 October 2026.

**Verification scope:** Local repository files
and retained local PostgreSQL regression logs.

### 11.2 Verified evidence file register

| ID | Evidence class | Description | Repository path | SHA-256 |
|---|---|---|---|---|
| E01 | Implementation | Migration 064 | `database/migrations/064_team_work_session_authorisation.sql` | `0bdec36491baeb89ce3b8b083b1c18f80ff466c2f34ce5c4c742427b6c7f9219` |
| E02 | Implementation | Migration 066 | `database/migrations/066_team_scoped_case_queue_visibility.sql` | `3bc42ee36ab5e59710d8ffa048778486db2aa4dbf85ac0db8e8df62bd55efc25` |
| E03 | Implementation | Migration 067 | `database/migrations/067_operational_case_work_authorisation.sql` | `7d32da0aa17fd2646bed48b7f5dd1c414194102b3212ac0eea05e51c077ef5f3` |
| E04 | Test source | Test 044 fixture | `database/tests/044_team_scoped_case_queue_security.sql` | `49101730d0e4712dfb96e268b0a63b50893c29303ae111f1b46457e9e4e7d29b` |
| E05 | Test source | Test 057 | `database/tests/057_case_evidence_storage_rls_revocation_security.sql` | `c151fa0566a866bcbac9df6453ae153275e29a0437e0aa08b3f0f1fb98a3d130` |
| E06 | Test source | Test 058 | `database/tests/058_active_case_lock_visibility_security.sql` | `03ac0e84c5e172e438c86c252df179d7496e059a5adb9edfc0904c4f340e52e7` |
| E07 | Test source | Test 059 | `database/tests/059_evidence_reservation_work_revocation_security.sql` | `4389c037ef1db37e36ba0fc49fa70ba1d759864ab25e55b3c238a3810f518a6b` |
| E08 | Test source | Test 060 | `database/tests/060_case_evidence_recovery_status_work_revocation_security.sql` | `22a8e9d8607ea95ec6fd966064b087cac05c32d585aa9292cf5cecc4454765c2` |
| E09 | Execution log | Test 057 log | `database/test-results/test057_regression_20261028T015920Z.log` | `f024d4e9248a465655628f29c2ffc70ced2f52b537bd3f456c30971075eb7a8d` |
| E10 | Execution log | Test 058 log | `database/test-results/test058_regression_20261028T020105Z.log` | `24a6321a65e31ecffa498e940ed22431585efafbda7e5bb235a050de49308015` |
| E11 | Execution log | Test 059 log | `database/test-results/test059_regression_20261028T020156Z.log` | `a8c7d714f5e204313d0ccb08083f5a0b22f48cda65c0a99745079a7c9ec7713e` |
| E12 | Execution log | Test 060 log | `database/test-results/test060_recovery_status_work_revocation.log` | `c991373c2b79f9a1fe5fb796ba91d8286be18dd31d17cab97ef6fb874099f929` |
| E13 | Evidence index | Test results | `database/tests/TEST_RESULTS.md` | `9c7da781c61ef5e533be0dd879be85a6c3c8843db8358ba621eecc3db068b7c6` |
| E14 | Evidence index | Test matrix | `database/tests/TEST_MATRIX.md` | `4b81ada6cf3fbe30feb217aefde96fcd0ddac79f3e71049ab23b0e4567e678f3` |
| E15 | Supporting document | Team permission architecture | `docs/security/058_063_team_permission_security_architecture.md` | `7a30ae8314c1f54cd68a71f53c1a3737589fc274c21a9efe24300acdea1dedcd` |
| E16 | Supporting document | Earlier verification dossier | `docs/security/058_063_engineering_verification_dossier.md` | `e948499088da6a761461245cc8d7994ac28cdcc70721b2cdb388b20e952e655f` |

All sixteen entries above were present and
fingerprint-matched during the read-only
Step 3111 evidence verification.

The current dossier itself is registered
separately in Section 11.6 to avoid a
self-referential checksum.

### 11.3 Execution-log verification register

| Test | Log evidence ID | PASS markers | FAIL markers | ERROR markers | Exact ROLLBACK results |
|---|---|---:|---:|---:|---:|
| 057 | E09 | 91 | 0 | 0 | 1 |
| 058 | E10 | 7 | 0 | 0 | 1 |
| 059 | E11 | 8 | 0 | 0 | 1 |
| 060 | E12 | 10 | 0 | 0 | 1 |
| **Total** | **Four logs** | **116** | **0** | **0** | **4** |

These are textual markers found in retained
execution logs, not a substitute for independent
assessment of every test assertion.

The exact standalone PostgreSQL ROLLBACK
result was counted, rather than every
occurrence of the word ROLLBACK.

The recorded tests used local synthetic
data and rollback-based isolation.

### 11.4 Evidence-to-claim traceability

| Claim area | Primary evidence | Supporting evidence | Qualification |
|---|---|---|---|
| Operational work authorisation | E03 | E05, E09, E13, E14 | Source inspected; selected local PASS |
| Active-lock visibility | E03, E06 | E10, E14 | Selected local PASS |
| Evidence reservation revocation | E03, E07 | E11, E13 | Selected local PASS |
| Evidence recovery-status revocation | E03, E08 | E12, E13 | Selected local PASS |
| Team-scoped queue foundation | E02, E04 | E14 | Fixture and source references; no fresh full Test 044 run claimed |
| Lock/session compatibility | E01, E03 | E05, E09 | Source review and selected local tests; browser pending |
| Storage RLS authorisation | E03, E05 | E09, E13 | Selected local assertions; real Storage API pending |
| Threat and requirement coverage | E13, E14 | This dossier, Sections 6–10 | Documented traceability; incomplete acceptance gates |
| Earlier team-permission architecture | E15, E16 | This dossier, Sections 3–6 | Supporting design documentation, not fresh execution evidence |

The test evidence does not establish
that all sixteen Migration 067 functions
have exhaustive independent behavioural
coverage.

### 11.5 Evidence hierarchy and limitations

For this dossier, evidence should be
interpreted in the following order:

1. Reproducible execution logs and
   their corresponding test source.
2. Exact migration source and verified
   installed definitions where recorded.
3. Requirements and test-result registers.
4. Architecture documents and narrative
   engineering interpretation.

A source file proves what was written,
not necessarily what is installed.

A local regression log records a test
execution, not hosted deployment.

A PASS marker does not establish
independent penetration testing,
production readiness or certification.

The following evidence remains outstanding:

- Real authenticated HTTP RPC tests.
- Real authenticated Storage API tests.
- Browser-level locking and revocation tests.
- Controlled concurrency testing.
- Exhaustive function-level behavioural coverage.
- Hosted migration, grant and policy verification.
- Independent security review and release approval.

These limitations correspond to the
production acceptance gates in Section 10.

### 11.6 Dossier fingerprint and self-reference

The current document is:

`docs/security/067_operational_case_work_authorisation_verification_dossier.md`

Its SHA-256 must be calculated **after**
each final document modification.

The dossier's own current fingerprint
is intentionally not embedded as a
fixed value inside this file.

Embedding the file's own fingerprint
would change its bytes and invalidate
the embedded fingerprint.

Instead, retain the final dossier
fingerprint in the terminal verification
output, controlled release manifest
or versioned Git commit record.

The pre-Section-11 dossier fingerprint,
verified before this update, was:

`6ec47323b439814fdfd6c389e3d5b086e49ea31504859e41f4c3ccc1c6f25ade`

That value is a historical checkpoint,
not the fingerprint of the final dossier.

### 11.7 Change control and evidence retention

When an implementation, test source,
log or supporting document changes:

1. Record the changed file and reason.
2. Recalculate its SHA-256 fingerprint.
3. Identify affected controls and claims.
4. Re-execute applicable regression tests.
5. Update TEST_RESULTS and TEST_MATRIX.
6. Update the evidence register and risks.
7. Review the affected acceptance gates.
8. Record the reviewer and decision.
9. Preserve the previous evidence
   or identify its archived location.

A changed file must not silently
retain its earlier fingerprint.

Historical logs must not be presented
as evidence of a new implementation
without demonstrating compatibility.

### 11.8 Integrity conclusion

Sixteen external evidence files
were verified against their recorded
SHA-256 fingerprints.

Four retained local regression logs
contained 116 PASS markers, zero
FAIL markers, zero ERROR markers
and four exact ROLLBACK results.

This supports traceability and
reproducibility of the selected
local engineering evidence.

It does not establish hosted
deployment, independent certification
or production approval.

## 12. Verification statement

### 12.1 Statement purpose and authority

This statement records the internal engineering verification
position for Madzera Migration 067 as of 28 October 2026.

It is a controlled compilation of reviewed implementation,
local regression evidence, outstanding risks and release gates.

It is not a third-party assurance opinion, penetration-test
certificate, regulatory certification or production approval.

### 12.2 Implementation examined

**Primary implementation:**
`database/migrations/067_operational_case_work_authorisation.sql`

**Verified source SHA-256:**
`7d32da0aa17fd2646bed48b7f5dd1c414194102b3212ac0eea05e51c077ef5f3`

The implementation extends organisation-scoped team-work
authorisation into protected operational case workflows.

Reviewed functions address case details, assignment Save,
updates, comments, audit-history retrieval, evidence
operations, Storage authorisation and active-lock visibility.

The intended security boundary requires effective team-work
permission in addition to applicable exclusive-lock ownership.

### 12.3 Established local verification evidence

The retained local PostgreSQL executions of Tests 057–060
record the following results:

| Verification measure | Recorded result |
|---|---:|
| Regression execution logs | 4 |
| PASS markers | 116 |
| FAIL markers | 0 |
| ERROR markers | 0 |
| Exact transaction ROLLBACK results | 4 |
| Registered external evidence files | 16 |
| Matching external SHA-256 fingerprints | 16 |

These results support selected database-level assertions
within the tested scenarios and local environment.

The corresponding source files and execution logs are
identified in Section 11.

PASS markers are not evidence of exhaustive independent
verification or complete production security.

### 12.4 Bounded engineering findings

The reviewed source, recorded inspections and selected
local tests support the following bounded findings:

1. Reviewed operational case functions contain
   team-work authorisation enforcement paths.
2. The reviewed design distinguishes effective team
   permission from possession of an exclusive case lock.
3. Selected local regressions record restriction or
   denial of protected operations after work revocation.
4. Selected local regressions cover active-lock visibility
   and evidence reservation or recovery-status controls.
5. Locking, Save, reassignment confirmation and audit
   compatibility have been examined at source level;
   complete browser-level compatibility remains pending.
6. Selected claims can be traced to identified source,
   execution logs and supporting evidence registers.

These findings must not be interpreted as proof that
all functions, attack paths or deployment configurations
have been independently verified.

### 12.5 Outstanding production acceptance gates

The following gate statuses are carried forward
from Section 10:

| Gate | Required assurance | Status |
|---|---|---|
| G067-01 | Exhaustive function-level behavioural coverage | NOT ESTABLISHED |
| G067-02 | Frontend locking and Save compatibility | PENDING |
| G067-03 | Authenticated HTTP RPC enforcement | PENDING |
| G067-04 | Browser-level permission revocation | PENDING |
| G067-05 | Concurrency and transaction safety | PENDING |
| G067-06 | Hosted deployment verification | PENDING |
| G067-07 | Independent security assessment | PENDING |
| G067-08 | Real authenticated Storage API verification | PENDING |
| G067-09 | Audit and denial integrity reconciliation | NOT ESTABLISHED |
| G067-10 | Risk disposition and release decision | PENDING |

Two gates are NOT ESTABLISHED and eight are PENDING.

No gate is represented as formally accepted.

### 12.6 Residual-risk position

Section 9 records twelve residual risks,
R067-01 through R067-12.

All twelve remain OPEN in the current register.

No risk is formally accepted, closed or transferred
by preparation of this dossier.

Future disposition requires documented supporting
evidence, an identified decision-maker, rationale,
review date and explicit approval.

### 12.7 Privacy-first architecture qualification

Madzera's privacy-first objective informs its
organisation isolation, permission enforcement,
controlled evidence access and auditability.

The reviewed local controls provide engineering
evidence relevant to that objective.

They do not independently establish complete data
residency, absence of data exfiltration, end-to-end
privacy compliance or certification against
PAS 41201 or another external standard.

Such claims require additional deployment,
operational, technical and compliance evidence.

### 12.8 Demonstration and production boundary

Selected database-level security controls have
positive recorded local verification results.

An MVP demonstration is distinct from a
production deployment and must comply with
the controls applicable to its environment.

This dossier does not automatically authorise
an MVP demonstration or production release.

**Production decision: NOT APPROVED FOR PRODUCTION.**

Hosted production verification, independent
security approval and regulatory certification
are not established by this evidence.

### 12.9 Ownership and approval record

**Document owner:** Madzera engineering.

**Evidence compilation date:** 28 October 2026.

**Evidence basis:** Reviewed repository sources,
local PostgreSQL inspections and retained
regression execution logs.

**Independent reviewer:** Not recorded.

**Security approver:** Not recorded.

**Production release approver:** Not recorded.

**Formal approval date:** Not applicable.

No approval, signature or independent review
is implied by document preparation.

### 12.10 Final engineering verification conclusion

The available evidence supports a traceable,
locally tested implementation of selected
Migration 067 operational case-work
authorisation controls.

The reviewed implementation aims to prevent
continued protected case activity when effective
team-work permission has been revoked,
including where a case lock remains valid.

The retained local regression results are
positive within their recorded scenarios.

However, outstanding function-level,
frontend, authenticated HTTP, Storage API,
concurrency, audit, hosted deployment and
independent assessment requirements prevent
a production-readiness conclusion.

**Final assurance classification:**
Selected database-level security controls
locally verified; production acceptance incomplete.

**Final release status: NOT APPROVED FOR PRODUCTION.**

This statement must be revised when additional
verified evidence, residual-risk decisions
and formal approvals become available.
