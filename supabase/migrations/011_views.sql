-- =============================================================================
-- ACCORD CRM V1 — FINAL SQL PACKAGE
-- Migration: 011_views
-- Description: All reporting and dashboard views. Views only — no tables, no
--              materialized views. All views inherit RLS from underlying
--              tables; no SECURITY DEFINER on any view.
--
--              Correction applied (debugging history): v_pipeline_performance
--              originally nested LEAD() (a window function) directly inside
--              AVG() (an aggregate) at the same query level, which PostgreSQL
--              rejects with ERROR 42803: aggregate function calls cannot
--              contain window function calls. Fixed below by computing
--              LEAD() in a derived CTE first, then aggregating over the
--              already-materialised per-row result in a second query level.
--
--              Must run after 001–010.
-- =============================================================================


-- =============================================================================
-- VIEW: v_dashboard_kpis
-- =============================================================================
CREATE OR REPLACE VIEW public.v_dashboard_kpis AS
SELECT
    COALESCE(SUM(CASE WHEN ds.name = 'Active' THEN d.proposal_value ELSE 0 END), 0) AS pipeline_revenue,
    COALESCE(SUM(CASE WHEN ds.name = 'Won'    THEN d.final_contract_value ELSE 0 END), 0) AS won_revenue,
    COALESCE(SUM(CASE WHEN ds.name = 'Lost'   THEN d.proposal_value ELSE 0 END), 0) AS lost_revenue,
    COALESCE(SUM(CASE WHEN ds.name = 'Active' THEN d.employee_headcount ELSE 0 END), 0) AS pipeline_headcount,
    COUNT(*) FILTER (WHERE ds.name = 'Active')    AS active_deals,
    COUNT(*) FILTER (WHERE ds.name = 'Won')       AS won_deals,
    COUNT(*) FILTER (WHERE ds.name = 'Lost')      AS lost_deals,
    COUNT(*) FILTER (WHERE ds.name = 'Cancelled') AS cancelled_deals,
    COUNT(*)                                      AS total_deals,
    COUNT(*) FILTER (
        WHERE ds.name = 'Active'
        AND   date_trunc('month', d.expected_close_date) = date_trunc('month', CURRENT_DATE)
    ) AS deals_closing_this_month,
    COALESCE(SUM(CASE
        WHEN ds.name = 'Active' AND date_trunc('month', d.expected_close_date) = date_trunc('month', CURRENT_DATE)
        THEN d.proposal_value ELSE 0
    END), 0) AS closing_this_month_value,
    CASE
        WHEN COUNT(*) FILTER (WHERE ds.name IN ('Won', 'Lost')) = 0 THEN 0
        ELSE ROUND(100.0 * COUNT(*) FILTER (WHERE ds.name = 'Won') / NULLIF(COUNT(*) FILTER (WHERE ds.name IN ('Won', 'Lost')), 0), 2)
    END AS global_conversion_rate
FROM   public.deals         d
JOIN   public.deal_statuses ds ON ds.id = d.status_id
WHERE  d.is_active = true;

COMMENT ON VIEW public.v_dashboard_kpis IS 'Single-row dashboard KPI summary. RLS scopes to the current user''s accessible deals.';


-- =============================================================================
-- VIEW: v_pipeline_by_stage
-- =============================================================================
CREATE OR REPLACE VIEW public.v_pipeline_by_stage AS
SELECT
    ds.id   AS stage_id,
    ds.name AS stage_name,
    ds.display_order,
    COUNT(d.id)                            AS deal_count,
    COALESCE(SUM(d.proposal_value), 0)     AS total_value,
    COALESCE(SUM(d.employee_headcount), 0) AS total_headcount,
    COALESCE(AVG(d.proposal_value), 0)     AS avg_deal_value
FROM   public.deal_stages ds
LEFT JOIN public.deals d
    ON d.stage_id = ds.id
    AND d.is_active = true
    AND EXISTS (SELECT 1 FROM public.deal_statuses dst WHERE dst.id = d.status_id AND dst.name = 'Active')
WHERE  ds.is_active = true
GROUP  BY ds.id, ds.name, ds.display_order
ORDER  BY ds.display_order ASC;

