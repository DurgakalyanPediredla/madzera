
-- MADZERA SECURITY TEST: RLS-06
-- Own-organisation case visibility.
--
-- Environment: Synthetic development database.
-- Expected: PASS, 1 visible case.
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
    'RLS-06' AS test_id,
    CASE
        WHEN COUNT(*) = 1
         AND COUNT(*) FILTER (
             WHERE external_case_id = 'CASE-DEMO-001'
         ) = 1
         AND COUNT(*) FILTER (
             WHERE organisation_id =
                 (SELECT public.current_user_organisation_id())
         ) = 1
        THEN 'PASS'
        ELSE 'FAIL'
    END AS result,
    COUNT(*) AS visible_case_count,
    COUNT(*) FILTER (
        WHERE external_case_id = 'CASE-DEMO-001'
    ) AS expected_case_visible
FROM visible_cases;

ROLLBACK;
