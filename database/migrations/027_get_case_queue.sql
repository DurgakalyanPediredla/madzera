-- MADZERA MIGRATION 027
-- Return the organisation-scoped case queue.
-- Show active lock holders without exposing lock tokens or case descriptions.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_case_queue()
RETURNS TABLE (
    case_id UUID,
    case_title VARCHAR,
    case_status VARCHAR,
    case_priority VARCHAR,
    case_source VARCHAR,
    customer_id UUID,
    assigned_team_id UUID,
    assigned_user_id UUID,
    created_at TIMESTAMPTZ,
    locked_by_name VARCHAR
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT
        c.id AS case_id,
        c.title AS case_title,
        c.status AS case_status,
        c.priority AS case_priority,
        c.source AS case_source,
        c.customer_id,
        c.assigned_team_id,
        c.assigned_user_id,
        c.created_at,
        u.full_name AS locked_by_name
    FROM public.cases AS c
    LEFT JOIN public.case_locks AS l
        ON l.case_id = c.id
       AND l.organisation_id = c.organisation_id
       AND l.expires_at > NOW()
    LEFT JOIN public.users AS u
        ON u.id = l.locked_by_user_id
       AND u.organisation_id = c.organisation_id
    WHERE c.organisation_id = public.current_user_organisation_id()
    ORDER BY c.created_at DESC;
$function$;

REVOKE ALL ON FUNCTION public.get_case_queue()
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_case_queue()
TO authenticated, service_role;

COMMIT;
