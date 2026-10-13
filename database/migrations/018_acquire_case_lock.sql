-- MADZERA MIGRATION 018
-- Reproduce the live exclusive case-lock acquisition function.
-- Direct execution is restricted to privileged database roles.

BEGIN;

CREATE OR REPLACE FUNCTION public.acquire_case_lock(p_case_id UUID)
RETURNS TABLE (
    acquired BOOLEAN,
    lock_expires_at TIMESTAMPTZ,
    lock_token UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id UUID;
    v_organisation_id UUID;
    v_expires_at TIMESTAMPTZ;
    v_token UUID;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases c
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
    ) THEN
        RAISE EXCEPTION 'Case not found or access denied';
    END IF;

    INSERT INTO public.case_locks (
        case_id,
        organisation_id,
        locked_by_user_id,
        lock_token,
        locked_at,
        expires_at
    )
    VALUES (
        p_case_id,
        v_organisation_id,
        v_employee_id,
        gen_random_uuid(),
        NOW(),
        NOW() + INTERVAL '5 minutes'
    )
    ON CONFLICT (case_id)
    DO UPDATE SET
        locked_by_user_id = EXCLUDED.locked_by_user_id,
        lock_token = EXCLUDED.lock_token,
        locked_at = EXCLUDED.locked_at,
        expires_at = EXCLUDED.expires_at
    WHERE public.case_locks.expires_at <= NOW()
    RETURNING
        public.case_locks.expires_at,
        public.case_locks.lock_token
    INTO v_expires_at, v_token;

    RETURN QUERY
    SELECT
        v_token IS NOT NULL,
        v_expires_at,
        v_token;
END;
$function$;

REVOKE ALL ON FUNCTION public.acquire_case_lock(UUID)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.acquire_case_lock(UUID)
TO service_role, postgres;

COMMIT;
