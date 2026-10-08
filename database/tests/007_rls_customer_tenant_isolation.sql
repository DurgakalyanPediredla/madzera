
-- MADZERA SECURITY TEST: RLS-05
-- Cross-organisation customer isolation.
--
-- Environment: Synthetic Supabase development database.
-- Expected: PASS.
-- Sarah sees NorthStar's customer only.
-- HarbourBridge's customer must not be visible.
-- No persistent database changes.

BEGIN;

-- Establish Sarah's identity before role switching.
SELECT set_config(
    'request.jwt.claim.sub',
    (
        SELECT auth_user_id::text
        FROM public.users
        WHERE email = 'sarah@northstar-demo.test'
    ),
    true
);

-- Simulate an authenticated database session.
SET LOCAL ROLE authenticated;

-- Evaluate customer visibility under RLS.
WITH visible_customers AS (
    SELECT
        external_customer_id,
        name,
        organisation_id
    FROM public.customers
)
SELECT
    'RLS-05' AS test_id,
    CASE
        WHEN COUNT(*) = 1
         AND COUNT(*) FILTER (
             WHERE external_customer_id = 'CUST-1001'
               AND name = 'ABC Imports Ltd'
         ) = 1
         AND COUNT(*) FILTER (
             WHERE external_customer_id = 'CUST-HB-1001'
               AND name = 'Seabrook Trading Ltd'
         ) = 0
         AND COUNT(*) FILTER (
             WHERE organisation_id =
                 (SELECT public.current_user_organisation_id())
         ) = 1
        THEN 'PASS'
        ELSE 'FAIL'
    END AS result,
    COUNT(*) AS visible_customer_count,
    COUNT(*) FILTER (
        WHERE external_customer_id = 'CUST-HB-1001'
    ) AS harbourbridge_customers_visible
FROM visible_customers;

ROLLBACK;
