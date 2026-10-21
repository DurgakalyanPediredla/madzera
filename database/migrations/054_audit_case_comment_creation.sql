-- Record internal case comments in the audit history.
-- Keep comment creation and audit recording atomic.
-- Preserve the existing comment-saving RPC and case-lock lifecycle.

BEGIN;

CREATE FUNCTION public.audit_case_comment_creation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
    INSERT INTO public.case_events (
        case_id,
        organisation_id,
        actor_user_id,
        event_type,
        details
    )
    VALUES (
        NEW.case_id,
        NEW.organisation_id,
        NEW.author_user_id,
        'comment_added',
        'Comment ID: ' || NEW.id::text
    );

    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.audit_case_comment_creation()
FROM PUBLIC, anon, authenticated;

CREATE TRIGGER audit_case_comment_creation
AFTER INSERT ON public.comments
FOR EACH ROW
EXECUTE FUNCTION public.audit_case_comment_creation();

COMMIT;
