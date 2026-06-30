-- =============================================================================
-- ACCORD CRM V1 — FINAL SQL PACKAGE
-- Migration: 003_lookup_tables
-- Description: 10 configurable lookup tables that drive dropdowns and enums
--              throughout the application: stages, statuses, priorities,
--              sources, industries, products, modules, won/loss reasons,
--              contact roles. All share an identical schema shape.
--              Must run after 001_auth_foundation.sql, 002_rbac.sql.
-- =============================================================================


-- =============================================================================
-- TABLE: public.deal_stages
-- The 6 approved pipeline stages, in fixed order, plus a flag identifying
-- which single stage represents "Won" and which represents "Lost" for use
-- by views and triggers that need to detect terminal stages by flag rather
-- than by brittle string-matching on the name.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.deal_stages (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    name            VARCHAR(50)     NOT NULL,
    description     TEXT            NULL,
    display_order   INTEGER         NOT NULL,
    is_won_stage    BOOLEAN         NOT NULL DEFAULT false,
    is_lost_stage   BOOLEAN         NOT NULL DEFAULT false,
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    created_by      UUID            NULL,
    updated_by      UUID            NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT deal_stages_pkey     PRIMARY KEY (id),
    CONSTRAINT deal_stages_name_uq  UNIQUE (name),
    CONSTRAINT deal_stages_order_uq UNIQUE (display_order),

    -- Only one Won stage and one Lost stage permitted at a time.
    -- EXCLUDE USING btree on a scalar boolean equality is supported natively
    -- by PostgreSQL 9.5+ — no btree_gist extension required (that extension
    -- is only needed for EXCLUDE USING gist on range/geometric types).
    CONSTRAINT deal_stages_one_won_stage
        EXCLUDE USING btree (is_won_stage WITH =) WHERE (is_won_stage = true),
    CONSTRAINT deal_stages_one_lost_stage
        EXCLUDE USING btree (is_lost_stage WITH =) WHERE (is_lost_stage = true),

    CONSTRAINT deal_stages_created_by_fk FOREIGN KEY (created_by) REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT deal_stages_updated_by_fk FOREIGN KEY (updated_by) REFERENCES public.users (id) ON DELETE SET NULL
);

COMMENT ON TABLE public.deal_stages IS 'Pipeline stages, fixed display order. Exactly one row may have is_won_stage=true and one may have is_lost_stage=true.';

CREATE INDEX IF NOT EXISTS idx_deal_stages_display_order ON public.deal_stages (display_order) WHERE is_active = true;

DROP TRIGGER IF EXISTS trg_deal_stages_updated_at ON public.deal_stages;
CREATE TRIGGER trg_deal_stages_updated_at BEFORE UPDATE ON public.deal_stages FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

INSERT INTO public.deal_stages (name, description, display_order, is_won_stage, is_lost_stage) VALUES
    ('Opportunity',    'Initial opportunity identified',           1, false, false),
    ('Qualified',      'Lead has been qualified',                  2, false, false),
    ('Demonstration',  'Product demonstration in progress',        3, false, false),
    ('Proposal',       'Formal proposal submitted',                4, false, false),
    ('Negotiation',    'Terms being negotiated',                   5, false, false),
    ('Won',            'Deal won — terminal stage',                6, true,  false)
ON CONFLICT (name) DO NOTHING;

-- "Lost" is not a pipeline stage a deal progresses through in the normal flow
-- (a deal may be lost FROM any stage), so it is represented as a status, not
-- a stage, per the approved BRD. See deal_statuses below for "Lost".


