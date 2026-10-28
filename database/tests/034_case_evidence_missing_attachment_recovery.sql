\set ON_ERROR_STOP on

-- MADZERA TEST 034
-- Completed evidence reservation missing attachment.
-- Transaction-scoped fixtures; no persistent database changes.

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
    v_org_id uuid := '0a316877-23d4-4dc3-b0ed-350208d68fb3';
    v_employee_id uuid := 'f1af6f09-7032-428d-a176-7bbfa6dba747';
    v_reservation_id uuid := gen_random_uuid();
    v_attachment_id uuid := gen_random_uuid();
    v_storage_path text;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks
        WHERE case_id = v_case_id
          AND organisation_id = v_org_id
          AND locked_by_user_id = v_employee_id
          AND lock_token IS NOT NULL
          AND expires_at <= clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'FAIL: Expected expired case lock fixture missing';
    END IF;

    PERFORM set_config(
        'madzera.test034.lock_token',
        (
            SELECT lock_token::text
            FROM public.case_locks
            WHERE case_id = v_case_id
              AND organisation_id = v_org_id
              AND locked_by_user_id = v_employee_id
        ),
        true
    );

    v_storage_path := v_org_id::text || '/' ||
                      v_case_id::text || '/' ||
                      v_reservation_id::text;

    PERFORM set_config(
        'madzera.test034.reservation_id',
        v_reservation_id::text,
        true
    );

    PERFORM set_config(
        'madzera.test034.attachment_id',
        v_attachment_id::text,
        true
    );

    PERFORM set_config(
        'madzera.test034.storage_path',
        v_storage_path,
        true
    );

    INSERT INTO public.case_evidence_upload_reservations (
        id,
        case_id,
        organisation_id,
        employee_id,
        storage_path,
        file_name,
        file_type,
        file_size_bytes,
        status,
        created_at,
        expires_at,
        completed_at
    )
    VALUES (
        v_reservation_id,
        v_case_id,
        v_org_id,
        v_employee_id,
        v_storage_path,
        'test034-missing-attachment.pdf',
        'application/pdf',
        1024,
        'completed',
        clock_timestamp() - interval '2 minutes',
        clock_timestamp() + interval '8 minutes',
        clock_timestamp() - interval '1 minute'
    );

    IF EXISTS (
        SELECT 1
        FROM public.attachments
        WHERE storage_reference = v_storage_path
    ) THEN
        RAISE EXCEPTION 'FAIL: Synthetic attachment unexpectedly exists';
    END IF;

    RAISE NOTICE 'PASS: Completed reservation created without attachment';
END;
$test$;

-- Extend the existing lock only inside this transaction.

UPDATE public.case_locks
SET expires_at = clock_timestamp() + interval '5 minutes'
WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
  AND organisation_id = '0a316877-23d4-4dc3-b0ed-350208d68fb3'
  AND locked_by_user_id = 'f1af6f09-7032-428d-a176-7bbfa6dba747';

DO $test$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks
        WHERE case_id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
          AND locked_by_user_id =
              'f1af6f09-7032-428d-a176-7bbfa6dba747'
          AND expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'FAIL: Test lock was not extended';
    END IF;

    RAISE NOTICE 'PASS: Valid case lock established';
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
    v_reservation_id uuid :=
        current_setting('madzera.test034.reservation_id')::uuid;
    v_token uuid;
    v_count integer;
BEGIN
    v_token :=
        current_setting('madzera.test034.lock_token')::uuid;

    IF v_token IS NULL THEN
        RAISE EXCEPTION 'FAIL: Missing test lock token';
    END IF;

    BEGIN
        PERFORM public.get_case_evidence_upload_recovery_status(
            v_reservation_id,
            v_case_id,
            v_token
        );

        RAISE EXCEPTION
            'FAIL: Missing attachment was incorrectly accepted';

    EXCEPTION WHEN SQLSTATE '22023' THEN
        IF SQLERRM <> 'Completed reservation missing attachment' THEN
            RAISE;
        END IF;

        RAISE NOTICE
            'PASS: Missing attachment rejected with SQLSTATE 22023';
    END;

    SELECT count(*)
    INTO v_count
    FROM public.list_employee_case_evidence_upload_reservations(
        v_case_id,
        v_token
    )
    WHERE reservation_id = v_reservation_id
      AND reservation_status = 'completed';

    IF v_count <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Completed reservation not visible in own listing';
    END IF;

    RAISE NOTICE
        'PASS: Own listing reports completed reservation';
END;
$test$;

RESET ROLE;

-- Create the matching attachment as a positive control.

INSERT INTO public.attachments (
    id,
    case_id,
    organisation_id,
    uploaded_by_user_id,
    file_name,
    file_type,
    file_size_bytes,
    storage_reference,
    visibility
)
VALUES (
    current_setting('madzera.test034.attachment_id')::uuid,
    'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
    '0a316877-23d4-4dc3-b0ed-350208d68fb3',
    'f1af6f09-7032-428d-a176-7bbfa6dba747',
    'test034-missing-attachment.pdf',
    'application/pdf',
    1024,
    current_setting('madzera.test034.storage_path'),
    'internal'
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_status text;
    v_attachment_id uuid;
    v_token uuid;
BEGIN
    v_token :=
        current_setting('madzera.test034.lock_token')::uuid;

    SELECT reservation_status, attachment_id
    INTO v_status, v_attachment_id
    FROM public.get_case_evidence_upload_recovery_status(
        current_setting('madzera.test034.reservation_id')::uuid,
        'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
        v_token
    );

    IF v_status IS DISTINCT FROM 'completed'
       OR v_attachment_id IS DISTINCT FROM
          current_setting('madzera.test034.attachment_id')::uuid
    THEN
        RAISE EXCEPTION
            'FAIL: Matching attachment recovery returned incorrect result';
    END IF;

    RAISE NOTICE
        'PASS: Matching attachment returns completed status and ID';
END;
$test$;

RESET ROLE;

ROLLBACK;
