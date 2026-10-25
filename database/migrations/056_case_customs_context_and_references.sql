-- MADZERA MIGRATION 056
-- Context-First Case Management: structured customs context
-- and typed operational references.
--
-- Additive schema only. No existing RPC or locking changes.
-- No direct access for anon/authenticated roles.

BEGIN;

CREATE TABLE public.case_customs_context (
    case_id uuid PRIMARY KEY,
    organisation_id uuid NOT NULL,
    operation_type text NOT NULL,
    issue_category text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_customs_context_case_organisation
        FOREIGN KEY (case_id, organisation_id)
        REFERENCES public.cases (id, organisation_id),

    CONSTRAINT chk_customs_context_operation
        CHECK (operation_type IN (
            'import_declaration',
            'export_declaration',
            'transit_movement',
            'documents_compliance',
            'general_internal'
        )),

    CONSTRAINT chk_customs_context_issue
        CHECK (
            length(btrim(issue_category)) BETWEEN 1 AND 100
            AND issue_category = btrim(issue_category)
        )
);

CREATE INDEX idx_customs_context_organisation
    ON public.case_customs_context (organisation_id, operation_type);

ALTER TABLE public.case_customs_context
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.case_customs_context
    FROM PUBLIC, anon, authenticated;

CREATE TABLE public.case_operational_references (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id uuid NOT NULL,
    organisation_id uuid NOT NULL,
    reference_type text NOT NULL,
    reference_value text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT fk_operational_reference_case_organisation
        FOREIGN KEY (case_id, organisation_id)
        REFERENCES public.cases (id, organisation_id),

    CONSTRAINT chk_operational_reference_type
        CHECK (reference_type IN (
            'import_mrn',
            'export_mrn',
            'transit_mrn',
            'ducr',
            'gmr',
            'shipment_reference',
            'job_reference',
            'eori',
            'other'
        )),

    CONSTRAINT chk_operational_reference_value
        CHECK (
            length(btrim(reference_value)) BETWEEN 1 AND 150
            AND reference_value = btrim(reference_value)
        ),

    CONSTRAINT uq_operational_reference_per_case
        UNIQUE (case_id, reference_type, reference_value)
);

CREATE INDEX idx_operational_reference_match
    ON public.case_operational_references (
        organisation_id,
        reference_type,
        reference_value,
        case_id
    );

ALTER TABLE public.case_operational_references
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.case_operational_references
    FROM PUBLIC, anon, authenticated;

COMMIT;
