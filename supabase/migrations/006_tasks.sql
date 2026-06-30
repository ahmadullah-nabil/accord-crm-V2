-- =============================================================================
-- ACCORD CRM V1 — FINAL SQL PACKAGE
-- Migration: 006_tasks
-- Description: Task management linked to deals. Includes follow-up source
--              linkage columns (call/meeting/note traceability) and the
--              is_overdue denormalised field maintained by trigger + a
--              standalone nightly-refresh function for calendar-driven
--              overdue detection (pg_cron target).
--              Must run after 001, 002, 003, 004, 005.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.tasks (
    id                      UUID            NOT NULL DEFAULT gen_random_uuid(),

    deal_id                 UUID            NOT NULL,
    contact_id              UUID            NULL,
    assigned_to             UUID            NULL,

    title                   VARCHAR(300)    NOT NULL,
    description             TEXT            NULL,

    priority                VARCHAR(20)     NOT NULL DEFAULT 'Medium'
                                CHECK (priority IN ('High', 'Medium', 'Low')),
    status                  VARCHAR(20)     NOT NULL DEFAULT 'Open'
                                CHECK (status IN ('Open', 'In Progress', 'Completed', 'Cancelled')),

    due_date                DATE            NULL,
    completed_at            TIMESTAMPTZ     NULL,
    next_followup_date      DATE            NULL,

    is_overdue              BOOLEAN         NOT NULL DEFAULT false,

    is_follow_up            BOOLEAN         NOT NULL DEFAULT false,
    follow_up_source_type   VARCHAR(20)     NULL
                                CHECK (follow_up_source_type IS NULL OR follow_up_source_type IN ('call', 'meeting', 'note')),
    follow_up_source_id     UUID            NULL,

    created_by              UUID            NOT NULL,
    updated_by              UUID            NULL,
    completed_by            UUID            NULL,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),

    is_active               BOOLEAN         NOT NULL DEFAULT true,

    CONSTRAINT tasks_pkey                PRIMARY KEY (id),
    CONSTRAINT tasks_title_nonempty      CHECK (trim(title) <> ''),

    CONSTRAINT tasks_completed_requires_timestamp
        CHECK ((status <> 'Completed') OR (status = 'Completed' AND completed_at IS NOT NULL)),

    CONSTRAINT tasks_followup_source_consistency
        CHECK (
            (follow_up_source_type IS NULL AND follow_up_source_id IS NULL)
            OR (follow_up_source_type IS NOT NULL AND follow_up_source_id IS NOT NULL)
        ),

    CONSTRAINT tasks_deal_fk         FOREIGN KEY (deal_id)      REFERENCES public.deals (id)         ON DELETE CASCADE,
    CONSTRAINT tasks_contact_fk      FOREIGN KEY (contact_id)   REFERENCES public.deal_contacts (id) ON DELETE SET NULL,
    CONSTRAINT tasks_assigned_to_fk  FOREIGN KEY (assigned_to)  REFERENCES public.users (id)         ON DELETE SET NULL,
    CONSTRAINT tasks_created_by_fk   FOREIGN KEY (created_by)   REFERENCES public.users (id)         ON DELETE RESTRICT,
    CONSTRAINT tasks_updated_by_fk   FOREIGN KEY (updated_by)   REFERENCES public.users (id)         ON DELETE RESTRICT,
    CONSTRAINT tasks_completed_by_fk FOREIGN KEY (completed_by) REFERENCES public.users (id)         ON DELETE RESTRICT
);

COMMENT ON TABLE  public.tasks                       IS 'Tasks linked to deals. Includes follow-up source linkage for call/meeting/note traceability.';
COMMENT ON COLUMN public.tasks.is_overdue            IS 'Denormalised. Maintained by trigger on row write + nightly fn_refresh_overdue_tasks() for calendar-driven overdue.';
COMMENT ON COLUMN public.tasks.follow_up_source_type IS 'call | meeting | note. Polymorphic — no DB FK (PostgreSQL has no native polymorphic FK).';

CREATE INDEX IF NOT EXISTS idx_tasks_deal_id        ON public.tasks (deal_id);
CREATE INDEX IF NOT EXISTS idx_tasks_contact_id      ON public.tasks (contact_id) WHERE contact_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_assigned_to     ON public.tasks (assigned_to) WHERE assigned_to IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_status          ON public.tasks (deal_id, status);
CREATE INDEX IF NOT EXISTS idx_tasks_due_date        ON public.tasks (due_date) WHERE due_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_next_followup_date ON public.tasks (next_followup_date) WHERE next_followup_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_overdue         ON public.tasks (is_overdue, due_date) WHERE is_overdue = true AND is_active = true;
CREATE INDEX IF NOT EXISTS idx_tasks_follow_up       ON public.tasks (is_follow_up, due_date) WHERE is_follow_up = true AND is_active = true;
CREATE INDEX IF NOT EXISTS idx_tasks_follow_up_source ON public.tasks (follow_up_source_type, follow_up_source_id) WHERE follow_up_source_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_assigned_open
    ON public.tasks (assigned_to, status) WHERE status IN ('Open', 'In Progress') AND is_active = true;

