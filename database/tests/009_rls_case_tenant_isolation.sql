
-- MADZERA SECURITY TEST: RLS-07
-- Cross-organisation case isolation.
--
-- Environment: Synthetic Supabase development database.
-- Expected: PASS.
-- Sarah sees NorthStar's case only.
-- HarbourBridge's case must not be visible.
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

-- Evaluate case visibility under RLS.
WITH visible_cases AS (
    SELECT
        external_case_id,
        organisation_id
    FROM public.cases
)
SELECT
    'RLS-07' AS test_id,
    CASE
        WHEN COUNT(*) = 1
         AND COUNT(*) FILTER (
             WHERE external_case_id = 'CASE-DEMO-001'
         ) = 1
         AND COUNT(*) FILTER (
             WHERE external_case_id = 'CASE-HB-DEMO-001'
         ) = 0
         AND COUNT(*) FILTER (
             WHERE organisation_id =
                 (SELECT public.current_user_organisation_id())
         ) = 1
        THEN 'PASS'
        ELSE 'FAIL'
    END AS result,
    COUNT(*) AS visible_case_count,
    COUNT(*) FILTER (
        WHERE external_case_id = 'CASE-HB-DEMO-001'
    ) AS harbourbridge_cases_visible
FROM visible_cases;

ROLLBACK;
