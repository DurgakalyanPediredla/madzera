-- MADZERA MIGRATION 024
-- Close an employee's case session by releasing its exclusive lock.
-- Record the exit audit event only after successful lock release.

BEGIN;

CREATE OR REPLACE FUNCTION public.close_case_session(
    p_case_id UUID,
    p_lock_token UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id UUID;
    v_organisation_id UUID;
    v_released BOOLEAN;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required';
    END IF;

    IF p_lock_token IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Confirm this employee holds the specified session lock.
    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks l
        WHERE l.case_id = p_case_id
          AND l.organisation_id = v_organisation_id
          AND l.locked_by_user_id = v_employee_id
          AND l.lock_token = p_lock_token
    ) THEN
        RETURN FALSE;
    END IF;

    -- Release the lock using the token-aware function.
    v_released := public.release_case_lock(
        p_case_id,
        p_lock_token
    );

    IF NOT v_released THEN
        RETURN FALSE;
    END IF;

    -- Record the exit only after successful release.
    PERFORM public.record_case_exit(p_case_id);

    RETURN TRUE;
END;
$function$;

REVOKE ALL ON FUNCTION public.close_case_session(UUID, UUID)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.close_case_session(UUID, UUID)
TO authenticated, service_role;

COMMIT;
