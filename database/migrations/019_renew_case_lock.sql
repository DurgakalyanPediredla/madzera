-- MADZERA MIGRATION 019
-- Renew an active case lock only for its authenticated owner.
-- Preserves the live five-minute expiry behaviour.

BEGIN;

CREATE OR REPLACE FUNCTION public.renew_case_lock(
    p_case_id UUID,
    p_lock_token UUID
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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

REVOKE ALL ON FUNCTION public.renew_case_lock(UUID, UUID)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.renew_case_lock(UUID, UUID)
TO authenticated, service_role;

COMMIT;
