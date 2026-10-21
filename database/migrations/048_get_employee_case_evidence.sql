-- MADZERA MIGRATION 048
-- List internal evidence for an exclusively locked case.
-- Does not expose Storage paths or grant Storage access.

BEGIN;

CREATE FUNCTION public.get_employee_case_evidence(
    p_case_id uuid,
    p_lock_token uuid
)
RETURNS TABLE (
    id uuid,
    comment_id uuid,
    file_name text,
    file_type text,
    file_size_bytes bigint,
    created_at timestamptz,
    uploaded_by_user_id uuid,
    uploaded_by_name text
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

    IF v_employee_id IS NULL
       OR v_organisation_id IS NULL
       OR p_case_id IS NULL
       OR p_lock_token IS NULL
    THEN
        RAISE EXCEPTION 'Authenticated employee and case lock required'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases AS c
        JOIN public.case_locks AS l
          ON l.case_id = c.id
         AND l.organisation_id = c.organisation_id
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
          AND l.locked_by_user_id = v_employee_id
          AND l.lock_token = p_lock_token
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'Case access denied or lock expired'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        a.id,
        a.comment_id,
        a.file_name::text,
        a.file_type::text,
        a.file_size_bytes,
        a.created_at,
        a.uploaded_by_user_id,
        COALESCE(u.full_name::text, 'Unknown employee')
    FROM public.attachments AS a
    LEFT JOIN public.users AS u
      ON u.id = a.uploaded_by_user_id
     AND u.organisation_id = a.organisation_id
    WHERE a.case_id = p_case_id
      AND a.organisation_id = v_organisation_id
      AND a.visibility = 'internal'
    ORDER BY a.created_at ASC, a.id ASC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_employee_case_evidence(
    uuid, uuid
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_employee_case_evidence(
    uuid, uuid
) TO authenticated;

COMMIT;
