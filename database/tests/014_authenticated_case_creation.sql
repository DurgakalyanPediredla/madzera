
-- MADZERA TEST CASE-INSERT-01
-- Migration 013: Authenticated case creation.
--
-- Expected:
-- One NorthStar case returned.
-- status = open
-- priority = medium
-- source = manual
--
-- Uses a simulated authenticated session.
-- Transaction is rolled back.

BEGIN;

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

INSERT INTO public.cases (
    organisation_id,
    title,
    description,
    source
)
VALUES (
    (SELECT public.current_user_organisation_id()),
    'TEST-100: Customer enquiry',
    'Temporary case to verify authenticated creation.',
    'manual'
)
RETURNING
    title,
    status,
    priority,
    source,
    organisation_id;

ROLLBACK;