COMMENT ON VIEW public.v_pipeline_by_stage IS 'Active deal counts and values per pipeline stage.';


-- =============================================================================
-- VIEW: v_pipeline_performance
-- Stage-by-stage performance with average time-in-stage from stage_logs.
--
-- CORRECTED VERSION: LEAD() is computed first inside the stage_periods CTE
-- (a plain per-row window function call, no aggregate wrapping it). The
-- aggregation (AVG) happens in a second, separate query level (stage_time)
-- that consumes the already-materialised per-row durations. This two-step
-- structure is what PostgreSQL requires — window functions must fully
-- evaluate before any aggregate can consume their output.
-- =============================================================================
CREATE OR REPLACE VIEW public.v_pipeline_performance AS
WITH stage_periods AS (
    SELECT
        sl.deal_id,
        sl.to_stage_id AS stage_id,
        sl.changed_at  AS entered_at,
        LEAD(sl.changed_at) OVER (PARTITION BY sl.deal_id ORDER BY sl.changed_at) AS exited_at
    FROM public.stage_logs sl
),
stage_time AS (
    SELECT
        stage_id,
        AVG(EXTRACT(EPOCH FROM (COALESCE(exited_at, now()) - entered_at))) / 86400.0 AS avg_days_in_stage,
        COUNT(DISTINCT deal_id) AS deals_through_stage
    FROM   stage_periods
    GROUP  BY stage_id
)
SELECT
    ds.id   AS stage_id,
    ds.name AS stage_name,
    ds.display_order,
    COUNT(d.id) FILTER (WHERE dst.name = 'Active') AS active_deals,
    COALESCE(SUM(d.proposal_value) FILTER (WHERE dst.name = 'Active'), 0) AS active_value,
    COUNT(d.id) FILTER (WHERE dst.name = 'Won')  AS won_deals,
    COUNT(d.id) FILTER (WHERE dst.name = 'Lost') AS lost_deals,
    COALESCE(st.avg_days_in_stage, 0)   AS avg_days_in_stage,
    COALESCE(st.deals_through_stage, 0) AS deals_through_stage
FROM   public.deal_stages ds
LEFT JOIN public.deals         d   ON d.stage_id = ds.id AND d.is_active = true
LEFT JOIN public.deal_statuses dst ON dst.id = d.status_id
LEFT JOIN stage_time            st  ON st.stage_id = ds.id
WHERE  ds.is_active = true
GROUP  BY ds.id, ds.name, ds.display_order, st.avg_days_in_stage, st.deals_through_stage
ORDER  BY ds.display_order ASC;

COMMENT ON VIEW public.v_pipeline_performance IS 'Pipeline Performance: stage counts, values, avg time-in-stage. LEAD() computed in a CTE before AVG() aggregation — required by PostgreSQL (ERROR 42803 otherwise).';


-- =============================================================================
-- VIEW: v_revenue_over_time
-- =============================================================================
CREATE OR REPLACE VIEW public.v_revenue_over_time AS
SELECT
    date_trunc('month', de.recorded_at) AS month,
    to_char(date_trunc('month', de.recorded_at), 'Mon YYYY') AS month_label,
    COUNT(de.id) AS deals_won,
    COALESCE(SUM(de.final_contract_value), 0) AS won_revenue,
    COALESCE(AVG(de.final_contract_value), 0) AS avg_deal_value
FROM   public.deal_events de
WHERE  de.event_type = 'won'
AND    de.recorded_at >= date_trunc('month', now() - INTERVAL '23 months')
GROUP  BY date_trunc('month', de.recorded_at)
ORDER  BY date_trunc('month', de.recorded_at) ASC;

COMMENT ON VIEW public.v_revenue_over_time IS 'Monthly Won revenue for the last 24 months.';


