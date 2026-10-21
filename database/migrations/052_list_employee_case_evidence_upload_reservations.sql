-- MADZERA MIGRATION 052
-- Discover an employee's own case evidence upload reservations.
-- Read-only; requires current ownership of the exclusive case lock.

BEGIN;

CREATE FUNCTION public.list_employee_case_evidence_upload_reservations(
    p_case_id uuid,
    p_lock_token uuid
)
RETURNS TABLE (
    reservation_id uuid,
    file_name text,
    reservation_status text,
    created_at timestamptz,
    expires_at timestamptz
)
LANGUAGE plpgsql
STABLE
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
        r.id,
        r.file_name::text,
        CASE
            WHEN r.status = 'pending'
                 AND r.expires_at <= clock_timestamp()
            THEN 'expired'::text
            ELSE r.status
        END,
        r.created_at,
        r.expires_at
    FROM public.case_evidence_upload_reservations AS r
    WHERE r.case_id = p_case_id
      AND r.organisation_id = v_organisation_id
      AND r.employee_id = v_employee_id
    ORDER BY r.created_at DESC, r.id DESC;
END;
$function$;

REVOKE ALL ON FUNCTION
    public.list_employee_case_evidence_upload_reservations(uuid, uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
    public.list_employee_case_evidence_upload_reservations(uuid, uuid)
TO authenticated;

COMMIT;
