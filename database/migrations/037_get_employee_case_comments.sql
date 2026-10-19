-- Madzera: read internal case activity comments.
-- Requires the authenticated employee to own the active case lock.
-- Does not modify the case, assignment, comments, or lock.

BEGIN;

CREATE FUNCTION public.get_employee_case_comments(
    p_case_id uuid,
    p_lock_token uuid
)
RETURNS TABLE (
    id uuid,
    body text,
    created_at timestamptz,
    author_user_id uuid,
    author_name text
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
        cm.id,
        cm.body,
        cm.created_at,
        cm.author_user_id,
        COALESCE(u.full_name::text, 'Unknown employee') AS author_name
    FROM public.comments AS cm
    LEFT JOIN public.users AS u
      ON u.id = cm.author_user_id
     AND u.organisation_id = cm.organisation_id
    WHERE cm.case_id = p_case_id
      AND cm.organisation_id = v_organisation_id
      AND cm.visibility = 'internal'
    ORDER BY cm.created_at ASC, cm.id ASC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_employee_case_comments(uuid, uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_employee_case_comments(uuid, uuid)
TO authenticated;

COMMIT;
