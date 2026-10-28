-- MADZERA MIGRATION 066
-- Team-Scoped Operational Case Queue Visibility
--
-- STATUS: DRAFT - NOT YET APPLIED.
--
-- Security objectives:
-- 1. Restrict operational queue visibility to explicit team work grants.
-- 2. Preserve organisation isolation.
-- 3. Deny visibility for cases without a destination team.
-- 4. Do not grant visibility through submission or creator status.
-- 5. Preserve the existing 15-column queue contract.
-- 6. Preserve customer reference and active-lock display behaviour.
-- 7. Preserve case ordering.
--
-- Requires migrations through 065.
-- Must pass rollback-only security regression tests.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_case_queue()
RETURNS TABLE (
    case_id uuid,
    case_title varchar,
    case_status varchar,
    case_priority varchar,
    case_source varchar,
    customer_id uuid,
    assigned_team_id uuid,
    assigned_user_id uuid,
    created_at timestamptz,
    locked_by_name varchar,
    case_type varchar,
    initiated_by varchar,
    case_reference text,
    customer_reference text,
    customer_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT
        c.id AS case_id,
        c.title AS case_title,
        c.status AS case_status,
        c.priority AS case_priority,
        c.source AS case_source,
        c.customer_id,
        c.assigned_team_id,
        c.assigned_user_id,
        c.created_at,
        u.full_name AS locked_by_name,
        c.case_type,
        c.initiated_by,
        c.case_reference,
        customer.customer_reference,
        customer.name::text AS customer_name
    FROM public.cases AS c
    LEFT JOIN public.customers AS customer
        ON customer.id = c.customer_id
       AND customer.organisation_id = c.organisation_id
    LEFT JOIN public.case_locks AS l
        ON l.case_id = c.id
       AND l.organisation_id = c.organisation_id
       AND l.expires_at > NOW()
    LEFT JOIN public.users AS u
        ON u.id = l.locked_by_user_id
       AND u.organisation_id = c.organisation_id
    WHERE c.organisation_id = public.current_user_organisation_id()
      AND c.assigned_team_id IS NOT NULL
      AND public.has_team_permission(
          c.assigned_team_id,
          'work'
      )
    ORDER BY c.created_at DESC;
$function$;

REVOKE ALL ON FUNCTION public.get_case_queue()
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_case_queue()
TO authenticated, service_role;

COMMENT ON FUNCTION public.get_case_queue() IS
    'Returns operational case queue rows only for destination teams where the authenticated employee has an explicit work permission grant. Unassigned cases are excluded.';

COMMIT;
