
-- MADZERA MIGRATION 008
-- Purpose: Enforce tenant consistency for
-- case events, comments and attachments.
--
-- Verified in Supabase on 09 October 2026.
-- Verification: 8 of 8 foreign keys validated.
--
-- These constraints prevent references to
-- employees, teams or customers belonging
-- to a different organisation.
--
-- They do not grant application permissions
-- or implement file storage security.

BEGIN;

-- Case event employee references

ALTER TABLE public.case_events
ADD CONSTRAINT fk_case_events_actor_user_organisation
FOREIGN KEY (actor_user_id, organisation_id)
REFERENCES public.users (id, organisation_id);

ALTER TABLE public.case_events
ADD CONSTRAINT fk_case_events_from_user_organisation
FOREIGN KEY (from_user_id, organisation_id)
REFERENCES public.users (id, organisation_id);

ALTER TABLE public.case_events
ADD CONSTRAINT fk_case_events_to_user_organisation
FOREIGN KEY (to_user_id, organisation_id)
REFERENCES public.users (id, organisation_id);

-- Case event team references

ALTER TABLE public.case_events
ADD CONSTRAINT fk_case_events_from_team_organisation
FOREIGN KEY (from_team_id, organisation_id)
REFERENCES public.teams (id, organisation_id);

ALTER TABLE public.case_events
ADD CONSTRAINT fk_case_events_to_team_organisation
FOREIGN KEY (to_team_id, organisation_id)
REFERENCES public.teams (id, organisation_id);

-- Comment author reference

ALTER TABLE public.comments
ADD CONSTRAINT fk_comments_author_user_organisation
FOREIGN KEY (author_user_id, organisation_id)
REFERENCES public.users (id, organisation_id);

-- Attachment employee uploader reference

ALTER TABLE public.attachments
ADD CONSTRAINT fk_attachments_uploaded_user_organisation
FOREIGN KEY (uploaded_by_user_id, organisation_id)
REFERENCES public.users (id, organisation_id);

-- Attachment customer uploader reference

ALTER TABLE public.attachments
ADD CONSTRAINT fk_attachments_uploaded_customer_organisation
FOREIGN KEY (uploaded_by_customer_id, organisation_id)
REFERENCES public.customers (id, organisation_id);

COMMIT;
