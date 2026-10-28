\set ON_ERROR_STOP on

-- MADZERA TEST 033
-- Evidence recovery employee and organisation isolation.
-- All fixtures and lock changes are transaction-scoped.

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
    v_case_a uuid := 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';
    v_case_b uuid := 'a1d410f6-0521-4d25-a1f1-9e0023423a14';
    v_org_a uuid := '0a316877-23d4-4dc3-b0ed-350208d68fb3';
    v_org_b uuid := 'cbd6a8ae-adf3-4099-9352-1862e1751dea';
    v_employee_a uuid := 'f1af6f09-7032-428d-a176-7bbfa6dba747';
    v_employee_b uuid := 'ba0a74da-c3e5-4346-a337-0f536115bb7c';
    v_employee_c uuid := 'e5bce736-bcce-4a04-b720-a7b90837e371';
    v_reservation_a uuid := gen_random_uuid();
    v_reservation_b uuid := gen_random_uuid();
    v_reservation_c uuid := gen_random_uuid();
    v_token_a uuid := gen_random_uuid();
    v_token_b uuid := gen_random_uuid();
    v_token_c uuid := gen_random_uuid();
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.case_locks
        WHERE case_id = v_case_a
          AND organisation_id = v_org_a
          AND locked_by_user_id = v_employee_a
          AND expires_at <= clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'FAIL: Original Organisation A lock fixture missing';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.case_locks WHERE case_id = v_case_b
    ) THEN
        RAISE EXCEPTION 'FAIL: Organisation B case unexpectedly has a lock';
    END IF;

    PERFORM set_config('madzera.test033.reservation_a', v_reservation_a::text, true);
    PERFORM set_config('madzera.test033.reservation_b', v_reservation_b::text, true);
    PERFORM set_config('madzera.test033.reservation_c', v_reservation_c::text, true);
    PERFORM set_config('madzera.test033.token_a', v_token_a::text, true);
    PERFORM set_config('madzera.test033.token_b', v_token_b::text, true);
    PERFORM set_config('madzera.test033.token_c', v_token_c::text, true);

    INSERT INTO public.case_evidence_upload_reservations (
        id, case_id, organisation_id, employee_id,
        storage_path, file_name, file_type, file_size_bytes,
        status, created_at, expires_at
    )
    VALUES
    (
        v_reservation_a, v_case_a, v_org_a, v_employee_a,
        'test033/' || v_reservation_a::text,
        'test033-employee-a.pdf', 'application/pdf', 1024,
        'pending', clock_timestamp(), clock_timestamp() + interval '10 minutes'
    ),
    (
        v_reservation_b, v_case_a, v_org_a, v_employee_b,
        'test033/' || v_reservation_b::text,
        'test033-employee-b.pdf', 'application/pdf', 1024,
        'pending', clock_timestamp(), clock_timestamp() + interval '10 minutes'
    ),
    (
        v_reservation_c, v_case_b, v_org_b, v_employee_c,
        'test033/' || v_reservation_c::text,
        'test033-employee-c.pdf', 'application/pdf', 1024,
        'pending', clock_timestamp(), clock_timestamp() + interval '10 minutes'
    );

    UPDATE public.case_locks
    SET locked_by_user_id = v_employee_a,
        locked_at = clock_timestamp(),
        expires_at = clock_timestamp() + interval '5 minutes',
        lock_token = v_token_a
    WHERE case_id = v_case_a;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'FAIL: Organisation A lock update failed';
    END IF;

    INSERT INTO public.case_locks (
        case_id, organisation_id, locked_by_user_id,
        locked_at, expires_at, lock_token
    )
    VALUES (
        v_case_b, v_org_b, v_employee_c,
        clock_timestamp(), clock_timestamp() + interval '5 minutes',
        v_token_c
    );

    RAISE NOTICE 'PASS: Isolation fixtures and valid locks created';
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
    v_status text;
    v_count integer;
BEGIN
    SELECT reservation_status INTO v_status
    FROM public.get_case_evidence_upload_recovery_status(
        current_setting('madzera.test033.reservation_a')::uuid,
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
        current_setting('madzera.test033.token_a')::uuid
    );

    IF v_status IS DISTINCT FROM 'pending' THEN
        RAISE EXCEPTION 'FAIL: Employee A cannot recover own reservation';
    END IF;

    RAISE NOTICE 'PASS: Employee A can recover own reservation';

    SELECT count(*) INTO v_count
    FROM public.list_employee_case_evidence_upload_reservations(
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
        current_setting('madzera.test033.token_a')::uuid
    )
    WHERE reservation_id = current_setting('madzera.test033.reservation_a')::uuid;

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'FAIL: Employee A cannot list own reservation';
    END IF;

    RAISE NOTICE 'PASS: Employee A can list own reservation';
