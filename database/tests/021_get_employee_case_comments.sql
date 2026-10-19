\set ON_ERROR_STOP on

BEGIN;

SELECT set_config(
    'request.jwt.claim.sub',
    'dc36ef25-8ff9-4845-857c-2a191ecc2b4a',
    true
);

INSERT INTO public.case_locks (
    case_id, organisation_id, locked_by_user_id,
    expires_at, lock_token
)
VALUES (
    'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
    '0a316877-23d4-4dc3-b0ed-350208d68fb3',
    'f1af6f09-7032-428d-a176-7bbfa6dba747',
    clock_timestamp() + interval '5 minutes',
    '11111111-1111-4111-8111-111111111111'
);

CREATE TEMP TABLE test_lock_before AS
SELECT * FROM public.case_locks
WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_comment_id uuid;
    v_count integer;
    v_rejected boolean;
BEGIN
    v_comment_id := public.save_employee_case_comment(
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
        '11111111-1111-4111-8111-111111111111',
        'Madzera read regression test'
    );

    SELECT COUNT(*) INTO v_count
    FROM public.get_employee_case_comments(
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
        '11111111-1111-4111-8111-111111111111'
    ) AS activity
    WHERE activity.id = v_comment_id
      AND activity.body = 'Madzera read regression test'
      AND activity.author_user_id =
          'f1af6f09-7032-428d-a176-7bbfa6dba747'
      AND activity.author_name = 'Test Employee A';

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'FAIL: Saved comment not returned correctly';
    END IF;

    RAISE NOTICE 'PASS: Comment reading and attribution';

    v_rejected := false;
    BEGIN
        PERFORM *
        FROM public.get_employee_case_comments(
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            '22222222-2222-4222-8222-222222222222'
        );
    EXCEPTION WHEN insufficient_privilege THEN
        v_rejected := true;
    END;

    IF NOT v_rejected THEN
        RAISE EXCEPTION 'FAIL: Incorrect token accepted';
    END IF;

    RAISE NOTICE 'PASS: Incorrect token rejected';

    PERFORM set_config(
        'request.jwt.claim.sub',
        'cd9c949c-8c81-42db-88a2-e08091866ed0',
        true
    );

    v_rejected := false;
    BEGIN
        PERFORM *
        FROM public.get_employee_case_comments(
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            '11111111-1111-4111-8111-111111111111'
        );
    EXCEPTION WHEN insufficient_privilege THEN
        v_rejected := true;
    END;

    IF NOT v_rejected THEN
        RAISE EXCEPTION 'FAIL: Other employee accepted';
    END IF;

    RAISE NOTICE 'PASS: Other employee rejected';

    PERFORM set_config(
        'request.jwt.claim.sub',
        '33e98afb-f3fd-44ad-89b1-4bb88b20e37d',
        true
    );

    v_rejected := false;
    BEGIN
        PERFORM *
        FROM public.get_employee_case_comments(
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            '11111111-1111-4111-8111-111111111111'
        );
    EXCEPTION WHEN insufficient_privilege THEN
        v_rejected := true;
    END;

    IF NOT v_rejected THEN
        RAISE EXCEPTION 'FAIL: Cross-organisation access accepted';
    END IF;

    RAISE NOTICE 'PASS: Cross-organisation access rejected';
END;
$test$;

RESET ROLE;

DO $test$
BEGIN
    IF EXISTS (
        (SELECT * FROM public.case_locks
         WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
         EXCEPT SELECT * FROM test_lock_before)
        UNION ALL
        (SELECT * FROM test_lock_before
         EXCEPT SELECT * FROM public.case_locks
         WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea')
    ) THEN
        RAISE EXCEPTION 'FAIL: Reading modified exclusive lock';
    END IF;

    RAISE NOTICE 'PASS: Exclusive lock preserved';
END;
$test$;

UPDATE public.case_locks
SET
    locked_at = clock_timestamp() - interval '10 minutes',
    expires_at = clock_timestamp() - interval '5 minutes'
WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';

SELECT set_config(
    'request.jwt.claim.sub',
    'dc36ef25-8ff9-4845-857c-2a191ecc2b4a',
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_rejected boolean := false;
BEGIN
    BEGIN
        PERFORM *
        FROM public.get_employee_case_comments(
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            '11111111-1111-4111-8111-111111111111'
        );
    EXCEPTION WHEN insufficient_privilege THEN
        v_rejected := true;
    END;

    IF NOT v_rejected THEN
        RAISE EXCEPTION 'FAIL: Expired lock accepted';
    END IF;

    RAISE NOTICE 'PASS: Expired lock rejected';
END;
$test$;

RESET ROLE;

ROLLBACK;
