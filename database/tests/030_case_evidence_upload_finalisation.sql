-- MADZERA TEST 030
-- Case evidence upload finalisation security.
-- Synthetic fixtures and all database changes are rolled back.

\set ON_ERROR_STOP on

BEGIN;

-- Temporarily restore the existing employee's expired lock.
-- The original expiry is restored automatically by ROLLBACK.
UPDATE public.case_locks
SET expires_at = clock_timestamp() + interval '5 minutes'
WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
  AND locked_by_user_id = 'f1af6f09-7032-428d-a176-7bbfa6dba747'
  AND expires_at <= clock_timestamp();

DO $test$
DECLARE
    v_lock_token uuid;
    v_reservation_id uuid;
    v_storage_path text;
BEGIN
    SELECT lock_token
    INTO v_lock_token
    FROM public.case_locks
    WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
      AND locked_by_user_id = 'f1af6f09-7032-428d-a176-7bbfa6dba747'
      AND expires_at > clock_timestamp();

    IF v_lock_token IS NULL THEN
        RAISE EXCEPTION 'FAIL: Valid case-lock fixture missing';
    END IF;

    v_reservation_id := gen_random_uuid();

    v_storage_path :=
        '0a316877-23d4-4dc3-b0ed-350208d68fb3/' ||
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea/' ||
        v_reservation_id::text;

    INSERT INTO public.case_evidence_upload_reservations (
        id,
        case_id,
        organisation_id,
        employee_id,
        storage_path,
        file_name,
        file_type,
        file_size_bytes,
        expires_at
    )
    VALUES (
        v_reservation_id,
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
        '0a316877-23d4-4dc3-b0ed-350208d68fb3',
        'f1af6f09-7032-428d-a176-7bbfa6dba747',
        v_storage_path,
        'test-finalisation.pdf',
        'application/pdf',
        1024,
        clock_timestamp() + interval '5 minutes'
    );

    INSERT INTO storage.objects (
        bucket_id,
        name,
        metadata
    )
    VALUES (
        'case-evidence',
        v_storage_path,
        jsonb_build_object(
            'size', 1024,
            'mimetype', 'application/pdf'
        )
    );

    PERFORM set_config(
        'test.finalisation_reservation_id',
        v_reservation_id::text,
        true
    );

    PERFORM set_config(
        'test.finalisation_lock_token',
        v_lock_token::text,
        true
    );

    -- Separate reservation deliberately has no Storage object.
    -- This tests finalisation before the file reaches Storage.
    DECLARE
        v_missing_reservation_id uuid := gen_random_uuid();
    BEGIN
        INSERT INTO public.case_evidence_upload_reservations (
            id,
            case_id,
            organisation_id,
            employee_id,
            storage_path,
            file_name,
            file_type,
            file_size_bytes,
            expires_at
        )
        VALUES (
            v_missing_reservation_id,
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            '0a316877-23d4-4dc3-b0ed-350208d68fb3',
            'f1af6f09-7032-428d-a176-7bbfa6dba747',
            '0a316877-23d4-4dc3-b0ed-350208d68fb3/' ||
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea/' ||
            v_missing_reservation_id::text,
            'test-missing-storage.pdf',
            'application/pdf',
            1024,
            clock_timestamp() + interval '5 minutes'
        );

        PERFORM set_config(
            'test.finalisation_missing_reservation_id',
            v_missing_reservation_id::text,
            true
        );
    END;

    -- Separate fixture: Storage metadata differs from reservation.
    DECLARE
        v_mismatch_id uuid := gen_random_uuid();
        v_mismatch_path text;
    BEGIN
        v_mismatch_path :=
            '0a316877-23d4-4dc3-b0ed-350208d68fb3/' ||
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea/' ||
            v_mismatch_id::text;

        INSERT INTO public.case_evidence_upload_reservations (
            id, case_id, organisation_id, employee_id,
            storage_path, file_name, file_type,
            file_size_bytes, expires_at
        )
        VALUES (
            v_mismatch_id,
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            '0a316877-23d4-4dc3-b0ed-350208d68fb3',
            'f1af6f09-7032-428d-a176-7bbfa6dba747',
            v_mismatch_path,
            'test-mismatched-metadata.pdf',
            'application/pdf',
            1024,
            clock_timestamp() + interval '5 minutes'
        );

        INSERT INTO storage.objects (
            bucket_id, name, metadata
        )
        VALUES (
            'case-evidence',
            v_mismatch_path,
            jsonb_build_object(
                'size', 2048,
                'mimetype', 'application/pdf'
            )
        );

        PERFORM set_config(
            'test.finalisation_mismatch_reservation_id',
            v_mismatch_id::text,
            true
        );
    END;

    -- Separate expired reservation with matching Storage metadata.
    DECLARE
        v_expired_id uuid := gen_random_uuid();
        v_expired_path text;
    BEGIN
        v_expired_path :=
            '0a316877-23d4-4dc3-b0ed-350208d68fb3/' ||
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea/' ||
            v_expired_id::text;

        INSERT INTO public.case_evidence_upload_reservations (
            id, case_id, organisation_id, employee_id,
            storage_path, file_name, file_type,
            file_size_bytes, created_at, expires_at
        )
        VALUES (
            v_expired_id,
            'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
            '0a316877-23d4-4dc3-b0ed-350208d68fb3',
            'f1af6f09-7032-428d-a176-7bbfa6dba747',
            v_expired_path,
            'test-expired-finalisation.pdf',
            'application/pdf',
            1024,
            clock_timestamp() - interval '12 minutes',
            clock_timestamp() - interval '2 minutes'
        );

        INSERT INTO storage.objects (
            bucket_id, name, metadata
        )
        VALUES (
            'case-evidence',
            v_expired_path,
            jsonb_build_object(
                'size', 1024,
                'mimetype', 'application/pdf'
            )
        );

        PERFORM set_config(
            'test.finalisation_expired_reservation_id',
            v_expired_id::text,
            true
        );
    END;

    RAISE NOTICE 'PASS: Synthetic finalisation fixtures created';
