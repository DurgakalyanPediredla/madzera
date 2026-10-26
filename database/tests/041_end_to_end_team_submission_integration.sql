-- MADZERA TEST 041
-- End-to-end administrator provisioning, team permission and case submission.
-- Requires migrations 060-063.
-- Disposable local development database only.
-- All changes are rolled back.

\set ON_ERROR_STOP on

BEGIN;

SET LOCAL statement_timeout = '60s';

CREATE TEMP TABLE test041_fixture (
    organisation_id uuid NOT NULL,
    administrator_id uuid NOT NULL,
    administrator_auth uuid NOT NULL,
    colleague_id uuid NOT NULL,
    colleague_auth uuid NOT NULL,
    team_id uuid,
    case_id uuid
);

GRANT SELECT ON test041_fixture TO authenticated;

WITH ranked AS (
    SELECT
        u.id,
        u.auth_user_id,
        u.organisation_id,
        ROW_NUMBER() OVER (
            PARTITION BY u.organisation_id
            ORDER BY u.id
        ) AS employee_number
    FROM public.users u
    WHERE u.is_active = TRUE
      AND u.auth_user_id IS NOT NULL
),
eligible AS (
    SELECT r.organisation_id
    FROM ranked r
    WHERE NOT EXISTS (
        SELECT 1
        FROM public.organisation_administrators oa
        WHERE oa.organisation_id = r.organisation_id
    )
    GROUP BY r.organisation_id
    HAVING COUNT(*) >= 2
    ORDER BY r.organisation_id
    LIMIT 1
)
INSERT INTO test041_fixture (
    organisation_id,
    administrator_id,
    administrator_auth,
    colleague_id,
    colleague_auth
)
SELECT
    a.organisation_id,
    a.id,
    a.auth_user_id,
    b.id,
    b.auth_user_id
FROM ranked a
JOIN ranked b
  ON b.organisation_id = a.organisation_id
 AND b.employee_number = 2
WHERE a.organisation_id = (
    SELECT organisation_id FROM eligible
)
AND a.employee_number = 1;

DO $test$
BEGIN
    IF (SELECT COUNT(*) FROM test041_fixture) <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Eligible administrator/colleague fixtures unavailable';
    END IF;

    RAISE NOTICE 'PASS: Dynamic integration fixtures selected';
END;
$test$;

-- Initial provisioning is deliberately performed as postgres.
DO $test$
DECLARE
    f test041_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test041_fixture;

    IF madzera_internal.provision_initial_organisation_admin(
        f.organisation_id,
        f.administrator_id,
        'TEST041 controlled end-to-end integration verification'
    ) IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'FAIL: Administrator provisioning failed';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.permission_audit_events e
        WHERE e.organisation_id = f.organisation_id
          AND e.target_user_id = f.administrator_id
          AND e.permission_type = 'organisation_admin'
          AND e.action = 'granted'
          AND e.reason =
              'TEST041 controlled end-to-end integration verification'
    ) THEN
        RAISE EXCEPTION 'FAIL: Administrator provisioning audit missing';
    END IF;

    RAISE NOTICE 'PASS: Administrator provisioning and audit';
END;
$test$;

-- Authenticate the newly provisioned administrator.
SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT administrator_auth::text FROM test041_fixture),
    true
);

SET LOCAL ROLE authenticated;

SELECT set_config(
    'madzera.test041.team_id',
    public.create_organisation_team(
        'TEST041 INTEGRATION TEAM',
        'Rollback-only integration test'
    )::text,
    true
);

RESET ROLE;

DO $test$
DECLARE
    f test041_fixture%ROWTYPE;
    v_team_id uuid := current_setting('madzera.test041.team_id')::uuid;
BEGIN
    SELECT * INTO STRICT f FROM test041_fixture;

    IF NOT EXISTS (
        SELECT 1
        FROM public.teams t
        WHERE t.id = v_team_id
          AND t.organisation_id = f.organisation_id
    ) THEN
        RAISE EXCEPTION 'FAIL: Team organisation attribution incorrect';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.organisation_admin_audit_events e
        WHERE e.organisation_id = f.organisation_id
          AND e.actor_user_id = f.administrator_id
          AND e.team_id = v_team_id
          AND e.action = 'team_created'
    ) THEN
        RAISE EXCEPTION 'FAIL: Team creation audit missing';
    END IF;

    RAISE NOTICE 'PASS: Administrator team creation and audit';
