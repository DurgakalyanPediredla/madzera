-- MADZERA MIGRATION 035
-- Feature 001: Save and persistent employee case responsibility.
-- Existing exclusive lock acquisition, renewal and release are unchanged.

BEGIN;

CREATE FUNCTION public.save_employee_case_assignment(
    p_case_id uuid,
    p_lock_token uuid,
    p_expected_assigned_user_id uuid DEFAULT NULL,
    p_confirm_reassignment boolean DEFAULT FALSE
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
    v_current_assignee uuid;
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

    -- Reuse the existing exclusive lock; do not modify its lifecycle.
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

    -- Serialize assignment changes and inspect the current responsibility.
    SELECT c.assigned_user_id
    INTO v_current_assignee
    FROM public.cases AS c
    WHERE c.id = p_case_id
      AND c.organisation_id = v_organisation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Case not found or access denied'
            USING ERRCODE = '42501';
    END IF;

    IF v_current_assignee IS DISTINCT FROM p_expected_assigned_user_id THEN
        RAISE EXCEPTION 'Case assignment changed; refresh before saving'
            USING ERRCODE = '40001';
    END IF;

    IF v_current_assignee IS NOT NULL
       AND v_current_assignee IS DISTINCT FROM v_employee_id
       AND p_confirm_reassignment IS NOT TRUE
    THEN
        RAISE EXCEPTION 'Explicit reassignment confirmation required'
            USING ERRCODE = '42501';
    END IF;

    IF v_lock.expires_at <= clock_timestamp() THEN
        RAISE EXCEPTION 'Case lock expired during save'
            USING ERRCODE = '42501';
    END IF;

    IF v_current_assignee IS DISTINCT FROM v_employee_id THEN
        UPDATE public.cases
        SET assigned_user_id = v_employee_id
        WHERE id = p_case_id
          AND organisation_id = v_organisation_id;
        -- The existing audit trigger records the assignment change.
    END IF;

    RETURN p_case_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.save_employee_case_assignment(
    uuid, uuid, uuid, boolean
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.save_employee_case_assignment(
    uuid, uuid, uuid, boolean
) TO authenticated;

COMMIT;