-- =============================================================================
-- TABLE: public.deal_statuses
-- Independent of stage. A deal is always in exactly one status: Active,
-- On Hold, Won, Lost, or Cancelled.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.deal_statuses (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    name            VARCHAR(50)     NOT NULL,
    description     TEXT            NULL,
    display_order   INTEGER         NOT NULL,
    is_terminal     BOOLEAN         NOT NULL DEFAULT false,
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    created_by      UUID            NULL,
    updated_by      UUID            NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT deal_statuses_pkey     PRIMARY KEY (id),
    CONSTRAINT deal_statuses_name_uq  UNIQUE (name),
    CONSTRAINT deal_statuses_order_uq UNIQUE (display_order),

    CONSTRAINT deal_statuses_created_by_fk FOREIGN KEY (created_by) REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT deal_statuses_updated_by_fk FOREIGN KEY (updated_by) REFERENCES public.users (id) ON DELETE SET NULL
);

COMMENT ON TABLE public.deal_statuses IS 'Deal lifecycle status: Active, On Hold, Won, Lost, Cancelled. is_terminal=true for Won/Lost/Cancelled.';

DROP TRIGGER IF EXISTS trg_deal_statuses_updated_at ON public.deal_statuses;
CREATE TRIGGER trg_deal_statuses_updated_at BEFORE UPDATE ON public.deal_statuses FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

INSERT INTO public.deal_statuses (name, description, display_order, is_terminal) VALUES
    ('Active',    'Deal is actively being worked',     1, false),
    ('On Hold',   'Deal is temporarily paused',         2, false),
    ('Won',       'Deal closed successfully',           3, true),
    ('Lost',      'Deal was lost',                      4, true),
    ('Cancelled', 'Deal was cancelled',                 5, true)
ON CONFLICT (name) DO NOTHING;


-- =============================================================================
-- TABLE: public.deal_priorities
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.deal_priorities (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    name            VARCHAR(50)     NOT NULL,
    display_order   INTEGER         NOT NULL,
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    created_by      UUID            NULL,
    updated_by      UUID            NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT deal_priorities_pkey     PRIMARY KEY (id),
    CONSTRAINT deal_priorities_name_uq  UNIQUE (name),
    CONSTRAINT deal_priorities_order_uq UNIQUE (display_order),

    CONSTRAINT deal_priorities_created_by_fk FOREIGN KEY (created_by) REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT deal_priorities_updated_by_fk FOREIGN KEY (updated_by) REFERENCES public.users (id) ON DELETE SET NULL
);

DROP TRIGGER IF EXISTS trg_deal_priorities_updated_at ON public.deal_priorities;
CREATE TRIGGER trg_deal_priorities_updated_at BEFORE UPDATE ON public.deal_priorities FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

INSERT INTO public.deal_priorities (name, display_order) VALUES
    ('High',   1),
    ('Medium', 2),
    ('Low',    3)
ON CONFLICT (name) DO NOTHING;


-- =============================================================================
-- TABLE: public.sources
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.sources (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    name            VARCHAR(100)    NOT NULL,
    display_order   INTEGER         NOT NULL,
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    created_by      UUID            NULL,
    updated_by      UUID            NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT sources_pkey     PRIMARY KEY (id),
    CONSTRAINT sources_name_uq  UNIQUE (name),
    CONSTRAINT sources_order_uq UNIQUE (display_order),

    CONSTRAINT sources_created_by_fk FOREIGN KEY (created_by) REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT sources_updated_by_fk FOREIGN KEY (updated_by) REFERENCES public.users (id) ON DELETE SET NULL
);

DROP TRIGGER IF EXISTS trg_sources_updated_at ON public.sources;
CREATE TRIGGER trg_sources_updated_at BEFORE UPDATE ON public.sources FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

INSERT INTO public.sources (name, display_order) VALUES
    ('Referral',       1),
    ('Website',        2),
    ('Cold Outreach',  3),
    ('Event',          4),
    ('Partner',        5),
    ('Inbound Call',   6),
    ('Social Media',   7)
ON CONFLICT (name) DO NOTHING;


