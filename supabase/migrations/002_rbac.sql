-- =============================================================================
-- ACCORD CRM V1 — FINAL SQL PACKAGE
-- Migration: 002_rbac
-- Description: Roles, permissions, role_permissions, user_roles. Redefines the
--              RBAC helper function stubs created in 001_auth_foundation.sql
--              with their real implementations now that roles/permissions exist.
--              Seeds 4 system roles and the full permission catalogue.
--
-- Corrections applied (debugging history):
--   - "system_user" is a reserved keyword in PostgreSQL 14+ (zero-argument
--     SQL-standard function). Using it as a CTE alias causes
--     ERROR 42601: syntax error at or near "system_user".
--     Fixed: renamed to seed_actor throughout this file.
--   - NEW must never be referenced inside an RLS WITH CHECK expression —
--     PostgreSQL has no FROM-clause entry for "new" in that context
--     (ERROR: missing FROM-clause entry for table "new"). The system-role
--     protection logic lives in a BEFORE UPDATE/DELETE trigger instead.
--
-- Must run after 001_auth_foundation.sql.
-- =============================================================================


-- =============================================================================
-- TABLE: public.roles
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.roles (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    name            VARCHAR(50)     NOT NULL,
    description     TEXT            NULL,
    is_system_role  BOOLEAN         NOT NULL DEFAULT false,
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    created_by      UUID            NULL,
    updated_by      UUID            NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT roles_pkey      PRIMARY KEY (id),
    CONSTRAINT roles_name_uq   UNIQUE (name),
    CONSTRAINT roles_name_nonempty CHECK (trim(name) <> ''),

    CONSTRAINT roles_created_by_fk FOREIGN KEY (created_by) REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT roles_updated_by_fk FOREIGN KEY (updated_by) REFERENCES public.users (id) ON DELETE SET NULL
);

COMMENT ON TABLE  public.roles               IS 'CRM roles. 4 system roles seeded: Admin, Partner, Manager, Executive.';
COMMENT ON COLUMN public.roles.is_system_role IS 'System roles cannot be deleted or have their name changed. Protected by trigger.';

CREATE INDEX IF NOT EXISTS idx_roles_is_active ON public.roles (is_active);

DROP TRIGGER IF EXISTS trg_roles_updated_at ON public.roles;
CREATE TRIGGER trg_roles_updated_at
    BEFORE UPDATE ON public.roles
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_updated_at();


-- =============================================================================
-- TABLE: public.permissions
-- Format: "module.action", e.g. "pipeline.create", "settings.manage".
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.permissions (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    name            VARCHAR(100)    NOT NULL,
    module          VARCHAR(50)     NOT NULL,
    action          VARCHAR(50)     NOT NULL,
    description     TEXT            NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT permissions_pkey    PRIMARY KEY (id),
    CONSTRAINT permissions_name_uq UNIQUE (name),
    CONSTRAINT permissions_name_format CHECK (name = module || '.' || action)
);

COMMENT ON TABLE public.permissions IS 'Permission catalogue. name is always "{module}.{action}" — enforced by CHECK constraint.';

CREATE INDEX IF NOT EXISTS idx_permissions_module ON public.permissions (module);


-- =============================================================================
-- TABLE: public.role_permissions
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.role_permissions (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    role_id         UUID            NOT NULL,
    permission_id   UUID            NOT NULL,
    granted_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    granted_by      UUID            NULL,

    CONSTRAINT role_permissions_pkey PRIMARY KEY (id),
    CONSTRAINT role_permissions_uq   UNIQUE (role_id, permission_id),

    CONSTRAINT role_permissions_role_fk       FOREIGN KEY (role_id)       REFERENCES public.roles (id)       ON DELETE CASCADE,
    CONSTRAINT role_permissions_permission_fk FOREIGN KEY (permission_id) REFERENCES public.permissions (id) ON DELETE CASCADE,
    CONSTRAINT role_permissions_granted_by_fk FOREIGN KEY (granted_by)    REFERENCES public.users (id)       ON DELETE SET NULL
);

COMMENT ON TABLE public.role_permissions IS 'Many-to-many: which permissions are granted to which role.';

CREATE INDEX IF NOT EXISTS idx_role_permissions_role_id       ON public.role_permissions (role_id);
CREATE INDEX IF NOT EXISTS idx_role_permissions_permission_id ON public.role_permissions (permission_id);


