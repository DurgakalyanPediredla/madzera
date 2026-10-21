-- MADZERA MIGRATION 043
-- Secure Case Evidence Attachments
-- Phase 1: relational integrity and private Storage bucket.
-- No employee Storage access is granted in this phase.

BEGIN;

-- Enforce that an attachment's linked activity belongs
-- to the same case and organisation.
ALTER TABLE public.comments
    ADD CONSTRAINT uq_comments_id_case_organisation
    UNIQUE (id, case_id, organisation_id);

ALTER TABLE public.attachments
    ADD COLUMN comment_id uuid;

ALTER TABLE public.attachments
    ADD CONSTRAINT fk_attachments_comment_case_organisation
    FOREIGN KEY (comment_id, case_id, organisation_id)
    REFERENCES public.comments (id, case_id, organisation_id);

-- Support efficient retrieval of activity-linked evidence.
CREATE INDEX idx_attachments_comment_case_organisation
    ON public.attachments (comment_id, case_id, organisation_id)
    WHERE comment_id IS NOT NULL;

-- Private bucket: no public file URLs.
-- File types and size are limited at the bucket level.
INSERT INTO storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
VALUES (
    'case-evidence',
    'case-evidence',
    false,
    10485760,
    ARRAY[
        'application/pdf',
        'image/jpeg',
        'image/png'
    ]::text[]
);

COMMIT;
