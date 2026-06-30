// =============================================================================
// Accord CRM V1 — Dashboard Types
// Mirrors the exact column shapes returned by the 011_views_and_reporting.sql
// views. All fields are nullable where the SQL can return NULL.
// =============================================================================

// ---------------------------------------------------------------------------
// v_dashboard_kpis — single-row aggregate view
// ---------------------------------------------------------------------------
export interface DashboardKpis {
  pipeline_revenue: number;
  won_revenue: number;
  lost_revenue: number;
  pipeline_headcount: number;
  active_deals: number;
  won_deals: number;
  lost_deals: number;
  cancelled_deals: number;
  total_deals: number;
  deals_closing_this_month: number;
  closing_this_month_value: number;
  global_conversion_rate: number;
}

// ---------------------------------------------------------------------------
// v_pipeline_by_stage — one row per active stage
// ---------------------------------------------------------------------------
export interface PipelineByStageRow {
  stage_id: string;
  stage_name: string;
  display_order: number;
  deal_count: number;
  total_value: number;
  total_headcount: number;
  avg_deal_value: number;
  latest_deal_created_at: string | null;
}

// ---------------------------------------------------------------------------
// v_overdue_tasks_summary — single-row aggregate
// ---------------------------------------------------------------------------
export interface OverdueTasksSummary {
  overdue_count: number;
  my_overdue_count: number;
  oldest_overdue_date: string | null;
}

// ---------------------------------------------------------------------------
// v_upcoming_followups_summary — single-row aggregate
// ---------------------------------------------------------------------------
export interface UpcomingFollowupsSummary {
  followup_count: number;
  my_followup_count: number;
  nearest_followup_date: string | null;
}

// ---------------------------------------------------------------------------
// v_deals_closing_this_month — up to 10 rows
// ---------------------------------------------------------------------------
export interface DealClosingRow {
  id: string;
  deal_number: string;
  company_name: string;
  proposal_value: number | null;
  expected_close_date: string;
  stage_name: string;
  priority_name: string | null;
  assigned_to_name: string | null;
  assigned_to_avatar: string | null;
  days_until_close: number;
}

// ---------------------------------------------------------------------------
// v_followup_dashboard — upcoming follow-up tasks
// ---------------------------------------------------------------------------
export interface FollowupTaskRow {
  task_id: string;
  deal_id: string;
  deal_number: string;
  company_name: string;
  task_title: string;
  due_date: string | null;
  is_overdue: boolean;
  follow_up_source_type: string | null;
  task_status: string;
  assignee_id: string | null;
  assignee_name: string | null;
  assignee_avatar: string | null;
  contact_name: string | null;
  deal_stage: string;
  days_until_due: number | null;
  created_at: string;
}

// ---------------------------------------------------------------------------
// deal_timeline — recent activity (direct table query, limited to 10)
// ---------------------------------------------------------------------------
export interface RecentActivityRow {
  id: string;
  deal_id: string;
  event_type: string;
  event_title: string;
  event_description: string | null;
  event_date: string;
  performed_by: string;
  performed_by_name: string;
  performed_by_avatar: string | null;
  reference_table: string | null;
  reference_id: string | null;
  metadata: Record<string, unknown> | null;
  created_at: string;
}

// ---------------------------------------------------------------------------
// Upcoming meetings — direct query on meetings table
// ---------------------------------------------------------------------------
export interface UpcomingMeetingRow {
  id: string;
  deal_id: string;
  title: string;
  meeting_type: string;
  meeting_status: string;
  scheduled_at: string;
  location: string | null;
  meeting_url: string | null;
  company_name: string;
  deal_number: string;
  contact_name: string | null;
}

// ---------------------------------------------------------------------------
// UpcomingTaskRow — returned by fetchUpcomingTasks() in dashboard.service.ts
// ---------------------------------------------------------------------------
export interface UpcomingTaskRow {
  id: string;
  title: string;
  description: string | null;
  priority: string | null;
  status: string;
  due_date: string | null;
  is_overdue: boolean;
  is_follow_up: boolean;
  deal_id: string;
  deal_number: string;
  company_name: string;
  assignee_name: string | null;
  assignee_avatar: string | null;
}
