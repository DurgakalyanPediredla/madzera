
-- MADZERA TEST CASE-UPDATE-03
-- Verify cross-organisation UPDATE isolation.
--
-- Expected:
-- PASS - cross-organisation UPDATE blocked.
--
-- Uses a simulated authenticated employee session.
-- All changes are rolled back.

BEGIN;

-- Simulate Sarah Mitchell's authenticated identity.
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

-- Attempt to update HarbourBridge's case.
WITH attempted_update AS (
    UPDATE public.cases
    SET priority = 'critical'
    WHERE external_case_id = 'CASE-HB-DEMO-001'
    RETURNING id
)
SELECT
    COUNT(*) AS rows_updated,
    CASE
        WHEN COUNT(*) = 0
        THEN 'PASS - cross-organisation UPDATE blocked'
        ELSE 'FAIL - cross-organisation UPDATE succeeded'
    END AS test_result
FROM attempted_update;

ROLLBACK;
