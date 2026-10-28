-- MADZERA TEST 059
-- Evidence Reservation Listing: Immediate Team-Work Revocation
--
-- Requires Test 044's fixture setup and Migration 067.
-- Execute within an outer rollback-only transaction.
-- Insert before Test 044's original authorisation assertions.
-- Never execute independently against production.

\echo '=== TEST059: CREATE VALID LOCK AND RESERVATION ==='

CREATE TEMP TABLE test059_fixture (
    lock_token uuid NOT NULL,
    reservation_id uuid NOT NULL
) ON COMMIT DROP;

GRANT SELECT ON test059_fixture TO authenticated;

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
    v_token uuid := gen_random_uuid();
    v_reservation uuid := gen_random_uuid();
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;

    IF EXISTS (
        SELECT 1
        FROM public.case_locks
        WHERE case_id = f.case_a
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
        f.case_a,
        f.organisation_a,
        f.employee_a,
        clock_timestamp(),
        clock_timestamp() + interval '5 minutes',
        v_token
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
        expires_at
    )
    VALUES (
        v_reservation,
        f.case_a,
        f.organisation_a,
        f.employee_a,
        'test059/' || v_reservation::text,
        'test059-revocation.pdf',
        'application/pdf',
        1024,
        'pending',
        clock_timestamp(),
        clock_timestamp() + interval '10 minutes'
    );

    INSERT INTO test059_fixture (lock_token, reservation_id)
    VALUES (v_token, v_reservation);

    RAISE NOTICE
        'PASS: Valid case lock and owned reservation created';
END;
$test$;

\echo '=== TEST059: AUTHORISED RESERVATION LISTING ==='

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test044_fixture),
    TRUE
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
    x test059_fixture%ROWTYPE;
    v_count integer;
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;
    SELECT * INTO STRICT x FROM test059_fixture;

    IF public.can_work_on_case(f.case_a) IS NOT TRUE THEN
        RAISE EXCEPTION
            'FAIL: Existing work grant not recognised';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM public.list_employee_case_evidence_upload_reservations(
        f.case_a,
        x.lock_token
    ) AS r
    WHERE r.reservation_id = x.reservation_id
      AND r.reservation_status = 'pending';

    IF v_count <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Authorised employee cannot list own reservation';
    END IF;

    RAISE NOTICE
        'PASS: Work-authorised employee lists owned reservation';
END;
$test$;

RESET ROLE;

\echo '=== TEST059: REVOKE WORK WITHOUT RELEASING LOCK ==='

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
    x test059_fixture%ROWTYPE;
    v_deleted integer;
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;
    SELECT * INTO STRICT x FROM test059_fixture;

    DELETE FROM public.team_permission_grants g
    WHERE g.organisation_id = f.organisation_a
      AND g.team_id = f.team_a
      AND g.user_id = f.employee_a
      AND g.permission_type = 'work';

    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    IF v_deleted <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Expected exactly one work grant revocation';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks l
        WHERE l.case_id = f.case_a
          AND l.organisation_id = f.organisation_a
          AND l.locked_by_user_id = f.employee_a
          AND l.lock_token = x.lock_token
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION
            'FAIL: Original exclusive lock no longer valid';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_evidence_upload_reservations r
        WHERE r.id = x.reservation_id
          AND r.case_id = f.case_a
          AND r.employee_id = f.employee_a
    ) THEN
        RAISE EXCEPTION
            'FAIL: Reservation unexpectedly disappeared';
    END IF;

    RAISE NOTICE
        'PASS: Work permission revoked; original lock and reservation retained';
END;
$test$;

\echo '=== TEST059: VERIFY IMMEDIATE ACCESS DENIAL ==='

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test044_fixture),
    TRUE
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
    x test059_fixture%ROWTYPE;
    v_denied boolean := FALSE;
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;
    SELECT * INTO STRICT x FROM test059_fixture;

    IF public.can_work_on_case(f.case_a) IS TRUE THEN
        RAISE EXCEPTION
            'FAIL: Revoked work permission remains effective';
    END IF;

    BEGIN
        PERFORM *
        FROM public.list_employee_case_evidence_upload_reservations(
            f.case_a,
            x.lock_token
        );

    EXCEPTION
        WHEN insufficient_privilege THEN
            IF SQLERRM <> 'Case work permission required' THEN
                RAISE;
            END IF;

            v_denied := TRUE;
    END;

    IF NOT v_denied THEN
        RAISE EXCEPTION
            'FAIL: Valid lock bypassed revoked team-work permission';
    END IF;

    RAISE NOTICE
        'PASS: Revoked work permission denies reservation listing despite valid lock';
END;
$test$;

RESET ROLE;

\echo '=== TEST059: VERIFY LOCK AND RESERVATION SURVIVED ==='

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
    x test059_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;
    SELECT * INTO STRICT x FROM test059_fixture;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks
        WHERE case_id = f.case_a
          AND locked_by_user_id = f.employee_a
          AND lock_token = x.lock_token
          AND expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION
            'FAIL: Lock changed during access-denial test';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_evidence_upload_reservations
        WHERE id = x.reservation_id
          AND case_id = f.case_a
    ) THEN
        RAISE EXCEPTION
            'FAIL: Reservation changed during access-denial test';
    END IF;

    RAISE NOTICE
        'PASS: Denial preserves original lock and reservation';
    RAISE NOTICE
        'PASS: TEST059 behavioural assertions completed';
END;
$test$;

\echo '=== TEST059: COMPLETE ==='
