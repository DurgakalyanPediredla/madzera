-- MADZERA MIGRATION 064
-- Team Work Authorisation: Case Session Entry
--
-- VERIFIED IN ROLLBACK-ONLY LOCAL TEST; NOT YET PERMANENTLY APPLIED.
--
-- Security objectives:
--   1. Require explicit destination-team work permission.
--   2. Preserve organisation isolation.
--   3. Preserve existing exclusive lock mechanics.
--   4. Deny unassigned legacy cases until separately remediated.
--
-- Remaining work before deployment:
--   - Review full installed function definitions.
--   - Implement work checks at independent session boundaries.
--   - Review renewal, resume, case details and operational RPCs.
--   - Preserve safe lock release after revocation.
--   - Add rollback-based regression tests.
--   - Verify frontend compatibility.
--   - Review deployment atomicity and migration ordering.
--
-- Executable SQL passed rollback-only security test 042 on 26 October 2026.

BEGIN;

CREATE OR REPLACE FUNCTION public.acquire_case_lock(p_case_id uuid)
 RETURNS TABLE(acquired boolean, lock_expires_at timestamp with time zone, lock_token uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_employee_id UUID;
    v_organisation_id UUID;
    v_expires_at TIMESTAMPTZ;
    v_token UUID;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases c
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
    ) THEN
        RAISE EXCEPTION 'Case not found or access denied';
    END IF;

    -- Require explicit work permission before acquiring a case lock.
    -- Unassigned legacy cases are denied until separately remediated.
    IF NOT EXISTS (
        SELECT 1
        FROM public.cases AS c
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
          AND c.assigned_team_id IS NOT NULL
          AND public.has_team_permission(
              c.assigned_team_id,
              'work'
          )
    ) THEN
        RAISE EXCEPTION 'Team work permission required'
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.case_locks (
        case_id,
        organisation_id,
        locked_by_user_id,
        lock_token,
        locked_at,
        expires_at
    )
    VALUES (
        p_case_id,
        v_organisation_id,
        v_employee_id,
        gen_random_uuid(),
        NOW(),
        NOW() + INTERVAL '5 minutes'
    )
    ON CONFLICT (case_id)
    DO UPDATE SET
        locked_by_user_id = EXCLUDED.locked_by_user_id,
        lock_token = EXCLUDED.lock_token,
        locked_at = EXCLUDED.locked_at,
        expires_at = EXCLUDED.expires_at
    WHERE public.case_locks.expires_at <= NOW()
    RETURNING
        public.case_locks.expires_at,
        public.case_locks.lock_token
    INTO v_expires_at, v_token;

    RETURN QUERY
    SELECT
        v_token IS NOT NULL,
        v_expires_at,
        v_token;
END;
$function$;


CREATE OR REPLACE FUNCTION public.resume_employee_case_session(p_case_id uuid, p_lock_token uuid)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_employee_id UUID;
    v_organisation_id UUID;
    v_expires_at TIMESTAMPTZ;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required'
            USING ERRCODE = '42501';
    END IF;


    IF p_case_id IS NULL OR p_lock_token IS NULL THEN
        RETURN NULL;
    END IF;

    -- Require current work permission before using an existing lock.
    IF NOT EXISTS (
        SELECT 1
        FROM public.cases AS c
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
          AND c.assigned_team_id IS NOT NULL
          AND public.has_team_permission(
              c.assigned_team_id,
              'work'
          )
    ) THEN
        RAISE EXCEPTION 'Team work permission required'
            USING ERRCODE = '42501';
    END IF;


    SELECT l.expires_at
    INTO v_expires_at
    FROM public.case_locks AS l
    INNER JOIN public.cases AS c
        ON c.id = l.case_id
       AND c.organisation_id = l.organisation_id
    WHERE l.case_id = p_case_id
      AND l.organisation_id = v_organisation_id
      AND c.organisation_id = v_organisation_id
      AND l.locked_by_user_id = v_employee_id
      AND l.lock_token = p_lock_token
      AND l.expires_at > clock_timestamp();

    RETURN v_expires_at;
END;
$function$;

CREATE OR REPLACE FUNCTION public.renew_case_lock(p_case_id uuid, p_lock_token uuid)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_employee_id UUID;
    v_organisation_id UUID;
    v_expires_at TIMESTAMPTZ;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required';
    END IF;

    IF p_lock_token IS NULL THEN
        RETURN NULL;
    END IF;


    -- Require current work permission before using an existing lock.
    IF NOT EXISTS (
        SELECT 1
        FROM public.cases AS c
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
          AND c.assigned_team_id IS NOT NULL
          AND public.has_team_permission(
              c.assigned_team_id,
              'work'
          )
    ) THEN
        RAISE EXCEPTION 'Team work permission required'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.case_locks
    SET expires_at = NOW() + INTERVAL '5 minutes'
    WHERE case_id = p_case_id
      AND organisation_id = v_organisation_id
      AND locked_by_user_id = v_employee_id
      AND lock_token = p_lock_token
      AND expires_at > NOW()
    RETURNING expires_at INTO v_expires_at;

    RETURN v_expires_at;
END;
$function$;


CREATE OR REPLACE FUNCTION public.open_case_session(p_case_id uuid)
 RETURNS TABLE(acquired boolean, lock_expires_at timestamp with time zone, lock_token uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_employee_id UUID;
    v_organisation_id UUID;
    v_acquired BOOLEAN;
    v_expires_at TIMESTAMPTZ;
    v_token UUID;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases c
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
    ) THEN
        RAISE EXCEPTION 'Case not found or access denied';
    END IF;

    -- Require explicit work permission before opening a case.
    IF NOT EXISTS (
        SELECT 1
        FROM public.cases AS c
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
          AND c.assigned_team_id IS NOT NULL
          AND public.has_team_permission(
              c.assigned_team_id,
              'work'
          )
    ) THEN
        RAISE EXCEPTION 'Team work permission required'
            USING ERRCODE = '42501';
    END IF;

    SELECT
        l.acquired,
        l.lock_expires_at,
        l.lock_token
    INTO
        v_acquired,
        v_expires_at,
        v_token
    FROM public.acquire_case_lock(p_case_id) AS l;

    IF v_acquired THEN
        PERFORM public.record_case_opened(p_case_id);
    END IF;

    RETURN QUERY
    SELECT
        COALESCE(v_acquired, FALSE),
        v_expires_at,
        v_token;
END;
$function$;

COMMIT;
