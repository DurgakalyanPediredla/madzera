
-- MADZERA MIGRATION 004
-- Organisation and team read policies.
-- No INSERT, UPDATE or DELETE permissions added.

BEGIN;

CREATE POLICY "Employees can view their organisation"
ON public.organisations
FOR SELECT
TO authenticated
USING (
    id = (SELECT public.current_user_organisation_id())
);

CREATE POLICY "Employees can view their organisation teams"
ON public.teams
FOR SELECT
TO authenticated
USING (
    organisation_id =
        (SELECT public.current_user_organisation_id())
);

CREATE POLICY "Employees can view their organisation team memberships"
ON public.team_members
FOR SELECT
TO authenticated
USING (
    organisation_id =
        (SELECT public.current_user_organisation_id())
);

COMMIT;