-- =============================================================================
-- VIEW: v_conversion_global
-- =============================================================================
CREATE OR REPLACE VIEW public.v_conversion_global AS
SELECT
    COUNT(*) AS total_deals,
    COUNT(*) FILTER (WHERE dst.name = 'Won')    AS won_deals,
    COUNT(*) FILTER (WHERE dst.name = 'Lost')   AS lost_deals,
    COUNT(*) FILTER (WHERE dst.name = 'Active') AS active_deals,
    COUNT(*) FILTER (WHERE dst.name IN ('Won', 'Lost')) AS closed_deals,
    CASE
        WHEN COUNT(*) FILTER (WHERE dst.name IN ('Won', 'Lost')) = 0 THEN 0
        ELSE ROUND(100.0 * COUNT(*) FILTER (WHERE dst.name = 'Won') / NULLIF(COUNT(*) FILTER (WHERE dst.name IN ('Won', 'Lost')), 0), 2)
    END AS win_rate_pct,
    COALESCE(SUM(de.final_contract_value), 0) AS total_won_revenue,
    COALESCE(AVG(de.final_contract_value) FILTER (WHERE dst.name = 'Won'), 0) AS avg_won_value
FROM   public.deals d
JOIN   public.deal_statuses dst ON dst.id = d.status_id
LEFT JOIN public.deal_events de ON de.deal_id = d.id AND de.event_type = 'won'
WHERE  d.is_active = true;

COMMENT ON VIEW public.v_conversion_global IS 'Global conversion rate and revenue summary.';


-- =============================================================================
-- VIEW: v_conversion_by_industry
-- =============================================================================
CREATE OR REPLACE VIEW public.v_conversion_by_industry AS
SELECT
    i.id   AS industry_id,
    i.name AS industry_name,
    COUNT(d.id) AS total_deals,
    COUNT(d.id) FILTER (WHERE dst.name = 'Won')    AS won_deals,
    COUNT(d.id) FILTER (WHERE dst.name = 'Lost')   AS lost_deals,
    COUNT(d.id) FILTER (WHERE dst.name = 'Active') AS active_deals,
    CASE
        WHEN COUNT(d.id) FILTER (WHERE dst.name IN ('Won', 'Lost')) = 0 THEN 0
        ELSE ROUND(100.0 * COUNT(d.id) FILTER (WHERE dst.name = 'Won') / NULLIF(COUNT(d.id) FILTER (WHERE dst.name IN ('Won', 'Lost')), 0), 2)
    END AS win_rate_pct,
    COALESCE(SUM(d.proposal_value) FILTER (WHERE dst.name = 'Active'), 0) AS active_pipeline_value,
    COALESCE(SUM(de.final_contract_value), 0) AS total_won_revenue
FROM   public.industries i
LEFT JOIN public.deals         d   ON d.industry_id = i.id AND d.is_active = true
LEFT JOIN public.deal_statuses dst ON dst.id = d.status_id
LEFT JOIN public.deal_events   de  ON de.deal_id = d.id AND de.event_type = 'won'
WHERE  i.is_active = true
GROUP  BY i.id, i.name
ORDER  BY total_deals DESC, win_rate_pct DESC;

COMMENT ON VIEW public.v_conversion_by_industry IS 'Win rate and pipeline metrics per industry.';


-- =============================================================================
-- VIEW: v_conversion_by_module
-- =============================================================================
CREATE OR REPLACE VIEW public.v_conversion_by_module AS
SELECT
    m.id   AS module_id,
    m.name AS module_name,
    p.name AS product_name,
    COUNT(DISTINCT d.id) AS total_deals,
    COUNT(DISTINCT d.id) FILTER (WHERE dst.name = 'Won')    AS won_deals,
    COUNT(DISTINCT d.id) FILTER (WHERE dst.name = 'Lost')   AS lost_deals,
    COUNT(DISTINCT d.id) FILTER (WHERE dst.name = 'Active') AS active_deals,
    CASE
        WHEN COUNT(DISTINCT d.id) FILTER (WHERE dst.name IN ('Won', 'Lost')) = 0 THEN 0
        ELSE ROUND(100.0 * COUNT(DISTINCT d.id) FILTER (WHERE dst.name = 'Won') / NULLIF(COUNT(DISTINCT d.id) FILTER (WHERE dst.name IN ('Won', 'Lost')), 0), 2)
    END AS win_rate_pct,
    COALESCE(SUM(de.final_contract_value), 0) AS total_won_revenue
