-- MADZERA MIGRATION 051
-- Read-only recovery status for an employee's evidence reservation.
-- Does not modify case locks, Storage objects, or evidence records.

BEGIN;

CREATE FUNCTION public.get_case_evidence_upload_recovery_status(
    p_reservation_id uuid,
    p_case_id uuid,
    p_lock_token uuid
)
RETURNS TABLE (
    reservation_status text,
    attachment_id uuid
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
    v_reservation public.case_evidence_upload_reservations%ROWTYPE;
    v_attachment_id uuid;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL
        OR v_organisation_id IS NULL
        OR p_reservation_id IS NULL
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

    SELECT r.*
    INTO v_reservation
    FROM public.case_evidence_upload_reservations AS r
    WHERE r.id = p_reservation_id
      AND r.case_id = p_case_id
      AND r.organisation_id = v_organisation_id
      AND r.employee_id = v_employee_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Evidence reservation not found'
            USING ERRCODE = '42501';
    END IF;

    IF v_reservation.status = 'completed' THEN
        SELECT a.id
        INTO v_attachment_id
        FROM public.attachments AS a
        WHERE a.storage_reference = v_reservation.storage_path
          AND a.case_id = p_case_id
          AND a.organisation_id = v_organisation_id
          AND a.uploaded_by_user_id = v_employee_id
          AND a.visibility = 'internal'
        ORDER BY a.created_at ASC, a.id ASC
        LIMIT 1;

        IF v_attachment_id IS NULL THEN
            RAISE EXCEPTION 'Completed reservation missing attachment'
                USING ERRCODE = '22023';
        END IF;

        RETURN QUERY SELECT 'completed'::text, v_attachment_id;

    ELSIF v_reservation.status = 'expired'
        OR v_reservation.expires_at <= clock_timestamp()
    THEN
        RETURN QUERY SELECT 'expired'::text, NULL::uuid;

    ELSE
        RETURN QUERY SELECT 'pending'::text, NULL::uuid;
    END IF;
END;
$function$;

REVOKE ALL ON FUNCTION
    public.get_case_evidence_upload_recovery_status(uuid, uuid, uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
    public.get_case_evidence_upload_recovery_status(uuid, uuid, uuid)
TO authenticated;

COMMIT;
