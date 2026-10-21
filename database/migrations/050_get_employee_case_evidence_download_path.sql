BEGIN;

CREATE FUNCTION public.get_employee_case_evidence_download_path(
    p_attachment_id uuid,
    p_case_id uuid,
    p_lock_token uuid
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
    v_storage_path text;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL
       OR v_organisation_id IS NULL
       OR p_attachment_id IS NULL
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

    SELECT a.storage_reference
    INTO v_storage_path
    FROM public.attachments AS a
    JOIN public.case_evidence_upload_reservations AS r
      ON r.storage_path = a.storage_reference
     AND r.case_id = a.case_id
     AND r.organisation_id = a.organisation_id
    WHERE a.id = p_attachment_id
      AND a.case_id = p_case_id
      AND a.organisation_id = v_organisation_id
      AND a.visibility = 'internal'
      AND r.status = 'completed';

    IF v_storage_path IS NULL THEN
        RAISE EXCEPTION 'Evidence attachment not found'
            USING ERRCODE = '42501';
    END IF;

    RETURN v_storage_path;
END;
$function$;

REVOKE ALL ON FUNCTION
    public.get_employee_case_evidence_download_path(uuid, uuid, uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
    public.get_employee_case_evidence_download_path(uuid, uuid, uuid)
TO authenticated;

COMMIT;
