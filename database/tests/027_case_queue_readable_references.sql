-- MADZERA TEST 027
-- Migration 042: readable queue references and organisation isolation.
-- Requires employee-a and employee-c local fixtures and Migration 042.
-- Read-only assertions; transaction rolled back.

\set ON_ERROR_STOP on

BEGIN;

DO $test$
DECLARE
    v_a uuid;
    v_c uuid;
    v_org_a uuid;
    v_org_c uuid;
BEGIN
    SELECT auth_user_id, organisation_id INTO v_a, v_org_a
    FROM public.users
    WHERE email = 'employee-a@madzera-test.example'
      AND is_active = true;

    SELECT auth_user_id, organisation_id INTO v_c, v_org_c
    FROM public.users
    WHERE email = 'employee-c@madzera-test.example'
      AND is_active = true;

    IF v_a IS NULL OR v_c IS NULL OR v_org_a IS NULL
       OR v_org_c IS NULL OR v_org_a = v_org_c THEN
        RAISE EXCEPTION 'FAIL: Two distinct employee fixtures required';
    END IF;

    PERFORM set_config('madzera.test.employee_a', v_a::text, true);
    PERFORM set_config('madzera.test.employee_c', v_c::text, true);
    PERFORM set_config('madzera.test.org_a', v_org_a::text, true);
    PERFORM set_config('madzera.test.org_c', v_org_c::text, true);

    IF has_function_privilege('anon', 'public.get_case_queue()', 'EXECUTE') THEN
        RAISE EXCEPTION 'FAIL: Anonymous queue EXECUTE granted';
    END IF;

    IF NOT has_function_privilege(
        'authenticated', 'public.get_case_queue()', 'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'FAIL: Authenticated queue EXECUTE missing';
    END IF;

    RAISE NOTICE 'PASS: Queue function access grants';
END;
$test$;

-- Anonymous access must be denied by PostgreSQL.
SET LOCAL ROLE anon;

DO $test$
DECLARE
    v_denied boolean := false;
BEGIN
    BEGIN
        PERFORM * FROM public.get_case_queue();
    EXCEPTION WHEN insufficient_privilege THEN
        v_denied := true;
    END;

    IF NOT v_denied THEN
        RAISE EXCEPTION 'FAIL: Anonymous queue access accepted';
    END IF;

    RAISE NOTICE 'PASS: Anonymous queue access denied';
END;
$test$;

RESET ROLE;

-- Unlinked authenticated users must receive no tenant rows.
SELECT set_config(
    'request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000099',
    true
);

SET LOCAL ROLE authenticated;

DO $test$
BEGIN
    IF EXISTS (SELECT 1 FROM public.get_case_queue()) THEN
        RAISE EXCEPTION 'FAIL: Unlinked identity can see queue records';
    END IF;

    RAISE NOTICE 'PASS: Unlinked identity sees no queue records';
END;
$test$;

RESET ROLE;

-- Establish isolated team-scoped fixtures for the legacy reference test.
-- All records and grants are rolled back at the end of this test.

CREATE TEMP TABLE madzera_test_027_fixture (
    employee_label text PRIMARY KEY,
    organisation_id uuid NOT NULL,
    user_id uuid NOT NULL,
    team_id uuid,
    case_id uuid
) ON COMMIT DROP;

INSERT INTO madzera_test_027_fixture (
    employee_label,
    organisation_id,
    user_id
)
SELECT
    CASE
        WHEN u.email = 'employee-a@madzera-test.example' THEN 'A'
        ELSE 'C'
    END,
    u.organisation_id,
    u.id
FROM public.users u
WHERE u.email IN (
    'employee-a@madzera-test.example',
    'employee-c@madzera-test.example'
)
AND u.is_active = true
AND u.auth_user_id IS NOT NULL;

DO $test$
BEGIN
    IF (SELECT COUNT(*) FROM madzera_test_027_fixture) <> 2 THEN
        RAISE EXCEPTION 'FAIL: Test 027 employee fixtures incomplete';
    END IF;
END;
$test$;

WITH created AS (
    INSERT INTO public.teams (organisation_id, name)
    SELECT
        organisation_id,
        'TEST027 REFERENCE TEAM ' || employee_label
    FROM madzera_test_027_fixture
    RETURNING id, organisation_id
)
UPDATE madzera_test_027_fixture f
SET team_id = t.id
FROM created t
WHERE t.organisation_id = f.organisation_id;

WITH created AS (
    INSERT INTO public.cases (
        organisation_id,
        assigned_team_id,
        title,
        source
    )
    SELECT
        organisation_id,
        team_id,
        'TEST027 REFERENCE CASE ' || employee_label,
        'manual'
    FROM madzera_test_027_fixture
    RETURNING id, assigned_team_id
)
UPDATE madzera_test_027_fixture f
SET case_id = c.id
FROM created c
WHERE c.assigned_team_id = f.team_id;

INSERT INTO public.team_permission_grants (
    organisation_id,
    team_id,
    user_id,
    permission_type
)
SELECT
    organisation_id,
    team_id,
    user_id,
    'work'
FROM madzera_test_027_fixture;

DO $test$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM madzera_test_027_fixture
        WHERE team_id IS NULL OR case_id IS NULL
    ) THEN
        RAISE EXCEPTION 'FAIL: Test 027 team fixtures incomplete';
    END IF;

    RAISE NOTICE 'PASS: Temporary team-scoped queue fixtures established';
END;
$test$;

