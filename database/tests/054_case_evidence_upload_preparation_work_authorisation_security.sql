-- MADZERA TEST 053
-- Completed evidence download-path work-authorisation regression.
-- Local rollback-only test; derived from Test 052.

-- MADZERA TEST 048
-- Save/claim team-work authorisation regression
-- Rollback-only; derived from Test 046.

-- MADZERA TEST 046
-- Protected case-detail retrieval security regression
-- Rollback-only; derived from Test 045.

-- MADZERA TEST 045
-- Rollback-only case work helper regression
-- Derived from Test 042; original remains unchanged.

-- MADZERA TEST 042
-- Team Work Session Authorisation Security
--
-- Requires migrations 060-064.
-- Disposable local development database only.
-- All test-created data is rolled back.
--
-- Security objectives:
--   1. Explicit work permission required for session entry.
--   2. Submit/manage permissions do not imply work.
--   3. Cross-team and cross-organisation access denied.
--   4. Revocation immediately prevents operational access.
--   5. Existing lock ownership and exclusivity preserved.
--   6. Legitimate owners can release locks after revocation.
--   7. Rejected operations do not create locks or opening events.
--   8. Unassigned legacy cases fail closed.
--
-- Functional rollback-only security assertions implemented and executed.
-- Scope: case-session authorisation only; not a complete application security test.

\set ON_ERROR_STOP on

BEGIN;

-- Migration 067: Operational case work authorisation
--
-- Purpose:
-- Enforce current team-work permission throughout protected
-- employee case operations.
--
-- This initial section introduces a reusable authorisation helper.
-- Operational RPC replacements and Storage enforcement will follow
-- after separate review and rollback-only verification.
--
-- Security principles:
-- 1. Organisation-scoped access.
-- 2. Explicit team-work permission.
-- 3. Fail closed for unassigned cases.
-- 4. No implicit administrator or manage-permission bypass.
-- 5. No changes to existing exclusive lock mechanics.

CREATE OR REPLACE FUNCTION public.can_work_on_case(
    p_case_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT COALESCE(
        (
            SELECT public.has_team_permission(
                c.assigned_team_id,
                'work'
            )
            FROM public.cases AS c
            WHERE c.id = p_case_id
              AND c.organisation_id =
                  public.current_user_organisation_id()
              AND c.assigned_team_id IS NOT NULL
        ),
        FALSE
    );
$function$;

CREATE OR REPLACE FUNCTION public.get_locked_case_details(
    p_case_id UUID,
    p_lock_token UUID
)
RETURNS SETOF public.cases
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id UUID;
    v_organisation_id UUID;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL
       OR v_organisation_id IS NULL
       OR p_case_id IS NULL
       OR p_lock_token IS NULL
    THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT c.*
    FROM public.cases AS c
    INNER JOIN public.case_locks AS l
        ON l.case_id = c.id
       AND l.organisation_id = c.organisation_id
    WHERE c.id = p_case_id
      AND c.organisation_id = v_organisation_id
      AND l.locked_by_user_id = v_employee_id
      AND l.lock_token = p_lock_token
      AND l.expires_at > NOW()
      AND public.can_work_on_case(c.id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.save_employee_case_assignment(
    p_case_id uuid,
    p_lock_token uuid,
    p_expected_assigned_user_id uuid DEFAULT NULL,
    p_confirm_reassignment boolean DEFAULT FALSE
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
    v_lock public.case_locks%ROWTYPE;
    v_current_assignee uuid;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required'
            USING ERRCODE = '42501';
    END IF;

    IF p_case_id IS NULL OR p_lock_token IS NULL THEN
        RAISE EXCEPTION 'Valid case and lock token required'
            USING ERRCODE = '42501';
    END IF;

    -- Reuse the existing exclusive lock; do not modify its lifecycle.
    SELECT l.*
    INTO v_lock
    FROM public.case_locks AS l
    WHERE l.case_id = p_case_id
      AND l.organisation_id = v_organisation_id
    FOR UPDATE;

    IF NOT FOUND
       OR v_lock.locked_by_user_id IS DISTINCT FROM v_employee_id
       OR v_lock.lock_token IS DISTINCT FROM p_lock_token
       OR v_lock.expires_at <= clock_timestamp()
    THEN
        RAISE EXCEPTION 'Case lock invalid, expired, or not owned by employee'
            USING ERRCODE = '42501';
    END IF;

    -- Revalidate current team-work permission after lock validation.
    -- Revocation must take effect even while the lock remains active.
    IF public.can_work_on_case(p_case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    -- Serialize assignment changes and inspect the current responsibility.
    SELECT c.assigned_user_id
    INTO v_current_assignee
    FROM public.cases AS c
    WHERE c.id = p_case_id
      AND c.organisation_id = v_organisation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Case not found or access denied'
            USING ERRCODE = '42501';
    END IF;

    IF v_current_assignee IS DISTINCT FROM p_expected_assigned_user_id THEN
        RAISE EXCEPTION 'Case assignment changed; refresh before saving'
            USING ERRCODE = '40001';
    END IF;

    IF v_current_assignee IS NOT NULL
       AND v_current_assignee IS DISTINCT FROM v_employee_id
       AND p_confirm_reassignment IS NOT TRUE
    THEN
        RAISE EXCEPTION 'Explicit reassignment confirmation required'
            USING ERRCODE = '42501';
    END IF;

    IF v_lock.expires_at <= clock_timestamp() THEN
        RAISE EXCEPTION 'Case lock expired during save'
            USING ERRCODE = '42501';
    END IF;

    IF v_current_assignee IS DISTINCT FROM v_employee_id THEN
        UPDATE public.cases
        SET assigned_user_id = v_employee_id
        WHERE id = p_case_id
          AND organisation_id = v_organisation_id;
        -- The existing audit trigger records the assignment change.
    END IF;

    RETURN p_case_id;
END;
$function$;



REVOKE ALL ON FUNCTION public.can_work_on_case(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.can_work_on_case(uuid)
TO authenticated, service_role;


SET LOCAL statement_timeout = '60s';

CREATE TEMP TABLE test042_fixture (
    organisation_a uuid NOT NULL,
    employee_a uuid NOT NULL,
    auth_a uuid NOT NULL,
    colleague_a uuid NOT NULL,
    auth_colleague uuid NOT NULL,
    administrator_a uuid,
    auth_administrator uuid,
    organisation_b uuid NOT NULL,
    employee_b uuid NOT NULL,
    auth_b uuid NOT NULL,
    team_a uuid,
    team_other uuid,
    team_b uuid,
    case_a uuid,
    case_other uuid,
    case_b uuid,
    lock_token uuid
);

GRANT SELECT ON test042_fixture TO authenticated;

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
INSERT INTO test042_fixture (
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
    IF (SELECT COUNT(*) FROM test042_fixture) <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Required multi-organisation fixtures unavailable';
    END IF;

    RAISE NOTICE
        'PASS: Dynamic session security fixtures selected';
END;
$test$;


-- TEST042 TEMPORARY ADMINISTRATOR IDENTITY
-- Database-only synthetic identity; no password or confirmed email.
-- Both records are created within this transaction and rolled back.
-- This does not simulate a real Supabase signup or login.

WITH created_auth AS (
    INSERT INTO auth.users (
        id,
        aud,
        role,
        created_at,
        updated_at
    )
    VALUES (
        gen_random_uuid(),
        'authenticated',
        'authenticated',
        now(),
        now()
    )
    RETURNING id
),
created_employee AS (
    INSERT INTO public.users (
        organisation_id,
        email,
        full_name,
        role,
        is_active,
        auth_user_id
    )
    SELECT
        f.organisation_a,
        'test042-administrator@example.invalid',
        'TEST042 Temporary Organisation Administrator',
        'employee',
        TRUE,
        a.id
    FROM test042_fixture f
    CROSS JOIN created_auth a
    RETURNING id, auth_user_id
)
UPDATE test042_fixture f
SET administrator_a = e.id,
    auth_administrator = e.auth_user_id
FROM created_employee e;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test042_fixture;

    IF f.administrator_a IS NULL
       OR f.auth_administrator IS NULL THEN
        RAISE EXCEPTION
            'FAIL: Temporary administrator identity missing';
    END IF;

    IF f.administrator_a IN (
        f.employee_a,
        f.colleague_a,
        f.employee_b
    ) THEN
        RAISE EXCEPTION
            'FAIL: Administrator identity is not distinct';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.users u
        JOIN auth.users a
          ON a.id = u.auth_user_id
        WHERE u.id = f.administrator_a
          AND u.organisation_id = f.organisation_a
          AND u.is_active = TRUE
          AND u.auth_user_id = f.auth_administrator
          AND a.encrypted_password IS NULL
          AND a.email_confirmed_at IS NULL
    ) THEN
        RAISE EXCEPTION
            'FAIL: Administrator identity linkage invalid';
    END IF;

    RAISE NOTICE
        'PASS: Distinct rollback-only administrator identity created';
END;
$test$;

-- TEST042 CONTROLLED ADMINISTRATOR PROVISIONING
-- Use the existing privileged and audited initial-provisioning function.
-- The administrator has no implicit team work permission.

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
    v_result boolean;
BEGIN
    SELECT * INTO STRICT f FROM test042_fixture;

    v_result :=
        madzera_internal.provision_initial_organisation_admin(
            f.organisation_a,
            f.administrator_a,
            'TEST042 controlled temporary administrator provisioning'
        );

    IF v_result IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION
            'FAIL: Temporary administrator provisioning unsuccessful';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.organisation_administrators oa
        WHERE oa.organisation_id = f.organisation_a
          AND oa.user_id = f.administrator_a
    ) THEN
        RAISE EXCEPTION
            'FAIL: Temporary administrator assignment missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.permission_audit_events e
        WHERE e.organisation_id = f.organisation_a
          AND e.target_user_id = f.administrator_a
          AND e.permission_type = 'organisation_admin'
          AND e.action = 'granted'
          AND e.reason =
              'TEST042 controlled temporary administrator provisioning'
    ) THEN
        RAISE EXCEPTION
            'FAIL: Administrator provisioning audit event missing';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.team_permission_grants g
        WHERE g.user_id = f.administrator_a
          AND g.permission_type = 'work'
    ) THEN
        RAISE EXCEPTION
            'FAIL: Administrator unexpectedly received work permission';
    END IF;

    RAISE NOTICE
        'PASS: Separate administrator provisioned and audited without work permission';
END;
$test$;

-- Provision isolated test teams as postgres.
-- These fixtures exist only within the rollback transaction.

WITH created AS (
    INSERT INTO public.teams (organisation_id, name)
    SELECT organisation_a, 'TEST042 WORK TEAM'
    FROM test042_fixture
    RETURNING id, organisation_id
)
UPDATE test042_fixture f
SET team_a = created.id
FROM created
WHERE f.organisation_a = created.organisation_id;

WITH created AS (
    INSERT INTO public.teams (organisation_id, name)
    SELECT organisation_a, 'TEST042 OTHER TEAM'
    FROM test042_fixture
    RETURNING id, organisation_id
)
UPDATE test042_fixture f
SET team_other = created.id
FROM created
WHERE f.organisation_a = created.organisation_id;

WITH created AS (
    INSERT INTO public.teams (organisation_id, name)
    SELECT organisation_b, 'TEST042 FOREIGN TEAM'
    FROM test042_fixture
    RETURNING id, organisation_id
)
UPDATE test042_fixture f
SET team_b = created.id
FROM created
WHERE f.organisation_b = created.organisation_id;

-- Create isolated cases without modifying historical cases.

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
        'TEST042 AUTHORISED CASE',
        'manual'
    FROM test042_fixture
    RETURNING id, assigned_team_id
)
UPDATE test042_fixture f
SET case_a = created.id
FROM created
WHERE f.team_a = created.assigned_team_id;

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
        'TEST042 OTHER TEAM CASE',
        'manual'
    FROM test042_fixture
    RETURNING id, assigned_team_id
)
UPDATE test042_fixture f
SET case_other = created.id
FROM created
WHERE f.team_other = created.assigned_team_id;

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
        'TEST042 FOREIGN ORGANISATION CASE',
        'manual'
    FROM test042_fixture
    RETURNING id, assigned_team_id
)
UPDATE test042_fixture f
SET case_b = created.id
FROM created
WHERE f.team_b = created.assigned_team_id;

