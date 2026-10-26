-- MADZERA TEST 037
-- Migration 057: Context-first case creation RPC security.
-- Requires employee-a fixture and migrations 056/057.
-- All test-created records are rolled back.

\set ON_ERROR_STOP on

BEGIN;

-- Verify expected fixture and store identity for role-switched tests.
DO $test$
DECLARE
    v_employee uuid;
    v_auth_user uuid;
    v_org uuid;
    v_other_org uuid;
    v_other_customer uuid;
    v_team_id uuid;
BEGIN
    SELECT u.id, u.auth_user_id, u.organisation_id
    INTO v_employee, v_auth_user, v_org
    FROM public.users u
    WHERE u.email = 'employee-a@madzera-test.example'
      AND u.is_active = true;

    IF v_employee IS NULL OR v_auth_user IS NULL OR v_org IS NULL THEN
        RAISE EXCEPTION 'FAIL: Employee fixture missing';
    END IF;

    SELECT o.id INTO v_other_org
    FROM public.organisations o
    WHERE o.id <> v_org
    ORDER BY o.id
    LIMIT 1;

    IF v_other_org IS NULL THEN
        RAISE EXCEPTION 'FAIL: Second organisation fixture missing';
    END IF;

    -- Migration 063: explicitly authorise this employee to submit cases.
    INSERT INTO public.teams (organisation_id, name)
    VALUES (v_org, 'MADZERA TEST 037 SUBMISSION TEAM')
    RETURNING id INTO v_team_id;

    INSERT INTO public.team_permission_grants (
        organisation_id,
        team_id,
        user_id,
        permission_type
    )
    VALUES (v_org, v_team_id, v_employee, 'submit');

    PERFORM set_config(
        'madzera.test037.team',
        v_team_id::text,
        true
    );

    PERFORM set_config('madzera.test037.employee', v_employee::text, true);
    PERFORM set_config('madzera.test037.auth_user', v_auth_user::text, true);
    PERFORM set_config('madzera.test037.org', v_org::text, true);
    PERFORM set_config('madzera.test037.other_org', v_other_org::text, true);

    RAISE NOTICE 'PASS: Employee and organisation fixtures available';
END;
$test$;

-- Anonymous execution must be denied.
SET LOCAL ROLE anon;

DO $test$
DECLARE
    v_error text;
BEGIN
    v_error := NULL;

    BEGIN
        PERFORM public.create_employee_case_v3(
            'TEST 037 ANONYMOUS',
            NULL, 'medium', NULL, NULL, 'internal_case',
            'general_internal', 'general_query', '[]'::jsonb
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error = RETURNED_SQLSTATE;
    END;

    IF v_error IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION
            'FAIL: Anonymous execution not denied as expected: %',
            v_error;
    END IF;

    RAISE NOTICE 'PASS: Anonymous execution denied';
END;
$test$;

RESET ROLE;

-- An authenticated user without an active employee link must fail.
SELECT set_config(
    'request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000099',
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_error text;
BEGIN
    v_error := NULL;

    BEGIN
        PERFORM public.create_employee_case_v3(
            'TEST 037 UNLINKED',
            NULL, 'medium', NULL, NULL, 'internal_case',
            'general_internal', 'general_query', '[]'::jsonb
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error = RETURNED_SQLSTATE;
    END;

    IF v_error IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION
            'FAIL: Unlinked identity not rejected: %',
            v_error;
    END IF;

    RAISE NOTICE 'PASS: Unlinked identity rejected';
END;
$test$;

RESET ROLE;

SELECT set_config(
    'request.jwt.claim.sub',
    current_setting('madzera.test037.auth_user'),
    true
);

-- Create valid case through authenticated RPC.
SET LOCAL ROLE authenticated;

SELECT set_config(
    'madzera.test037.case_id',
    public.create_employee_case_v3(
        'TEST 037 CONTEXT FIRST',
        'Transactional creation verification',
        'high',
        NULL,
        current_setting('madzera.test037.team')::uuid,
        'internal_case',
        'import_declaration',
        'missing_documents',
        '[
          {"reference_type":"import_mrn","reference_value":"TEST037-MRN"},
          {"reference_type":"shipment_reference","reference_value":"TEST037-SHIP"}
        ]'::jsonb
    )::text,
    true
);

RESET ROLE;

-- Inspect the resulting records using the privileged test harness.
DO $test$
DECLARE
    v_case uuid := current_setting('madzera.test037.case_id')::uuid;
    v_org uuid := current_setting('madzera.test037.org')::uuid;
    v_employee uuid := current_setting('madzera.test037.employee')::uuid;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.cases c
        WHERE c.id = v_case
          AND c.organisation_id = v_org
          AND c.case_type = 'internal_case'
          AND c.initiated_by = 'employee'
          AND c.status = 'open'
    ) THEN
        RAISE EXCEPTION 'FAIL: Case creation or attribution incorrect';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_customs_context cc
        WHERE cc.case_id = v_case
          AND cc.organisation_id = v_org
          AND cc.operation_type = 'import_declaration'
          AND cc.issue_category = 'missing_documents'
    ) THEN
        RAISE EXCEPTION 'FAIL: Customs context missing or incorrect';
    END IF;

    IF (
        SELECT count(*)
        FROM public.case_operational_references r
        WHERE r.case_id = v_case
          AND r.organisation_id = v_org
          AND (
              (r.reference_type = 'import_mrn'
               AND r.reference_value = 'TEST037-MRN')
              OR
              (r.reference_type = 'shipment_reference'
               AND r.reference_value = 'TEST037-SHIP')
          )
    ) <> 2 THEN
        RAISE EXCEPTION 'FAIL: Operational references incorrect';
    END IF;

    IF (
        SELECT count(*)
        FROM public.case_events e
        WHERE e.case_id = v_case
          AND e.organisation_id = v_org
          AND e.actor_user_id = v_employee
          AND e.event_type = 'case_created'
    ) <> 1 THEN
        RAISE EXCEPTION 'FAIL: Employee-attributed audit event missing';
    END IF;

    RAISE NOTICE 'PASS: Case, context, references and audit attribution';
