-- MADZERA MIGRATION 047
-- Finalise reserved evidence uploads.
-- Preserves the existing exclusive case-lock lifecycle.

BEGIN;

CREATE FUNCTION public.finalise_case_evidence_upload(
    p_reservation_id uuid,
    p_lock_token uuid,
    p_comment_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
    v_reservation public.case_evidence_upload_reservations%ROWTYPE;
    v_lock public.case_locks%ROWTYPE;
    v_object storage.objects%ROWTYPE;
    v_attachment_id uuid;
    v_actual_size bigint;
    v_actual_type text;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required'
            USING ERRCODE = '42501';
    END IF;

    SELECT r.*
    INTO v_reservation
    FROM public.case_evidence_upload_reservations AS r
    WHERE r.id = p_reservation_id
      AND r.employee_id = v_employee_id
      AND r.organisation_id = v_organisation_id
      AND r.status = 'pending'
    FOR UPDATE;

    IF NOT FOUND
       OR v_reservation.expires_at <= clock_timestamp()
    THEN
        RAISE EXCEPTION 'Upload reservation invalid or expired'
            USING ERRCODE = '42501';
    END IF;

    SELECT l.*
    INTO v_lock
    FROM public.case_locks AS l
    WHERE l.case_id = v_reservation.case_id
      AND l.organisation_id = v_organisation_id
    FOR UPDATE;

    IF NOT FOUND
       OR v_lock.locked_by_user_id IS DISTINCT FROM v_employee_id
       OR v_lock.lock_token IS DISTINCT FROM p_lock_token
       OR v_lock.expires_at <= clock_timestamp()
    THEN
        RAISE EXCEPTION 'Valid exclusive case lock required'
            USING ERRCODE = '42501';
    END IF;

    IF p_comment_id IS NOT NULL THEN
        PERFORM 1
        FROM public.comments AS c
        WHERE c.id = p_comment_id
          AND c.case_id = v_reservation.case_id
          AND c.organisation_id = v_organisation_id
          AND c.visibility = 'internal';

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Activity not found in this case'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    SELECT o.*
    INTO v_object
    FROM storage.objects AS o
    WHERE o.bucket_id = 'case-evidence'
      AND o.name = v_reservation.storage_path
      AND o.archived_at IS NULL
      AND o.is_delete_marker IS DISTINCT FROM true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Uploaded evidence object not found'
            USING ERRCODE = '22023';
    END IF;

    IF v_object.metadata->>'size' IS NULL
       OR (v_object.metadata->>'size') !~ '^[0-9]+$'
    THEN
        RAISE EXCEPTION 'Uploaded evidence size metadata missing'
            USING ERRCODE = '22023';
    END IF;

    v_actual_size := (v_object.metadata->>'size')::bigint;
    v_actual_type := v_object.metadata->>'mimetype';

    IF v_actual_size <> v_reservation.file_size_bytes
       OR v_actual_type IS DISTINCT FROM v_reservation.file_type
    THEN
        RAISE EXCEPTION 'Uploaded evidence metadata does not match reservation'
            USING ERRCODE = '22023';
    END IF;

    IF v_lock.expires_at <= clock_timestamp() THEN
        RAISE EXCEPTION 'Case lock expired during finalisation'
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.attachments (
        case_id,
        organisation_id,
        uploaded_by_user_id,
        file_name,
        file_type,
        file_size_bytes,
        storage_reference,
        visibility,
        comment_id
    )
    VALUES (
        v_reservation.case_id,
        v_organisation_id,
        v_employee_id,
        v_reservation.file_name,
        v_reservation.file_type,
        v_actual_size,
        v_reservation.storage_path,
        'internal',
        p_comment_id
    )
    RETURNING id INTO v_attachment_id;

    INSERT INTO public.case_events (
        case_id,
        organisation_id,
        actor_user_id,
        event_type,
        details
    )
    VALUES (
        v_reservation.case_id,
        v_organisation_id,
        v_employee_id,
        'evidence_uploaded',
        'Attachment ID: ' || v_attachment_id::text
    );

    UPDATE public.case_evidence_upload_reservations
    SET
        status = 'completed',
        completed_at = clock_timestamp()
    WHERE id = v_reservation.id;

    RETURN v_attachment_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.finalise_case_evidence_upload(
    uuid, uuid, uuid
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.finalise_case_evidence_upload(
    uuid, uuid, uuid
) TO authenticated;

COMMIT;
