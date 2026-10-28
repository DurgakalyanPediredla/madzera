-- MADZERA TEST 044
-- Team-Scoped Operational Case Queue Security
--
-- STATUS: DRAFT - FIXTURE PHASE ONLY.
--
-- Requires migration 066 inside an outer rollback-only transaction.
-- The outer test runner owns BEGIN and ROLLBACK.
-- Never run independently against production.

\echo '=== TEST044: SELECT AUTHENTICATED EMPLOYEE FIXTURES ==='

CREATE TEMP TABLE test044_fixture (
    organisation_a uuid NOT NULL,
    employee_a uuid NOT NULL,
    auth_a uuid NOT NULL,
    colleague_a uuid NOT NULL,
    auth_colleague uuid NOT NULL,
    organisation_b uuid NOT NULL,
    employee_b uuid NOT NULL,
    auth_b uuid NOT NULL,
    team_a uuid,
    team_other uuid,
    team_b uuid,
    case_a uuid,
    case_other uuid,
    case_b uuid
) ON COMMIT DROP;

GRANT SELECT ON test044_fixture TO authenticated;

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
INSERT INTO test044_fixture (
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
    IF (SELECT COUNT(*) FROM test044_fixture) <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Required authenticated identities unavailable';
    END IF;

    RAISE NOTICE
        'PASS: Multi-organisation authenticated identities selected';
END;
$test$;

\echo '=== TEST044: CREATE ISOLATED TEAMS ==='

WITH created AS (
    INSERT INTO public.teams (organisation_id, name)
    SELECT organisation_a, 'TEST044 TEAM A'
    FROM test044_fixture
    RETURNING id, organisation_id
)
UPDATE test044_fixture f
SET team_a = t.id
FROM created t
WHERE f.organisation_a = t.organisation_id;

WITH created AS (
    INSERT INTO public.teams (organisation_id, name)
    SELECT organisation_a, 'TEST044 OTHER TEAM'
    FROM test044_fixture
    RETURNING id, organisation_id
)
UPDATE test044_fixture f
SET team_other = t.id
FROM created t
WHERE f.organisation_a = t.organisation_id;

WITH created AS (
    INSERT INTO public.teams (organisation_id, name)
    SELECT organisation_b, 'TEST044 FOREIGN TEAM'
    FROM test044_fixture
    RETURNING id, organisation_id
)
UPDATE test044_fixture f
SET team_b = t.id
FROM created t
WHERE f.organisation_b = t.organisation_id;

\echo '=== TEST044: CREATE ISOLATED CASES ==='

WITH created AS (
    INSERT INTO public.cases (
        organisation_id,
        assigned_team_id,
        title,
        source
    )
    SELECT
        organisation_a,
        team_a,
        'TEST044 TEAM A CASE',
        'manual'
    FROM test044_fixture
    RETURNING id, assigned_team_id
)
UPDATE test044_fixture f
SET case_a = c.id
FROM created c
WHERE f.team_a = c.assigned_team_id;

WITH created AS (
    INSERT INTO public.cases (
        organisation_id,
        assigned_team_id,
        title,
        source
    )
    SELECT
        organisation_a,
        team_other,
        'TEST044 OTHER TEAM CASE',
        'manual'
    FROM test044_fixture
    RETURNING id, assigned_team_id
)
UPDATE test044_fixture f
SET case_other = c.id
FROM created c
WHERE f.team_other = c.assigned_team_id;

WITH created AS (
    INSERT INTO public.cases (
        organisation_id,
        assigned_team_id,
        title,
        source
    )
    SELECT
        organisation_b,
        team_b,
        'TEST044 FOREIGN CASE',
        'manual'
    FROM test044_fixture
    RETURNING id, assigned_team_id
)
UPDATE test044_fixture f
SET case_b = c.id
FROM created c
WHERE f.team_b = c.assigned_team_id;

\echo '=== TEST044: ESTABLISH MEMBERSHIP AND GRANTS ==='

INSERT INTO public.team_members (
    organisation_id,
    team_id,
    user_id
)
SELECT organisation_a, team_a, colleague_a
FROM test044_fixture;

INSERT INTO public.team_permission_grants (
    organisation_id,
    team_id,
    user_id,
    permission_type
)
SELECT organisation_a, team_a, employee_a, 'work'
FROM test044_fixture;

INSERT INTO public.team_permission_grants (
    organisation_id,
    team_id,
    user_id,
    permission_type
)
SELECT organisation_a, team_a, colleague_a, 'submit'
FROM test044_fixture;

INSERT INTO public.team_permission_grants (
    organisation_id,
    team_id,
    user_id,
    permission_type
)
SELECT organisation_a, team_a, colleague_a, 'manage'
FROM test044_fixture;

INSERT INTO public.team_permission_grants (
    organisation_id,
    team_id,
    user_id,
    permission_type
)
SELECT organisation_b, team_b, employee_b, 'work'
FROM test044_fixture;

\echo '=== TEST044: VERIFY FIXTURE INTEGRITY ==='

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;

    IF f.team_a IS NULL
       OR f.team_other IS NULL
       OR f.team_b IS NULL
       OR f.case_a IS NULL
       OR f.case_other IS NULL
       OR f.case_b IS NULL THEN
        RAISE EXCEPTION
            'FAIL: Missing team or case fixture';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM public.cases c
        JOIN test044_fixture x
          ON c.id IN (x.case_a, x.case_other, x.case_b)
        JOIN public.teams t
          ON t.id = c.assigned_team_id
         AND t.organisation_id = c.organisation_id
    ) <> 3 THEN
        RAISE EXCEPTION
            'FAIL: Team-scoped case fixtures invalid';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.team_permission_grants g
        WHERE (
            g.user_id = f.colleague_a
            AND g.team_id = f.team_a
            AND g.permission_type = 'work'
        ) OR (
            g.user_id = f.employee_a
            AND g.team_id = f.team_other
            AND g.permission_type = 'work'
        )
    ) THEN
        RAISE EXCEPTION
            'FAIL: Unexpected cross-team work grant';
    END IF;

    RAISE NOTICE
        'PASS: Isolated teams, cases, memberships and grants established';
