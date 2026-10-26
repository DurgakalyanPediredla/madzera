-- MADZERA TEST 040
-- Migration 063: Mandatory Destination-Team Submission Authorisation
--
-- Requires Migration 063, active employees in two organisations,
-- and the existing case-creation RPCs.
--
-- All test-created data is rolled back.
-- Run only against a disposable local development database.

\set ON_ERROR_STOP on

BEGIN;

-- Discover active employee fixtures without hardcoded identifiers.

CREATE TEMP TABLE test040_fixture (
    employee_a uuid NOT NULL,
    auth_a uuid NOT NULL,
    colleague_a uuid NOT NULL,
    auth_colleague uuid NOT NULL,
    organisation_a uuid NOT NULL,
    employee_b uuid NOT NULL,
    auth_b uuid NOT NULL,
    organisation_b uuid NOT NULL,
    team_a uuid,
    team_b uuid,
    successful_case_id uuid
);

GRANT SELECT ON test040_fixture TO authenticated;

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
    SELECT organisation_id
    FROM ranked
    GROUP BY organisation_id
    HAVING COUNT(*) >= 2
    ORDER BY organisation_id
    LIMIT 1
),
other_org AS (
    SELECT organisation_id
    FROM ranked
    WHERE organisation_id <> (
        SELECT organisation_id FROM eligible
    )
    GROUP BY organisation_id
    ORDER BY organisation_id
    LIMIT 1
)
INSERT INTO test040_fixture (
    employee_a,
    auth_a,
    colleague_a,
    auth_colleague,
    organisation_a,
    employee_b,
    auth_b,
    organisation_b
)
SELECT
    a.id,
    a.auth_user_id,
    colleague.id,
    colleague.auth_user_id,
    a.organisation_id,
    b.id,
    b.auth_user_id,
    b.organisation_id
FROM ranked a
JOIN ranked colleague
  ON colleague.organisation_id = a.organisation_id
 AND colleague.employee_number = 2
JOIN ranked b
  ON b.organisation_id = (
      SELECT organisation_id FROM other_org
  )
 AND b.employee_number = 1
WHERE a.organisation_id = (
    SELECT organisation_id FROM eligible
)
  AND a.employee_number = 1;

DO $test$
BEGIN
    IF (SELECT COUNT(*) FROM test040_fixture) <> 1 THEN
        RAISE EXCEPTION 'FAIL: Required employee fixtures unavailable';
    END IF;

    RAISE NOTICE 'PASS: Multi-organisation employee fixtures';
END;
$test$;

-- Create two organisation-scoped destination teams.

WITH created AS (
    INSERT INTO public.teams (organisation_id, name)
    SELECT organisation_a, 'TEST040 DESTINATION A'
    FROM test040_fixture
    RETURNING id, organisation_id
)
UPDATE test040_fixture f
SET team_a = created.id
FROM created
WHERE created.organisation_id = f.organisation_a;

WITH created AS (
    INSERT INTO public.teams (organisation_id, name)
    SELECT organisation_b, 'TEST040 DESTINATION B'
    FROM test040_fixture
    RETURNING id, organisation_id
)
UPDATE test040_fixture f
SET team_b = created.id
FROM created
WHERE created.organisation_id = f.organisation_b;

DO $test$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM test040_fixture
        WHERE team_a IS NULL OR team_b IS NULL
    ) THEN
        RAISE EXCEPTION 'FAIL: Test teams unavailable';
    END IF;

    RAISE NOTICE 'PASS: Organisation-scoped teams created';
END;
$test$;

-- Authenticate employee A.

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test040_fixture),
    true
);

SET LOCAL ROLE authenticated;

-- Missing destination team must be rejected.

DO $test$
DECLARE
    v_error text;
BEGIN
    BEGIN
        PERFORM public.create_employee_case_v2(
            'TEST040 MISSING DESTINATION',
            NULL,
            'medium',
            NULL,
            NULL,
            'internal_case'
        );

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error = RETURNED_SQLSTATE;
    END;

    IF v_error IS DISTINCT FROM '22023' THEN
        RAISE EXCEPTION
            'FAIL: Missing destination returned SQLSTATE %',
            COALESCE(v_error, 'NO ERROR');
    END IF;

    RAISE NOTICE 'PASS: Missing destination rejected';
END;
$test$;

-- A team belonging to another organisation must be rejected.

