
-- MADZERA SECURITY TEST: AUTH-01
-- Verify Sarah's Supabase Auth identity mapping.
--
-- Environment: Synthetic development database only.
-- Expected: One PASS row.
-- Read-only test. Does not modify database records.

WITH auth_mapping AS (
    SELECT
        u.id AS employee_id,
        u.auth_user_id,
        u.is_active,
        u.organisation_id,
        o.name AS organisation_name,
        a.id AS authenticated_identity
    FROM public.users AS u
    LEFT JOIN public.organisations AS o
        ON o.id = u.organisation_id
    LEFT JOIN auth.users AS a
        ON a.id = u.auth_user_id
    WHERE u.email = 'sarah@northstar-demo.test'
)
SELECT
    'AUTH-01' AS test_id,
    CASE
        WHEN COUNT(*) = 1
         AND COUNT(auth_user_id) = 1
         AND COUNT(authenticated_identity) = 1
         AND BOOL_AND(is_active IS TRUE)
         AND BOOL_AND(
             organisation_name = 'NorthStar Customs Ltd'
         )
        THEN 'PASS'
        ELSE 'FAIL'
    END AS result,
    COUNT(*) AS matching_employee_records
FROM auth_mapping;
