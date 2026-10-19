-- MADZERA TEST 022
-- Audit History retrieval, tenant isolation and exclusive-lock security.
-- All test data changes are rolled back.

BEGIN;

SELECT set_config(
    'request.jwt.claim.sub',
    'dc36ef25-8ff9-4845-857c-2a191ecc2b4a',
    true
);

INSERT INTO public.case_locks (
    case_id,
    organisation_id,
    locked_by_user_id,
    locked_at,
    expires_at,
    lock_token
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

INSERT INTO public.case_events (
    case_id,
    organisation_id,
    actor_user_id,
    event_type,
    details
)
VALUES (
    'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
    '0a316877-23d4-4dc3-b0ed-350208d68fb3',
    'f1af6f09-7032-428d-a176-7bbfa6dba747',
    'case_opened',
    'Audit History regression test event'
);

CREATE TEMP TABLE audit_lock_snapshot AS
SELECT *
FROM public.case_locks
WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_count integer;
    v_actor_name text;
BEGIN
    SELECT COUNT(*), MAX(actor_name)
    INTO v_count, v_actor_name
    FROM public.get_employee_case_audit_history(
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
        '11111111-1111-4111-8111-111111111111'
    )
    WHERE details = 'Audit History regression test event'
      AND event_type = 'case_opened';

    IF v_count <> 1 OR v_actor_name IS NULL
       OR v_actor_name = 'System / unknown' THEN
        RAISE EXCEPTION 'FAIL: Event retrieval or attribution incorrect';
    END IF;

    RAISE NOTICE 'PASS: Audit event retrieval and attribution';

    BEGIN
        PERFORM *
        FROM public.get_employee_case_audit_history(
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            '22222222-2222-4222-8222-222222222222'
        );

        RAISE EXCEPTION 'FAIL: Incorrect lock token accepted';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: Incorrect lock token rejected';
    END;
END;
$test$;

SELECT set_config(
    'request.jwt.claim.sub',
    'cd9c949c-8c81-42db-88a2-e08091866ed0',
    true
);

DO $test$
BEGIN
    BEGIN
        PERFORM *
        FROM public.get_employee_case_audit_history(
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            '11111111-1111-4111-8111-111111111111'
        );

        RAISE EXCEPTION 'FAIL: Other employee accepted';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: Other employee rejected';
    END;
END;
$test$;

SELECT set_config(
    'request.jwt.claim.sub',
    '33e98afb-f3fd-44ad-89b1-4bb88b20e37d',
    true
);

DO $test$
BEGIN
    BEGIN
        PERFORM *
        FROM public.get_employee_case_audit_history(
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            '11111111-1111-4111-8111-111111111111'
        );

        RAISE EXCEPTION 'FAIL: Cross-organisation access accepted';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: Cross-organisation access rejected';
    END;
END;
$test$;

RESET ROLE;

DO $test$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.case_locks AS current_lock
        JOIN audit_lock_snapshot AS snapshot
          ON snapshot.case_id = current_lock.case_id
        WHERE current_lock.lock_token IS DISTINCT FROM snapshot.lock_token
           OR current_lock.locked_by_user_id
              IS DISTINCT FROM snapshot.locked_by_user_id
           OR current_lock.expires_at IS DISTINCT FROM snapshot.expires_at
    ) THEN
        RAISE EXCEPTION 'FAIL: Audit reading modified the lock';
    END IF;

    RAISE NOTICE 'PASS: Exclusive lock preserved';
END;
$test$;

UPDATE public.case_locks
SET expires_at = clock_timestamp() - interval '1 second',
    locked_at = clock_timestamp() - interval '6 minutes'
WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';

SELECT set_config(
    'request.jwt.claim.sub',
    'dc36ef25-8ff9-4845-857c-2a191ecc2b4a',
    true
);

SET LOCAL ROLE authenticated;

DO $test$
BEGIN
    BEGIN
        PERFORM *
        FROM public.get_employee_case_audit_history(
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            '11111111-1111-4111-8111-111111111111'
        );

        RAISE EXCEPTION 'FAIL: Expired lock accepted';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: Expired lock rejected';
    END;
END;
$test$;

RESET ROLE;

ROLLBACK;
