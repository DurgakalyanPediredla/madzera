-- Migration 063: Mandatory destination-team submission authorisation.
-- Enforces explicit team selection and submit permission for employee cases.
-- Preserves historical cases and existing public RPC signatures.

BEGIN;

CREATE OR REPLACE FUNCTION madzera_internal.create_employee_case_impl(
    p_title text,
    p_description text,
    p_priority text,
    p_customer_id uuid,
    p_assigned_team_id uuid,
    p_case_type text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
    v_case_id uuid;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Active employee authentication required'
            USING ERRCODE = '42501';
    END IF;

    IF p_title IS NULL OR length(btrim(p_title)) = 0 THEN
        RAISE EXCEPTION 'Case title is required'
            USING ERRCODE = '22023';
    END IF;

    IF p_priority IS NULL
       OR p_priority NOT IN ('low', 'medium', 'high', 'critical') THEN
        RAISE EXCEPTION 'Invalid case priority'
            USING ERRCODE = '22023';
    END IF;

    IF p_case_type IS NULL
       OR p_case_type NOT IN ('customer_query', 'internal_case') THEN
        RAISE EXCEPTION 'Invalid case type'
            USING ERRCODE = '22023';
    END IF;

    IF p_case_type = 'customer_query' AND p_customer_id IS NULL THEN
        RAISE EXCEPTION 'Customer enquiry requires a customer'
            USING ERRCODE = '22023';
    END IF;

    IF p_customer_id IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
           FROM public.customers c
           WHERE c.id = p_customer_id
             AND c.organisation_id = v_organisation_id
       ) THEN
        RAISE EXCEPTION 'Customer not found in employee organisation'
            USING ERRCODE = '42501';
    END IF;

    IF p_assigned_team_id IS NULL THEN
        RAISE EXCEPTION 'Destination team is required'
            USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
           SELECT 1
           FROM public.teams t
           WHERE t.id = p_assigned_team_id
             AND t.organisation_id = v_organisation_id
       ) THEN
        RAISE EXCEPTION 'Team not found in employee organisation'
            USING ERRCODE = '42501';
    END IF;

    IF NOT public.has_team_permission(
        p_assigned_team_id,
        'submit'
    ) THEN
        RAISE EXCEPTION 'Submission permission required for destination team'
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.cases (
        organisation_id,
        customer_id,
        assigned_team_id,
        title,
        description,
        status,
        priority,
        source,
        case_type,
        initiated_by
    )
    VALUES (
        v_organisation_id,
        p_customer_id,
        p_assigned_team_id,
        btrim(p_title),
        p_description,
        'open',
        p_priority,
        'manual',
        p_case_type,
        'employee'
    )
    RETURNING id INTO v_case_id;

    INSERT INTO public.case_events (
        case_id,
        organisation_id,
        actor_user_id,
        event_type,
        to_status,
        to_team_id,
        details
    )
    VALUES (
        v_case_id,
        v_organisation_id,
        v_employee_id,
        'case_created',
        'open',
        p_assigned_team_id,
        'Case created manually by an authenticated employee.'
    );

    RETURN v_case_id;
END;
$function$;

COMMIT;
