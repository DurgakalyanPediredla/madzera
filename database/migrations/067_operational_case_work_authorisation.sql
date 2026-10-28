-- Migration 067: Operational case work authorisation
--
-- Purpose:
-- Enforce current team-work permission throughout protected
-- employee case operations.
--
-- This initial section introduces a reusable authorisation helper.
-- Operational RPC replacements and Storage enforcement will follow
-- after separate review and rollback-only verification.
--
-- Security principles:
-- 1. Organisation-scoped access.
-- 2. Explicit team-work permission.
-- 3. Fail closed for unassigned cases.
-- 4. No implicit administrator or manage-permission bypass.
-- 5. No changes to existing exclusive lock mechanics.

CREATE OR REPLACE FUNCTION public.can_work_on_case(
    p_case_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT COALESCE(
        (
            SELECT public.has_team_permission(
                c.assigned_team_id,
                'work'
            )
            FROM public.cases AS c
            WHERE c.id = p_case_id
              AND c.organisation_id =
                  public.current_user_organisation_id()
              AND c.assigned_team_id IS NOT NULL
        ),
        FALSE
    );
$function$;

REVOKE ALL ON FUNCTION public.can_work_on_case(uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.can_work_on_case(uuid)
TO authenticated, service_role;


-- Protected operation 01:
-- Case details require current team-work permission
-- in addition to existing exclusive lock validation.

CREATE OR REPLACE FUNCTION public.get_locked_case_details(
    p_case_id UUID,
    p_lock_token UUID
)
RETURNS SETOF public.cases
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id UUID;
    v_organisation_id UUID;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL
       OR v_organisation_id IS NULL
       OR p_case_id IS NULL
       OR p_lock_token IS NULL
    THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT c.*
    FROM public.cases AS c
    INNER JOIN public.case_locks AS l
        ON l.case_id = c.id
       AND l.organisation_id = c.organisation_id
    WHERE c.id = p_case_id
      AND c.organisation_id = v_organisation_id
      AND l.locked_by_user_id = v_employee_id
      AND l.lock_token = p_lock_token
      AND l.expires_at > NOW()
      AND public.can_work_on_case(c.id);
END;
$function$;


-- Protected operation 02:
-- Save/claim requires current team-work permission.
-- Existing lock lifecycle, reassignment checks and auditing remain unchanged.

CREATE OR REPLACE FUNCTION public.save_employee_case_assignment(
    p_case_id uuid,
    p_lock_token uuid,
    p_expected_assigned_user_id uuid DEFAULT NULL,
    p_confirm_reassignment boolean DEFAULT FALSE
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
    v_lock public.case_locks%ROWTYPE;
    v_current_assignee uuid;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required'
            USING ERRCODE = '42501';
    END IF;

    IF p_case_id IS NULL OR p_lock_token IS NULL THEN
        RAISE EXCEPTION 'Valid case and lock token required'
            USING ERRCODE = '42501';
    END IF;

    -- Reuse the existing exclusive lock; do not modify its lifecycle.
    SELECT l.*
    INTO v_lock
    FROM public.case_locks AS l
    WHERE l.case_id = p_case_id
      AND l.organisation_id = v_organisation_id
    FOR UPDATE;

    IF NOT FOUND
       OR v_lock.locked_by_user_id IS DISTINCT FROM v_employee_id
       OR v_lock.lock_token IS DISTINCT FROM p_lock_token
       OR v_lock.expires_at <= clock_timestamp()
    THEN
        RAISE EXCEPTION 'Case lock invalid, expired, or not owned by employee'
            USING ERRCODE = '42501';
    END IF;

    -- Revalidate current team-work permission after lock validation.
    -- Revocation must take effect even while the lock remains active.
    IF public.can_work_on_case(p_case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    -- Serialize assignment changes and inspect the current responsibility.
    SELECT c.assigned_user_id
    INTO v_current_assignee
    FROM public.cases AS c
    WHERE c.id = p_case_id
      AND c.organisation_id = v_organisation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Case not found or access denied'
            USING ERRCODE = '42501';
    END IF;

    IF v_current_assignee IS DISTINCT FROM p_expected_assigned_user_id THEN
        RAISE EXCEPTION 'Case assignment changed; refresh before saving'
            USING ERRCODE = '40001';
    END IF;

    IF v_current_assignee IS NOT NULL
       AND v_current_assignee IS DISTINCT FROM v_employee_id
       AND p_confirm_reassignment IS NOT TRUE
    THEN
        RAISE EXCEPTION 'Explicit reassignment confirmation required'
            USING ERRCODE = '42501';
    END IF;

    IF v_lock.expires_at <= clock_timestamp() THEN
        RAISE EXCEPTION 'Case lock expired during save'
            USING ERRCODE = '42501';
    END IF;

    IF v_current_assignee IS DISTINCT FROM v_employee_id THEN
        UPDATE public.cases
        SET assigned_user_id = v_employee_id
        WHERE id = p_case_id
          AND organisation_id = v_organisation_id;
        -- The existing audit trigger records the assignment change.
    END IF;

    RETURN p_case_id;
END;
$function$;


-- Protected operation 03:
-- Controlled case updates require current team-work permission.
-- Team transfer and destination-team removal are deferred to
-- a separately authorised workflow.
-- Existing lock, status, priority, employee assignment and audit
-- behaviour is otherwise preserved.

CREATE OR REPLACE FUNCTION public.update_employee_case(
    p_case_id uuid,
    p_lock_token uuid,
    p_status text DEFAULT NULL,
    p_priority text DEFAULT NULL,
    p_assigned_team_id uuid DEFAULT NULL,
    p_assigned_user_id uuid DEFAULT NULL,
    p_clear_team boolean DEFAULT FALSE,
    p_clear_user boolean DEFAULT FALSE
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
    v_lock public.case_locks%ROWTYPE;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required'
            USING ERRCODE = '42501';
    END IF;

    IF p_case_id IS NULL OR p_lock_token IS NULL THEN
        RAISE EXCEPTION 'Valid case and lock token required'
            USING ERRCODE = '42501';
    END IF;

    IF (p_clear_team AND p_assigned_team_id IS NOT NULL)
       OR (p_clear_user AND p_assigned_user_id IS NOT NULL)
    THEN
        RAISE EXCEPTION 'Cannot assign and clear the same field'
            USING ERRCODE = '22023';
    END IF;

    -- Lock the lock record for this transaction.
    SELECT l.*
    INTO v_lock
    FROM public.case_locks AS l
    WHERE l.case_id = p_case_id
      AND l.organisation_id = v_organisation_id
    FOR UPDATE;

    IF NOT FOUND
       OR v_lock.locked_by_user_id IS DISTINCT FROM v_employee_id
       OR v_lock.lock_token IS DISTINCT FROM p_lock_token
       OR v_lock.expires_at <= clock_timestamp()
    THEN
        RAISE EXCEPTION 'Case lock invalid, expired, or not owned by employee'
            USING ERRCODE = '42501';
    END IF;

    -- Require current work permission, not merely an existing lock.
    IF public.can_work_on_case(p_case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    -- Team transfers require a separate authorised workflow.
    -- Never allow this general-purpose RPC to remove the destination team.
    IF p_clear_team IS TRUE THEN
        RAISE EXCEPTION 'Clearing destination team is not permitted'
            USING ERRCODE = '42501';
    END IF;

    IF p_assigned_team_id IS NOT NULL
       AND p_assigned_team_id IS DISTINCT FROM (
           SELECT c.assigned_team_id
           FROM public.cases AS c
           WHERE c.id = p_case_id
             AND c.organisation_id = v_organisation_id
       )
    THEN
        RAISE EXCEPTION 'Team transfer requires separate authorisation'
            USING ERRCODE = '42501';
    END IF;

    UPDATE public.cases AS c
    SET
        status = COALESCE(p_status, c.status),
        priority = COALESCE(p_priority, c.priority),
        assigned_team_id = CASE
            WHEN p_clear_team THEN NULL
            ELSE COALESCE(p_assigned_team_id, c.assigned_team_id)
        END,
        assigned_user_id = CASE
            WHEN p_clear_user THEN NULL
            ELSE COALESCE(p_assigned_user_id, c.assigned_user_id)
        END
    WHERE c.id = p_case_id
      AND c.organisation_id = v_organisation_id
      AND v_lock.expires_at > clock_timestamp();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Case not found or access denied'
            USING ERRCODE = '42501';
    END IF;

    RETURN p_case_id;
END;
$function$;


-- Protected operation 04:
-- Internal case comments require current team-work permission.
-- Existing exclusive-lock validation, comment constraints and
-- persistence behaviour are preserved.

CREATE OR REPLACE FUNCTION public.save_employee_case_comment(
    p_case_id uuid,
    p_lock_token uuid,
    p_body text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
    v_lock public.case_locks%ROWTYPE;
    v_comment_id uuid;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required'
            USING ERRCODE = '42501';
    END IF;

    IF p_case_id IS NULL OR p_lock_token IS NULL THEN
        RAISE EXCEPTION 'Valid case and lock token required'
            USING ERRCODE = '42501';
    END IF;

    IF p_body IS NULL
       OR length(btrim(p_body)) = 0
       OR length(p_body) > 10000
    THEN
        RAISE EXCEPTION 'Comment must contain 1 to 10000 characters'
            USING ERRCODE = '22023';
    END IF;

    SELECT l.*
    INTO v_lock
    FROM public.case_locks AS l
    WHERE l.case_id = p_case_id
      AND l.organisation_id = v_organisation_id
    FOR UPDATE;

    IF NOT FOUND
       OR v_lock.locked_by_user_id IS DISTINCT FROM v_employee_id
       OR v_lock.lock_token IS DISTINCT FROM p_lock_token
       OR v_lock.expires_at <= clock_timestamp()
    THEN
        RAISE EXCEPTION 'Case lock invalid, expired, or not owned by employee'
            USING ERRCODE = '42501';
    END IF;

    -- A valid existing lock does not override revoked work permission.
    IF public.can_work_on_case(p_case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    PERFORM 1
    FROM public.cases AS c
    WHERE c.id = p_case_id
      AND c.organisation_id = v_organisation_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Case not found or access denied'
            USING ERRCODE = '42501';
    END IF;

    IF v_lock.expires_at <= clock_timestamp() THEN
        RAISE EXCEPTION 'Case lock expired during save'
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.comments (
        case_id,
        organisation_id,
        author_user_id,
        body,
        visibility
    )
    VALUES (
        p_case_id,
        v_organisation_id,
        v_employee_id,
        btrim(p_body),
        'internal'
    )
    RETURNING id INTO v_comment_id;

    RETURN v_comment_id;
END;
$function$;


-- Protected operation 05:
-- Internal comment retrieval requires current team-work permission.
-- Preserve the original result structure, organisation isolation,
-- exclusive-lock validation and chronological ordering.

CREATE OR REPLACE FUNCTION public.get_employee_case_comments(
    p_case_id uuid,
    p_lock_token uuid
)
RETURNS TABLE (
    id uuid,
    body text,
    created_at timestamptz,
    author_user_id uuid,
    author_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required'
            USING ERRCODE = '42501';
    END IF;

    IF p_case_id IS NULL OR p_lock_token IS NULL THEN
        RAISE EXCEPTION 'Valid case and lock token required'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases AS c
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
    ) THEN
        RAISE EXCEPTION 'Case not found or access denied'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks AS l
        WHERE l.case_id = p_case_id
          AND l.organisation_id = v_organisation_id
          AND l.locked_by_user_id = v_employee_id
          AND l.lock_token = p_lock_token
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'Case lock invalid, expired, or not owned by employee'
            USING ERRCODE = '42501';
    END IF;

    -- Existing lock ownership does not override revoked work access.
    IF public.can_work_on_case(p_case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        cm.id,
        cm.body,
        cm.created_at,
        cm.author_user_id,
        COALESCE(u.full_name::text, 'Unknown employee') AS author_name
    FROM public.comments AS cm
    LEFT JOIN public.users AS u
      ON u.id = cm.author_user_id
     AND u.organisation_id = cm.organisation_id
    WHERE cm.case_id = p_case_id
      AND cm.organisation_id = v_organisation_id
      AND cm.visibility = 'internal'
    ORDER BY cm.created_at ASC, cm.id ASC;
END;
$function$;


-- Protected operation 06:
-- Audit-history retrieval requires current team-work permission.
-- Preserve existing lock validation, tenant isolation, event attribution,
-- twelve-column return structure and reverse-chronological ordering.

CREATE OR REPLACE FUNCTION public.get_employee_case_audit_history(
    p_case_id uuid,
    p_lock_token uuid
)
RETURNS TABLE (
    id uuid,
    event_type text,
    created_at timestamptz,
    actor_user_id uuid,
    actor_name text,
    from_status text,
    to_status text,
    from_team_name text,
    to_team_name text,
    from_user_name text,
    to_user_name text,
    details text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required'
            USING ERRCODE = '42501';
    END IF;

    IF p_case_id IS NULL OR p_lock_token IS NULL THEN
        RAISE EXCEPTION 'Valid case and lock token required'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases AS c
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
    ) THEN
        RAISE EXCEPTION 'Case not found or access denied'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.case_locks AS l
        WHERE l.case_id = p_case_id
          AND l.organisation_id = v_organisation_id
          AND l.locked_by_user_id = v_employee_id
          AND l.lock_token = p_lock_token
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'Case lock invalid, expired, or not owned by employee'
            USING ERRCODE = '42501';
    END IF;

    -- Existing lock ownership does not override revoked work access.
    IF public.can_work_on_case(p_case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        ev.id,
        ev.event_type::text,
        ev.created_at,
        ev.actor_user_id,
        COALESCE(actor.full_name::text, 'System / unknown') AS actor_name,
        ev.from_status::text,
        ev.to_status::text,
        previous_team.name::text AS from_team_name,
        next_team.name::text AS to_team_name,
        previous_user.full_name::text AS from_user_name,
        next_user.full_name::text AS to_user_name,
        ev.details
    FROM public.case_events AS ev
    LEFT JOIN public.users AS actor
      ON actor.id = ev.actor_user_id
     AND actor.organisation_id = ev.organisation_id
    LEFT JOIN public.teams AS previous_team
      ON previous_team.id = ev.from_team_id
     AND previous_team.organisation_id = ev.organisation_id
    LEFT JOIN public.teams AS next_team
      ON next_team.id = ev.to_team_id
     AND next_team.organisation_id = ev.organisation_id
    LEFT JOIN public.users AS previous_user
      ON previous_user.id = ev.from_user_id
     AND previous_user.organisation_id = ev.organisation_id
    LEFT JOIN public.users AS next_user
      ON next_user.id = ev.to_user_id
     AND next_user.organisation_id = ev.organisation_id
    WHERE ev.case_id = p_case_id
      AND ev.organisation_id = v_organisation_id
    ORDER BY ev.created_at DESC, ev.id DESC;
END;
$function$;


-- Protected operation 07:
-- Evidence metadata retrieval requires current team-work permission.
-- Preserve existing tenant isolation, exclusive-lock validation,
-- eight-column response, internal-only filtering and ordering.

CREATE OR REPLACE FUNCTION public.get_employee_case_evidence(
    p_case_id uuid,
    p_lock_token uuid
)
RETURNS TABLE (
    id uuid,
    comment_id uuid,
    file_name text,
    file_type text,
    file_size_bytes bigint,
    created_at timestamptz,
    uploaded_by_user_id uuid,
    uploaded_by_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL
       OR v_organisation_id IS NULL
       OR p_case_id IS NULL
       OR p_lock_token IS NULL
    THEN
        RAISE EXCEPTION 'Authenticated employee and case lock required'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases AS c
        JOIN public.case_locks AS l
          ON l.case_id = c.id
         AND l.organisation_id = c.organisation_id
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
          AND l.locked_by_user_id = v_employee_id
          AND l.lock_token = p_lock_token
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'Case access denied or lock expired'
            USING ERRCODE = '42501';
    END IF;

    -- Existing lock ownership does not override revoked work access.
    IF public.can_work_on_case(p_case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        a.id,
        a.comment_id,
        a.file_name::text,
        a.file_type::text,
        a.file_size_bytes,
        a.created_at,
        a.uploaded_by_user_id,
        COALESCE(u.full_name::text, 'Unknown employee')
    FROM public.attachments AS a
    LEFT JOIN public.users AS u
      ON u.id = a.uploaded_by_user_id
     AND u.organisation_id = a.organisation_id
    WHERE a.case_id = p_case_id
      AND a.organisation_id = v_organisation_id
      AND a.visibility = 'internal'
    ORDER BY a.created_at ASC, a.id ASC;
END;
$function$;


-- Protected operation 08:
-- Evidence download-path retrieval requires current team-work permission.
-- Preserve existing tenant isolation, lock ownership, internal attachment
-- validation and completed-reservation requirements.

CREATE OR REPLACE FUNCTION public.get_employee_case_evidence_download_path(
    p_attachment_id uuid,
    p_case_id uuid,
    p_lock_token uuid
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
    v_storage_path text;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL
       OR v_organisation_id IS NULL
       OR p_attachment_id IS NULL
       OR p_case_id IS NULL
       OR p_lock_token IS NULL
    THEN
        RAISE EXCEPTION 'Authenticated employee and case lock required'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases AS c
        JOIN public.case_locks AS l
          ON l.case_id = c.id
         AND l.organisation_id = c.organisation_id
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
          AND l.locked_by_user_id = v_employee_id
          AND l.lock_token = p_lock_token
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'Case access denied or lock expired'
            USING ERRCODE = '42501';
    END IF;

    -- Existing lock ownership does not override revoked work access.
    IF public.can_work_on_case(p_case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    SELECT a.storage_reference
    INTO v_storage_path
    FROM public.attachments AS a
    JOIN public.case_evidence_upload_reservations AS r
      ON r.storage_path = a.storage_reference
     AND r.case_id = a.case_id
     AND r.organisation_id = a.organisation_id
    WHERE a.id = p_attachment_id
      AND a.case_id = p_case_id
      AND a.organisation_id = v_organisation_id
      AND a.visibility = 'internal'
      AND r.status = 'completed';

    IF v_storage_path IS NULL THEN
        RAISE EXCEPTION 'Evidence attachment not found'
            USING ERRCODE = '42501';
    END IF;

    RETURN v_storage_path;
END;
$function$;


-- Protected operation 09:
-- Evidence upload preparation requires current team-work permission.
-- Preserve original lock ownership, file validation, tenant isolation,
-- pending-reservation overlap prevention and Storage path generation.

CREATE OR REPLACE FUNCTION public.prepare_case_evidence_upload(
    p_case_id uuid,
    p_lock_token uuid,
    p_file_name text,
    p_file_type text,
    p_file_size_bytes bigint
)
RETURNS TABLE (
    reservation_id uuid,
    storage_path text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
    v_lock public.case_locks%ROWTYPE;
    v_reservation_id uuid;
    v_storage_path text;
    v_file_name text;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required'
            USING ERRCODE = '42501';
    END IF;

    IF p_case_id IS NULL OR p_lock_token IS NULL THEN
        RAISE EXCEPTION 'Valid case and lock token required'
            USING ERRCODE = '42501';
    END IF;

    v_file_name := btrim(p_file_name);

    IF v_file_name IS NULL
       OR length(v_file_name) = 0
       OR length(v_file_name) > 255
       OR v_file_name ~ '[/\\]'
       OR v_file_name ~ '[[:cntrl:]]'
    THEN
        RAISE EXCEPTION 'Invalid evidence file name'
            USING ERRCODE = '22023';
    END IF;

    IF p_file_type IS NULL
       OR p_file_type NOT IN (
           'application/pdf',
           'image/jpeg',
           'image/png'
       )
    THEN
        RAISE EXCEPTION 'Unsupported evidence file type'
            USING ERRCODE = '22023';
    END IF;

    IF p_file_size_bytes IS NULL
       OR p_file_size_bytes < 1
       OR p_file_size_bytes > 10485760
    THEN
        RAISE EXCEPTION 'Evidence file exceeds permitted size'
            USING ERRCODE = '22023';
    END IF;

    SELECT l.*
    INTO v_lock
    FROM public.case_locks AS l
    WHERE l.case_id = p_case_id
      AND l.organisation_id = v_organisation_id
    FOR UPDATE;

    IF NOT FOUND
       OR v_lock.locked_by_user_id IS DISTINCT FROM v_employee_id
       OR v_lock.lock_token IS DISTINCT FROM p_lock_token
       OR v_lock.expires_at <= clock_timestamp()
    THEN
        RAISE EXCEPTION 'Case lock invalid, expired, or not owned by employee'
            USING ERRCODE = '42501';
    END IF;

    PERFORM 1
    FROM public.cases AS c
    WHERE c.id = p_case_id
      AND c.organisation_id = v_organisation_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Case not found or access denied'
            USING ERRCODE = '42501';
    END IF;

    -- A valid existing lock does not override revoked team-work access.
    IF public.can_work_on_case(p_case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    -- The case-lock row is already locked FOR UPDATE above.
    -- Serialise reservation creation and reject unresolved uploads.
    IF EXISTS (
        SELECT 1
        FROM public.case_evidence_upload_reservations AS r
        WHERE r.case_id = p_case_id
          AND r.organisation_id = v_organisation_id
          AND r.employee_id = v_employee_id
          AND r.status = 'pending'
    ) THEN
        RAISE EXCEPTION
            'An earlier evidence upload requires recovery review'
            USING ERRCODE = '23505';
    END IF;

    v_reservation_id := gen_random_uuid();

    v_storage_path :=
        v_organisation_id::text || '/' ||
        p_case_id::text || '/' ||
        v_reservation_id::text;

    INSERT INTO public.case_evidence_upload_reservations (
        id,
        case_id,
        organisation_id,
        employee_id,
        storage_path,
        file_name,
        file_type,
        file_size_bytes,
        expires_at
    )
    VALUES (
        v_reservation_id,
        p_case_id,
        v_organisation_id,
        v_employee_id,
        v_storage_path,
        v_file_name,
        p_file_type,
        p_file_size_bytes,
        clock_timestamp() + interval '10 minutes'
    );

    RETURN QUERY
    SELECT v_reservation_id, v_storage_path;
END;
$function$;


-- Protected operation 10:
-- Evidence finalisation requires current team-work permission.
-- Preserve reservation ownership, exclusive-lock validation,
-- Storage metadata verification, attachment creation, audit events
-- and reservation completion.

CREATE OR REPLACE FUNCTION public.finalise_case_evidence_upload(
    p_reservation_id uuid,
    p_lock_token uuid,
    p_comment_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
    v_reservation public.case_evidence_upload_reservations%ROWTYPE;
    v_lock public.case_locks%ROWTYPE;
    v_object storage.objects%ROWTYPE;
    v_attachment_id uuid;
    v_actual_size bigint;
    v_actual_type text;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL OR v_organisation_id IS NULL THEN
        RAISE EXCEPTION 'Authenticated active employee required'
            USING ERRCODE = '42501';
    END IF;

    SELECT r.*
    INTO v_reservation
    FROM public.case_evidence_upload_reservations AS r
    WHERE r.id = p_reservation_id
      AND r.employee_id = v_employee_id
      AND r.organisation_id = v_organisation_id
      AND r.status = 'pending'
    FOR UPDATE;

    IF NOT FOUND
       OR v_reservation.expires_at <= clock_timestamp()
    THEN
        RAISE EXCEPTION 'Upload reservation invalid or expired'
            USING ERRCODE = '42501';
    END IF;

    SELECT l.*
    INTO v_lock
    FROM public.case_locks AS l
    WHERE l.case_id = v_reservation.case_id
      AND l.organisation_id = v_organisation_id
    FOR UPDATE;

    IF NOT FOUND
       OR v_lock.locked_by_user_id IS DISTINCT FROM v_employee_id
       OR v_lock.lock_token IS DISTINCT FROM p_lock_token
       OR v_lock.expires_at <= clock_timestamp()
    THEN
        RAISE EXCEPTION 'Valid exclusive case lock required'
            USING ERRCODE = '42501';
    END IF;

    -- A valid reservation and exclusive lock do not override
    -- revoked team-work permission.
    IF public.can_work_on_case(v_reservation.case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    IF p_comment_id IS NOT NULL THEN
        PERFORM 1
        FROM public.comments AS c
        WHERE c.id = p_comment_id
          AND c.case_id = v_reservation.case_id
          AND c.organisation_id = v_organisation_id
          AND c.visibility = 'internal';

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Activity not found in this case'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    SELECT o.*
    INTO v_object
    FROM storage.objects AS o
    WHERE o.bucket_id = 'case-evidence'
      AND o.name = v_reservation.storage_path
      AND o.archived_at IS NULL
      AND o.is_delete_marker IS DISTINCT FROM true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Uploaded evidence object not found'
            USING ERRCODE = '22023';
    END IF;

    IF v_object.metadata->>'size' IS NULL
       OR (v_object.metadata->>'size') !~ '^[0-9]+$'
    THEN
        RAISE EXCEPTION 'Uploaded evidence size metadata missing'
            USING ERRCODE = '22023';
    END IF;

    v_actual_size := (v_object.metadata->>'size')::bigint;
    v_actual_type := v_object.metadata->>'mimetype';

    IF v_actual_size <> v_reservation.file_size_bytes
       OR v_actual_type IS DISTINCT FROM v_reservation.file_type
    THEN
        RAISE EXCEPTION 'Uploaded evidence metadata does not match reservation'
            USING ERRCODE = '22023';
    END IF;

    IF v_lock.expires_at <= clock_timestamp() THEN
        RAISE EXCEPTION 'Case lock expired during finalisation'
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.attachments (
        case_id,
        organisation_id,
        uploaded_by_user_id,
        file_name,
        file_type,
        file_size_bytes,
        storage_reference,
        visibility,
        comment_id
    )
    VALUES (
        v_reservation.case_id,
        v_organisation_id,
        v_employee_id,
        v_reservation.file_name,
        v_reservation.file_type,
        v_actual_size,
        v_reservation.storage_path,
        'internal',
        p_comment_id
    )
    RETURNING id INTO v_attachment_id;

    INSERT INTO public.case_events (
        case_id,
        organisation_id,
        actor_user_id,
        event_type,
        details
    )
    VALUES (
        v_reservation.case_id,
        v_organisation_id,
        v_employee_id,
        'evidence_uploaded',
        'Attachment ID: ' || v_attachment_id::text
    );

    UPDATE public.case_evidence_upload_reservations
    SET
        status = 'completed',
        completed_at = clock_timestamp()
    WHERE id = v_reservation.id;

    RETURN v_attachment_id;
END;
$function$;

-- Require current team-work permission for Storage access.
CREATE OR REPLACE FUNCTION public.can_upload_reserved_case_evidence(
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
          AND public.can_work_on_case(r.case_id) IS TRUE
    );
$function$;

-- Require current team-work permission for Storage access.
CREATE OR REPLACE FUNCTION public.can_download_locked_case_evidence(
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
          AND public.can_work_on_case(a.case_id) IS TRUE
    );
$function$;


-- Protected operation 11:
-- Evidence upload recovery status requires current team-work permission.
-- Preserve original identity, organisation, lock, reservation ownership,
-- recovery status and attachment-integrity validation.

CREATE OR REPLACE FUNCTION public.get_case_evidence_upload_recovery_status(
    p_reservation_id uuid,
    p_case_id uuid,
    p_lock_token uuid
)
RETURNS TABLE (
    reservation_status text,
    attachment_id uuid
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
    v_reservation public.case_evidence_upload_reservations%ROWTYPE;
    v_attachment_id uuid;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL
        OR v_organisation_id IS NULL
        OR p_reservation_id IS NULL
        OR p_case_id IS NULL
        OR p_lock_token IS NULL
    THEN
        RAISE EXCEPTION 'Authenticated employee and case lock required'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases AS c
        JOIN public.case_locks AS l
          ON l.case_id = c.id
         AND l.organisation_id = c.organisation_id
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
          AND l.locked_by_user_id = v_employee_id
          AND l.lock_token = p_lock_token
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'Case access denied or lock expired'
            USING ERRCODE = '42501';
    END IF;

    -- An existing exclusive lock does not override revoked team-work access.
    IF public.can_work_on_case(p_case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    SELECT r.*
    INTO v_reservation
    FROM public.case_evidence_upload_reservations AS r
    WHERE r.id = p_reservation_id
      AND r.case_id = p_case_id
      AND r.organisation_id = v_organisation_id
      AND r.employee_id = v_employee_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Evidence reservation not found'
            USING ERRCODE = '42501';
    END IF;

    IF v_reservation.status = 'completed' THEN
        SELECT a.id
        INTO v_attachment_id
        FROM public.attachments AS a
        WHERE a.storage_reference = v_reservation.storage_path
          AND a.case_id = p_case_id
          AND a.organisation_id = v_organisation_id
          AND a.uploaded_by_user_id = v_employee_id
          AND a.visibility = 'internal'
        ORDER BY a.created_at ASC, a.id ASC
        LIMIT 1;

        IF v_attachment_id IS NULL THEN
            RAISE EXCEPTION 'Completed reservation missing attachment'
                USING ERRCODE = '22023';
        END IF;

        RETURN QUERY SELECT 'completed'::text, v_attachment_id;

    ELSIF v_reservation.status = 'expired'
        OR v_reservation.expires_at <= clock_timestamp()
    THEN
        RETURN QUERY SELECT 'expired'::text, NULL::uuid;

    ELSE
        RETURN QUERY SELECT 'pending'::text, NULL::uuid;
    END IF;
END;
$function$;


-- Protected operation 12:
-- Evidence upload reservation listing requires current team-work
-- permission in addition to the existing identity, organisation,
-- exclusive-lock and reservation-ownership checks.

CREATE OR REPLACE FUNCTION public.list_employee_case_evidence_upload_reservations(
    p_case_id uuid,
    p_lock_token uuid
)
RETURNS TABLE (
    reservation_id uuid,
    file_name text,
    reservation_status text,
    created_at timestamptz,
    expires_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_employee_id uuid;
    v_organisation_id uuid;
BEGIN
    v_employee_id := public.current_employee_id();
    v_organisation_id := public.current_user_organisation_id();

    IF v_employee_id IS NULL
        OR v_organisation_id IS NULL
        OR p_case_id IS NULL
        OR p_lock_token IS NULL
    THEN
        RAISE EXCEPTION 'Authenticated employee and case lock required'
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.cases AS c
        JOIN public.case_locks AS l
          ON l.case_id = c.id
         AND l.organisation_id = c.organisation_id
        WHERE c.id = p_case_id
          AND c.organisation_id = v_organisation_id
          AND l.locked_by_user_id = v_employee_id
          AND l.lock_token = p_lock_token
          AND l.expires_at > clock_timestamp()
    ) THEN
        RAISE EXCEPTION 'Case access denied or lock expired'
            USING ERRCODE = '42501';
    END IF;

    -- A valid lock never overrides revoked team-work permission.
    IF public.can_work_on_case(p_case_id) IS NOT TRUE THEN
        RAISE EXCEPTION 'Case work permission required'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        r.id,
        r.file_name::text,
        CASE
            WHEN r.status = 'pending'
                 AND r.expires_at <= clock_timestamp()
            THEN 'expired'::text
            ELSE r.status
        END,
        r.created_at,
        r.expires_at
    FROM public.case_evidence_upload_reservations AS r
    WHERE r.case_id = p_case_id
      AND r.organisation_id = v_organisation_id
      AND r.employee_id = v_employee_id
    ORDER BY r.created_at DESC, r.id DESC;
END;
$function$;

REVOKE ALL ON FUNCTION
    public.list_employee_case_evidence_upload_reservations(uuid, uuid)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
    public.list_employee_case_evidence_upload_reservations(uuid, uuid)
TO authenticated;


-- Protected operation 13:
-- Active case-lock visibility follows operational queue authorisation.
-- Multi-team access requires explicit work permission for each team.
-- No implicit manager or organisation-administrator bypass.

CREATE OR REPLACE FUNCTION public.get_active_case_locks()
RETURNS TABLE (
    case_id UUID,
    employee_name VARCHAR,
    lock_expires_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
    SELECT
        l.case_id,
        u.full_name AS employee_name,
        l.expires_at AS lock_expires_at
    FROM public.case_locks AS l
    INNER JOIN public.cases AS c
        ON c.id = l.case_id
       AND c.organisation_id = l.organisation_id
    INNER JOIN public.users AS u
        ON u.id = l.locked_by_user_id
       AND u.organisation_id = l.organisation_id
    WHERE l.organisation_id = public.current_user_organisation_id()
      AND l.expires_at > NOW()
      AND u.is_active = TRUE
      AND public.can_work_on_case(c.id) IS TRUE;
$function$;

REVOKE ALL ON FUNCTION public.get_active_case_locks()
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_active_case_locks()
TO authenticated, service_role;