-- =============================================================================
-- TABLE: public.user_roles
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.user_roles (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    user_id         UUID            NOT NULL,
    role_id         UUID            NOT NULL,
    assigned_at     TIMESTAMPTZ     NOT NULL DEFAULT now(),
    assigned_by     UUID            NULL,
    is_active       BOOLEAN         NOT NULL DEFAULT true,

    CONSTRAINT user_roles_pkey PRIMARY KEY (id),
    CONSTRAINT user_roles_uq   UNIQUE (user_id, role_id),

    CONSTRAINT user_roles_user_fk        FOREIGN KEY (user_id)     REFERENCES public.users (id) ON DELETE CASCADE,
    CONSTRAINT user_roles_role_fk        FOREIGN KEY (role_id)     REFERENCES public.roles (id) ON DELETE RESTRICT,
    CONSTRAINT user_roles_assigned_by_fk FOREIGN KEY (assigned_by) REFERENCES public.users (id) ON DELETE SET NULL
);

COMMENT ON TABLE public.user_roles IS 'Many-to-many: which roles are assigned to which user.';

CREATE INDEX IF NOT EXISTS idx_user_roles_user_id ON public.user_roles (user_id) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_user_roles_role_id ON public.user_roles (role_id) WHERE is_active = true;


-- =============================================================================
-- SEED: 4 system roles
-- =============================================================================
INSERT INTO public.roles (name, description, is_system_role, is_active) VALUES
    ('Admin',     'Full system access. Manages users, roles, and all configuration.', true, true),
    ('Partner',   'Senior leadership. Full pipeline and reporting access across all deals.', true, true),
    ('Manager',   'Team management. Full visibility and edit access within their scope.', true, true),
    ('Executive', 'Individual sales contributor. Access scoped to own and assigned deals.', true, true)
ON CONFLICT (name) DO NOTHING;


-- =============================================================================
-- SEED: Permission catalogue
-- 7 modules × up to 5 actions each. "module.action" naming enforced by CHECK.
-- =============================================================================
INSERT INTO public.permissions (name, module, action, description) VALUES
    -- dashboard
    ('dashboard.view',          'dashboard', 'view',          'View the dashboard'),
    -- pipeline
    ('pipeline.view',           'pipeline',  'view',          'View deals in the pipeline'),
    ('pipeline.view_all',       'pipeline',  'view_all',      'View all deals regardless of ownership'),
    ('pipeline.create',         'pipeline',  'create',        'Create new deals'),
    ('pipeline.edit',           'pipeline',  'edit',          'Edit deal details'),
    ('pipeline.assign',         'pipeline',  'assign',        'Reassign deals to other users'),
    -- customers
    ('customers.view',          'customers', 'view',          'View customer records'),
    ('customers.create',        'customers', 'create',        'Manually create customer records'),
    ('customers.edit',          'customers', 'edit',          'Edit customer records'),
    -- tasks
    ('tasks.view',               'tasks',     'view',          'View tasks'),
    ('tasks.create',             'tasks',     'create',        'Create tasks'),
    ('tasks.edit',               'tasks',     'edit',          'Edit tasks'),
    -- meetings
    ('meetings.view',           'meetings',  'view',          'View meetings'),
    ('meetings.create',         'meetings',  'create',        'Schedule meetings'),
    ('meetings.edit',           'meetings',  'edit',          'Edit meeting details and outcomes'),
    -- reports
    ('reports.view',            'reports',   'view',          'View reports scoped to own data'),
    ('reports.view_all',        'reports',   'view_all',      'View reports across all users'' data'),
    -- settings
    ('settings.view',           'settings',  'view',          'View settings pages'),
    ('settings.manage',         'settings',  'manage',        'Modify settings: lookups, roles, products')
ON CONFLICT (name) DO NOTHING;


