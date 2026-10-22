-- MADZERA TEST 031
-- Case evidence Storage INSERT policy and prohibited modifications.
-- All synthetic fixtures and database changes are rolled back.

\set ON_ERROR_STOP on

BEGIN;

DO $test$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks
        WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
          AND locked_by_user_id = 'f1af6f09-7032-428d-a176-7bbfa6dba747'
          AND expires_at <= clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'FAIL: Expected expired lock fixture missing';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.case_evidence_upload_reservations
        WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
          AND status = 'pending'
    ) THEN
        RAISE EXCEPTION 'FAIL: Unexpected pending reservation fixture';
    END IF;

    RAISE NOTICE 'PASS: Existing fixture prerequisites verified';
END;
$test$;

-- Create a synthetic pending reservation while the original lock is expired.
DO $test$
DECLARE
    v_id uuid := gen_random_uuid();
    v_path text;
BEGIN
    v_path :=
        '0a316877-23d4-4dc3-b0ed-350208d68fb3/' ||
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea/' ||
        v_id::text;

    INSERT INTO public.case_evidence_upload_reservations (
        id, case_id, organisation_id, employee_id,
        storage_path, file_name, file_type,
        file_size_bytes, expires_at
    )
    VALUES (
        v_id,
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
        '0a316877-23d4-4dc3-b0ed-350208d68fb3',
        'f1af6f09-7032-428d-a176-7bbfa6dba747',
        v_path,
        'test-storage-policy.pdf',
        'application/pdf',
        1024,
        clock_timestamp() + interval '5 minutes'
    );

    PERFORM set_config('madzera.test031.path', v_path, true);
    PERFORM set_config('madzera.test031.reservation_id', v_id::text, true);

    RAISE NOTICE 'PASS: Synthetic reservation created';
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
    v_path text := current_setting('madzera.test031.path');
BEGIN
    IF public.can_upload_reserved_case_evidence(v_path) THEN
        RAISE EXCEPTION 'FAIL: Expired lock permits upload';
    END IF;

    RAISE NOTICE 'PASS: Expired lock denies upload';
END;
$test$;

RESET ROLE;

-- Create a second bucket only within this rollback-protected transaction.
-- This avoids confusing a foreign-key failure with an RLS rejection.
INSERT INTO storage.buckets (id, name, public)
VALUES ('madzera-test031-other', 'madzera-test031-other', false);

-- Temporarily extend the existing lock, within this transaction only.
UPDATE public.case_locks
SET expires_at = clock_timestamp() + interval '5 minutes'
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
    v_path text := current_setting('madzera.test031.path');
    v_count integer;
BEGIN
    IF NOT public.can_upload_reserved_case_evidence(v_path) THEN
        RAISE EXCEPTION 'FAIL: Valid reservation and lock not authorised';
    END IF;

    RAISE NOTICE 'PASS: Valid reservation and lock authorised';

    -- Actual INSERT under authenticated role: Storage RLS WITH CHECK.
    INSERT INTO storage.objects (bucket_id, name, metadata)
    VALUES (
        'case-evidence',
        v_path,
        jsonb_build_object(
            'size', 1024,
            'mimetype', 'application/pdf'
        )
    );

    RAISE NOTICE 'PASS: Authenticated reserved Storage INSERT succeeded';

    -- An unreserved path must be rejected by actual INSERT RLS.
    BEGIN
        INSERT INTO storage.objects (bucket_id, name, metadata)
        VALUES (
            'case-evidence',
            v_path || '-unreserved',
            '{"size":1024,"mimetype":"application/pdf"}'::jsonb
        );

        RAISE EXCEPTION 'FAIL: Unreserved Storage path accepted';
    EXCEPTION
        WHEN insufficient_privilege THEN
            RAISE NOTICE 'PASS: Unreserved Storage path rejected';
    END;

    -- A reserved path must not be usable in another bucket.
    -- The temporary bucket is created earlier under the privileged role.
    BEGIN
        INSERT INTO storage.objects (bucket_id, name, metadata)
        VALUES (
            'madzera-test031-other',
            v_path,
            '{"size":1024,"mimetype":"application/pdf"}'::jsonb
        );

        RAISE EXCEPTION 'FAIL: Wrong Storage bucket accepted';
    EXCEPTION
        WHEN insufficient_privilege THEN
            RAISE NOTICE 'PASS: Wrong Storage bucket rejected';
    END;

    -- No UPDATE policy should permit modifying the inserted object.
    UPDATE storage.objects
    SET metadata = '{"size":2048,"mimetype":"application/pdf"}'::jsonb
    WHERE bucket_id = 'case-evidence'
      AND name = v_path;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    IF v_count <> 0 THEN
        RAISE EXCEPTION 'FAIL: Authenticated Storage UPDATE succeeded';
    END IF;

    RAISE NOTICE 'PASS: Authenticated Storage UPDATE denied';

    -- Direct deletion may be blocked by Storage's protection trigger
    -- before RLS can determine whether a row is deletable.
    BEGIN
        DELETE FROM storage.objects
        WHERE bucket_id = 'case-evidence'
          AND name = v_path;

        GET DIAGNOSTICS v_count = ROW_COUNT;

        IF v_count <> 0 THEN
            RAISE EXCEPTION 'FAIL: Authenticated Storage DELETE succeeded';
        END IF;

        RAISE NOTICE 'PASS: Authenticated Storage DELETE affected zero rows';
    EXCEPTION
        WHEN insufficient_privilege THEN
            IF SQLERRM <> 'Direct deletion from storage tables is not allowed. Use the Storage API instead.' THEN
                RAISE;
            END IF;

            RAISE NOTICE 'PASS: Storage protection trigger rejected direct DELETE';
    END;
END;
$test$;

RESET ROLE;

-- An unrelated authenticated identity must not upload.
SELECT set_config(
    'request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000099',
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_path text := current_setting('madzera.test031.path');
BEGIN
    IF public.can_upload_reserved_case_evidence(v_path) THEN
        RAISE EXCEPTION 'FAIL: Unlinked identity authorised';
    END IF;

    RAISE NOTICE 'PASS: Unlinked identity denied';
END;
$test$;

RESET ROLE;

-- Expire the synthetic reservation.
UPDATE public.case_evidence_upload_reservations
SET created_at = clock_timestamp() - interval '12 minutes',
    expires_at = clock_timestamp() - interval '2 minutes'
WHERE id = current_setting('madzera.test031.reservation_id')::uuid;

SELECT set_config(
    'request.jwt.claim.sub',
    'dc36ef25-8ff9-4845-857c-2a191ecc2b4a',
    true
);

SET LOCAL ROLE authenticated;

DO $test$
BEGIN
    IF public.can_upload_reserved_case_evidence(
        current_setting('madzera.test031.path')
    ) THEN
        RAISE EXCEPTION 'FAIL: Expired reservation authorised';
    END IF;

    RAISE NOTICE 'PASS: Expired reservation denied';
END;
$test$;

RESET ROLE;

ROLLBACK;
