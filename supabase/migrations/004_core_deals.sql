-- =============================================================================
-- ACCORD CRM V1 — FINAL SQL PACKAGE
-- Migration: 004_core_deals
-- Description: The deals table (the central entity of the CRM), deal_modules
--              (many-to-many with modules), and deal_contacts (Gap Analysis
--              addition — contacts at the prospect company). Includes the
--              deal_number auto-generation sequence and the can_access_deal()
--              RLS helper consumed by every later migration.
--              Must run after 001, 002, 003.
-- =============================================================================


-- =============================================================================
-- TABLE: public.deal_number_sequences
-- Backs atomic deal_number generation: DL-YYYY-NNNNNN, reset per calendar year.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.deal_number_sequences (
    year        INTEGER     NOT NULL,
    last_value  BIGINT      NOT NULL DEFAULT 0,
    CONSTRAINT deal_number_sequences_pkey PRIMARY KEY (year)
);

CREATE OR REPLACE FUNCTION public.generate_deal_number()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_year  INTEGER;
    v_next  BIGINT;
BEGIN
    v_year := EXTRACT(YEAR FROM now())::INTEGER;
    INSERT INTO public.deal_number_sequences (year, last_value)
    VALUES (v_year, 1)
    ON CONFLICT (year) DO UPDATE
        SET last_value = deal_number_sequences.last_value + 1
    RETURNING last_value INTO v_next;
    RETURN 'DL-' || v_year::TEXT || '-' || lpad(v_next::TEXT, 6, '0');
END;
$$;

COMMENT ON FUNCTION public.generate_deal_number() IS 'Atomically generates the next deal number in DL-YYYY-NNNNNN format.';


-- =============================================================================
-- TABLE: public.deals
-- The central entity. 35 business columns + audit/system columns.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.deals (
    -- ── Identity ──────────────────────────────────────────────────────────────
    id                          UUID            NOT NULL DEFAULT gen_random_uuid(),
    deal_number                 VARCHAR(30)     NOT NULL DEFAULT public.generate_deal_number(),

    -- ── Company Information ──────────────────────────────────────────────────
    title                       VARCHAR(300)    NULL,
    description                 TEXT            NULL,
    company_name                VARCHAR(200)    NOT NULL,
    industry_id                 UUID            NULL,
    website                     VARCHAR(255)    NULL,
    country                     VARCHAR(100)    NULL,
    employee_headcount          INTEGER         NULL CHECK (employee_headcount IS NULL OR employee_headcount > 0),
    current_system              VARCHAR(200)    NULL,

    -- ── Source ────────────────────────────────────────────────────────────────
    source_id                   UUID            NULL,
    referral_source             VARCHAR(200)    NULL,

    -- ── Ownership ─────────────────────────────────────────────────────────────
    owner_id                    UUID            NOT NULL,
    assigned_to                 UUID            NULL,

    -- ── Pipeline State ────────────────────────────────────────────────────────
    stage_id                    UUID            NOT NULL,
    status_id                   UUID            NOT NULL,
    priority_id                 UUID            NULL,

    -- ── Product / Solution ────────────────────────────────────────────────────
    product_id                  UUID            NULL,

    -- ── Commercial ────────────────────────────────────────────────────────────
    proposal_value               NUMERIC(15,2)   NULL CHECK (proposal_value IS NULL OR proposal_value >= 0),
    final_contract_value         NUMERIC(15,2)   NULL CHECK (final_contract_value IS NULL OR final_contract_value >= 0),
    contract_duration_months     INTEGER         NULL CHECK (contract_duration_months IS NULL OR contract_duration_months > 0),
    expected_close_date          DATE            NULL,

    -- ── Terminal State: Won ──────────────────────────────────────────────────
    won_at                      TIMESTAMPTZ     NULL,
    won_reason_id               UUID            NULL,
    won_remark                  TEXT            NULL,
    won_by                      UUID            NULL,

    -- ── Terminal State: Lost ─────────────────────────────────────────────────
    lost_at                     TIMESTAMPTZ     NULL,
    lost_at_stage_id            UUID            NULL,
    loss_reason_id              UUID            NULL,
    loss_remark                 TEXT            NULL,
    lost_by                     UUID            NULL,

    -- ── Follow-up & Activity Tracking ────────────────────────────────────────
    next_followup_date          DATE            NULL,
    last_activity_at            TIMESTAMPTZ     NULL,

    -- ── Audit ─────────────────────────────────────────────────────────────────
    created_by                  UUID            NOT NULL,
    updated_by                  UUID            NULL,
    created_at                  TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ     NOT NULL DEFAULT now(),

    -- ── System ────────────────────────────────────────────────────────────────
    is_active                   BOOLEAN         NOT NULL DEFAULT true,
    metadata                    JSONB           NULL,

    -- ── Constraints ───────────────────────────────────────────────────────────
    CONSTRAINT deals_pkey                PRIMARY KEY (id),
    CONSTRAINT deals_deal_number_uq      UNIQUE (deal_number),
    CONSTRAINT deals_company_name_nonempty CHECK (trim(company_name) <> ''),

    -- ── Foreign Keys ──────────────────────────────────────────────────────────
    CONSTRAINT deals_industry_fk      FOREIGN KEY (industry_id)      REFERENCES public.industries (id)      ON DELETE SET NULL,
    CONSTRAINT deals_source_fk        FOREIGN KEY (source_id)        REFERENCES public.sources (id)         ON DELETE SET NULL,
    CONSTRAINT deals_owner_fk         FOREIGN KEY (owner_id)         REFERENCES public.users (id)           ON DELETE RESTRICT,
    CONSTRAINT deals_assigned_to_fk   FOREIGN KEY (assigned_to)      REFERENCES public.users (id)           ON DELETE SET NULL,
    CONSTRAINT deals_stage_fk         FOREIGN KEY (stage_id)         REFERENCES public.deal_stages (id)     ON DELETE RESTRICT,
    CONSTRAINT deals_status_fk        FOREIGN KEY (status_id)        REFERENCES public.deal_statuses (id)   ON DELETE RESTRICT,
    CONSTRAINT deals_priority_fk      FOREIGN KEY (priority_id)      REFERENCES public.deal_priorities (id) ON DELETE SET NULL,
    CONSTRAINT deals_product_fk       FOREIGN KEY (product_id)       REFERENCES public.products (id)        ON DELETE SET NULL,
    CONSTRAINT deals_won_reason_fk    FOREIGN KEY (won_reason_id)    REFERENCES public.won_reasons (id)     ON DELETE SET NULL,
    CONSTRAINT deals_won_by_fk        FOREIGN KEY (won_by)           REFERENCES public.users (id)           ON DELETE SET NULL,
    CONSTRAINT deals_lost_at_stage_fk FOREIGN KEY (lost_at_stage_id) REFERENCES public.deal_stages (id)     ON DELETE SET NULL,
    CONSTRAINT deals_loss_reason_fk   FOREIGN KEY (loss_reason_id)   REFERENCES public.loss_reasons (id)    ON DELETE SET NULL,
    CONSTRAINT deals_lost_by_fk       FOREIGN KEY (lost_by)          REFERENCES public.users (id)           ON DELETE SET NULL,
    CONSTRAINT deals_created_by_fk    FOREIGN KEY (created_by)       REFERENCES public.users (id)           ON DELETE RESTRICT,
    CONSTRAINT deals_updated_by_fk    FOREIGN KEY (updated_by)       REFERENCES public.users (id)           ON DELETE RESTRICT
);