DO $test$
DECLARE
    v_team_b uuid;
    v_error text;
BEGIN
    SELECT team_b INTO STRICT v_team_b FROM test040_fixture;

    BEGIN
        PERFORM public.create_employee_case_v2(
            'TEST040 FOREIGN DESTINATION',
            NULL,
            'medium',
            NULL,
            v_team_b,
            'internal_case'
        );

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error = RETURNED_SQLSTATE;
    END;

    IF v_error IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION
            'FAIL: Foreign destination returned SQLSTATE %',
            COALESCE(v_error, 'NO ERROR');
    END IF;

    RAISE NOTICE 'PASS: Cross-organisation destination rejected';
END;
$test$;

-- A same-organisation team without a submit grant must be rejected.

DO $test$
DECLARE
    v_team_a uuid;
    v_error text;
BEGIN
    SELECT team_a INTO STRICT v_team_a FROM test040_fixture;

    BEGIN
        PERFORM public.create_employee_case_v2(
            'TEST040 NO SUBMIT GRANT',
            NULL,
            'medium',
            NULL,
            v_team_a,
            'internal_case'
        );

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error = RETURNED_SQLSTATE;
    END;

    IF v_error IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION
            'FAIL: Ungranted submission returned SQLSTATE %',
            COALESCE(v_error, 'NO ERROR');
    END IF;

    RAISE NOTICE 'PASS: Ungranted submission rejected';
END;
$test$;

RESET ROLE;


-- Verify work/manage permissions do not imply submission permission.

RESET ROLE;

INSERT INTO public.team_permission_grants (
    organisation_id, team_id, user_id, permission_type
)
SELECT organisation_a, team_a, employee_a, permission_type
FROM test040_fixture
CROSS JOIN (
    VALUES ('work'), ('manage')
) AS permissions(permission_type);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_team uuid;
    v_error text;
BEGIN
    SELECT team_a INTO STRICT v_team FROM test040_fixture;

    IF public.has_team_permission(v_team, 'work') IS DISTINCT FROM TRUE
       OR public.has_team_permission(v_team, 'manage') IS DISTINCT FROM TRUE
       OR public.has_team_permission(v_team, 'submit') IS DISTINCT FROM FALSE
    THEN
        RAISE EXCEPTION 'FAIL: Permission separation incorrect';
    END IF;

    BEGIN
        PERFORM public.create_employee_case_v2(
            'TEST040 WORK MANAGE ONLY',
            NULL, 'medium', NULL, v_team, 'internal_case'
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error = RETURNED_SQLSTATE;
    END;

    IF v_error IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION
            'FAIL: Work/manage-only submission returned SQLSTATE %',
            COALESCE(v_error, 'NO ERROR');
    END IF;

    RAISE NOTICE 'PASS: Work/manage permissions do not authorise submission';
END;
$test$;

RESET ROLE;

-- Remove work/manage grants before the explicit submit-grant scenario.

DELETE FROM public.team_permission_grants g
USING test040_fixture f
WHERE g.team_id = f.team_a
  AND g.user_id = f.employee_a
  AND g.permission_type IN ('work', 'manage');

-- Grant submit permission to employee A only.

INSERT INTO public.team_permission_grants (
    organisation_id,
    team_id,
    user_id,
    permission_type
)
SELECT
    organisation_a,
    team_a,
    employee_a,
    'submit'
FROM test040_fixture;

-- Reauthenticate employee A.

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test040_fixture),
    true
);

SET LOCAL ROLE authenticated;

-- Successful authorised submission.

DO $test$
DECLARE
    v_team_a uuid;
    v_case_id uuid;
BEGIN
    SELECT team_a INTO STRICT v_team_a FROM test040_fixture;

    IF public.has_team_permission(v_team_a, 'submit')
       IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'FAIL: Submit permission not recognised';
    END IF;

    v_case_id := public.create_employee_case_v2(
        'TEST040 AUTHORISED SUBMISSION',
        'Mandatory destination-team verification',
        'high',
        NULL,
        v_team_a,
        'internal_case'
    );

    PERFORM set_config(
        'madzera.test040.case_id',
        v_case_id::text,
        true
    );

    RAISE NOTICE 'PASS: Authorised submission accepted';
END;
$test$;

RESET ROLE;

-- Verify the created case and its audit event.

