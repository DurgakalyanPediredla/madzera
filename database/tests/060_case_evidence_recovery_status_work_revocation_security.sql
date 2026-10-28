-- MADZERA TEST 060
-- Evidence Recovery Status: Immediate Team-Work Revocation
--
-- Requires Test 044's fixture setup and Migration 067.
-- Execute inside an outer rollback-only transaction.
-- Insert before Test 044's original authorisation assertions.
-- Never execute independently against production.

\echo '=== TEST060: CREATE VALID LOCK AND OWNED RESERVATION ==='

CREATE TEMP TABLE test060_fixture (
    lock_token uuid NOT NULL,
    reservation_id uuid NOT NULL,
    reservation_before jsonb NOT NULL,
    lock_before jsonb NOT NULL,
    attachment_count_before bigint NOT NULL,
    audit_count_before bigint NOT NULL
) ON COMMIT DROP;

GRANT SELECT ON test060_fixture TO authenticated;

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
    v_token uuid := gen_random_uuid();
    v_reservation uuid := gen_random_uuid();
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;

    IF EXISTS (
        SELECT 1 FROM public.case_locks
        WHERE case_id = f.case_a
    ) THEN
        RAISE EXCEPTION
            'STOP: Existing case lock must not be overwritten';
    END IF;

    INSERT INTO public.case_locks (
        case_id, organisation_id, locked_by_user_id,
        locked_at, expires_at, lock_token
    )
    VALUES (
        f.case_a, f.organisation_a, f.employee_a,
        clock_timestamp(),
        clock_timestamp() + interval '5 minutes',
        v_token
    );

    INSERT INTO public.case_evidence_upload_reservations (
        id, case_id, organisation_id, employee_id,
        storage_path, file_name, file_type,
        file_size_bytes, status, created_at, expires_at
    )
    VALUES (
        v_reservation, f.case_a, f.organisation_a,
        f.employee_a,
        'test060/' || v_reservation::text,
        'test060-recovery.pdf', 'application/pdf',
        1024, 'pending', clock_timestamp(),
        clock_timestamp() + interval '10 minutes'
    );

    INSERT INTO test060_fixture (
        lock_token, reservation_id, reservation_before,
        lock_before, attachment_count_before, audit_count_before
    )
    SELECT
        v_token,
        v_reservation,
        to_jsonb(r),
        to_jsonb(l),
        (SELECT COUNT(*) FROM public.attachments
         WHERE case_id = f.case_a),
        (SELECT COUNT(*) FROM public.case_events
         WHERE case_id = f.case_a)
    FROM public.case_evidence_upload_reservations r
    JOIN public.case_locks l ON l.case_id = r.case_id
    WHERE r.id = v_reservation
      AND l.lock_token = v_token;

    IF (SELECT COUNT(*) FROM test060_fixture) <> 1 THEN
        RAISE EXCEPTION 'FAIL: Fixture baseline not captured';
    END IF;

    RAISE NOTICE
        'PASS: Valid exclusive lock, reservation and integrity baseline created';
END;
$test$;

\echo '=== TEST060: AUTHORISED RECOVERY STATUS ==='

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test044_fixture),
    TRUE
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
    x test060_fixture%ROWTYPE;
    v_status text;
    v_attachment uuid;
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;
    SELECT * INTO STRICT x FROM test060_fixture;

    IF public.can_work_on_case(f.case_a) IS NOT TRUE THEN
        RAISE EXCEPTION
            'FAIL: Expected work permission missing';
    END IF;

    SELECT reservation_status, attachment_id
    INTO STRICT v_status, v_attachment
    FROM public.get_case_evidence_upload_recovery_status(
        x.reservation_id,
        f.case_a,
        x.lock_token
    );

    IF v_status IS DISTINCT FROM 'pending'
       OR v_attachment IS NOT NULL THEN
        RAISE EXCEPTION
            'FAIL: Unexpected authorised recovery status';
    END IF;

    RAISE NOTICE
        'PASS: Work-authorised employee retrieves pending recovery status';
