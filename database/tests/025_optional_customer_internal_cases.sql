-- MADZERA TEST 025
-- Migration 041: Optional customer association for internal cases.
-- All test-created records are rolled back.

BEGIN;

DO $test$
DECLARE
    v_auth_user_id uuid;
    v_organisation_id uuid;
    v_other_organisation_id uuid;
    v_customer_id uuid;
    v_other_customer_id uuid;
    v_team_id uuid;
    v_other_team_id uuid;
BEGIN
    SELECT u.auth_user_id, u.organisation_id
    INTO v_auth_user_id, v_organisation_id
    FROM public.users u
    WHERE u.email = 'employee-a@madzera-test.example'
      AND u.is_active = true;

    IF v_auth_user_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Missing authenticated employee fixture';
    END IF;

    SELECT o.id INTO v_other_organisation_id
    FROM public.organisations o
    WHERE o.id <> v_organisation_id
    ORDER BY o.id
    LIMIT 1;

    IF v_other_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Missing second organisation fixture';
    END IF;

    SELECT c.id INTO v_customer_id
    FROM public.customers c
    WHERE c.organisation_id = v_organisation_id
    ORDER BY c.id
    LIMIT 1;

    IF v_customer_id IS NULL THEN
        RAISE EXCEPTION 'Missing primary organisation customer';
    END IF;

    INSERT INTO public.customers (organisation_id, name)
    VALUES (
        v_other_organisation_id,
        'MADZERA TEST 025 OTHER ORGANISATION CUSTOMER'
    )
    RETURNING id INTO v_other_customer_id;

    INSERT INTO public.teams (organisation_id, name)
    VALUES (
        v_organisation_id,
        'MADZERA TEST 025 PRIMARY TEAM'
    )
    RETURNING id INTO v_team_id;

    INSERT INTO public.teams (organisation_id, name)
    VALUES (
        v_other_organisation_id,
        'MADZERA TEST 025 OTHER TEAM'
    )
    RETURNING id INTO v_other_team_id;

    PERFORM set_config(
        'request.jwt.claim.sub',
        v_auth_user_id::text,
        true
    );

    PERFORM set_config(
        'madzera.test.customer_id',
        v_customer_id::text,
        true
    );

    PERFORM set_config(
        'madzera.test.other_customer_id',
        v_other_customer_id::text,
        true
    );

    PERFORM set_config(
        'madzera.test.team_id',
        v_team_id::text,
        true
    );

    PERFORM set_config(
        'madzera.test.other_team_id',
        v_other_team_id::text,
        true
    );

    RAISE NOTICE 'PASS: Transactional test fixtures prepared';
END;
$test$;

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_customer_id uuid :=
        current_setting('madzera.test.customer_id')::uuid;
    v_other_customer_id uuid :=
        current_setting('madzera.test.other_customer_id')::uuid;
    v_team_id uuid :=
        current_setting('madzera.test.team_id')::uuid;
    v_other_team_id uuid :=
        current_setting('madzera.test.other_team_id')::uuid;
    v_case_id uuid;
    v_error_code text;
