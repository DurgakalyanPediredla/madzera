-- MADZERA MIGRATION 053
-- Prevent overlapping unresolved evidence reservations.
-- Preserve the existing exclusive case-lock lifecycle.
-- Expired pending reservations remain blocked for recovery review.

BEGIN;

CREATE OR REPLACE FUNCTION public.prepare_case_evidence_upload(
    p_case_id uuid,
    p_lock_token uuid,
    p_file_name text,
    p_file_type text,
    p_file_size_bytes bigint
)
RETURNS TABLE (
    reservation_id uuid,
    storage_path text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
    v_lock public.case_locks%ROWTYPE;
    v_reservation_id uuid;
    v_storage_path text;
    v_file_name text;
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

    v_file_name := btrim(p_file_name);

    IF v_file_name IS NULL
       OR length(v_file_name) = 0
       OR length(v_file_name) > 255
       OR v_file_name ~ '[/\\]'
       OR v_file_name ~ '[[:cntrl:]]'
    THEN
        RAISE EXCEPTION 'Invalid evidence file name'
            USING ERRCODE = '22023';
    END IF;

    IF p_file_type IS NULL
       OR p_file_type NOT IN (
           'application/pdf',
           'image/jpeg',
           'image/png'
       )
    THEN
        RAISE EXCEPTION 'Unsupported evidence file type'
            USING ERRCODE = '22023';
    END IF;

    IF p_file_size_bytes IS NULL
       OR p_file_size_bytes < 1
       OR p_file_size_bytes > 10485760
    THEN
        RAISE EXCEPTION 'Evidence file exceeds permitted size'
            USING ERRCODE = '22023';
    END IF;

    SELECT l.*
    INTO v_lock
    FROM public.case_locks AS l
    WHERE l.case_id = p_case_id
      AND l.organisation_id = v_organisation_id
    FOR UPDATE;

    IF NOT FOUND
       OR v_lock.locked_by_user_id IS DISTINCT FROM v_employee_id
       OR v_lock.lock_token IS DISTINCT FROM p_lock_token
       OR v_lock.expires_at <= clock_timestamp()
    THEN
        RAISE EXCEPTION 'Case lock invalid, expired, or not owned by employee'
            USING ERRCODE = '42501';
    END IF;

    PERFORM 1
    FROM public.cases AS c
    WHERE c.id = p_case_id
      AND c.organisation_id = v_organisation_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Case not found or access denied'
            USING ERRCODE = '42501';
    END IF;

    -- The case-lock row is already locked FOR UPDATE above.
    -- Serialise reservation creation and reject unresolved uploads.
    IF EXISTS (
        SELECT 1
        FROM public.case_evidence_upload_reservations AS r
        WHERE r.case_id = p_case_id
          AND r.organisation_id = v_organisation_id
          AND r.employee_id = v_employee_id
          AND r.status = 'pending'
    ) THEN
        RAISE EXCEPTION
            'An earlier evidence upload requires recovery review'
            USING ERRCODE = '23505';
    END IF;

    v_reservation_id := gen_random_uuid();

    v_storage_path :=
        v_organisation_id::text || '/' ||
        p_case_id::text || '/' ||
        v_reservation_id::text;

    INSERT INTO public.case_evidence_upload_reservations (
        id,
        case_id,
        organisation_id,
        employee_id,
        storage_path,
        file_name,
        file_type,
        file_size_bytes,
        expires_at
    )
    VALUES (
        v_reservation_id,
        p_case_id,
        v_organisation_id,
        v_employee_id,
        v_storage_path,
        v_file_name,
        p_file_type,
        p_file_size_bytes,
        clock_timestamp() + interval '10 minutes'
    );

    RETURN QUERY
    SELECT v_reservation_id, v_storage_path;
END;
$function$;

COMMIT;
