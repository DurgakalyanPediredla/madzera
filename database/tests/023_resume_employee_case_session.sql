-- MADZERA TEST 023
-- Secure case-session recovery and exclusive-lock preservation.
-- All changes rolled back.

BEGIN;

SELECT set_config(
    'request.jwt.claim.sub',
    'dc36ef25-8ff9-4845-857c-2a191ecc2b4a',
    true
);

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
BEGIN
    IF public.resume_employee_case_session(
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
        '11111111-1111-4111-8111-111111111111'
    ) IS NOT NULL THEN
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
BEGIN
    IF public.resume_employee_case_session(
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
        '11111111-1111-4111-8111-111111111111'
    ) IS NOT NULL THEN
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