END;
$test$;

-- Validation failures must not create cases.
SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_error text;
    v_test jsonb;
BEGIN
    FOR v_test IN
        SELECT value
        FROM (
            VALUES
                ('[{"reference_type":"invalid","reference_value":"X"}]'::jsonb),
                ('[{"reference_type":"import_mrn","reference_value":" "}]'::jsonb),
                ('[{"reference_type":"import_mrn","reference_value":"A"},{"reference_type":"import_mrn","reference_value":"A"}]'::jsonb),
                ('{"reference_type":"import_mrn","reference_value":"A"}'::jsonb),
                ('[{"reference_type":"import_mrn","reference_value":"A","extra":"B"}]'::jsonb)
        ) AS invalid_inputs(value)
    LOOP
        v_error := NULL;

        BEGIN
            PERFORM public.create_employee_case_v3(
                'TEST 037 INVALID REFERENCE',
                NULL, 'medium', NULL, current_setting('madzera.test037.team')::uuid, 'internal_case',
                'general_internal', 'general_query', v_test
            );
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_error = RETURNED_SQLSTATE;
        END;

        IF v_error IS DISTINCT FROM '22023' THEN
            RAISE EXCEPTION
                'FAIL: Invalid reference input not rejected: %, SQLSTATE %',
                v_test, v_error;
        END IF;
    END LOOP;

    v_error := NULL;

    BEGIN
        PERFORM public.create_employee_case_v3(
            'TEST 037 INVALID OPERATION',
            NULL, 'medium', NULL, current_setting('madzera.test037.team')::uuid, 'internal_case',
            'invalid_operation', 'general_query', '[]'::jsonb
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error = RETURNED_SQLSTATE;
    END;

    IF v_error IS DISTINCT FROM '22023' THEN
        RAISE EXCEPTION 'FAIL: Invalid operation accepted';
    END IF;

    RAISE NOTICE 'PASS: Invalid reference and operation inputs rejected';
END;
$test$;

RESET ROLE;

-- Boundary tests: 20 references accepted, 21 rejected.
-- Issue categories must be nonblank, trimmed and at most 100 characters.
SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_references jsonb;
    v_case uuid;
    v_error text;
    v_category text;
BEGIN
    SELECT pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
            'reference_type', 'job_reference',
            'reference_value', 'TEST037-REF-' || n::text
        )
    )
    INTO v_references
    FROM pg_catalog.generate_series(1, 20) AS n;

    v_case := public.create_employee_case_v3(
        'TEST 037 TWENTY REFERENCES',
        NULL, 'medium', NULL, current_setting('madzera.test037.team')::uuid, 'internal_case',
        'general_internal', 'general_query', v_references
    );

    PERFORM set_config(
        'madzera.test037.twenty_case',
        v_case::text,
        true
    );

    RAISE NOTICE 'PASS: 20 references accepted';

    SELECT pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
            'reference_type', 'job_reference',
            'reference_value', 'TEST037-REF-' || n::text
        )
    )
    INTO v_references
    FROM pg_catalog.generate_series(1, 21) AS n;

    v_error := NULL;

    BEGIN
        PERFORM public.create_employee_case_v3(
            'TEST 037 TWENTY ONE REFERENCES',
            NULL, 'medium', NULL, current_setting('madzera.test037.team')::uuid, 'internal_case',
            'general_internal', 'general_query', v_references
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error = RETURNED_SQLSTATE;
    END;

    IF v_error IS DISTINCT FROM '22023' THEN
        RAISE EXCEPTION
            'FAIL: 21 references not rejected: %', v_error;
    END IF;

    RAISE NOTICE 'PASS: 21 references rejected';

    FOREACH v_category IN ARRAY ARRAY[
        '',
        ' ',
        ' leading',
        'trailing ',
        pg_catalog.repeat('X', 101)
    ] LOOP
        v_error := NULL;

        BEGIN
            PERFORM public.create_employee_case_v3(
                'TEST 037 INVALID CATEGORY',
                NULL, 'medium', NULL, current_setting('madzera.test037.team')::uuid, 'internal_case',
                'general_internal', v_category, '[]'::jsonb
            );
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_error = RETURNED_SQLSTATE;
        END;

        IF v_error IS DISTINCT FROM '22023' THEN
            RAISE EXCEPTION
                'FAIL: Invalid category accepted: %, SQLSTATE %',
                v_category, v_error;
        END IF;
    END LOOP;

    RAISE NOTICE 'PASS: Invalid issue categories rejected';
END;
$test$;

RESET ROLE;

-- Verify the successful 20-reference case and rejected inputs.
DO $test$
DECLARE
    v_case uuid := current_setting('madzera.test037.twenty_case')::uuid;
    v_org uuid := current_setting('madzera.test037.org')::uuid;
BEGIN
    IF (
        SELECT count(*)
        FROM public.case_operational_references r
        WHERE r.case_id = v_case
          AND r.organisation_id = v_org
    ) <> 20 THEN
        RAISE EXCEPTION 'FAIL: 20-reference case did not persist 20 references';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.cases
        WHERE title IN (
            'TEST 037 TWENTY ONE REFERENCES',
            'TEST 037 INVALID CATEGORY'
        )
    ) THEN
        RAISE EXCEPTION 'FAIL: Rejected boundary input created a case';
    END IF;

    RAISE NOTICE 'PASS: Reference count and rejected-case integrity';
