-- Migration 040: Organisation-specific customer and case references.
-- Internal UUID primary keys remain unchanged.
-- Do not execute until reviewed and tested.

BEGIN;

-- Prevent concurrent customer/case writes during historical backfill.
-- These locks are held until COMMIT or ROLLBACK.
LOCK TABLE public.customers, public.cases
    IN ACCESS EXCLUSIVE MODE;

-- Private numbering state. Not exposed through the public API.
CREATE SCHEMA IF NOT EXISTS madzera_internal;

REVOKE ALL ON SCHEMA madzera_internal FROM PUBLIC;
REVOKE ALL ON SCHEMA madzera_internal FROM anon, authenticated;

-- Explicitly restrict this internal schema to trusted database roles.
-- Trigger functions remain executable through their owning triggers,
-- not through direct application RPC calls.

CREATE TABLE madzera_internal.reference_counters (
    organisation_id uuid NOT NULL
        REFERENCES public.organisations(id),
    reference_kind text NOT NULL,
    reference_year integer NOT NULL,
    last_number bigint NOT NULL DEFAULT 0,
    CONSTRAINT reference_counters_pkey
        PRIMARY KEY (
            organisation_id,
            reference_kind,
            reference_year
        ),
    CONSTRAINT reference_counters_kind_check
        CHECK (reference_kind IN ('customer', 'case')),
    CONSTRAINT reference_counters_number_check
        CHECK (last_number >= 0),
    CONSTRAINT reference_counters_year_check
        CHECK (
            (reference_kind = 'customer' AND reference_year = 0)
            OR
            (reference_kind = 'case' AND reference_year BETWEEN 2000 AND 9999)
        )
);

REVOKE ALL ON TABLE madzera_internal.reference_counters
FROM PUBLIC, anon, authenticated;

ALTER TABLE public.customers
    ADD COLUMN customer_reference text;

ALTER TABLE public.cases
    ADD COLUMN case_reference text;

CREATE UNIQUE INDEX uq_customers_organisation_reference
ON public.customers (organisation_id, customer_reference);

CREATE UNIQUE INDEX uq_cases_organisation_reference
ON public.cases (organisation_id, case_reference);

