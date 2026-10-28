\set ON_ERROR_STOP on

-- MADZERA TEST 035
-- Evidence download-path RPC security regression.
-- LOCAL SUPABASE POSTGRESQL ONLY.
--
-- Tests public.get_employee_case_evidence_download_path.
-- All database mutations are transaction-scoped and rolled back.
-- Never execute this file against hosted Supabase.

BEGIN;

-- TEST-ONLY EXPIRED LOCK FIXTURE
-- Do not overwrite an existing case lock.
-- This fixture is removed by the final ROLLBACK.

DO $fixture$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.case_locks
        WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
    ) THEN
        RAISE EXCEPTION
            'STOP: Existing case lock must not be overwritten';
    END IF;

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
        clock_timestamp() - interval '10 minutes',
        clock_timestamp() - interval '5 minutes',
        gen_random_uuid()
    );

    RAISE NOTICE 'PASS: Synthetic expired case lock created';
END;
$fixture$;

DO $test$
DECLARE
    v_attachment_id uuid;
    v_storage_path text;
BEGIN
    IF current_database() <> 'postgres'
       OR inet_server_port() <> 5432 THEN
        RAISE EXCEPTION 'FAIL: Unexpected database environment';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.cases
        WHERE id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
          AND organisation_id = '0a316877-23d4-4dc3-b0ed-350208d68fb3'
    ) OR NOT EXISTS (
        SELECT 1 FROM public.cases
        WHERE id = 'a1d410f6-0521-4d25-a1f1-9e0023423a14'
          AND organisation_id = 'cbd6a8ae-adf3-4099-9352-1862e1751dea'
    ) THEN
        RAISE EXCEPTION 'FAIL: Case fixtures missing';
    END IF;

    IF (
        SELECT count(*)
        FROM public.users
        WHERE
            (
                id = 'f1af6f09-7032-428d-a176-7bbfa6dba747'
                AND organisation_id = '0a316877-23d4-4dc3-b0ed-350208d68fb3'
                AND auth_user_id = 'dc36ef25-8ff9-4845-857c-2a191ecc2b4a'
            )
            OR (
                id = 'ba0a74da-c3e5-4346-a337-0f536115bb7c'
                AND organisation_id = '0a316877-23d4-4dc3-b0ed-350208d68fb3'
                AND auth_user_id = 'cd9c949c-8c81-42db-88a2-e08091866ed0'
            )
            OR (
                id = 'e5bce736-bcce-4a04-b720-a7b90837e371'
                AND organisation_id = 'cbd6a8ae-adf3-4099-9352-1862e1751dea'
                AND auth_user_id = '33e98afb-f3fd-44ad-89b1-4bb88b20e37d'
            )
    ) <> 3 THEN
        RAISE EXCEPTION 'FAIL: Employee fixtures missing';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.users
        WHERE id IN (
            'f1af6f09-7032-428d-a176-7bbfa6dba747',
            'ba0a74da-c3e5-4346-a337-0f536115bb7c',
            'e5bce736-bcce-4a04-b720-a7b90837e371'
        )
        AND is_active IS DISTINCT FROM true
    ) THEN
        RAISE EXCEPTION 'FAIL: Inactive employee fixture';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.case_locks
        WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
          AND organisation_id = '0a316877-23d4-4dc3-b0ed-350208d68fb3'
          AND locked_by_user_id = 'f1af6f09-7032-428d-a176-7bbfa6dba747'
          AND expires_at <= clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'FAIL: Expected expired lock fixture missing';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.case_locks
        WHERE case_id = 'a1d410f6-0521-4d25-a1f1-9e0023423a14'
    ) THEN
        RAISE EXCEPTION 'FAIL: Organisation B case already locked';
    END IF;

    SELECT a.id, a.storage_reference
    INTO v_attachment_id, v_storage_path
    FROM public.attachments a
    JOIN public.case_evidence_upload_reservations r
      ON r.storage_path = a.storage_reference
     AND r.case_id = a.case_id
     AND r.organisation_id = a.organisation_id
    WHERE a.case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
      AND a.organisation_id = '0a316877-23d4-4dc3-b0ed-350208d68fb3'
      AND a.visibility = 'internal'
      AND r.status = 'completed'
    ORDER BY a.created_at, a.id
    LIMIT 1;

    IF v_attachment_id IS NULL OR v_storage_path IS NULL THEN
        RAISE EXCEPTION 'FAIL: Completed evidence fixture missing';
    END IF;

    PERFORM set_config(
        'madzera.test035.attachment_id',
        v_attachment_id::text, true
    );
    PERFORM set_config(
        'madzera.test035.storage_path',
        v_storage_path, true
    );
    PERFORM set_config(
        'madzera.test035.token_a',
        gen_random_uuid()::text, true
    );
    PERFORM set_config(
        'madzera.test035.token_b',
        gen_random_uuid()::text, true
    );

    RAISE NOTICE 'PASS: Local fixtures validated';
