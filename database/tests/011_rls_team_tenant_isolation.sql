
-- MADZERA TEST RLS-09
-- Team tenant isolation.
-- Previously executed successfully in Supabase.
-- Expected: Only NorthStar teams are visible.

BEGIN;

SELECT set_config(
    'request.jwt.claim.sub',
    (
        SELECT auth_user_id::text
        FROM public.users
        WHERE email = 'sarah@northstar-demo.test'
    ),
    true
);

SET LOCAL ROLE authenticated;

SELECT
    t.name AS team_name,
    o.name AS organisation_name
FROM public.teams AS t
JOIN public.organisations AS o
    ON o.id = t.organisation_id
ORDER BY o.name, t.name;

ROLLBACK;
