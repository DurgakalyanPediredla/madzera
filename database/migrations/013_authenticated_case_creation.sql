
-- MADZERA MIGRATION 013
-- Purpose: Enable tenant-restricted case creation.
--
-- Verification:
-- Step 100: Same-organisation INSERT succeeded.
-- Step 101: Cross-organisation INSERT rejected
--           with PostgreSQL error 42501.
--
-- UPDATE and DELETE permissions remain disabled.

BEGIN;

CREATE POLICY "Employees can create cases in their organisation"
ON public.cases
FOR INSERT
TO authenticated
WITH CHECK (
    organisation_id =
        (SELECT public.current_user_organisation_id())
);

GRANT INSERT ON TABLE public.cases TO authenticated;

COMMIT;
