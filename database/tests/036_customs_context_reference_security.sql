-- MADZERA TEST 036
-- Migration 056: Customs context and operational reference security.
-- Local PostgreSQL structural, permission and integrity regression.
-- All test-created records are rolled back.
-- Does not establish RPC-level tenant authorisation.

\set ON_ERROR_STOP on

BEGIN;

DO $test$
DECLARE
    v_table text;
    v_role text;
    v_privilege text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'case_customs_context',
        'case_operational_references'
    ] LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public'
              AND c.relname = v_table
              AND c.relrowsecurity
        ) THEN
            RAISE EXCEPTION 'FAIL: RLS missing on %', v_table;
        END IF;

        FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
            FOREACH v_privilege IN ARRAY ARRAY[
                'SELECT', 'INSERT', 'UPDATE', 'DELETE'
            ] LOOP
                IF has_table_privilege(
                    v_role,
                    format('public.%I', v_table),
                    v_privilege
                ) THEN
                    RAISE EXCEPTION
                        'FAIL: % has % privilege on %',
                        v_role, v_privilege, v_table;
                END IF;
            END LOOP;
        END LOOP;
    END LOOP;

    RAISE NOTICE 'PASS: RLS enabled and direct application-role privileges denied';
END;
$test$;

-- Create two synthetic cases using existing, validated creation RPCs.
DO $test$
DECLARE
    v_employee uuid;
    v_org uuid;
    v_other_org uuid;
    v_case_one uuid;
    v_case_two uuid;
    v_user_id uuid;
    v_team_id uuid;
BEGIN
    SELECT u.auth_user_id, u.organisation_id
      INTO v_employee, v_org
    FROM public.users u
    WHERE u.email = 'employee-a@madzera-test.example'
      AND u.is_active = true;

    IF v_employee IS NULL OR v_org IS NULL THEN
        RAISE EXCEPTION 'Missing employee-a test fixture';
    END IF;

    SELECT id INTO v_other_org
    FROM public.organisations
    WHERE id <> v_org
    ORDER BY id
    LIMIT 1;

    IF v_other_org IS NULL THEN
        RAISE EXCEPTION 'Missing second organisation fixture';
    END IF;

    -- Migration 063: authorise this employee for a destination team.
    SELECT u.id
    INTO STRICT v_user_id
    FROM public.users u
    WHERE u.auth_user_id = v_employee
      AND u.organisation_id = v_org
      AND u.is_active = true;

    INSERT INTO public.teams (organisation_id, name)
    VALUES (v_org, 'MADZERA TEST 036 SUBMISSION TEAM')
    RETURNING id INTO v_team_id;

    INSERT INTO public.team_permission_grants (
        organisation_id,
        team_id,
        user_id,
        permission_type
    )
    VALUES (v_org, v_team_id, v_user_id, 'submit');

    PERFORM set_config(
        'madzera.test036.team',
        v_team_id::text,
        true
    );

    PERFORM set_config('request.jwt.claim.sub', v_employee::text, true);
    PERFORM set_config('madzera.test036.org', v_org::text, true);
    PERFORM set_config('madzera.test036.other_org', v_other_org::text, true);
END;
$test$;

SET LOCAL ROLE authenticated;

SELECT set_config(
    'madzera.test036.case_one',
    public.create_employee_case_v2(
        'TEST 036 CUSTOMS CASE ONE',
        NULL, 'medium', NULL,
        current_setting('madzera.test036.team')::uuid,
        'internal_case'
    )::text,
    true
);

SELECT set_config(
    'madzera.test036.case_two',
    public.create_employee_case_v2(
        'TEST 036 CUSTOMS CASE TWO',
        NULL, 'medium', NULL,
        current_setting('madzera.test036.team')::uuid,
        'internal_case'
    )::text,
    true
);

-- Direct access must fail even for an authenticated employee.
DO $test$
DECLARE
    v_rejected boolean;
BEGIN
    v_rejected := false;
    BEGIN
        EXECUTE 'SELECT 1 FROM public.case_customs_context LIMIT 1';
    EXCEPTION WHEN insufficient_privilege THEN
        v_rejected := true;
    END;
    IF NOT v_rejected THEN
        RAISE EXCEPTION 'FAIL: Authenticated context SELECT accepted';
    END IF;

    v_rejected := false;
    BEGIN
        EXECUTE 'SELECT 1 FROM public.case_operational_references LIMIT 1';
    EXCEPTION WHEN insufficient_privilege THEN
        v_rejected := true;
    END;
    IF NOT v_rejected THEN
        RAISE EXCEPTION 'FAIL: Authenticated reference SELECT accepted';
    END IF;

    RAISE NOTICE 'PASS: Authenticated direct reads rejected';
