-- MADZERA MIGRATION 049
-- Restrict evidence downloads to finalised attachments
-- belonging to cases exclusively locked by the employee.

BEGIN;

CREATE FUNCTION public.can_download_locked_case_evidence(
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
        FROM public.attachments AS a
        JOIN public.cases AS c
          ON c.id = a.case_id
         AND c.organisation_id = a.organisation_id
        JOIN public.case_locks AS l
          ON l.case_id = a.case_id
         AND l.organisation_id = a.organisation_id
        JOIN public.users AS u
          ON u.id = l.locked_by_user_id
         AND u.organisation_id = a.organisation_id
        JOIN public.case_evidence_upload_reservations AS r
          ON r.storage_path = a.storage_reference
         AND r.case_id = a.case_id
         AND r.organisation_id = a.organisation_id
        WHERE a.storage_reference = p_storage_path
          AND a.visibility = 'internal'
          AND r.status = 'completed'
          AND u.auth_user_id = (SELECT auth.uid())
          AND u.is_active = true
          AND l.expires_at > clock_timestamp()
    );
$function$;

REVOKE ALL ON FUNCTION public.can_download_locked_case_evidence(text)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.can_download_locked_case_evidence(text)
TO authenticated;

CREATE POLICY case_evidence_locked_employee_download
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'case-evidence'
    AND public.can_download_locked_case_evidence(name)
    AND storage.allow_only_operation('object.get_authenticated')
);

COMMIT;
