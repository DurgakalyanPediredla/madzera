-- MADZERA MIGRATION 026
-- Return full case details only to the employee holding
-- the correct, unexpired, organisation-scoped case lock.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_locked_case_details(
    p_case_id UUID,
    p_lock_token UUID
)
RETURNS SETOF public.cases
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id UUID;
    v_organisation_id UUID;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL
       OR v_organisation_id IS NULL
       OR p_case_id IS NULL
       OR p_lock_token IS NULL
    THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT c.*
    FROM public.cases AS c
    INNER JOIN public.case_locks AS l
        ON l.case_id = c.id
       AND l.organisation_id = c.organisation_id
    WHERE c.id = p_case_id
      AND c.organisation_id = v_organisation_id
      AND l.locked_by_user_id = v_employee_id
      AND l.lock_token = p_lock_token
      AND l.expires_at > NOW();
END;
$function$;

REVOKE ALL ON FUNCTION public.get_locked_case_details(UUID, UUID)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_locked_case_details(UUID, UUID)
TO authenticated, service_role;

COMMIT;