END;
$test$;

RESET ROLE;

\echo '=== TEST060: REVOKE WORK WITHOUT RELEASING LOCK ==='

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
    x test060_fixture%ROWTYPE;
    v_deleted integer;
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;
    SELECT * INTO STRICT x FROM test060_fixture;

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
        SELECT 1 FROM public.case_locks l
        WHERE l.case_id = f.case_a
          AND l.organisation_id = f.organisation_a
          AND l.locked_by_user_id = f.employee_a
          AND l.lock_token = x.lock_token
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION
            'FAIL: Valid exclusive lock lost during revocation';
    END IF;

    RAISE NOTICE
        'PASS: Work revoked while original exclusive lock remains valid';
END;
$test$;

\echo '=== TEST060: DENY RECOVERY STATUS AFTER REVOCATION ==='

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test044_fixture),
    TRUE
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
    x test060_fixture%ROWTYPE;
    v_denied boolean := FALSE;
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;
    SELECT * INTO STRICT x FROM test060_fixture;

    IF public.can_work_on_case(f.case_a) IS TRUE THEN
        RAISE EXCEPTION
            'FAIL: Revoked work permission remains effective';
    END IF;

    BEGIN
        PERFORM *
        FROM public.get_case_evidence_upload_recovery_status(
            x.reservation_id,
            f.case_a,
            x.lock_token
        );

    EXCEPTION
        WHEN SQLSTATE '42501' THEN
            IF SQLERRM <> 'Case work permission required' THEN
                RAISE EXCEPTION
                    'FAIL: Unexpected recovery denial: %', SQLERRM;
            END IF;

            v_denied := TRUE;
    END;

    IF NOT v_denied THEN
        RAISE EXCEPTION
            'FAIL: Valid lock bypassed revoked work permission';
    END IF;

    RAISE NOTICE
        'PASS: Revoked employee recovery status denied despite valid lock';
END;
$test$;

RESET ROLE;

\echo '=== TEST060: VERIFY DENIAL PRESERVED STATE ==='

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
    x test060_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;
    SELECT * INTO STRICT x FROM test060_fixture;

    IF NOT EXISTS (
        SELECT 1 FROM public.case_locks l
        WHERE l.case_id = f.case_a
          AND l.organisation_id = f.organisation_a
          AND l.locked_by_user_id = f.employee_a
          AND l.lock_token = x.lock_token
          AND l.expires_at > clock_timestamp()
          AND to_jsonb(l) = x.lock_before
    ) THEN
        RAISE EXCEPTION
            'FAIL: Exclusive lock changed after recovery denial';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_evidence_upload_reservations r
        WHERE r.id = x.reservation_id
          AND r.case_id = f.case_a
          AND to_jsonb(r) = x.reservation_before
    ) THEN
        RAISE EXCEPTION
            'FAIL: Reservation changed after recovery denial';
    END IF;

    IF (
        SELECT COUNT(*) FROM public.attachments
        WHERE case_id = f.case_a
    ) <> x.attachment_count_before THEN
        RAISE EXCEPTION
            'FAIL: Attachment count changed after recovery denial';
    END IF;

    IF (
        SELECT COUNT(*) FROM public.case_events
        WHERE case_id = f.case_a
    ) <> x.audit_count_before THEN
        RAISE EXCEPTION
            'FAIL: Audit event count changed after recovery denial';
    END IF;

    RAISE NOTICE
        'PASS: Recovery denial preserved exclusive lock exactly';
    RAISE NOTICE
        'PASS: Recovery denial preserved reservation exactly';
    RAISE NOTICE
        'PASS: Recovery denial created no attachment or audit event';
    RAISE NOTICE
        'PASS: TEST060 behavioural assertions completed';
END;
$test$;

\echo '=== TEST060: COMPLETE ==='