END;
$test$;

RESET ROLE;

DO $test$
DECLARE
    v_org uuid := current_setting('madzera.test036.org')::uuid;
    v_other_org uuid := current_setting('madzera.test036.other_org')::uuid;
    v_case_one uuid := current_setting('madzera.test036.case_one')::uuid;
    v_case_two uuid := current_setting('madzera.test036.case_two')::uuid;
    v_state text;
BEGIN
    -- Valid context.
    INSERT INTO public.case_customs_context (
        case_id, organisation_id, operation_type, issue_category
    ) VALUES (
        v_case_one, v_org, 'import_declaration', 'document_query'
    );

    -- Cross-organisation context must fail.
    v_state := NULL;
    BEGIN
        INSERT INTO public.case_customs_context (
            case_id, organisation_id, operation_type, issue_category
        ) VALUES (
            v_case_two, v_other_org, 'export_declaration', 'status_query'
        );
    EXCEPTION WHEN foreign_key_violation THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
    END;
    IF v_state IS DISTINCT FROM '23503' THEN
        RAISE EXCEPTION 'FAIL: Cross-organisation context accepted';
    END IF;

    -- Invalid operation must fail.
    v_state := NULL;
    BEGIN
        INSERT INTO public.case_customs_context (
            case_id, organisation_id, operation_type, issue_category
        ) VALUES (
            v_case_two, v_org, 'invalid_operation', 'status_query'
        );
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
    END;
    IF v_state IS DISTINCT FROM '23514' THEN
        RAISE EXCEPTION 'FAIL: Invalid operation accepted';
    END IF;

    -- Valid second context.
    INSERT INTO public.case_customs_context (
        case_id, organisation_id, operation_type, issue_category
    ) VALUES (
        v_case_two, v_org, 'export_declaration', 'status_query'
    );

    -- Multiple references on one case.
    INSERT INTO public.case_operational_references (
        case_id, organisation_id, reference_type, reference_value
    ) VALUES
        (v_case_one, v_org, 'import_mrn', 'TEST036MRN001'),
        (v_case_one, v_org, 'shipment_reference', 'TEST036SHIP001');

    -- Same typed reference can occur on a different case.
    INSERT INTO public.case_operational_references (
        case_id, organisation_id, reference_type, reference_value
    ) VALUES (
        v_case_two, v_org, 'import_mrn', 'TEST036MRN001'
    );

    -- Duplicate on same case must fail.
    v_state := NULL;
    BEGIN
        INSERT INTO public.case_operational_references (
            case_id, organisation_id, reference_type, reference_value
        ) VALUES (
            v_case_one, v_org, 'import_mrn', 'TEST036MRN001'
        );
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
    END;
    IF v_state IS DISTINCT FROM '23505' THEN
        RAISE EXCEPTION 'FAIL: Duplicate reference accepted';
    END IF;

    -- Invalid reference type must fail.
    v_state := NULL;
    BEGIN
        INSERT INTO public.case_operational_references (
            case_id, organisation_id, reference_type, reference_value
        ) VALUES (
            v_case_one, v_org, 'invalid_reference', 'TEST036INVALID'
        );
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
    END;
    IF v_state IS DISTINCT FROM '23514' THEN
        RAISE EXCEPTION 'FAIL: Invalid reference type accepted';
    END IF;

    -- Cross-organisation reference must fail.
    v_state := NULL;
    BEGIN
        INSERT INTO public.case_operational_references (
            case_id, organisation_id, reference_type, reference_value
        ) VALUES (
            v_case_one, v_other_org, 'gmr', 'TEST036GMR001'
        );
    EXCEPTION WHEN foreign_key_violation THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
    END;
    IF v_state IS DISTINCT FROM '23503' THEN
        RAISE EXCEPTION 'FAIL: Cross-organisation reference accepted';
    END IF;

    IF (
        SELECT count(*)
        FROM public.case_operational_references
        WHERE case_id = v_case_one
    ) <> 2 THEN
        RAISE EXCEPTION 'FAIL: Multiple-reference count incorrect';
    END IF;

    RAISE NOTICE 'PASS: Valid customs contexts';
    RAISE NOTICE 'PASS: Cross-organisation foreign keys';
    RAISE NOTICE 'PASS: Operation and reference type constraints';
    RAISE NOTICE 'PASS: Duplicate reference prevention';
    RAISE NOTICE 'PASS: Multiple references and independent cases';
END;
$test$;

ROLLBACK;
