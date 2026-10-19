-- MADZERA MIGRATION 036
-- Save an internal employee case activity comment.
-- Preserve existing exclusive-lock lifecycle.

BEGIN;

CREATE FUNCTION public.save_employee_case_comment(
    p_case_id uuid,
    p_lock_token uuid,
    p_body text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
    v_lock public.case_locks%ROWTYPE;
    v_comment_id uuid;
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

    IF p_body IS NULL
       OR length(btrim(p_body)) = 0
       OR length(p_body) > 10000
    THEN
        RAISE EXCEPTION 'Comment must contain 1 to 10000 characters'
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

    IF v_lock.expires_at <= clock_timestamp() THEN
        RAISE EXCEPTION 'Case lock expired during save'
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.comments (
        case_id,
        organisation_id,
        author_user_id,
        body,
        visibility
    )
    VALUES (
        p_case_id,
        v_organisation_id,
        v_employee_id,
        btrim(p_body),
        'internal'
    )
    RETURNING id INTO v_comment_id;

    RETURN v_comment_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.save_employee_case_comment(
    uuid, uuid, text
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.save_employee_case_comment(
    uuid, uuid, text
) TO authenticated;

COMMIT;
