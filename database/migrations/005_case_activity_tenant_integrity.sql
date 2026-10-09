
-- MADZERA MIGRATION 005
-- Enforce parent-case tenant integrity.
-- No RLS policies or write permissions added.

BEGIN;

-- 1. Composite key for organisation-consistent
--    case references.

ALTER TABLE public.cases
ADD CONSTRAINT uq_cases_id_organisation
UNIQUE (id, organisation_id);

-- 2. Case events must reference cases
--    in the same organisation.

ALTER TABLE public.case_events
ADD CONSTRAINT fk_case_events_case_organisation
FOREIGN KEY (case_id, organisation_id)
REFERENCES public.cases (id, organisation_id);

-- 3. Comments must reference cases
--    in the same organisation.

ALTER TABLE public.comments
ADD CONSTRAINT fk_comments_case_organisation
FOREIGN KEY (case_id, organisation_id)
REFERENCES public.cases (id, organisation_id);

-- 4. Attachments must reference cases
--    in the same organisation.

ALTER TABLE public.attachments
ADD CONSTRAINT fk_attachments_case_organisation
FOREIGN KEY (case_id, organisation_id)
REFERENCES public.cases (id, organisation_id);

COMMIT;
