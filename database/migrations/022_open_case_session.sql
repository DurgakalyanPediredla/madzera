-- MADZERA MIGRATION 022
-- Open an exclusive case session and record a successful opening.
-- Requires an authenticated active employee in the case's organisation.

BEGIN;

CREATE OR REPLACE FUNCTION public.open_case_session(p_case_id UUID)
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
    v_acquired BOOLEAN;
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

    SELECT
        l.acquired,
        l.lock_expires_at,
        l.lock_token
    INTO
        v_acquired,
        v_expires_at,
        v_token
    FROM public.acquire_case_lock(p_case_id) AS l;

    IF v_acquired THEN
        PERFORM public.record_case_opened(p_case_id);
    END IF;

    RETURN QUERY
    SELECT
        COALESCE(v_acquired, FALSE),
        v_expires_at,
        v_token;
END;
$function$;

REVOKE ALL ON FUNCTION public.open_case_session(UUID)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.open_case_session(UUID)
TO authenticated, service_role;

COMMIT;
