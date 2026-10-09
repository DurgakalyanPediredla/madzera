
-- MADZERA MIGRATION 009
-- Purpose: Apply least-privilege table access
-- to core case-management records.
--
-- Verified in Supabase on 09 October 2026.
--
-- Verification:
-- Step 79: Effective table privileges PASS
-- Step 80B: Authenticated case visibility PASS
--
-- Existing case SELECT RLS policies remain active.
-- Other case-management permissions will be
-- introduced as individual workflows are built.
--
-- service_role privileges are unchanged.

BEGIN;

REVOKE ALL PRIVILEGES ON TABLE
    public.cases,
    public.case_events,
    public.comments,
    public.attachments
FROM anon, authenticated;

GRANT SELECT ON TABLE public.cases
TO authenticated;

COMMIT;
