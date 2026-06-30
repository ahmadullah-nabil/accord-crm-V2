-- =============================================================================
-- ACCORD CRM V1 — FINAL SQL PACKAGE
-- Migration: 001_auth_foundation
-- Description: Extensions, users table (bridge to Supabase auth.users), core
--              helper functions used by RLS policies throughout the project.
--              This is the root migration — no dependencies.
-- =============================================================================

-- ── Extensions ────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pg_trgm";    -- trigram search indexes


-- =============================================================================
-- TABLE: public.users
-- Bridges Supabase auth.users to a CRM-domain profile row.
-- auth_user_id is nullable to support pre-provisioning a user before they
-- accept an invite (auth.users row does not exist yet).
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.users (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    auth_user_id    UUID            NULL,
    full_name       VARCHAR(200)    NOT NULL,
    email           VARCHAR(255)    NOT NULL,
    phone           VARCHAR(50)     NULL,
    avatar_url      TEXT            NULL,
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    metadata        JSONB           NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT users_pkey            PRIMARY KEY (id),
    CONSTRAINT users_email_uq        UNIQUE (email),
    CONSTRAINT users_auth_user_id_uq UNIQUE (auth_user_id),
    CONSTRAINT users_full_name_nonempty CHECK (trim(full_name) <> ''),
    CONSTRAINT users_email_nonempty     CHECK (trim(email) <> '')
);

COMMENT ON TABLE  public.users               IS 'CRM user profile. Bridges auth.users (Supabase Auth) to domain-level user data via auth_user_id.';
COMMENT ON COLUMN public.users.auth_user_id  IS 'FK to auth.users.id (no DB-level FK — auth schema is managed by Supabase). NULL until the user accepts their invite.';

CREATE INDEX IF NOT EXISTS idx_users_auth_user_id ON public.users (auth_user_id) WHERE auth_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_is_active     ON public.users (is_active);
CREATE INDEX IF NOT EXISTS idx_users_full_name_trgm ON public.users USING gin (full_name gin_trgm_ops);


-- =============================================================================
-- FUNCTION: handle_updated_at()
-- Generic BEFORE UPDATE trigger function. Sets updated_at = now() on every
-- UPDATE. Reused by every table in the schema that has an updated_at column.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_updated_at() IS 'Generic BEFORE UPDATE trigger: sets updated_at = now(). Reused across all tables.';

DROP TRIGGER IF EXISTS trg_users_updated_at ON public.users;
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();


-- =============================================================================
-- FUNCTION: get_current_crm_user_id()
-- Resolves the CRM users.id for the currently authenticated Supabase session.
-- Returns NULL if no session, or if the auth user has no linked CRM profile.
-- STABLE (not VOLATILE) — safe to use multiple times per query without
-- repeated evaluation cost; auth.uid() is consistent within a statement.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_current_crm_user_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT id
    FROM   public.users
    WHERE  auth_user_id = auth.uid()
    AND    is_active     = true
    LIMIT  1;
$$;

COMMENT ON FUNCTION public.get_current_crm_user_id() IS 'Resolves the current session''s CRM users.id via auth.uid(). Returns NULL if unauthenticated or profile inactive.';


-- =============================================================================
-- STUB FUNCTIONS — replaced by 002_rbac.sql once roles/permissions exist.
-- Defined here so that any table created later in this migration (none today,
-- but RLS-bearing future tables) can reference them without forward-declaration
-- errors. Each stub fails closed (returns false / NULL) until 002 redefines it.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_current_user_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT NULL::TEXT;
$$;

COMMENT ON FUNCTION public.get_current_user_role() IS 'STUB — redefined in 002_rbac.sql. Returns the highest-priority role name for the current user.';

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT false;
$$;

COMMENT ON FUNCTION public.is_admin() IS 'STUB — redefined in 002_rbac.sql.';

CREATE OR REPLACE FUNCTION public.is_admin_or_partner()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT false;
$$;

COMMENT ON FUNCTION public.is_admin_or_partner() IS 'STUB — redefined in 002_rbac.sql.';

CREATE OR REPLACE FUNCTION public.is_manager_or_above()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT false;
$$;

COMMENT ON FUNCTION public.is_manager_or_above() IS 'STUB — redefined in 002_rbac.sql.';

