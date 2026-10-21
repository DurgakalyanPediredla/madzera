-- MADZERA MIGRATION 046
-- Restrict case-evidence Storage uploads to valid reservations.
-- No broad SELECT, UPDATE or DELETE access is granted.

BEGIN;

CREATE FUNCTION public.can_upload_reserved_case_evidence(
    p_storage_path text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.case_evidence_upload_reservations AS r
        JOIN public.case_locks AS l
          ON l.case_id = r.case_id
         AND l.organisation_id = r.organisation_id
        JOIN public.users AS u
          ON u.id = r.employee_id
         AND u.organisation_id = r.organisation_id
        WHERE r.storage_path = p_storage_path
          AND r.status = 'pending'
          AND r.expires_at > clock_timestamp()
          AND u.auth_user_id = auth.uid()
          AND u.is_active = true
          AND l.locked_by_user_id = r.employee_id
          AND l.expires_at > clock_timestamp()
    );
$function$;

REVOKE ALL ON FUNCTION public.can_upload_reserved_case_evidence(text)
    FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.can_upload_reserved_case_evidence(text)
    TO authenticated;

CREATE POLICY case_evidence_reserved_employee_insert
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'case-evidence'
    AND public.can_upload_reserved_case_evidence(name)
);

COMMIT;
