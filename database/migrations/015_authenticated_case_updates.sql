
-- MADZERA MIGRATION 015
-- Purpose: Enable tenant-restricted case updates.
--
-- Verified:
-- 118: Authorised employee UPDATE succeeded.
-- 119: Automatic audit event created.
-- 120: Cross-organisation UPDATE blocked.
-- 121: Protected-column UPDATE denied.
--
-- DELETE remains prohibited.

BEGIN;

CREATE POLICY "Employees can update cases in their organisation"
ON public.cases
FOR UPDATE
TO authenticated
USING (
    organisation_id =
        (SELECT public.current_user_organisation_id())
)
WITH CHECK (
    organisation_id =
        (SELECT public.current_user_organisation_id())
);

REVOKE UPDATE ON TABLE public.cases
FROM authenticated;

GRANT UPDATE (
    status,
    priority,
    assigned_team_id,
    assigned_user_id
)
ON TABLE public.cases
TO authenticated;

COMMIT;
