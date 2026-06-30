// =============================================================================
// Accord CRM V1 — Dashboard Service
// All Supabase queries for the dashboard. Calls 011_views_and_reporting.sql
// views directly. No mock data — live Supabase only.
// =============================================================================

import { supabase } from '@/services/supabase';
import type {
  DashboardKpis,
  PipelineByStageRow,
  OverdueTasksSummary,
  UpcomingFollowupsSummary,
  DealClosingRow,
  FollowupTaskRow,
  RecentActivityRow,
  UpcomingMeetingRow,
  UpcomingTaskRow,
} from '../types/dashboard.types';

// ---------------------------------------------------------------------------
// fetchDashboardKpis
// Queries the v_dashboard_kpis view (011_views_and_reporting.sql).
// Returns a single aggregate row — all KPI card values in one round-trip.
// RLS on the underlying deals/tasks tables automatically scopes by role.
// ---------------------------------------------------------------------------
export async function fetchDashboardKpis(): Promise<DashboardKpis> {
  const { data, error } = await supabase
    .from('v_dashboard_kpis')
    .select('*')
    .single();

  if (error) throw error;
  if (!data) throw new Error('Dashboard KPIs returned no data');

  return data as DashboardKpis;
}

// ---------------------------------------------------------------------------
// fetchPipelineByStage
// Queries v_pipeline_by_stage — deal counts and values per active stage.
// Used by the Pipeline by Stage horizontal bar chart.
// ---------------------------------------------------------------------------
export async function fetchPipelineByStage(): Promise<PipelineByStageRow[]> {
  const { data, error } = await supabase
    .from('v_pipeline_by_stage')
    .select('*')
    .order('display_order', { ascending: true });

  if (error) throw error;
  return (data ?? []) as PipelineByStageRow[];
}

// ---------------------------------------------------------------------------
// fetchOverdueTasksSummary
// Queries v_overdue_tasks_summary — single aggregate row.
// ---------------------------------------------------------------------------
export async function fetchOverdueTasksSummary(): Promise<OverdueTasksSummary> {
  const { data, error } = await supabase
    .from('v_overdue_tasks_summary')
    .select('*')
    .single();

  if (error) throw error;
  if (!data) return { overdue_count: 0, my_overdue_count: 0, oldest_overdue_date: null };
  return data as OverdueTasksSummary;
}

// ---------------------------------------------------------------------------
// fetchUpcomingFollowupsSummary
// Queries v_upcoming_followups_summary — single aggregate row.
// ---------------------------------------------------------------------------
export async function fetchUpcomingFollowupsSummary(): Promise<UpcomingFollowupsSummary> {
  const { data, error } = await supabase
    .from('v_upcoming_followups_summary')
    .select('*')
    .single();

  if (error) throw error;
  if (!data) return { followup_count: 0, my_followup_count: 0, nearest_followup_date: null };
  return data as UpcomingFollowupsSummary;
}

// ---------------------------------------------------------------------------
// fetchDealsClosingThisMonth
// Queries v_deals_closing_this_month — up to 10 deals sorted by close date.
// ---------------------------------------------------------------------------
export async function fetchDealsClosingThisMonth(): Promise<DealClosingRow[]> {
  const { data, error } = await supabase
    .from('v_deals_closing_this_month')
    .select('*')
    .order('expected_close_date', { ascending: true })
    .limit(10);

  if (error) throw error;
  return (data ?? []) as DealClosingRow[];
}

// ---------------------------------------------------------------------------
// fetchUpcomingFollowups
// Queries v_followup_dashboard — tasks with is_follow_up = true, not completed,
// due within 7 days. Max 8 rows for the dashboard panel.
// ---------------------------------------------------------------------------
export async function fetchUpcomingFollowups(): Promise<FollowupTaskRow[]> {
  const { data, error } = await supabase
    .from('v_followup_dashboard')
    .select('*')
    .eq('task_status', 'Open')
    .order('days_until_due', { ascending: true })
    .limit(8);

  if (error) throw error;
  return (data ?? []) as FollowupTaskRow[];
}

