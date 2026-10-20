-- MADZERA MIGRATION 041
-- Allow internal cases to optionally reference a customer.
-- Preserve the existing five-argument creation RPC.
-- Keep case classification independent of customer association.

BEGIN;

CREATE FUNCTION madzera_internal.create_employee_case_impl(
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

    IF p_assigned_team_id IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
           FROM public.teams t
           WHERE t.id = p_assigned_team_id
             AND t.organisation_id = v_organisation_id
       ) THEN
        RAISE EXCEPTION 'Team not found in employee organisation'
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

REVOKE ALL ON FUNCTION madzera_internal.create_employee_case_impl(
    text, text, text, uuid, uuid, text
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_employee_case(
    p_title text,
    p_description text DEFAULT NULL,
    p_priority text DEFAULT 'medium',
    p_customer_id uuid DEFAULT NULL,
    p_assigned_team_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    RETURN madzera_internal.create_employee_case_impl(
        p_title,
        p_description,
        p_priority,
        p_customer_id,
        p_assigned_team_id,
        CASE
            WHEN p_customer_id IS NULL THEN 'internal_case'
            ELSE 'customer_query'
        END
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.create_employee_case(
    text, text, text, uuid, uuid
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_employee_case(
    text, text, text, uuid, uuid
) TO authenticated, service_role;

CREATE FUNCTION public.create_employee_case_v2(
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
BEGIN
    RETURN madzera_internal.create_employee_case_impl(
        p_title,
        p_description,
        p_priority,
        p_customer_id,
        p_assigned_team_id,
        p_case_type
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.create_employee_case_v2(
    text, text, text, uuid, uuid, text
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_employee_case_v2(
    text, text, text, uuid, uuid, text
) TO authenticated, service_role;

COMMIT;
