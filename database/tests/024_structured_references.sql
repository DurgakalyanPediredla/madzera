-- MADZERA TEST 024
-- Migration 040: Structured customer and case references.
-- All data changes are rolled back.

\set ON_ERROR_STOP on

BEGIN;

DO $test$
DECLARE
    v_org_a uuid := '0a316877-23d4-4dc3-b0ed-350208d68fb3';
    v_org_b uuid := 'cbd6a8ae-adf3-4099-9352-1862e1751dea';
    v_customer_a text;
    v_customer_b text;
    v_case_a text;
    v_case_b text;
    v_case_next_year text;
    v_case_id uuid;
    v_rejected boolean;
    v_expected bigint;
    v_year integer := EXTRACT(
        YEAR FROM CURRENT_TIMESTAMP AT TIME ZONE 'UTC'
    )::integer;
BEGIN
    -- Check existing references and uniqueness.
    IF EXISTS (
        SELECT 1
        FROM public.customers
        WHERE customer_reference IS NULL
    ) OR EXISTS (
        SELECT 1
        FROM public.cases
        WHERE case_reference IS NULL
    ) THEN
        RAISE EXCEPTION 'FAIL: Existing reference is NULL';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.customers
        GROUP BY organisation_id, customer_reference
        HAVING COUNT(*) > 1
    ) OR EXISTS (
        SELECT 1 FROM public.cases
        GROUP BY organisation_id, case_reference
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION 'FAIL: Duplicate existing references';
    END IF;

    RAISE NOTICE 'PASS: Existing references populated and unique';

    -- Customer reference generation.
    INSERT INTO public.customers (organisation_id, name)
    VALUES (v_org_a, 'MADZERA TEST 024 CUSTOMER A')
    RETURNING customer_reference INTO v_customer_a;

    INSERT INTO public.customers (organisation_id, name)
    VALUES (v_org_b, 'MADZERA TEST 024 CUSTOMER B')
    RETURNING customer_reference INTO v_customer_b;

    SELECT last_number
    INTO v_expected
    FROM madzera_internal.reference_counters
    WHERE organisation_id = v_org_a
      AND reference_kind = 'customer'
      AND reference_year = 0;

    IF v_expected <> 2
       OR v_customer_a <> 'CUS000002'
       OR v_customer_b <> 'CUS000001' THEN
        RAISE EXCEPTION
            'FAIL: Customer numbering incorrect: %, %',
            v_customer_a, v_customer_b;
    END IF;

    RAISE NOTICE 'PASS: Customer reference generation and tenant counters';

    -- Case reference generation for the current UTC year.
    INSERT INTO public.cases (
        organisation_id, title, source, case_type, initiated_by
    )
    VALUES (
        v_org_a, 'MADZERA TEST 024 CASE A',
        'manual', 'internal_case', 'system'
    )
    RETURNING id, case_reference INTO v_case_id, v_case_a;

    INSERT INTO public.cases (
        organisation_id, title, source, case_type, initiated_by
    )
    VALUES (
        v_org_b, 'MADZERA TEST 024 CASE B',
        'manual', 'internal_case', 'system'
    )
    RETURNING case_reference INTO v_case_b;

    SELECT last_number
    INTO v_expected
    FROM madzera_internal.reference_counters
    WHERE organisation_id = v_org_a
      AND reference_kind = 'case'
      AND reference_year = v_year;

    IF v_case_a <> 'CAS' || v_year::text
                   || lpad(v_expected::text, 6, '0')
       OR v_case_b <> 'CAS' || v_year::text || '000002' THEN
        RAISE EXCEPTION
            'FAIL: Case numbering incorrect: %, %',
            v_case_a, v_case_b;
    END IF;

    RAISE NOTICE 'PASS: Case reference generation and tenant counters';

    -- Next year's counter starts independently.
    INSERT INTO public.cases (
        organisation_id, title, source, case_type,
        initiated_by, created_at
    )
    VALUES (
        v_org_a, 'MADZERA TEST 024 NEXT YEAR',
        'manual', 'internal_case', 'system',
        make_timestamptz(v_year + 1, 1, 1, 0, 0, 0, 'UTC')
    )
    RETURNING case_reference INTO v_case_next_year;

    IF v_case_next_year <>
       'CAS' || (v_year + 1)::text || '000001' THEN
        RAISE EXCEPTION
            'FAIL: Annual case reset incorrect: %',
            v_case_next_year;
    END IF;

    RAISE NOTICE 'PASS: Annual UTC case counter reset';

    -- Customer references cannot be modified.
    v_rejected := false;
    BEGIN
        UPDATE public.customers
        SET customer_reference = 'CUS999999'
        WHERE name = 'MADZERA TEST 024 CUSTOMER A';
    EXCEPTION WHEN insufficient_privilege THEN
        v_rejected := true;
    END;

    IF NOT v_rejected THEN
        RAISE EXCEPTION 'FAIL: Customer reference modification allowed';
    END IF;

    RAISE NOTICE 'PASS: Customer reference immutable';

    -- Case references cannot be modified.
    v_rejected := false;
    BEGIN
        UPDATE public.cases
        SET case_reference = 'CAS9999999999'
        WHERE id = v_case_id;
    EXCEPTION WHEN insufficient_privilege THEN
        v_rejected := true;
    END;

    IF NOT v_rejected THEN
        RAISE EXCEPTION 'FAIL: Case reference modification allowed';
    END IF;

    RAISE NOTICE 'PASS: Case reference immutable';

    -- Direct access to private counter state is denied.
    IF has_schema_privilege(
        'authenticated', 'madzera_internal', 'USAGE'
    ) OR has_schema_privilege(
        'anon', 'madzera_internal', 'USAGE'
    ) OR has_table_privilege(
        'authenticated',
        'madzera_internal.reference_counters',
        'UPDATE'
    ) THEN
        RAISE EXCEPTION 'FAIL: Private counter access exposed';
    END IF;

    RAISE NOTICE 'PASS: Private counter permissions';
END;
$test$;

-- Verify authenticated employee creation still uses the trigger.
SELECT set_config(
    'request.jwt.claim.sub',
    'dc36ef25-8ff9-4845-857c-2a191ecc2b4a',
    true
);

SET LOCAL ROLE authenticated;

DO $test$
DECLARE
    v_case_id uuid;
BEGIN
    v_case_id := public.create_employee_case(
        'MADZERA TEST 024 AUTHENTICATED CASE'
    );

    IF v_case_id IS NULL THEN
        RAISE EXCEPTION 'FAIL: Authenticated case creation returned NULL';
    END IF;

    RAISE NOTICE 'PASS: Authenticated case creation RPC';
END;
$test$;

RESET ROLE;

DO $test$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.cases
        WHERE title = 'MADZERA TEST 024 AUTHENTICATED CASE'
          AND case_reference ~ '^CAS[0-9]{10}$'
    ) THEN
        RAISE EXCEPTION
            'FAIL: Authenticated case missing structured reference';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_events e
        JOIN public.cases c ON c.id = e.case_id
        WHERE c.title = 'MADZERA TEST 024 AUTHENTICATED CASE'
          AND e.event_type = 'case_created'
    ) THEN
        RAISE EXCEPTION
            'FAIL: Authenticated case missing creation audit event';
    END IF;

    RAISE NOTICE 'PASS: Authenticated RPC reference and audit event';
END;
$test$;

ROLLBACK;
