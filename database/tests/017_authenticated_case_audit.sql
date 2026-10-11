
-- MADZERA TEST CASE-AUDIT-02
-- Verify an authenticated case UPDATE creates
-- an audit event with the correct employee.
--
-- Expected:
-- PASS - authenticated update audited.
--
-- All changes are rolled back.

BEGIN;

-- Establish Sarah's simulated identity.
SELECT set_config(
    'request.jwt.claim.sub',
    (
        SELECT auth_user_id::text
        FROM public.users
        WHERE email = 'sarah@northstar-demo.test'
    ),
    true
);

-- Update the case as an authenticated employee.
SET LOCAL ROLE authenticated;

UPDATE public.cases
SET priority = 'high'
WHERE external_case_id = 'CASE-DEMO-001';

-- Inspect the protected audit table using
-- the privileged SQL Editor role.
RESET ROLE;

SELECT
    CASE
        WHEN COUNT(*) = 1
        THEN 'PASS - authenticated update audited'
        ELSE 'FAIL - expected audit event not found'
    END AS test_result
FROM public.case_events AS ce
JOIN public.cases AS c
    ON c.id = ce.case_id
   AND c.organisation_id = ce.organisation_id
JOIN public.users AS u
    ON u.id = ce.actor_user_id
   AND u.organisation_id = ce.organisation_id
WHERE c.external_case_id = 'CASE-DEMO-001'
  AND ce.event_type = 'case_updated'
  AND u.email = 'sarah@northstar-demo.test'
  AND ce.details =
      'Case workflow updated; priority: medium -> high'
  AND ce.created_at >= transaction_timestamp();

ROLLBACK;
