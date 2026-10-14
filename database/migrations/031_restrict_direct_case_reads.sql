-- Migration 031
-- Prevent authenticated employees from reading cases directly.
-- Case queue and locked case details remain accessible through
-- their existing SECURITY DEFINER functions.

BEGIN;

REVOKE SELECT ON TABLE public.cases FROM authenticated;

COMMIT;
