-- MADZERA MIGRATION 025
-- Display active case locks within the employee's organisation.
-- Exposes the lock holder's name and expiry, never the lock token.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_active_case_locks()
RETURNS TABLE (
    case_id UUID,
    employee_name VARCHAR,
    lock_expires_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT
        l.case_id,
        u.full_name AS employee_name,
        l.expires_at AS lock_expires_at
    FROM public.case_locks AS l
    INNER JOIN public.users AS u
        ON u.id = l.locked_by_user_id
       AND u.organisation_id = l.organisation_id
    WHERE l.organisation_id = public.current_user_organisation_id()
      AND l.expires_at > NOW()
      AND u.is_active = TRUE;
$function$;

REVOKE ALL ON FUNCTION public.get_active_case_locks()
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_active_case_locks()
TO authenticated, service_role;

COMMIT;
