\set ON_ERROR_STOP on

-- MADZERA TEST 032
-- Evidence upload recovery security.
-- Synthetic fixtures; all changes rolled back.

BEGIN;

-- TEST-ONLY TEAM WORK AUTHORISATION FIXTURE
-- Historical recovery cases predate team-based authorisation.
-- All team assignments, memberships and grants are rolled back.
DO $team_fixture$
DECLARE
    v_original_auth_sub text := current_setting('request.jwt.claim.sub', true);
    v_team_a uuid;
    v_team_b uuid;
    v_org_a uuid := '0a316877-23d4-4dc3-b0ed-350208d68fb3';
    v_org_b uuid := 'cbd6a8ae-adf3-4099-9352-1862e1751dea';
    v_case_a uuid := 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';
    v_case_b uuid := 'a1d410f6-0521-4d25-a1f1-9e0023423a14';
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.cases
        WHERE id IN (v_case_a, v_case_b)
          AND assigned_team_id IS NOT NULL
    ) THEN
        RAISE EXCEPTION
            'STOP: Historical recovery case already has a team';
    END IF;

    INSERT INTO public.teams (organisation_id, name)
    VALUES (v_org_a, 'TEST RECOVERY ORGANISATION A')
    RETURNING id INTO v_team_a;

    INSERT INTO public.teams (organisation_id, name)
    VALUES (v_org_b, 'TEST RECOVERY ORGANISATION B')
    RETURNING id INTO v_team_b;

    PERFORM set_config(
        'request.jwt.claim.sub',
        'dc36ef25-8ff9-4845-857c-2a191ecc2b4a',
        true
    );

    UPDATE public.cases
    SET assigned_team_id = v_team_a
    WHERE id = v_case_a
      AND organisation_id = v_org_a;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'STOP: Organisation A case missing';
    END IF;

    PERFORM set_config(
        'request.jwt.claim.sub',
        '33e98afb-f3fd-44ad-89b1-4bb88b20e37d',
        true
    );

    UPDATE public.cases
    SET assigned_team_id = v_team_b
    WHERE id = v_case_b
      AND organisation_id = v_org_b;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'STOP: Organisation B case missing';
    END IF;

    INSERT INTO public.team_members (
        organisation_id, team_id, user_id
    )
    VALUES
        (v_org_a, v_team_a, 'f1af6f09-7032-428d-a176-7bbfa6dba747'),
        (v_org_a, v_team_a, 'ba0a74da-c3e5-4346-a337-0f536115bb7c'),
        (v_org_b, v_team_b, 'e5bce736-bcce-4a04-b720-a7b90837e371');

    INSERT INTO public.team_permission_grants (
        organisation_id, team_id, user_id, permission_type
    )
    VALUES
        (v_org_a, v_team_a, 'f1af6f09-7032-428d-a176-7bbfa6dba747', 'work'),
        (v_org_a, v_team_a, 'ba0a74da-c3e5-4346-a337-0f536115bb7c', 'work'),
        (v_org_b, v_team_b, 'e5bce736-bcce-4a04-b720-a7b90837e371', 'work');

    PERFORM set_config(
        'request.jwt.claim.sub',
        COALESCE(v_original_auth_sub, ''),
        true
    );

    RAISE NOTICE
        'PASS: Transaction-scoped recovery team permissions provisioned';
END;
$team_fixture$;


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
    v_lock_token uuid;
    v_reservation_id uuid;
    v_attachment_id uuid := gen_random_uuid();
    v_kind text;
    v_status text;
    v_created timestamptz;
    v_expires timestamptz;
