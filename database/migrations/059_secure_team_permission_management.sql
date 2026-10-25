-- MADZERA MIGRATION 059
-- Controlled team permission grants and revocations.
-- No existing case functions or locking behaviour changed.

BEGIN;

CREATE FUNCTION public.grant_team_permission(
    p_team_id uuid,
    p_target_user_id uuid,
    p_permission_type text,
    p_reason text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor_id uuid;
    v_organisation_id uuid;
    v_grant_id uuid;
BEGIN
    v_actor_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_actor_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorised employee';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.organisation_administrators oa
        WHERE oa.user_id = v_actor_id
          AND oa.organisation_id = v_organisation_id
    ) THEN
        RAISE EXCEPTION 'Organisation administrator required';
    END IF;

    IF p_permission_type IS NULL
       OR p_permission_type NOT IN ('submit', 'work', 'manage') THEN
        RAISE EXCEPTION 'Invalid permission type';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.teams t
        WHERE t.id = p_team_id
          AND t.organisation_id = v_organisation_id
    ) THEN
        RAISE EXCEPTION 'Team not found';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.users u
        WHERE u.id = p_target_user_id
          AND u.organisation_id = v_organisation_id
          AND u.is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'Active target employee not found';
    END IF;

    INSERT INTO public.team_permission_grants (
        organisation_id,
        team_id,
        user_id,
        permission_type
    )
    VALUES (
        v_organisation_id,
        p_team_id,
        p_target_user_id,
        p_permission_type
    )
    ON CONFLICT (team_id, user_id, permission_type)
    DO NOTHING
    RETURNING id INTO v_grant_id;

    IF v_grant_id IS NULL THEN
        RAISE EXCEPTION 'Permission already granted';
    END IF;

    INSERT INTO public.permission_audit_events (
        organisation_id,
        actor_user_id,
        target_user_id,
        team_id,
        permission_type,
        action,
        reason
    )
    VALUES (
        v_organisation_id,
        v_actor_id,
        p_target_user_id,
        p_team_id,
        p_permission_type,
        'granted',
        p_reason
    );

    RETURN v_grant_id;
END;
$function$;

CREATE FUNCTION public.revoke_team_permission(
    p_team_id uuid,
    p_target_user_id uuid,
    p_permission_type text,
    p_reason text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor_id uuid;
    v_organisation_id uuid;
    v_deleted_id uuid;
BEGIN
    v_actor_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_actor_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorised employee';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.organisation_administrators oa
        WHERE oa.user_id = v_actor_id
          AND oa.organisation_id = v_organisation_id
    ) THEN
        RAISE EXCEPTION 'Organisation administrator required';
    END IF;

    IF p_permission_type IS NULL
       OR p_permission_type NOT IN ('submit', 'work', 'manage') THEN
        RAISE EXCEPTION 'Invalid permission type';
    END IF;

    DELETE FROM public.team_permission_grants g
    WHERE g.organisation_id = v_organisation_id
      AND g.team_id = p_team_id
      AND g.user_id = p_target_user_id
      AND g.permission_type = p_permission_type
    RETURNING g.id INTO v_deleted_id;

    IF v_deleted_id IS NULL THEN
        RAISE EXCEPTION 'Permission not found';
    END IF;

    INSERT INTO public.permission_audit_events (
        organisation_id,
        actor_user_id,
        target_user_id,
        team_id,
        permission_type,
        action,
        reason
    )
    VALUES (
        v_organisation_id,
        v_actor_id,
        p_target_user_id,
        p_team_id,
        p_permission_type,
        'revoked',
        p_reason
    );

    RETURN TRUE;
END;
$function$;

REVOKE ALL ON FUNCTION public.grant_team_permission(
    uuid, uuid, text, text
) FROM PUBLIC, anon;

REVOKE ALL ON FUNCTION public.revoke_team_permission(
    uuid, uuid, text, text
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.grant_team_permission(
    uuid, uuid, text, text
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.revoke_team_permission(
    uuid, uuid, text, text
) TO authenticated;

COMMIT;