CREATE OR REPLACE FUNCTION public.has_permission(p_permission_name TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT false;
$$;

COMMENT ON FUNCTION public.has_permission(TEXT) IS 'STUB — redefined in 002_rbac.sql. Checks the current user''s resolved permission set for p_permission_name (format: "module.action").';


-- =============================================================================
-- ROW-LEVEL SECURITY: users
-- Note: is_admin() etc. are stubs at this point (return false), so until
-- 002_rbac.sql redefines them, only the "select_own" policy is effectively
-- reachable. This is expected and safe — 002 runs immediately after.
-- =============================================================================
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_select_own"
    ON public.users FOR SELECT TO authenticated
    USING (auth_user_id = auth.uid());

CREATE POLICY "users_select_admin_partner"
    ON public.users FOR SELECT TO authenticated
    USING (public.is_admin_or_partner());

CREATE POLICY "users_select_manager"
    ON public.users FOR SELECT TO authenticated
    USING (public.get_current_user_role() = 'Manager');

-- Active-user picker: any authenticated user can see the names/avatars of
-- other active users (needed for assignee dropdowns, @mentions, etc.)
CREATE POLICY "users_select_active_for_pickers"
    ON public.users FOR SELECT TO authenticated
    USING (is_active = true);

CREATE POLICY "users_insert_admin"
    ON public.users FOR INSERT TO authenticated
    WITH CHECK (public.is_admin());

-- UPDATE: Admin only at the RLS layer. The system-role / self-deactivation
-- guard (which requires comparing OLD vs NEW) is enforced by a dedicated
-- BEFORE UPDATE trigger below — NEW is never referenced inside a WITH CHECK
-- expression because PostgreSQL has no FROM-clause entry for "new" there.
CREATE POLICY "users_update_admin"
    ON public.users FOR UPDATE TO authenticated
    USING  (public.is_admin())
    WITH CHECK (public.is_admin());

-- No DELETE policy — users are deactivated (is_active = false), never deleted.


-- =============================================================================
-- TRIGGER: prevent self-deactivation
-- A user cannot deactivate (is_active: true -> false) their own account via
-- the application. Comparing OLD/NEW is only valid inside a trigger function
-- — this was previously (incorrectly) attempted inline in an RLS WITH CHECK.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.prevent_self_deactivation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF OLD.is_active = true
       AND NEW.is_active = false
       AND OLD.auth_user_id = auth.uid()
    THEN
        RAISE EXCEPTION 'You cannot deactivate your own account.'
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.prevent_self_deactivation() IS 'BEFORE UPDATE guard: blocks a user from deactivating their own account. OLD/NEW comparison belongs in a trigger, not in an RLS WITH CHECK expression.';

DROP TRIGGER IF EXISTS trg_users_prevent_self_deactivation ON public.users;
CREATE TRIGGER trg_users_prevent_self_deactivation
    BEFORE UPDATE OF is_active ON public.users
    FOR EACH ROW
    WHEN (OLD.is_active IS DISTINCT FROM NEW.is_active)
    EXECUTE FUNCTION public.prevent_self_deactivation();


-- =============================================================================
-- TRIGGER: sync auth.users -> public.users on signup
-- When Supabase Auth creates a new auth.users row (sign-up or invite
-- acceptance), automatically link it to an existing pre-provisioned
-- public.users row matched by email, or create a new profile row.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Try to link to a pre-provisioned profile by email first
    UPDATE public.users
    SET    auth_user_id = NEW.id,
           updated_at   = now()
    WHERE  email = NEW.email
    AND    auth_user_id IS NULL;

    -- If no pre-provisioned row existed, create one now
    IF NOT FOUND THEN
        INSERT INTO public.users (auth_user_id, full_name, email)
        VALUES (
            NEW.id,
            COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
            NEW.email
        )
        ON CONFLICT (email) DO UPDATE
            SET auth_user_id = EXCLUDED.auth_user_id;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_auth_user() IS 'Fires AFTER INSERT on auth.users. Links or creates the corresponding public.users profile row.';

DROP TRIGGER IF EXISTS trg_on_auth_user_created ON auth.users;
CREATE TRIGGER trg_on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_auth_user();


-- =============================================================================
-- END: 001_auth_foundation.sql
-- =============================================================================
