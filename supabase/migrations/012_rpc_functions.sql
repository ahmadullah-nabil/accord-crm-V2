-- =============================================================================
-- ACCORD CRM V1 — FINAL SQL PACKAGE
-- Migration: 012_rpc_functions
-- Description: RPC workflow functions called directly by the React frontend
--              via supabase.rpc(...). These wrap a session-parameter SET
--              LOCAL and the corresponding UPDATE on deals in a single
--              atomic SECURITY DEFINER function call, which is required
--              because the stage_logs/assignment_logs triggers in
--              004_core_deals.sql read crm.stage_change_reason and
--              crm.assignment_change_reason from the session — a plain
--              REST PATCH from the Supabase client has no way to set a
--              session-local parameter before its UPDATE, so these RPCs
--              are the only supported way to change stage or assignment.
--
--              Authorization is enforced explicitly inside each function via
--              can_access_deal() and has_permission() — these functions do
--              NOT rely on the deals table's own RLS UPDATE policy, because
--              SECURITY DEFINER functions execute with the privileges of
--              the function owner and therefore bypass RLS entirely. Each
--              function re-implements the equivalent authorization check
--              before performing its UPDATE.
--
--              Must run after 001–011.
-- =============================================================================


-- =============================================================================
-- FUNCTION: rpc_change_deal_stage(p_deal_id, p_new_stage_id, p_remark)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.rpc_change_deal_stage(
    p_deal_id       UUID,
    p_new_stage_id  UUID,
    p_remark        TEXT
)
RETURNS public.deals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_deal      public.deals;
    v_actor_id  UUID;
BEGIN
    v_actor_id := public.get_current_crm_user_id();

    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Explicit authorization check — this function bypasses RLS as
    -- SECURITY DEFINER, so the access check that RLS would normally provide
    -- must be re-implemented here.
    IF NOT public.can_access_deal(p_deal_id) THEN
        RAISE EXCEPTION 'You do not have access to this deal.' USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT public.has_permission('pipeline.edit') THEN
        RAISE EXCEPTION 'You do not have permission to edit deals.' USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_remark IS NULL OR trim(p_remark) = '' THEN
        RAISE EXCEPTION 'A remark is required to change a deal''s stage.' USING ERRCODE = 'check_violation';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.deal_stages WHERE id = p_new_stage_id AND is_active = true) THEN
        RAISE EXCEPTION 'Invalid or inactive stage.' USING ERRCODE = 'foreign_key_violation';
    END IF;

    -- Set the session-local parameter the stage_logs trigger reads, then
    -- perform the UPDATE in the same transaction. SET LOCAL is automatically
    -- reset at transaction end regardless of commit/rollback.
    PERFORM set_config('crm.stage_change_reason', trim(p_remark), true);

    UPDATE public.deals
    SET    stage_id   = p_new_stage_id,
           updated_by = v_actor_id,
           updated_at = now()
    WHERE  id = p_deal_id
    RETURNING * INTO v_deal;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Deal not found.' USING ERRCODE = 'no_data_found';
    END IF;

    RETURN v_deal;
END;
$$;

COMMENT ON FUNCTION public.rpc_change_deal_stage(UUID, UUID, TEXT) IS
    'Frontend-facing RPC for stage changes. Wraps SET LOCAL crm.stage_change_reason + UPDATE deals.stage_id in one atomic SECURITY DEFINER call. Re-implements authorization explicitly since SECURITY DEFINER bypasses RLS.';


-- =============================================================================
-- FUNCTION: rpc_reassign_deal(p_deal_id, p_new_assignee_id, p_remark)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.rpc_reassign_deal(
    p_deal_id          UUID,
    p_new_assignee_id  UUID,
    p_remark           TEXT
)
RETURNS public.deals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_deal      public.deals;
    v_actor_id  UUID;
