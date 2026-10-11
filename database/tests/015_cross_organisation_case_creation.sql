
-- MADZERA TEST CASE-INSERT-02
-- Cross-organisation case creation must be rejected.
-- Verified in Supabase: 10 October 2026.
-- Expected: PASS - cross-organisation INSERT rejected.
-- All test changes are rolled back.

BEGIN;

CREATE TEMP TABLE madzera_test_result (
    result text
) ON COMMIT DROP;

DO $$
DECLARE
    v_sarah_auth_id uuid;
    v_harbourbridge_id uuid;
BEGIN
    SELECT auth_user_id INTO v_sarah_auth_id
    FROM public.users
    WHERE email = 'sarah@northstar-demo.test';

    SELECT id INTO v_harbourbridge_id
    FROM public.organisations
    WHERE name = 'HarbourBridge Customs Ltd';

    IF v_sarah_auth_id IS NULL
       OR v_harbourbridge_id IS NULL THEN
        RAISE EXCEPTION 'Required test fixtures missing';
    END IF;

    PERFORM set_config(
        'request.jwt.claim.sub',
        v_sarah_auth_id::text,
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
            v_harbourbridge_id,
            'TEST-128: Cross-organisation attempt',
            'manual'
        );

        RAISE EXCEPTION
            'FAIL: Cross-organisation INSERT was allowed';

    EXCEPTION
        WHEN insufficient_privilege THEN
            EXECUTE 'RESET ROLE';

            INSERT INTO madzera_test_result
            VALUES (
                'PASS - cross-organisation INSERT rejected'
            );
    END;
END;
$$;

SELECT result FROM madzera_test_result;

ROLLBACK;
