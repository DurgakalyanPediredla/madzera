-- MADZERA TEST 039
-- Migration 062: Secure Organisation Team Provisioning
--
-- Requires migrations 060-062 and eligible authenticated employees
-- in two distinct organisations.
--
-- All changes are rolled back.
-- Run only against a disposable local development database.

\set ON_ERROR_STOP on

BEGIN;

-- 1. Confirm installed objects and effective privileges.

DO $test$
DECLARE
    v_role text;
    v_privilege text;
BEGIN
    IF to_regprocedure(
        'public.create_organisation_team(text,text)'
    ) IS NULL THEN
        RAISE EXCEPTION 'FAIL: Team creation RPC missing';
    END IF;

    IF to_regclass(
        'public.organisation_admin_audit_events'
    ) IS NULL THEN
        RAISE EXCEPTION 'FAIL: Administrative audit table missing';
    END IF;

    FOREACH v_role IN ARRAY ARRAY[
        'anon', 'authenticator', 'service_role'
    ] LOOP
        IF has_function_privilege(
            v_role,
            'public.create_organisation_team(text,text)',
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                'FAIL: % can execute team creation RPC',
                v_role;
        END IF;
    END LOOP;

    IF NOT has_function_privilege(
        'authenticated',
        'public.create_organisation_team(text,text)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'FAIL: Authenticated RPC execution denied';
    END IF;

    FOREACH v_role IN ARRAY ARRAY[
        'anon', 'authenticated', 'service_role'
    ] LOOP
        FOREACH v_privilege IN ARRAY ARRAY[
            'SELECT', 'INSERT', 'UPDATE', 'DELETE'
        ] LOOP
            IF has_table_privilege(
                v_role,
                'public.organisation_admin_audit_events',
                v_privilege
            ) THEN
                RAISE EXCEPTION
                    'FAIL: % has direct audit-table % privilege',
                    v_role, v_privilege;
            END IF;
        END LOOP;
    END LOOP;

    IF NOT (
        SELECT c.relrowsecurity
        FROM pg_class c
        WHERE c.oid =
            'public.organisation_admin_audit_events'::regclass
    ) THEN
        RAISE EXCEPTION 'FAIL: Audit table RLS disabled';
    END IF;

    RAISE NOTICE 'PASS: RPC privileges and audit-table security';
END;
$test$;

-- 2. Discover employee fixtures dynamically.

CREATE TEMP TABLE test039_fixture (
    organisation_a uuid NOT NULL,
    employee_a uuid NOT NULL,
    auth_a uuid NOT NULL,
    colleague_a uuid NOT NULL,
    auth_colleague uuid NOT NULL,
    organisation_b uuid NOT NULL,
    employee_b uuid NOT NULL,
    auth_b uuid NOT NULL,
    team_a uuid,
    trimmed_team uuid
);

GRANT SELECT ON test039_fixture TO authenticated;

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
INSERT INTO test039_fixture (
    organisation_a,
    employee_a,
    auth_a,
    colleague_a,
    auth_colleague,
    organisation_b,
    employee_b,
    auth_b
)
SELECT
    a.organisation_id,
    a.id,
    a.auth_user_id,
    colleague.id,
    colleague.auth_user_id,
    b.organisation_id,
    b.id,
    b.auth_user_id
FROM ranked a
JOIN ranked colleague
  ON colleague.organisation_id = a.organisation_id
 AND colleague.employee_number = 2
JOIN ranked b
  ON b.organisation_id = (
      SELECT organisation_id FROM other_org
  )
 AND b.employee_number = 1
WHERE a.organisation_id = (
    SELECT organisation_id FROM eligible
)
  AND a.employee_number = 1;

DO $test$
BEGIN
    IF (SELECT COUNT(*) FROM test039_fixture) <> 1 THEN
        RAISE EXCEPTION 'FAIL: Required fixtures unavailable';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.organisation_administrators oa
        JOIN test039_fixture f
          ON oa.organisation_id IN (
              f.organisation_a, f.organisation_b
          )
    ) THEN
        RAISE EXCEPTION
            'FAIL: Test requires organisations without administrators';
    END IF;

    RAISE NOTICE 'PASS: Dynamic multi-organisation fixtures';
END;
$test$;

-- 3. Anonymous execution must be denied.

SET LOCAL ROLE anon;

DO $test$
DECLARE
    v_state text;
BEGIN
    BEGIN
        PERFORM public.create_organisation_team(
            'TEST039 ANONYMOUS'
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_state = RETURNED_SQLSTATE;
    END;

    IF v_state IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION
            'FAIL: Anonymous execution SQLSTATE %', v_state;
    END IF;

    RAISE NOTICE 'PASS: Anonymous team creation denied';
END;
$test$;

RESET ROLE;

-- 4. Unlinked authenticated identity must be denied.

SELECT set_config(
    'request.jwt.claim.sub',
    gen_random_uuid()::text,
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_state text;
BEGIN
    IF public.current_employee_id() IS NOT NULL THEN
        RAISE EXCEPTION
            'FAIL: Unlinked identity unexpectedly resolved';
    END IF;

    BEGIN
        PERFORM public.create_organisation_team(
            'TEST039 UNLINKED'
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_state = RETURNED_SQLSTATE;
    END;

    IF v_state IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION
            'FAIL: Unlinked identity SQLSTATE %', v_state;
    END IF;

    RAISE NOTICE 'PASS: Unlinked identity denied';
END;
$test$;

RESET ROLE;

-- 5. Ordinary employee must be denied.

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test039_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_state text;
BEGIN
    BEGIN
        PERFORM public.create_organisation_team(
            'TEST039 ORDINARY EMPLOYEE'
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_state = RETURNED_SQLSTATE;
    END;

    IF v_state IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION
            'FAIL: Ordinary employee SQLSTATE %', v_state;
    END IF;

    RAISE NOTICE 'PASS: Ordinary employee denied';
END;
$test$;

RESET ROLE;

-- 6. Use controlled initial administrator provisioning.

DO $test$
DECLARE
    f test039_fixture%ROWTYPE;
    v_result boolean;
BEGIN
    SELECT * INTO STRICT f FROM test039_fixture;

    v_result :=
        madzera_internal.provision_initial_organisation_admin(
            f.organisation_a,
            f.employee_a,
            'TEST039 controlled initial administrator provisioning'
        );

    IF v_result IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION
            'FAIL: Initial administrator provisioning failed';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.permission_audit_events e
        WHERE e.organisation_id = f.organisation_a
          AND e.target_user_id = f.employee_a
          AND e.permission_type = 'organisation_admin'
          AND e.action = 'granted'
          AND e.reason =
              'TEST039 controlled initial administrator provisioning'
    ) THEN
        RAISE EXCEPTION
            'FAIL: Initial administrator audit event missing';
    END IF;

    RAISE NOTICE
        'PASS: Controlled provisioning and audit attribution';
END;
$test$;

-- 7. Initial provisioning cannot be repeated.

DO $test$
DECLARE
    f test039_fixture%ROWTYPE;
    v_state text;
BEGIN
    SELECT * INTO STRICT f FROM test039_fixture;

    BEGIN
        PERFORM
            madzera_internal.provision_initial_organisation_admin(
                f.organisation_a,
                f.colleague_a,
                'TEST039 duplicate administrator provisioning attempt'
            );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_state = RETURNED_SQLSTATE;
    END;

    IF v_state IS NULL THEN
        RAISE EXCEPTION
            'FAIL: Duplicate initial provisioning accepted';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.organisation_administrators
        WHERE organisation_id = f.organisation_a
          AND user_id = f.colleague_a
    ) THEN
        RAISE EXCEPTION
            'FAIL: Duplicate administrator record created';
    END IF;

    RAISE NOTICE 'PASS: Duplicate initial provisioning denied';
END;
$test$;

-- 8. Authorised administrator creates a team.

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test039_fixture),
    true
);

SET LOCAL ROLE authenticated;

SELECT set_config(
    'madzera.test039.team_a',
    public.create_organisation_team(
        'TEST039 AUTHORISED TEAM',
        'Audited team provisioning test'
    )::text,
    true
);

RESET ROLE;

UPDATE test039_fixture
SET team_a = current_setting('madzera.test039.team_a')::uuid;

DO $test$
DECLARE
    f test039_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test039_fixture;

    IF NOT EXISTS (
        SELECT 1
        FROM public.teams t
        WHERE t.id = f.team_a
          AND t.organisation_id = f.organisation_a
          AND t.name = 'TEST039 AUTHORISED TEAM'
          AND t.description = 'Audited team provisioning test'
    ) THEN
        RAISE EXCEPTION
            'FAIL: Authorised team missing or incorrectly attributed';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM public.organisation_admin_audit_events e
        WHERE e.team_id = f.team_a
          AND e.organisation_id = f.organisation_a
          AND e.actor_user_id = f.employee_a
          AND e.action = 'team_created'
    ) <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Team creation audit attribution incorrect';
    END IF;

    RAISE NOTICE
        'PASS: Authorised creation and exact audit attribution';