END;
$test$;

RESET ROLE;

-- Transfer the same case lock to Employee B, within the transaction.
UPDATE public.case_locks
SET locked_by_user_id = 'ba0a74da-c3e5-4346-a337-0f536115bb7c',
    locked_at = clock_timestamp(),
    expires_at = clock_timestamp() + interval '5 minutes',
    lock_token = current_setting('madzera.test033.token_b')::uuid
WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';

SELECT set_config(
    'request.jwt.claim.sub',
    'cd9c949c-8c81-42db-88a2-e08091866ed0',
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_case uuid := 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';
    v_token uuid := current_setting('madzera.test033.token_b')::uuid;
    v_count integer;
    v_status text;
BEGIN
    -- Positive control: Employee B really has a valid case lock.
    SELECT reservation_status INTO v_status
    FROM public.get_case_evidence_upload_recovery_status(
        current_setting('madzera.test033.reservation_b')::uuid,
        v_case, v_token
    );

    IF v_status IS DISTINCT FROM 'pending' THEN
        RAISE EXCEPTION 'FAIL: Employee B valid-lock control failed';
    END IF;

    RAISE NOTICE 'PASS: Employee B valid-lock control verified';

    BEGIN
        PERFORM public.get_case_evidence_upload_recovery_status(
            current_setting('madzera.test033.reservation_a')::uuid,
            v_case, v_token
        );

        RAISE EXCEPTION 'FAIL: Employee B accessed Employee A reservation';
    EXCEPTION WHEN insufficient_privilege THEN
        IF SQLERRM <> 'Evidence reservation not found' THEN RAISE; END IF;
        RAISE NOTICE 'PASS: Cross-employee recovery denied despite valid lock';
    END;

    SELECT count(*) INTO v_count
    FROM public.list_employee_case_evidence_upload_reservations(
        v_case, v_token
    )
    WHERE reservation_id = current_setting('madzera.test033.reservation_a')::uuid;

    IF v_count <> 0 THEN
        RAISE EXCEPTION 'FAIL: Employee A reservation leaked to Employee B';
    END IF;

    RAISE NOTICE 'PASS: Cross-employee listing isolation verified';
END;
$test$;

RESET ROLE;

SELECT set_config(
    'request.jwt.claim.sub',
    '33e98afb-f3fd-44ad-89b1-4bb88b20e37d',
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_case_a uuid := 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea';
    v_case_b uuid := 'a1d410f6-0521-4d25-a1f1-9e0023423a14';
    v_token uuid := current_setting('madzera.test033.token_c')::uuid;
    v_status text;
    v_count integer;
BEGIN
    -- Positive control: Organisation B's employee has their own valid lock.
    SELECT reservation_status INTO v_status
    FROM public.get_case_evidence_upload_recovery_status(
        current_setting('madzera.test033.reservation_c')::uuid,
        v_case_b, v_token
    );

    IF v_status IS DISTINCT FROM 'pending' THEN
        RAISE EXCEPTION 'FAIL: Organisation B positive control failed';
    END IF;

    RAISE NOTICE 'PASS: Organisation B valid-lock control verified';

    BEGIN
        PERFORM public.get_case_evidence_upload_recovery_status(
            current_setting('madzera.test033.reservation_a')::uuid,
            v_case_a, v_token
        );

        RAISE EXCEPTION 'FAIL: Organisation B accessed Organisation A case';
    EXCEPTION WHEN insufficient_privilege THEN
        IF SQLERRM <> 'Case access denied or lock expired' THEN RAISE; END IF;
        RAISE NOTICE 'PASS: Cross-organisation recovery denied';
    END;

    BEGIN
        PERFORM public.list_employee_case_evidence_upload_reservations(
            v_case_a, v_token
        );

        RAISE EXCEPTION 'FAIL: Organisation B listed Organisation A case';
    EXCEPTION WHEN insufficient_privilege THEN
        IF SQLERRM <> 'Case access denied or lock expired' THEN RAISE; END IF;
        RAISE NOTICE 'PASS: Cross-organisation listing denied';
    END;

    SELECT count(*) INTO v_count
    FROM public.list_employee_case_evidence_upload_reservations(
        v_case_b, v_token
    )
    WHERE reservation_id = current_setting('madzera.test033.reservation_a')::uuid;

    IF v_count <> 0 THEN
        RAISE EXCEPTION 'FAIL: Organisation A reservation leaked into Organisation B listing';
    END IF;

    RAISE NOTICE 'PASS: Organisation B listing excludes Organisation A reservation';
END;
$test$;

RESET ROLE;

ROLLBACK;