END;
$test$;

SELECT set_config(
    'request.jwt.claim.sub',
    'dc36ef25-8ff9-4845-857c-2a191ecc2b4a',
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_attachment_id uuid;
    v_reservation_id uuid;
    v_lock_token uuid;
BEGIN
    v_reservation_id :=
        current_setting('test.finalisation_reservation_id')::uuid;

    v_lock_token :=
        current_setting('test.finalisation_lock_token')::uuid;

    -- A nonexistent reservation must not be finalised.
    BEGIN
        PERFORM public.finalise_case_evidence_upload(
            gen_random_uuid(),
            v_lock_token,
            NULL
        );

        RAISE EXCEPTION 'FAIL: Nonexistent reservation accepted';
    EXCEPTION
        WHEN insufficient_privilege THEN
            IF SQLERRM <> 'Upload reservation invalid or expired' THEN
                RAISE EXCEPTION
                    'FAIL: Unexpected reservation rejection: %', SQLERRM;
            END IF;

            RAISE NOTICE 'PASS: Nonexistent reservation denied';
    END;

    -- The valid reservation must reject an incorrect lock token.
    BEGIN
        PERFORM public.finalise_case_evidence_upload(
            v_reservation_id,
            gen_random_uuid(),
            NULL
        );

        RAISE EXCEPTION 'FAIL: Incorrect lock token accepted';
    EXCEPTION
        WHEN insufficient_privilege THEN
            IF SQLERRM <> 'Valid exclusive case lock required' THEN
                RAISE EXCEPTION
                    'FAIL: Unexpected lock-token rejection: %', SQLERRM;
            END IF;

            RAISE NOTICE 'PASS: Incorrect lock token denied';
    END;

    -- A valid reservation without a Storage object must be rejected.
    BEGIN
        PERFORM public.finalise_case_evidence_upload(
            current_setting(
                'test.finalisation_missing_reservation_id'
            )::uuid,
            v_lock_token,
            NULL
        );

        RAISE EXCEPTION 'FAIL: Missing Storage object accepted';
    EXCEPTION
        WHEN invalid_parameter_value THEN
            IF SQLERRM <> 'Uploaded evidence object not found' THEN
                RAISE EXCEPTION
                    'FAIL: Unexpected missing-Storage rejection: %',
                    SQLERRM;
            END IF;

            RAISE NOTICE 'PASS: Missing Storage object denied';
    END;

    -- Reject Storage metadata that does not match the reservation.
    BEGIN
        PERFORM public.finalise_case_evidence_upload(
            current_setting(
                'test.finalisation_mismatch_reservation_id'
            )::uuid,
            v_lock_token,
            NULL
        );

        RAISE EXCEPTION 'FAIL: Mismatched Storage metadata accepted';
    EXCEPTION
        WHEN invalid_parameter_value THEN
            IF SQLERRM <>
                'Uploaded evidence metadata does not match reservation'
            THEN
                RAISE EXCEPTION
                    'FAIL: Unexpected metadata mismatch rejection: %',
                    SQLERRM;
            END IF;

            RAISE NOTICE 'PASS: Mismatched Storage metadata denied';
    END;

    -- An expired reservation must not permit evidence finalisation.
    BEGIN
        PERFORM public.finalise_case_evidence_upload(
            current_setting(
                'test.finalisation_expired_reservation_id'
            )::uuid,
            v_lock_token,
            NULL
        );

        RAISE EXCEPTION 'FAIL: Expired reservation accepted';
    EXCEPTION
        WHEN insufficient_privilege THEN
            IF SQLERRM <> 'Upload reservation invalid or expired'
            THEN
                RAISE EXCEPTION
                    'FAIL: Unexpected expired reservation rejection: %',
                    SQLERRM;
            END IF;

            RAISE NOTICE 'PASS: Expired reservation denied';
    END;

    -- Evidence must not link to an activity outside the valid case scope.
    BEGIN
        PERFORM public.finalise_case_evidence_upload(
            v_reservation_id,
            v_lock_token,
            '00000000-0000-0000-0000-000000000000'::uuid
        );

        RAISE EXCEPTION 'FAIL: Invalid activity association accepted';
    EXCEPTION
        WHEN insufficient_privilege THEN
            IF SQLERRM <> 'Activity not found in this case'
            THEN
                RAISE EXCEPTION
                    'FAIL: Unexpected invalid activity rejection: %',
                    SQLERRM;
            END IF;

            RAISE NOTICE 'PASS: Invalid activity association denied';
    END;

    v_attachment_id :=
        public.finalise_case_evidence_upload(
            v_reservation_id,
            v_lock_token,
            '67a0126a-642f-4065-9201-8996b5edf775'
        );

    IF v_attachment_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: Finalisation returned no attachment ID';
    END IF;

    PERFORM set_config(
        'test.finalisation_attachment_id',
        v_attachment_id::text,
        true
    );

    RAISE NOTICE 'PASS: Authenticated employee finalised evidence';

    -- A completed reservation must not create another attachment.
    BEGIN
        PERFORM public.finalise_case_evidence_upload(
            v_reservation_id,
            v_lock_token,
            '67a0126a-642f-4065-9201-8996b5edf775'
        );

        RAISE EXCEPTION 'FAIL: Completed reservation finalised twice';
    EXCEPTION
        WHEN insufficient_privilege THEN
            IF SQLERRM <> 'Upload reservation invalid or expired'
            THEN
                RAISE EXCEPTION
                    'FAIL: Unexpected repeated-finalisation rejection: %',
                    SQLERRM;
            END IF;

            RAISE NOTICE 'PASS: Repeated finalisation denied';
    END;
END;
$test$;

RESET ROLE;

DO $test$
DECLARE
    v_attachment_id uuid;
    v_reservation_id uuid;
BEGIN
    v_attachment_id :=
        current_setting('test.finalisation_attachment_id')::uuid;

    v_reservation_id :=
        current_setting('test.finalisation_reservation_id')::uuid;

    IF NOT EXISTS (
        SELECT 1
        FROM public.attachments
        WHERE id = v_attachment_id
          AND case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
          AND organisation_id = '0a316877-23d4-4dc3-b0ed-350208d68fb3'
          AND uploaded_by_user_id = 'f1af6f09-7032-428d-a176-7bbfa6dba747'
          AND comment_id = '67a0126a-642f-4065-9201-8996b5edf775'
          AND visibility = 'internal'
          AND file_name = 'test-finalisation.pdf'
          AND file_type = 'application/pdf'
          AND file_size_bytes = 1024
    ) THEN
        RAISE EXCEPTION 'FAIL: Finalised attachment metadata incorrect';
    END IF;

    RAISE NOTICE 'PASS: Attachment metadata and activity link verified';

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_evidence_upload_reservations
        WHERE id = v_reservation_id
          AND status = 'completed'
          AND completed_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'FAIL: Reservation was not completed';
    END IF;

    RAISE NOTICE 'PASS: Reservation marked completed';

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_events
        WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
          AND organisation_id = '0a316877-23d4-4dc3-b0ed-350208d68fb3'
          AND actor_user_id = 'f1af6f09-7032-428d-a176-7bbfa6dba747'
          AND event_type = 'evidence_uploaded'
          AND details = 'Attachment ID: ' || v_attachment_id::text
    ) THEN
        RAISE EXCEPTION 'FAIL: Evidence audit event missing';
    END IF;

    RAISE NOTICE 'PASS: Evidence audit event verified';

    -- Repeated finalisation must not create duplicate attachments.
    IF (
        SELECT count(*)
        FROM public.attachments
        WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
          AND organisation_id = '0a316877-23d4-4dc3-b0ed-350208d68fb3'
          AND storage_reference = (
              SELECT storage_path
              FROM public.case_evidence_upload_reservations
              WHERE id = v_reservation_id
          )
    ) <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Expected exactly one attachment for reservation';
    END IF;

    RAISE NOTICE 'PASS: No duplicate attachment created';

    -- Exactly one audit event must reference the new attachment.
    IF (
        SELECT count(*)
        FROM public.case_events
        WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
          AND organisation_id = '0a316877-23d4-4dc3-b0ed-350208d68fb3'
          AND event_type = 'evidence_uploaded'
          AND details = 'Attachment ID: ' || v_attachment_id::text
    ) <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Expected exactly one evidence audit event';
    END IF;

    RAISE NOTICE 'PASS: No duplicate evidence audit event created';
END;
$test$;

ROLLBACK;
