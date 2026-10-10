
-- MADZERA MIGRATION 011
-- Purpose: Standardise case workflow values.
--
-- Verification:
-- 1 legacy priority corrected.
-- 3 of 3 CHECK constraints validated.
--
-- No RLS or application permissions changed.

BEGIN;

-- Standardise legacy priority.
UPDATE public.cases
SET
    priority = 'medium',
    updated_at = NOW()
WHERE priority = 'normal';

-- Approved case statuses.
ALTER TABLE public.cases
ADD CONSTRAINT chk_cases_status
CHECK (
    status IN (
        'open',
        'in_progress',
        'pending_customer',
        'resolved',
        'closed'
    )
);

-- Approved case priorities.
ALTER TABLE public.cases
ADD CONSTRAINT chk_cases_priority
CHECK (
    priority IN (
        'low',
        'medium',
        'high',
        'critical'
    )
);

-- Approved enquiry sources.
ALTER TABLE public.cases
ADD CONSTRAINT chk_cases_source
CHECK (
    source IN (
        'web_chatbot',
        'email',
        'phone',
        'manual'
    )
);

COMMIT;