// ---------------------------------------------------------------------------
// fetchRecentActivity
// Queries v_deal_timeline_display (defined in 008_timeline.sql) for the
// most recent 10 events across all accessible deals.
// RLS on deal_timeline ensures correct scoping per role.
// ---------------------------------------------------------------------------
export async function fetchRecentActivity(): Promise<RecentActivityRow[]> {
  const { data, error } = await supabase
    .from('v_deal_timeline_display')
    .select('*')
    .order('event_date', { ascending: false })
    .limit(10);

  if (error) throw error;
  return (data ?? []) as RecentActivityRow[];
}

// ---------------------------------------------------------------------------
// fetchUpcomingMeetings
// Direct query on meetings table joined with deals.
// Returns meetings scheduled in the next 7 days, not cancelled.
// ---------------------------------------------------------------------------
export async function fetchUpcomingMeetings(): Promise<UpcomingMeetingRow[]> {
  const now = new Date().toISOString();
  const sevenDaysOut = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();

  const { data, error } = await supabase
    .from('meetings')
    .select(`
      id,
      title,
      meeting_type,
      meeting_status,
      scheduled_at,
      location,
      meeting_url,
      deal_id,
      deals!inner (
        deal_number,
        company_name
      ),
      deal_contacts (
        full_name
      )
    `)
    .neq('meeting_status', 'Cancelled')
    .gte('scheduled_at', now)
    .lte('scheduled_at', sevenDaysOut)
    .eq('is_active', true)
    .order('scheduled_at', { ascending: true })
    .limit(6);

  if (error) throw error;

  return (data ?? []).map((m: any) => ({
    id: m.id,
    deal_id: m.deal_id,
    title: m.title,
    meeting_type: m.meeting_type,
    meeting_status: m.meeting_status,
    scheduled_at: m.scheduled_at,
    location: m.location,
    meeting_url: m.meeting_url,
    company_name: m.deals?.company_name ?? '',
    deal_number: m.deals?.deal_number ?? '',
    contact_name: m.deal_contacts?.full_name ?? null,
  })) as UpcomingMeetingRow[];
}

// ---------------------------------------------------------------------------
// fetchUpcomingTasks
// Direct query on tasks table — open tasks due in the next 14 days,
// assigned to the current user. Max 8 rows for the dashboard panel.
// RLS auto-scopes to current user's accessible deals.
// ---------------------------------------------------------------------------
export async function fetchUpcomingTasks(): Promise<UpcomingTaskRow[]> {
  const today = new Date().toISOString().split('T')[0];
  const fourteenDays = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000)
    .toISOString()
    .split('T')[0];

  const { data, error } = await supabase
    .from('tasks')
    .select(`
      id,
      title,
      description,
      priority,
      status,
      due_date,
      is_overdue,
      is_follow_up,
      deal_id,
      deals!inner (
        deal_number,
        company_name
      ),
      users!tasks_assigned_to_fkey (
        full_name,
        avatar_url
      )
    `)
    .in('status', ['Open', 'In Progress'])
    .eq('is_active', true)
    .gte('due_date', today)
    .lte('due_date', fourteenDays)
    .order('due_date', { ascending: true })
    .limit(8);

  if (error) throw error;

  return (data ?? []).map((t: any) => ({
    id: t.id,
    title: t.title,
    description: t.description,
    priority: t.priority,
    status: t.status,
    due_date: t.due_date,
    is_overdue: t.is_overdue,
    is_follow_up: t.is_follow_up,
    deal_id: t.deal_id,
    deal_number: t.deals?.deal_number ?? '',
    company_name: t.deals?.company_name ?? '',
    assignee_name: t.users?.full_name ?? null,
    assignee_avatar: t.users?.avatar_url ?? null,
  }));
}