END;
$test$;

-- Temporary locks. Both changes disappear at ROLLBACK.

UPDATE public.case_locks
SET locked_at = clock_timestamp(),
    expires_at = clock_timestamp() + interval '5 minutes',
    lock_token = current_setting('madzera.test035.token_a')::uuid
WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
  AND organisation_id = '0a316877-23d4-4dc3-b0ed-350208d68fb3'
  AND locked_by_user_id = 'f1af6f09-7032-428d-a176-7bbfa6dba747';

INSERT INTO public.case_locks (
    case_id, organisation_id, locked_by_user_id,
    locked_at, expires_at, lock_token
)
VALUES (
    'a1d410f6-0521-4d25-a1f1-9e0023423a14',
    'cbd6a8ae-adf3-4099-9352-1862e1751dea',
    'e5bce736-bcce-4a04-b720-a7b90837e371',
    clock_timestamp(),
    clock_timestamp() + interval '5 minutes',
    current_setting('madzera.test035.token_b')::uuid
);

-- Employee A: valid access, wrong token, unknown attachment.

SELECT set_config(
    'request.jwt.claim.sub',
    'dc36ef25-8ff9-4845-857c-2a191ecc2b4a', true
);
SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_path text;
    v_state text;
    v_message text;
BEGIN
    SELECT public.get_employee_case_evidence_download_path(
        current_setting('madzera.test035.attachment_id')::uuid,
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
        current_setting('madzera.test035.token_a')::uuid
    ) INTO v_path;

    IF v_path IS DISTINCT FROM
       current_setting('madzera.test035.storage_path') THEN
        RAISE EXCEPTION 'FAIL: Valid download returned incorrect path';
    END IF;
    RAISE NOTICE 'PASS: Valid employee receives correct path';

    BEGIN
        PERFORM public.get_employee_case_evidence_download_path(
            current_setting('madzera.test035.attachment_id')::uuid,
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            gen_random_uuid()
        );
        RAISE EXCEPTION 'FAIL: Incorrect token accepted';
    EXCEPTION WHEN SQLSTATE '42501' THEN
        GET STACKED DIAGNOSTICS
            v_state = RETURNED_SQLSTATE,
            v_message = MESSAGE_TEXT;
        IF v_state <> '42501'
           OR v_message <> 'Case access denied or lock expired' THEN
            RAISE EXCEPTION 'FAIL: Unexpected wrong-token rejection: %', v_message;
        END IF;
        RAISE NOTICE 'PASS: Incorrect token denied';
    END;

    BEGIN
        PERFORM public.get_employee_case_evidence_download_path(
            gen_random_uuid(),
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            current_setting('madzera.test035.token_a')::uuid
        );
        RAISE EXCEPTION 'FAIL: Unknown attachment accepted';
    EXCEPTION WHEN SQLSTATE '42501' THEN
        GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
        IF v_message <> 'Evidence attachment not found' THEN
            RAISE EXCEPTION 'FAIL: Unexpected attachment rejection: %', v_message;
        END IF;
        RAISE NOTICE 'PASS: Unknown attachment denied';
    END;
