-- MADZERA TEST 038
-- Migration 061: Team Permission Authorisation Security
--
-- Requires Migration 061 and active authenticated employee fixtures:
-- two employees in one organisation and one in another.
--
-- All changes are rolled back.
-- Run only against a disposable local development database.

\set ON_ERROR_STOP on

BEGIN;

-- Confirm that the installed helper exists.
DO $test$
BEGIN
    IF to_regprocedure(
        'public.has_team_permission(uuid,text)'
    ) IS NULL THEN
        RAISE EXCEPTION
            'FAIL: Migration 061 helper is not installed';
    END IF;

    RAISE NOTICE 'PASS: Migration 061 helper installed';
END;
$test$;

-- Verify effective execution privileges.
DO $test$
DECLARE
    v_role text;
BEGIN
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticator'] LOOP
        IF has_function_privilege(
            v_role,
            'public.has_team_permission(uuid,text)',
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                'FAIL: % can execute permission helper', v_role;
        END IF;
    END LOOP;

    FOREACH v_role IN ARRAY ARRAY[
        'authenticated', 'service_role', 'postgres'
    ] LOOP
        IF NOT has_function_privilege(
            v_role,
            'public.has_team_permission(uuid,text)',
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                'FAIL: % cannot execute permission helper', v_role;
        END IF;
    END LOOP;

    RAISE NOTICE 'PASS: Function execution privileges';
END;
$test$;

-- Discover fixtures without hardcoded employee identifiers.
CREATE TEMP TABLE test038_fixture (
    employee_a uuid NOT NULL,
    auth_a uuid NOT NULL,
    colleague_a uuid NOT NULL,
    auth_colleague uuid NOT NULL,
    organisation_a uuid NOT NULL,
    employee_b uuid NOT NULL,
    auth_b uuid NOT NULL,
    organisation_b uuid NOT NULL,
    team_a uuid,
    team_b uuid
);

GRANT SELECT ON test038_fixture TO authenticated;

WITH ranked AS (
    SELECT
        u.id,
        u.auth_user_id,
        u.organisation_id,
        ROW_NUMBER() OVER (
            PARTITION BY u.organisation_id
            ORDER BY u.id
        ) AS employee_number
    FROM public.users u
    WHERE u.is_active = TRUE
      AND u.auth_user_id IS NOT NULL
),
eligible AS (
    SELECT organisation_id
    FROM ranked
    GROUP BY organisation_id
    HAVING COUNT(*) >= 2
    ORDER BY organisation_id
    LIMIT 1
),
other_org AS (
    SELECT organisation_id
    FROM ranked
    WHERE organisation_id <> (
        SELECT organisation_id FROM eligible
    )
    GROUP BY organisation_id
    ORDER BY organisation_id
    LIMIT 1
)
INSERT INTO test038_fixture (
    employee_a,
    auth_a,
    colleague_a,
    auth_colleague,
    organisation_a,
    employee_b,
    auth_b,
    organisation_b
)
SELECT
    a.id,
    a.auth_user_id,
    colleague.id,
    colleague.auth_user_id,
    a.organisation_id,
    b.id,
    b.auth_user_id,
    b.organisation_id
FROM ranked a
JOIN ranked colleague
  ON colleague.organisation_id = a.organisation_id
 AND colleague.employee_number = 2
JOIN ranked b
  ON b.organisation_id = (SELECT organisation_id FROM other_org)
 AND b.employee_number = 1
WHERE a.organisation_id = (SELECT organisation_id FROM eligible)
  AND a.employee_number = 1;

DO $test$
BEGIN
    IF (SELECT COUNT(*) FROM test038_fixture) <> 1 THEN
        RAISE EXCEPTION 'FAIL: Required employee fixtures unavailable';
    END IF;

    RAISE NOTICE 'PASS: Dynamic employee fixtures discovered';
END;
$test$;

-- Create teams and capture their actual generated identifiers.
WITH created AS (
    INSERT INTO public.teams (organisation_id, name)
    SELECT organisation_a, 'TEST038 TEAM A'
    FROM test038_fixture
    RETURNING id, organisation_id
)
UPDATE test038_fixture f
SET team_a = created.id
FROM created
WHERE created.organisation_id = f.organisation_a;

WITH created AS (
    INSERT INTO public.teams (organisation_id, name)
    SELECT organisation_b, 'TEST038 TEAM B'
    FROM test038_fixture
    RETURNING id, organisation_id
)
UPDATE test038_fixture f
SET team_b = created.id
FROM created
WHERE created.organisation_id = f.organisation_b;

DO $test$
BEGIN
    IF EXISTS (
        SELECT 1 FROM test038_fixture
        WHERE team_a IS NULL OR team_b IS NULL
    ) THEN
        RAISE EXCEPTION 'FAIL: Test teams unavailable';
    END IF;

    RAISE NOTICE 'PASS: Isolated test teams created';
END;
$test$;

-- Grant submit permission only to employee A.
INSERT INTO public.team_permission_grants (
    organisation_id,
    team_id,
    user_id,
    permission_type
)
SELECT
    organisation_a,
    team_a,
    employee_a,
    'submit'
FROM test038_fixture;

-- Employee A: allowed submit, denied other permissions.
SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test038_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_team_a uuid;
    v_team_b uuid;
BEGIN
    SELECT team_a, team_b
    INTO STRICT v_team_a, v_team_b
    FROM test038_fixture;

    IF public.has_team_permission(v_team_a, 'submit')
       IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'FAIL: Explicit submit grant denied';
    END IF;

    IF public.has_team_permission(v_team_a, 'work')
       IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'FAIL: Work permission inherited';
    END IF;

    IF public.has_team_permission(v_team_a, 'manage')
       IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'FAIL: Manage permission inherited';
    END IF;

    IF public.has_team_permission(v_team_b, 'submit')
       IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'FAIL: Cross-organisation permission accepted';
    END IF;

    IF public.has_team_permission(v_team_a, 'invalid')
       IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'FAIL: Invalid permission accepted';
    END IF;

    RAISE NOTICE 'PASS: Explicit grant and permission separation';
    RAISE NOTICE 'PASS: Cross-organisation team denied';
    RAISE NOTICE 'PASS: Invalid permission denied';
END;
$test$;

RESET ROLE;

-- A colleague cannot inherit employee A's grant.
SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_colleague::text FROM test038_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_team uuid;
BEGIN
    SELECT team_a INTO STRICT v_team
    FROM test038_fixture;

    IF public.has_team_permission(v_team, 'submit')
       IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'FAIL: Colleague inherited permission';
    END IF;

    RAISE NOTICE 'PASS: Colleague permission isolation';
END;
$test$;

RESET ROLE;

-- An employee in organisation B cannot use organisation A's grant.
SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_b::text FROM test038_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_team uuid;
BEGIN
    SELECT team_a INTO STRICT v_team
    FROM test038_fixture;

    IF public.has_team_permission(v_team, 'submit')
       IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'FAIL: Cross-tenant grant accepted';
    END IF;

    RAISE NOTICE 'PASS: Cross-tenant employee isolation';
END;
$test$;

RESET ROLE;

-- An authenticated identity without an employee link must be denied.
DO $test$
DECLARE
    v_unlinked_auth uuid := gen_random_uuid();
BEGIN
    WHILE EXISTS (
        SELECT 1
        FROM public.users
        WHERE auth_user_id = v_unlinked_auth
    ) LOOP
        v_unlinked_auth := gen_random_uuid();
    END LOOP;

    PERFORM set_config(
        'request.jwt.claim.sub',
        v_unlinked_auth::text,
        true
    );

    RAISE NOTICE 'PASS: Unlinked authentication fixture prepared';
END;
$test$;

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_team uuid;
BEGIN
    SELECT team_a INTO STRICT v_team
    FROM test038_fixture;

    IF public.current_employee_id() IS NOT NULL THEN
        RAISE EXCEPTION
            'FAIL: Unlinked identity resolved to an employee';
    END IF;

    IF public.has_team_permission(v_team, 'submit')
       IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION
            'FAIL: Unlinked identity received team permission';
    END IF;

    RAISE NOTICE 'PASS: Unlinked authenticated identity denied';
END;
$test$;

RESET ROLE;

-- Restore employee A and verify permission before revocation.
SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test038_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_team uuid;
BEGIN
    SELECT team_a INTO STRICT v_team
    FROM test038_fixture;

    IF public.has_team_permission(v_team, 'submit')
       IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'FAIL: Granted access not restored';
    END IF;

    RAISE NOTICE 'PASS: Granted employee access confirmed';
END;
$test$;

RESET ROLE;

-- Deactivate employee A while the grant still exists.
DO $test$
DECLARE
    v_rows integer;
BEGIN
    UPDATE public.users u
    SET is_active = FALSE
    FROM test038_fixture f
    WHERE u.id = f.employee_a
      AND u.is_active = TRUE;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Expected one employee deactivation, got %',
            v_rows;
    END IF;

    RAISE NOTICE 'PASS: Exactly one employee deactivated';
END;
$test$;

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_team uuid;
BEGIN
    SELECT team_a INTO STRICT v_team
    FROM test038_fixture;

    IF public.current_employee_id() IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Inactive employee identity resolved';
    END IF;

    IF public.has_team_permission(v_team, 'submit')
       IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'FAIL: Inactive employee retained access';
    END IF;

    RAISE NOTICE 'PASS: Inactive employee denied';
END;
$test$;

RESET ROLE;

-- Reactivate within transaction to test grant revocation separately.
DO $test$
DECLARE
    v_rows integer;
BEGIN
    UPDATE public.users u
    SET is_active = TRUE
    FROM test038_fixture f
    WHERE u.id = f.employee_a
      AND u.is_active = FALSE;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Expected one employee reactivation, got %',
            v_rows;
    END IF;

    RAISE NOTICE 'PASS: Exactly one employee reactivated';
END;
$test$;

DO $test$
DECLARE
    v_rows integer;
BEGIN
    DELETE FROM public.team_permission_grants g
    USING test038_fixture f
    WHERE g.team_id = f.team_a
      AND g.user_id = f.employee_a
      AND g.permission_type = 'submit';

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Expected one permission revocation, got %',
            v_rows;
    END IF;

    RAISE NOTICE 'PASS: Exactly one permission grant revoked';
END;
$test$;

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_team uuid;
BEGIN
    SELECT team_a INTO STRICT v_team
    FROM test038_fixture;

    IF public.has_team_permission(v_team, 'submit')
       IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'FAIL: Revoked permission retained';
    END IF;

    RAISE NOTICE 'PASS: Revoked permission denied';
END;
$test$;

RESET ROLE;

ROLLBACK;
