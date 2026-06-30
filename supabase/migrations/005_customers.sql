-- =============================================================================
-- ACCORD CRM V1 — FINAL SQL PACKAGE
-- Migration: 005_customers
-- Description: Customer management layer. Customers are auto-created when a
--              deal's status transitions to Won — never created manually in
--              the normal workflow. customer_modules mirrors deal_modules at
--              the moment of Win.
--              Must run after 001, 002, 003, 004.
-- =============================================================================


-- =============================================================================
-- TABLE: public.customer_number_sequences
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.customer_number_sequences (
    year        INTEGER     NOT NULL,
    last_value  BIGINT      NOT NULL DEFAULT 0,
    CONSTRAINT customer_number_sequences_pkey PRIMARY KEY (year)
);

CREATE OR REPLACE FUNCTION public.generate_customer_number()
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
    INSERT INTO public.customer_number_sequences (year, last_value)
    VALUES (v_year, 1)
    ON CONFLICT (year) DO UPDATE
        SET last_value = customer_number_sequences.last_value + 1
    RETURNING last_value INTO v_next;
    RETURN 'CUST-' || v_year::TEXT || '-' || lpad(v_next::TEXT, 6, '0');
END;
$$;

COMMENT ON FUNCTION public.generate_customer_number() IS 'Atomically generates the next customer number in CUST-YYYY-NNNNNN format.';


-- =============================================================================
-- TABLE: public.customers
-- 1:1 with the source Won deal. Company data is a snapshot copied at Win
-- time, not a live link back to the deal.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.customers (
    id                          UUID            NOT NULL DEFAULT gen_random_uuid(),
    customer_number             VARCHAR(30)     NOT NULL,
    deal_id                     UUID            NOT NULL,

    customer_name               VARCHAR(200)    NOT NULL,
    industry_id                 UUID            NULL,
    website                     VARCHAR(255)    NULL,
    country                     VARCHAR(100)    NULL,
    employee_headcount          INTEGER         NULL CHECK (employee_headcount IS NULL OR employee_headcount > 0),
    current_system              VARCHAR(200)    NULL,

    product_id                  UUID            NULL,
    primary_contact_id          UUID            NULL,
    account_owner_id            UUID            NULL,

    customer_status             VARCHAR(30)     NOT NULL DEFAULT 'Active'
                                    CHECK (customer_status IN ('Active', 'Inactive', 'Churned', 'Suspended')),

    contract_value               NUMERIC(15,2)   NULL CHECK (contract_value IS NULL OR contract_value >= 0),
    contract_duration_months     INTEGER         NULL CHECK (contract_duration_months IS NULL OR contract_duration_months > 0),
    contract_start_date         DATE            NULL,
    contract_end_date           DATE            NULL,

    renewal_date                DATE            NULL,
    renewal_notice_days         INTEGER         NOT NULL DEFAULT 30 CHECK (renewal_notice_days >= 0),
    last_activity_at            TIMESTAMPTZ     NULL,

    notes                       TEXT            NULL,

    created_by                  UUID            NOT NULL,
    updated_by                  UUID            NULL,
    created_at                  TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ     NOT NULL DEFAULT now(),

    is_active                   BOOLEAN         NOT NULL DEFAULT true,
    metadata                    JSONB           NULL,

    CONSTRAINT customers_pkey               PRIMARY KEY (id),
    CONSTRAINT customers_customer_number_uq UNIQUE (customer_number),
    CONSTRAINT customers_deal_id_uq         UNIQUE (deal_id),
    CONSTRAINT customers_name_nonempty      CHECK (trim(customer_name) <> ''),
    CONSTRAINT customers_contract_end_after_start
        CHECK (contract_end_date IS NULL OR contract_start_date IS NULL OR contract_end_date > contract_start_date),

    CONSTRAINT customers_deal_fk            FOREIGN KEY (deal_id)            REFERENCES public.deals (id)         ON DELETE RESTRICT,
    CONSTRAINT customers_industry_fk        FOREIGN KEY (industry_id)        REFERENCES public.industries (id)    ON DELETE SET NULL,
    CONSTRAINT customers_product_fk         FOREIGN KEY (product_id)         REFERENCES public.products (id)      ON DELETE SET NULL,
    CONSTRAINT customers_primary_contact_fk FOREIGN KEY (primary_contact_id) REFERENCES public.deal_contacts (id) ON DELETE SET NULL,
    CONSTRAINT customers_account_owner_fk   FOREIGN KEY (account_owner_id)   REFERENCES public.users (id)         ON DELETE SET NULL,
    CONSTRAINT customers_created_by_fk      FOREIGN KEY (created_by)         REFERENCES public.users (id)         ON DELETE RESTRICT,
    CONSTRAINT customers_updated_by_fk      FOREIGN KEY (updated_by)         REFERENCES public.users (id)         ON DELETE RESTRICT
);