END;
$test$;

RESET ROLE;

-- Expired lock rejection.

UPDATE public.case_locks
SET locked_at = clock_timestamp() - interval '2 minutes',
    expires_at = clock_timestamp() - interval '1 minute'
WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_message text;
BEGIN
    BEGIN
        PERFORM public.get_employee_case_evidence_download_path(
            current_setting('madzera.test035.attachment_id')::uuid,
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            current_setting('madzera.test035.token_a')::uuid
        );
        RAISE EXCEPTION 'FAIL: Expired lock accepted';
    EXCEPTION WHEN SQLSTATE '42501' THEN
        GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
        IF v_message <> 'Case access denied or lock expired' THEN
            RAISE EXCEPTION 'FAIL: Unexpected expiry rejection: %', v_message;
        END IF;
        RAISE NOTICE 'PASS: Expired lock denied';
    END;
END;
$test$;

RESET ROLE;

UPDATE public.case_locks
SET expires_at = clock_timestamp() + interval '5 minutes'
WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';

-- Unlinked identity rejection.

SELECT set_config(
    'request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000099', true
);
SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_message text;
BEGIN
    BEGIN
        PERFORM public.get_employee_case_evidence_download_path(
            current_setting('madzera.test035.attachment_id')::uuid,
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            current_setting('madzera.test035.token_a')::uuid
        );
        RAISE EXCEPTION 'FAIL: Unlinked identity accepted';
    EXCEPTION WHEN SQLSTATE '42501' THEN
        GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
        IF v_message <> 'Authenticated employee and case lock required' THEN
            RAISE EXCEPTION 'FAIL: Unexpected identity rejection: %', v_message;
        END IF;
        RAISE NOTICE 'PASS: Unlinked identity denied';
    END;
END;
$test$;

RESET ROLE;

-- Same-organisation Employee B cannot use Employee A's lock.

SELECT set_config(
    'request.jwt.claim.sub',
    'cd9c949c-8c81-42db-88a2-e08091866ed0', true
);
SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_message text;
BEGIN
    BEGIN
        PERFORM public.get_employee_case_evidence_download_path(
            current_setting('madzera.test035.attachment_id')::uuid,
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            current_setting('madzera.test035.token_a')::uuid
        );
        RAISE EXCEPTION 'FAIL: Other employee accepted';
    EXCEPTION WHEN SQLSTATE '42501' THEN
        GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
        IF v_message <> 'Case access denied or lock expired' THEN
            RAISE EXCEPTION 'FAIL: Unexpected employee rejection: %', v_message;
        END IF;
        RAISE NOTICE 'PASS: Other employee denied';
    END;
END;
$test$;

RESET ROLE;

-- Cross-organisation rejection.
-- Employee C has a valid lock on Organisation B's own case.

SELECT set_config(
    'request.jwt.claim.sub',
    '33e98afb-f3fd-44ad-89b1-4bb88b20e37d', true
);
SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_message text;
    v_path text;
BEGIN
    BEGIN
        PERFORM public.get_employee_case_evidence_download_path(
            current_setting('madzera.test035.attachment_id')::uuid,
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            current_setting('madzera.test035.token_a')::uuid
        );
        RAISE EXCEPTION 'FAIL: Cross-organisation access accepted';
    EXCEPTION WHEN SQLSTATE '42501' THEN
        GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
        IF v_message <> 'Case access denied or lock expired' THEN
            RAISE EXCEPTION 'FAIL: Unexpected tenant rejection: %', v_message;
        END IF;
        RAISE NOTICE 'PASS: Cross-organisation access denied';
    END;
END;
$test$;

RESET ROLE;

-- Correct attachment ID with the wrong case ID is rejected.
-- This exercises the initial case-access check.

