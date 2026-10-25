-- MADZERA MIGRATION 061
-- Team Permission Authorisation Helper
--
-- Purpose:
--   Centralise explicit team permission checks.
--
-- Security:
--   - Identity derived from the authenticated session.
--   - Organisation isolation enforced.
--   - No implicit permission from team membership.
--   - No implicit permission inheritance.
--   - Missing or revoked grants deny access.
--
-- This migration does not change case workflows.

BEGIN;

CREATE OR REPLACE FUNCTION public.has_team_permission(
    p_team_id uuid,
    p_permission_type text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT
        COALESCE(
            (
                SELECT EXISTS (
                    SELECT 1
                    FROM public.team_permission_grants AS g
                    INNER JOIN public.teams AS t
                        ON t.id = g.team_id
                       AND t.organisation_id = g.organisation_id
                    WHERE g.team_id = p_team_id
                      AND g.permission_type = p_permission_type
                      AND g.user_id = identity.employee_id
                      AND g.organisation_id = identity.organisation_id
                      AND p_permission_type IN (
                          'submit',
                          'work',
                          'manage'
                      )
                )
                FROM (
                    SELECT
                        public.current_employee_id() AS employee_id,
                        public.current_user_organisation_id()
                            AS organisation_id
                ) AS identity
                WHERE identity.employee_id IS NOT NULL
                  AND identity.organisation_id IS NOT NULL
            ),
            FALSE
        );
$function$;

REVOKE ALL ON FUNCTION public.has_team_permission(
    uuid,
    text
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.has_team_permission(
    uuid,
    text
) TO authenticated;

COMMIT;