COMMENT ON TABLE  public.customers           IS 'Customer records auto-created on deal Won. 1:1 with the source deal. Company data is a snapshot copied at Win time.';
COMMENT ON COLUMN public.customers.renewal_date IS 'Auto-computed as contract_end_date if NULL. Used for renewal alerts.';

CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_customer_number ON public.customers (customer_number);
CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_deal_id         ON public.customers (deal_id);
CREATE INDEX IF NOT EXISTS idx_customers_customer_name_trgm ON public.customers USING gin (customer_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_customers_account_owner_id   ON public.customers (account_owner_id) WHERE account_owner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_customers_customer_status    ON public.customers (customer_status);
CREATE INDEX IF NOT EXISTS idx_customers_renewal_date       ON public.customers (renewal_date) WHERE renewal_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_customers_renewal_alert
    ON public.customers (renewal_date, renewal_notice_days, customer_status)
    WHERE renewal_date IS NOT NULL AND is_active = true;

DROP TRIGGER IF EXISTS trg_customers_updated_at ON public.customers;
CREATE TRIGGER trg_customers_updated_at BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE OR REPLACE FUNCTION public.set_customer_renewal_date()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.renewal_date IS NULL AND NEW.contract_end_date IS NOT NULL THEN
        NEW.renewal_date := NEW.contract_end_date;
    END IF;
    IF NEW.contract_end_date IS NULL
       AND NEW.contract_start_date IS NOT NULL
       AND NEW.contract_duration_months IS NOT NULL
    THEN
        NEW.contract_end_date := NEW.contract_start_date + (NEW.contract_duration_months * INTERVAL '1 month');
        IF NEW.renewal_date IS NULL THEN
            NEW.renewal_date := NEW.contract_end_date;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_customers_renewal_date ON public.customers;
CREATE TRIGGER trg_customers_renewal_date
    BEFORE INSERT OR UPDATE OF contract_end_date, contract_start_date, contract_duration_months, renewal_date
    ON public.customers
    FOR EACH ROW
    EXECUTE FUNCTION public.set_customer_renewal_date();


-- =============================================================================
-- TABLE: public.customer_modules
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.customer_modules (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    customer_id     UUID            NOT NULL,
    module_id       UUID            NOT NULL,
    added_at        TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT customer_modules_pkey PRIMARY KEY (id),
    CONSTRAINT customer_modules_uq   UNIQUE (customer_id, module_id),

    CONSTRAINT customer_modules_customer_fk FOREIGN KEY (customer_id) REFERENCES public.customers (id) ON DELETE CASCADE,
    CONSTRAINT customer_modules_module_fk   FOREIGN KEY (module_id)   REFERENCES public.modules (id)   ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_customer_modules_customer_id ON public.customer_modules (customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_modules_module_id   ON public.customer_modules (module_id);


-- =============================================================================
-- FUNCTION: create_customer_on_deal_won()
-- Fires AFTER UPDATE on deals when status_id transitions to Won. Copies
-- company data, primary contact, modules, and ownership atomically.
-- Idempotent — a second Won transition on the same deal is a no-op.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.create_customer_on_deal_won()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_won_status_id     UUID;
    v_new_customer_id   UUID;
    v_primary_contact   UUID;
    v_actor_id          UUID;
    v_contract_start    DATE;
    v_contract_end      DATE;
BEGIN
    v_won_status_id := public.get_status_id('Won');

    IF NEW.status_id <> v_won_status_id THEN
        RETURN NEW;
    END IF;
    IF OLD.status_id = v_won_status_id THEN
        RETURN NEW;
    END IF;

    IF EXISTS (SELECT 1 FROM public.customers WHERE deal_id = NEW.id) THEN
        RETURN NEW;
    END IF;

    v_actor_id := public.get_current_crm_user_id();
    IF v_actor_id IS NULL THEN
        v_actor_id := COALESCE(NEW.won_by, NEW.updated_by, NEW.created_by);
    END IF;

    SELECT id INTO v_primary_contact
    FROM   public.deal_contacts
    WHERE  deal_id    = NEW.id
    AND    is_primary = true
    AND    is_active  = true
    LIMIT  1;

    v_contract_start := COALESCE(NEW.won_at::DATE, CURRENT_DATE);
    IF NEW.contract_duration_months IS NOT NULL THEN
        v_contract_end := v_contract_start + (NEW.contract_duration_months * INTERVAL '1 month');
    END IF;

    INSERT INTO public.customers (
        customer_number, deal_id, customer_name, industry_id, website, country,
        employee_headcount, current_system, product_id, primary_contact_id,
        account_owner_id, customer_status, contract_value, contract_duration_months,
        contract_start_date, contract_end_date, created_by
    ) VALUES (
        public.generate_customer_number(),
        NEW.id,
        NEW.company_name,
        NEW.industry_id,
        NEW.website,
        NEW.country,
        NEW.employee_headcount,
        NEW.current_system,
        NEW.product_id,
        v_primary_contact,
        COALESCE(NEW.won_by, NEW.assigned_to, NEW.owner_id),
        'Active',
        NEW.final_contract_value,
        NEW.contract_duration_months,
        v_contract_start,
        v_contract_end,
        COALESCE(v_actor_id, NEW.created_by)
    )
    RETURNING id INTO v_new_customer_id;

    INSERT INTO public.customer_modules (customer_id, module_id)
    SELECT v_new_customer_id, dm.module_id
    FROM   public.deal_modules dm
    WHERE  dm.deal_id = NEW.id
    ON CONFLICT (customer_id, module_id) DO NOTHING;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.create_customer_on_deal_won() IS 'Fires on deals.status_id transition to Won. Creates customers record and copies deal_modules to customer_modules atomically. Idempotent.';

DROP TRIGGER IF EXISTS trg_create_customer_on_won ON public.deals;
CREATE TRIGGER trg_create_customer_on_won
    AFTER UPDATE OF status_id ON public.deals
    FOR EACH ROW
    EXECUTE FUNCTION public.create_customer_on_deal_won();


-- =============================================================================
-- FUNCTION: can_access_customer(p_customer_id UUID)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.can_access_customer(p_customer_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM   public.customers c
        WHERE  c.id = p_customer_id
        AND    (public.is_manager_or_above() OR public.can_access_deal(c.deal_id))
    );
$$;

COMMENT ON FUNCTION public.can_access_customer(UUID) IS 'RLS helper for customer access: Manager+ full access, Executive scoped via the source deal.';


-- =============================================================================
-- ROW-LEVEL SECURITY: customers
-- =============================================================================
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "customers_select_admin_partner_manager"
    ON public.customers FOR SELECT TO authenticated
    USING (public.is_manager_or_above());

CREATE POLICY "customers_select_executive"
    ON public.customers FOR SELECT TO authenticated
    USING (
        public.get_current_user_role() = 'Executive'
        AND public.can_access_deal(deal_id)
    );

CREATE POLICY "customers_insert_admin_partner"
    ON public.customers FOR INSERT TO authenticated
    WITH CHECK (public.is_admin_or_partner() AND public.has_permission('customers.create'));

CREATE POLICY "customers_update_admin_partner"
    ON public.customers FOR UPDATE TO authenticated
    USING  (public.is_admin_or_partner())
    WITH CHECK (public.is_admin_or_partner());

CREATE POLICY "customers_update_manager"
    ON public.customers FOR UPDATE TO authenticated
    USING  (public.get_current_user_role() = 'Manager')
    WITH CHECK (public.get_current_user_role() = 'Manager');

CREATE POLICY "customers_update_executive"
    ON public.customers FOR UPDATE TO authenticated
    USING (
        public.get_current_user_role() = 'Executive'
        AND public.can_access_deal(deal_id)
        AND public.has_permission('customers.edit')
    )
    WITH CHECK (
        public.get_current_user_role() = 'Executive'
        AND public.can_access_deal(deal_id)
        AND public.has_permission('customers.edit')
    );


-- =============================================================================
-- ROW-LEVEL SECURITY: customer_modules
-- =============================================================================
ALTER TABLE public.customer_modules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "customer_modules_select" ON public.customer_modules FOR SELECT TO authenticated
    USING (public.can_access_customer(customer_id));

CREATE POLICY "customer_modules_insert_admin_partner" ON public.customer_modules FOR INSERT TO authenticated
    WITH CHECK (public.is_admin_or_partner());

CREATE POLICY "customer_modules_delete_admin_partner" ON public.customer_modules FOR DELETE TO authenticated
    USING (public.is_admin_or_partner());


-- =============================================================================
-- ROW-LEVEL SECURITY: customer_number_sequences
-- =============================================================================
ALTER TABLE public.customer_number_sequences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "customer_number_sequences_select_admin"
    ON public.customer_number_sequences FOR SELECT TO authenticated
    USING (public.is_admin());


-- =============================================================================
-- END: 005_customers.sql
-- =============================================================================
