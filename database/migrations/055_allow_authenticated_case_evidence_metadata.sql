-- MADZERA MIGRATION 055
-- Allow authenticated evidence metadata lookup required by Storage downloads.
-- Preserve existing locked-employee evidence authorisation.

BEGIN;

DROP POLICY IF EXISTS case_evidence_locked_employee_download
ON storage.objects;

CREATE POLICY case_evidence_locked_employee_download
ON storage.objects
FOR SELECT
TO authenticated
USING (
    bucket_id = 'case-evidence'
    AND public.can_download_locked_case_evidence(name)
    AND storage.allow_any_operation(
        ARRAY[
            'object.get_authenticated',
            'object.get_authenticated_info'
        ]
    )
);

COMMIT;
