-- Madzera Database Migration 001
-- Authentication mapping and organisation-level read policies

-- 1. Link Madzera employees to Supabase Auth identities

ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS auth_user_id UUID
REFERENCES auth.users(id);

CREATE UNIQUE INDEX IF NOT EXISTS
idx_users_auth_user_id
ON public.users(auth_user_id);


-- 2. Resolve the current authenticated employee's organisation

CREATE OR REPLACE FUNCTION public.current_user_organisation_id()
RETURNS UUID
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT u.organisation_id
    FROM public.users AS u
    WHERE u.auth_user_id = (SELECT auth.uid())
      AND u.is_active = TRUE
$$;

REVOKE ALL ON FUNCTION public.current_user_organisation_id()
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.current_user_organisation_id()
TO authenticated;


-- 3. Organisation-level employee visibility

CREATE POLICY "Employees can view users in their organisation"
ON public.users
FOR SELECT
TO authenticated
USING (
    organisation_id =
    (SELECT public.current_user_organisation_id())
);


-- 4. Organisation-level customer visibility

CREATE POLICY "Employees can view customers in their organisation"
ON public.customers
FOR SELECT
TO authenticated
USING (
    organisation_id =
    (SELECT public.current_user_organisation_id())
);


-- 5. Organisation-level case visibility

CREATE POLICY "Employees can view cases in their organisation"
ON public.cases
FOR SELECT
TO authenticated
USING (
    organisation_id =
    (SELECT public.current_user_organisation_id())
);