BEGIN
    SELECT lock_token INTO v_lock_token
    FROM public.case_locks
    WHERE case_id = v_case_id
      AND locked_by_user_id = v_employee_id
      AND expires_at <= clock_timestamp();

    IF v_lock_token IS NULL THEN
        RAISE EXCEPTION 'FAIL: Original expired-lock fixture missing';
    END IF;

    PERFORM set_config('madzera.test032.lock_token', v_lock_token::text, true);
    PERFORM set_config('madzera.test032.attachment_id', v_attachment_id::text, true);

    FOR v_kind IN SELECT unnest(ARRAY['pending','expired','completed'])
    LOOP
        v_reservation_id := gen_random_uuid();

        v_created := CASE
            WHEN v_kind = 'expired' THEN clock_timestamp() - interval '20 minutes'
            ELSE clock_timestamp()
        END;

        v_expires := CASE
            WHEN v_kind = 'expired' THEN clock_timestamp() - interval '10 minutes'
            ELSE clock_timestamp() + interval '10 minutes'
        END;

        v_status := CASE
            WHEN v_kind = 'completed' THEN 'completed'
            ELSE 'pending'
        END;

        INSERT INTO public.case_evidence_upload_reservations (
            id, case_id, organisation_id, employee_id,
            storage_path, file_name, file_type, file_size_bytes,
            status, created_at, expires_at, completed_at
        )
        VALUES (
            v_reservation_id,
            v_case_id,
            '0a316877-23d4-4dc3-b0ed-350208d68fb3',
            v_employee_id,
            '0a316877-23d4-4dc3-b0ed-350208d68fb3/' ||
                v_case_id::text || '/' || v_reservation_id::text,
            'test-recovery-' || v_kind || '.pdf',
            'application/pdf',
            1024,
            v_status,
            v_created,
            v_expires,
            CASE WHEN v_kind = 'completed' THEN clock_timestamp()
                 ELSE NULL END
        );

        PERFORM set_config(
            'madzera.test032.' || v_kind || '_id',
            v_reservation_id::text,
            true
        );

        IF v_kind = 'completed' THEN
            INSERT INTO public.attachments (
                id, case_id, organisation_id, uploaded_by_user_id,
                file_name, file_type, file_size_bytes,
                storage_reference, visibility
            )
            VALUES (
                v_attachment_id,
                v_case_id,
                '0a316877-23d4-4dc3-b0ed-350208d68fb3',
                v_employee_id,
                'test-recovery-completed.pdf',
                'application/pdf',
                1024,
                '0a316877-23d4-4dc3-b0ed-350208d68fb3/' ||
                    v_case_id::text || '/' || v_reservation_id::text,
                'internal'
            );
        END IF;
    END LOOP;

    RAISE NOTICE 'PASS: Recovery fixtures created';
END;
$test$;

UPDATE public.case_locks
SET expires_at = clock_timestamp() + interval '5 minutes'
WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
  AND locked_by_user_id = 'f1af6f09-7032-428d-a176-7bbfa6dba747';

-- Assert the lock was actually extended.
DO $test$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.case_locks
        WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
          AND expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'FAIL: Test lock was not extended';
    END IF;
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
    v_case_id uuid := 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';
    v_token uuid := current_setting('madzera.test032.lock_token')::uuid;
    v_kind text;
    v_status text;
    v_attachment uuid;
    v_expected_attachment uuid :=
        current_setting('madzera.test032.attachment_id')::uuid;
    v_count integer;
