-- MADZERA TEST 023
-- Secure case-session recovery and exclusive-lock preservation.
-- All changes rolled back.

BEGIN;

SELECT set_config(
    'request.jwt.claim.sub',
    'dc36ef25-8ff9-4845-857c-2a191ecc2b4a',
    true
);

-- LEGACY TEAM WORK FIXTURE
-- Compatibility fixture for historical cases without an assigned team.
-- All changes, including the audited case assignment, are rolled back.

CREATE TEMP TABLE legacy_team_work_fixture (
    team_id uuid NOT NULL
) ON COMMIT DROP;

WITH created AS (
    INSERT INTO public.teams (
        organisation_id,
        name
    )
    VALUES (
        '0a316877-23d4-4dc3-b0ed-350208d68fb3',
        'LEGACY WORK REGRESSION TEAM'
    )
    RETURNING id
)
INSERT INTO legacy_team_work_fixture (team_id)
SELECT id FROM created;

INSERT INTO public.team_members (
    organisation_id,
    team_id,
    user_id
)
SELECT
    '0a316877-23d4-4dc3-b0ed-350208d68fb3',
    team_id,
    'f1af6f09-7032-428d-a176-7bbfa6dba747'
FROM legacy_team_work_fixture;

INSERT INTO public.team_permission_grants (
    organisation_id,
    team_id,
    user_id,
    permission_type
)
SELECT
    '0a316877-23d4-4dc3-b0ed-350208d68fb3',
    team_id,
    'f1af6f09-7032-428d-a176-7bbfa6dba747',
    'work'
FROM legacy_team_work_fixture;

UPDATE public.cases
SET assigned_team_id = (
    SELECT team_id
    FROM legacy_team_work_fixture
)
WHERE id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
  AND organisation_id = '0a316877-23d4-4dc3-b0ed-350208d68fb3'
  AND assigned_team_id IS NULL;

DO $fixture$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.cases c
        JOIN legacy_team_work_fixture f
          ON f.team_id = c.assigned_team_id
        WHERE c.id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
          AND c.organisation_id = '0a316877-23d4-4dc3-b0ed-350208d68fb3'
    ) THEN
        RAISE EXCEPTION
            'FAIL: Legacy case work fixture was not established';
    END IF;

    RAISE NOTICE
        'PASS: Legacy case assigned to authorised test team';
END;
$fixture$;


INSERT INTO public.case_locks (
    case_id, organisation_id, locked_by_user_id,
    locked_at, expires_at, lock_token
)
VALUES (
    'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
    '0a316877-23d4-4dc3-b0ed-350208d68fb3',
    'f1af6f09-7032-428d-a176-7bbfa6dba747',
    clock_timestamp(),
    clock_timestamp() + interval '5 minutes',
    '11111111-1111-4111-8111-111111111111'
)
ON CONFLICT (case_id) DO UPDATE
SET locked_by_user_id = EXCLUDED.locked_by_user_id,
    locked_at = EXCLUDED.locked_at,
    expires_at = EXCLUDED.expires_at,
    lock_token = EXCLUDED.lock_token;

CREATE TEMP TABLE resume_lock_snapshot AS
SELECT *
FROM public.case_locks
WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_expiry timestamptz;
BEGIN
    SELECT public.resume_employee_case_session(
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
        '11111111-1111-4111-8111-111111111111'
    ) INTO v_expiry;

    IF v_expiry IS NULL THEN
        RAISE EXCEPTION 'FAIL: Valid owner could not resume';
    END IF;
    RAISE NOTICE 'PASS: Valid owner resumes active lock';

    SELECT public.resume_employee_case_session(
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
        '22222222-2222-4222-8222-222222222222'
    ) INTO v_expiry;

    IF v_expiry IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Incorrect token accepted';
    END IF;
    RAISE NOTICE 'PASS: Incorrect token rejected';

    SELECT public.resume_employee_case_session(
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
        NULL
    ) INTO v_expiry;

    IF v_expiry IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: NULL token accepted';
    END IF;
    RAISE NOTICE 'PASS: NULL token rejected';
END;
$test$;

SELECT set_config(
    'request.jwt.claim.sub',
    'cd9c949c-8c81-42db-88a2-e08091866ed0',
    true
);

DO $test$
DECLARE
    v_expiry timestamptz;
BEGIN
    BEGIN
        SELECT public.resume_employee_case_session(
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            '11111111-1111-4111-8111-111111111111'
        ) INTO v_expiry;
    EXCEPTION WHEN insufficient_privilege THEN
        v_expiry := NULL;
    END;

    IF v_expiry IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Different employee resumed lock';
    END IF;

    RAISE NOTICE 'PASS: Different employee rejected';
END;
$test$;

SELECT set_config(
    'request.jwt.claim.sub',
    '33e98afb-f3fd-44ad-89b1-4bb88b20e37d',
    true
);

DO $test$
DECLARE
    v_expiry timestamptz;
BEGIN
    BEGIN
        SELECT public.resume_employee_case_session(
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            '11111111-1111-4111-8111-111111111111'
        ) INTO v_expiry;
    EXCEPTION WHEN insufficient_privilege THEN
        v_expiry := NULL;
    END;

    IF v_expiry IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Cross-organisation resume allowed';
    END IF;

    RAISE NOTICE 'PASS: Cross-organisation access rejected';
END;
$test$;

RESET ROLE;

DO $test$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.case_locks AS current_lock
        JOIN resume_lock_snapshot AS original
          ON original.case_id = current_lock.case_id
        WHERE current_lock.lock_token IS DISTINCT FROM original.lock_token
           OR current_lock.locked_by_user_id
              IS DISTINCT FROM original.locked_by_user_id
           OR current_lock.expires_at IS DISTINCT FROM original.expires_at
           OR current_lock.locked_at IS DISTINCT FROM original.locked_at
    ) THEN
        RAISE EXCEPTION 'FAIL: Recovery modified the lock';
    END IF;
    RAISE NOTICE 'PASS: Recovery leaves lock unchanged';
END;
$test$;

UPDATE public.case_locks
SET locked_at = clock_timestamp() - interval '6 minutes',
    expires_at = clock_timestamp() - interval '1 second'
WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';

SELECT set_config(
    'request.jwt.claim.sub',
    'dc36ef25-8ff9-4845-857c-2a191ecc2b4a',
    true
);

SET LOCAL ROLE authenticated;

DO $test$
BEGIN
    IF public.resume_employee_case_session(
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
        '11111111-1111-4111-8111-111111111111'
    ) IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Expired lock resumed';
    END IF;
    RAISE NOTICE 'PASS: Expired lock rejected';
END;
$test$;

RESET ROLE;

ROLLBACK;
