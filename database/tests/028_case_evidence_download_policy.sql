-- MADZERA TEST 028
-- Migrations 049 and 055: locked evidence download policy.
-- Requires local Employee A fixture and completed case evidence.
-- All database changes rolled back.

\set ON_ERROR_STOP on

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
    v_case_id uuid := 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';
    v_employee_id uuid := 'f1af6f09-7032-428d-a176-7bbfa6dba747';
    v_auth_id uuid := 'dc36ef25-8ff9-4845-857c-2a191ecc2b4a';
    v_path text;
BEGIN
    SELECT a.storage_reference INTO v_path
    FROM public.attachments a
    JOIN public.case_evidence_upload_reservations r
      ON r.storage_path = a.storage_reference
     AND r.case_id = a.case_id
     AND r.organisation_id = a.organisation_id
    WHERE a.case_id = v_case_id
      AND a.visibility = 'internal'
      AND r.status = 'completed'
    LIMIT 1;

    IF v_path IS NULL THEN
        RAISE EXCEPTION 'FAIL: Completed evidence fixture missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.case_locks
        WHERE case_id = v_case_id
          AND locked_by_user_id = v_employee_id
          AND expires_at <= clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'FAIL: Expected expired employee lock missing';
    END IF;

    PERFORM set_config('madzera.test.evidence_path', v_path, true);
    PERFORM set_config('request.jwt.claim.sub', v_auth_id::text, true);

    IF public.can_download_locked_case_evidence(v_path) THEN
        RAISE EXCEPTION 'FAIL: Expired lock permits evidence download';
    END IF;

    RAISE NOTICE 'PASS: Expired lock denies evidence download';
END;
$test$;

UPDATE public.case_locks
SET expires_at = clock_timestamp() + interval '5 minutes'
WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
  AND locked_by_user_id = 'f1af6f09-7032-428d-a176-7bbfa6dba747';

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_path text := current_setting('madzera.test.evidence_path');
BEGIN
    IF NOT public.can_download_locked_case_evidence(v_path) THEN
        RAISE EXCEPTION 'FAIL: Valid lock cannot authorise evidence';
    END IF;

    RAISE NOTICE 'PASS: Valid employee lock authorises evidence';
END;
$test$;

RESET ROLE;

SELECT set_config(
    'request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000099',
    true
);

SET LOCAL ROLE authenticated;

DO $test$
BEGIN
    IF public.can_download_locked_case_evidence(
        current_setting('madzera.test.evidence_path')
    ) THEN
        RAISE EXCEPTION 'FAIL: Unlinked identity authorised';
    END IF;

    RAISE NOTICE 'PASS: Unlinked identity denied';
END;
$test$;

RESET ROLE;

-- Verify the actual Storage SELECT policy under the authorised identity.
SELECT set_config(
    'request.jwt.claim.sub',
    'dc36ef25-8ff9-4845-857c-2a191ecc2b4a',
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_path text := current_setting('madzera.test.evidence_path');
    v_count integer;
    v_operation text;
BEGIN
    FOREACH v_operation IN ARRAY ARRAY[
        'object.get_authenticated',
        'object.get_authenticated_info',
        'object.list',
        'object.delete'
    ]
    LOOP
        PERFORM set_config('storage.operation', v_operation, true);

        -- Dynamic SQL forces a fresh statement for each operation.
        EXECUTE
            'SELECT count(*) FROM storage.objects ' ||
            'WHERE bucket_id = $1 AND name = $2'
        INTO v_count
        USING 'case-evidence', v_path;

        IF v_operation IN (
            'object.get_authenticated',
            'object.get_authenticated_info'
        ) THEN
            IF v_count <> 1 THEN
                RAISE EXCEPTION
                    'FAIL: Operation % expected one visible object, got %',
                    v_operation, v_count;
            END IF;
        ELSE
            IF v_count <> 0 THEN
                RAISE EXCEPTION
                    'FAIL: Prohibited operation % exposed % objects',
                    v_operation, v_count;
            END IF;
        END IF;

        RAISE NOTICE 'PASS: Storage operation % returned % objects',
            v_operation, v_count;
    END LOOP;
END;
$test$;

RESET ROLE;

ROLLBACK;
