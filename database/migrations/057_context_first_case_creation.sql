-- Migration 057: Context-first employee case creation
-- Adds a versioned RPC without modifying existing creation or locking functions.
-- Requires migration 056.
BEGIN;

CREATE FUNCTION public.create_employee_case_v3(
    p_title text,
    p_description text,
    p_priority text,
    p_customer_id uuid,
    p_assigned_team_id uuid,
    p_case_type text,
    p_operation_type text,
    p_issue_category text,
    p_references jsonb DEFAULT '[]'::jsonb
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
    v_reference jsonb;
    v_reference_type text;
    v_reference_value text;
    v_seen jsonb := '[]'::jsonb;
BEGIN
    -- Do not accept tenant identity from client input.
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Active employee authentication required'
            USING ERRCODE = '42501';
    END IF;

    IF p_operation_type IS NULL
       OR p_operation_type NOT IN (
           'import_declaration',
           'export_declaration',
           'transit_movement',
           'documents_compliance',
           'general_internal'
       ) THEN
        RAISE EXCEPTION 'Invalid customs operation type'
            USING ERRCODE = '22023';
    END IF;

    IF p_issue_category IS NULL
       OR pg_catalog.length(pg_catalog.btrim(p_issue_category)) NOT BETWEEN 1 AND 100
       OR p_issue_category <> pg_catalog.btrim(p_issue_category) THEN
        RAISE EXCEPTION 'Invalid issue category'
            USING ERRCODE = '22023';
    END IF;

    IF p_references IS NULL
       OR pg_catalog.jsonb_typeof(p_references) <> 'array' THEN
        RAISE EXCEPTION 'References must be a JSON array'
            USING ERRCODE = '22023';
    END IF;

    IF pg_catalog.jsonb_array_length(p_references) > 20 THEN
        RAISE EXCEPTION 'Too many operational references'
            USING ERRCODE = '22023';
    END IF;

    -- Validate the entire reference collection before creating a case.
    FOR v_reference IN
        SELECT value
        FROM pg_catalog.jsonb_array_elements(p_references)
    LOOP
        IF pg_catalog.jsonb_typeof(v_reference) <> 'object'
           OR NOT (v_reference ? 'reference_type')
           OR NOT (v_reference ? 'reference_value')
           OR pg_catalog.jsonb_typeof(v_reference -> 'reference_type') <> 'string'
           OR pg_catalog.jsonb_typeof(v_reference -> 'reference_value') <> 'string'
           OR (SELECT count(*) FROM pg_catalog.jsonb_object_keys(v_reference)) <> 2
        THEN
            RAISE EXCEPTION 'Invalid reference object'
                USING ERRCODE = '22023';
        END IF;

        v_reference_type := v_reference ->> 'reference_type';
        v_reference_value := v_reference ->> 'reference_value';

        IF v_reference_type NOT IN (
            'import_mrn',
            'export_mrn',
            'transit_mrn',
            'ducr',
            'gmr',
            'shipment_reference',
            'job_reference',
            'eori',
            'other'
        ) THEN
            RAISE EXCEPTION 'Invalid reference type'
                USING ERRCODE = '22023';
        END IF;

        IF pg_catalog.length(pg_catalog.btrim(v_reference_value)) NOT BETWEEN 1 AND 150
           OR v_reference_value <> pg_catalog.btrim(v_reference_value) THEN
            RAISE EXCEPTION 'Invalid reference value'
                USING ERRCODE = '22023';
        END IF;

        IF v_seen @> pg_catalog.jsonb_build_array(
            pg_catalog.jsonb_build_object(
                'reference_type', v_reference_type,
                'reference_value', v_reference_value
            )
        ) THEN
            RAISE EXCEPTION 'Duplicate operational reference'
                USING ERRCODE = '22023';
        END IF;

        v_seen := v_seen || pg_catalog.jsonb_build_array(
            pg_catalog.jsonb_build_object(
                'reference_type', v_reference_type,
                'reference_value', v_reference_value
            )
        );
    END LOOP;

    -- Existing implementation enforces case/customer/team rules and
    -- writes the employee-attributed case_created audit event.
    v_case_id := madzera_internal.create_employee_case_impl(
        p_title,
        p_description,
        p_priority,
        p_customer_id,
        p_assigned_team_id,
        p_case_type
    );

    INSERT INTO public.case_customs_context (
        case_id,
        organisation_id,
        operation_type,
        issue_category
    )
    VALUES (
        v_case_id,
        v_organisation_id,
        p_operation_type,
        p_issue_category
    );

    INSERT INTO public.case_operational_references (
        case_id,
        organisation_id,
        reference_type,
        reference_value
    )
    SELECT
        v_case_id,
        v_organisation_id,
        item.value ->> 'reference_type',
        item.value ->> 'reference_value'
    FROM pg_catalog.jsonb_array_elements(p_references) AS item(value);

    RETURN v_case_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_employee_case_v3(
    text, text, text, uuid, uuid, text, text, text, jsonb
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_employee_case_v3(
    text, text, text, uuid, uuid, text, text, text, jsonb
) TO authenticated, service_role;

COMMIT;
