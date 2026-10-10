
-- MADZERA TEST CASE-INSERT-02
-- Migration 013: Cross-organisation INSERT isolation.
--
-- Expected: PASS - cross-organisation INSERT rejected.
-- Uses Sarah's simulated authenticated identity.
-- No permanent database changes.

BEGIN;

DO $$
DECLARE
    v_sarah_auth_id uuid;
    v_harbourbridge_id uuid;
    v_rejected boolean := false;
BEGIN
    SELECT auth_user_id
    INTO v_sarah_auth_id
    FROM public.users
    WHERE email = 'sarah@northstar-demo.test';

    SELECT id
    INTO v_harbourbridge_id
    FROM public.organisations
    WHERE name = 'HarbourBridge Customs Ltd';

    IF v_sarah_auth_id IS NULL
       OR v_harbourbridge_id IS NULL THEN
        RAISE EXCEPTION 'Missing required test fixture';
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
            description,
            source
        )
        VALUES (
            v_harbourbridge_id,
            'TEST-101: Cross-organisation attempt',
            'Must be rejected by RLS.',
            'manual'
        );

    EXCEPTION
        WHEN insufficient_privilege THEN
            v_rejected := true;
    END;

    IF NOT v_rejected THEN
        RAISE EXCEPTION
            'FAIL: Cross-organisation INSERT was allowed';
    END IF;

    RAISE NOTICE
        'PASS: Cross-organisation INSERT rejected';
END;
$$;

ROLLBACK;