-- =============================================================================
-- SEED: role_permissions
-- Built via a CTE that joins role name + permission name to their UUIDs.
-- "seed_actor" replaces the originally-attempted "system_user" CTE name,
-- which is a reserved PostgreSQL keyword and caused a 42601 syntax error.
-- =============================================================================
WITH seed_actor AS (
    SELECT id AS actor_id FROM public.users LIMIT 1   -- NULL-safe: no users exist yet at fresh install
),
role_perm_pairs AS (
    -- Admin: every permission
    SELECT 'Admin' AS role_name, name AS permission_name FROM public.permissions

    UNION ALL

    -- Partner: everything except settings.manage (Partner has settings.view only)
    SELECT 'Partner', name FROM public.permissions
    WHERE name <> 'settings.manage'

    UNION ALL

    -- Manager: full pipeline/customers/tasks/meetings, view_all reports, no settings.manage
    SELECT 'Manager', name FROM public.permissions
    WHERE name IN (
        'dashboard.view',
        'pipeline.view', 'pipeline.view_all', 'pipeline.create', 'pipeline.edit', 'pipeline.assign',
        'customers.view', 'customers.create', 'customers.edit',
        'tasks.view', 'tasks.create', 'tasks.edit',
        'meetings.view', 'meetings.create', 'meetings.edit',
        'reports.view', 'reports.view_all',
        'settings.view'
    )

    UNION ALL

    -- Executive: own-scope only, no pipeline.view_all, no pipeline.assign, no reports.view_all
    SELECT 'Executive', name FROM public.permissions
    WHERE name IN (
        'dashboard.view',
        'pipeline.view', 'pipeline.create', 'pipeline.edit',
        'customers.view',
        'tasks.view', 'tasks.create', 'tasks.edit',
        'meetings.view', 'meetings.create', 'meetings.edit',
        'reports.view'
    )
),
combined AS (
    SELECT
        r.id  AS role_id,
        p.id  AS permission_id,
        (SELECT actor_id FROM seed_actor) AS granted_by
    FROM   role_perm_pairs rp
    JOIN   public.roles       r ON r.name = rp.role_name
    JOIN   public.permissions p ON p.name = rp.permission_name
)
INSERT INTO public.role_permissions (role_id, permission_id, granted_by)
SELECT role_id, permission_id, granted_by
FROM   combined
ON CONFLICT (role_id, permission_id) DO NOTHING;


-- =============================================================================
-- FUNCTION (REDEFINE): get_current_user_role()
-- Returns the single highest-priority role name for the current user.
-- Priority: Admin > Partner > Manager > Executive.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_current_user_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT r.name
    FROM   public.user_roles ur
    JOIN   public.roles      r ON r.id = ur.role_id
    WHERE  ur.user_id   = public.get_current_crm_user_id()
    AND    ur.is_active = true
    AND    r.is_active  = true
    ORDER BY CASE r.name
        WHEN 'Admin'     THEN 1
        WHEN 'Partner'   THEN 2
        WHEN 'Manager'   THEN 3
        WHEN 'Executive' THEN 4
        ELSE 5
    END
    LIMIT 1;
$$;

COMMENT ON FUNCTION public.get_current_user_role() IS 'Returns the highest-priority role name for the current session user. Priority: Admin > Partner > Manager > Executive.';


-- =============================================================================
-- FUNCTION (REDEFINE): is_admin()
-- =============================================================================
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.get_current_user_role() = 'Admin';
$$;


-- =============================================================================
-- FUNCTION (REDEFINE): is_admin_or_partner()
-- =============================================================================
CREATE OR REPLACE FUNCTION public.is_admin_or_partner()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.get_current_user_role() IN ('Admin', 'Partner');
$$;


-- =============================================================================
-- FUNCTION (REDEFINE): is_manager_or_above()
-- =============================================================================
CREATE OR REPLACE FUNCTION public.is_manager_or_above()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.get_current_user_role() IN ('Admin', 'Partner', 'Manager');
$$;


-- =============================================================================
-- FUNCTION (REDEFINE): has_permission(p_permission_name TEXT)
-- Checks whether the current user's resolved permission set contains
-- p_permission_name, across ALL of their active role assignments (a user
-- may hold more than one role; permissions are the union across roles).
--
-- Correction applied: the original stub always returned false and an early
-- draft mistakenly filtered only by get_current_user_role() (the single
-- highest-priority role), which silently dropped permissions granted by a
-- second, lower-priority role assignment. Fixed to join user_roles directly
-- so every active role the user holds contributes its permissions.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.has_permission(p_permission_name TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM   public.user_roles      ur
        JOIN   public.roles           r  ON r.id = ur.role_id
        JOIN   public.role_permissions rp ON rp.role_id = r.id
        JOIN   public.permissions     p  ON p.id = rp.permission_id
        WHERE  ur.user_id   = public.get_current_crm_user_id()
        AND    ur.is_active = true
        AND    r.is_active  = true
        AND    p.name       = p_permission_name
    );
$$;

COMMENT ON FUNCTION public.has_permission(TEXT) IS 'Checks the current user''s full resolved permission set (union across all active roles) for p_permission_name.';


-- =============================================================================
-- ROW-LEVEL SECURITY: roles
-- =============================================================================
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "roles_select_all_authenticated"
    ON public.roles FOR SELECT TO authenticated
    USING (true);

CREATE POLICY "roles_insert_admin"
    ON public.roles FOR INSERT TO authenticated
    WITH CHECK (public.is_admin());

-- UPDATE: Admin only. The "cannot rename/deactivate a system role" guard
-- requires OLD/NEW comparison and is enforced by a trigger below — never
-- inline in WITH CHECK, which has no access to NEW as a queryable row source.
CREATE POLICY "roles_update_admin"
    ON public.roles FOR UPDATE TO authenticated
    USING  (public.is_admin())
    WITH CHECK (public.is_admin());

