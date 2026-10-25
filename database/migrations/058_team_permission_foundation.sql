-- MADZERA MIGRATION 058
-- Organisation administration and team permission foundation.
--
-- Schema only. No existing case functions or locks modified.
-- No administrator is automatically provisioned.

BEGIN;

-- Organisation administrator assignments.

CREATE TABLE public.organisation_administrators (
    organisation_id uuid NOT NULL,
    user_id uuid NOT NULL,
    granted_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_organisation_administrators
        PRIMARY KEY (organisation_id, user_id),

    CONSTRAINT fk_org_admin_organisation
        FOREIGN KEY (organisation_id)
        REFERENCES public.organisations(id),

    CONSTRAINT fk_org_admin_user
        FOREIGN KEY (user_id, organisation_id)
        REFERENCES public.users(id, organisation_id)
);

-- Team-specific permission grants.

CREATE TABLE public.team_permission_grants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organisation_id uuid NOT NULL,
    team_id uuid NOT NULL,
    user_id uuid NOT NULL,
    permission_type text NOT NULL,
    granted_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_team_permission_type
        CHECK (
            permission_type IN ('submit', 'work', 'manage')
        ),

    CONSTRAINT uq_team_permission_grant
        UNIQUE (team_id, user_id, permission_type),

    CONSTRAINT fk_permission_team
        FOREIGN KEY (team_id, organisation_id)
        REFERENCES public.teams(id, organisation_id),

    CONSTRAINT fk_permission_user
        FOREIGN KEY (user_id, organisation_id)
        REFERENCES public.users(id, organisation_id)
);

CREATE INDEX idx_team_permission_user
    ON public.team_permission_grants (
        organisation_id,
        user_id,
        team_id,
        permission_type
    );

-- Dedicated permission-change audit ledger.
-- Append-only restrictions and transactional audit writes
-- will be enforced in subsequent controlled RPCs.

CREATE TABLE public.permission_audit_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organisation_id uuid NOT NULL,
    actor_user_id uuid,
    target_user_id uuid NOT NULL,
    team_id uuid,
    permission_type text NOT NULL,
    action text NOT NULL,
    reason text,
    approval_reference uuid,
    occurred_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_permission_audit_type
        CHECK (
            permission_type IN (
                'organisation_admin',
                'submit',
                'work',
                'manage'
            )
        ),

    CONSTRAINT chk_permission_audit_action
        CHECK (action IN ('granted', 'revoked')),

    CONSTRAINT fk_permission_audit_organisation
        FOREIGN KEY (organisation_id)
        REFERENCES public.organisations(id),

    CONSTRAINT fk_permission_audit_actor
        FOREIGN KEY (actor_user_id, organisation_id)
        REFERENCES public.users(id, organisation_id),

    CONSTRAINT fk_permission_audit_target
        FOREIGN KEY (target_user_id, organisation_id)
        REFERENCES public.users(id, organisation_id),

    CONSTRAINT fk_permission_audit_team
        FOREIGN KEY (team_id, organisation_id)
        REFERENCES public.teams(id, organisation_id),

    CONSTRAINT chk_permission_audit_scope
        CHECK (
            (
                permission_type = 'organisation_admin'
                AND team_id IS NULL
            )
            OR
            (
                permission_type <> 'organisation_admin'
                AND team_id IS NOT NULL
            )
        )
);

CREATE INDEX idx_permission_audit_organisation_time
    ON public.permission_audit_events (
        organisation_id,
        occurred_at DESC
    );

-- Default-deny database access.

ALTER TABLE public.organisation_administrators
    ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.team_permission_grants
    ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.permission_audit_events
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.organisation_administrators
    FROM PUBLIC, anon, authenticated;

REVOKE ALL ON public.team_permission_grants
    FROM PUBLIC, anon, authenticated;

REVOKE ALL ON public.permission_audit_events
    FROM PUBLIC, anon, authenticated;

COMMIT;
