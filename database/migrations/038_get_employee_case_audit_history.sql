-- MADZERA MIGRATION 038
-- Read existing case audit events for the employee holding the active lock.
-- Does not modify cases, events, assignments, or locks.

BEGIN;

CREATE INDEX IF NOT EXISTS idx_case_events_org_case_created
ON public.case_events (
    organisation_id,
    case_id,
    created_at DESC,
    id DESC
);

CREATE FUNCTION public.get_employee_case_audit_history(
    p_case_id uuid,
    p_lock_token uuid
)
RETURNS TABLE (
    id uuid,
    event_type text,
    created_at timestamptz,
    actor_user_id uuid,
    actor_name text,
    from_status text,
    to_status text,
    from_team_name text,
    to_team_name text,
    from_user_name text,
    to_user_name text,
    details text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required'
            USING ERRCODE = '42501';
    END IF;

    IF p_case_id IS NULL OR p_lock_token IS NULL THEN
        RAISE EXCEPTION 'Valid case and lock token required'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases AS c
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
    ) THEN
        RAISE EXCEPTION 'Case not found or access denied'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks AS l
        WHERE l.case_id = p_case_id
          AND l.organisation_id = v_organisation_id
          AND l.locked_by_user_id = v_employee_id
          AND l.lock_token = p_lock_token
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'Case lock invalid, expired, or not owned by employee'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        ev.id,
        ev.event_type::text,
        ev.created_at,
        ev.actor_user_id,
        COALESCE(actor.full_name::text, 'System / unknown') AS actor_name,
        ev.from_status::text,
        ev.to_status::text,
        previous_team.name::text AS from_team_name,
        next_team.name::text AS to_team_name,
        previous_user.full_name::text AS from_user_name,
        next_user.full_name::text AS to_user_name,
        ev.details
    FROM public.case_events AS ev
    LEFT JOIN public.users AS actor
      ON actor.id = ev.actor_user_id
     AND actor.organisation_id = ev.organisation_id
    LEFT JOIN public.teams AS previous_team
      ON previous_team.id = ev.from_team_id
     AND previous_team.organisation_id = ev.organisation_id
    LEFT JOIN public.teams AS next_team
      ON next_team.id = ev.to_team_id
     AND next_team.organisation_id = ev.organisation_id
    LEFT JOIN public.users AS previous_user
      ON previous_user.id = ev.from_user_id
     AND previous_user.organisation_id = ev.organisation_id
    LEFT JOIN public.users AS next_user
      ON next_user.id = ev.to_user_id
     AND next_user.organisation_id = ev.organisation_id
    WHERE ev.case_id = p_case_id
      AND ev.organisation_id = v_organisation_id
    ORDER BY ev.created_at DESC, ev.id DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_employee_case_audit_history(uuid, uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_employee_case_audit_history(uuid, uuid)
TO authenticated;

COMMIT;
