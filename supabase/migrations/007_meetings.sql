-- =============================================================================
-- ACCORD CRM V1 — FINAL SQL PACKAGE
-- Migration: 007_meetings
-- Description: Meeting scheduling and outcome tracking per deal. Includes
--              contact_id linkage (Gap Analysis amendment).
--              Must run after 001, 002, 003, 004, 005.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.meetings (
    id                  UUID            NOT NULL DEFAULT gen_random_uuid(),

    deal_id             UUID            NOT NULL,
    contact_id          UUID            NULL,
    assigned_to         UUID            NULL,

    meeting_type        VARCHAR(20)     NOT NULL DEFAULT 'Online'
                            CHECK (meeting_type IN ('Online', 'Physical', 'Hybrid')),
    meeting_status       VARCHAR(20)     NOT NULL DEFAULT 'Scheduled'
                            CHECK (meeting_status IN ('Scheduled', 'Completed', 'Cancelled', 'No Show', 'Rescheduled')),

    title               VARCHAR(300)    NOT NULL,
    agenda              TEXT            NULL,
    location            VARCHAR(300)    NULL,
    meeting_url         TEXT            NULL,
    participants        TEXT[]          NULL,

    scheduled_at        TIMESTAMPTZ     NOT NULL,
    started_at          TIMESTAMPTZ     NULL,
    ended_at            TIMESTAMPTZ     NULL,

    summary             TEXT            NULL,
    outcome             TEXT            NULL,
    outcome_recorded_at TIMESTAMPTZ     NULL,

    next_followup_date  DATE            NULL,

    created_by          UUID            NOT NULL,
    updated_by          UUID            NULL,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),

    is_active           BOOLEAN         NOT NULL DEFAULT true,

    CONSTRAINT meetings_pkey         PRIMARY KEY (id),
    CONSTRAINT meetings_title_nonempty CHECK (trim(title) <> ''),
    CONSTRAINT meetings_end_after_start CHECK (ended_at IS NULL OR started_at IS NULL OR ended_at >= started_at),

    CONSTRAINT meetings_deal_fk       FOREIGN KEY (deal_id)     REFERENCES public.deals (id)         ON DELETE CASCADE,
    CONSTRAINT meetings_contact_fk    FOREIGN KEY (contact_id)  REFERENCES public.deal_contacts (id) ON DELETE SET NULL,
    CONSTRAINT meetings_assigned_to_fk FOREIGN KEY (assigned_to) REFERENCES public.users (id)        ON DELETE SET NULL,
    CONSTRAINT meetings_created_by_fk FOREIGN KEY (created_by)  REFERENCES public.users (id)         ON DELETE RESTRICT,
    CONSTRAINT meetings_updated_by_fk FOREIGN KEY (updated_by)  REFERENCES public.users (id)         ON DELETE RESTRICT
);

COMMENT ON TABLE  public.meetings              IS 'Meeting scheduling and outcome tracking per deal. contact_id added by Gap Analysis.';
COMMENT ON COLUMN public.meetings.outcome_recorded_at IS 'Populated when outcome is entered post-meeting. Drives the Awaiting Outcome tab.';

CREATE INDEX IF NOT EXISTS idx_meetings_deal_id        ON public.meetings (deal_id);
CREATE INDEX IF NOT EXISTS idx_meetings_contact_id      ON public.meetings (contact_id) WHERE contact_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_meetings_assigned_to     ON public.meetings (assigned_to) WHERE assigned_to IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_meetings_scheduled_at    ON public.meetings (scheduled_at DESC);
CREATE INDEX IF NOT EXISTS idx_meetings_meeting_status  ON public.meetings (deal_id, meeting_status);
CREATE INDEX IF NOT EXISTS idx_meetings_next_followup_date ON public.meetings (next_followup_date) WHERE next_followup_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_meetings_awaiting_outcome
    ON public.meetings (scheduled_at) WHERE outcome IS NULL AND is_active = true;

DROP TRIGGER IF EXISTS trg_meetings_updated_at ON public.meetings;
CREATE TRIGGER trg_meetings_updated_at BEFORE UPDATE ON public.meetings FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE OR REPLACE FUNCTION public.update_deal_last_activity_on_meeting()
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

DROP TRIGGER IF EXISTS trg_meetings_update_deal_activity ON public.meetings;
CREATE TRIGGER trg_meetings_update_deal_activity
    AFTER INSERT ON public.meetings
    FOR EACH ROW
    EXECUTE FUNCTION public.update_deal_last_activity_on_meeting();

CREATE OR REPLACE FUNCTION public.update_contact_last_contacted_on_meeting()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.contact_id IS NOT NULL THEN
        UPDATE public.deal_contacts
        SET    last_contacted_at = NEW.scheduled_at, updated_at = now()
        WHERE  id = NEW.contact_id
        AND    (last_contacted_at IS NULL OR last_contacted_at < NEW.scheduled_at);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_meetings_update_contact_last_contacted ON public.meetings;
CREATE TRIGGER trg_meetings_update_contact_last_contacted
    AFTER INSERT ON public.meetings
    FOR EACH ROW
    EXECUTE FUNCTION public.update_contact_last_contacted_on_meeting();


-- =============================================================================
-- ROW-LEVEL SECURITY: meetings
-- =============================================================================
ALTER TABLE public.meetings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "meetings_select_admin_partner_manager"
    ON public.meetings FOR SELECT TO authenticated
    USING (public.is_manager_or_above());

CREATE POLICY "meetings_select_executive"
    ON public.meetings FOR SELECT TO authenticated
    USING (public.get_current_user_role() = 'Executive' AND public.can_access_deal(deal_id));

CREATE POLICY "meetings_insert"
    ON public.meetings FOR INSERT TO authenticated
    WITH CHECK (
        public.can_access_deal(deal_id)
        AND public.has_permission('meetings.create')
        AND created_by = public.get_current_crm_user_id()
    );

CREATE POLICY "meetings_update_admin_partner_manager"
    ON public.meetings FOR UPDATE TO authenticated
    USING  (public.is_manager_or_above())
    WITH CHECK (public.is_manager_or_above());

CREATE POLICY "meetings_update_executive_own"
    ON public.meetings FOR UPDATE TO authenticated
    USING (
        public.get_current_user_role() = 'Executive'
        AND public.can_access_deal(deal_id)
        AND created_by = public.get_current_crm_user_id()
    )
    WITH CHECK (
        public.get_current_user_role() = 'Executive'
        AND public.can_access_deal(deal_id)
        AND created_by = public.get_current_crm_user_id()
    );


-- =============================================================================
-- END: 007_meetings.sql
-- =============================================================================