BEGIN
    v_actor_id := public.get_current_crm_user_id();

    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT public.can_access_deal(p_deal_id) THEN
        RAISE EXCEPTION 'You do not have access to this deal.' USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT public.has_permission('pipeline.assign') THEN
        RAISE EXCEPTION 'You do not have permission to reassign deals.' USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_remark IS NULL OR trim(p_remark) = '' THEN
        RAISE EXCEPTION 'A remark is required to reassign a deal.' USING ERRCODE = 'check_violation';
    END IF;

    IF p_new_assignee_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_new_assignee_id AND is_active = true)
    THEN
        RAISE EXCEPTION 'Invalid or inactive user.' USING ERRCODE = 'foreign_key_violation';
    END IF;

    PERFORM set_config('crm.assignment_change_reason', trim(p_remark), true);

    UPDATE public.deals
    SET    assigned_to = p_new_assignee_id,
           updated_by  = v_actor_id,
           updated_at  = now()
    WHERE  id = p_deal_id
    RETURNING * INTO v_deal;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Deal not found.' USING ERRCODE = 'no_data_found';
    END IF;

    RETURN v_deal;
END;
$$;

COMMENT ON FUNCTION public.rpc_reassign_deal(UUID, UUID, TEXT) IS
    'Frontend-facing RPC for deal reassignment. Wraps SET LOCAL crm.assignment_change_reason + UPDATE deals.assigned_to in one atomic SECURITY DEFINER call.';


-- =============================================================================
-- FUNCTION: rpc_mark_deal_won(p_deal_id, p_won_reason_id, p_won_remark, p_final_contract_value, p_contract_duration_months)
-- Wraps setting all Won-related fields and the status transition in one call.
-- The trg_deals_won trigger (004_core_deals.sql) fires on this UPDATE and
-- handles deal_events insertion and customer auto-creation (005_customers.sql).
-- =============================================================================
CREATE OR REPLACE FUNCTION public.rpc_mark_deal_won(
    p_deal_id                    UUID,
    p_won_reason_id              UUID,
    p_won_remark                 TEXT,
    p_final_contract_value       NUMERIC DEFAULT NULL,
    p_contract_duration_months   INTEGER DEFAULT NULL
)
RETURNS public.deals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_deal          public.deals;
    v_actor_id      UUID;
    v_won_status_id UUID;
BEGIN
    v_actor_id := public.get_current_crm_user_id();

    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT public.can_access_deal(p_deal_id) THEN
        RAISE EXCEPTION 'You do not have access to this deal.' USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT public.has_permission('pipeline.edit') THEN
        RAISE EXCEPTION 'You do not have permission to edit deals.' USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_won_remark IS NULL OR trim(p_won_remark) = '' THEN
        RAISE EXCEPTION 'A remark is required to mark a deal Won.' USING ERRCODE = 'check_violation';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.won_reasons WHERE id = p_won_reason_id AND is_active = true) THEN
        RAISE EXCEPTION 'Invalid or inactive won reason.' USING ERRCODE = 'foreign_key_violation';
    END IF;

    v_won_status_id := public.get_status_id('Won');

    -- The pipeline stage is moved to whichever stage has is_won_stage = true
    -- in the same UPDATE, so trg_deals_stage_change also fires correctly —
    -- the stage-change session parameter is set alongside the status change.
    PERFORM set_config('crm.stage_change_reason', 'Deal marked Won: ' || trim(p_won_remark), true);

    UPDATE public.deals
    SET    status_id                 = v_won_status_id,
           stage_id                  = (SELECT id FROM public.deal_stages WHERE is_won_stage = true LIMIT 1),
           won_reason_id             = p_won_reason_id,
           won_remark                = trim(p_won_remark),
           final_contract_value      = p_final_contract_value,
           contract_duration_months  = p_contract_duration_months,
           updated_by                = v_actor_id,
           updated_at                = now()
    WHERE  id = p_deal_id
    RETURNING * INTO v_deal;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Deal not found.' USING ERRCODE = 'no_data_found';
    END IF;

    RETURN v_deal;
END;
$$;