SELECT set_config(
    'request.jwt.claim.sub',
    'dc36ef25-8ff9-4845-857c-2a191ecc2b4a', true
);
SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_message text;
BEGIN
    BEGIN
        PERFORM public.get_employee_case_evidence_download_path(
            current_setting('madzera.test035.attachment_id')::uuid,
            'a1d410f6-0521-4d25-a1f1-9e0023423a14',
            current_setting('madzera.test035.token_a')::uuid
        );
        RAISE EXCEPTION 'FAIL: Wrong-case attachment accepted';
    EXCEPTION WHEN SQLSTATE '42501' THEN
        GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
        IF v_message <> 'Case access denied or lock expired' THEN
            RAISE EXCEPTION 'FAIL: Unexpected wrong-case rejection: %', v_message;
        END IF;
        RAISE NOTICE 'PASS: Wrong-case attachment denied';
    END;
END;
$test$;

RESET ROLE;

-- Synthetic pending reservation and attachment.
-- Created under local database administrator role only.

DO $test$
DECLARE
    v_reservation_id uuid := gen_random_uuid();
    v_attachment_id uuid := gen_random_uuid();
    v_path text := 'test035/' || v_reservation_id::text;
BEGIN
    INSERT INTO public.case_evidence_upload_reservations (
        id, case_id, organisation_id, employee_id,
        storage_path, file_name, file_type, file_size_bytes,
        status, created_at, expires_at
    )
    VALUES (
        v_reservation_id,
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
        '0a316877-23d4-4dc3-b0ed-350208d68fb3',
        'f1af6f09-7032-428d-a176-7bbfa6dba747',
        v_path,
        'test035-pending.pdf',
        'application/pdf',
        1024,
        'pending',
        clock_timestamp(),
        clock_timestamp() + interval '10 minutes'
    );

    INSERT INTO public.attachments (
        id, case_id, organisation_id, uploaded_by_user_id,
        file_name, file_type, file_size_bytes,
        storage_reference, visibility
    )
    VALUES (
        v_attachment_id,
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
        '0a316877-23d4-4dc3-b0ed-350208d68fb3',
        'f1af6f09-7032-428d-a176-7bbfa6dba747',
        'test035-pending.pdf',
        'application/pdf',
        1024,
        v_path,
        'internal'
    );

    PERFORM set_config(
        'madzera.test035.pending_attachment_id',
        v_attachment_id::text, true
    );

    RAISE NOTICE 'PASS: Synthetic pending fixture created';
END;
$test$;

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_message text;
BEGIN
    BEGIN
        PERFORM public.get_employee_case_evidence_download_path(
            current_setting('madzera.test035.pending_attachment_id')::uuid,
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            current_setting('madzera.test035.token_a')::uuid
        );
        RAISE EXCEPTION 'FAIL: Pending evidence accepted';
    EXCEPTION WHEN SQLSTATE '42501' THEN
        GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
        IF v_message <> 'Evidence attachment not found' THEN
            RAISE EXCEPTION 'FAIL: Unexpected pending rejection: %', v_message;
        END IF;
        RAISE NOTICE 'PASS: Pending evidence denied';
    END;
END;
$test$;

RESET ROLE;

-- Anonymous users must not execute the RPC.

SET LOCAL ROLE anon;

DO $test$
DECLARE
    v_message text;
BEGIN
    BEGIN
        PERFORM public.get_employee_case_evidence_download_path(
            current_setting('madzera.test035.attachment_id')::uuid,
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            current_setting('madzera.test035.token_a')::uuid
        );
        RAISE EXCEPTION 'FAIL: Anonymous RPC execution accepted';
    EXCEPTION WHEN SQLSTATE '42501' THEN
        GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
        IF v_message NOT LIKE
           'permission denied for function get_employee_case_evidence_download_path%' THEN
            RAISE EXCEPTION 'FAIL: Unexpected anonymous rejection: %', v_message;
        END IF;
        RAISE NOTICE 'PASS: Anonymous RPC execution denied';
    END;
END;
$test$;

RESET ROLE;

ROLLBACK;