DO $test$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM test042_fixture
        WHERE team_a IS NULL
           OR team_other IS NULL
           OR team_b IS NULL
           OR case_a IS NULL
           OR case_other IS NULL
           OR case_b IS NULL
    ) THEN
        RAISE EXCEPTION 'FAIL: Team or case fixture missing';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM public.cases c
        JOIN test042_fixture f
          ON c.id IN (f.case_a, f.case_other, f.case_b)
        JOIN public.teams t
          ON t.id = c.assigned_team_id
         AND t.organisation_id = c.organisation_id
    ) <> 3 THEN
        RAISE EXCEPTION
            'FAIL: Test cases are not correctly team-scoped';
    END IF;

    RAISE NOTICE
        'PASS: Three organisation-scoped teams and cases created';
END;
$test$;

-- TEST042 ORGANISATION-SCOPED TEAM MEMBERSHIPS
-- Membership is independent of explicit submit/work permissions.
-- Colleague A belongs to a different team from the destination team.

INSERT INTO public.team_members (
    organisation_id,
    team_id,
    user_id
)
SELECT organisation_a, team_a, employee_a
FROM test042_fixture;

INSERT INTO public.team_members (
    organisation_id,
    team_id,
    user_id
)
SELECT organisation_a, team_other, colleague_a
FROM test042_fixture;

INSERT INTO public.team_members (
    organisation_id,
    team_id,
    user_id
)
SELECT organisation_b, team_b, employee_b
FROM test042_fixture;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test042_fixture;

    IF (
        SELECT COUNT(*)
        FROM public.team_members m
        WHERE
            (
                m.organisation_id = f.organisation_a
                AND m.team_id = f.team_a
                AND m.user_id = f.employee_a
            )
            OR
            (
                m.organisation_id = f.organisation_a
                AND m.team_id = f.team_other
                AND m.user_id = f.colleague_a
            )
            OR
            (
                m.organisation_id = f.organisation_b
                AND m.team_id = f.team_b
                AND m.user_id = f.employee_b
            )
    ) <> 3 THEN
        RAISE EXCEPTION
            'FAIL: Expected three organisation-scoped memberships';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.team_members m
        WHERE
            m.user_id = f.administrator_a
            OR (
                m.user_id = f.colleague_a
                AND m.team_id = f.team_a
            )
            OR (
                m.user_id = f.employee_a
                AND m.team_id = f.team_other
            )
    ) THEN
        RAISE EXCEPTION
            'FAIL: Unexpected team membership detected';
    END IF;

    RAISE NOTICE
        'PASS: Separate team memberships established without administrator membership';
END;
$test$;

-- TEST042 EXPLICIT TEAM PERMISSION FIXTURES
-- Employee A works Team A cases.
-- Colleague A submits to Team A without Team A work access.
-- Employee B represents the separate organisation's worker.
-- Organisation administrator has no implicit operational grant.

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
    'work'
FROM test042_fixture;

INSERT INTO public.team_permission_grants (
    organisation_id,
    team_id,
    user_id,
    permission_type
)
SELECT
    organisation_a,
    team_a,
    colleague_a,
    'submit'
FROM test042_fixture;

INSERT INTO public.team_permission_grants (
    organisation_id,
    team_id,
    user_id,
    permission_type
)
SELECT
    organisation_b,
    team_b,
    employee_b,
    'work'
FROM test042_fixture;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test042_fixture;

    IF (
        SELECT COUNT(*)
        FROM public.team_permission_grants g
        WHERE
            (
                g.organisation_id = f.organisation_a
                AND g.team_id = f.team_a
                AND g.user_id = f.employee_a
                AND g.permission_type = 'work'
            )
            OR
            (
                g.organisation_id = f.organisation_a
                AND g.team_id = f.team_a
                AND g.user_id = f.colleague_a
                AND g.permission_type = 'submit'
            )
            OR
            (
                g.organisation_id = f.organisation_b
                AND g.team_id = f.team_b
                AND g.user_id = f.employee_b
                AND g.permission_type = 'work'
            )
    ) <> 3 THEN
        RAISE EXCEPTION
            'FAIL: Expected three explicit team grants';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.team_permission_grants g
        WHERE
            (
                g.user_id = f.colleague_a
                AND g.permission_type = 'work'
            )
            OR
            (
                g.user_id = f.administrator_a
                AND g.permission_type = 'work'
            )
            OR
            (
                g.user_id = f.employee_a
                AND g.team_id = f.team_other
                AND g.permission_type = 'work'
            )
    ) THEN
        RAISE EXCEPTION
            'FAIL: Unexpected operational permission detected';
    END IF;

    RAISE NOTICE
        'PASS: Worker, cross-team submitter and administrator permissions isolated';
END;
$test$;

-- TEST042 AUTHORISED CASE SESSION OPEN
-- Run the operational RPC as authenticated.
-- Verify database state separately after restoring postgres.

CREATE TEMP TABLE test042_session_result (
    acquired BOOLEAN,
    lock_expires_at TIMESTAMPTZ,
    lock_token UUID
) ON COMMIT DROP;

GRANT INSERT ON test042_session_result TO authenticated;

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test042_fixture),
    true
);