END;
$test$;

-- Cross-organisation customer and team fixtures.
-- These records exist only inside this test transaction.
DO $test$
DECLARE
    v_other_org uuid := current_setting('madzera.test037.other_org')::uuid;
    v_other_customer uuid;
    v_other_team uuid;
BEGIN
    INSERT INTO public.customers (organisation_id, name)
    VALUES (v_other_org, 'TEST 037 OTHER ORGANISATION CUSTOMER')
    RETURNING id INTO v_other_customer;

    INSERT INTO public.teams (organisation_id, name)
    VALUES (v_other_org, 'TEST 037 OTHER ORGANISATION TEAM')
    RETURNING id INTO v_other_team;

    PERFORM set_config(
        'madzera.test037.other_customer',
        v_other_customer::text,
        true
    );

    PERFORM set_config(
        'madzera.test037.other_team',
        v_other_team::text,
        true
    );

    RAISE NOTICE 'PASS: Cross-organisation fixtures prepared';
END;
$test$;

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_other_customer uuid :=
        current_setting('madzera.test037.other_customer')::uuid;
    v_other_team uuid :=
        current_setting('madzera.test037.other_team')::uuid;
    v_error text;
BEGIN
    v_error := NULL;

    BEGIN
        PERFORM public.create_employee_case_v3(
            'TEST 037 CROSS TENANT CUSTOMER',
            NULL, 'medium',
            v_other_customer, current_setting('madzera.test037.team')::uuid, 'customer_query',
            'import_declaration', 'general_query', '[]'::jsonb
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error = RETURNED_SQLSTATE;
    END;

    IF v_error IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION
            'FAIL: Cross-organisation customer not rejected: %',
            v_error;
    END IF;

    RAISE NOTICE 'PASS: Cross-organisation customer rejected';

    v_error := NULL;

    BEGIN
        PERFORM public.create_employee_case_v3(
            'TEST 037 CROSS TENANT TEAM',
            NULL, 'medium',
            NULL, v_other_team, 'internal_case',
            'general_internal', 'general_query', '[]'::jsonb
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error = RETURNED_SQLSTATE;
    END;

    IF v_error IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION
            'FAIL: Cross-organisation team not rejected: %',
            v_error;
    END IF;

    RAISE NOTICE 'PASS: Cross-organisation team rejected';
END;
$test$;

RESET ROLE;

DO $test$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.cases
        WHERE title IN (
            'TEST 037 CROSS TENANT CUSTOMER',
            'TEST 037 CROSS TENANT TEAM'
        )
    ) THEN
        RAISE EXCEPTION
            'FAIL: Cross-organisation request created a case';
    END IF;

    RAISE NOTICE 'PASS: Cross-organisation requests left no cases';
END;
$test$;

-- Fault injection: reject reference insertion after case/context/audit creation.
-- Test-only trigger and function are removed within this transaction.
CREATE FUNCTION public.test037_reject_reference_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $test_trigger$
BEGIN
    RAISE EXCEPTION
        'TEST037_INJECTED_REFERENCE_FAILURE:%', NEW.case_id
        USING ERRCODE = 'P0001';
END;
$test_trigger$;

CREATE TRIGGER test037_reject_reference_insert
BEFORE INSERT ON public.case_operational_references
FOR EACH ROW
EXECUTE FUNCTION public.test037_reject_reference_insert();

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_error text;
    v_message text;
    v_case_id uuid;
BEGIN
    v_error := NULL;
    v_message := NULL;

    BEGIN
        PERFORM public.create_employee_case_v3(
            'TEST 037 ATOMICITY FAILURE',
            'Test-only forced failure after case creation',
            'medium', NULL, current_setting('madzera.test037.team')::uuid, 'internal_case',
            'general_internal', 'general_query',
            '[{"reference_type":"job_reference","reference_value":"TEST037-ATOMIC"}]'::jsonb
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_error = RETURNED_SQLSTATE,
            v_message = MESSAGE_TEXT;
    END;

    IF v_error IS DISTINCT FROM 'P0001'
       OR v_message IS NULL
       OR v_message !~ '^TEST037_INJECTED_REFERENCE_FAILURE:[0-9a-f-]{36}$'
    THEN
        RAISE EXCEPTION
            'FAIL: Expected injected reference failure; got SQLSTATE %, message %',
            v_error, v_message;
    END IF;

    v_case_id := pg_catalog.split_part(v_message, ':', 2)::uuid;

    PERFORM pg_catalog.set_config(
        'madzera.test037.failed_case_id',
        v_case_id::text,
        true
    );

    RAISE NOTICE 'PASS: Controlled reference-insertion failure captured';
END;
$test$;

RESET ROLE;

-- Privileged test assertions: inspect each table independently.
DO $test$
DECLARE
    v_case_id uuid :=
        current_setting('madzera.test037.failed_case_id')::uuid;
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.cases
        WHERE id = v_case_id
    ) THEN
        RAISE EXCEPTION 'FAIL: Case survived injected failure';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.case_customs_context
        WHERE case_id = v_case_id
    ) THEN
        RAISE EXCEPTION 'FAIL: Customs context survived injected failure';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.case_operational_references
        WHERE case_id = v_case_id
    ) THEN
        RAISE EXCEPTION 'FAIL: Operational reference survived injected failure';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.case_events
        WHERE case_id = v_case_id
    ) THEN
        RAISE EXCEPTION 'FAIL: Audit event survived injected failure';
    END IF;

    RAISE NOTICE
        'PASS: Injected reference failure rolled back case %, context, references and audit',
        v_case_id;
END;
$test$;

-- Remove fault injection before the remaining assertions.
DROP TRIGGER test037_reject_reference_insert
    ON public.case_operational_references;

DROP FUNCTION public.test037_reject_reference_insert();

-- Confirm rejected requests created no persistent rows.
DO $test$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.cases
        WHERE title IN (
            'TEST 037 INVALID REFERENCE',
            'TEST 037 INVALID OPERATION',
            'TEST 037 ANONYMOUS',
            'TEST 037 UNLINKED'
        )
    ) THEN
        RAISE EXCEPTION 'FAIL: Rejected request created a case';
    END IF;

    RAISE NOTICE 'PASS: Rejected requests left no case records';
END;
$test$;

ROLLBACK;