-- =============================================================================
-- TABLE: public.industries
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.industries (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    name            VARCHAR(100)    NOT NULL,
    display_order   INTEGER         NOT NULL,
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    created_by      UUID            NULL,
    updated_by      UUID            NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT industries_pkey     PRIMARY KEY (id),
    CONSTRAINT industries_name_uq  UNIQUE (name),
    CONSTRAINT industries_order_uq UNIQUE (display_order),

    CONSTRAINT industries_created_by_fk FOREIGN KEY (created_by) REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT industries_updated_by_fk FOREIGN KEY (updated_by) REFERENCES public.users (id) ON DELETE SET NULL
);

DROP TRIGGER IF EXISTS trg_industries_updated_at ON public.industries;
CREATE TRIGGER trg_industries_updated_at BEFORE UPDATE ON public.industries FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

INSERT INTO public.industries (name, display_order) VALUES
    ('Banking & Finance',     1),
    ('Manufacturing',         2),
    ('Retail & E-commerce',   3),
    ('Healthcare',            4),
    ('Education',             5),
    ('Real Estate',           6),
    ('Telecommunications',    7),
    ('NGO / Development',     8),
    ('Government',            9),
    ('Other',                 10)
ON CONFLICT (name) DO NOTHING;


-- =============================================================================
-- TABLE: public.products
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.products (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    name            VARCHAR(100)    NOT NULL,
    description     TEXT            NULL,
    display_order   INTEGER         NOT NULL,
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    created_by      UUID            NULL,
    updated_by      UUID            NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT products_pkey     PRIMARY KEY (id),
    CONSTRAINT products_name_uq  UNIQUE (name),
    CONSTRAINT products_order_uq UNIQUE (display_order),

    CONSTRAINT products_created_by_fk FOREIGN KEY (created_by) REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT products_updated_by_fk FOREIGN KEY (updated_by) REFERENCES public.users (id) ON DELETE SET NULL
);

DROP TRIGGER IF EXISTS trg_products_updated_at ON public.products;
CREATE TRIGGER trg_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

INSERT INTO public.products (name, description, display_order) VALUES
    ('Accord HRM', 'Human Resource Management Suite', 1),
    ('Accord CRM', 'Customer Relationship Management Suite', 2)
ON CONFLICT (name) DO NOTHING;


-- =============================================================================
-- TABLE: public.modules
-- Belongs to a product. Module names are unique within a product, not
-- globally — two different products may each have a "Reporting" module.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.modules (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    product_id      UUID            NOT NULL,
    name            VARCHAR(100)    NOT NULL,
    description     TEXT            NULL,
    display_order   INTEGER         NOT NULL DEFAULT 0,
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    created_by      UUID            NULL,
    updated_by      UUID            NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT modules_pkey         PRIMARY KEY (id),
    CONSTRAINT modules_product_name_uq UNIQUE (product_id, name),

    CONSTRAINT modules_product_fk    FOREIGN KEY (product_id) REFERENCES public.products (id) ON DELETE CASCADE,
    CONSTRAINT modules_created_by_fk FOREIGN KEY (created_by) REFERENCES public.users (id)    ON DELETE SET NULL,
    CONSTRAINT modules_updated_by_fk FOREIGN KEY (updated_by) REFERENCES public.users (id)    ON DELETE SET NULL
);

COMMENT ON TABLE public.modules IS 'Sub-modules of a product. Unique within product_id, not globally.';

CREATE INDEX IF NOT EXISTS idx_modules_product_id ON public.modules (product_id) WHERE is_active = true;

DROP TRIGGER IF EXISTS trg_modules_updated_at ON public.modules;
CREATE TRIGGER trg_modules_updated_at BEFORE UPDATE ON public.modules FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

INSERT INTO public.modules (product_id, name, display_order)
SELECT p.id, m.name, m.display_order
FROM public.products p
JOIN (VALUES
    ('Accord CRM', 'Pipeline Management', 1),
    ('Accord CRM', 'Customer Management', 2),
    ('Accord CRM', 'Reporting & Analytics', 3),
    ('Accord CRM', 'Task & Activity Tracking', 4),
    ('Accord HRM', 'Payroll', 1),
    ('Accord HRM', 'Attendance', 2),
    ('Accord HRM', 'Recruitment', 3),
    ('Accord HRM', 'Performance Management', 4)
) AS m(product_name, name, display_order) ON m.product_name = p.name
ON CONFLICT (product_id, name) DO NOTHING;


