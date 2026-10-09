
-- MADZERA MIGRATION 003
-- Enforce same-organisation team memberships.
-- Structural database migration.

BEGIN;

-- 1. Add organisation identifier.
ALTER TABLE public.team_members
ADD COLUMN organisation_id UUID;

-- 2. Populate existing memberships.
UPDATE public.team_members AS tm
SET organisation_id = t.organisation_id
FROM public.teams AS t
WHERE tm.team_id = t.id;

-- 3. Require an organisation for every membership.
ALTER TABLE public.team_members
ALTER COLUMN organisation_id SET NOT NULL;

-- 4. Create composite unique constraints required
--    by PostgreSQL foreign-key enforcement.
ALTER TABLE public.teams
ADD CONSTRAINT uq_teams_id_organisation
UNIQUE (id, organisation_id);

ALTER TABLE public.users
ADD CONSTRAINT uq_users_id_organisation
UNIQUE (id, organisation_id);

-- 5. Enforce team/organisation consistency.
ALTER TABLE public.team_members
ADD CONSTRAINT fk_team_members_team_organisation
FOREIGN KEY (team_id, organisation_id)
REFERENCES public.teams (id, organisation_id);

-- 6. Enforce employee/organisation consistency.
ALTER TABLE public.team_members
ADD CONSTRAINT fk_team_members_user_organisation
FOREIGN KEY (user_id, organisation_id)
REFERENCES public.users (id, organisation_id);

COMMIT;
