
-- MADZERA TEST CASE-INSERT-03
-- Reject case creation from an unlinked identity.
--
-- Expected:
-- PASS - unlinked identity INSERT rejected.
--
-- Uses a simulated authenticated session.
-- No permanent database changes.

BEGIN;

CREATE TEMP TABLE madzera_test_result (
    result text
) ON COMMIT DROP;

DO $$
DECLARE
    v_northstar_id uuid;
    v_error_code text;
BEGIN
    SELECT id
    INTO v_northstar_id
    FROM public.organisations
    WHERE name = 'NorthStar Customs Ltd';

    IF v_northstar_id IS NULL THEN
        RAISE EXCEPTION 'Missing NorthStar test fixture';
    END IF;

    -- Simulate an identity not linked to an employee.
    PERFORM set_config(
        'request.jwt.claim.sub',
        '00000000-0000-4000-8000-000000000001',
        true
    );

    EXECUTE 'SET LOCAL ROLE authenticated';

    BEGIN
        INSERT INTO public.cases (
            organisation_id,
            title,
            source
        )
        VALUES (
            v_northstar_id,
            'TEST-130: Unlinked identity attempt',
            'manual'
        );

    EXCEPTION
        WHEN SQLSTATE '42501' THEN
            GET STACKED DIAGNOSTICS
                v_error_code = RETURNED_SQLSTATE;
    END;

    EXECUTE 'RESET ROLE';

    IF v_error_code = '42501' THEN
        INSERT INTO madzera_test_result
        VALUES ('PASS - unlinked identity INSERT rejected');
    ELSE
        RAISE EXCEPTION
            'FAIL: Unlinked identity INSERT was not rejected';
    END IF;
END;
$$;

SELECT result FROM madzera_test_result;

ROLLBACK;
