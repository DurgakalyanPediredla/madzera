-- MADZERA MIGRATION 044
-- Secure Case Evidence: Upload Reservations
-- Phase 1: reservation metadata and relational integrity.
-- No Storage permissions are granted by this migration.

BEGIN;

CREATE TABLE public.case_evidence_upload_reservations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id uuid NOT NULL,
    organisation_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    storage_path text NOT NULL UNIQUE,
    file_name varchar(255) NOT NULL,
    file_type varchar(100) NOT NULL,
    file_size_bytes bigint NOT NULL,
    status text NOT NULL DEFAULT 'pending',
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    completed_at timestamptz,

    CONSTRAINT fk_evidence_reservation_case_organisation
        FOREIGN KEY (case_id, organisation_id)
        REFERENCES public.cases (id, organisation_id),

    CONSTRAINT fk_evidence_reservation_employee_organisation
        FOREIGN KEY (employee_id, organisation_id)
        REFERENCES public.users (id, organisation_id),

    CONSTRAINT chk_evidence_reservation_size
        CHECK (file_size_bytes BETWEEN 1 AND 10485760),

    CONSTRAINT chk_evidence_reservation_type
        CHECK (file_type IN (
            'application/pdf',
            'image/jpeg',
            'image/png'
        )),

    CONSTRAINT chk_evidence_reservation_status
        CHECK (status IN ('pending', 'completed', 'expired')),

    CONSTRAINT chk_evidence_reservation_completion
        CHECK (
            (status = 'completed' AND completed_at IS NOT NULL)
            OR
            (status <> 'completed' AND completed_at IS NULL)
        ),

    CONSTRAINT chk_evidence_reservation_expiry
        CHECK (expires_at > created_at)
);

CREATE INDEX idx_evidence_reservations_case_employee
    ON public.case_evidence_upload_reservations (
        case_id,
        employee_id,
        status
    );

CREATE INDEX idx_evidence_reservations_pending_expiry
    ON public.case_evidence_upload_reservations (expires_at)
    WHERE status = 'pending';

ALTER TABLE public.case_evidence_upload_reservations
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.case_evidence_upload_reservations
    FROM PUBLIC, anon, authenticated;

COMMIT;
