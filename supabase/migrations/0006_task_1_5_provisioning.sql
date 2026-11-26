-- ============================================================
-- TwoFold
-- Migration: 0006_task_1_5_provisioning.sql
-- Purpose: Secure, atomic initial couple provisioning
-- ============================================================

CREATE OR REPLACE FUNCTION public.provision_initial_couple(
    p_owner_user_id uuid,
    p_partner_user_id uuid,
    p_owner_display_name text,
    p_partner_display_name text,
    p_space_name text DEFAULT 'TwoFold',
    p_anniversary_date date DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    v_couple_id uuid;
BEGIN

    -- 1. Validate user IDs
    IF p_owner_user_id IS NULL OR p_partner_user_id IS NULL THEN
        RAISE EXCEPTION
            USING ERRCODE = '22023',
                  MESSAGE = 'Both user IDs are required.';
    END IF;

    IF p_owner_user_id = p_partner_user_id THEN
        RAISE EXCEPTION
            USING ERRCODE = '22023',
                  MESSAGE = 'Owner and partner must be different users.';
    END IF;

    -- 2. Validate display names
    IF p_owner_display_name IS NULL
       OR pg_catalog.char_length(pg_catalog.btrim(p_owner_display_name))
          NOT BETWEEN 1 AND 80 THEN
        RAISE EXCEPTION
            USING ERRCODE = '22023',
                  MESSAGE = 'Owner display name must contain 1-80 characters.';
    END IF;

    IF p_partner_display_name IS NULL
       OR pg_catalog.char_length(pg_catalog.btrim(p_partner_display_name))
          NOT BETWEEN 1 AND 80 THEN
        RAISE EXCEPTION
            USING ERRCODE = '22023',
                  MESSAGE = 'Partner display name must contain 1-80 characters.';
    END IF;

    -- 3. Validate couple space name
    IF p_space_name IS NULL
       OR pg_catalog.char_length(pg_catalog.btrim(p_space_name))
          NOT BETWEEN 1 AND 100 THEN
        RAISE EXCEPTION
            USING ERRCODE = '22023',
                  MESSAGE = 'Space name must contain 1-100 characters.';
    END IF;

    -- 4. Create the couple
    INSERT INTO public.couples (
        space_name,
        anniversary_date
    )
    VALUES (
        pg_catalog.btrim(p_space_name),
        p_anniversary_date
    )
    RETURNING id INTO v_couple_id;

    -- 5. Create both profiles
    INSERT INTO public.profiles (
        id,
        display_name
    )
    VALUES
        (p_owner_user_id, pg_catalog.btrim(p_owner_display_name)),
        (p_partner_user_id, pg_catalog.btrim(p_partner_display_name));

    -- 6. Create both private settings records
    INSERT INTO public.user_private_settings (
        user_id
    )
    VALUES
        (p_owner_user_id),
        (p_partner_user_id);

    -- 7. Create both couple memberships
    INSERT INTO public.couple_members (
        couple_id,
        user_id,
        role
    )
    VALUES
        (v_couple_id, p_owner_user_id, 'owner'),
        (v_couple_id, p_partner_user_id, 'partner');

    -- 8. Return the created couple ID
    RETURN v_couple_id;

END;
$function$;

-- Restrict function execution
REVOKE ALL ON FUNCTION public.provision_initial_couple(
    uuid, uuid, text, text, text, date
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.provision_initial_couple(
    uuid, uuid, text, text, text, date
) TO service_role;

-- Document the function
COMMENT ON FUNCTION public.provision_initial_couple(
    uuid, uuid, text, text, text, date
) IS
'Privileged, atomic initial provisioning of the single TwoFold couple space, its two profiles, private settings, and owner/partner memberships.';
