-- MADZERA MIGRATION 060
-- Privileged initial organisation administrator provisioning.
--
-- Must be executed only by a trusted database operator.
-- No authenticated or anonymous API execution.
-- No existing case or locking functions modified.

BEGIN;

CREATE FUNCTION madzera_internal.provision_initial_organisation_admin(
    p_organisation_id uuid,
    p_user_id uuid,
    p_reason text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Privileged database operator required';
    END IF;

    IF p_reason IS NULL
       OR length(btrim(p_reason)) < 10 THEN
        RAISE EXCEPTION 'Provisioning reason is required';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.users u
        WHERE u.id = p_user_id
          AND u.organisation_id = p_organisation_id
          AND u.is_active = TRUE
          AND u.auth_user_id IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'Active authenticated employee not found';
    END IF;

    -- Serialise initial provisioning for this organisation.
    -- Concurrent attempts must wait for the same organisation row.
    PERFORM 1
    FROM public.organisations o
    WHERE o.id = p_organisation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Organisation not found';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.organisation_administrators oa
        WHERE oa.organisation_id = p_organisation_id
    ) THEN
        RAISE EXCEPTION 'Organisation already has an administrator';
    END IF;

    INSERT INTO public.organisation_administrators (
        organisation_id,
        user_id
    )
    VALUES (
        p_organisation_id,
        p_user_id
    );

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
        p_organisation_id,
        NULL,
        p_user_id,
        NULL,
        'organisation_admin',
        'granted',
        p_reason
    );

    RETURN TRUE;
END;
$function$;

REVOKE ALL ON FUNCTION
    madzera_internal.provision_initial_organisation_admin(
        uuid, uuid, text
    )
FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
