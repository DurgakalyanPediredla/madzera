-- MADZERA MIGRATION 039
-- Securely resume an existing, unexpired exclusive case session.
-- Read-only validation: never acquires, renews, replaces or releases a lock.

BEGIN;

CREATE FUNCTION public.resume_employee_case_session(
    p_case_id UUID,
    p_lock_token UUID
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id UUID;
    v_organisation_id UUID;
    v_expires_at TIMESTAMPTZ;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required'
            USING ERRCODE = '42501';
    END IF;

    IF p_case_id IS NULL OR p_lock_token IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT l.expires_at
    INTO v_expires_at
    FROM public.case_locks AS l
    INNER JOIN public.cases AS c
        ON c.id = l.case_id
       AND c.organisation_id = l.organisation_id
    WHERE l.case_id = p_case_id
      AND l.organisation_id = v_organisation_id
      AND c.organisation_id = v_organisation_id
      AND l.locked_by_user_id = v_employee_id
      AND l.lock_token = p_lock_token
      AND l.expires_at > clock_timestamp();

    RETURN v_expires_at;
END;
$function$;

REVOKE ALL ON FUNCTION public.resume_employee_case_session(UUID, UUID)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.resume_employee_case_session(UUID, UUID)
TO authenticated;

COMMIT;
