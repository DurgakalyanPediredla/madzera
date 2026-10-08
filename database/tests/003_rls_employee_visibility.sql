
-- MADZERA SECURITY TEST: RLS-01
-- Verify authenticated employee visibility.
--
-- Environment: Synthetic development database only.
-- Expected: PASS, with 4 NorthStar employees visible.
-- Tests SELECT access using a simulated authenticated role.
-- No persistent database changes.

BEGIN;

-- Establish Sarah's identity while running as the
-- SQL Editor's privileged database role.
SELECT set_config(
    'request.jwt.claim.sub',
    (
        SELECT auth_user_id::text
        FROM public.users
        WHERE email = 'sarah@northstar-demo.test'
    ),
    true
);

-- Switch to the role used by authenticated clients.
SET LOCAL ROLE authenticated;

-- Evaluate the actual RLS-filtered result.
SELECT
    'RLS-01' AS test_id,
    CASE
        WHEN COUNT(*) = 4
         AND COUNT(*) FILTER (
             WHERE email IN (
                 'sarah@northstar-demo.test',
                 'james@northstar-demo.test',
                 'priya@northstar-demo.test',
                 'emma@northstar-demo.test'
             )
         ) = 4
        THEN 'PASS'
        ELSE 'FAIL'
    END AS result,
    COUNT(*) AS visible_employee_count
FROM public.users;

-- Restore the original transaction state.
ROLLBACK;
