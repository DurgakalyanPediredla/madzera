
-- MADZERA MIGRATION 012
-- Purpose: Align the default case priority
-- with the approved workflow values.
--
-- Verification:
-- column_default = 'medium'::character varying
-- is_nullable = NO
--
-- No existing records, RLS policies
-- or table privileges are modified.

BEGIN;

ALTER TABLE public.cases
ALTER COLUMN priority SET DEFAULT 'medium';

COMMIT;
