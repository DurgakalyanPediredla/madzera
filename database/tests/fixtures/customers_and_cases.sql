-- Local security-test fixtures only.
-- Execute only against the verified local Docker database.

BEGIN;

INSERT INTO public.customers (
    id, organisation_id, name, email, status
)
VALUES (
    '50b8faa0-b296-484a-8e9c-4f412c11f300',
    '0a316877-23d4-4dc3-b0ed-350208d68fb3',
    'Liverpool Test Imports Ltd',
    'operations@liverpool-test-imports.example',
    'active'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.cases (
    id, organisation_id, customer_id, title,
    status, priority, source, case_type, initiated_by
)
VALUES
(
    'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea',
    '0a316877-23d4-4dc3-b0ed-350208d68fb3',
    '50b8faa0-b296-484a-8e9c-4f412c11f300',
    'Import declaration awaiting clearance',
    'open', 'medium', 'email', 'customer_query', 'customer'
),
(
    'a1d410f6-0521-4d25-a1f1-9e0023423a14',
    'cbd6a8ae-adf3-4099-9352-1862e1751dea',
    NULL,
    'TENANT ISOLATION TEST - Organisation B',
    'open', 'medium', 'manual', 'internal_case', 'employee'
)
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.customers
        WHERE id = '50b8faa0-b296-484a-8e9c-4f412c11f300'
          AND organisation_id = '0a316877-23d4-4dc3-b0ed-350208d68fb3'
          AND name = 'Liverpool Test Imports Ltd'
          AND email = 'operations@liverpool-test-imports.example'
          AND status = 'active'
    ) THEN
        RAISE EXCEPTION 'Customer fixture mismatch';
    END IF;

    IF (
        SELECT count(*) FROM public.cases
        WHERE
            (id = 'c16dd5f1-8c7e-49a6-b940-0e2c3dc5f8ea'
             AND organisation_id = '0a316877-23d4-4dc3-b0ed-350208d68fb3'
             AND customer_id = '50b8faa0-b296-484a-8e9c-4f412c11f300'
             AND title = 'Import declaration awaiting clearance'
             AND status = 'open'
             AND priority = 'medium'
             AND source = 'email'
             AND case_type = 'customer_query'
             AND initiated_by = 'customer')
            OR
            (id = 'a1d410f6-0521-4d25-a1f1-9e0023423a14'
             AND organisation_id = 'cbd6a8ae-adf3-4099-9352-1862e1751dea'
             AND customer_id IS NULL
             AND title = 'TENANT ISOLATION TEST - Organisation B'
             AND status = 'open'
             AND priority = 'medium'
             AND source = 'manual'
             AND case_type = 'internal_case'
             AND initiated_by = 'employee')
    ) <> 2 THEN
        RAISE EXCEPTION 'Case fixture mismatch';
    END IF;
END;
$$;

COMMIT;
