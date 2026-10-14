-- MADZERA MIGRATION 029
-- Reconstruct case classification columns verified in the live database.
-- NULL is intentionally permitted for historical records.
-- No existing case data is modified.

BEGIN;

ALTER TABLE public.cases
    ADD COLUMN IF NOT EXISTS case_type VARCHAR,
    ADD COLUMN IF NOT EXISTS initiated_by VARCHAR;

ALTER TABLE public.cases
    ADD CONSTRAINT cases_case_type_check
    CHECK (case_type IN ('customer_query', 'internal_case'));

ALTER TABLE public.cases
    ADD CONSTRAINT cases_initiated_by_check
    CHECK (initiated_by IN ('customer', 'employee', 'system'));

COMMIT;
