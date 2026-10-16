-- Local security-test fixtures only.
-- Never execute against hosted Supabase.
-- Execute only through the verified local Docker database.

BEGIN;

DO $$
BEGIN
    IF current_database() <> 'postgres'
       OR inet_server_port() <> 5432 THEN
        RAISE EXCEPTION 'Unexpected database environment';
    END IF;
END;
$$;

INSERT INTO public.organisations (id, name)
VALUES
    (
        '0a316877-23d4-4dc3-b0ed-350208d68fb3',
        'Madzera Test Customs A'
    ),
    (
        'cbd6a8ae-adf3-4099-9352-1862e1751dea',
        'Madzera Test Customs B'
    )
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
    IF (
        SELECT count(*)
        FROM public.organisations
        WHERE
            (id = '0a316877-23d4-4dc3-b0ed-350208d68fb3'
             AND name = 'Madzera Test Customs A')
            OR
            (id = 'cbd6a8ae-adf3-4099-9352-1862e1751dea'
             AND name = 'Madzera Test Customs B')
    ) <> 2 THEN
        RAISE EXCEPTION 'Organisation fixture mismatch';
    END IF;
END;
$$;

COMMIT;
