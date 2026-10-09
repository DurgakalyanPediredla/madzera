
-- MADZERA MIGRATION 007
-- Purpose: Establish organisation-scoped
-- customer references.
--
-- Verified in Supabase on 09 October 2026.
--
-- This composite unique constraint allows
-- foreign keys to reference a customer ID
-- together with its organisation ID.
--
-- It does not itself enforce attachment
-- ownership or customer access permissions.

BEGIN;

ALTER TABLE public.customers
ADD CONSTRAINT uq_customers_id_organisation
UNIQUE (id, organisation_id);

COMMIT;