FROM   public.modules m
JOIN   public.products p ON p.id = m.product_id
LEFT JOIN public.deal_modules  dm  ON dm.module_id = m.id
LEFT JOIN public.deals         d   ON d.id = dm.deal_id AND d.is_active = true
LEFT JOIN public.deal_statuses dst ON dst.id = d.status_id
LEFT JOIN public.deal_events   de  ON de.deal_id = d.id AND de.event_type = 'won'
WHERE  m.is_active = true
GROUP  BY m.id, m.name, p.name
ORDER  BY total_deals DESC, win_rate_pct DESC;

COMMENT ON VIEW public.v_conversion_by_module IS 'Win rate per product module.';


-- =============================================================================
-- VIEW: v_conversion_by_source
-- =============================================================================
CREATE OR REPLACE VIEW public.v_conversion_by_source AS
SELECT
    s.id   AS source_id,
    s.name AS source_name,
    COUNT(d.id) AS total_deals,
    COUNT(d.id) FILTER (WHERE dst.name = 'Won')    AS won_deals,
    COUNT(d.id) FILTER (WHERE dst.name = 'Lost')   AS lost_deals,
    COUNT(d.id) FILTER (WHERE dst.name = 'Active') AS active_deals,
    CASE
        WHEN COUNT(d.id) FILTER (WHERE dst.name IN ('Won', 'Lost')) = 0 THEN 0
        ELSE ROUND(100.0 * COUNT(d.id) FILTER (WHERE dst.name = 'Won') / NULLIF(COUNT(d.id) FILTER (WHERE dst.name IN ('Won', 'Lost')), 0), 2)
    END AS win_rate_pct,
    COALESCE(SUM(d.proposal_value) FILTER (WHERE dst.name = 'Active'), 0) AS active_pipeline_value,
    COALESCE(SUM(de.final_contract_value), 0) AS total_won_revenue
FROM   public.sources s
LEFT JOIN public.deals         d   ON d.source_id = s.id AND d.is_active = true
LEFT JOIN public.deal_statuses dst ON dst.id = d.status_id
LEFT JOIN public.deal_events   de  ON de.deal_id = d.id AND de.event_type = 'won'
WHERE  s.is_active = true
GROUP  BY s.id, s.name
ORDER  BY total_deals DESC, win_rate_pct DESC;

COMMENT ON VIEW public.v_conversion_by_source IS 'Win rate and revenue per lead source.';


-- =============================================================================
-- VIEW: v_user_performance
-- =============================================================================
CREATE OR REPLACE VIEW public.v_user_performance AS
SELECT
    u.id   AS user_id,
    u.full_name,
    u.email,
    u.avatar_url,
    COUNT(DISTINCT d.id) AS deals_created,
    COUNT(DISTINCT d.id) FILTER (WHERE dst.name = 'Won')    AS deals_won,
    COUNT(DISTINCT d.id) FILTER (WHERE dst.name = 'Lost')   AS deals_lost,
    COUNT(DISTINCT d.id) FILTER (WHERE dst.name = 'Active') AS deals_active,
    CASE
        WHEN COUNT(DISTINCT d.id) FILTER (WHERE dst.name IN ('Won', 'Lost')) = 0 THEN 0
        ELSE ROUND(100.0 * COUNT(DISTINCT d.id) FILTER (WHERE dst.name = 'Won') / NULLIF(COUNT(DISTINCT d.id) FILTER (WHERE dst.name IN ('Won', 'Lost')), 0), 2)
    END AS win_rate_pct,
    COALESCE(SUM(de.final_contract_value), 0) AS total_won_revenue,
    COUNT(DISTINCT t.id) AS tasks_created,
    COUNT(DISTINCT t.id) FILTER (WHERE t.status = 'Completed') AS tasks_completed,
    COUNT(DISTINCT t.id) FILTER (WHERE t.is_overdue = true)    AS tasks_overdue,
    COUNT(DISTINCT mt.id) AS meetings_scheduled
FROM   public.users u
LEFT JOIN public.deals         d   ON d.created_by = u.id AND d.is_active = true
LEFT JOIN public.deal_statuses dst ON dst.id = d.status_id
LEFT JOIN public.deal_events   de  ON de.deal_id = d.id AND de.event_type = 'won'
LEFT JOIN public.tasks         t   ON t.created_by = u.id AND t.is_active = true
LEFT JOIN public.meetings      mt  ON mt.created_by = u.id AND mt.is_active = true
WHERE  u.is_active = true
GROUP  BY u.id, u.full_name, u.email, u.avatar_url
ORDER  BY deals_won DESC, total_won_revenue DESC;