CREATE OR REPLACE FUNCTION public.update_employee_case(
    p_case_id uuid,
    p_lock_token uuid,
    p_status text DEFAULT NULL,
    p_priority text DEFAULT NULL,
    p_assigned_team_id uuid DEFAULT NULL,
    p_assigned_user_id uuid DEFAULT NULL,
    p_clear_team boolean DEFAULT FALSE,
    p_clear_user boolean DEFAULT FALSE
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
    v_lock public.case_locks%ROWTYPE;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required'
            USING ERRCODE = '42501';
    END IF;

    IF p_case_id IS NULL OR p_lock_token IS NULL THEN
        RAISE EXCEPTION 'Valid case and lock token required'
            USING ERRCODE = '42501';
    END IF;

    IF (p_clear_team AND p_assigned_team_id IS NOT NULL)
       OR (p_clear_user AND p_assigned_user_id IS NOT NULL)
    THEN
        RAISE EXCEPTION 'Cannot assign and clear the same field'
            USING ERRCODE = '22023';
    END IF;

    -- Lock the lock record for this transaction.
    SELECT l.*
    INTO v_lock
    FROM public.case_locks AS l
    WHERE l.case_id = p_case_id
      AND l.organisation_id = v_organisation_id
    FOR UPDATE;

    IF NOT FOUND
       OR v_lock.locked_by_user_id IS DISTINCT FROM v_employee_id
       OR v_lock.lock_token IS DISTINCT FROM p_lock_token
       OR v_lock.expires_at <= clock_timestamp()
    THEN
        RAISE EXCEPTION 'Case lock invalid, expired, or not owned by employee'
            USING ERRCODE = '42501';
    END IF;

    -- Require current work permission, not merely an existing lock.
    IF public.can_work_on_case(p_case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    -- Team transfers require a separate authorised workflow.
    -- Never allow this general-purpose RPC to remove the destination team.
    IF p_clear_team IS TRUE THEN
        RAISE EXCEPTION 'Clearing destination team is not permitted'
            USING ERRCODE = '42501';
    END IF;

    IF p_assigned_team_id IS NOT NULL
       AND p_assigned_team_id IS DISTINCT FROM (
           SELECT c.assigned_team_id
           FROM public.cases AS c
           WHERE c.id = p_case_id
             AND c.organisation_id = v_organisation_id
       )
    THEN
        RAISE EXCEPTION 'Team transfer requires separate authorisation'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.cases AS c
    SET
        status = COALESCE(p_status, c.status),
        priority = COALESCE(p_priority, c.priority),
        assigned_team_id = CASE
            WHEN p_clear_team THEN NULL
            ELSE COALESCE(p_assigned_team_id, c.assigned_team_id)
        END,
        assigned_user_id = CASE
            WHEN p_clear_user THEN NULL
            ELSE COALESCE(p_assigned_user_id, c.assigned_user_id)
        END
    WHERE c.id = p_case_id
      AND c.organisation_id = v_organisation_id
      AND v_lock.expires_at > clock_timestamp();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Case not found or access denied'
            USING ERRCODE = '42501';
    END IF;

    RETURN p_case_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.save_employee_case_comment(
    p_case_id uuid,
    p_lock_token uuid,
    p_body text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
    v_lock public.case_locks%ROWTYPE;
    v_comment_id uuid;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required'
            USING ERRCODE = '42501';
    END IF;

    IF p_case_id IS NULL OR p_lock_token IS NULL THEN
        RAISE EXCEPTION 'Valid case and lock token required'
            USING ERRCODE = '42501';
    END IF;

    IF p_body IS NULL
       OR length(btrim(p_body)) = 0
       OR length(p_body) > 10000
    THEN
        RAISE EXCEPTION 'Comment must contain 1 to 10000 characters'
            USING ERRCODE = '22023';
    END IF;

    SELECT l.*
    INTO v_lock
    FROM public.case_locks AS l
    WHERE l.case_id = p_case_id
      AND l.organisation_id = v_organisation_id
    FOR UPDATE;

    IF NOT FOUND
       OR v_lock.locked_by_user_id IS DISTINCT FROM v_employee_id
       OR v_lock.lock_token IS DISTINCT FROM p_lock_token
       OR v_lock.expires_at <= clock_timestamp()
    THEN
        RAISE EXCEPTION 'Case lock invalid, expired, or not owned by employee'
            USING ERRCODE = '42501';
    END IF;

    -- A valid existing lock does not override revoked work permission.
    IF public.can_work_on_case(p_case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    PERFORM 1
    FROM public.cases AS c
    WHERE c.id = p_case_id
      AND c.organisation_id = v_organisation_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Case not found or access denied'
            USING ERRCODE = '42501';
    END IF;

    IF v_lock.expires_at <= clock_timestamp() THEN
        RAISE EXCEPTION 'Case lock expired during save'
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.comments (
        case_id,
        organisation_id,
        author_user_id,
        body,
        visibility
    )
    VALUES (
        p_case_id,
        v_organisation_id,
        v_employee_id,
        btrim(p_body),
        'internal'
    )
    RETURNING id INTO v_comment_id;

    RETURN v_comment_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_employee_case_comments(
    p_case_id uuid,
    p_lock_token uuid
)
RETURNS TABLE (
    id uuid,
    body text,
    created_at timestamptz,
    author_user_id uuid,
    author_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required'
            USING ERRCODE = '42501';
    END IF;

    IF p_case_id IS NULL OR p_lock_token IS NULL THEN
        RAISE EXCEPTION 'Valid case and lock token required'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases AS c
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
    ) THEN
        RAISE EXCEPTION 'Case not found or access denied'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks AS l
        WHERE l.case_id = p_case_id
          AND l.organisation_id = v_organisation_id
          AND l.locked_by_user_id = v_employee_id
          AND l.lock_token = p_lock_token
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'Case lock invalid, expired, or not owned by employee'
            USING ERRCODE = '42501';
    END IF;

    -- Existing lock ownership does not override revoked work access.
    IF public.can_work_on_case(p_case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        cm.id,
        cm.body,
        cm.created_at,
        cm.author_user_id,
        COALESCE(u.full_name::text, 'Unknown employee') AS author_name
    FROM public.comments AS cm
    LEFT JOIN public.users AS u
      ON u.id = cm.author_user_id
     AND u.organisation_id = cm.organisation_id
    WHERE cm.case_id = p_case_id
      AND cm.organisation_id = v_organisation_id
      AND cm.visibility = 'internal'
    ORDER BY cm.created_at ASC, cm.id ASC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_employee_case_audit_history(
    p_case_id uuid,
    p_lock_token uuid
)
RETURNS TABLE (
    id uuid,
    event_type text,
    created_at timestamptz,
    actor_user_id uuid,
    actor_name text,
    from_status text,
    to_status text,
    from_team_name text,
    to_team_name text,
    from_user_name text,
    to_user_name text,
    details text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required'
            USING ERRCODE = '42501';
    END IF;

    IF p_case_id IS NULL OR p_lock_token IS NULL THEN
        RAISE EXCEPTION 'Valid case and lock token required'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases AS c
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
    ) THEN
        RAISE EXCEPTION 'Case not found or access denied'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks AS l
        WHERE l.case_id = p_case_id
          AND l.organisation_id = v_organisation_id
          AND l.locked_by_user_id = v_employee_id
          AND l.lock_token = p_lock_token
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'Case lock invalid, expired, or not owned by employee'
            USING ERRCODE = '42501';
    END IF;

    -- Existing lock ownership does not override revoked work access.
    IF public.can_work_on_case(p_case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        ev.id,
        ev.event_type::text,
        ev.created_at,
        ev.actor_user_id,
        COALESCE(actor.full_name::text, 'System / unknown') AS actor_name,
        ev.from_status::text,
        ev.to_status::text,
        previous_team.name::text AS from_team_name,
        next_team.name::text AS to_team_name,
        previous_user.full_name::text AS from_user_name,
        next_user.full_name::text AS to_user_name,
        ev.details
    FROM public.case_events AS ev
    LEFT JOIN public.users AS actor
      ON actor.id = ev.actor_user_id
     AND actor.organisation_id = ev.organisation_id
    LEFT JOIN public.teams AS previous_team
      ON previous_team.id = ev.from_team_id
     AND previous_team.organisation_id = ev.organisation_id
    LEFT JOIN public.teams AS next_team
      ON next_team.id = ev.to_team_id
     AND next_team.organisation_id = ev.organisation_id
    LEFT JOIN public.users AS previous_user
      ON previous_user.id = ev.from_user_id
     AND previous_user.organisation_id = ev.organisation_id
    LEFT JOIN public.users AS next_user
      ON next_user.id = ev.to_user_id
     AND next_user.organisation_id = ev.organisation_id
    WHERE ev.case_id = p_case_id
      AND ev.organisation_id = v_organisation_id
    ORDER BY ev.created_at DESC, ev.id DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_employee_case_evidence(
    p_case_id uuid,
    p_lock_token uuid
)
RETURNS TABLE (
    id uuid,
    comment_id uuid,
    file_name text,
    file_type text,
    file_size_bytes bigint,
    created_at timestamptz,
    uploaded_by_user_id uuid,
    uploaded_by_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL
       OR v_organisation_id IS NULL
       OR p_case_id IS NULL
       OR p_lock_token IS NULL
    THEN
        RAISE EXCEPTION 'Authenticated employee and case lock required'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases AS c
        JOIN public.case_locks AS l
          ON l.case_id = c.id
         AND l.organisation_id = c.organisation_id
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
          AND l.locked_by_user_id = v_employee_id
          AND l.lock_token = p_lock_token
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'Case access denied or lock expired'
            USING ERRCODE = '42501';
    END IF;

    -- Existing lock ownership does not override revoked work access.
    IF public.can_work_on_case(p_case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        a.id,
        a.comment_id,
        a.file_name::text,
        a.file_type::text,
        a.file_size_bytes,
        a.created_at,
        a.uploaded_by_user_id,
        COALESCE(u.full_name::text, 'Unknown employee')
    FROM public.attachments AS a
    LEFT JOIN public.users AS u
      ON u.id = a.uploaded_by_user_id
     AND u.organisation_id = a.organisation_id
    WHERE a.case_id = p_case_id
      AND a.organisation_id = v_organisation_id
      AND a.visibility = 'internal'
    ORDER BY a.created_at ASC, a.id ASC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_employee_case_evidence_download_path(
    p_attachment_id uuid,
    p_case_id uuid,
    p_lock_token uuid
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
    v_storage_path text;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL
       OR v_organisation_id IS NULL
       OR p_attachment_id IS NULL
       OR p_case_id IS NULL
       OR p_lock_token IS NULL
    THEN
        RAISE EXCEPTION 'Authenticated employee and case lock required'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases AS c
        JOIN public.case_locks AS l
          ON l.case_id = c.id
         AND l.organisation_id = c.organisation_id
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
          AND l.locked_by_user_id = v_employee_id
          AND l.lock_token = p_lock_token
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'Case access denied or lock expired'
            USING ERRCODE = '42501';
    END IF;

    -- Existing lock ownership does not override revoked work access.
    IF public.can_work_on_case(p_case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    SELECT a.storage_reference
    INTO v_storage_path
    FROM public.attachments AS a
    JOIN public.case_evidence_upload_reservations AS r
      ON r.storage_path = a.storage_reference
     AND r.case_id = a.case_id
     AND r.organisation_id = a.organisation_id
    WHERE a.id = p_attachment_id
      AND a.case_id = p_case_id
      AND a.organisation_id = v_organisation_id
      AND a.visibility = 'internal'
      AND r.status = 'completed';

    IF v_storage_path IS NULL THEN
        RAISE EXCEPTION 'Evidence attachment not found'
            USING ERRCODE = '42501';
    END IF;

    RETURN v_storage_path;
END;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_case_evidence_upload(
    p_case_id uuid,
    p_lock_token uuid,
    p_file_name text,
    p_file_type text,
    p_file_size_bytes bigint
)
RETURNS TABLE (
    reservation_id uuid,
    storage_path text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
    v_lock public.case_locks%ROWTYPE;
    v_reservation_id uuid;
    v_storage_path text;
    v_file_name text;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required'
            USING ERRCODE = '42501';
    END IF;

    IF p_case_id IS NULL OR p_lock_token IS NULL THEN
        RAISE EXCEPTION 'Valid case and lock token required'
            USING ERRCODE = '42501';
    END IF;

    v_file_name := btrim(p_file_name);

    IF v_file_name IS NULL
       OR length(v_file_name) = 0
       OR length(v_file_name) > 255
       OR v_file_name ~ '[/\\]'
       OR v_file_name ~ '[[:cntrl:]]'
    THEN
        RAISE EXCEPTION 'Invalid evidence file name'
            USING ERRCODE = '22023';
    END IF;

    IF p_file_type IS NULL
       OR p_file_type NOT IN (
           'application/pdf',
           'image/jpeg',
           'image/png'
       )
    THEN
        RAISE EXCEPTION 'Unsupported evidence file type'
            USING ERRCODE = '22023';
    END IF;

    IF p_file_size_bytes IS NULL
       OR p_file_size_bytes < 1
       OR p_file_size_bytes > 10485760
    THEN
        RAISE EXCEPTION 'Evidence file exceeds permitted size'
            USING ERRCODE = '22023';
    END IF;

    SELECT l.*
    INTO v_lock
    FROM public.case_locks AS l
    WHERE l.case_id = p_case_id
      AND l.organisation_id = v_organisation_id
    FOR UPDATE;

    IF NOT FOUND
       OR v_lock.locked_by_user_id IS DISTINCT FROM v_employee_id
       OR v_lock.lock_token IS DISTINCT FROM p_lock_token
       OR v_lock.expires_at <= clock_timestamp()
    THEN
        RAISE EXCEPTION 'Case lock invalid, expired, or not owned by employee'
            USING ERRCODE = '42501';
    END IF;

    PERFORM 1
    FROM public.cases AS c
    WHERE c.id = p_case_id
      AND c.organisation_id = v_organisation_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Case not found or access denied'
            USING ERRCODE = '42501';
    END IF;

    -- A valid existing lock does not override revoked team-work access.
    IF public.can_work_on_case(p_case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    -- The case-lock row is already locked FOR UPDATE above.
    -- Serialise reservation creation and reject unresolved uploads.
    IF EXISTS (
        SELECT 1
        FROM public.case_evidence_upload_reservations AS r
        WHERE r.case_id = p_case_id
          AND r.organisation_id = v_organisation_id
          AND r.employee_id = v_employee_id
          AND r.status = 'pending'
    ) THEN
        RAISE EXCEPTION
            'An earlier evidence upload requires recovery review'
            USING ERRCODE = '23505';
    END IF;

    v_reservation_id := gen_random_uuid();

    v_storage_path :=
        v_organisation_id::text || '/' ||
        p_case_id::text || '/' ||
        v_reservation_id::text;

    INSERT INTO public.case_evidence_upload_reservations (
        id,
        case_id,
        organisation_id,
        employee_id,
        storage_path,
        file_name,
        file_type,
        file_size_bytes,
        expires_at
    )
    VALUES (
        v_reservation_id,
        p_case_id,
        v_organisation_id,
        v_employee_id,
        v_storage_path,
        v_file_name,
        p_file_type,
        p_file_size_bytes,
        clock_timestamp() + interval '10 minutes'
    );

    RETURN QUERY
    SELECT v_reservation_id, v_storage_path;
END;
$function$;

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
BEGIN
    IF current_user <> 'authenticated' THEN
        RAISE EXCEPTION
            'FAIL: Session RPC is not running as authenticated';
    END IF;

    SELECT * INTO STRICT f FROM test042_fixture;

    INSERT INTO test042_session_result (
        acquired,
        lock_expires_at,
        lock_token
    )
    SELECT
        s.acquired,
        s.lock_expires_at,
        s.lock_token
    FROM public.open_case_session(f.case_a) AS s;
END;
$test$;

RESET ROLE;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
    v_acquired BOOLEAN;
    v_expires_at TIMESTAMPTZ;
    v_lock_token UUID;
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION
            'FAIL: Privileged verification role not restored';
    END IF;

    SELECT * INTO STRICT f FROM test042_fixture;

    IF (SELECT COUNT(*) FROM test042_session_result) <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Session RPC returned unexpected row count';
    END IF;

    SELECT
        acquired,
        lock_expires_at,
        lock_token
    INTO STRICT
        v_acquired,
        v_expires_at,
        v_lock_token
    FROM test042_session_result;

    IF v_acquired IS DISTINCT FROM TRUE
       OR v_expires_at IS NULL
       OR v_lock_token IS NULL THEN
        RAISE EXCEPTION
            'FAIL: Authorised employee did not acquire case session';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks l
        WHERE l.case_id = f.case_a
          AND l.organisation_id = f.organisation_a
          AND l.locked_by_user_id = f.employee_a
          AND l.lock_token = v_lock_token
          AND l.expires_at = v_expires_at
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION
            'FAIL: Acquired lock ownership or expiry invalid';
    END IF;

    UPDATE test042_fixture
    SET lock_token = v_lock_token;

    RAISE NOTICE
        'PASS: Authorised Team A worker acquired exclusive case session';
END;
$test$;

-- TEST042 SUBMIT-ONLY SESSION DENIAL
-- Colleague A has Team A submit permission, but no Team A work permission.
-- A submit grant must never authorise an operational case session.

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_colleague::text FROM test042_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
    v_sqlstate TEXT;
BEGIN
    IF current_user <> 'authenticated' THEN
        RAISE EXCEPTION
            'FAIL: Submit-only denial test is not authenticated';
    END IF;

    SELECT * INTO STRICT f FROM test042_fixture;

    IF public.has_team_permission(f.team_a, 'work') THEN
        RAISE EXCEPTION
            'FAIL: Submit-only employee unexpectedly has work permission';
    END IF;

    IF NOT public.has_team_permission(f.team_a, 'submit') THEN
        RAISE EXCEPTION
            'FAIL: Submit-only employee lacks expected submit permission';
    END IF;

    BEGIN
        PERFORM *
        FROM public.open_case_session(f.case_a);

        RAISE EXCEPTION
            'FAIL: Submit-only employee opened operational case';
    EXCEPTION
        WHEN insufficient_privilege THEN
            GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;

            IF v_sqlstate <> '42501' THEN
                RAISE EXCEPTION
                    'FAIL: Unexpected denial SQLSTATE %', v_sqlstate;
            END IF;
    END;

    RAISE NOTICE
        'PASS: Submit-only employee denied Team A operational session';
END;
$test$;

RESET ROLE;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test042_fixture;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks l
        WHERE l.case_id = f.case_a
          AND l.organisation_id = f.organisation_a
          AND l.locked_by_user_id = f.employee_a
          AND l.lock_token = f.lock_token
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION
            'FAIL: Denied request changed the authorised employee lock';
    END IF;

    RAISE NOTICE
        'PASS: Submit-only denial preserved existing exclusive lock';
END;
$test$;

-- TEST042 ORGANISATION ADMINISTRATOR SESSION DENIAL
-- Organisation administration does not imply operational work access.

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test042_fixture;

    IF NOT EXISTS (
        SELECT 1
        FROM public.organisation_administrators oa
        WHERE oa.organisation_id = f.organisation_a
          AND oa.user_id = f.administrator_a
    ) THEN
        RAISE EXCEPTION
            'FAIL: Organisation administrator fixture is missing';
    END IF;
END;
$test$;

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_administrator::text FROM test042_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
    v_sqlstate TEXT;
    v_denied BOOLEAN := FALSE;
BEGIN
    IF current_user <> 'authenticated' THEN
        RAISE EXCEPTION
            'FAIL: Administrator denial test is not authenticated';
    END IF;

    SELECT * INTO STRICT f FROM test042_fixture;

    IF public.has_team_permission(f.team_a, 'work') THEN
        RAISE EXCEPTION
            'FAIL: Administrator unexpectedly has Team A work access';
    END IF;

    BEGIN
        PERFORM *
        FROM public.open_case_session(f.case_a);

    EXCEPTION
        WHEN insufficient_privilege THEN
            GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;

            IF v_sqlstate <> '42501' THEN
                RAISE EXCEPTION
                    'FAIL: Unexpected administrator denial SQLSTATE %',
                    v_sqlstate;
            END IF;

            v_denied := TRUE;
    END;

    IF NOT v_denied THEN
        RAISE EXCEPTION
            'FAIL: Administrator opened operational case without work permission';
    END IF;

    RAISE NOTICE
        'PASS: Organisation administrator denied operational session';
END;
$test$;

RESET ROLE;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test042_fixture;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks l
        WHERE l.case_id = f.case_a
          AND l.organisation_id = f.organisation_a
          AND l.locked_by_user_id = f.employee_a
          AND l.lock_token = f.lock_token
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION
            'FAIL: Administrator denial changed existing exclusive lock';
    END IF;

    RAISE NOTICE
        'PASS: Administrator denial preserved authorised employee lock';
END;
$test$;

-- TEST042 CROSS-ORGANISATION SESSION DENIAL
-- Employee C is authorised to work Team C cases in Organisation B.
-- That permission must never allow opening Organisation A cases.
-- Use an unlocked Organisation A case to isolate the tenant boundary.

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test042_fixture;

    IF f.organisation_a = f.organisation_b THEN
        RAISE EXCEPTION
            'FAIL: Cross-organisation fixture uses the same organisation';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.case_locks l
        WHERE l.case_id = f.case_other
    ) THEN
        RAISE EXCEPTION
            'FAIL: Cross-organisation target case is already locked';
    END IF;
END;
$test$;

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_b::text FROM test042_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
    v_denied BOOLEAN := FALSE;
    v_sqlstate TEXT;
BEGIN
    IF current_user <> 'authenticated' THEN
        RAISE EXCEPTION
            'FAIL: Cross-organisation test is not authenticated';
    END IF;

    SELECT * INTO STRICT f FROM test042_fixture;

    IF NOT public.has_team_permission(f.team_b, 'work') THEN
        RAISE EXCEPTION
            'FAIL: Organisation B employee lacks expected Team C work access';
    END IF;

    IF public.has_team_permission(f.team_other, 'work') THEN
        RAISE EXCEPTION
            'FAIL: Organisation B employee unexpectedly has Organisation A work access';
    END IF;

    BEGIN
        PERFORM *
        FROM public.open_case_session(f.case_other);

    EXCEPTION
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;

            IF v_sqlstate = '42501' THEN
                v_denied := TRUE;
            ELSIF v_sqlstate = 'P0001' THEN
                v_denied := TRUE;
            ELSE
                RAISE EXCEPTION
                    'FAIL: Unexpected cross-organisation SQLSTATE %',
                    v_sqlstate;
            END IF;
    END;

    IF NOT v_denied THEN
        RAISE EXCEPTION
            'FAIL: Organisation B employee opened Organisation A case';
    END IF;

    RAISE NOTICE
        'PASS: Organisation B worker denied Organisation A case session';
END;
$test$;

RESET ROLE;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test042_fixture;

    IF EXISTS (
        SELECT 1
        FROM public.case_locks l
        WHERE l.case_id = f.case_other
    ) THEN
        RAISE EXCEPTION
            'FAIL: Cross-organisation denial created an unauthorised lock';
    END IF;

    RAISE NOTICE
        'PASS: Cross-organisation denial created no case lock';
END;
$test$;

-- TEST042 SAME-ORGANISATION CROSS-TEAM DENIAL
-- Employee A has Team A work permission, not Team B work permission.
-- Membership in Organisation A must not confer access to all teams.

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test042_fixture;

    IF f.team_a = f.team_other THEN
        RAISE EXCEPTION
            'FAIL: Cross-team fixture uses the same team';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases c
        WHERE c.id = f.case_other
          AND c.organisation_id = f.organisation_a
          AND c.assigned_team_id = f.team_other
    ) THEN
        RAISE EXCEPTION
            'FAIL: Team B case fixture is invalid';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.case_locks l
        WHERE l.case_id = f.case_other
    ) THEN
        RAISE EXCEPTION
            'FAIL: Cross-team target case is already locked';
    END IF;
END;
$test$;

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test042_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
    v_denied BOOLEAN := FALSE;
    v_sqlstate TEXT;
BEGIN
    IF current_user <> 'authenticated' THEN
        RAISE EXCEPTION
            'FAIL: Cross-team test is not authenticated';
    END IF;

    SELECT * INTO STRICT f FROM test042_fixture;

    IF NOT public.has_team_permission(f.team_a, 'work') THEN
        RAISE EXCEPTION
            'FAIL: Employee A lacks expected Team A work permission';
    END IF;

    IF public.has_team_permission(f.team_other, 'work') THEN
        RAISE EXCEPTION
            'FAIL: Employee A unexpectedly has Team B work permission';
    END IF;

    BEGIN
        PERFORM *
        FROM public.open_case_session(f.case_other);

    EXCEPTION
        WHEN insufficient_privilege THEN
            GET STACKED DIAGNOSTICS
                v_sqlstate = RETURNED_SQLSTATE;

            IF v_sqlstate <> '42501' THEN
                RAISE EXCEPTION
                    'FAIL: Unexpected cross-team SQLSTATE %',
                    v_sqlstate;
            END IF;

            v_denied := TRUE;
    END;

    IF NOT v_denied THEN
        RAISE EXCEPTION
            'FAIL: Team A worker opened Team B case without permission';
    END IF;

    RAISE NOTICE
        'PASS: Team A worker denied Team B operational session';
END;
$test$;

RESET ROLE;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test042_fixture;

    IF EXISTS (
        SELECT 1
        FROM public.case_locks l
        WHERE l.case_id = f.case_other
    ) THEN
        RAISE EXCEPTION
            'FAIL: Cross-team denial created an unauthorised lock';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks l
        WHERE l.case_id = f.case_a
          AND l.organisation_id = f.organisation_a
          AND l.locked_by_user_id = f.employee_a
          AND l.lock_token = f.lock_token
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION
            'FAIL: Cross-team denial disturbed authorised Team A lock';
    END IF;

    RAISE NOTICE
        'PASS: Cross-team denial preserved existing lock isolation';
END;
$test$;

-- TEST042 AUTHORISED SESSION RESUME AND RENEW
-- Verify continuity before testing permission revocation.

CREATE TEMP TABLE test042_continuity_result (
    resumed_expiry TIMESTAMPTZ,
    renewed_expiry TIMESTAMPTZ
) ON COMMIT DROP;

GRANT INSERT ON test042_continuity_result TO authenticated;

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test042_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
    v_resumed TIMESTAMPTZ;
    v_renewed TIMESTAMPTZ;
BEGIN
    IF current_user <> 'authenticated' THEN
        RAISE EXCEPTION
            'FAIL: Continuity test is not authenticated';
    END IF;

    SELECT * INTO STRICT f FROM test042_fixture;

    IF NOT public.has_team_permission(f.team_a, 'work') THEN
        RAISE EXCEPTION
            'FAIL: Employee A lacks Team A work permission';
    END IF;

    v_resumed := public.resume_employee_case_session(
        f.case_a,
        f.lock_token
    );

    IF v_resumed IS NULL THEN
        RAISE EXCEPTION
            'FAIL: Authorised employee could not resume session';
    END IF;


    RAISE NOTICE
        'PASS: Authorised employee resumed existing session';

    v_renewed := public.renew_case_lock(
        f.case_a,
        f.lock_token
    );

    IF v_renewed IS NULL THEN
        RAISE EXCEPTION
            'FAIL: Authorised employee could not renew session';
    END IF;


    INSERT INTO test042_continuity_result (
        resumed_expiry,
        renewed_expiry
    )
    VALUES (
        v_resumed,
        v_renewed
    );

    RAISE NOTICE
        'PASS: Authorised employee renewed existing session';
END;
$test$;

RESET ROLE;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
    v_resumed TIMESTAMPTZ;
    v_renewed TIMESTAMPTZ;
BEGIN
    SELECT * INTO STRICT f FROM test042_fixture;

    IF (SELECT COUNT(*) FROM test042_continuity_result) <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Expected one session continuity result';
    END IF;

    SELECT resumed_expiry, renewed_expiry
    INTO STRICT v_resumed, v_renewed
    FROM test042_continuity_result;

    IF v_resumed IS NULL OR v_renewed IS NULL THEN
        RAISE EXCEPTION
            'FAIL: Missing session continuity timestamps';
    END IF;

    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION
            'FAIL: Lock verification is not running as postgres';
    END IF;

    IF v_resumed > v_renewed THEN
        RAISE EXCEPTION
            'FAIL: Renewal produced an earlier expiry than resume';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks l
        WHERE l.case_id = f.case_a
          AND l.organisation_id = f.organisation_a
          AND l.locked_by_user_id = f.employee_a
          AND l.lock_token = f.lock_token
          AND l.expires_at = v_renewed
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION
            'FAIL: Final lock differs from authorised renewal';
    END IF;

    RAISE NOTICE
        'PASS: Session continuity preserved exclusive lock identity';
END;
$test$;

-- TEST042 ACTIVE-SESSION WORK PERMISSION REVOCATION
-- Revocation must prevent session resume and renewal without
-- changing the employee's existing exclusive lock.

CREATE TEMP TABLE test042_revocation_snapshot AS
SELECT
    l.case_id,
    l.organisation_id,
    l.locked_by_user_id,
    l.lock_token,
    l.locked_at,
    l.expires_at
FROM public.case_locks l
JOIN test042_fixture f ON f.case_a = l.case_id
WHERE l.organisation_id = f.organisation_a
  AND l.locked_by_user_id = f.employee_a
  AND l.lock_token = f.lock_token;


-- TEST045: AUTHORISED CASE WORK HELPER ASSERTIONS

-- TEST053: Synthetic completed evidence fixture.
-- Created by local database administrator only.
-- No real Storage object is created.
DO $test053_fixture$
DECLARE
    f test042_fixture%ROWTYPE;
    v_reservation_id uuid := gen_random_uuid();
    v_attachment_id uuid := gen_random_uuid();
    v_storage_path text;
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION
            'FAIL: Test053 fixture must be created as postgres';
    END IF;

    SELECT * INTO STRICT f FROM test042_fixture;

    v_storage_path :=
        'test053/' || f.case_a::text || '/' || v_reservation_id::text;

    INSERT INTO public.case_evidence_upload_reservations (
        id, case_id, organisation_id, employee_id,
        storage_path, file_name, file_type, file_size_bytes,
        status, created_at, expires_at, completed_at
    )
    VALUES (
        v_reservation_id,
        f.case_a,
        f.organisation_a,
        f.employee_a,
        v_storage_path,
        'test053-evidence.pdf',
        'application/pdf',
        1024,
        'completed',
        clock_timestamp(),
        clock_timestamp() + interval '10 minutes',
        clock_timestamp()
    );

    INSERT INTO public.attachments (
        id, case_id, organisation_id, uploaded_by_user_id,
        file_name, file_type, file_size_bytes,
        storage_reference, visibility
    )
    VALUES (
        v_attachment_id,
        f.case_a,
        f.organisation_a,
        f.employee_a,
        'test053-evidence.pdf',
        'application/pdf',
        1024,
        v_storage_path,
        'internal'
    );

    PERFORM set_config(
        'madzera.test053.attachment_id',
        v_attachment_id::text,
        true
    );

    PERFORM set_config(
        'madzera.test053.storage_path',
        v_storage_path,
        true
    );

    RAISE NOTICE
        'PASS: Completed evidence fixture created under postgres';
END;
$test053_fixture$;

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test042_fixture),
    TRUE
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test042_fixture;

    IF public.can_work_on_case(f.case_a) IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'FAIL: Authorised team worker denied';
    END IF;

    IF public.can_work_on_case(f.case_other) IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'FAIL: Cross-team case access permitted';
    END IF;

    IF public.can_work_on_case(f.case_b) IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'FAIL: Cross-organisation case access permitted';
    END IF;


    IF (
        SELECT COUNT(*)
        FROM public.get_locked_case_details(
            f.case_a,
            f.lock_token
        )
    ) <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Authorised employee cannot retrieve locked case';
    END IF;

    RAISE NOTICE
        'PASS: Authorised employee retrieved locked case';


    -- TEST049: An authorised worker may record an internal comment.
    IF public.save_employee_case_comment(
        f.case_a,
        f.lock_token,
        'TEST049 authorised employee activity'
    ) IS NULL THEN
        RAISE EXCEPTION 'FAIL: Authorised comment returned no ID';
    END IF;

    RAISE NOTICE 'PASS: Authorised employee created internal comment';

    -- TEST050: An authorised employee can retrieve internal comments.
    IF NOT EXISTS (
        SELECT 1
        FROM public.get_employee_case_comments(
            f.case_a,
            f.lock_token
        ) AS cm
        WHERE cm.body = 'TEST049 authorised employee activity'
          AND cm.author_user_id = f.employee_a
          AND cm.id IS NOT NULL
          AND cm.created_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION
            'FAIL: Authorised internal comment retrieval failed';
    END IF;

    RAISE NOTICE
        'PASS: Authorised employee retrieved internal comment';

    -- TEST051: Authorised employee can retrieve attributed audit events.
    IF NOT EXISTS (
        SELECT 1
        FROM public.get_employee_case_audit_history(
            f.case_a,
            f.lock_token
        ) AS ev
        WHERE ev.event_type = 'comment_added'
          AND ev.actor_user_id = f.employee_a
          AND ev.id IS NOT NULL
          AND ev.created_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION
            'FAIL: Authorised employee could not retrieve comment audit event';
    END IF;

    RAISE NOTICE
        'PASS: Authorised employee retrieved attributed audit history';

    -- TEST052: An authorised employee can access evidence metadata.
    -- An empty result is valid when no attachments exist.
    PERFORM *
    FROM public.get_employee_case_evidence(
        f.case_a,
        f.lock_token
    );

    RAISE NOTICE
        'PASS: Authorised employee evidence retrieval permitted';

    IF public.get_employee_case_evidence_download_path(
        current_setting('madzera.test053.attachment_id')::uuid,
        f.case_a,
        f.lock_token
    ) IS DISTINCT FROM
       current_setting('madzera.test053.storage_path') THEN

        RAISE EXCEPTION
            'FAIL: Authorised download returned incorrect path';
    END IF;

    RAISE NOTICE
        'PASS: Authorised employee retrieved completed evidence download path';

    -- TEST054: Current team-work permission permits upload preparation.
    -- The reservation is transaction-scoped and rolled back.
    DECLARE
        v_test054_reservation_id uuid;
        v_test054_storage_path text;
    BEGIN
        SELECT reservation_id, storage_path
        INTO STRICT v_test054_reservation_id, v_test054_storage_path
        FROM public.prepare_case_evidence_upload(
            f.case_a,
            f.lock_token,
            'test054-evidence.pdf',
            'application/pdf',
            1024
        );

        IF v_test054_reservation_id IS NULL
           OR v_test054_storage_path IS NULL THEN
            RAISE EXCEPTION
                'FAIL: Authorised upload preparation returned incomplete data';
        END IF;

        PERFORM set_config(
            'madzera.test054.reservation_id',
            v_test054_reservation_id::text,
            true
        );

        RAISE NOTICE
            'PASS: Authorised employee prepared evidence upload';
    END;









    -- The employee invokes Save through the restricted RPC.
    IF public.save_employee_case_assignment(
        f.case_a,
        f.lock_token,
        NULL,
        FALSE
    ) IS DISTINCT FROM f.case_a THEN
        RAISE EXCEPTION 'FAIL: Authorised Save returned wrong case';
    END IF;

    RAISE NOTICE 'PASS: Authorised employee executed Save RPC';


    -- Authorised status/priority update, retaining the destination team.
    IF public.update_employee_case(
        p_case_id := f.case_a,
        p_lock_token := f.lock_token,
        p_status := 'in_progress',
        p_priority := 'high',
        p_assigned_team_id := f.team_a
    ) IS DISTINCT FROM f.case_a THEN
        RAISE EXCEPTION 'FAIL: Authorised case update returned wrong case';
    END IF;

    RAISE NOTICE 'PASS: Authorised case status and priority updated';

    -- A general case-update RPC must not transfer responsibility.
    BEGIN
        PERFORM public.update_employee_case(
            p_case_id := f.case_a,
            p_lock_token := f.lock_token,
            p_assigned_team_id := f.team_other
        );

        RAISE EXCEPTION
            'FAIL: Unauthorised team transfer succeeded'
            USING ERRCODE = 'P0002';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN
            RAISE NOTICE 'PASS: Unauthorised team transfer denied';
    END;

    -- The destination team must not be removed.
    BEGIN
        PERFORM public.update_employee_case(
            p_case_id := f.case_a,
            p_lock_token := f.lock_token,
            p_clear_team := TRUE
        );

        RAISE EXCEPTION
            'FAIL: Destination team removal succeeded'
            USING ERRCODE = 'P0002';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN
            RAISE NOTICE 'PASS: Destination team removal denied';
    END;

    RAISE NOTICE 'PASS: Authorised and isolated case work access';
END;
$test$;

RESET ROLE;

-- Privileged assertions: never grant direct case-table access
-- to the application role for testing purposes.
DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'FAIL: Save verification must run as postgres';
    END IF;

    SELECT * INTO STRICT f FROM test042_fixture;

    IF (
        SELECT assigned_user_id
        FROM public.cases
        WHERE id = f.case_a
    ) IS DISTINCT FROM f.employee_a THEN
        RAISE EXCEPTION 'FAIL: Save did not assign employee';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM public.case_events e
        WHERE e.case_id = f.case_a
          AND e.organisation_id = f.organisation_a
          AND e.actor_user_id = f.employee_a
          AND e.event_type = 'case_updated'
          AND e.from_user_id IS NULL
          AND e.to_user_id = f.employee_a
    ) <> 1 THEN
        RAISE EXCEPTION 'FAIL: Save assignment audit incorrect';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks l
        JOIN test042_revocation_snapshot s
          ON s.case_id = l.case_id
        WHERE l.case_id = f.case_a
          AND l.organisation_id = s.organisation_id
          AND l.locked_by_user_id = s.locked_by_user_id
          AND l.lock_token = s.lock_token
          AND l.locked_at = s.locked_at
          AND l.expires_at = s.expires_at
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'FAIL: Save changed existing lock';
    END IF;


    IF NOT EXISTS (
        SELECT 1
        FROM public.cases c
        WHERE c.id = f.case_a
          AND c.organisation_id = f.organisation_a
          AND c.status = 'in_progress'
          AND c.priority = 'high'
          AND c.assigned_team_id = f.team_a
          AND c.assigned_user_id = f.employee_a
    ) THEN
        RAISE EXCEPTION
            'FAIL: Authorised update or team isolation state incorrect';
    END IF;

    RAISE NOTICE
        'PASS: Updated case values and destination team verified';

    RAISE NOTICE
        'PASS: Save assignment, audit and lock verified as postgres';
END;
$test$;

-- TEST049: Record the authorised comment state before revocation.
CREATE TEMP TABLE test049_comments_before_revocation AS
SELECT c.id
FROM public.comments c
JOIN test042_fixture f
  ON c.case_id = f.case_a
 AND c.organisation_id = f.organisation_a;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test042_fixture;

    IF NOT EXISTS (
        SELECT 1
        FROM public.comments c
        WHERE c.case_id = f.case_a
          AND c.organisation_id = f.organisation_a
          AND c.author_user_id = f.employee_a
          AND c.body = 'TEST049 authorised employee activity'
          AND c.visibility = 'internal'
    ) THEN
        RAISE EXCEPTION 'FAIL: Authorised comment not persisted';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_events e
        WHERE e.case_id = f.case_a
          AND e.organisation_id = f.organisation_a
          AND e.event_type = 'comment_added'
    ) THEN
        RAISE EXCEPTION 'FAIL: Authorised comment audit missing';
    END IF;

    RAISE NOTICE 'PASS: Authorised comment and audit verified';
END;
$test$;

-- TEST054: Record reservations before revoking team-work access.
CREATE TEMP TABLE test054_reservations_before_revocation AS
SELECT r.id
FROM public.case_evidence_upload_reservations AS r
JOIN test042_fixture AS f
  ON r.case_id = f.case_a
 AND r.organisation_id = f.organisation_a;

DO $test054_snapshot$
BEGIN
    IF (
        SELECT COUNT(*)
        FROM test054_reservations_before_revocation
        WHERE id = current_setting(
            'madzera.test054.reservation_id'
        )::uuid
    ) <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Authorised upload reservation missing before revocation';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_evidence_upload_reservations
        WHERE id = current_setting(
            'madzera.test054.reservation_id'
        )::uuid
          AND status = 'pending'
    ) THEN
        RAISE EXCEPTION
            'FAIL: Authorised upload reservation is not pending';
    END IF;

    RAISE NOTICE
        'PASS: Authorised upload reservation recorded before revocation';
END;
$test054_snapshot$;

-- Capture the exact audit-event IDs after authorised updates.
-- Rejected operations must not change this set.
CREATE TEMP TABLE test048_audit_before_revocation AS
SELECT e.id
FROM public.case_events e
JOIN test042_fixture f
  ON e.case_id = f.case_a
 AND e.organisation_id = f.organisation_a;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
    v_rows INTEGER;
BEGIN
    SELECT * INTO STRICT f FROM test042_fixture;

    IF (SELECT COUNT(*) FROM test042_revocation_snapshot) <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Expected exactly one active lock snapshot';
    END IF;

    DELETE FROM public.team_permission_grants g
    WHERE g.organisation_id = f.organisation_a
      AND g.team_id = f.team_a
      AND g.user_id = f.employee_a
      AND g.permission_type = 'work';

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Expected one work grant revocation, got %',
            v_rows;
    END IF;

    RAISE NOTICE
        'PASS: Exactly one active-session work grant revoked';
END;
$test$;


-- TEST045: POST-REVOCATION CASE WORK HELPER ASSERTIONS
SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test042_fixture),
    TRUE
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT f FROM test042_fixture;

    IF public.can_work_on_case(f.case_a) IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION 'FAIL: Revoked work permission still authorises case';
    END IF;


    IF EXISTS (
        SELECT 1
        FROM public.get_locked_case_details(
            f.case_a,
            f.lock_token
        )
    ) THEN
        RAISE EXCEPTION
            'FAIL: Revoked employee retrieved protected case details';
    END IF;

    RAISE NOTICE
        'PASS: Revoked employee denied case details despite valid lock';


    -- A revoked worker must receive SQLSTATE 42501.
    -- The successful-call path must fail the test outside
    -- the exception handler.
    BEGIN
        PERFORM public.save_employee_case_assignment(
            f.case_a,
            f.lock_token,
            f.employee_a,
            FALSE
        );

        RAISE EXCEPTION
            'FAIL: Revoked Save unexpectedly succeeded'
            USING ERRCODE = 'P0002';

    EXCEPTION
        WHEN SQLSTATE '42501' THEN
            RAISE NOTICE 'PASS: Revoked Save rejected with SQLSTATE 42501';
    END;


    -- Existing lock must not authorise updates after revocation.
    BEGIN
        PERFORM public.update_employee_case(
            p_case_id := f.case_a,
            p_lock_token := f.lock_token,
            p_status := 'resolved',
            p_priority := 'critical'
        );

        RAISE EXCEPTION
            'FAIL: Revoked employee updated case'
            USING ERRCODE = 'P0002';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN
            RAISE NOTICE 'PASS: Revoked employee case update denied';
    END;

    -- TEST049: A retained valid lock cannot authorise new comments.
    BEGIN
        PERFORM public.save_employee_case_comment(
            f.case_a,
            f.lock_token,
            'TEST049 rejected comment after revocation'
        );

        RAISE EXCEPTION 'FAIL: Revoked employee inserted a comment'
            USING ERRCODE = 'P0002';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN
            RAISE NOTICE 'PASS: Revoked employee comment denied';

    -- TEST050: Existing lock ownership cannot bypass revoked work access.
    BEGIN
        PERFORM *
        FROM public.get_employee_case_comments(
            f.case_a,
            f.lock_token
        );

        RAISE EXCEPTION
            'FAIL: Revoked employee retrieved internal comments'
            USING ERRCODE = 'P0002';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN
            RAISE NOTICE
                'PASS: Revoked employee comment retrieval denied';

    -- TEST051: Valid lock does not bypass revoked work permission.
    BEGIN
        PERFORM *
        FROM public.get_employee_case_audit_history(
            f.case_a,
            f.lock_token
        );

        RAISE EXCEPTION
            'FAIL: Revoked employee retrieved case audit history'
            USING ERRCODE = 'P0002';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN
            RAISE NOTICE
                'PASS: Revoked employee audit-history retrieval denied';

    -- TEST052: An existing valid lock cannot bypass revoked work access.
    BEGIN
        PERFORM *
        FROM public.get_employee_case_evidence(
            f.case_a,
            f.lock_token
        );

        RAISE EXCEPTION
            'FAIL: Revoked employee retrieved evidence metadata'
            USING ERRCODE = 'P0002';
    EXCEPTION
        WHEN SQLSTATE '42501' THEN
            RAISE NOTICE
                'PASS: Revoked employee evidence retrieval denied';

    -- Test the exact completed attachment used before revocation.
    -- The valid exclusive lock remains held at this point.
    BEGIN
        PERFORM public.get_employee_case_evidence_download_path(
            current_setting('madzera.test053.attachment_id')::uuid,
            f.case_a,
            f.lock_token
        );

        RAISE EXCEPTION
            'FAIL: Revoked employee retrieved completed evidence path'
            USING ERRCODE = 'P0002';

    EXCEPTION
        WHEN SQLSTATE '42501' THEN
            RAISE NOTICE
                'PASS: Revoked employee download-path retrieval denied';
    END;

    END;

    END;

    END;

    END;

    -- TEST054: Revoked work access must override the valid old lock.
    -- Check the precise permission error, not merely SQLSTATE 42501.
    BEGIN
        PERFORM *
        FROM public.prepare_case_evidence_upload(
            f.case_a,
            f.lock_token,
            'test054-after-revocation.pdf',
            'application/pdf',
            1024
        );

        RAISE EXCEPTION
            'FAIL: Revoked employee prepared evidence upload'
            USING ERRCODE = 'P0002';

    EXCEPTION
        WHEN SQLSTATE '42501' THEN
            IF SQLERRM <> 'Case work permission required' THEN
                RAISE EXCEPTION
                    'FAIL: Unexpected upload-preparation denial: %',
                    SQLERRM;
            END IF;

            RAISE NOTICE
                'PASS: Revoked employee upload preparation denied';
    END;

    RAISE NOTICE 'PASS: Revoked case work permission denied immediately';
END;
$test$;

RESET ROLE;

-- TEST054: Revoked preparation must preserve reservation IDs.
DO $test054_verify$
DECLARE
    f test042_fixture%ROWTYPE;
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION
            'FAIL: Reservation verification requires postgres';
    END IF;

    SELECT * INTO STRICT f FROM test042_fixture;

    IF EXISTS (
        (
            SELECT r.id
            FROM public.case_evidence_upload_reservations AS r
            WHERE r.case_id = f.case_a
              AND r.organisation_id = f.organisation_a
            EXCEPT
            SELECT id FROM test054_reservations_before_revocation
        )
        UNION ALL
        (
            SELECT id FROM test054_reservations_before_revocation
            EXCEPT
            SELECT r.id
            FROM public.case_evidence_upload_reservations AS r
            WHERE r.case_id = f.case_a
              AND r.organisation_id = f.organisation_a
        )
    ) THEN
        RAISE EXCEPTION
            'FAIL: Revoked upload preparation changed reservations';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_evidence_upload_reservations
        WHERE id = current_setting(
            'madzera.test054.reservation_id'
        )::uuid
          AND status = 'pending'
    ) THEN
        RAISE EXCEPTION
            'FAIL: Revoked upload preparation altered pending reservation';
    END IF;

    RAISE NOTICE
        'PASS: Revoked upload preparation preserved reservation records';
END;
$test054_verify$;

-- Verify the rejected Save did not alter persistent state.
DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'FAIL: Revoked Save verification must run as postgres';
    END IF;

    SELECT * INTO STRICT f FROM test042_fixture;

    IF (
        SELECT assigned_user_id
        FROM public.cases
        WHERE id = f.case_a
    ) IS DISTINCT FROM f.employee_a THEN
        RAISE EXCEPTION 'FAIL: Revoked Save changed assignment';
    END IF;

    -- TEST049: Rejected comment creation must not change comment records.
    IF EXISTS (
        (
            SELECT c.id
            FROM public.comments c
            WHERE c.case_id = f.case_a
              AND c.organisation_id = f.organisation_a
            EXCEPT
            SELECT s.id
            FROM test049_comments_before_revocation s
        )
        UNION ALL
        (
            SELECT s.id
            FROM test049_comments_before_revocation s
            EXCEPT
            SELECT c.id
            FROM public.comments c
            WHERE c.case_id = f.case_a
              AND c.organisation_id = f.organisation_a
        )
    ) THEN
        RAISE EXCEPTION 'FAIL: Rejected comment changed comment records';
    END IF;

    RAISE NOTICE 'PASS: Revoked comment preserved comment records';

    -- Compare exact event IDs rather than assuming one audit event.
    -- The authorised status/priority update legitimately adds history.
    IF EXISTS (
        (
            SELECT e.id
            FROM public.case_events e
            WHERE e.case_id = f.case_a
              AND e.organisation_id = f.organisation_a
            EXCEPT
            SELECT s.id
            FROM test048_audit_before_revocation s
        )
        UNION ALL
        (
            SELECT s.id
            FROM test048_audit_before_revocation s
            EXCEPT
            SELECT e.id
            FROM public.case_events e
            WHERE e.case_id = f.case_a
              AND e.organisation_id = f.organisation_a
        )
    ) THEN
        RAISE EXCEPTION
            'FAIL: Rejected operations changed case audit history';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks l
        JOIN test042_revocation_snapshot s
          ON s.case_id = l.case_id
        WHERE l.case_id = f.case_a
          AND l.organisation_id = s.organisation_id
          AND l.locked_by_user_id = s.locked_by_user_id
          AND l.lock_token = s.lock_token
          AND l.locked_at = s.locked_at
          AND l.expires_at = s.expires_at
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'FAIL: Revoked Save changed existing lock';
    END IF;


    IF NOT EXISTS (
        SELECT 1
        FROM public.cases c
        WHERE c.id = f.case_a
          AND c.organisation_id = f.organisation_a
          AND c.status = 'in_progress'
          AND c.priority = 'high'
          AND c.assigned_team_id = f.team_a
          AND c.assigned_user_id = f.employee_a
    ) THEN
        RAISE EXCEPTION
            'FAIL: Revoked update changed protected case state';
    END IF;

    RAISE NOTICE
        'PASS: Revoked update preserved case state';

    RAISE NOTICE
        'PASS: Revoked Save preserved assignment, audit and lock';
END;
$test$;

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test042_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
    v_sqlstate TEXT;
    v_denied BOOLEAN;
BEGIN
    IF current_user <> 'authenticated' THEN
        RAISE EXCEPTION
            'FAIL: Revocation test is not authenticated';
    END IF;

    SELECT * INTO STRICT f FROM test042_fixture;

    IF public.has_team_permission(f.team_a, 'work') THEN
        RAISE EXCEPTION
            'FAIL: Revoked work permission remains effective';
    END IF;

    v_denied := FALSE;

    BEGIN
        PERFORM public.resume_employee_case_session(
            f.case_a,
            f.lock_token
        );
    EXCEPTION WHEN insufficient_privilege THEN
        GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;
        IF v_sqlstate = '42501' THEN
            v_denied := TRUE;
        END IF;
    END;

    IF NOT v_denied THEN
        RAISE EXCEPTION
            'FAIL: Revoked employee could resume existing session';
    END IF;

    RAISE NOTICE
        'PASS: Revoked employee denied session resume';

    v_denied := FALSE;

    BEGIN
        PERFORM public.renew_case_lock(
            f.case_a,
            f.lock_token
        );
    EXCEPTION WHEN insufficient_privilege THEN
        GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE;
        IF v_sqlstate = '42501' THEN
            v_denied := TRUE;
        END IF;
    END;

    IF NOT v_denied THEN
        RAISE EXCEPTION
            'FAIL: Revoked employee could renew existing session';
    END IF;

    RAISE NOTICE
        'PASS: Revoked employee denied session renewal';
END;
$test$;

RESET ROLE;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION
            'FAIL: Revocation verification is not privileged';
    END IF;

    SELECT * INTO STRICT f FROM test042_fixture;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks l
        JOIN test042_revocation_snapshot s
          ON s.case_id = l.case_id
        WHERE l.case_id = f.case_a
          AND l.organisation_id = s.organisation_id
          AND l.locked_by_user_id = s.locked_by_user_id
          AND l.lock_token IS NOT DISTINCT FROM s.lock_token
          AND l.locked_at = s.locked_at
          AND l.expires_at = s.expires_at
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION
            'FAIL: Denied session operations modified existing lock';
    END IF;

    RAISE NOTICE
        'PASS: Revocation denials preserved exclusive lock unchanged';
END;
$test$;

-- TEST042 POST-REVOCATION SAFE SESSION EXIT
-- An active employee whose work grant was revoked must still
-- be able to release their own lock and generate an exit audit.

CREATE TEMP TABLE test042_exit_baseline AS
SELECT
    f.case_a AS case_id,
    f.organisation_a AS organisation_id,
    f.employee_a AS actor_user_id,
    COUNT(e.id)::BIGINT AS prior_exit_count
FROM test042_fixture f
LEFT JOIN public.case_events e
  ON e.case_id = f.case_a
 AND e.organisation_id = f.organisation_a
 AND e.actor_user_id = f.employee_a
 AND e.event_type = 'case_closed_view'
GROUP BY f.case_a, f.organisation_a, f.employee_a;

CREATE TEMP TABLE test042_exit_result (
    first_release BOOLEAN NOT NULL,
    second_release BOOLEAN NOT NULL
) ON COMMIT DROP;

GRANT INSERT ON test042_exit_result TO authenticated;

SELECT set_config(
    'request.jwt.claim.sub',
    (SELECT auth_a::text FROM test042_fixture),
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
    v_first BOOLEAN;
    v_second BOOLEAN;
BEGIN
    IF current_user <> 'authenticated' THEN
        RAISE EXCEPTION
            'FAIL: Safe-exit test is not authenticated';
    END IF;

    SELECT * INTO STRICT f FROM test042_fixture;

    IF public.has_team_permission(f.team_a, 'work') THEN
        RAISE EXCEPTION
            'FAIL: Work permission unexpectedly restored';
    END IF;

    v_first := public.close_case_session(
        f.case_a,
        f.lock_token
    );

    IF v_first IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION
            'FAIL: Revoked employee could not safely close session';
    END IF;

    RAISE NOTICE
        'PASS: Revoked employee safely closed owned session';

    v_second := public.close_case_session(
        f.case_a,
        f.lock_token
    );

    IF v_second IS DISTINCT FROM FALSE THEN
        RAISE EXCEPTION
            'FAIL: Duplicate session closure was accepted';
    END IF;

    RAISE NOTICE
        'PASS: Duplicate session closure rejected safely';

    INSERT INTO test042_exit_result (
        first_release,
        second_release
    )
    VALUES (v_first, v_second);
END;
$test$;

RESET ROLE;

DO $test$
DECLARE
    f test042_fixture%ROWTYPE;
    v_prior BIGINT;
    v_current BIGINT;
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION
            'FAIL: Exit verification is not running as postgres';
    END IF;

    SELECT * INTO STRICT f FROM test042_fixture;

    IF (SELECT COUNT(*) FROM test042_exit_result) <> 1 THEN
        RAISE EXCEPTION
            'FAIL: Expected exactly one safe-exit result';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.case_locks l
        WHERE l.case_id = f.case_a
          AND l.organisation_id = f.organisation_a
    ) THEN
        RAISE EXCEPTION
            'FAIL: Revoked employee lock remains after safe exit';
    END IF;

    RAISE NOTICE
        'PASS: Safe exit removed exclusive case lock';

    SELECT prior_exit_count
    INTO STRICT v_prior
    FROM test042_exit_baseline
    WHERE case_id = f.case_a
      AND organisation_id = f.organisation_a
      AND actor_user_id = f.employee_a;

    SELECT COUNT(*)
    INTO v_current
    FROM public.case_events e
    WHERE e.case_id = f.case_a
      AND e.organisation_id = f.organisation_a
      AND e.actor_user_id = f.employee_a
      AND e.event_type = 'case_closed_view';

    IF v_current <> v_prior + 1 THEN
        RAISE EXCEPTION
            'FAIL: Expected one exit audit event, prior %, current %',
            v_prior,
            v_current;
    END IF;

    RAISE NOTICE
        'PASS: Exactly one employee-attributed exit audit recorded';
END;
$test$;

-- End of implemented session-authorisation regression assertions.

ROLLBACK;
