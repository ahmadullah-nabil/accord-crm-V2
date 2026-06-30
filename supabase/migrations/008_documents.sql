-- =============================================================================
-- ACCORD CRM V1 — FINAL SQL PACKAGE
-- Migration: 008_documents
-- Description: Document/file attachment metadata per deal, plus the notes
--              table (free-text deal notes). Actual files live in Supabase
--              Storage — this table stores metadata and the Storage object
--              path only.
--              Must run after 001, 002, 003, 004, 005.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.notes (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),

    deal_id         UUID            NOT NULL,
    contact_id      UUID            NULL,

    note_text       TEXT            NOT NULL,
    is_pinned       BOOLEAN         NOT NULL DEFAULT false,

    created_by      UUID            NOT NULL,
    updated_by      UUID            NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    is_active       BOOLEAN         NOT NULL DEFAULT true,

    CONSTRAINT notes_pkey         PRIMARY KEY (id),
    CONSTRAINT notes_text_nonempty CHECK (trim(note_text) <> ''),

    CONSTRAINT notes_deal_fk       FOREIGN KEY (deal_id)    REFERENCES public.deals (id)         ON DELETE CASCADE,
    CONSTRAINT notes_contact_fk    FOREIGN KEY (contact_id) REFERENCES public.deal_contacts (id) ON DELETE SET NULL,
    CONSTRAINT notes_created_by_fk FOREIGN KEY (created_by) REFERENCES public.users (id)         ON DELETE RESTRICT,
    CONSTRAINT notes_updated_by_fk FOREIGN KEY (updated_by) REFERENCES public.users (id)         ON DELETE RESTRICT
);

COMMENT ON TABLE public.notes IS 'Free-text notes per deal. Append-only from a UX perspective.';

CREATE INDEX IF NOT EXISTS idx_notes_deal_id    ON public.notes (deal_id);
CREATE INDEX IF NOT EXISTS idx_notes_contact_id  ON public.notes (contact_id) WHERE contact_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notes_created_at  ON public.notes (deal_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notes_pinned      ON public.notes (deal_id, is_pinned) WHERE is_pinned = true AND is_active = true;

DROP TRIGGER IF EXISTS trg_notes_updated_at ON public.notes;
CREATE TRIGGER trg_notes_updated_at BEFORE UPDATE ON public.notes FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE OR REPLACE FUNCTION public.update_deal_last_activity_on_note()
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

DROP TRIGGER IF EXISTS trg_notes_update_deal_activity ON public.notes;
CREATE TRIGGER trg_notes_update_deal_activity
    AFTER INSERT ON public.notes
    FOR EACH ROW
    EXECUTE FUNCTION public.update_deal_last_activity_on_note();


-- =============================================================================
-- TABLE: public.documents
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.documents (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),

    deal_id         UUID            NOT NULL,

    file_name       VARCHAR(300)    NOT NULL,
    file_path       TEXT            NOT NULL,
    file_size       BIGINT          NULL CHECK (file_size IS NULL OR file_size > 0),
    mime_type       VARCHAR(127)    NULL,
    description     TEXT            NULL,

    uploaded_by     UUID            NOT NULL,
    updated_by      UUID            NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),

    is_active       BOOLEAN         NOT NULL DEFAULT true,

    CONSTRAINT documents_pkey             PRIMARY KEY (id),
    CONSTRAINT documents_file_name_nonempty CHECK (trim(file_name) <> ''),
    CONSTRAINT documents_file_path_nonempty CHECK (trim(file_path) <> ''),

    CONSTRAINT documents_deal_fk        FOREIGN KEY (deal_id)     REFERENCES public.deals (id) ON DELETE CASCADE,
    CONSTRAINT documents_uploaded_by_fk FOREIGN KEY (uploaded_by) REFERENCES public.users (id) ON DELETE RESTRICT,
    CONSTRAINT documents_updated_by_fk  FOREIGN KEY (updated_by)  REFERENCES public.users (id) ON DELETE RESTRICT
);

COMMENT ON TABLE  public.documents           IS 'Document metadata per deal. Files stored in Supabase Storage. file_path is the Storage object path.';
COMMENT ON COLUMN public.documents.file_path IS 'Supabase Storage object path: {bucket}/{deal_id}/{uuid}_{filename}.';

CREATE INDEX IF NOT EXISTS idx_documents_deal_id     ON public.documents (deal_id);
CREATE INDEX IF NOT EXISTS idx_documents_uploaded_by ON public.documents (uploaded_by);
CREATE INDEX IF NOT EXISTS idx_documents_created_at  ON public.documents (deal_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_documents_is_active   ON public.documents (deal_id, is_active);

DROP TRIGGER IF EXISTS trg_documents_updated_at ON public.documents;
CREATE TRIGGER trg_documents_updated_at BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE OR REPLACE FUNCTION public.update_deal_last_activity_on_document()
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

DROP TRIGGER IF EXISTS trg_documents_update_deal_activity ON public.documents;
CREATE TRIGGER trg_documents_update_deal_activity
    AFTER INSERT ON public.documents
    FOR EACH ROW
    EXECUTE FUNCTION public.update_deal_last_activity_on_document();


-- =============================================================================
-- ROW-LEVEL SECURITY: notes
-- =============================================================================
ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notes_select_admin_partner_manager"
    ON public.notes FOR SELECT TO authenticated
    USING (public.is_manager_or_above());

CREATE POLICY "notes_select_executive"
    ON public.notes FOR SELECT TO authenticated
    USING (public.get_current_user_role() = 'Executive' AND public.can_access_deal(deal_id));

CREATE POLICY "notes_insert"
    ON public.notes FOR INSERT TO authenticated
    WITH CHECK (
        public.can_access_deal(deal_id)
        AND public.has_permission('pipeline.edit')
        AND created_by = public.get_current_crm_user_id()
    );

CREATE POLICY "notes_update_admin_partner_manager"
    ON public.notes FOR UPDATE TO authenticated
    USING  (public.is_manager_or_above())
    WITH CHECK (public.is_manager_or_above());

-- Notes are UX-append-only — no Executive UPDATE policy.


-- =============================================================================
-- ROW-LEVEL SECURITY: documents
-- =============================================================================
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "documents_select_admin_partner_manager"
    ON public.documents FOR SELECT TO authenticated
    USING (public.is_manager_or_above());

CREATE POLICY "documents_select_executive"
    ON public.documents FOR SELECT TO authenticated
    USING (public.get_current_user_role() = 'Executive' AND public.can_access_deal(deal_id));

CREATE POLICY "documents_insert"
    ON public.documents FOR INSERT TO authenticated
    WITH CHECK (
        public.can_access_deal(deal_id)
        AND public.has_permission('pipeline.edit')
        AND uploaded_by = public.get_current_crm_user_id()
    );

CREATE POLICY "documents_update_admin_partner_manager"
    ON public.documents FOR UPDATE TO authenticated
    USING  (public.is_manager_or_above())
    WITH CHECK (public.is_manager_or_above());

-- No hard DELETE policy on either table — soft delete via is_active only.


-- =============================================================================
-- END: 008_documents.sql
-- =============================================================================