BEGIN
    FOR v_kind IN SELECT unnest(ARRAY['pending','expired','completed'])
    LOOP
        SELECT reservation_status, attachment_id
        INTO v_status, v_attachment
        FROM public.get_case_evidence_upload_recovery_status(
            current_setting('madzera.test032.' || v_kind || '_id')::uuid,
            v_case_id,
            v_token
        );

        IF v_status IS DISTINCT FROM v_kind
           OR (v_kind = 'completed'
               AND v_attachment IS DISTINCT FROM v_expected_attachment)
           OR (v_kind <> 'completed' AND v_attachment IS NOT NULL)
        THEN
            RAISE EXCEPTION 'FAIL: Incorrect % recovery result', v_kind;
        END IF;

        RAISE NOTICE 'PASS: % recovery status verified', v_kind;
    END LOOP;

    SELECT count(*) INTO v_count
    FROM public.list_employee_case_evidence_upload_reservations(
        v_case_id, v_token
    ) AS r
    WHERE (r.reservation_id =
               current_setting('madzera.test032.pending_id')::uuid
           AND r.reservation_status = 'pending')
       OR (r.reservation_id =
               current_setting('madzera.test032.expired_id')::uuid
           AND r.reservation_status = 'expired')
       OR (r.reservation_id =
               current_setting('madzera.test032.completed_id')::uuid
           AND r.reservation_status = 'completed');

    IF v_count <> 3 THEN
        RAISE EXCEPTION 'FAIL: Reservation listing statuses incorrect';
    END IF;

    RAISE NOTICE 'PASS: Own reservation listing and statuses verified';

    BEGIN
        PERFORM public.get_case_evidence_upload_recovery_status(
            current_setting('madzera.test032.pending_id')::uuid,
            v_case_id, gen_random_uuid()
        );
        RAISE EXCEPTION 'FAIL: Wrong token accepted by recovery status';
    EXCEPTION WHEN insufficient_privilege THEN
        IF SQLERRM <> 'Case access denied or lock expired' THEN RAISE; END IF;
        RAISE NOTICE 'PASS: Wrong token denied by recovery status';
    END;

    BEGIN
        PERFORM public.list_employee_case_evidence_upload_reservations(
            v_case_id, gen_random_uuid()
        );
        RAISE EXCEPTION 'FAIL: Wrong token accepted by listing';
    EXCEPTION WHEN insufficient_privilege THEN
        IF SQLERRM <> 'Case access denied or lock expired' THEN RAISE; END IF;
        RAISE NOTICE 'PASS: Wrong token denied by listing';
    END;
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
DECLARE
    v_case_id uuid := 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';
    v_token uuid := current_setting('madzera.test032.lock_token')::uuid;
BEGIN
    BEGIN
        PERFORM public.get_case_evidence_upload_recovery_status(
            current_setting('madzera.test032.pending_id')::uuid,
            v_case_id, v_token
        );
        RAISE EXCEPTION 'FAIL: Unlinked identity accessed recovery status';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: Unlinked identity denied recovery status';
    END;

    BEGIN
        PERFORM public.list_employee_case_evidence_upload_reservations(
            v_case_id, v_token
        );
        RAISE EXCEPTION 'FAIL: Unlinked identity accessed reservation listing';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: Unlinked identity denied reservation listing';
    END;
END;
$test$;

RESET ROLE;

UPDATE public.case_locks
SET expires_at = clock_timestamp() - interval '1 minute'
WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';

SELECT set_config(
    'request.jwt.claim.sub',
    'dc36ef25-8ff9-4845-857c-2a191ecc2b4a',
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_case_id uuid := 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';
    v_token uuid := current_setting('madzera.test032.lock_token')::uuid;
BEGIN
    BEGIN
        PERFORM public.get_case_evidence_upload_recovery_status(
            current_setting('madzera.test032.pending_id')::uuid,
            v_case_id, v_token
        );
        RAISE EXCEPTION 'FAIL: Expired lock allowed recovery status';
    EXCEPTION WHEN insufficient_privilege THEN
        IF SQLERRM <> 'Case access denied or lock expired' THEN RAISE; END IF;
        RAISE NOTICE 'PASS: Expired lock denied recovery status';
    END;

    BEGIN
        PERFORM public.list_employee_case_evidence_upload_reservations(
            v_case_id, v_token
        );
        RAISE EXCEPTION 'FAIL: Expired lock allowed reservation listing';
    EXCEPTION WHEN insufficient_privilege THEN
        IF SQLERRM <> 'Case access denied or lock expired' THEN RAISE; END IF;
        RAISE NOTICE 'PASS: Expired lock denied reservation listing';
    END;
END;
$test$;

RESET ROLE;

ROLLBACK;