-- Allocate the next reference number atomically.
CREATE FUNCTION madzera_internal.next_reference_number(
    p_organisation_id uuid,
    p_kind text,
    p_year integer
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_number bigint;
BEGIN
    IF p_organisation_id IS NULL
       OR p_kind NOT IN ('customer', 'case')
       OR p_year IS NULL
       OR (p_kind = 'customer' AND p_year <> 0)
       OR (p_kind = 'case' AND p_year NOT BETWEEN 2000 AND 9999)
    THEN
        RAISE EXCEPTION 'Invalid reference allocation request'
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO madzera_internal.reference_counters (
        organisation_id,
        reference_kind,
        reference_year,
        last_number
    )
    VALUES (
        p_organisation_id,
        p_kind,
        p_year,
        1
    )
    ON CONFLICT (
        organisation_id,
        reference_kind,
        reference_year
    )
    DO UPDATE
    SET last_number =
        madzera_internal.reference_counters.last_number + 1
    RETURNING last_number INTO v_number;

    IF v_number > 999999 THEN
        RAISE EXCEPTION 'Reference number capacity exceeded'
            USING ERRCODE = '22003';
    END IF;

    RETURN v_number;
END;
$function$;

REVOKE ALL ON FUNCTION madzera_internal.next_reference_number(
    uuid, text, integer
) FROM PUBLIC, anon, authenticated;

-- Generate a customer reference automatically.
CREATE FUNCTION madzera_internal.assign_customer_reference()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_number bigint;
BEGIN
    IF NEW.customer_reference IS NOT NULL THEN
        RAISE EXCEPTION 'Customer reference is database generated'
            USING ERRCODE = '42501';
    END IF;

    v_number := madzera_internal.next_reference_number(
        NEW.organisation_id,
        'customer',
        0
    );

    NEW.customer_reference :=
        'CUS' || lpad(v_number::text, 6, '0');

    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION madzera_internal.assign_customer_reference()
FROM PUBLIC, anon, authenticated;

-- Generate a case reference automatically.
CREATE FUNCTION madzera_internal.assign_case_reference()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_year integer;
    v_number bigint;
BEGIN
    IF NEW.case_reference IS NOT NULL THEN
        RAISE EXCEPTION 'Case reference is database generated'
            USING ERRCODE = '42501';
    END IF;

    IF NEW.created_at IS NULL THEN
        RAISE EXCEPTION 'Case creation timestamp is required'
            USING ERRCODE = '23502';
    END IF;

    v_year := EXTRACT(
        YEAR FROM NEW.created_at AT TIME ZONE 'UTC'
    )::integer;

    v_number := madzera_internal.next_reference_number(
        NEW.organisation_id,
        'case',
        v_year
    );

    NEW.case_reference :=
        'CAS' || v_year::text || lpad(v_number::text, 6, '0');

    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION madzera_internal.assign_case_reference()
FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_assign_customer_reference
BEFORE INSERT ON public.customers
FOR EACH ROW
EXECUTE FUNCTION madzera_internal.assign_customer_reference();

CREATE TRIGGER trg_assign_case_reference
BEFORE INSERT ON public.cases
FOR EACH ROW
EXECUTE FUNCTION madzera_internal.assign_case_reference();

-- Backfill existing customers without changing UUIDs.
-- Existing records are ordered by creation time and UUID.
WITH ordered_customers AS (
    SELECT
        id,
        organisation_id,
        ROW_NUMBER() OVER (
            PARTITION BY organisation_id
            ORDER BY created_at, id
        ) AS sequence_number
    FROM public.customers
)
UPDATE public.customers AS c
SET customer_reference =
    'CUS' || lpad(o.sequence_number::text, 6, '0')
FROM ordered_customers AS o
WHERE c.id = o.id;

-- Migration-only exception:
-- Existing audit logic requires an active employee identity.
-- Historical reference allocation is an administrative operation.
-- The exclusive table lock prevents concurrent application writes.
-- Re-enable the trigger before transaction commit.
ALTER TABLE public.cases
    DISABLE TRIGGER trg_audit_case_update;

-- Backfill existing cases without changing UUIDs.
WITH ordered_cases AS (
    SELECT
        id,
        organisation_id,
        EXTRACT(
            YEAR FROM created_at AT TIME ZONE 'UTC'
        )::integer AS creation_year,
        ROW_NUMBER() OVER (
            PARTITION BY
                organisation_id,
                EXTRACT(YEAR FROM created_at AT TIME ZONE 'UTC')
            ORDER BY created_at, id
        ) AS sequence_number
    FROM public.cases
)
UPDATE public.cases AS c
SET case_reference =
    'CAS' || o.creation_year::text
    || lpad(o.sequence_number::text, 6, '0')
FROM ordered_cases AS o
WHERE c.id = o.id;

-- Restore normal case audit enforcement before proceeding.
ALTER TABLE public.cases
    ENABLE TRIGGER trg_audit_case_update;

-- Initialise counters from the assigned historical references.
INSERT INTO madzera_internal.reference_counters (
    organisation_id,
    reference_kind,
    reference_year,
    last_number
)
SELECT
    organisation_id,
    'customer',
    0,
    COUNT(*)
FROM public.customers
GROUP BY organisation_id;

INSERT INTO madzera_internal.reference_counters (
    organisation_id,
    reference_kind,
    reference_year,
    last_number
)
SELECT
    organisation_id,
    'case',
    EXTRACT(YEAR FROM created_at AT TIME ZONE 'UTC')::integer,
    COUNT(*)
FROM public.cases
GROUP BY
    organisation_id,
    EXTRACT(YEAR FROM created_at AT TIME ZONE 'UTC');

ALTER TABLE public.customers
    ALTER COLUMN customer_reference SET NOT NULL;

ALTER TABLE public.cases
    ALTER COLUMN case_reference SET NOT NULL;

-- Prevent changes to assigned business references.
CREATE FUNCTION madzera_internal.protect_business_references()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
    IF TG_TABLE_NAME = 'customers' THEN
        IF NEW.customer_reference IS DISTINCT FROM OLD.customer_reference
           OR NEW.organisation_id IS DISTINCT FROM OLD.organisation_id
        THEN
            RAISE EXCEPTION 'Protected customer reference cannot be modified'
                USING ERRCODE = '42501';
        END IF;
    ELSIF TG_TABLE_NAME = 'cases' THEN
        IF NEW.case_reference IS DISTINCT FROM OLD.case_reference THEN
            RAISE EXCEPTION 'Protected case reference cannot be modified'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION madzera_internal.protect_business_references()
FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_protect_customer_reference
BEFORE UPDATE ON public.customers
FOR EACH ROW
EXECUTE FUNCTION madzera_internal.protect_business_references();

CREATE TRIGGER trg_protect_case_reference
BEFORE UPDATE ON public.cases
FOR EACH ROW
EXECUTE FUNCTION madzera_internal.protect_business_references();

COMMIT;
