
-- MADZERA TEST RLS-08
-- Organisation tenant isolation.
-- Previously executed successfully in Supabase.
-- Expected: NorthStar visible, HarbourBridge hidden.

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
    name AS organisation_name,
    COUNT(*) AS visible_records
FROM public.organisations
GROUP BY name
ORDER BY name;

ROLLBACK;
