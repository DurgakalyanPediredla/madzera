-- MADZERA TEST 026
-- Migration 041: RPC security and legacy compatibility.
-- Requires the local test employee fixture.
-- All test-created records are rolled back.

\set ON_ERROR_STOP on

BEGIN;

-- Confirm the expected employee fixture before role switching.
DO $test$
DECLARE
    v_auth_user_id uuid;
BEGIN
    SELECT u.auth_user_id
    INTO v_auth_user_id
    FROM public.users u
    WHERE u.email = 'employee-a@madzera-test.example'
      AND u.is_active = true;

    IF v_auth_user_id IS NULL THEN
        RAISE EXCEPTION 'Missing employee-a test fixture';
    END IF;

    PERFORM set_config(
        'madzera.test.auth_user_id',
        v_auth_user_id::text,
        true
    );
END;
$test$;

-- Anonymous users must not execute either public creation RPC.
SET LOCAL ROLE anon;

DO $test$
DECLARE
    v_rejected boolean;
BEGIN
    v_rejected := false;

    BEGIN
        PERFORM public.create_employee_case(
            p_title => 'TEST 026 anonymous legacy'
        );
    EXCEPTION WHEN insufficient_privilege THEN
        v_rejected := true;
    END;

    IF NOT v_rejected THEN
        RAISE EXCEPTION 'FAIL: Anonymous legacy RPC accepted';
    END IF;

    RAISE NOTICE 'PASS: Anonymous legacy RPC denied';

    v_rejected := false;

    BEGIN
        PERFORM public.create_employee_case_v2(
            'TEST 026 anonymous v2',
            NULL,
            'medium',
            NULL,
            NULL,
            'internal_case'
        );
    EXCEPTION WHEN insufficient_privilege THEN
        v_rejected := true;
    END;

    IF NOT v_rejected THEN
        RAISE EXCEPTION 'FAIL: Anonymous v2 RPC accepted';
    END IF;

    RAISE NOTICE 'PASS: Anonymous v2 RPC denied';
END;
$test$;

RESET ROLE;

-- An authenticated identity without an employee link must be rejected.
SELECT set_config(
    'request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000099',
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_rejected boolean;
BEGIN
    v_rejected := false;

    BEGIN
        PERFORM public.create_employee_case(
            p_title => 'TEST 026 unlinked legacy'
        );
    EXCEPTION WHEN insufficient_privilege THEN
        v_rejected := true;
    END;

    IF NOT v_rejected THEN
        RAISE EXCEPTION 'FAIL: Unlinked legacy RPC accepted';
    END IF;

    RAISE NOTICE 'PASS: Unlinked legacy RPC rejected';

    v_rejected := false;

    BEGIN
        PERFORM public.create_employee_case_v2(
            'TEST 026 unlinked v2',
            NULL,
            'medium',
            NULL,
            NULL,
            'internal_case'
        );
    EXCEPTION WHEN insufficient_privilege THEN
        v_rejected := true;
    END;

    IF NOT v_rejected THEN
        RAISE EXCEPTION 'FAIL: Unlinked v2 RPC accepted';
    END IF;

    RAISE NOTICE 'PASS: Unlinked v2 RPC rejected';
END;
$test$;

RESET ROLE;

-- The original RPC must remain operational for linked employees.
-- Migration 063 fixture: authorise the linked employee for one destination team.
DO $test$
DECLARE
    v_auth_user_id uuid :=
        current_setting('madzera.test.auth_user_id')::uuid;
    v_user_id uuid;
    v_org_id uuid;
    v_team_id uuid;
BEGIN
    SELECT u.id, u.organisation_id
    INTO STRICT v_user_id, v_org_id
    FROM public.users u
    WHERE u.auth_user_id = v_auth_user_id
      AND u.is_active = true;

    INSERT INTO public.teams (organisation_id, name)
    VALUES (v_org_id, 'MADZERA TEST 026 SUBMISSION TEAM')
    RETURNING id INTO v_team_id;

    INSERT INTO public.team_permission_grants (
        organisation_id,
        team_id,
        user_id,
        permission_type
    )
    VALUES (
        v_org_id,
        v_team_id,
        v_user_id,
        'submit'
    );

    PERFORM set_config(
        'madzera.test026.team_id',
        v_team_id::text,
        true
    );
END;
$test$;

SELECT set_config(
    'request.jwt.claim.sub',
    current_setting('madzera.test.auth_user_id'),
    true
);

SET LOCAL ROLE authenticated;

CREATE TEMP TABLE madzera_test_026_case_id (
    case_id uuid NOT NULL
) ON COMMIT DROP;

INSERT INTO madzera_test_026_case_id (case_id)
SELECT public.create_employee_case(
    p_title => 'TEST 026 legacy compatibility',
    p_assigned_team_id =>
        current_setting('madzera.test026.team_id')::uuid
);

RESET ROLE;

DO $test$
DECLARE
    v_case_id uuid;
    v_case_type text;
    v_customer_id uuid;
    v_case_reference text;
    v_event_count integer;
BEGIN
    SELECT case_id INTO v_case_id
    FROM madzera_test_026_case_id;

    IF v_case_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: Legacy RPC returned no case ID';
    END IF;

    SELECT c.case_type, c.customer_id, c.case_reference
    INTO v_case_type, v_customer_id, v_case_reference
    FROM public.cases c
    WHERE c.id = v_case_id;

    IF v_case_type IS DISTINCT FROM 'internal_case'
       OR v_customer_id IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL: Legacy classification changed';
    END IF;

    RAISE NOTICE 'PASS: Legacy RPC classification preserved';

    IF v_case_reference IS NULL
       OR v_case_reference !~ '^CAS[0-9]{10}$' THEN
        RAISE EXCEPTION 'FAIL: Legacy RPC case reference missing';
    END IF;

    RAISE NOTICE 'PASS: Legacy RPC structured reference';

    SELECT count(*)
    INTO v_event_count
    FROM public.case_events e
    WHERE e.case_id = v_case_id
      AND e.event_type = 'case_created';

    IF v_event_count <> 1 THEN
        RAISE EXCEPTION 'FAIL: Legacy RPC creation audit event missing';
    END IF;

    RAISE NOTICE 'PASS: Legacy RPC creation audit event';
END;
$test$;

ROLLBACK;