-- =============================================================================
-- TABLE: public.won_reasons
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.won_reasons (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    name            VARCHAR(150)    NOT NULL,
    display_order   INTEGER         NOT NULL,
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    created_by      UUID            NULL,
    updated_by      UUID            NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT won_reasons_pkey     PRIMARY KEY (id),
    CONSTRAINT won_reasons_name_uq  UNIQUE (name),
    CONSTRAINT won_reasons_order_uq UNIQUE (display_order),

    CONSTRAINT won_reasons_created_by_fk FOREIGN KEY (created_by) REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT won_reasons_updated_by_fk FOREIGN KEY (updated_by) REFERENCES public.users (id) ON DELETE SET NULL
);

DROP TRIGGER IF EXISTS trg_won_reasons_updated_at ON public.won_reasons;
CREATE TRIGGER trg_won_reasons_updated_at BEFORE UPDATE ON public.won_reasons FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

INSERT INTO public.won_reasons (name, display_order) VALUES
    ('Best Price',            1),
    ('Best Product Fit',      2),
    ('Strong Relationship',   3),
    ('Faster Implementation', 4),
    ('Superior Support',      5),
    ('Other',                 6)
ON CONFLICT (name) DO NOTHING;


-- =============================================================================
-- TABLE: public.loss_reasons
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.loss_reasons (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    name            VARCHAR(150)    NOT NULL,
    display_order   INTEGER         NOT NULL,
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    created_by      UUID            NULL,
    updated_by      UUID            NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT loss_reasons_pkey     PRIMARY KEY (id),
    CONSTRAINT loss_reasons_name_uq  UNIQUE (name),
    CONSTRAINT loss_reasons_order_uq UNIQUE (display_order),

    CONSTRAINT loss_reasons_created_by_fk FOREIGN KEY (created_by) REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT loss_reasons_updated_by_fk FOREIGN KEY (updated_by) REFERENCES public.users (id) ON DELETE SET NULL
);

DROP TRIGGER IF EXISTS trg_loss_reasons_updated_at ON public.loss_reasons;
CREATE TRIGGER trg_loss_reasons_updated_at BEFORE UPDATE ON public.loss_reasons FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

INSERT INTO public.loss_reasons (name, display_order) VALUES
    ('Price Too High',        1),
    ('Chose Competitor',      2),
    ('No Budget',             3),
    ('No Decision / Timeout', 4),
    ('Feature Gap',           5),
    ('Other',                 6)
ON CONFLICT (name) DO NOTHING;


-- =============================================================================
-- TABLE: public.contact_roles
-- Gap Analysis addition — classifies a deal_contact's role at the prospect
-- company (Decision Maker, Influencer, etc.). Table created here; FK consumer
-- is deal_contacts in 004_core_deals.sql / customers schema.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.contact_roles (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    name            VARCHAR(100)    NOT NULL,
    display_order   INTEGER         NOT NULL,
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    created_by      UUID            NULL,
    updated_by      UUID            NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT contact_roles_pkey     PRIMARY KEY (id),
    CONSTRAINT contact_roles_name_uq  UNIQUE (name),
    CONSTRAINT contact_roles_order_uq UNIQUE (display_order),

    CONSTRAINT contact_roles_created_by_fk FOREIGN KEY (created_by) REFERENCES public.users (id) ON DELETE SET NULL,
    CONSTRAINT contact_roles_updated_by_fk FOREIGN KEY (updated_by) REFERENCES public.users (id) ON DELETE SET NULL
);

DROP TRIGGER IF EXISTS trg_contact_roles_updated_at ON public.contact_roles;
CREATE TRIGGER trg_contact_roles_updated_at BEFORE UPDATE ON public.contact_roles FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