END;
$test$;

\echo '=== TEST044: AUTHORISED WORKER QUEUE ==='

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test044_fixture),
    TRUE
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
    v_count integer;
BEGIN
    IF current_user <> 'authenticated' THEN
        RAISE EXCEPTION
            'FAIL: Worker test is not authenticated';
    END IF;

    SELECT * INTO STRICT f FROM test044_fixture;

    IF NOT public.has_team_permission(f.team_a, 'work') THEN
        RAISE EXCEPTION
            'FAIL: Worker lacks expected work permission';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM public.get_case_queue() q
    WHERE q.case_id = f.case_a
      AND q.assigned_team_id = f.team_a;

    IF v_count <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Authorised worker cannot see Team A case';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.get_case_queue() q
        WHERE q.case_id IN (f.case_other, f.case_b)
    ) THEN
        RAISE EXCEPTION
            'FAIL: Worker sees unauthorised team or organisation';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.get_case_queue() q
        WHERE q.assigned_team_id IS NULL
    ) THEN
        RAISE EXCEPTION
            'FAIL: Unassigned case visible in operational queue';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.get_case_queue() q
        WHERE q.case_id = f.case_a
          AND (
              q.case_reference IS NULL
              OR q.case_reference = ''
          )
    ) THEN
        RAISE EXCEPTION
            'FAIL: Authorised case reference missing';
    END IF;

    RAISE NOTICE
        'PASS: Worker sees authorised case only';
END;
$test$;

RESET ROLE;

\echo '=== TEST044: SUBMIT AND MANAGE DO NOT IMPLY WORK ==='

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

    IF NOT public.has_team_permission(f.team_a, 'submit') THEN
        RAISE EXCEPTION
            'FAIL: Expected submit permission missing';
    END IF;

    IF NOT public.has_team_permission(f.team_a, 'manage') THEN
        RAISE EXCEPTION
            'FAIL: Expected manage permission missing';
    END IF;

    IF public.has_team_permission(f.team_a, 'work') THEN
        RAISE EXCEPTION
            'FAIL: Colleague unexpectedly has work permission';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.get_case_queue() q
        WHERE q.case_id IN (f.case_a, f.case_other, f.case_b)
    ) THEN
        RAISE EXCEPTION
            'FAIL: Non-worker can see protected test cases';
    END IF;

    RAISE NOTICE
        'PASS: Membership, submit and manage do not imply work';
