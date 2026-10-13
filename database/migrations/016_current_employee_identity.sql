-- MADZERA MIGRATION 016
-- Restore the employee identity helper present in the live database.
-- Required by the case-locking functions introduced in later migrations.

BEGIN;

CREATE OR REPLACE FUNCTION public.current_employee_id()
RETURNS UUID
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT u.id
    FROM public.users AS u
    WHERE u.auth_user_id = (SELECT auth.uid())
      AND u.is_active = TRUE
$$;

REVOKE ALL ON FUNCTION public.current_employee_id()
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.current_employee_id()
TO authenticated;

COMMIT;