COMMENT ON FUNCTION public.rpc_mark_deal_won(UUID, UUID, TEXT, NUMERIC, INTEGER) IS
    'Frontend-facing RPC to mark a deal Won. Sets stage to the is_won_stage row, status to Won, and all won_* fields in one atomic call. Triggers handle deal_events + customer auto-creation downstream.';


-- =============================================================================
-- FUNCTION: rpc_mark_deal_lost(p_deal_id, p_loss_reason_id, p_loss_remark)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.rpc_mark_deal_lost(
    p_deal_id          UUID,
    p_loss_reason_id   UUID,
    p_loss_remark      TEXT
)
RETURNS public.deals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_deal           public.deals;
    v_actor_id       UUID;
    v_lost_status_id UUID;
BEGIN
    v_actor_id := public.get_current_crm_user_id();

    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT public.can_access_deal(p_deal_id) THEN
        RAISE EXCEPTION 'You do not have access to this deal.' USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT public.has_permission('pipeline.edit') THEN
        RAISE EXCEPTION 'You do not have permission to edit deals.' USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF p_loss_remark IS NULL OR trim(p_loss_remark) = '' THEN
        RAISE EXCEPTION 'A remark is required to mark a deal Lost.' USING ERRCODE = 'check_violation';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.loss_reasons WHERE id = p_loss_reason_id AND is_active = true) THEN
        RAISE EXCEPTION 'Invalid or inactive loss reason.' USING ERRCODE = 'foreign_key_violation';
    END IF;

    v_lost_status_id := public.get_status_id('Lost');

    -- A deal may be Lost from any stage — stage_id is intentionally NOT
    -- modified here. trg_deals_lost reads OLD.stage_id directly to snapshot
    -- lost_at_stage_id, so the stage_logs trigger is not involved in a Lost
    -- transition (no crm.stage_change_reason session parameter is needed).
    UPDATE public.deals
    SET    status_id      = v_lost_status_id,
           loss_reason_id = p_loss_reason_id,
           loss_remark    = trim(p_loss_remark),
           updated_by     = v_actor_id,
           updated_at     = now()
    WHERE  id = p_deal_id
    RETURNING * INTO v_deal;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Deal not found.' USING ERRCODE = 'no_data_found';
    END IF;

    RETURN v_deal;
END;
$$;

COMMENT ON FUNCTION public.rpc_mark_deal_lost(UUID, UUID, TEXT) IS
    'Frontend-facing RPC to mark a deal Lost. A deal may be lost from any stage — stage_id is left unchanged.';


-- =============================================================================
-- FUNCTION: rpc_complete_task(p_task_id)
-- Convenience RPC: marks a task Completed and stamps completed_at/completed_by
-- in one call, satisfying the tasks_completed_requires_timestamp CHECK
-- constraint from 006_tasks.sql without requiring the client to compute the
-- timestamp itself.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.rpc_complete_task(p_task_id UUID)
RETURNS public.tasks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_task     public.tasks;
    v_actor_id UUID;
BEGIN
    v_actor_id := public.get_current_crm_user_id();

    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated.' USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.tasks t
        WHERE  t.id = p_task_id
        AND    (public.can_access_deal(t.deal_id) OR t.assigned_to = v_actor_id)
    ) THEN
        RAISE EXCEPTION 'You do not have access to this task.' USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT public.has_permission('tasks.edit') THEN
        RAISE EXCEPTION 'You do not have permission to edit tasks.' USING ERRCODE = 'insufficient_privilege';
    END IF;

    UPDATE public.tasks
    SET    status       = 'Completed',
           completed_at = now(),
           completed_by = v_actor_id,
           updated_by   = v_actor_id,
           updated_at   = now()
    WHERE  id = p_task_id
    RETURNING * INTO v_task;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Task not found.' USING ERRCODE = 'no_data_found';
    END IF;

    RETURN v_task;
END;
$$;

COMMENT ON FUNCTION public.rpc_complete_task(UUID) IS
    'Frontend-facing RPC to mark a task Completed, satisfying the completed_at NOT NULL CHECK constraint atomically.';


