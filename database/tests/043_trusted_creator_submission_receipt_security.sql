-- MADZERA TEST 043
-- Trusted Creator Attribution and Submission Receipt Security
--
-- Requires migration 065 within the same rollback-only transaction.
-- Disposable local development database only.
-- Do not execute independently against production.
--
-- Phase 1: authenticated submit-only creation and receipt.
-- Phase 2: negative authorisation and immutability assertions.
--
-- The outer test runner owns BEGIN and ROLLBACK.

\echo '=== TEST043: SELECT EXISTING MULTI-ORGANISATION IDENTITIES ==='

CREATE TEMP TABLE test043_fixture (
    organisation_a uuid NOT NULL,
    employee_a uuid NOT NULL,
    auth_a uuid NOT NULL,
    colleague_a uuid NOT NULL,
    auth_colleague uuid NOT NULL,
    organisation_b uuid NOT NULL,
    employee_b uuid NOT NULL,
    auth_b uuid NOT NULL,
    destination_team uuid,
    created_case_id uuid
) ON COMMIT DROP;

GRANT SELECT ON test043_fixture TO authenticated;

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
    ORDER BY organisation_id
    LIMIT 1
)
INSERT INTO test043_fixture (
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
    IF (SELECT COUNT(*) FROM test043_fixture) <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Multi-organisation employee fixtures unavailable';
    END IF;

    RAISE NOTICE 'PASS: Test identities selected';
END;
$test$;

\echo '=== TEST043: CREATE ISOLATED DESTINATION TEAM ==='

WITH created AS (
    INSERT INTO public.teams (
        organisation_id,
        name
    )
    SELECT
        organisation_a,
        'TEST043 SUBMISSION DESTINATION'
    FROM test043_fixture
    RETURNING id, organisation_id
)
UPDATE test043_fixture f
SET destination_team = t.id
FROM created t
WHERE f.organisation_a = t.organisation_id;

INSERT INTO public.team_permission_grants (
    organisation_id,
    team_id,
    user_id,
    permission_type
)
SELECT
    organisation_a,
    destination_team,
    employee_a,
    'submit'
FROM test043_fixture;

DO $test$
DECLARE
    f test043_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test043_fixture;

    IF f.destination_team IS NULL THEN
        RAISE EXCEPTION 'FAIL: Destination team missing';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.team_permission_grants g
        WHERE g.user_id = f.employee_a
          AND g.team_id = f.destination_team
          AND g.permission_type = 'work'
    ) THEN
        RAISE EXCEPTION
            'FAIL: Submit-only employee has work permission';
    END IF;

    RAISE NOTICE 'PASS: Isolated submit-only permission established';
END;
$test$;

\echo '=== TEST043: AUTHENTICATED CASE CREATION ==='

CREATE TEMP TABLE test043_creation_result (
    case_id uuid NOT NULL
) ON COMMIT DROP;

GRANT INSERT ON test043_creation_result TO authenticated;

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test043_fixture),
    TRUE
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test043_fixture%ROWTYPE;
    v_case_id uuid;
BEGIN
    IF current_user <> 'authenticated' THEN
        RAISE EXCEPTION
            'FAIL: Case creation did not run as authenticated';
    END IF;

    SELECT * INTO STRICT f FROM test043_fixture;

    IF NOT public.has_team_permission(
        f.destination_team,
        'submit'
    ) THEN
        RAISE EXCEPTION
            'FAIL: Submit permission not effective';
    END IF;

    IF public.has_team_permission(
        f.destination_team,
        'work'
    ) THEN
        RAISE EXCEPTION
            'FAIL: Submit-only creator unexpectedly has work permission';
    END IF;

    v_case_id := public.create_employee_case_v2(
        'TEST043 Trusted Creator Case',
        'Rollback-only creator attribution security test',
        'medium',
        NULL,
        f.destination_team,
        'internal_case'
    );

    IF v_case_id IS NULL THEN
        RAISE EXCEPTION
            'FAIL: Case creation returned NULL';
    END IF;

    INSERT INTO test043_creation_result(case_id)
    VALUES (v_case_id);

    RAISE NOTICE
        'PASS: Submit-only employee created case through public v2 RPC';
