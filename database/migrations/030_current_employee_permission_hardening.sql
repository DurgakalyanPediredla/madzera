-- MADZERA MIGRATION 030
-- Purpose: Remove explicit anonymous execution access
-- from the employee identity helper.
--
-- Migration 016 revoked PUBLIC execution, but the
-- Supabase anon role retained an explicit EXECUTE grant.
--
-- Keep authenticated and service_role access intact.

BEGIN;

REVOKE EXECUTE ON FUNCTION public.current_employee_id()
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.current_employee_id()
TO authenticated, service_role;

COMMIT;