END;
$test$;

SET LOCAL ROLE authenticated;

SELECT public.grant_team_permission(
    current_setting('madzera.test041.team_id')::uuid,
    (SELECT administrator_id FROM test041_fixture),
    'submit',
    'TEST041 explicit case submission authorisation'
);

DO $test$
DECLARE
    v_team_id uuid := current_setting('madzera.test041.team_id')::uuid;
BEGIN
    IF public.has_team_permission(v_team_id, 'submit')
        IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'FAIL: Submit permission not recognised';
    END IF;

    RAISE NOTICE 'PASS: Authenticated submission permission recognised';
END;
$test$;

RESET ROLE;

DO $test$
DECLARE
    f test041_fixture%ROWTYPE;
    v_team_id uuid := current_setting('madzera.test041.team_id')::uuid;
BEGIN
    SELECT * INTO STRICT f FROM test041_fixture;

    IF NOT EXISTS (
        SELECT 1
        FROM public.permission_audit_events e
        WHERE e.organisation_id = f.organisation_id
          AND e.actor_user_id = f.administrator_id
          AND e.target_user_id = f.administrator_id
          AND e.team_id = v_team_id
          AND e.permission_type = 'submit'
          AND e.action = 'granted'
          AND e.reason =
              'TEST041 explicit case submission authorisation'
    ) THEN
        RAISE EXCEPTION 'FAIL: Submission permission audit missing';
    END IF;

    RAISE NOTICE 'PASS: Explicit submission grant and audit';
END;
$test$;

SET LOCAL ROLE authenticated;

SELECT set_config(
    'madzera.test041.case_id',
    public.create_employee_case_v2(
        'TEST041 AUTHORISED CASE',
        'End-to-end integration verification',
        'medium',
        NULL,
        current_setting('madzera.test041.team_id')::uuid,
        'internal_case'
    )::text,
    true
);

RESET ROLE;

DO $test$
DECLARE
    f test041_fixture%ROWTYPE;
    v_team_id uuid := current_setting('madzera.test041.team_id')::uuid;
    v_case_id uuid := current_setting('madzera.test041.case_id')::uuid;
BEGIN
    SELECT * INTO STRICT f FROM test041_fixture;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases c
        WHERE c.id = v_case_id
          AND c.organisation_id = f.organisation_id
          AND c.assigned_team_id = v_team_id
          AND c.initiated_by = 'employee'
    ) THEN
        RAISE EXCEPTION 'FAIL: Case attribution incorrect';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_events e
        WHERE e.case_id = v_case_id
          AND e.organisation_id = f.organisation_id
          AND e.actor_user_id = f.administrator_id
          AND e.to_team_id = v_team_id
          AND e.event_type = 'case_created'
    ) THEN
        RAISE EXCEPTION 'FAIL: Case creation audit missing';
    END IF;

    RAISE NOTICE 'PASS: Authorised case creation and audit';
END;
$test$;

-- Colleague must not inherit administrator's submission permission.
SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT colleague_auth::text FROM test041_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_team_id uuid := current_setting('madzera.test041.team_id')::uuid;
    v_error text;
BEGIN
    IF public.has_team_permission(v_team_id, 'submit')
        IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'FAIL: Colleague inherited submission permission';
    END IF;

    BEGIN
        PERFORM public.create_employee_case_v2(
            'TEST041 UNAUTHORISED CASE',
            NULL,
            'medium',
            NULL,
            v_team_id,
            'internal_case'
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error = RETURNED_SQLSTATE;
    END;

    IF v_error IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION
            'FAIL: Unauthorised submission SQLSTATE %', v_error;
    END IF;

    RAISE NOTICE 'PASS: Colleague submission correctly denied';
END;
$test$;

RESET ROLE;

DO $test$
DECLARE
    f test041_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test041_fixture;

    IF EXISTS (
        SELECT 1
        FROM public.cases c
        WHERE c.organisation_id = f.organisation_id
          AND c.title = 'TEST041 UNAUTHORISED CASE'
    ) THEN
        RAISE EXCEPTION 'FAIL: Rejected case was persisted';
    END IF;

    RAISE NOTICE 'PASS: Rejected case not persisted';
END;
$test$;

ROLLBACK;
