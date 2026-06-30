-- =============================================================================
-- ACCORD CRM V1 — FINAL SQL PACKAGE
-- Migration: 009_notifications
-- Description: Two cross-cutting, event-driven concerns that both consume
--              events from every preceding table and therefore must run last
--              among the domain tables:
--                1. public.deal_timeline — the unified immutable activity
--                   feed for the Deal Detail screen (13 event types).
--                2. public.notifications — in-app notification system.
--              Must run after 001, 002, 003, 004, 005, 006, 007, 008.
-- =============================================================================


-- =============================================================================
-- ══════════════════════════════════════════════════════════════════════════
-- PART 1 OF 2: DEAL TIMELINE
-- ══════════════════════════════════════════════════════════════════════════
-- =============================================================================

-- =============================================================================
-- TABLE: public.deal_timeline
-- The single source of truth for the Deal Detail activity feed. Append-only.
-- Populated exclusively by triggers below — never by application code.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.deal_timeline (
    id                  UUID            NOT NULL DEFAULT gen_random_uuid(),
    deal_id             UUID            NOT NULL,

    event_type          VARCHAR(60)     NOT NULL
                            CHECK (event_type IN (
                                'deal_created', 'stage_changed', 'assignment_changed',
                                'call_logged', 'meeting_logged', 'task_created', 'task_completed',
                                'note_added', 'document_uploaded',
                                'deal_won', 'deal_lost', 'deal_cancelled', 'customer_created'
                            )),

    event_title         VARCHAR(300)    NOT NULL,
    event_description   TEXT            NULL,
    event_date          TIMESTAMPTZ     NOT NULL,

    performed_by        UUID            NOT NULL,

    reference_table     VARCHAR(60)     NULL,
    reference_id        UUID            NULL,

    metadata            JSONB           NULL,

    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT deal_timeline_pkey         PRIMARY KEY (id),
    CONSTRAINT deal_timeline_title_nonempty CHECK (trim(event_title) <> ''),

    CONSTRAINT deal_timeline_deal_fk        FOREIGN KEY (deal_id)      REFERENCES public.deals (id) ON DELETE CASCADE,
    CONSTRAINT deal_timeline_performed_by_fk FOREIGN KEY (performed_by) REFERENCES public.users (id) ON DELETE RESTRICT
);

COMMENT ON TABLE public.deal_timeline IS 'Unified immutable event stream per deal. Append-only. Populated exclusively by triggers.';

CREATE INDEX IF NOT EXISTS idx_timeline_deal_id_event_date     ON public.deal_timeline (deal_id, event_date DESC);
CREATE INDEX IF NOT EXISTS idx_timeline_deal_event_type        ON public.deal_timeline (deal_id, event_type);
CREATE INDEX IF NOT EXISTS idx_timeline_performed_by           ON public.deal_timeline (performed_by);
CREATE INDEX IF NOT EXISTS idx_timeline_reference               ON public.deal_timeline (reference_table, reference_id) WHERE reference_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_timeline_terminal_events
    ON public.deal_timeline (event_type, event_date DESC) WHERE event_type IN ('deal_won', 'deal_lost', 'deal_cancelled');
CREATE INDEX IF NOT EXISTS idx_timeline_created_at_brin ON public.deal_timeline USING brin (created_at);

CREATE OR REPLACE FUNCTION public.enforce_timeline_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RAISE EXCEPTION 'deal_timeline is immutable. UPDATE and DELETE are permanently prohibited.'
    USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_deal_timeline_immutable ON public.deal_timeline;
CREATE TRIGGER trg_deal_timeline_immutable
    BEFORE UPDATE OR DELETE ON public.deal_timeline
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_timeline_immutability();

