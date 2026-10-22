-- MADZERA TEST 029
-- Evidence upload preparation security.
-- All database changes are rolled back.

\set ON_ERROR_STOP on

BEGIN;

SELECT set_config(
    'test.evidence_expired_lock_token',
    lock_token::text,
    true
)
FROM public.case_locks
WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
  AND locked_by_user_id = 'f1af6f09-7032-428d-a176-7bbfa6dba747'
  AND expires_at <= clock_timestamp();

SELECT set_config(
    'request.jwt.claim.sub',
    'dc36ef25-8ff9-4845-857c-2a191ecc2b4a',
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_lock_token uuid;
BEGIN
    v_lock_token := current_setting(
        'test.evidence_expired_lock_token',
        true
    )::uuid;

    IF v_lock_token IS NULL THEN
        RAISE EXCEPTION 'FAIL: Expired lock fixture missing';
    END IF;

    BEGIN
        PERFORM *
        FROM public.prepare_case_evidence_upload(
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            v_lock_token,
            'test.pdf',
            'application/pdf',
            1024
        );

        RAISE EXCEPTION 'FAIL: Expired lock permitted upload';
    EXCEPTION
        WHEN insufficient_privilege THEN
            IF SQLERRM <> 'Case lock invalid, expired, or not owned by employee' THEN
                RAISE EXCEPTION
                    'FAIL: Unexpected expired-lock rejection: %', SQLERRM;
            END IF;

            RAISE NOTICE 'PASS: Authenticated employee denied by expired lock';
    END;
END;
$test$;

RESET ROLE;

UPDATE public.case_locks
SET expires_at = clock_timestamp() + interval '5 minutes'
WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
  AND locked_by_user_id = 'f1af6f09-7032-428d-a176-7bbfa6dba747';

SELECT set_config(
    'test.evidence_lock_token',
    lock_token::text,
    true
)
FROM public.case_locks
WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';

SELECT set_config(
    'request.jwt.claim.sub',
    'dc36ef25-8ff9-4845-857c-2a191ecc2b4a',
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_reservation_id uuid;
    v_storage_path text;
    v_lock_token uuid;
BEGIN
    v_lock_token := current_setting(
        'test.evidence_lock_token',
        true
    )::uuid;

    -- File validation must happen before reservation creation.
    DECLARE
        v_names text[] := ARRAY[
            '',
            'folder/file.pdf',
            E'bad\\name.pdf',
            E'bad\\nname.pdf'
        ];
        v_name text;
    BEGIN
        FOREACH v_name IN ARRAY v_names LOOP
            BEGIN
                PERFORM *
                FROM public.prepare_case_evidence_upload(
                    'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
                    v_lock_token,
                    v_name,
                    'application/pdf',
                    1024
                );

                RAISE EXCEPTION 'FAIL: Invalid filename accepted';
            EXCEPTION
                WHEN invalid_parameter_value THEN
                    NULL;
            END;
        END LOOP;

        RAISE NOTICE 'PASS: Invalid filenames rejected';
    END;

    BEGIN
        PERFORM *
        FROM public.prepare_case_evidence_upload(
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            v_lock_token,
            'test.exe',
            'application/octet-stream',
            1024
        );

        RAISE EXCEPTION 'FAIL: Unsupported file type accepted';
    EXCEPTION
        WHEN invalid_parameter_value THEN
            RAISE NOTICE 'PASS: Unsupported file type rejected';
    END;

    BEGIN
        PERFORM *
        FROM public.prepare_case_evidence_upload(
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            v_lock_token,
            'empty.pdf',
            'application/pdf',
            0
        );

        RAISE EXCEPTION 'FAIL: Empty file accepted';
    EXCEPTION
        WHEN invalid_parameter_value THEN
            RAISE NOTICE 'PASS: Empty file rejected';
    END;

    BEGIN
        PERFORM *
        FROM public.prepare_case_evidence_upload(
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            v_lock_token,
            'oversized.pdf',
            'application/pdf',
            10485761
        );

        RAISE EXCEPTION 'FAIL: Oversized file accepted';
    EXCEPTION
        WHEN invalid_parameter_value THEN
            RAISE NOTICE 'PASS: File exceeding 10 MB rejected';
    END;

    SELECT reservation_id, storage_path
    INTO v_reservation_id, v_storage_path
    FROM public.prepare_case_evidence_upload(
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
        v_lock_token,
        'test.pdf',
        'application/pdf',
        1024
    );

    IF v_reservation_id IS NULL OR v_storage_path IS NULL THEN
        RAISE EXCEPTION 'FAIL: Valid upload reservation not created';
    END IF;

    PERFORM set_config(
        'test.evidence_created_reservation_id',
        v_reservation_id::text,
        true
    );

    RAISE NOTICE 'PASS: Valid lock permits upload preparation';

    BEGIN
        PERFORM *
        FROM public.prepare_case_evidence_upload(
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            gen_random_uuid(),
            'invalid-token.pdf',
            'application/pdf',
            1024
        );

        RAISE EXCEPTION 'FAIL: Incorrect lock token accepted';
    EXCEPTION
        WHEN insufficient_privilege THEN
            IF SQLERRM <> 'Case lock invalid, expired, or not owned by employee' THEN
                RAISE EXCEPTION
                    'FAIL: Unexpected incorrect-token rejection: %', SQLERRM;
            END IF;

            RAISE NOTICE 'PASS: Incorrect lock token denied';
    END;

    BEGIN
        PERFORM *
        FROM public.prepare_case_evidence_upload(
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            v_lock_token,
            'overlapping.pdf',
            'application/pdf',
            1024
        );

        RAISE EXCEPTION 'FAIL: Overlapping reservation accepted';
    EXCEPTION
        WHEN unique_violation THEN
            IF SQLERRM <> 'An earlier evidence upload requires recovery review' THEN
                RAISE EXCEPTION
                    'FAIL: Unexpected overlapping-reservation rejection: %', SQLERRM;
            END IF;

            RAISE NOTICE 'PASS: Overlapping pending reservation denied';
    END;

    -- This test is inside the authenticated block.
    -- The expired-pending scenario will be tested separately,
    -- after RESET ROLE, to avoid direct table access by employees.


END;
$test$;

RESET ROLE;

-- Simulate an interrupted upload with an expired pending reservation.
UPDATE public.case_evidence_upload_reservations
SET created_at = clock_timestamp() - interval '12 minutes',
    expires_at = clock_timestamp() - interval '2 minutes'
WHERE id = current_setting(
    'test.evidence_created_reservation_id',
    true
)::uuid
  AND status = 'pending';

DO $test$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.case_evidence_upload_reservations
        WHERE id = current_setting(
            'test.evidence_created_reservation_id',
            true
        )::uuid
          AND status = 'pending'
          AND expires_at <= clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'FAIL: Expired pending fixture not established';
    END IF;
END;
$test$;

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_lock_token uuid;
BEGIN
    v_lock_token := current_setting(
        'test.evidence_lock_token',
        true
    )::uuid;

    BEGIN
        PERFORM *
        FROM public.prepare_case_evidence_upload(
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            v_lock_token,
            'after-expiry.pdf',
            'application/pdf',
            1024
        );

        RAISE EXCEPTION 'FAIL: Expired pending reservation bypassed';
    EXCEPTION
        WHEN unique_violation THEN
            IF SQLERRM <> 'An earlier evidence upload requires recovery review' THEN
                RAISE EXCEPTION
                    'FAIL: Unexpected expired-reservation rejection: %', SQLERRM;
            END IF;

            RAISE NOTICE 'PASS: Expired pending reservation remains blocked';
    END;
END;
$test$;

RESET ROLE;

ROLLBACK;
