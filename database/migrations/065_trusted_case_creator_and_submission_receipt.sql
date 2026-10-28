-- MADZERA MIGRATION 065
-- Trusted Case Creator Attribution and Minimal Submission Receipt
--
-- STATUS: DRAFT - NOT YET APPLIED.
--
-- Security objectives:
-- 1. Attribute employee-created cases to the authenticated employee.
-- 2. Enforce organisation-scoped creator identity.
-- 3. Prevent subsequent modification of creator attribution.
-- 4. Preserve historical attribution until separately verified.
-- 5. Allow attributed creators to retrieve minimal submission receipts.
-- 6. Preserve existing case creation, audit and reference behaviour.
-- 7. Do not grant operational case access through receipt retrieval.
--
-- Requires migrations through 064.
-- Must pass dedicated rollback-only security regression tests
-- before permanent application.

BEGIN;

-- ============================================================
-- 1. TRUSTED CREATOR ATTRIBUTION
-- ============================================================

ALTER TABLE public.cases
    ADD COLUMN created_by_user_id uuid;

ALTER TABLE public.cases
    ADD CONSTRAINT fk_cases_creator_user_organisation
    FOREIGN KEY (created_by_user_id, organisation_id)
    REFERENCES public.users (id, organisation_id);

COMMENT ON COLUMN public.cases.created_by_user_id IS
    'Original authenticated employee creator; immutable after insertion. NULL for unattributed historical, customer or system cases.';

-- ============================================================
-- 2. HISTORICAL ATTRIBUTION POLICY
-- ============================================================
--
-- Existing historical cases remain unattributed by this migration.
-- Verified historical backfill requires a separately reviewed,
-- auditable administrative data-migration procedure.
-- No employee authentication context is impersonated here.
--

-- ============================================================
-- 3. IMMUTABLE CREATOR ATTRIBUTION
-- ============================================================

CREATE FUNCTION madzera_internal.protect_case_creator()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF NEW.created_by_user_id
       IS DISTINCT FROM OLD.created_by_user_id THEN
        RAISE EXCEPTION
            'Original case creator cannot be modified'
            USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_protect_case_creator
BEFORE UPDATE ON public.cases
FOR EACH ROW
EXECUTE FUNCTION madzera_internal.protect_case_creator();

REVOKE ALL ON FUNCTION
    madzera_internal.protect_case_creator()
FROM PUBLIC, anon, authenticated;

-- ============================================================
-- 4. EMPLOYEE CASE CREATION
-- ============================================================

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
        initiated_by,
        created_by_user_id
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
        'employee',
        v_employee_id
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

-- ============================================================
-- 5. MINIMAL ORIGINAL-CREATOR SUBMISSION RECEIPT
-- ============================================================

CREATE FUNCTION public.get_case_submission_receipt(
    p_case_id uuid
)
RETURNS TABLE (
    case_id uuid,
    case_reference text,
    created_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT
        c.id,
        c.case_reference,
        c.created_at
    FROM public.cases c
    WHERE c.id = p_case_id
      AND c.organisation_id = public.current_user_organisation_id()
      AND c.created_by_user_id = public.current_employee_id()
      AND c.initiated_by = 'employee'
      AND c.created_by_user_id IS NOT NULL
    LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION
    public.get_case_submission_receipt(uuid)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
    public.get_case_submission_receipt(uuid)
TO authenticated;

COMMENT ON FUNCTION public.get_case_submission_receipt(uuid) IS
    'Returns minimal case-submission confirmation to the original authenticated employee creator only. Does not grant destination-team work access.';

COMMIT;
