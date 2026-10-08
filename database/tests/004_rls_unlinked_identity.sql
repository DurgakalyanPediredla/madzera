
-- MADZERA SECURITY TEST: RLS-02
-- Unlinked authenticated identity access denial.
--
-- Environment: Synthetic development database only.
-- Expected: PASS, with 0 visible employees.
-- Execution: Simulated authenticated PostgreSQL role.
-- No persistent database changes.

BEGIN;

-- Set a synthetic authentication identity that has
-- no corresponding active Madzera employee record.
SELECT set_config(
    'request.jwt.claim.sub',
    '00000000-0000-4000-8000-000000000099',
    true
);

-- Simulate an authenticated database session.
SET LOCAL ROLE authenticated;

-- Verify the identity cannot read employee records.
SELECT
    'RLS-02' AS test_id,
    CASE
        WHEN COUNT(*) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS result,
    COUNT(*) AS visible_employee_count
FROM public.users;

-- Restore the original transaction state.
ROLLBACK;
