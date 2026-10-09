
-- MADZERA TEST RLS-10
-- Team membership tenant isolation.
-- Previously executed successfully in Supabase.
-- Expected: Only NorthStar memberships visible.

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
    u.email AS employee_email,
    t.name AS team_name,
    o.name AS organisation_name
FROM public.team_members AS tm
JOIN public.users AS u
    ON u.id = tm.user_id
JOIN public.teams AS t
    ON t.id = tm.team_id
JOIN public.organisations AS o
    ON o.id = tm.organisation_id
ORDER BY o.name, t.name, u.email;

ROLLBACK;