CREATE OR REPLACE FUNCTION public.append_timeline_event(
    p_deal_id           UUID,
    p_event_type        TEXT,
    p_event_title       TEXT,
    p_event_description TEXT,
    p_event_date        TIMESTAMPTZ,
    p_performed_by      UUID,
    p_reference_table   TEXT  DEFAULT NULL,
    p_reference_id      UUID  DEFAULT NULL,
    p_metadata          JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO public.deal_timeline (
        deal_id, event_type, event_title, event_description, event_date,
        performed_by, reference_table, reference_id, metadata
    ) VALUES (
        p_deal_id, p_event_type, p_event_title, p_event_description, p_event_date,
        p_performed_by, p_reference_table, p_reference_id, p_metadata
    )
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.append_timeline_event IS 'Central timeline insertion function. All trigger functions below call this.';

-- 1. Deal Created
CREATE OR REPLACE FUNCTION public.tl_deal_created()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor_name TEXT; v_stage_name TEXT;
BEGIN
    SELECT full_name INTO v_actor_name FROM public.users WHERE id = NEW.created_by;
    SELECT name INTO v_stage_name FROM public.deal_stages WHERE id = NEW.stage_id;
    PERFORM public.append_timeline_event(
        NEW.id, 'deal_created', 'Deal Created',
        'Deal created by ' || COALESCE(v_actor_name, 'Unknown') || ' for ' || NEW.company_name,
        NEW.created_at, NEW.created_by, 'deals', NEW.id,
        jsonb_build_object('company_name', NEW.company_name, 'stage', v_stage_name, 'deal_number', NEW.deal_number)
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tl_deal_created ON public.deals;
CREATE TRIGGER trg_tl_deal_created AFTER INSERT ON public.deals FOR EACH ROW EXECUTE FUNCTION public.tl_deal_created();

-- 2. Stage Changed
CREATE OR REPLACE FUNCTION public.tl_stage_changed()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor_name TEXT; v_from TEXT; v_to TEXT;
BEGIN
    IF NEW.from_stage_id IS NULL AND NEW.change_reason = 'Deal created' THEN RETURN NEW; END IF;
    SELECT full_name INTO v_actor_name FROM public.users WHERE id = NEW.changed_by;
    SELECT name INTO v_from FROM public.deal_stages WHERE id = NEW.from_stage_id;
    SELECT name INTO v_to   FROM public.deal_stages WHERE id = NEW.to_stage_id;
    PERFORM public.append_timeline_event(
        NEW.deal_id, 'stage_changed', 'Stage Changed',
        'Stage changed from ' || COALESCE(v_from, '—') || ' → ' || COALESCE(v_to, 'Unknown') || ' by ' || COALESCE(v_actor_name, 'Unknown'),
        NEW.changed_at, NEW.changed_by, 'stage_logs', NEW.id,
        jsonb_build_object('from_stage', v_from, 'to_stage', v_to, 'remark', NEW.change_reason)
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tl_stage_changed ON public.stage_logs;
CREATE TRIGGER trg_tl_stage_changed AFTER INSERT ON public.stage_logs FOR EACH ROW EXECUTE FUNCTION public.tl_stage_changed();

-- 3. Assignment Changed
CREATE OR REPLACE FUNCTION public.tl_assignment_changed()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor_name TEXT; v_from_name TEXT; v_to_name TEXT;
BEGIN
    SELECT full_name INTO v_actor_name FROM public.users WHERE id = NEW.changed_by;
    SELECT full_name INTO v_from_name  FROM public.users WHERE id = NEW.from_user_id;
    SELECT full_name INTO v_to_name    FROM public.users WHERE id = NEW.to_user_id;
    PERFORM public.append_timeline_event(
        NEW.deal_id, 'assignment_changed', 'Deal Reassigned',
        'Deal reassigned from ' || COALESCE(v_from_name, 'Unassigned') || ' to ' || COALESCE(v_to_name, 'Unassigned') || ' by ' || COALESCE(v_actor_name, 'Unknown'),
        NEW.changed_at, NEW.changed_by, 'assignment_logs', NEW.id,
        jsonb_build_object('from_user', v_from_name, 'to_user', v_to_name, 'remark', NEW.change_reason)
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tl_assignment_changed ON public.assignment_logs;
CREATE TRIGGER trg_tl_assignment_changed AFTER INSERT ON public.assignment_logs FOR EACH ROW EXECUTE FUNCTION public.tl_assignment_changed();

-- 4. Task Created
CREATE OR REPLACE FUNCTION public.tl_task_created()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor_name TEXT; v_assignee_name TEXT;
BEGIN
    SELECT full_name INTO v_actor_name    FROM public.users WHERE id = NEW.created_by;
    SELECT full_name INTO v_assignee_name FROM public.users WHERE id = NEW.assigned_to;
    PERFORM public.append_timeline_event(
        NEW.deal_id, 'task_created', 'Task Created',
        'Task "' || NEW.title || '" created by ' || COALESCE(v_actor_name, 'Unknown')
            || CASE WHEN v_assignee_name IS NOT NULL THEN ' and assigned to ' || v_assignee_name ELSE '' END,
        NEW.created_at, NEW.created_by, 'tasks', NEW.id,
        jsonb_build_object('title', NEW.title, 'priority', NEW.priority, 'status', NEW.status, 'due_date', NEW.due_date, 'is_follow_up', NEW.is_follow_up)
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tl_task_created ON public.tasks;
CREATE TRIGGER trg_tl_task_created AFTER INSERT ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.tl_task_created();

-- 5. Task Completed
CREATE OR REPLACE FUNCTION public.tl_task_completed()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor_name TEXT;
BEGIN
    IF NEW.status <> 'Completed' OR OLD.status = 'Completed' THEN RETURN NEW; END IF;
    SELECT full_name INTO v_actor_name FROM public.users WHERE id = COALESCE(NEW.completed_by, NEW.updated_by);
    PERFORM public.append_timeline_event(
        NEW.deal_id, 'task_completed', 'Task Completed',
        'Task "' || NEW.title || '" marked complete by ' || COALESCE(v_actor_name, 'Unknown'),
        COALESCE(NEW.completed_at, now()), COALESCE(NEW.completed_by, NEW.updated_by, NEW.created_by), 'tasks', NEW.id,
        jsonb_build_object('title', NEW.title, 'status', NEW.status)
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tl_task_completed ON public.tasks;
CREATE TRIGGER trg_tl_task_completed
    AFTER UPDATE OF status ON public.tasks
    FOR EACH ROW
    WHEN (NEW.status = 'Completed' AND OLD.status <> 'Completed')
    EXECUTE FUNCTION public.tl_task_completed();

-- 6. Meeting Logged
CREATE OR REPLACE FUNCTION public.tl_meeting_logged()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor_name TEXT; v_contact_name TEXT;
BEGIN
    SELECT full_name INTO v_actor_name   FROM public.users WHERE id = NEW.created_by;
    SELECT full_name INTO v_contact_name FROM public.deal_contacts WHERE id = NEW.contact_id;
    PERFORM public.append_timeline_event(
        NEW.deal_id, 'meeting_logged', 'Meeting Scheduled',
        'Meeting "' || NEW.title || '" scheduled by ' || COALESCE(v_actor_name, 'Unknown')
            || CASE WHEN v_contact_name IS NOT NULL THEN ' with ' || v_contact_name ELSE '' END,
        NEW.scheduled_at, NEW.created_by, 'meetings', NEW.id,
        jsonb_build_object('title', NEW.title, 'meeting_type', NEW.meeting_type, 'meeting_status', NEW.meeting_status, 'location', NEW.location)
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tl_meeting_logged ON public.meetings;
CREATE TRIGGER trg_tl_meeting_logged AFTER INSERT ON public.meetings FOR EACH ROW EXECUTE FUNCTION public.tl_meeting_logged();

-- 7. Note Added
CREATE OR REPLACE FUNCTION public.tl_note_added()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor_name TEXT; v_preview TEXT;
BEGIN
    SELECT full_name INTO v_actor_name FROM public.users WHERE id = NEW.created_by;
    v_preview := left(NEW.note_text, 120);
    IF length(NEW.note_text) > 120 THEN v_preview := v_preview || '…'; END IF;
    PERFORM public.append_timeline_event(
        NEW.deal_id, 'note_added', 'Note Added',
        'Note added by ' || COALESCE(v_actor_name, 'Unknown') || ': ' || v_preview,
        NEW.created_at, NEW.created_by, 'notes', NEW.id,
        jsonb_build_object('note_preview', v_preview, 'is_pinned', NEW.is_pinned)
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tl_note_added ON public.notes;
CREATE TRIGGER trg_tl_note_added AFTER INSERT ON public.notes FOR EACH ROW EXECUTE FUNCTION public.tl_note_added();

-- 8. Document Uploaded
CREATE OR REPLACE FUNCTION public.tl_document_uploaded()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor_name TEXT;
BEGIN
    SELECT full_name INTO v_actor_name FROM public.users WHERE id = NEW.uploaded_by;
    PERFORM public.append_timeline_event(
        NEW.deal_id, 'document_uploaded', 'Document Uploaded',
        '"' || NEW.file_name || '" uploaded by ' || COALESCE(v_actor_name, 'Unknown'),
        NEW.created_at, NEW.uploaded_by, 'documents', NEW.id,
        jsonb_build_object('file_name', NEW.file_name, 'file_size', NEW.file_size, 'mime_type', NEW.mime_type)
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tl_document_uploaded ON public.documents;
CREATE TRIGGER trg_tl_document_uploaded AFTER INSERT ON public.documents FOR EACH ROW EXECUTE FUNCTION public.tl_document_uploaded();

-- 9. Deal Won
CREATE OR REPLACE FUNCTION public.tl_deal_won()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor_name TEXT; v_reason_name TEXT;
BEGIN
    IF NEW.event_type <> 'won' THEN RETURN NEW; END IF;
    SELECT full_name INTO v_actor_name  FROM public.users       WHERE id = NEW.recorded_by;
    SELECT name      INTO v_reason_name FROM public.won_reasons WHERE id = NEW.won_reason_id;
    PERFORM public.append_timeline_event(
        NEW.deal_id, 'deal_won', 'Deal Won',
        'Deal marked Won by ' || COALESCE(v_actor_name, 'Unknown') || CASE WHEN v_reason_name IS NOT NULL THEN ' — ' || v_reason_name ELSE '' END,
        NEW.recorded_at, NEW.recorded_by, 'deal_events', NEW.id,
        jsonb_build_object('won_reason', v_reason_name, 'won_remark', NEW.won_remark, 'final_contract_value', NEW.final_contract_value)
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tl_deal_won ON public.deal_events;
CREATE TRIGGER trg_tl_deal_won AFTER INSERT ON public.deal_events FOR EACH ROW WHEN (NEW.event_type = 'won') EXECUTE FUNCTION public.tl_deal_won();

-- 10. Deal Lost
CREATE OR REPLACE FUNCTION public.tl_deal_lost()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor_name TEXT; v_reason_name TEXT;
BEGIN
    IF NEW.event_type <> 'lost' THEN RETURN NEW; END IF;
    SELECT full_name INTO v_actor_name  FROM public.users        WHERE id = NEW.recorded_by;
    SELECT name      INTO v_reason_name FROM public.loss_reasons WHERE id = NEW.loss_reason_id;
    PERFORM public.append_timeline_event(
        NEW.deal_id, 'deal_lost', 'Deal Lost',
        'Deal marked Lost by ' || COALESCE(v_actor_name, 'Unknown') || CASE WHEN v_reason_name IS NOT NULL THEN ' — Reason: ' || v_reason_name ELSE '' END,
        NEW.recorded_at, NEW.recorded_by, 'deal_events', NEW.id,
        jsonb_build_object('loss_reason', v_reason_name, 'loss_remark', NEW.loss_remark)
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tl_deal_lost ON public.deal_events;
CREATE TRIGGER trg_tl_deal_lost AFTER INSERT ON public.deal_events FOR EACH ROW WHEN (NEW.event_type = 'lost') EXECUTE FUNCTION public.tl_deal_lost();

-- 11. Deal Cancelled
CREATE OR REPLACE FUNCTION public.tl_deal_cancelled()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_cancelled_status_id UUID; v_actor_id UUID; v_actor_name TEXT;
BEGIN
    v_cancelled_status_id := public.get_status_id('Cancelled');
    IF NEW.status_id <> v_cancelled_status_id THEN RETURN NEW; END IF;
    IF OLD.status_id = v_cancelled_status_id THEN RETURN NEW; END IF;
    v_actor_id := COALESCE(public.get_current_crm_user_id(), NEW.updated_by, NEW.created_by);
    SELECT full_name INTO v_actor_name FROM public.users WHERE id = v_actor_id;
    PERFORM public.append_timeline_event(
        NEW.id, 'deal_cancelled', 'Deal Cancelled',
        'Deal cancelled by ' || COALESCE(v_actor_name, 'Unknown'),
        now(), v_actor_id, 'deals', NEW.id,
        jsonb_build_object('deal_number', NEW.deal_number, 'company_name', NEW.company_name)
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tl_deal_cancelled ON public.deals;
CREATE TRIGGER trg_tl_deal_cancelled AFTER UPDATE OF status_id ON public.deals FOR EACH ROW EXECUTE FUNCTION public.tl_deal_cancelled();

-- 12. Call Logged — stub function defined now; calls table does not exist in
-- this 12-file package (no dedicated calls migration was requested), so this
-- trigger function is defined for completeness but is never wired to a
-- trigger. If a calls table is added in a future migration, register:
--   CREATE TRIGGER trg_tl_call_logged AFTER INSERT ON public.calls
--   FOR EACH ROW EXECUTE FUNCTION public.tl_call_logged();
CREATE OR REPLACE FUNCTION public.tl_call_logged()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM public.append_timeline_event(
        NEW.deal_id, 'call_logged', 'Call Logged',
        'Call logged', NEW.created_at, NEW.created_by, 'calls', NEW.id, NULL
    );
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.tl_call_logged() IS 'Defined for forward-compatibility. Not wired to a trigger in this package — no calls table is created by 001–012.';

-- 13. Customer Created
CREATE OR REPLACE FUNCTION public.tl_customer_created()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_actor_name TEXT;
BEGIN
    SELECT full_name INTO v_actor_name FROM public.users WHERE id = NEW.created_by;
    PERFORM public.append_timeline_event(
        NEW.deal_id, 'customer_created', 'Customer Created',
        'Customer record created for ' || NEW.customer_name || ' by ' || COALESCE(v_actor_name, 'System'),
        NEW.created_at, NEW.created_by, 'customers', NEW.id,
        jsonb_build_object('company_name', NEW.customer_name, 'customer_number', NEW.customer_number, 'contract_value', NEW.contract_value)
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tl_customer_created ON public.customers;
CREATE TRIGGER trg_tl_customer_created AFTER INSERT ON public.customers FOR EACH ROW EXECUTE FUNCTION public.tl_customer_created();


-- =============================================================================
-- ROW-LEVEL SECURITY: deal_timeline
-- =============================================================================
ALTER TABLE public.deal_timeline ENABLE ROW LEVEL SECURITY;

CREATE POLICY "deal_timeline_select_admin_partner_manager"
    ON public.deal_timeline FOR SELECT TO authenticated USING (public.is_manager_or_above());

CREATE POLICY "deal_timeline_select_executive"
    ON public.deal_timeline FOR SELECT TO authenticated
    USING (public.get_current_user_role() = 'Executive' AND public.can_access_deal(deal_id));

CREATE POLICY "deal_timeline_update_denied" ON public.deal_timeline FOR UPDATE TO authenticated USING (false);
CREATE POLICY "deal_timeline_delete_denied" ON public.deal_timeline FOR DELETE TO authenticated USING (false);

-- No INSERT policy — service-role triggers only.


-- =============================================================================
-- VIEW: v_deal_timeline_display
-- Enriches timeline rows with the actor's name and avatar to avoid a second
-- query in the frontend Activity Feed.
-- =============================================================================
CREATE OR REPLACE VIEW public.v_deal_timeline_display AS
SELECT
    dt.id, dt.deal_id, dt.event_type, dt.event_title, dt.event_description, dt.event_date,
    dt.performed_by, u.full_name AS performed_by_name, u.avatar_url AS performed_by_avatar,
    dt.reference_table, dt.reference_id, dt.metadata, dt.created_at
FROM   public.deal_timeline dt
JOIN   public.users u ON u.id = dt.performed_by
ORDER  BY dt.event_date DESC;

COMMENT ON VIEW public.v_deal_timeline_display IS 'Timeline rows enriched with actor name/avatar. Primary data source for the Deal Detail Activity Feed.';


-- =============================================================================
-- ══════════════════════════════════════════════════════════════════════════
-- PART 2 OF 2: NOTIFICATIONS
-- ══════════════════════════════════════════════════════════════════════════
-- =============================================================================


CREATE TABLE IF NOT EXISTS public.notifications (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),

    user_id         UUID            NOT NULL,           -- recipient

    notification_type VARCHAR(40)   NOT NULL
                        CHECK (notification_type IN (
                            'deal_assigned',
                            'task_assigned',
                            'task_due_soon',
                            'task_overdue',
                            'meeting_reminder',
                            'deal_won',
                            'deal_lost',
                            'mention'
                        )),

    title           VARCHAR(200)    NOT NULL,
    body            TEXT            NULL,

    reference_table VARCHAR(60)     NULL,               -- e.g. 'deals', 'tasks', 'meetings'
    reference_id    UUID            NULL,

    is_read         BOOLEAN         NOT NULL DEFAULT false,
    read_at         TIMESTAMPTZ     NULL,

    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    CONSTRAINT notifications_pkey         PRIMARY KEY (id),
    CONSTRAINT notifications_title_nonempty CHECK (trim(title) <> ''),
    CONSTRAINT notifications_read_consistency
        CHECK ((is_read = false AND read_at IS NULL) OR (is_read = true AND read_at IS NOT NULL)),

    CONSTRAINT notifications_user_fk FOREIGN KEY (user_id) REFERENCES public.users (id) ON DELETE CASCADE
);

COMMENT ON TABLE  public.notifications              IS 'In-app notifications, one row per user per event. Subscribe via Supabase Realtime on user_id = current user.';
COMMENT ON COLUMN public.notifications.reference_table IS 'Polymorphic source table name (deals, tasks, meetings). No DB FK — app resolves reference_id against reference_table.';

CREATE INDEX IF NOT EXISTS idx_notifications_user_id_unread
    ON public.notifications (user_id, created_at DESC) WHERE is_read = false;
CREATE INDEX IF NOT EXISTS idx_notifications_user_id_all
    ON public.notifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_reference
    ON public.notifications (reference_table, reference_id) WHERE reference_id IS NOT NULL;


-- =============================================================================
-- FUNCTION: create_notification(...)
-- Central insertion helper. All trigger functions below call this.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.create_notification(
    p_user_id         UUID,
    p_notification_type TEXT,
    p_title            TEXT,
    p_body              TEXT DEFAULT NULL,
    p_reference_table  TEXT DEFAULT NULL,
    p_reference_id      UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id UUID;
BEGIN
    -- Never notify a NULL user (e.g. deal has no assignee yet)
    IF p_user_id IS NULL THEN
        RETURN NULL;
    END IF;

    INSERT INTO public.notifications (
        user_id, notification_type, title, body, reference_table, reference_id
    ) VALUES (
        p_user_id, p_notification_type, p_title, p_body, p_reference_table, p_reference_id
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.create_notification IS 'Central notification insertion helper. NULL-safe on p_user_id (no-op).';


-- =============================================================================
-- TRIGGER: notify on deal assignment
-- Fires AFTER UPDATE on deals when assigned_to changes to a non-NULL value.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.notify_deal_assigned()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.assigned_to IS NOT NULL AND NEW.assigned_to IS DISTINCT FROM OLD.assigned_to THEN
        PERFORM public.create_notification(
            NEW.assigned_to,
            'deal_assigned',
            'Deal assigned to you',
            NEW.company_name || ' (' || NEW.deal_number || ')',
            'deals',
            NEW.id
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_deals_notify_assigned ON public.deals;
CREATE TRIGGER trg_deals_notify_assigned
    AFTER UPDATE OF assigned_to ON public.deals
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_deal_assigned();


-- =============================================================================
-- TRIGGER: notify on task assignment
-- =============================================================================
CREATE OR REPLACE FUNCTION public.notify_task_assigned()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.assigned_to IS NOT NULL
       AND (TG_OP = 'INSERT' OR NEW.assigned_to IS DISTINCT FROM OLD.assigned_to)
    THEN
        PERFORM public.create_notification(
            NEW.assigned_to,
            'task_assigned',
            'Task assigned to you',
            NEW.title,
            'tasks',
            NEW.id
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tasks_notify_assigned ON public.tasks;
CREATE TRIGGER trg_tasks_notify_assigned
    AFTER INSERT OR UPDATE OF assigned_to ON public.tasks
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_task_assigned();


-- =============================================================================
-- TRIGGER: notify on deal won (owner + assignee)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.notify_deal_won()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_won_status_id UUID;
BEGIN
    v_won_status_id := public.get_status_id('Won');

    IF NEW.status_id = v_won_status_id AND OLD.status_id <> v_won_status_id THEN
        PERFORM public.create_notification(
            NEW.owner_id, 'deal_won', 'Deal won! 🏆', NEW.company_name || ' (' || NEW.deal_number || ')', 'deals', NEW.id
        );
        IF NEW.assigned_to IS NOT NULL AND NEW.assigned_to <> NEW.owner_id THEN
            PERFORM public.create_notification(
                NEW.assigned_to, 'deal_won', 'Deal won! 🏆', NEW.company_name || ' (' || NEW.deal_number || ')', 'deals', NEW.id
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_deals_notify_won ON public.deals;
CREATE TRIGGER trg_deals_notify_won
    AFTER UPDATE OF status_id ON public.deals
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_deal_won();


-- =============================================================================
-- FUNCTION: fn_notify_tasks_due_soon()
-- Standalone nightly function (pg_cron target). Notifies assignees of tasks
-- due within 24 hours that have not already been notified today. Avoids
-- duplicate notifications by checking for an existing task_due_soon
-- notification for the same task created within the last 20 hours.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.fn_notify_tasks_due_soon()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER := 0;
    v_task  RECORD;
BEGIN
    FOR v_task IN
        SELECT t.id, t.title, t.assigned_to
        FROM   public.tasks t
        WHERE  t.due_date = CURRENT_DATE + INTERVAL '1 day'
        AND    t.status NOT IN ('Completed', 'Cancelled')
        AND    t.assigned_to IS NOT NULL
        AND    t.is_active = true
        AND NOT EXISTS (
            SELECT 1 FROM public.notifications n
            WHERE n.reference_table = 'tasks'
            AND   n.reference_id    = t.id
            AND   n.notification_type = 'task_due_soon'
            AND   n.created_at > now() - INTERVAL '20 hours'
        )
    LOOP
        PERFORM public.create_notification(
            v_task.assigned_to, 'task_due_soon', 'Task due tomorrow', v_task.title, 'tasks', v_task.id
        );
        v_count := v_count + 1;
    END LOOP;

    RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.fn_notify_tasks_due_soon() IS 'Nightly pg_cron target. Notifies assignees of tasks due tomorrow, de-duplicated per 20-hour window.';


-- =============================================================================
-- ROW-LEVEL SECURITY: notifications
-- Strictly own-row only — no role-based broadening. Even Admin cannot read
-- another user's notification feed through the API.
-- =============================================================================
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notifications_select_own"
    ON public.notifications FOR SELECT TO authenticated
    USING (user_id = public.get_current_crm_user_id());

CREATE POLICY "notifications_update_own"
    ON public.notifications FOR UPDATE TO authenticated
    USING  (user_id = public.get_current_crm_user_id())
    WITH CHECK (user_id = public.get_current_crm_user_id());

CREATE POLICY "notifications_delete_own"
    ON public.notifications FOR DELETE TO authenticated
    USING (user_id = public.get_current_crm_user_id());

-- No INSERT policy for authenticated users — all inserts go through
-- SECURITY DEFINER trigger functions / fn_notify_tasks_due_soon(), which
-- bypass RLS via the service-role execution context.


-- =============================================================================
-- TRIGGER: auto-set read_at on is_read transition
-- =============================================================================
CREATE OR REPLACE FUNCTION public.set_notification_read_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.is_read = true AND OLD.is_read = false THEN
        NEW.read_at := now();
    ELSIF NEW.is_read = false THEN
        NEW.read_at := NULL;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notifications_read_at ON public.notifications;
CREATE TRIGGER trg_notifications_read_at
    BEFORE UPDATE OF is_read ON public.notifications
    FOR EACH ROW
    EXECUTE FUNCTION public.set_notification_read_at();


-- =============================================================================
-- END: 009_notifications.sql
-- =============================================================================
