
-- MADZERA TEST CASE-UPDATE-04
-- Verify employees cannot modify organisation_id.
--
-- Expected:
-- PASS - protected organisation_id UPDATE denied.
--
-- Uses a simulated authenticated employee session.
-- No permanent database changes.

BEGIN;

CREATE TEMP TABLE madzera_test_result (
    result text
) ON COMMIT DROP;

DO $$
DECLARE
    v_sarah_auth_id uuid;
    v_error_code text;
BEGIN
    -- Retrieve the test employee's Auth identity.
    SELECT auth_user_id
    INTO v_sarah_auth_id
    FROM public.users
    WHERE email = 'sarah@northstar-demo.test';

    IF v_sarah_auth_id IS NULL THEN
        RAISE EXCEPTION 'Missing Sarah test fixture';
    END IF;

    PERFORM set_config(
        'request.jwt.claim.sub',
        v_sarah_auth_id::text,
        true
    );

    EXECUTE 'SET LOCAL ROLE authenticated';

    BEGIN
        UPDATE public.cases
        SET organisation_id =
            '00000000-0000-4000-8000-000000000001'
        WHERE external_case_id = 'CASE-DEMO-001';

    EXCEPTION
        WHEN SQLSTATE '42501' THEN
            GET STACKED DIAGNOSTICS
                v_error_code = RETURNED_SQLSTATE;
    END;

    EXECUTE 'RESET ROLE';

    IF v_error_code = '42501' THEN
        INSERT INTO madzera_test_result
        VALUES (
            'PASS - protected organisation_id UPDATE denied'
        );
    ELSE
        RAISE EXCEPTION
            'FAIL: Protected organisation_id UPDATE was not denied';
    END IF;
END;
$$;

SELECT result
FROM madzera_test_result;

ROLLBACK;