CREATE POLICY "roles_delete_admin_non_system"
    ON public.roles FOR DELETE TO authenticated
    USING (public.is_admin() AND is_system_role = false);


-- =============================================================================
-- TRIGGER: protect system roles from rename/deactivation
-- =============================================================================
CREATE OR REPLACE FUNCTION public.protect_system_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF OLD.is_system_role = true THEN
        IF NEW.name <> OLD.name THEN
            RAISE EXCEPTION 'System role "%" cannot be renamed.', OLD.name
            USING ERRCODE = 'check_violation';
        END IF;
        IF NEW.is_active = false THEN
            RAISE EXCEPTION 'System role "%" cannot be deactivated.', OLD.name
            USING ERRCODE = 'check_violation';
        END IF;
        IF NEW.is_system_role = false THEN
            RAISE EXCEPTION 'System role "%" flag cannot be removed.', OLD.name
            USING ERRCODE = 'check_violation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.protect_system_role() IS 'BEFORE UPDATE guard: prevents renaming, deactivating, or un-flagging a system role. OLD/NEW comparison correctly lives in a trigger, not RLS.';

DROP TRIGGER IF EXISTS trg_roles_protect_system ON public.roles;
CREATE TRIGGER trg_roles_protect_system
    BEFORE UPDATE ON public.roles
    FOR EACH ROW
    EXECUTE FUNCTION public.protect_system_role();


-- =============================================================================
-- ROW-LEVEL SECURITY: permissions
-- =============================================================================
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "permissions_select_all_authenticated"
    ON public.permissions FOR SELECT TO authenticated
    USING (true);

-- No INSERT/UPDATE/DELETE policies — permission catalogue is migration-managed only.


-- =============================================================================
-- ROW-LEVEL SECURITY: role_permissions
-- =============================================================================
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "role_permissions_select_all_authenticated"
    ON public.role_permissions FOR SELECT TO authenticated
    USING (true);

CREATE POLICY "role_permissions_insert_admin"
    ON public.role_permissions FOR INSERT TO authenticated
    WITH CHECK (public.is_admin());

CREATE POLICY "role_permissions_delete_admin"
    ON public.role_permissions FOR DELETE TO authenticated
    USING (public.is_admin());

-- No UPDATE policy — grants are inserted/deleted, never updated in place.


-- =============================================================================
-- ROW-LEVEL SECURITY: user_roles
-- =============================================================================
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_roles_select_own"
    ON public.user_roles FOR SELECT TO authenticated
    USING (user_id = public.get_current_crm_user_id());

CREATE POLICY "user_roles_select_admin_partner_manager"
    ON public.user_roles FOR SELECT TO authenticated
    USING (public.is_manager_or_above());

CREATE POLICY "user_roles_insert_admin"
    ON public.user_roles FOR INSERT TO authenticated
    WITH CHECK (public.is_admin());

CREATE POLICY "user_roles_update_admin"
    ON public.user_roles FOR UPDATE TO authenticated
    USING  (public.is_admin())
    WITH CHECK (public.is_admin());

CREATE POLICY "user_roles_delete_admin"
    ON public.user_roles FOR DELETE TO authenticated
    USING (public.is_admin());


-- =============================================================================
-- VERIFICATION HELPER: verify_rbac_seed()
-- Run manually after migration to sanity-check the seed data landed correctly.
-- SELECT * FROM public.verify_rbac_seed();
-- =============================================================================
CREATE OR REPLACE FUNCTION public.verify_rbac_seed()
RETURNS TABLE (check_name TEXT, expected TEXT, actual TEXT, passed BOOLEAN)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 'roles_count'::TEXT, '4'::TEXT, count(*)::TEXT, count(*) = 4
    FROM public.roles WHERE is_system_role = true;

    RETURN QUERY
    SELECT 'permissions_count'::TEXT, '19'::TEXT, count(*)::TEXT, count(*) = 19
    FROM public.permissions;

    RETURN QUERY
    SELECT 'admin_has_all_permissions'::TEXT, count(p.*)::TEXT, count(rp.*)::TEXT, count(p.*) = count(rp.*)
    FROM public.permissions p
    LEFT JOIN public.role_permissions rp
        ON rp.permission_id = p.id
        AND rp.role_id = (SELECT id FROM public.roles WHERE name = 'Admin');
END;
$$;

COMMENT ON FUNCTION public.verify_rbac_seed() IS 'Manual verification helper. Run: SELECT * FROM public.verify_rbac_seed();';


-- =============================================================================
-- END: 002_rbac.sql
-- =============================================================================
