-- Controlled employee case updates.
-- A valid, unexpired case-session lock is required.
BEGIN;

CREATE OR REPLACE FUNCTION public.update_employee_case(
    p_case_id uuid,
    p_lock_token uuid,
    p_status text DEFAULT NULL,
    p_priority text DEFAULT NULL,
    p_assigned_team_id uuid DEFAULT NULL,
    p_assigned_user_id uuid DEFAULT NULL,
    p_clear_team boolean DEFAULT FALSE,
    p_clear_user boolean DEFAULT FALSE
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

    IF (p_clear_team AND p_assigned_team_id IS NOT NULL)
       OR (p_clear_user AND p_assigned_user_id IS NOT NULL)
    THEN
        RAISE EXCEPTION 'Cannot assign and clear the same field'
            USING ERRCODE = '22023';
    END IF;

    -- Lock the lock record for this transaction.
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

    UPDATE public.cases AS c
    SET
        status = COALESCE(p_status, c.status),
        priority = COALESCE(p_priority, c.priority),
        assigned_team_id = CASE
            WHEN p_clear_team THEN NULL
            ELSE COALESCE(p_assigned_team_id, c.assigned_team_id)
        END,
        assigned_user_id = CASE
            WHEN p_clear_user THEN NULL
            ELSE COALESCE(p_assigned_user_id, c.assigned_user_id)
        END
    WHERE c.id = p_case_id
      AND c.organisation_id = v_organisation_id
      AND v_lock.expires_at > clock_timestamp();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Case not found or access denied'
            USING ERRCODE = '42501';
    END IF;

    RETURN p_case_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.update_employee_case(
    uuid, uuid, text, text, uuid, uuid, boolean, boolean
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.update_employee_case(
    uuid, uuid, text, text, uuid, uuid, boolean, boolean
) TO authenticated;

COMMIT;