END;
$test$;

RESET ROLE;

UPDATE test043_fixture f
SET created_case_id = r.case_id
FROM test043_creation_result r;

\echo '=== TEST043: VERIFY TRUSTED CREATOR AND AUDIT EVENT ==='

DO $test$
DECLARE
    f test043_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test043_fixture;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases c
        WHERE c.id = f.created_case_id
          AND c.organisation_id = f.organisation_a
          AND c.created_by_user_id = f.employee_a
          AND c.assigned_team_id = f.destination_team
          AND c.initiated_by = 'employee'
          AND c.case_reference IS NOT NULL
    ) THEN
        RAISE EXCEPTION
            'FAIL: Trusted creator attribution incorrect';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM public.case_events e
        WHERE e.case_id = f.created_case_id
          AND e.organisation_id = f.organisation_a
          AND e.actor_user_id = f.employee_a
          AND e.event_type = 'case_created'
          AND e.to_team_id = f.destination_team
    ) <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Original creation audit event incorrect';
    END IF;

    RAISE NOTICE
        'PASS: Creator attribution and creation audit event verified';
END;
$test$;

\echo '=== TEST043: ORIGINAL CREATOR RECEIPT ==='

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test043_fixture),
    TRUE
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test043_fixture%ROWTYPE;
    v_count integer;
BEGIN
    SELECT * INTO STRICT f FROM test043_fixture;

    SELECT COUNT(*)
    INTO v_count
    FROM public.get_case_submission_receipt(f.created_case_id);

    IF v_count <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Original creator receipt unavailable';
    END IF;

    RAISE NOTICE
        'PASS: Original creator can retrieve submission receipt';
END;
$test$;

RESET ROLE;

\echo '=== TEST043 PHASE 1 COMPLETE ==='

\echo '=== TEST043: SAME-ORGANISATION RECEIPT ISOLATION ==='

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_colleague::text FROM test043_fixture),
    TRUE
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test043_fixture%ROWTYPE;
    v_count integer;
BEGIN
    SELECT * INTO STRICT f FROM test043_fixture;

    SELECT COUNT(*)
    INTO v_count
    FROM public.get_case_submission_receipt(f.created_case_id);

    IF v_count <> 0 THEN
        RAISE EXCEPTION
            'FAIL: Same-organisation noncreator accessed receipt';
    END IF;

    RAISE NOTICE
        'PASS: Same-organisation noncreator cannot access receipt';
END;
$test$;

RESET ROLE;

\echo '=== TEST043: CROSS-ORGANISATION RECEIPT ISOLATION ==='

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_b::text FROM test043_fixture),
    TRUE
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test043_fixture%ROWTYPE;
    v_count integer;
BEGIN
    SELECT * INTO STRICT f FROM test043_fixture;

    SELECT COUNT(*)
    INTO v_count
    FROM public.get_case_submission_receipt(f.created_case_id);

    IF v_count <> 0 THEN
        RAISE EXCEPTION
            'FAIL: Cross-organisation employee accessed receipt';
    END IF;

    RAISE NOTICE
        'PASS: Cross-organisation receipt isolation enforced';
END;
$test$;

RESET ROLE;

\echo '=== TEST043: ANONYMOUS RECEIPT EXECUTION DENIED ==='

DO $test$
DECLARE
    v_allowed boolean;
BEGIN
    SELECT has_function_privilege(
        'anon',
        'public.get_case_submission_receipt(uuid)',
        'EXECUTE'
    )
    INTO v_allowed;

    IF v_allowed THEN
        RAISE EXCEPTION
            'FAIL: Anonymous role has receipt EXECUTE permission';
    END IF;

    RAISE NOTICE
        'PASS: Anonymous receipt EXECUTE permission denied';
