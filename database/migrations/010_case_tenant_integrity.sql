
-- MADZERA MIGRATION 010
-- Purpose: Enforce organisation consistency
-- for case customers, employees and teams.
--
-- Verified in Supabase on 09 October 2026.
--
-- Preflight:
-- 2 existing cases
-- 0 invalid customer references
-- 0 invalid employee assignments
-- 0 invalid team assignments
--
-- Verification:
-- 3 of 3 composite foreign keys validated.
--
-- Nullable customer and assignment fields remain
-- nullable for cases awaiting identification
-- or assignment.

BEGIN;

ALTER TABLE public.cases
ADD CONSTRAINT fk_cases_customer_organisation
FOREIGN KEY (customer_id, organisation_id)
REFERENCES public.customers (id, organisation_id);

ALTER TABLE public.cases
ADD CONSTRAINT fk_cases_assigned_user_organisation
FOREIGN KEY (assigned_user_id, organisation_id)
REFERENCES public.users (id, organisation_id);

ALTER TABLE public.cases
ADD CONSTRAINT fk_cases_assigned_team_organisation
FOREIGN KEY (assigned_team_id, organisation_id)
REFERENCES public.teams (id, organisation_id);

COMMIT;
