-- =============================================================================
-- ACCORD CRM V1 — FINAL SQL PACKAGE
-- Migration: 010_seed
-- Description: Optional sample data for development/staging environments.
--              Creates ONE pre-provisioned Admin user profile (auth_user_id
--              NULL until they sign up with the matching email — see README
--              for the exact post-migration steps to activate this account)
--              and assigns the Admin role.
--
--              No deals, customers, tasks, or other transactional sample
--              data are seeded — this migration is intentionally minimal so
--              a fresh Supabase project starts with a clean, working RBAC
--              setup and nothing else. Add transactional sample data
--              manually after first login if desired for a staging
--              environment.
--
--              Must run after 001, 002, 003, 004, 005, 006, 007, 008, 009.
-- =============================================================================


-- =============================================================================
-- SEED: Pre-provisioned Admin user profile
-- This INSERT creates the public.users row BEFORE the matching Supabase Auth
-- account exists. auth_user_id is NULL. When this person signs up via
-- Supabase Auth (or is invited) using the SAME email address, the
-- handle_new_auth_user() trigger (001_auth_foundation.sql) automatically
-- links the auth.users row to this pre-provisioned profile by matching on
-- email — see the README "Creating the First Admin Account" section for
-- the exact step-by-step procedure.
--
-- CHANGE THE EMAIL ADDRESS BELOW before running this migration in your own
-- environment. The placeholder below is a clearly-fake example address.
-- =============================================================================
INSERT INTO public.users (full_name, email, is_active)
VALUES ('System Administrator', 'admin@accordtechnologies.example', true)
ON CONFLICT (email) DO NOTHING;


-- =============================================================================
-- SEED: Assign Admin role to the pre-provisioned user
-- assigned_by is left NULL (self-assigned at provisioning time — there is
-- no "assigning admin" yet on a brand-new project).
-- =============================================================================
INSERT INTO public.user_roles (user_id, role_id, assigned_by, is_active)
SELECT
    u.id,
    r.id,
    NULL,
    true
FROM   public.users u
CROSS JOIN public.roles r
WHERE  u.email = 'admin@accordtechnologies.example'
AND    r.name  = 'Admin'
ON CONFLICT (user_id, role_id) DO NOTHING;


-- =============================================================================
-- VERIFICATION HELPER
-- =============================================================================
CREATE OR REPLACE FUNCTION public.verify_seed_data()
RETURNS TABLE (check_name TEXT, passed BOOLEAN, detail TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        'admin_user_provisioned'::TEXT,
        EXISTS (SELECT 1 FROM public.users WHERE email = 'admin@accordtechnologies.example'),
        'Pre-provisioned admin profile exists (auth_user_id will be NULL until first sign-up)'::TEXT;

    RETURN QUERY
    SELECT
        'admin_role_assigned'::TEXT,
        EXISTS (
            SELECT 1
            FROM   public.user_roles ur
            JOIN   public.users  u ON u.id = ur.user_id
            JOIN   public.roles  r ON r.id = ur.role_id
            WHERE  u.email = 'admin@accordtechnologies.example'
            AND    r.name  = 'Admin'
            AND    ur.is_active = true
        ),
        'Admin role correctly linked to the pre-provisioned user'::TEXT;

    RETURN QUERY
    SELECT
        'admin_auth_user_id_pending'::TEXT,
        (SELECT auth_user_id IS NULL FROM public.users WHERE email = 'admin@accordtechnologies.example'),
        'Expected TRUE until the admin completes their first Supabase Auth sign-up — see README'::TEXT;
END;
$$;

COMMENT ON FUNCTION public.verify_seed_data() IS 'Manual verification helper. Run: SELECT * FROM public.verify_seed_data();';


-- =============================================================================
-- END: 010_seed.sql
-- =============================================================================