END;
$test$;

\echo '=== TEST043: CREATOR IMMUTABILITY ==='

-- Execute as postgres to test the trigger itself, rather than
-- merely confirming an authenticated role lacks UPDATE privileges.

DO $test$
DECLARE
    f test043_fixture%ROWTYPE;
    v_denied boolean := FALSE;
    v_sqlstate text;
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION
            'FAIL: Immutability trigger test must run as postgres';
    END IF;

    SELECT * INTO STRICT f FROM test043_fixture;

    BEGIN
        UPDATE public.cases
        SET created_by_user_id = f.colleague_a
        WHERE id = f.created_case_id;

    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS
                v_sqlstate = RETURNED_SQLSTATE;

            IF v_sqlstate = '42501' THEN
                v_denied := TRUE;
            ELSE
                RAISE EXCEPTION
                    'FAIL: Unexpected creator update SQLSTATE %',
                    v_sqlstate;
            END IF;
    END;

    IF NOT v_denied THEN
        RAISE EXCEPTION
            'FAIL: Privileged creator update was not denied';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases c
        WHERE c.id = f.created_case_id
          AND c.created_by_user_id = f.employee_a
    ) THEN
        RAISE EXCEPTION
            'FAIL: Original creator attribution changed';
    END IF;

    RAISE NOTICE
        'PASS: Creator immutability enforced against privileged UPDATE';
END;
$test$;

\echo '=== TEST043: OPERATIONAL SESSION DENIED TO SUBMIT-ONLY CREATOR ==='

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test043_fixture),
    TRUE
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test043_fixture%ROWTYPE;
    v_denied boolean := FALSE;
BEGIN
    SELECT * INTO STRICT f FROM test043_fixture;

    IF public.has_team_permission(f.destination_team, 'work') THEN
        RAISE EXCEPTION
            'FAIL: Submit-only creator unexpectedly has work permission';
    END IF;

    BEGIN
        PERFORM *
        FROM public.open_case_session(f.created_case_id);

    EXCEPTION
        WHEN insufficient_privilege THEN
            v_denied := TRUE;
    END;

    IF NOT v_denied THEN
        RAISE EXCEPTION
            'FAIL: Submit-only creator opened operational case session';
    END IF;

    RAISE NOTICE
        'PASS: Receipt ownership does not grant operational access';
END;
$test$;

RESET ROLE;

\echo '=== TEST043: EXACT RECEIPT RETURN CONTRACT ==='

DO $test$
DECLARE
    v_names text[];
    v_types text[];
BEGIN
    SELECT
        ARRAY(
            SELECT p.proargnames[i]
            FROM generate_subscripts(p.proallargtypes, 1) AS i
            WHERE p.proargmodes[i] IN ('o', 'b', 't')
            ORDER BY i
        ),
        ARRAY(
            SELECT format_type(p.proallargtypes[i], NULL)
            FROM generate_subscripts(p.proallargtypes, 1) AS i
            WHERE p.proargmodes[i] IN ('o', 'b', 't')
            ORDER BY i
        )
    INTO v_names, v_types
    FROM pg_proc p
    WHERE p.oid =
        'public.get_case_submission_receipt(uuid)'::regprocedure;

    IF v_names IS DISTINCT FROM ARRAY[
        'case_id',
        'case_reference',
        'created_at'
    ]::text[] THEN
        RAISE EXCEPTION
            'FAIL: Unexpected receipt output names: %',
            v_names;
    END IF;

    IF v_types IS DISTINCT FROM ARRAY[
        'uuid',
        'text',
        'timestamp with time zone'
    ]::text[] THEN
        RAISE EXCEPTION
            'FAIL: Unexpected receipt output types: %',
            v_types;
    END IF;

    RAISE NOTICE
        'PASS: Receipt has exactly three approved output fields';
END;
$test$;

\echo '=== TEST043 PHASE 2 COMPLETE ==='
