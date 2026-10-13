-- MADZERA MIGRATION 023
-- Record an audit event when an employee exits a case record.
-- Direct execution is restricted to privileged database roles.

BEGIN;

CREATE OR REPLACE FUNCTION public.record_case_exit(p_case_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id UUID;
    v_organisation_id UUID;
    v_event_id UUID;
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

    INSERT INTO public.case_events (
        case_id,
        organisation_id,
        actor_user_id,
        event_type,
        details
    )
    VALUES (
        p_case_id,
        v_organisation_id,
        v_employee_id,
        'case_closed_view',
        'Employee exited the case record'
    )
    RETURNING id INTO v_event_id;

    RETURN v_event_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.record_case_exit(UUID)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.record_case_exit(UUID)
TO service_role, postgres;

COMMIT;
