-- MADZERA MIGRATION 028
-- Audit changes to case workflow and information fields.
-- Preserve the verified live trigger and execution permissions.
-- Exclusive lock enforcement requires separate security hardening.

BEGIN;

CREATE OR REPLACE FUNCTION public.audit_case_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_actor_user_id UUID;
BEGIN
    SELECT u.id
    INTO v_actor_user_id
    FROM public.users AS u
    WHERE u.auth_user_id = (SELECT auth.uid())
      AND u.organisation_id = OLD.organisation_id
      AND u.is_active = TRUE;

    IF v_actor_user_id IS NULL THEN
        RAISE EXCEPTION
            'Case update requires an active employee identity'
            USING ERRCODE = '42501';
    END IF;

    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.organisation_id IS DISTINCT FROM OLD.organisation_id
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN
        RAISE EXCEPTION
            'Protected case identifiers cannot be modified'
            USING ERRCODE = '42501';
    END IF;

    NEW.updated_at := NOW();

    IF NEW.status = 'resolved'
       AND OLD.status IS DISTINCT FROM 'resolved'
    THEN
        NEW.resolved_at := NOW();
    ELSIF NEW.status <> 'resolved'
          AND OLD.status = 'resolved'
    THEN
        NEW.resolved_at := NULL;
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status
       OR NEW.priority IS DISTINCT FROM OLD.priority
       OR NEW.assigned_team_id IS DISTINCT FROM OLD.assigned_team_id
       OR NEW.assigned_user_id IS DISTINCT FROM OLD.assigned_user_id
    THEN
        INSERT INTO public.case_events (
            case_id,
            organisation_id,
            actor_user_id,
            event_type,
            from_status,
            to_status,
            from_team_id,
            to_team_id,
            from_user_id,
            to_user_id,
            details
        )
        VALUES (
            OLD.id,
            OLD.organisation_id,
            v_actor_user_id,
            'case_updated',
            OLD.status,
            NEW.status,
            OLD.assigned_team_id,
            NEW.assigned_team_id,
            OLD.assigned_user_id,
            NEW.assigned_user_id,
            jsonb_build_object(
                'old_priority', OLD.priority,
                'new_priority', NEW.priority
            )::text
        );
    END IF;

    IF NEW.case_type IS DISTINCT FROM OLD.case_type
       OR NEW.initiated_by IS DISTINCT FROM OLD.initiated_by
       OR NEW.source IS DISTINCT FROM OLD.source
       OR NEW.title IS DISTINCT FROM OLD.title
       OR NEW.description IS DISTINCT FROM OLD.description
    THEN
        INSERT INTO public.case_events (
            case_id,
            organisation_id,
            actor_user_id,
            event_type,
            details
        )
        VALUES (
            OLD.id,
            OLD.organisation_id,
            v_actor_user_id,
            'case_information_updated',
            jsonb_build_object(
                'previous', jsonb_build_object(
                    'case_type', OLD.case_type,
                    'initiated_by', OLD.initiated_by,
                    'source', OLD.source,
                    'title', OLD.title,
                    'description', OLD.description
                ),
                'new', jsonb_build_object(
                    'case_type', NEW.case_type,
                    'initiated_by', NEW.initiated_by,
                    'source', NEW.source,
                    'title', NEW.title,
                    'description', NEW.description
                )
            )::text
        );
    END IF;

    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.audit_case_update()
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.audit_case_update()
TO service_role, postgres;

DROP TRIGGER IF EXISTS trg_audit_case_update ON public.cases;

CREATE TRIGGER trg_audit_case_update
BEFORE UPDATE ON public.cases
FOR EACH ROW
EXECUTE FUNCTION public.audit_case_update();

COMMIT;