BEGIN
    -- Internal case with a customer.
    v_case_id := public.create_employee_case_v2(
        'MADZERA TEST 025 INTERNAL WITH CUSTOMER',
        NULL, 'medium', v_customer_id, v_team_id, 'internal_case'
    );

    PERFORM set_config(
        'madzera.test.internal_with_customer',
        v_case_id::text,
        true
    );

    RAISE NOTICE 'PASS: Internal case with customer created';

    -- Internal case without a customer.
    v_case_id := public.create_employee_case_v2(
        'MADZERA TEST 025 INTERNAL WITHOUT CUSTOMER',
        NULL, 'medium', NULL, v_team_id, 'internal_case'
    );

    PERFORM set_config(
        'madzera.test.internal_without_customer',
        v_case_id::text,
        true
    );

    RAISE NOTICE 'PASS: Internal case without customer created';

    -- Customer enquiry with a customer.
    v_case_id := public.create_employee_case_v2(
        'MADZERA TEST 025 CUSTOMER ENQUIRY',
        NULL, 'medium', v_customer_id, v_team_id, 'customer_query'
    );

    PERFORM set_config(
        'madzera.test.customer_enquiry',
        v_case_id::text,
        true
    );

    RAISE NOTICE 'PASS: Customer enquiry with customer created';

    -- Customer enquiry without a customer must fail.
    v_error_code := NULL;
    BEGIN
        PERFORM public.create_employee_case_v2(
            'MADZERA TEST 025 INVALID CUSTOMER ENQUIRY',
            NULL, 'medium', NULL, v_team_id, 'customer_query'
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error_code = RETURNED_SQLSTATE;
    END;

    IF v_error_code IS DISTINCT FROM '22023' THEN
        RAISE EXCEPTION 'FAIL: Customer enquiry without customer accepted';
    END IF;

    RAISE NOTICE 'PASS: Customer enquiry requires customer';

    -- Cross-organisation customer must fail.
    v_error_code := NULL;
    BEGIN
        PERFORM public.create_employee_case_v2(
            'MADZERA TEST 025 CROSS TENANT CUSTOMER',
            NULL, 'medium', v_other_customer_id, v_team_id, 'internal_case'
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error_code = RETURNED_SQLSTATE;
    END;

    IF v_error_code IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION 'FAIL: Cross-organisation customer accepted';
    END IF;

    RAISE NOTICE 'PASS: Cross-organisation customer rejected';

    -- Cross-organisation team must fail.
    v_error_code := NULL;
    BEGIN
        PERFORM public.create_employee_case_v2(
            'MADZERA TEST 025 CROSS TENANT TEAM',
            NULL, 'medium', v_customer_id, v_other_team_id, 'internal_case'
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error_code = RETURNED_SQLSTATE;
    END;

    IF v_error_code IS DISTINCT FROM '42501' THEN
        RAISE EXCEPTION 'FAIL: Cross-organisation team accepted';
    END IF;

    RAISE NOTICE 'PASS: Cross-organisation team rejected';

    -- Invalid case type must fail.
    v_error_code := NULL;
    BEGIN
        PERFORM public.create_employee_case_v2(
            'MADZERA TEST 025 INVALID TYPE',
            NULL, 'medium', NULL, v_team_id, 'invalid_type'
        );
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_error_code = RETURNED_SQLSTATE;
    END;

    IF v_error_code IS DISTINCT FROM '22023' THEN
        RAISE EXCEPTION 'FAIL: Invalid case type accepted';
    END IF;

    RAISE NOTICE 'PASS: Invalid case type rejected';
END;
$test$;

RESET ROLE;

DO $test$
DECLARE
    v_with_customer uuid :=
        current_setting('madzera.test.internal_with_customer')::uuid;
    v_without_customer uuid :=
        current_setting('madzera.test.internal_without_customer')::uuid;
    v_customer_enquiry uuid :=
        current_setting('madzera.test.customer_enquiry')::uuid;
    v_customer_id uuid :=
        current_setting('madzera.test.customer_id')::uuid;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.cases
        WHERE id = v_with_customer
          AND case_type = 'internal_case'
          AND customer_id = v_customer_id
          AND case_reference ~ '^CAS[0-9]{10}$'
    ) THEN
        RAISE EXCEPTION 'FAIL: Internal case/customer classification';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.cases
        WHERE id = v_without_customer
          AND case_type = 'internal_case'
          AND customer_id IS NULL
          AND case_reference ~ '^CAS[0-9]{10}$'
    ) THEN
        RAISE EXCEPTION 'FAIL: Internal case without customer';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.cases
        WHERE id = v_customer_enquiry
          AND case_type = 'customer_query'
          AND customer_id = v_customer_id
          AND case_reference ~ '^CAS[0-9]{10}$'
    ) THEN
        RAISE EXCEPTION 'FAIL: Customer enquiry classification';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM public.case_events
        WHERE case_id IN (
            v_with_customer, v_without_customer, v_customer_enquiry
        )
          AND event_type = 'case_created'
    ) <> 3 THEN
        RAISE EXCEPTION 'FAIL: Creation audit events missing';
    END IF;

    RAISE NOTICE 'PASS: Case types and customer associations';
    RAISE NOTICE 'PASS: Structured case references';
    RAISE NOTICE 'PASS: Creation audit events';
END;
$test$;

ROLLBACK;
