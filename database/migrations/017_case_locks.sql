-- MADZERA MIGRATION 017
-- Reproduce the live case-lock table and its integrity constraints.
-- Lock management functions will be introduced separately.

BEGIN;

CREATE TABLE public.case_locks (
    case_id UUID NOT NULL,
    organisation_id UUID NOT NULL,
    locked_by_user_id UUID NOT NULL,
    locked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    lock_token UUID,

    CONSTRAINT case_locks_pkey
        PRIMARY KEY (case_id),

    CONSTRAINT chk_case_locks_expiry
        CHECK (expires_at > locked_at),

    CONSTRAINT fk_case_locks_case_organisation
        FOREIGN KEY (case_id, organisation_id)
        REFERENCES public.cases (id, organisation_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_case_locks_user_organisation
        FOREIGN KEY (locked_by_user_id, organisation_id)
        REFERENCES public.users (id, organisation_id)
);

CREATE INDEX idx_case_locks_expiry
ON public.case_locks (expires_at);

ALTER TABLE public.case_locks
ENABLE ROW LEVEL SECURITY;

-- No direct anonymous or authenticated table access.
-- Subsequent SECURITY DEFINER functions will manage locks.
REVOKE ALL ON TABLE public.case_locks
FROM PUBLIC, anon, authenticated;

COMMIT;