COMMENT ON VIEW public.v_user_performance IS 'Per-user deal, task, and meeting performance metrics.';


-- =============================================================================
-- VIEW: v_followup_dashboard
-- =============================================================================
CREATE OR REPLACE VIEW public.v_followup_dashboard AS
SELECT
    t.id AS task_id,
    t.deal_id,
    d.deal_number,
    d.company_name,
    t.title AS task_title,
    t.due_date,
    t.is_overdue,
    t.follow_up_source_type,
    t.status AS task_status,
    u.id   AS assignee_id,
    u.full_name AS assignee_name,
    u.avatar_url AS assignee_avatar,
    dc.full_name AS contact_name,
    ds.name AS deal_stage,
    t.due_date - CURRENT_DATE AS days_until_due,
    t.created_at
FROM   public.tasks t
JOIN   public.deals       d  ON d.id = t.deal_id
JOIN   public.deal_stages ds ON ds.id = d.stage_id
LEFT JOIN public.users         u  ON u.id = t.assigned_to
LEFT JOIN public.deal_contacts dc ON dc.id = t.contact_id
WHERE  t.is_follow_up = true
AND    t.is_active    = true
AND    t.status NOT IN ('Completed', 'Cancelled')
ORDER  BY t.is_overdue DESC, t.due_date ASC;

COMMENT ON VIEW public.v_followup_dashboard IS 'Follow-up tasks with deal and contact context.';


-- =============================================================================
-- VIEW: v_customer_renewals
-- =============================================================================
CREATE OR REPLACE VIEW public.v_customer_renewals AS
SELECT
    c.id AS customer_id,
    c.customer_number,
    c.customer_name,
    c.customer_status,
    c.contract_value,
    c.contract_start_date,
    c.contract_end_date,
    c.renewal_date,
    c.renewal_notice_days,
    c.renewal_date - CURRENT_DATE AS days_until_renewal,
    CASE
        WHEN c.renewal_date < CURRENT_DATE THEN 'Expired'
        WHEN c.renewal_date - CURRENT_DATE <= c.renewal_notice_days THEN 'Action Required'
        WHEN c.renewal_date - CURRENT_DATE <= c.renewal_notice_days * 2 THEN 'Upcoming'
        ELSE 'On Track'
    END AS renewal_alert_status,
    u.full_name AS account_owner_name,
    d.deal_number AS source_deal_number,
    i.name AS industry_name,
    p.name AS product_name,
    dc.full_name AS primary_contact_name
FROM   public.customers c
LEFT JOIN public.users         u  ON u.id = c.account_owner_id
LEFT JOIN public.deals          d  ON d.id = c.deal_id
LEFT JOIN public.industries     i  ON i.id = c.industry_id
LEFT JOIN public.products       p  ON p.id = c.product_id
LEFT JOIN public.deal_contacts  dc ON dc.id = c.primary_contact_id
WHERE  c.is_active = true
AND    c.customer_status <> 'Churned'
AND    c.renewal_date IS NOT NULL
ORDER  BY c.renewal_date ASC;

COMMENT ON VIEW public.v_customer_renewals IS 'Customer renewal pipeline with alert status.';


-- =============================================================================
-- VIEW: v_activity_summary
-- =============================================================================
CREATE OR REPLACE VIEW public.v_activity_summary AS
SELECT
    d.id AS deal_id,
    d.deal_number,
    d.company_name,
    dst.name AS status_name,
    ds.name  AS stage_name,
    COUNT(DISTINCT mt.id)  AS total_meetings,
    COUNT(DISTINCT t.id)   AS total_tasks,
    COUNT(DISTINCT t.id) FILTER (WHERE t.status = 'Completed') AS completed_tasks,
    COUNT(DISTINCT t.id) FILTER (WHERE t.is_overdue = true)    AS overdue_tasks,
    COUNT(DISTINCT n.id)   AS total_notes,
    COUNT(DISTINCT doc.id) AS total_documents,
    d.last_activity_at,
    COUNT(DISTINCT dt.id)  AS timeline_entries