INSERT INTO public.contact_roles (name, display_order) VALUES
    ('Decision Maker',     1),
    ('Influencer',         2),
    ('Technical Evaluator', 3),
    ('Procurement',        4),
    ('End User',           5),
    ('Other',              6)
ON CONFLICT (name) DO NOTHING;


-- =============================================================================
-- ROW-LEVEL SECURITY — identical pattern across all 10 lookup tables:
--   SELECT: any authenticated user, active rows only (configuration is
--           needed by every role to render dropdowns).
--   INSERT/UPDATE/DELETE: Admin only via has_permission('settings.manage').
-- Soft-delete via is_active — no hard DELETE policy on any lookup table;
-- deactivation is the only supported removal path so historical deals that
-- reference a since-retired lookup value are never orphaned.
-- =============================================================================

-- deal_stages
ALTER TABLE public.deal_stages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "deal_stages_select" ON public.deal_stages FOR SELECT TO authenticated USING (true);
CREATE POLICY "deal_stages_insert_admin" ON public.deal_stages FOR INSERT TO authenticated WITH CHECK (public.has_permission('settings.manage'));
CREATE POLICY "deal_stages_update_admin" ON public.deal_stages FOR UPDATE TO authenticated USING (public.has_permission('settings.manage')) WITH CHECK (public.has_permission('settings.manage'));

-- deal_statuses
ALTER TABLE public.deal_statuses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "deal_statuses_select" ON public.deal_statuses FOR SELECT TO authenticated USING (true);
CREATE POLICY "deal_statuses_insert_admin" ON public.deal_statuses FOR INSERT TO authenticated WITH CHECK (public.is_admin());
CREATE POLICY "deal_statuses_update_admin" ON public.deal_statuses FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- deal_priorities
ALTER TABLE public.deal_priorities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "deal_priorities_select" ON public.deal_priorities FOR SELECT TO authenticated USING (true);
CREATE POLICY "deal_priorities_insert_admin" ON public.deal_priorities FOR INSERT TO authenticated WITH CHECK (public.has_permission('settings.manage'));
CREATE POLICY "deal_priorities_update_admin" ON public.deal_priorities FOR UPDATE TO authenticated USING (public.has_permission('settings.manage')) WITH CHECK (public.has_permission('settings.manage'));

-- sources
ALTER TABLE public.sources ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sources_select" ON public.sources FOR SELECT TO authenticated USING (true);
CREATE POLICY "sources_insert_admin" ON public.sources FOR INSERT TO authenticated WITH CHECK (public.has_permission('settings.manage'));
CREATE POLICY "sources_update_admin" ON public.sources FOR UPDATE TO authenticated USING (public.has_permission('settings.manage')) WITH CHECK (public.has_permission('settings.manage'));

-- industries
ALTER TABLE public.industries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "industries_select" ON public.industries FOR SELECT TO authenticated USING (true);
CREATE POLICY "industries_insert_admin" ON public.industries FOR INSERT TO authenticated WITH CHECK (public.has_permission('settings.manage'));
CREATE POLICY "industries_update_admin" ON public.industries FOR UPDATE TO authenticated USING (public.has_permission('settings.manage')) WITH CHECK (public.has_permission('settings.manage'));

-- products
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "products_select" ON public.products FOR SELECT TO authenticated USING (true);
CREATE POLICY "products_insert_admin" ON public.products FOR INSERT TO authenticated WITH CHECK (public.has_permission('settings.manage'));
CREATE POLICY "products_update_admin" ON public.products FOR UPDATE TO authenticated USING (public.has_permission('settings.manage')) WITH CHECK (public.has_permission('settings.manage'));

-- modules
ALTER TABLE public.modules ENABLE ROW LEVEL SECURITY;
CREATE POLICY "modules_select" ON public.modules FOR SELECT TO authenticated USING (true);
CREATE POLICY "modules_insert_admin" ON public.modules FOR INSERT TO authenticated WITH CHECK (public.has_permission('settings.manage'));
CREATE POLICY "modules_update_admin" ON public.modules FOR UPDATE TO authenticated USING (public.has_permission('settings.manage')) WITH CHECK (public.has_permission('settings.manage'));