END;
$test$;

-- 9. Organisation B employee cannot inherit A's authority.

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_b::text FROM test039_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_state text;
BEGIN
    BEGIN
        PERFORM public.create_organisation_team(
            'TEST039 CROSS TENANT'
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_state = RETURNED_SQLSTATE;
    END;

    IF v_state IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION
            'FAIL: Cross-tenant employee SQLSTATE %', v_state;
    END IF;

    RAISE NOTICE 'PASS: Cross-tenant administrator isolation';
END;
$test$;

RESET ROLE;

-- 10. Colleague in A cannot inherit administrator authority.

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_colleague::text FROM test039_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_state text;
BEGIN
    BEGIN
        PERFORM public.create_organisation_team(
            'TEST039 COLLEAGUE'
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_state = RETURNED_SQLSTATE;
    END;

    IF v_state IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION
            'FAIL: Non-admin colleague SQLSTATE %', v_state;
    END IF;

    RAISE NOTICE 'PASS: Colleague administrator isolation';
END;
$test$;

RESET ROLE;

-- 11. Invalid names must be rejected; valid names trimmed.

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test039_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_name text;
    v_case text;
    v_state text;
    v_team uuid;
BEGIN
    FOR v_case, v_name IN
        SELECT 'null', NULL::text
        UNION ALL SELECT 'empty', ''::text
        UNION ALL SELECT 'whitespace', '   '::text
        UNION ALL SELECT 'overlength', repeat('X', 151)
    LOOP
        v_state := NULL;

        BEGIN
            PERFORM public.create_organisation_team(v_name);
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS
                v_state = RETURNED_SQLSTATE;
        END;

        IF v_state IS DISTINCT FROM '22023' THEN
            RAISE EXCEPTION
                'FAIL: % name returned SQLSTATE %',
                v_case, v_state;
        END IF;
    END LOOP;

    RAISE NOTICE 'PASS: Invalid team names rejected';

    v_team := public.create_organisation_team(
        '   TEST039 TRIMMED TEAM   '
    );

    PERFORM set_config(
        'madzera.test039.trimmed_team',
        v_team::text,
        true
    );

    RAISE NOTICE 'PASS: Valid trimmed-name request accepted';
END;
$test$;

RESET ROLE;

UPDATE test039_fixture
SET trimmed_team =
    current_setting('madzera.test039.trimmed_team')::uuid;

DO $test$
DECLARE
    f test039_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test039_fixture;

    IF NOT EXISTS (
        SELECT 1
        FROM public.teams
        WHERE id = f.trimmed_team
          AND organisation_id = f.organisation_a
          AND name = 'TEST039 TRIMMED TEAM'
    ) THEN
        RAISE EXCEPTION 'FAIL: Team name not trimmed';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM public.organisation_admin_audit_events
        WHERE team_id = f.trimmed_team
          AND organisation_id = f.organisation_a
          AND actor_user_id = f.employee_a
    ) <> 1 THEN
        RAISE EXCEPTION 'FAIL: Trimmed team audit missing';
    END IF;

    RAISE NOTICE 'PASS: Trimmed team and audit verified';
END;
$test$;

-- 12. Inactive administrator must be denied.

UPDATE public.users u
SET is_active = FALSE
FROM test039_fixture f
WHERE u.id = f.employee_a
  AND u.is_active = TRUE;

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test039_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_state text;
BEGIN
    IF public.current_employee_id() IS NOT NULL THEN
        RAISE EXCEPTION
            'FAIL: Inactive administrator resolved as active employee';
    END IF;

    BEGIN
        PERFORM public.create_organisation_team(
            'TEST039 INACTIVE ADMIN'
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_state = RETURNED_SQLSTATE;
    END;

    IF v_state IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION
            'FAIL: Inactive administrator SQLSTATE %', v_state;
    END IF;

    RAISE NOTICE 'PASS: Inactive administrator denied';
END;
$test$;

RESET ROLE;

UPDATE public.users u
SET is_active = TRUE
FROM test039_fixture f
WHERE u.id = f.employee_a
  AND u.is_active = FALSE;

-- 13. Simulate an audit insertion failure.
-- Trigger and function are removed by the outer ROLLBACK.

CREATE FUNCTION public.test039_reject_audit_insert()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
    IF NEW.action = 'team_created'
       AND NEW.details = 'Organisation team created' THEN
        RAISE EXCEPTION 'TEST039_FORCED_AUDIT_FAILURE'
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$function$;

CREATE TRIGGER test039_reject_audit_insert
BEFORE INSERT ON public.organisation_admin_audit_events
FOR EACH ROW
EXECUTE FUNCTION public.test039_reject_audit_insert();

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test039_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_state text;
    v_message text;
BEGIN
    BEGIN
        PERFORM public.create_organisation_team(
            'TEST039 ATOMICITY TEAM'
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_state = RETURNED_SQLSTATE,
            v_message = MESSAGE_TEXT;
    END;

    IF v_state IS DISTINCT FROM 'P0001'
       OR v_message IS DISTINCT FROM
           'TEST039_FORCED_AUDIT_FAILURE' THEN
        RAISE EXCEPTION
            'FAIL: Expected injected audit failure; got % / %',
            v_state, v_message;
    END IF;

    RAISE NOTICE 'PASS: Injected audit failure propagated';
END;
$test$;

RESET ROLE;

DO $test$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.teams
        WHERE name = 'TEST039 ATOMICITY TEAM'
    ) THEN
        RAISE EXCEPTION
            'FAIL: Team survived failed audit insertion';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.teams
        WHERE name IN (
            'TEST039 ANONYMOUS',
            'TEST039 UNLINKED',
            'TEST039 ORDINARY EMPLOYEE',
            'TEST039 CROSS TENANT',
            'TEST039 COLLEAGUE',
            'TEST039 INACTIVE ADMIN'
        )
    ) THEN
        RAISE EXCEPTION
            'FAIL: Unauthorised team record persisted';
    END IF;

    RAISE NOTICE
        'PASS: No unaudited or unauthorised teams persisted';
END;
$test$;

ROLLBACK;