-- Capture each employee's authorised RPC output.
-- Direct case-table access is intentionally unavailable to authenticated users.
CREATE TEMP TABLE madzera_test_027_queue (
    employee_label text NOT NULL,
    case_id uuid NOT NULL,
    case_reference text,
    customer_id uuid,
    customer_reference text,
    customer_name text
) ON COMMIT DROP;

-- Permit authenticated test sessions to insert RPC results into this
-- transaction-local test table. No application-table grants are changed.
GRANT INSERT ON madzera_test_027_queue TO authenticated;

SELECT set_config(
    'request.jwt.claim.sub',
    current_setting('madzera.test.employee_a'),
    true
);

SET LOCAL ROLE authenticated;

INSERT INTO madzera_test_027_queue
SELECT 'A', q.case_id, q.case_reference, q.customer_id,
       q.customer_reference, q.customer_name
FROM public.get_case_queue() q;

RESET ROLE;

SELECT set_config(
    'request.jwt.claim.sub',
    current_setting('madzera.test.employee_c'),
    true
);

SET LOCAL ROLE authenticated;

INSERT INTO madzera_test_027_queue
SELECT 'C', q.case_id, q.case_reference, q.customer_id,
       q.customer_reference, q.customer_name
FROM public.get_case_queue() q;

RESET ROLE;

-- Privileged assertions compare captured RPC results with source tables.
DO $test$
DECLARE
    v_label text;
    v_org uuid;
    v_count integer;
BEGIN
    FOR v_label, v_org IN
        SELECT 'A', current_setting('madzera.test.org_a')::uuid
        UNION ALL
        SELECT 'C', current_setting('madzera.test.org_c')::uuid
    LOOP
        SELECT count(*) INTO v_count
        FROM madzera_test_027_queue
        WHERE employee_label = v_label;

        IF v_count = 0 THEN
            RAISE EXCEPTION 'FAIL: Employee % has no queue cases', v_label;
        END IF;

        IF EXISTS (
            SELECT 1
            FROM madzera_test_027_queue q
            LEFT JOIN public.cases c ON c.id = q.case_id
            WHERE q.employee_label = v_label
              AND (
                  c.id IS NULL
                  OR c.organisation_id <> v_org
                  OR q.case_reference IS DISTINCT FROM c.case_reference
                  OR q.case_reference !~ '^CAS[0-9]{10}$'
                  OR q.customer_id IS DISTINCT FROM c.customer_id
                  OR (
                      c.customer_id IS NULL
                      AND (
                          q.customer_reference IS NOT NULL
                          OR q.customer_name IS NOT NULL
                      )
                  )
                  OR (
                      c.customer_id IS NOT NULL
                      AND NOT EXISTS (
                          SELECT 1
                          FROM public.customers customer
                          WHERE customer.id = c.customer_id
                            AND customer.organisation_id = c.organisation_id
                            AND q.customer_reference =
                                customer.customer_reference
                            AND q.customer_name = customer.name::text
                            AND q.customer_reference ~ '^CUS[0-9]{6}$'
                      )
                  )
              )
        ) THEN
            RAISE EXCEPTION
                'FAIL: Employee % queue references or tenant mismatch',
                v_label;
        END IF;

        IF v_count <> (
            SELECT COUNT(*)
            FROM public.cases c
            JOIN public.team_permission_grants g
              ON g.team_id = c.assigned_team_id
             AND g.organisation_id = c.organisation_id
             AND g.permission_type = 'work'
            JOIN madzera_test_027_fixture f
              ON f.user_id = g.user_id
             AND f.organisation_id = g.organisation_id
            WHERE f.employee_label = v_label
              AND c.organisation_id = v_org
        ) THEN
            RAISE EXCEPTION
                'FAIL: Employee % team-scoped queue count mismatch',
                v_label;
        END IF;

        -- Compare actual and authorised case IDs in both directions.
        -- Equal counts alone cannot detect swapped or leaked case rows.
        IF EXISTS (
            SELECT actual.case_id
            FROM madzera_test_027_queue actual
            WHERE actual.employee_label = v_label

            EXCEPT

            SELECT c.id
            FROM public.cases c
            JOIN public.team_permission_grants g
              ON g.team_id = c.assigned_team_id
             AND g.organisation_id = c.organisation_id
             AND g.permission_type = 'work'
            JOIN madzera_test_027_fixture f
              ON f.user_id = g.user_id
             AND f.organisation_id = g.organisation_id
            WHERE f.employee_label = v_label
              AND c.organisation_id = v_org
        ) OR EXISTS (
            SELECT c.id
            FROM public.cases c
            JOIN public.team_permission_grants g
              ON g.team_id = c.assigned_team_id
             AND g.organisation_id = c.organisation_id
             AND g.permission_type = 'work'
            JOIN madzera_test_027_fixture f
              ON f.user_id = g.user_id
             AND f.organisation_id = g.organisation_id
            WHERE f.employee_label = v_label
              AND c.organisation_id = v_org

            EXCEPT

            SELECT actual.case_id
            FROM madzera_test_027_queue actual
            WHERE actual.employee_label = v_label
        ) THEN
            RAISE EXCEPTION
                'FAIL: Employee % queue case IDs differ from authorised cases',
                v_label;
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM madzera_test_027_queue q
            JOIN madzera_test_027_fixture f
              ON f.employee_label = q.employee_label
             AND f.case_id = q.case_id
            WHERE q.employee_label = v_label
        ) THEN
            RAISE EXCEPTION
                'FAIL: Employee % cannot see authorised reference fixture',
                v_label;
        END IF;

        RAISE NOTICE
            'PASS: Employee % has % correctly scoped cases with valid references',
            v_label, v_count;
    END LOOP;
END;
$test$;

ROLLBACK;