FROM   public.deals d
JOIN   public.deal_statuses dst ON dst.id = d.status_id
JOIN   public.deal_stages   ds  ON ds.id  = d.stage_id
LEFT JOIN public.meetings      mt  ON mt.deal_id  = d.id AND mt.is_active  = true
LEFT JOIN public.tasks         t   ON t.deal_id   = d.id AND t.is_active   = true
LEFT JOIN public.notes         n   ON n.deal_id   = d.id AND n.is_active   = true
LEFT JOIN public.documents     doc ON doc.deal_id = d.id AND doc.is_active = true
LEFT JOIN public.deal_timeline dt  ON dt.deal_id  = d.id
WHERE  d.is_active = true
GROUP  BY d.id, d.deal_number, d.company_name, dst.name, ds.name, d.last_activity_at
ORDER  BY d.last_activity_at DESC NULLS LAST;

COMMENT ON VIEW public.v_activity_summary IS 'Activity counts and health metrics per deal.';


-- =============================================================================
-- VIEW: v_pipeline_list
-- Enriched deal list for the Pipeline screen — all FK-resolved fields in one
-- view, eliminating multiple joins in the frontend query layer.
-- =============================================================================
CREATE OR REPLACE VIEW public.v_pipeline_list AS
SELECT
    d.id, d.deal_number, d.company_name, d.title, d.proposal_value, d.final_contract_value,
    d.contract_duration_months, d.expected_close_date, d.won_at, d.lost_at, d.last_activity_at,
    d.next_followup_date, d.is_active, d.created_at, d.updated_at,
    ds.id AS stage_id, ds.name AS stage_name, ds.display_order AS stage_order, ds.is_won_stage, ds.is_lost_stage,
    dst.id AS status_id, dst.name AS status_name,
    dp.id AS priority_id, dp.name AS priority_name,
    i.id AS industry_id, i.name AS industry_name,
    s.id AS source_id, s.name AS source_name,
    pr.id AS product_id, pr.name AS product_name,
    u_owner.id AS owner_id, u_owner.full_name AS owner_name, u_owner.avatar_url AS owner_avatar,
    u_assigned.id AS assigned_to_id, u_assigned.full_name AS assigned_to_name, u_assigned.avatar_url AS assigned_to_avatar,
    wr.name AS won_reason_name,
    lr.name AS loss_reason_name
FROM   public.deals d
JOIN   public.deal_stages   ds  ON ds.id  = d.stage_id
JOIN   public.deal_statuses dst ON dst.id = d.status_id
LEFT JOIN public.deal_priorities dp         ON dp.id = d.priority_id
LEFT JOIN public.industries      i          ON i.id  = d.industry_id
LEFT JOIN public.sources         s          ON s.id  = d.source_id
LEFT JOIN public.products        pr         ON pr.id = d.product_id
LEFT JOIN public.users           u_owner    ON u_owner.id = d.owner_id
LEFT JOIN public.users           u_assigned ON u_assigned.id = d.assigned_to
LEFT JOIN public.won_reasons     wr         ON wr.id = d.won_reason_id
LEFT JOIN public.loss_reasons    lr         ON lr.id = d.loss_reason_id;

COMMENT ON VIEW public.v_pipeline_list IS 'Enriched deal list view with all FK-resolved fields. Primary data source for the Pipeline list screen.';


-- =============================================================================
-- VIEW: v_role_permission_matrix
-- =============================================================================
CREATE OR REPLACE VIEW public.v_role_permission_matrix AS
SELECT
    r.id AS role_id,
    r.name AS role_name,
    r.is_system_role,
    p.id AS permission_id,
    p.name AS permission_name,
    p.module,
    p.action,
    p.description,
    rp.id IS NOT NULL AS is_granted,
    rp.granted_at
FROM   public.roles r
CROSS JOIN public.permissions p
LEFT JOIN public.role_permissions rp ON rp.role_id = r.id AND rp.permission_id = p.id
WHERE  r.is_active = true
ORDER  BY r.name ASC, p.module ASC, p.action ASC;

COMMENT ON VIEW public.v_role_permission_matrix IS 'Full permission matrix: every role × every permission with grant status.';


-- =============================================================================
-- END: 011_views.sql
-- =============================================================================