COMMENT ON TABLE  public.deals               IS 'The central deal-centric entity. Deal numbers auto-generate as DL-YYYY-NNNNNN.';
COMMENT ON COLUMN public.deals.deal_number   IS 'Auto-generated via generate_deal_number(). Globally unique, never reused.';
COMMENT ON COLUMN public.deals.lost_at_stage_id IS 'Snapshot of stage_id at the moment the deal was marked Lost. Enables stage-of-loss analytics even after stage_id may later be reset.';

CREATE INDEX IF NOT EXISTS idx_deals_owner_id        ON public.deals (owner_id);
CREATE INDEX IF NOT EXISTS idx_deals_assigned_to      ON public.deals (assigned_to) WHERE assigned_to IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_deals_stage_id         ON public.deals (stage_id);
CREATE INDEX IF NOT EXISTS idx_deals_status_id        ON public.deals (status_id);
CREATE INDEX IF NOT EXISTS idx_deals_company_name_trgm ON public.deals USING gin (company_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_deals_expected_close_date ON public.deals (expected_close_date) WHERE expected_close_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_deals_created_at       ON public.deals (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_deals_is_active         ON public.deals (is_active);
CREATE INDEX IF NOT EXISTS idx_deals_next_followup_date ON public.deals (next_followup_date) WHERE next_followup_date IS NOT NULL;

DROP TRIGGER IF EXISTS trg_deals_updated_at ON public.deals;
CREATE TRIGGER trg_deals_updated_at BEFORE UPDATE ON public.deals FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Re-stamps deal_number defensively on UPDATE if somehow cleared; primarily a
-- BEFORE INSERT concern since the column DEFAULT already covers creation.
CREATE OR REPLACE FUNCTION public.set_deal_number()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' AND (NEW.deal_number IS NULL OR trim(NEW.deal_number) = '') THEN
        NEW.deal_number := public.generate_deal_number();
    END IF;

    IF TG_OP = 'UPDATE' AND NEW.deal_number IS DISTINCT FROM OLD.deal_number THEN
        RAISE EXCEPTION 'deal_number cannot be changed once assigned.'
        USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_deals_set_deal_number ON public.deals;
CREATE TRIGGER trg_deals_set_deal_number
    BEFORE INSERT OR UPDATE ON public.deals
    FOR EACH ROW
    EXECUTE FUNCTION public.set_deal_number();


-- =============================================================================
-- TABLE: public.deal_modules
-- Many-to-many: a deal may propose multiple modules.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.deal_modules (
    id          UUID        NOT NULL DEFAULT gen_random_uuid(),
    deal_id     UUID        NOT NULL,
    module_id   UUID        NOT NULL,
    added_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT deal_modules_pkey PRIMARY KEY (id),
    CONSTRAINT deal_modules_uq   UNIQUE (deal_id, module_id),

    CONSTRAINT deal_modules_deal_fk   FOREIGN KEY (deal_id)   REFERENCES public.deals (id)   ON DELETE CASCADE,
    CONSTRAINT deal_modules_module_fk FOREIGN KEY (module_id) REFERENCES public.modules (id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_deal_modules_deal_id   ON public.deal_modules (deal_id);
CREATE INDEX IF NOT EXISTS idx_deal_modules_module_id ON public.deal_modules (module_id);


-- =============================================================================
-- TABLE: public.deal_contacts
-- Gap Analysis addition. Contacts at the prospect company associated with
-- a deal. is_primary partial unique index ensures only one primary contact
-- per deal at a time; auto-demotion handled by trigger below.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.deal_contacts (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    deal_id         UUID            NOT NULL,
    role_id         UUID            NULL,
    first_name      VARCHAR(100)    NOT NULL,
    last_name       VARCHAR(100)    NULL,
    full_name       VARCHAR(200)    NULL,      -- auto-populated by trigger from first/last name
    designation     VARCHAR(150)    NULL,
    department      VARCHAR(150)    NULL,
    email           VARCHAR(255)    NULL,
    phone           VARCHAR(50)     NULL,
    mobile          VARCHAR(50)     NULL,
    linkedin_url    TEXT            NULL,
    is_primary      BOOLEAN         NOT NULL DEFAULT false,
    notes           TEXT            NULL,
    last_contacted_at TIMESTAMPTZ   NULL,
    created_by      UUID            NOT NULL,
    updated_by      UUID            NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    is_active       BOOLEAN         NOT NULL DEFAULT true,

    CONSTRAINT deal_contacts_pkey                PRIMARY KEY (id),
    CONSTRAINT deal_contacts_first_name_nonempty CHECK (trim(first_name) <> ''),

    CONSTRAINT deal_contacts_deal_fk        FOREIGN KEY (deal_id)     REFERENCES public.deals (id)         ON DELETE CASCADE,
    CONSTRAINT deal_contacts_role_fk        FOREIGN KEY (role_id)     REFERENCES public.contact_roles (id) ON DELETE SET NULL,
    CONSTRAINT deal_contacts_created_by_fk  FOREIGN KEY (created_by)  REFERENCES public.users (id)         ON DELETE RESTRICT,
    CONSTRAINT deal_contacts_updated_by_fk  FOREIGN KEY (updated_by)  REFERENCES public.users (id)         ON DELETE RESTRICT
);

COMMENT ON TABLE  public.deal_contacts            IS 'Contacts at the prospect company for a deal. Gap Analysis addition. Only one is_primary=true contact per deal at a time.';
COMMENT ON COLUMN public.deal_contacts.full_name  IS 'Auto-populated from first_name + last_name by trigger. Stored (not generated) so it can be indexed for trigram search.';

-- Partial unique index: only one primary contact per deal
CREATE UNIQUE INDEX IF NOT EXISTS idx_deal_contacts_one_primary
    ON public.deal_contacts (deal_id)
    WHERE is_primary = true AND is_active = true;

CREATE INDEX IF NOT EXISTS idx_deal_contacts_deal_id     ON public.deal_contacts (deal_id);
CREATE INDEX IF NOT EXISTS idx_deal_contacts_full_name_trgm ON public.deal_contacts USING gin (full_name gin_trgm_ops);

DROP TRIGGER IF EXISTS trg_deal_contacts_updated_at ON public.deal_contacts;
CREATE TRIGGER trg_deal_contacts_updated_at BEFORE UPDATE ON public.deal_contacts FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Auto-populate full_name
CREATE OR REPLACE FUNCTION public.sync_deal_contact_full_name()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    NEW.full_name := trim(NEW.first_name || ' ' || COALESCE(NEW.last_name, ''));
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_deal_contacts_full_name ON public.deal_contacts;
CREATE TRIGGER trg_deal_contacts_full_name
    BEFORE INSERT OR UPDATE OF first_name, last_name ON public.deal_contacts
    FOR EACH ROW
    EXECUTE FUNCTION public.sync_deal_contact_full_name();

-- Auto-demote: when a contact is set is_primary=true, demote any other
-- primary contact on the same deal (belt-and-suspenders alongside the
-- partial unique index, which would otherwise just reject the second INSERT).
CREATE OR REPLACE FUNCTION public.validate_primary_contact()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.is_primary = true THEN
        UPDATE public.deal_contacts
        SET    is_primary = false,
               updated_at = now()
        WHERE  deal_id    = NEW.deal_id
        AND    id        <> NEW.id
        AND    is_primary = true;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_deal_contacts_primary ON public.deal_contacts;
CREATE TRIGGER trg_deal_contacts_primary
    BEFORE INSERT OR UPDATE OF is_primary ON public.deal_contacts
    FOR EACH ROW
    WHEN (NEW.is_primary = true)
    EXECUTE FUNCTION public.validate_primary_contact();


-- =============================================================================
-- FUNCTION: can_access_deal(p_deal_id UUID)
-- Central RLS helper consumed by every deal-related table in every later
-- migration. Admin/Partner/Manager: full access. Executive: only deals they
-- own or are assigned to.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.can_access_deal(p_deal_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        public.is_manager_or_above()
        OR EXISTS (
            SELECT 1
            FROM   public.deals d
            WHERE  d.id = p_deal_id
            AND    (
                d.owner_id      = public.get_current_crm_user_id()
                OR d.assigned_to = public.get_current_crm_user_id()
            )
        );
$$;

COMMENT ON FUNCTION public.can_access_deal(UUID) IS 'Central RLS helper. Admin/Partner/Manager: full access. Executive: only own/assigned deals. Consumed by every deal-related table.';


-- =============================================================================
-- ROW-LEVEL SECURITY: deals
-- =============================================================================
ALTER TABLE public.deals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "deals_select_admin_partner_manager"
    ON public.deals FOR SELECT TO authenticated
    USING (public.is_manager_or_above());

CREATE POLICY "deals_select_executive"
    ON public.deals FOR SELECT TO authenticated
    USING (
        public.get_current_user_role() = 'Executive'
        AND (owner_id = public.get_current_crm_user_id() OR assigned_to = public.get_current_crm_user_id())
    );

CREATE POLICY "deals_insert"
    ON public.deals FOR INSERT TO authenticated
    WITH CHECK (
        public.has_permission('pipeline.create')
        AND created_by = public.get_current_crm_user_id()
    );

CREATE POLICY "deals_update_admin_partner_manager"
    ON public.deals FOR UPDATE TO authenticated
    USING  (public.is_manager_or_above())
    WITH CHECK (public.is_manager_or_above());

CREATE POLICY "deals_update_executive_own"
    ON public.deals FOR UPDATE TO authenticated
    USING (
        public.get_current_user_role() = 'Executive'
        AND (owner_id = public.get_current_crm_user_id() OR assigned_to = public.get_current_crm_user_id())
        AND public.has_permission('pipeline.edit')
    )
    WITH CHECK (
        public.get_current_user_role() = 'Executive'
        AND (owner_id = public.get_current_crm_user_id() OR assigned_to = public.get_current_crm_user_id())
        AND public.has_permission('pipeline.edit')
    );

-- No DELETE policy — deals are status-transitioned (Cancelled), never deleted.


-- =============================================================================
-- ROW-LEVEL SECURITY: deal_modules
-- =============================================================================
ALTER TABLE public.deal_modules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "deal_modules_select" ON public.deal_modules FOR SELECT TO authenticated
    USING (public.can_access_deal(deal_id));

CREATE POLICY "deal_modules_insert" ON public.deal_modules FOR INSERT TO authenticated
    WITH CHECK (public.can_access_deal(deal_id) AND public.has_permission('pipeline.edit'));

CREATE POLICY "deal_modules_delete" ON public.deal_modules FOR DELETE TO authenticated
    USING (public.can_access_deal(deal_id) AND public.has_permission('pipeline.edit'));


-- =============================================================================
-- ROW-LEVEL SECURITY: deal_contacts
-- =============================================================================
ALTER TABLE public.deal_contacts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "deal_contacts_select_admin_partner_manager"
    ON public.deal_contacts FOR SELECT TO authenticated
    USING (public.is_manager_or_above());

CREATE POLICY "deal_contacts_select_executive"
    ON public.deal_contacts FOR SELECT TO authenticated
    USING (
        public.get_current_user_role() = 'Executive'
        AND public.can_access_deal(deal_id)
    );

CREATE POLICY "deal_contacts_insert"
    ON public.deal_contacts FOR INSERT TO authenticated
    WITH CHECK (
        public.can_access_deal(deal_id)
        AND public.has_permission('pipeline.edit')
        AND created_by = public.get_current_crm_user_id()
    );

CREATE POLICY "deal_contacts_update_admin_partner_manager"
    ON public.deal_contacts FOR UPDATE TO authenticated
    USING  (public.is_manager_or_above())
    WITH CHECK (public.is_manager_or_above());

CREATE POLICY "deal_contacts_update_executive"
    ON public.deal_contacts FOR UPDATE TO authenticated
    USING (
        public.get_current_user_role() = 'Executive'
        AND public.can_access_deal(deal_id)
        AND public.has_permission('pipeline.edit')
    )
    WITH CHECK (
        public.get_current_user_role() = 'Executive'
        AND public.can_access_deal(deal_id)
        AND public.has_permission('pipeline.edit')
    );

-- No DELETE policy — deal_contacts are soft-deactivated via is_active.


-- =============================================================================
-- TABLE: public.stage_logs
-- Immutable record of every pipeline stage transition. Append-only — UPDATE
-- and DELETE are blocked for every role, including Admin, by RLS USING(false)
-- policies AND a trigger-level guard (two-layer enforcement).
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.stage_logs (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    deal_id         UUID            NOT NULL,
    from_stage_id   UUID            NULL,
    to_stage_id     UUID            NOT NULL,
    changed_by      UUID            NOT NULL,
    change_reason   TEXT            NOT NULL,
    changed_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT stage_logs_pkey PRIMARY KEY (id),
    CONSTRAINT stage_logs_reason_nonempty CHECK (trim(change_reason) <> ''),
    CONSTRAINT stage_logs_stage_must_change CHECK (from_stage_id IS NULL OR from_stage_id <> to_stage_id),

    CONSTRAINT stage_logs_deal_fk       FOREIGN KEY (deal_id)       REFERENCES public.deals (id)       ON DELETE RESTRICT,
    CONSTRAINT stage_logs_from_stage_fk FOREIGN KEY (from_stage_id) REFERENCES public.deal_stages (id) ON DELETE RESTRICT,
    CONSTRAINT stage_logs_to_stage_fk   FOREIGN KEY (to_stage_id)   REFERENCES public.deal_stages (id) ON DELETE RESTRICT,
    CONSTRAINT stage_logs_changed_by_fk FOREIGN KEY (changed_by)   REFERENCES public.users (id)       ON DELETE RESTRICT
);

COMMENT ON TABLE public.stage_logs IS 'Immutable stage-transition audit log. Append-only — UPDATE/DELETE blocked by RLS + trigger.';

CREATE INDEX IF NOT EXISTS idx_stage_logs_deal_id_changed_at ON public.stage_logs (deal_id, changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_stage_logs_changed_by         ON public.stage_logs (changed_by);
CREATE INDEX IF NOT EXISTS idx_stage_logs_to_stage_id        ON public.stage_logs (to_stage_id);


-- =============================================================================
-- TABLE: public.assignment_logs
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.assignment_logs (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    deal_id         UUID            NOT NULL,
    from_user_id    UUID            NULL,
    to_user_id      UUID            NULL,
    changed_by      UUID            NOT NULL,
    change_reason   TEXT            NOT NULL,
    changed_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT assignment_logs_pkey PRIMARY KEY (id),
    CONSTRAINT assignment_logs_reason_nonempty CHECK (trim(change_reason) <> ''),
    CONSTRAINT assignment_logs_user_must_change CHECK (from_user_id IS DISTINCT FROM to_user_id),

    CONSTRAINT assignment_logs_deal_fk       FOREIGN KEY (deal_id)      REFERENCES public.deals (id) ON DELETE RESTRICT,
    CONSTRAINT assignment_logs_from_user_fk  FOREIGN KEY (from_user_id) REFERENCES public.users (id) ON DELETE RESTRICT,
    CONSTRAINT assignment_logs_to_user_fk    FOREIGN KEY (to_user_id)   REFERENCES public.users (id) ON DELETE RESTRICT,
    CONSTRAINT assignment_logs_changed_by_fk FOREIGN KEY (changed_by)   REFERENCES public.users (id) ON DELETE RESTRICT
);

COMMENT ON TABLE public.assignment_logs IS 'Immutable assignment-change audit log. Append-only.';

CREATE INDEX IF NOT EXISTS idx_assignment_logs_deal_id_changed_at ON public.assignment_logs (deal_id, changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_assignment_logs_to_user_id ON public.assignment_logs (to_user_id) WHERE to_user_id IS NOT NULL;


-- =============================================================================
-- TABLE: public.deal_events
-- One row per deal: the terminal Won/Lost/Cancelled event.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.deal_events (
    id                          UUID            NOT NULL DEFAULT gen_random_uuid(),
    deal_id                     UUID            NOT NULL,
    event_type                  VARCHAR(10)     NOT NULL CHECK (event_type IN ('won', 'lost', 'cancelled')),

    won_reason_id               UUID            NULL,
    won_remark                  TEXT            NULL,
    final_contract_value        NUMERIC(15,2)   NULL CHECK (final_contract_value IS NULL OR final_contract_value >= 0),
    contract_duration_months    INTEGER         NULL CHECK (contract_duration_months IS NULL OR contract_duration_months > 0),

    loss_reason_id               UUID            NULL,
    loss_remark                  TEXT            NULL,
    stage_at_loss_id             UUID            NULL,

    recorded_by                 UUID            NOT NULL,
    recorded_at                 TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT deal_events_pkey    PRIMARY KEY (id),
    CONSTRAINT deal_events_deal_uq UNIQUE (deal_id),

    CONSTRAINT deal_events_won_fields_required
        CHECK (event_type <> 'won' OR (won_reason_id IS NOT NULL AND won_remark IS NOT NULL AND trim(won_remark) <> '')),
    CONSTRAINT deal_events_lost_fields_required
        CHECK (event_type <> 'lost' OR (loss_reason_id IS NOT NULL AND loss_remark IS NOT NULL AND trim(loss_remark) <> '')),

    CONSTRAINT deal_events_deal_fk          FOREIGN KEY (deal_id)          REFERENCES public.deals (id)        ON DELETE RESTRICT,
    CONSTRAINT deal_events_won_reason_fk    FOREIGN KEY (won_reason_id)    REFERENCES public.won_reasons (id)  ON DELETE SET NULL,
    CONSTRAINT deal_events_loss_reason_fk   FOREIGN KEY (loss_reason_id)   REFERENCES public.loss_reasons (id) ON DELETE SET NULL,
    CONSTRAINT deal_events_stage_at_loss_fk FOREIGN KEY (stage_at_loss_id) REFERENCES public.deal_stages (id)  ON DELETE SET NULL,
    CONSTRAINT deal_events_recorded_by_fk   FOREIGN KEY (recorded_by)      REFERENCES public.users (id)        ON DELETE RESTRICT
);

COMMENT ON TABLE public.deal_events IS 'Terminal deal event (Won/Lost/Cancelled). One per deal. Denormalised for fast revenue/loss reporting.';

CREATE UNIQUE INDEX IF NOT EXISTS idx_deal_events_deal_id ON public.deal_events (deal_id);
CREATE INDEX IF NOT EXISTS idx_deal_events_event_type     ON public.deal_events (event_type);
CREATE INDEX IF NOT EXISTS idx_deal_events_recorded_at    ON public.deal_events (recorded_at DESC);


-- =============================================================================
-- IMMUTABILITY ENFORCEMENT (second layer, on top of RLS USING(false) below)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.enforce_audit_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
BEGIN
    RAISE EXCEPTION 'Audit table "%" is immutable. UPDATE and DELETE are permanently prohibited.', TG_TABLE_NAME
    USING ERRCODE = 'restrict_violation';
END;
$func$;

COMMENT ON FUNCTION public.enforce_audit_immutability() IS 'Second-line immutability guard. Raises an exception on any UPDATE/DELETE, even from the service role.';

DROP TRIGGER IF EXISTS trg_stage_logs_immutable ON public.stage_logs;
CREATE TRIGGER trg_stage_logs_immutable BEFORE UPDATE OR DELETE ON public.stage_logs FOR EACH ROW EXECUTE FUNCTION public.enforce_audit_immutability();

DROP TRIGGER IF EXISTS trg_assignment_logs_immutable ON public.assignment_logs;
CREATE TRIGGER trg_assignment_logs_immutable BEFORE UPDATE OR DELETE ON public.assignment_logs FOR EACH ROW EXECUTE FUNCTION public.enforce_audit_immutability();

DROP TRIGGER IF EXISTS trg_deal_events_immutable ON public.deal_events;
CREATE TRIGGER trg_deal_events_immutable BEFORE UPDATE OR DELETE ON public.deal_events FOR EACH ROW EXECUTE FUNCTION public.enforce_audit_immutability();


-- =============================================================================
-- TRIGGER: stage_logs on deal creation (initial stage assignment)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.handle_deal_created_stage_log()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
BEGIN
    INSERT INTO public.stage_logs (deal_id, from_stage_id, to_stage_id, changed_by, change_reason, changed_at)
    VALUES (NEW.id, NULL, NEW.stage_id, NEW.created_by, 'Deal created', now());
    RETURN NEW;
END;
$func$;

DROP TRIGGER IF EXISTS trg_deals_created_stage_log ON public.deals;
CREATE TRIGGER trg_deals_created_stage_log
    AFTER INSERT ON public.deals
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_deal_created_stage_log();


-- =============================================================================
-- TRIGGER: stage_logs on stage change
-- Reads the mandatory remark from a session-local parameter set by the
-- application (or by rpc_change_deal_stage() in 012_rpc_functions.sql) in the
-- same transaction as the UPDATE:  SET LOCAL crm.stage_change_reason = '...';
-- =============================================================================
CREATE OR REPLACE FUNCTION public.handle_deal_stage_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
DECLARE
    v_reason   TEXT;
    v_actor_id UUID;
BEGIN
    IF NEW.stage_id IS NOT DISTINCT FROM OLD.stage_id THEN
        RETURN NEW;
    END IF;

    v_reason := current_setting('crm.stage_change_reason', true);
    IF v_reason IS NULL OR trim(v_reason) = '' THEN
        RAISE EXCEPTION 'Stage change requires a non-empty remark. Set "crm.stage_change_reason" before updating deals.stage_id.'
        USING ERRCODE = 'check_violation';
    END IF;

    v_actor_id := COALESCE(public.get_current_crm_user_id(), NEW.updated_by);
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Stage change: cannot determine acting user.' USING ERRCODE = 'not_null_violation';
    END IF;

    INSERT INTO public.stage_logs (deal_id, from_stage_id, to_stage_id, changed_by, change_reason, changed_at)
    VALUES (NEW.id, OLD.stage_id, NEW.stage_id, v_actor_id, trim(v_reason), now());

    PERFORM set_config('crm.stage_change_reason', '', true);

    RETURN NEW;
END;
$func$;

DROP TRIGGER IF EXISTS trg_deals_stage_change ON public.deals;
CREATE TRIGGER trg_deals_stage_change
    AFTER UPDATE OF stage_id ON public.deals
    FOR EACH ROW
    WHEN (NEW.stage_id IS DISTINCT FROM OLD.stage_id)
    EXECUTE FUNCTION public.handle_deal_stage_change();


-- =============================================================================
-- TRIGGER: assignment_logs on assignment change
-- =============================================================================
CREATE OR REPLACE FUNCTION public.handle_deal_assignment_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
DECLARE
    v_reason   TEXT;
    v_actor_id UUID;
BEGIN
    IF NEW.assigned_to IS NOT DISTINCT FROM OLD.assigned_to THEN
        RETURN NEW;
    END IF;

    v_reason := current_setting('crm.assignment_change_reason', true);
    IF v_reason IS NULL OR trim(v_reason) = '' THEN
        RAISE EXCEPTION 'Assignment change requires a non-empty remark. Set "crm.assignment_change_reason" before updating deals.assigned_to.'
        USING ERRCODE = 'check_violation';
    END IF;

    v_actor_id := COALESCE(public.get_current_crm_user_id(), NEW.updated_by);
    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Assignment change: cannot determine acting user.' USING ERRCODE = 'not_null_violation';
    END IF;

    INSERT INTO public.assignment_logs (deal_id, from_user_id, to_user_id, changed_by, change_reason, changed_at)
    VALUES (NEW.id, OLD.assigned_to, NEW.assigned_to, v_actor_id, trim(v_reason), now());

    PERFORM set_config('crm.assignment_change_reason', '', true);

    RETURN NEW;
END;
$func$;

DROP TRIGGER IF EXISTS trg_deals_assignment_change ON public.deals;
CREATE TRIGGER trg_deals_assignment_change
    AFTER UPDATE OF assigned_to ON public.deals
    FOR EACH ROW
    WHEN (NEW.assigned_to IS DISTINCT FROM OLD.assigned_to)
    EXECUTE FUNCTION public.handle_deal_assignment_change();


-- =============================================================================
-- TRIGGER: deal_events on Won
-- NOTE: AFTER trigger. Assignments to NEW.xxx inside an AFTER trigger body
-- are silently ignored by PostgreSQL — won_at/won_by are stamped via a real
-- UPDATE statement, never via "NEW.won_at := ...".
-- =============================================================================
CREATE OR REPLACE FUNCTION public.handle_deal_won_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
DECLARE
    v_won_status_id UUID;
    v_actor_id      UUID;
BEGIN
    v_won_status_id := public.get_status_id('Won');

    IF NEW.status_id <> v_won_status_id THEN RETURN NEW; END IF;
    IF OLD.status_id = v_won_status_id THEN RETURN NEW; END IF;

    v_actor_id := COALESCE(public.get_current_crm_user_id(), NEW.won_by, NEW.updated_by);

    IF NEW.won_at IS NULL THEN
        UPDATE public.deals
        SET    won_at = now(), won_by = COALESCE(v_actor_id, NEW.won_by), updated_at = now()
        WHERE  id = NEW.id;
    END IF;

    IF NEW.won_reason_id IS NULL THEN
        RAISE EXCEPTION 'Won deal requires won_reason_id to be set on the deal record.' USING ERRCODE = 'not_null_violation';
    END IF;
    IF NEW.won_remark IS NULL OR trim(NEW.won_remark) = '' THEN
        RAISE EXCEPTION 'Won deal requires a non-empty won_remark.' USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO public.deal_events (
        deal_id, event_type, won_reason_id, won_remark, final_contract_value, contract_duration_months, recorded_by, recorded_at
    ) VALUES (
        NEW.id, 'won', NEW.won_reason_id, NEW.won_remark, NEW.final_contract_value, NEW.contract_duration_months,
        COALESCE(v_actor_id, NEW.won_by), now()
    )
    ON CONFLICT (deal_id) DO NOTHING;

    RETURN NEW;
END;
$func$;

DROP TRIGGER IF EXISTS trg_deals_won ON public.deals;
CREATE TRIGGER trg_deals_won
    AFTER UPDATE OF status_id ON public.deals
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_deal_won_event();


-- =============================================================================
-- TRIGGER: deal_events on Lost
-- =============================================================================
CREATE OR REPLACE FUNCTION public.handle_deal_lost_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
DECLARE
    v_lost_status_id UUID;
    v_actor_id       UUID;
BEGIN
    v_lost_status_id := public.get_status_id('Lost');

    IF NEW.status_id <> v_lost_status_id THEN RETURN NEW; END IF;
    IF OLD.status_id = v_lost_status_id THEN RETURN NEW; END IF;

    v_actor_id := COALESCE(public.get_current_crm_user_id(), NEW.lost_by, NEW.updated_by);

    IF NEW.lost_at IS NULL THEN
        UPDATE public.deals
        SET    lost_at = now(), lost_by = COALESCE(v_actor_id, NEW.lost_by),
               lost_at_stage_id = OLD.stage_id, updated_at = now()
        WHERE  id = NEW.id;
    END IF;

    IF NEW.loss_reason_id IS NULL THEN
        RAISE EXCEPTION 'Lost deal requires loss_reason_id to be set on the deal record.' USING ERRCODE = 'not_null_violation';
    END IF;
    IF NEW.loss_remark IS NULL OR trim(NEW.loss_remark) = '' THEN
        RAISE EXCEPTION 'Lost deal requires a non-empty loss_remark.' USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO public.deal_events (
        deal_id, event_type, loss_reason_id, loss_remark, stage_at_loss_id, recorded_by, recorded_at
    ) VALUES (
        NEW.id, 'lost', NEW.loss_reason_id, NEW.loss_remark, OLD.stage_id, COALESCE(v_actor_id, NEW.lost_by), now()
    )
    ON CONFLICT (deal_id) DO NOTHING;

    RETURN NEW;
END;
$func$;

DROP TRIGGER IF EXISTS trg_deals_lost ON public.deals;
CREATE TRIGGER trg_deals_lost
    AFTER UPDATE OF status_id ON public.deals
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_deal_lost_event();


-- =============================================================================
-- ROW-LEVEL SECURITY: stage_logs / assignment_logs / deal_events
-- =============================================================================
ALTER TABLE public.stage_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "stage_logs_select_admin_partner_manager" ON public.stage_logs FOR SELECT TO authenticated USING (public.is_manager_or_above());
CREATE POLICY "stage_logs_select_executive" ON public.stage_logs FOR SELECT TO authenticated USING (public.get_current_user_role() = 'Executive' AND public.can_access_deal(deal_id));
CREATE POLICY "stage_logs_update_denied" ON public.stage_logs FOR UPDATE TO authenticated USING (false);
CREATE POLICY "stage_logs_delete_denied" ON public.stage_logs FOR DELETE TO authenticated USING (false);

ALTER TABLE public.assignment_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "assignment_logs_select_admin_partner_manager" ON public.assignment_logs FOR SELECT TO authenticated USING (public.is_manager_or_above());
CREATE POLICY "assignment_logs_select_executive" ON public.assignment_logs FOR SELECT TO authenticated USING (public.get_current_user_role() = 'Executive' AND public.can_access_deal(deal_id));
CREATE POLICY "assignment_logs_update_denied" ON public.assignment_logs FOR UPDATE TO authenticated USING (false);
CREATE POLICY "assignment_logs_delete_denied" ON public.assignment_logs FOR DELETE TO authenticated USING (false);

ALTER TABLE public.deal_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "deal_events_select_admin_partner_manager" ON public.deal_events FOR SELECT TO authenticated USING (public.is_manager_or_above());
CREATE POLICY "deal_events_select_executive" ON public.deal_events FOR SELECT TO authenticated USING (public.get_current_user_role() = 'Executive' AND public.can_access_deal(deal_id));
CREATE POLICY "deal_events_update_denied" ON public.deal_events FOR UPDATE TO authenticated USING (false);
CREATE POLICY "deal_events_delete_denied" ON public.deal_events FOR DELETE TO authenticated USING (false);

-- =============================================================================
-- VERIFICATION HELPER
-- =============================================================================
CREATE OR REPLACE FUNCTION public.verify_core_deals_seed()
RETURNS TABLE (check_name TEXT, passed BOOLEAN)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $func$
BEGIN
    RETURN QUERY SELECT 'deals_table_exists'::TEXT,
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'deals');
    RETURN QUERY SELECT 'can_access_deal_exists'::TEXT,
        EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'can_access_deal');
    RETURN QUERY SELECT 'generate_deal_number_works'::TEXT,
        public.generate_deal_number() LIKE 'DL-%';
    RETURN QUERY SELECT 'stage_logs_table_exists'::TEXT,
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'stage_logs');
    RETURN QUERY SELECT 'assignment_logs_table_exists'::TEXT,
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'assignment_logs');
    RETURN QUERY SELECT 'deal_events_table_exists'::TEXT,
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'deal_events');
    RETURN QUERY SELECT 'won_trigger_exists'::TEXT,
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_deals_won');
    RETURN QUERY SELECT 'lost_trigger_exists'::TEXT,
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_deals_lost');
END;
$func$;

COMMENT ON FUNCTION public.verify_core_deals_seed() IS 'Manual verification helper. Run: SELECT * FROM public.verify_core_deals_seed();';


-- =============================================================================
-- END: 004_core_deals.sql
-- =============================================================================