DO $test$
DECLARE
    v_case_id uuid := current_setting('madzera.test040.case_id')::uuid;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.cases c
        JOIN test040_fixture f
          ON c.organisation_id = f.organisation_a
        WHERE c.id = v_case_id
          AND c.assigned_team_id = f.team_a
          AND c.initiated_by = 'employee'
    ) THEN
        RAISE EXCEPTION
            'FAIL: Authorised case organisation/team attribution incorrect';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_events e
        JOIN test040_fixture f
          ON e.organisation_id = f.organisation_a
        WHERE e.case_id = v_case_id
          AND e.actor_user_id = f.employee_a
          AND e.to_team_id = f.team_a
          AND e.event_type = 'case_created'
    ) THEN
        RAISE EXCEPTION
            'FAIL: Authorised case creation audit missing';
    END IF;

    RAISE NOTICE 'PASS: Case and audit attribution verified';
END;
$test$;


-- A colleague cannot inherit another employee's submit grant.

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_colleague::text FROM test040_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_team uuid;
    v_error text;
BEGIN
    SELECT team_a INTO STRICT v_team FROM test040_fixture;

    BEGIN
        PERFORM public.create_employee_case_v2(
            'TEST040 COLLEAGUE WITHOUT GRANT',
            NULL, 'medium', NULL, v_team, 'internal_case'
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error = RETURNED_SQLSTATE;
    END;

    IF v_error IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION
            'FAIL: Colleague submission returned SQLSTATE %',
            COALESCE(v_error, 'NO ERROR');
    END IF;

    RAISE NOTICE 'PASS: Colleague cannot inherit submit permission';
END;
$test$;

RESET ROLE;

-- Revoke employee A's submit grant.

DELETE FROM public.team_permission_grants g
USING test040_fixture f
WHERE g.team_id = f.team_a
  AND g.user_id = f.employee_a
  AND g.permission_type = 'submit';

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test040_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_team uuid;
    v_error text;
BEGIN
    SELECT team_a INTO STRICT v_team FROM test040_fixture;

    IF public.has_team_permission(v_team, 'submit')
       IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'FAIL: Revoked submit permission still effective';
    END IF;

    BEGIN
        PERFORM public.create_employee_case_v2(
            'TEST040 REVOKED SUBMISSION',
            NULL, 'medium', NULL, v_team, 'internal_case'
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error = RETURNED_SQLSTATE;
    END;

    IF v_error IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION
            'FAIL: Revoked submission returned SQLSTATE %',
            COALESCE(v_error, 'NO ERROR');
    END IF;

    RAISE NOTICE 'PASS: Revoked submit permission prevents submission';
END;
$test$;

RESET ROLE;


-- Verify that rejected submissions produced no persistent case records.
-- Any audit event associated with an unexpected case is also a failure.

DO $test$
DECLARE
    v_rejected_cases integer;
    v_rejected_events integer;
BEGIN
    SELECT COUNT(*)
    INTO v_rejected_cases
    FROM public.cases c
    WHERE c.title IN (
        'TEST040 MISSING DESTINATION',
        'TEST040 FOREIGN DESTINATION',
        'TEST040 NO SUBMIT GRANT',
        'TEST040 WORK MANAGE ONLY',
        'TEST040 COLLEAGUE WITHOUT GRANT',
        'TEST040 REVOKED SUBMISSION'
    );

    IF v_rejected_cases <> 0 THEN
        RAISE EXCEPTION
            'FAIL: Rejected submissions created % case records',
            v_rejected_cases;
    END IF;

    SELECT COUNT(*)
    INTO v_rejected_events
    FROM public.case_events e
    JOIN public.cases c
      ON c.id = e.case_id
    WHERE c.title IN (
        'TEST040 MISSING DESTINATION',
        'TEST040 FOREIGN DESTINATION',
        'TEST040 NO SUBMIT GRANT',
        'TEST040 WORK MANAGE ONLY',
        'TEST040 COLLEAGUE WITHOUT GRANT',
        'TEST040 REVOKED SUBMISSION'
    );

    IF v_rejected_events <> 0 THEN
        RAISE EXCEPTION
            'FAIL: Rejected submissions created % audit events',
            v_rejected_events;
    END IF;

    RAISE NOTICE 'PASS: Rejected submissions left no case or audit records';
END;
$test$;

ROLLBACK;
