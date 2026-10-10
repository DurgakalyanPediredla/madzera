
-- MADZERA MIGRATION 014
-- Purpose: Automatically audit employee case updates.
--
-- Verified:
-- Step 113: Trigger installed and enabled.
-- Step 114: Audit event created with correct actor.
-- Step 115: Unlinked employee identity rejected.
-- Step 119: Audit event created under authenticated UPDATE.
--
-- No employee UPDATE privileges granted here.

BEGIN;

CREATE OR REPLACE FUNCTION public.audit_case_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_actor_user_id uuid;
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
            'Case workflow updated; priority: '
                || OLD.priority || ' -> ' || NEW.priority
        );
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.audit_case_update()
FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_audit_case_update
BEFORE UPDATE ON public.cases
FOR EACH ROW
EXECUTE FUNCTION public.audit_case_update();

COMMIT;
