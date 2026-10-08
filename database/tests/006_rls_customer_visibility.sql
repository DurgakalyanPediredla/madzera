
-- MADZERA SECURITY TEST: RLS-04
-- Own-organisation customer visibility.
--
-- Environment: Synthetic development database.
-- Expected: PASS, 1 visible customer.
-- No persistent database changes.

BEGIN;

-- Establish Sarah's authenticated identity
-- before switching to the restricted role.
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

-- Evaluate customer visibility under RLS.
WITH visible_customers AS (
    SELECT
        customer_code,
        organisation_id
    FROM public.customers
)
SELECT
    'RLS-04' AS test_id,
    CASE
        WHEN COUNT(*) = 1
         AND COUNT(*) FILTER (
             WHERE customer_code = 'CUST-1001'
         ) = 1
         AND COUNT(*) FILTER (
             WHERE organisation_id =
                 (SELECT public.current_user_organisation_id())
         ) = 1
        THEN 'PASS'
        ELSE 'FAIL'
    END AS result,
    COUNT(*) AS visible_customer_count,
    COUNT(*) FILTER (
        WHERE customer_code = 'CUST-1001'
    ) AS expected_customer_visible
FROM visible_customers;

ROLLBACK;