DROP TRIGGER IF EXISTS trg_tasks_updated_at ON public.tasks;
CREATE TRIGGER trg_tasks_updated_at BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE OR REPLACE FUNCTION public.compute_task_overdue()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    NEW.is_overdue := (
        NEW.due_date IS NOT NULL
        AND NEW.due_date < CURRENT_DATE
        AND NEW.status NOT IN ('Completed', 'Cancelled')
    );
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.compute_task_overdue() IS 'Recomputes is_overdue on every INSERT/UPDATE. Supplemented by fn_refresh_overdue_tasks for calendar-driven overdue without a row write.';

DROP TRIGGER IF EXISTS trg_tasks_compute_overdue ON public.tasks;
CREATE TRIGGER trg_tasks_compute_overdue
    BEFORE INSERT OR UPDATE OF due_date, status ON public.tasks
    FOR EACH ROW
    EXECUTE FUNCTION public.compute_task_overdue();

-- Standalone nightly refresh — call via pg_cron: SELECT cron.schedule(...)
CREATE OR REPLACE FUNCTION public.fn_refresh_overdue_tasks()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_updated INTEGER;
BEGIN
    UPDATE public.tasks
    SET    is_overdue = true, updated_at = now()
    WHERE  due_date IS NOT NULL
    AND    due_date < CURRENT_DATE
    AND    status NOT IN ('Completed', 'Cancelled')
    AND    is_overdue = false;

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    UPDATE public.tasks
    SET    is_overdue = false, updated_at = now()
    WHERE  is_overdue = true
    AND    (due_date IS NULL OR due_date >= CURRENT_DATE OR status IN ('Completed', 'Cancelled'));

    RETURN v_updated;
END;
$$;

COMMENT ON FUNCTION public.fn_refresh_overdue_tasks() IS 'Nightly bulk refresh of is_overdue. Schedule via pg_cron (e.g. daily 01:00 UTC). Returns count of rows newly marked overdue.';

CREATE OR REPLACE FUNCTION public.update_deal_last_activity_on_task()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.deals SET last_activity_at = now(), updated_at = now() WHERE id = NEW.deal_id;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tasks_update_deal_activity ON public.tasks;
CREATE TRIGGER trg_tasks_update_deal_activity
    AFTER INSERT ON public.tasks
    FOR EACH ROW
    EXECUTE FUNCTION public.update_deal_last_activity_on_task();


-- =============================================================================
-- ROW-LEVEL SECURITY: tasks
-- Executive: visible if either can_access_deal() OR assigned_to is them —
-- an Executive can see a task assigned to them even on a deal they do not
-- own (e.g. delegated work), which is the one deliberate broadening beyond
-- the standard can_access_deal() pattern used elsewhere.
-- =============================================================================
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tasks_select_admin_partner_manager"
    ON public.tasks FOR SELECT TO authenticated
    USING (public.is_manager_or_above());

CREATE POLICY "tasks_select_executive"
    ON public.tasks FOR SELECT TO authenticated
    USING (
        public.get_current_user_role() = 'Executive'
        AND (public.can_access_deal(deal_id) OR assigned_to = public.get_current_crm_user_id())
    );

CREATE POLICY "tasks_insert"
    ON public.tasks FOR INSERT TO authenticated
    WITH CHECK (
        public.can_access_deal(deal_id)
        AND public.has_permission('tasks.create')
        AND created_by = public.get_current_crm_user_id()
    );

CREATE POLICY "tasks_update_admin_partner_manager"
    ON public.tasks FOR UPDATE TO authenticated
    USING  (public.is_manager_or_above())
    WITH CHECK (public.is_manager_or_above());

CREATE POLICY "tasks_update_executive"
    ON public.tasks FOR UPDATE TO authenticated
    USING (
        public.get_current_user_role() = 'Executive'
        AND (public.can_access_deal(deal_id) OR assigned_to = public.get_current_crm_user_id())
        AND public.has_permission('tasks.edit')
    )
    WITH CHECK (
        public.get_current_user_role() = 'Executive'
        AND (public.can_access_deal(deal_id) OR assigned_to = public.get_current_crm_user_id())
        AND public.has_permission('tasks.edit')
    );

-- No DELETE policy — tasks are status-transitioned (Cancelled), never deleted.


-- =============================================================================
-- END: 006_tasks.sql
-- =============================================================================
