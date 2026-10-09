
-- MADZERA DATABASE MIGRATION 002
-- Function execution permission hardening
--
-- Purpose:
-- Remove direct anonymous EXECUTE access from the
-- organisation-resolution helper function.
--
-- Background:
-- Migration 001 revoked PUBLIC execution privileges,
-- but verification identified a separate direct
-- EXECUTE grant to the anon role.
--
-- This migration removes that grant while preserving
-- authenticated employee execution access.
--
-- Verified in Supabase development environment
-- on 9 October 2026.

REVOKE EXECUTE
ON FUNCTION public.current_user_organisation_id()
FROM anon;

-- Ensure the intended authenticated role retains access.
GRANT EXECUTE
ON FUNCTION public.current_user_organisation_id()
TO authenticated;
