
-- MADZERA TEST RLS-11
-- Unlinked authenticated identity access.
-- Previously executed successfully in Supabase.
-- Expected: All three visible record counts = 0.

BEGIN;

SELECT set_config(
    'request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000001',
    true
);

SET LOCAL ROLE authenticated;

SELECT
    (SELECT COUNT(*) FROM public.organisations)
        AS visible_organisations,

    (SELECT COUNT(*) FROM public.teams)
        AS visible_teams,

    (SELECT COUNT(*) FROM public.team_members)
        AS visible_team_memberships;

ROLLBACK;