END;
$test$;

RESET ROLE;

\echo '=== TEST044: FOREIGN ORGANISATION WORKER ==='

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_b::text FROM test044_fixture),
    TRUE
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
    v_count integer;
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;

    IF NOT public.has_team_permission(f.team_b, 'work') THEN
        RAISE EXCEPTION
            'FAIL: Foreign worker lacks expected work grant';
    END IF;

    SELECT COUNT(*)
    INTO v_count
    FROM public.get_case_queue() q
    WHERE q.case_id = f.case_b
      AND q.assigned_team_id = f.team_b;

    IF v_count <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Foreign worker cannot see own team case';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.get_case_queue() q
        WHERE q.case_id IN (f.case_a, f.case_other)
    ) THEN
        RAISE EXCEPTION
            'FAIL: Cross-organisation queue information leaked';
    END IF;

    RAISE NOTICE
        'PASS: Foreign worker sees own organisation only';
END;
$test$;

RESET ROLE;

\echo '=== TEST044: REVOKE WORK PERMISSION ==='

DO $test$
DECLARE
    f test044_fixture%ROWTYPE;
    v_deleted integer;
BEGIN
    SELECT * INTO STRICT f FROM test044_fixture;

    DELETE FROM public.team_permission_grants g
    WHERE g.organisation_id = f.organisation_a
      AND g.team_id = f.team_a
      AND g.user_id = f.employee_a
      AND g.permission_type = 'work';

    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    IF v_deleted <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Expected exactly one revoked work grant';
    END IF;

    RAISE NOTICE
        'PASS: Exactly one work permission revoked';
END;
$test$;

\echo '=== TEST044: VERIFY IMMEDIATE REVOCATION ==='

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

    IF public.has_team_permission(f.team_a, 'work') THEN
        RAISE EXCEPTION
            'FAIL: Revoked work permission remains effective';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.get_case_queue() q
        WHERE q.case_id = f.case_a
    ) THEN
        RAISE EXCEPTION
            'FAIL: Revoked worker retains operational visibility';
    END IF;

    RAISE NOTICE
        'PASS: Revocation immediately removes queue visibility';
END;
$test$;

RESET ROLE;

\echo '=== TEST044: VERIFY ANONYMOUS EXECUTION DENIED ==='

DO $test$
BEGIN
    IF has_function_privilege(
        'anon',
        'public.get_case_queue()',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'FAIL: Anonymous role has queue execution privilege';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        CROSS JOIN LATERAL aclexplode(
            COALESCE(
                p.proacl,
                acldefault('f', p.proowner)
            )
        ) acl
        WHERE p.oid = 'public.get_case_queue()'::regprocedure
          AND acl.grantee = 0
          AND acl.privilege_type = 'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'FAIL: PUBLIC has queue execution privilege';
    END IF;

    RAISE NOTICE
        'PASS: Anonymous and PUBLIC queue execution denied';
END;
$test$;

\echo '=== TEST044: VERIFY UNLINKED AUTHENTICATED IDENTITY ==='

SELECT set_config(
    'request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000044',
    TRUE
);

SET LOCAL ROLE authenticated;

DO $test$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.get_case_queue()
    ) THEN
        RAISE EXCEPTION
            'FAIL: Unlinked authenticated identity sees queue rows';
    END IF;

    RAISE NOTICE
        'PASS: Unlinked authenticated identity sees no queue rows';
END;
$test$;

RESET ROLE;

\echo '=== TEST044: VERIFY QUEUE SECURITY TEST COMPLETE ==='

DO $test$
BEGIN
    RAISE NOTICE
        'PASS: TEST044 behavioural assertions completed';
END;
$test$;
