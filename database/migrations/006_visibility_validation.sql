
-- MADZERA MIGRATION 006
-- Purpose: Enforce valid visibility values
-- for comments and attachments.
--
-- Verified in Supabase on 09 October 2026.
--
-- Allowed values:
-- internal = internal operational content
-- customer = content eligible for customer access
--
-- Note: Visibility values alone do not grant access.
-- Access must be enforced through RLS and
-- appropriate application/storage permissions.

BEGIN;

ALTER TABLE public.comments
ADD CONSTRAINT chk_comments_visibility
CHECK (visibility IN ('internal', 'customer'));

ALTER TABLE public.attachments
ADD CONSTRAINT chk_attachments_visibility
CHECK (visibility IN ('internal', 'customer'));

COMMIT;
