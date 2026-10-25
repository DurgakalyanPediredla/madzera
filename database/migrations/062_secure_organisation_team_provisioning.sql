-- MADZERA MIGRATION 062
-- Secure organisation-specific team creation with transactional audit.
--
-- No existing case creation, locking, Save or permission functions modified.

BEGIN;

CREATE TABLE public.organisation_admin_audit_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organisation_id uuid NOT NULL,
    actor_user_id uuid NOT NULL,
    team_id uuid NOT NULL,
    action text NOT NULL,
    details text,
    occurred_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT chk_org_admin_audit_action
        CHECK (action IN ('team_created')),

    CONSTRAINT fk_org_admin_audit_organisation
        FOREIGN KEY (organisation_id)
        REFERENCES public.organisations(id),

    CONSTRAINT fk_org_admin_audit_actor
        FOREIGN KEY (actor_user_id, organisation_id)
        REFERENCES public.users(id, organisation_id),

    CONSTRAINT fk_org_admin_audit_team
        FOREIGN KEY (team_id, organisation_id)
        REFERENCES public.teams(id, organisation_id)
);

CREATE INDEX idx_org_admin_audit_organisation_time
    ON public.organisation_admin_audit_events (
        organisation_id,
        occurred_at DESC
    );

ALTER TABLE public.organisation_admin_audit_events
    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.organisation_admin_audit_events
    FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.create_organisation_team(
    p_name text,
    p_description text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor_id uuid;
    v_organisation_id uuid;
    v_team_id uuid;
    v_name text;
BEGIN
    v_actor_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_actor_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorised employee'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.organisation_administrators oa
        WHERE oa.user_id = v_actor_id
          AND oa.organisation_id = v_organisation_id
    ) THEN
        RAISE EXCEPTION 'Organisation administrator required'
            USING ERRCODE = '42501';
    END IF;

    v_name := NULLIF(btrim(p_name), '');

    IF v_name IS NULL OR length(v_name) > 150 THEN
        RAISE EXCEPTION 'Invalid team name'
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.teams (
        organisation_id,
        name,
        description
    )
    VALUES (
        v_organisation_id,
        v_name,
        NULLIF(btrim(p_description), '')
    )
    RETURNING id INTO v_team_id;

    INSERT INTO public.organisation_admin_audit_events (
        organisation_id,
        actor_user_id,
        team_id,
        action,
        details
    )
    VALUES (
        v_organisation_id,
        v_actor_id,
        v_team_id,
        'team_created',
        'Organisation team created'
    );

    RETURN v_team_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_organisation_team(text, text)
    FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.create_organisation_team(text, text)
    TO authenticated;

COMMIT;
