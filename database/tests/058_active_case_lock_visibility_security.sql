-- MADZERA TEST 058
-- Active Case Lock Visibility Authorisation Security
--
-- STATUS: DRAFT - NOT YET EXECUTED.
--
-- Requires migrations 066 and 067 and the isolated fixture
-- created by Test 044 inside the same outer rollback-only
-- transaction.
--
-- Execute before Test 044 revokes its Team A work grant.
-- This test performs its own grant/revocation assertions.
--
-- Never run independently against production.

\echo '=== TEST058: CREATE SYNTHETIC ACTIVE LOCKS ==='

CREATE TEMP TABLE test058_locks (
    case_a uuid NOT NULL,
    case_other uuid NOT NULL,
    case_b uuid NOT NULL
) ON COMMIT DROP;

INSERT INTO test058_locks (case_a, case_other, case_b)
SELECT case_a, case_other, case_b
FROM test044_fixture;

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;

    IF EXISTS (
        SELECT 1
        FROM public.case_locks l
        WHERE l.case_id IN (f.case_a, f.case_other, f.case_b)
    ) THEN
        RAISE EXCEPTION
            'STOP: Synthetic cases unexpectedly have existing locks';
    END IF;

    INSERT INTO public.case_locks (
        case_id,
        organisation_id,
        locked_by_user_id,
        locked_at,
        expires_at,
        lock_token
    )
    VALUES
        (
            f.case_a,
            f.organisation_a,
            f.employee_a,
            clock_timestamp(),
            clock_timestamp() + interval '5 minutes',
            gen_random_uuid()
        ),
        (
            f.case_other,
            f.organisation_a,
            f.employee_a,
            clock_timestamp(),
            clock_timestamp() + interval '5 minutes',
            gen_random_uuid()
        ),
        (
            f.case_b,
            f.organisation_b,
            f.employee_b,
            clock_timestamp(),
            clock_timestamp() + interval '5 minutes',
            gen_random_uuid()
        );

    RAISE NOTICE 'PASS: Three synthetic active locks created';
END;
$test$;

\echo '=== TEST058: AUTHORISED WORKER VISIBILITY ==='

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test044_fixture),
    TRUE
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;

    IF NOT EXISTS (
        SELECT 1
        FROM public.get_active_case_locks() l
        WHERE l.case_id = f.case_a
    ) THEN
        RAISE EXCEPTION
            'FAIL: Authorised worker cannot see Team A lock';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.get_active_case_locks() l
        WHERE l.case_id IN (f.case_other, f.case_b)
    ) THEN
        RAISE EXCEPTION
            'FAIL: Unauthorised team or foreign lock visible';
    END IF;

    RAISE NOTICE
        'PASS: Worker sees authorised active lock only';
END;
$test$;

RESET ROLE;

\echo '=== TEST058: SUBMIT AND MANAGE CANNOT VIEW LOCKS ==='

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_colleague::text FROM test044_fixture),
    TRUE
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;

    IF NOT public.has_team_permission(f.team_a, 'submit')
        OR NOT public.has_team_permission(f.team_a, 'manage')
        OR public.has_team_permission(f.team_a, 'work')
    THEN
        RAISE EXCEPTION
            'FAIL: Non-worker permission fixture invalid';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.get_active_case_locks() l
        WHERE l.case_id IN (f.case_a, f.case_other, f.case_b)
    ) THEN
        RAISE EXCEPTION
            'FAIL: Submit/manage permissions exposed active locks';
    END IF;

    RAISE NOTICE
        'PASS: Submit/manage permissions do not expose locks';
END;
$test$;

RESET ROLE;

\echo '=== TEST058: EXPLICIT SECOND-TEAM WORK GRANT ==='

INSERT INTO public.team_permission_grants (
    organisation_id,
    team_id,
    user_id,
    permission_type
)
SELECT organisation_a, team_other, employee_a, 'work'
FROM test044_fixture;

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test044_fixture),
    TRUE
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;

    IF (
        SELECT COUNT(*)
        FROM public.get_active_case_locks() l
        WHERE l.case_id IN (f.case_a, f.case_other)
    ) <> 2 THEN
        RAISE EXCEPTION
            'FAIL: Explicit multi-team work grant did not expose both locks';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.get_active_case_locks() l
        WHERE l.case_id = f.case_b
    ) THEN
        RAISE EXCEPTION
            'FAIL: Cross-organisation lock exposed';
    END IF;

    RAISE NOTICE
        'PASS: Explicit work grants permit multi-team lock visibility';
END;
$test$;

RESET ROLE;

\echo '=== TEST058: REVOKE SECOND-TEAM WORK GRANT ==='

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
    v_deleted integer;
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;

    DELETE FROM public.team_permission_grants g
    WHERE g.organisation_id = f.organisation_a
      AND g.team_id = f.team_other
      AND g.user_id = f.employee_a
      AND g.permission_type = 'work';

    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    IF v_deleted <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Expected one second-team work grant revoked';
    END IF;
END;
$test$;

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test044_fixture),
    TRUE
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;

    IF NOT EXISTS (
        SELECT 1
        FROM public.get_active_case_locks() l
        WHERE l.case_id = f.case_a
    ) THEN
        RAISE EXCEPTION
            'FAIL: Revoking Team Other removed Team A visibility';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.get_active_case_locks() l
        WHERE l.case_id IN (f.case_other, f.case_b)
    ) THEN
        RAISE EXCEPTION
            'FAIL: Revoked second-team lock remains visible';
    END IF;

    RAISE NOTICE
        'PASS: Revocation immediately removes second-team visibility';
END;
$test$;

RESET ROLE;

\echo '=== TEST058: ACTIVE-LOCK SECURITY TEST COMPLETE ==='
