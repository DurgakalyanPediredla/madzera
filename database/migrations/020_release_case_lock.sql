-- MADZERA MIGRATION 020
-- Release a case lock only when employee, organisation and token match.
-- Direct execution is restricted to privileged database roles.

BEGIN;

CREATE OR REPLACE FUNCTION public.release_case_lock(
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
    v_deleted_count INTEGER;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required';
    END IF;

    IF p_lock_token IS NULL THEN
        RETURN FALSE;
    END IF;

    DELETE FROM public.case_locks
    WHERE case_id = p_case_id
      AND organisation_id = v_organisation_id
      AND locked_by_user_id = v_employee_id
      AND lock_token = p_lock_token;

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

    RETURN v_deleted_count > 0;
END;
$function$;

REVOKE ALL ON FUNCTION public.release_case_lock(UUID, UUID)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.release_case_lock(UUID, UUID)
TO service_role, postgres;

COMMIT;
