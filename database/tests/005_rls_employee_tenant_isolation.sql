
-- MADZERA SECURITY TEST: RLS-03
-- Cross-organisation employee isolation.
--
-- Environment: Synthetic Supabase development database.
-- Expected: PASS.
-- Sarah sees four NorthStar employees.
-- Daniel Brooks from HarbourBridge must be hidden.
-- No persistent database changes.

BEGIN;

-- Establish Sarah's authenticated identity
-- before switching to the restricted database role.
SELECT set_config(
    'request.jwt.claim.sub',
    (
        SELECT auth_user_id::text
        FROM public.users
        WHERE email = 'sarah@northstar-demo.test'
    ),
    true
);

-- Simulate an authenticated session.
SET LOCAL ROLE authenticated;

-- Evaluate employee visibility under RLS.
WITH visible_employees AS (
    SELECT
        u.id,
        u.email,
        u.organisation_id
    FROM public.users AS u
)
SELECT
    'RLS-03' AS test_id,
    CASE
        WHEN COUNT(*) = 4
         AND COUNT(*) FILTER (
             WHERE email = 'daniel@harbourbridge-demo.test'
         ) = 0
         AND COUNT(*) FILTER (
             WHERE organisation_id =
                 (SELECT public.current_user_organisation_id())
         ) = 4
        THEN 'PASS'
        ELSE 'FAIL'
    END AS result,
    COUNT(*) AS visible_employee_count,
    COUNT(*) FILTER (
        WHERE email = 'daniel@harbourbridge-demo.test'
    ) AS harbourbridge_employees_visible
FROM visible_employees;

ROLLBACK;