-- =============================================================================
-- VERIFICATION HELPER: verify_full_install()
-- Comprehensive end-to-end check across all 12 migrations. Run this LAST,
-- after 001–012 have all executed, to confirm the full install is sound.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.verify_full_install()
RETURNS TABLE (migration TEXT, check_name TEXT, passed BOOLEAN)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY SELECT '001'::TEXT, 'users_table'::TEXT, EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users');
    RETURN QUERY SELECT '001'::TEXT, 'get_current_crm_user_id_exists'::TEXT, EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_current_crm_user_id');

    RETURN QUERY SELECT '002'::TEXT, 'four_system_roles'::TEXT, (SELECT count(*) = 4 FROM public.roles WHERE is_system_role = true);
    RETURN QUERY SELECT '002'::TEXT, 'permissions_seeded'::TEXT, (SELECT count(*) = 19 FROM public.permissions);
    RETURN QUERY SELECT '002'::TEXT, 'has_permission_exists'::TEXT, EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'has_permission');

    RETURN QUERY SELECT '003'::TEXT, 'six_stages_seeded'::TEXT, (SELECT count(*) = 6 FROM public.deal_stages);
    RETURN QUERY SELECT '003'::TEXT, 'five_statuses_seeded'::TEXT, (SELECT count(*) = 5 FROM public.deal_statuses);

    RETURN QUERY SELECT '004'::TEXT, 'deals_table'::TEXT, EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'deals');
    RETURN QUERY SELECT '004'::TEXT, 'can_access_deal_exists'::TEXT, EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'can_access_deal');
    RETURN QUERY SELECT '004'::TEXT, 'stage_logs_table'::TEXT, EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'stage_logs');

    RETURN QUERY SELECT '005'::TEXT, 'customers_table'::TEXT, EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'customers');
    RETURN QUERY SELECT '005'::TEXT, 'create_customer_trigger_exists'::TEXT, EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_create_customer_on_won');

    RETURN QUERY SELECT '006'::TEXT, 'tasks_table'::TEXT, EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'tasks');

    RETURN QUERY SELECT '007'::TEXT, 'meetings_table'::TEXT, EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'meetings');

    RETURN QUERY SELECT '008'::TEXT, 'documents_table'::TEXT, EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'documents');
    RETURN QUERY SELECT '008'::TEXT, 'notes_table'::TEXT, EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'notes');

    RETURN QUERY SELECT '009'::TEXT, 'deal_timeline_table'::TEXT, EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'deal_timeline');
    RETURN QUERY SELECT '009'::TEXT, 'notifications_table'::TEXT, EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'notifications');

    RETURN QUERY SELECT '010'::TEXT, 'admin_seeded'::TEXT, EXISTS (SELECT 1 FROM public.users WHERE email = 'admin@accordtechnologies.example');

    RETURN QUERY SELECT '011'::TEXT, 'dashboard_kpis_view'::TEXT, EXISTS (SELECT 1 FROM information_schema.views WHERE table_name = 'v_dashboard_kpis');
    RETURN QUERY SELECT '011'::TEXT, 'pipeline_list_view'::TEXT, EXISTS (SELECT 1 FROM information_schema.views WHERE table_name = 'v_pipeline_list');

    RETURN QUERY SELECT '012'::TEXT, 'rpc_change_deal_stage_exists'::TEXT, EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_change_deal_stage');
    RETURN QUERY SELECT '012'::TEXT, 'rpc_reassign_deal_exists'::TEXT, EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_reassign_deal');
    RETURN QUERY SELECT '012'::TEXT, 'rpc_mark_deal_won_exists'::TEXT, EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_mark_deal_won');
    RETURN QUERY SELECT '012'::TEXT, 'rpc_mark_deal_lost_exists'::TEXT, EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_mark_deal_lost');
END;
$$;

COMMENT ON FUNCTION public.verify_full_install() IS 'Comprehensive post-install check across all 12 migrations. Run: SELECT * FROM public.verify_full_install() WHERE passed = false;  -- should return zero rows';


-- =============================================================================
-- END: 012_rpc_functions.sql
-- =============================================================================