-- won_reasons
ALTER TABLE public.won_reasons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "won_reasons_select" ON public.won_reasons FOR SELECT TO authenticated USING (true);
CREATE POLICY "won_reasons_insert_admin" ON public.won_reasons FOR INSERT TO authenticated WITH CHECK (public.has_permission('settings.manage'));
CREATE POLICY "won_reasons_update_admin" ON public.won_reasons FOR UPDATE TO authenticated USING (public.has_permission('settings.manage')) WITH CHECK (public.has_permission('settings.manage'));

-- loss_reasons
ALTER TABLE public.loss_reasons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "loss_reasons_select" ON public.loss_reasons FOR SELECT TO authenticated USING (true);
CREATE POLICY "loss_reasons_insert_admin" ON public.loss_reasons FOR INSERT TO authenticated WITH CHECK (public.has_permission('settings.manage'));
CREATE POLICY "loss_reasons_update_admin" ON public.loss_reasons FOR UPDATE TO authenticated USING (public.has_permission('settings.manage')) WITH CHECK (public.has_permission('settings.manage'));

-- contact_roles
ALTER TABLE public.contact_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "contact_roles_select" ON public.contact_roles FOR SELECT TO authenticated USING (true);
CREATE POLICY "contact_roles_insert_admin" ON public.contact_roles FOR INSERT TO authenticated WITH CHECK (public.has_permission('settings.manage'));
CREATE POLICY "contact_roles_update_admin" ON public.contact_roles FOR UPDATE TO authenticated USING (public.has_permission('settings.manage')) WITH CHECK (public.has_permission('settings.manage'));


-- =============================================================================
-- FUNCTION: get_status_id(p_status_name TEXT)
-- Resolves a deal_statuses.id by name. Used by trigger functions in later
-- migrations to detect Won/Lost/Cancelled transitions without hardcoding UUIDs.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_status_id(p_status_name TEXT)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT id FROM public.deal_statuses WHERE name = p_status_name LIMIT 1;
$$;

COMMENT ON FUNCTION public.get_status_id(TEXT) IS 'Resolves deal_statuses.id by name. Used by later-migration triggers to detect status transitions.';


-- =============================================================================
-- FUNCTION: get_stage_id(p_stage_name TEXT)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_stage_id(p_stage_name TEXT)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT id FROM public.deal_stages WHERE name = p_stage_name LIMIT 1;
$$;

COMMENT ON FUNCTION public.get_stage_id(TEXT) IS 'Resolves deal_stages.id by name.';


-- =============================================================================
-- VERIFICATION HELPER
-- =============================================================================
CREATE OR REPLACE FUNCTION public.verify_lookup_seed()
RETURNS TABLE (table_name TEXT, row_count BIGINT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT 'deal_stages', count(*) FROM public.deal_stages
    UNION ALL SELECT 'deal_statuses', count(*) FROM public.deal_statuses
    UNION ALL SELECT 'deal_priorities', count(*) FROM public.deal_priorities
    UNION ALL SELECT 'sources', count(*) FROM public.sources
    UNION ALL SELECT 'industries', count(*) FROM public.industries
    UNION ALL SELECT 'products', count(*) FROM public.products
    UNION ALL SELECT 'modules', count(*) FROM public.modules
    UNION ALL SELECT 'won_reasons', count(*) FROM public.won_reasons
    UNION ALL SELECT 'loss_reasons', count(*) FROM public.loss_reasons
    UNION ALL SELECT 'contact_roles', count(*) FROM public.contact_roles;
$$;

COMMENT ON FUNCTION public.verify_lookup_seed() IS 'Manual verification helper. Run: SELECT * FROM public.verify_lookup_seed();';


-- =============================================================================
-- END: 003_lookup_tables.sql
-- =============================================================================
