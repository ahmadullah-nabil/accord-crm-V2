// =============================================================================
// Accord CRM V1 — Dashboard Hooks
// TanStack Query v5 wrappers around dashboard.service.ts functions.
// staleTime: 5 minutes for KPIs (dashboard data is not realtime-critical).
// All queries fire in parallel via useQueries or independent useQuery calls.
// =============================================================================

import { useQuery } from '@tanstack/react-query';
import {
  fetchDashboardKpis,
  fetchPipelineByStage,
  fetchOverdueTasksSummary,
  fetchUpcomingFollowupsSummary,
  fetchDealsClosingThisMonth,
  fetchUpcomingFollowups,
  fetchRecentActivity,
  fetchUpcomingMeetings,
  fetchUpcomingTasks,
} from '../services/dashboard.service';

const STALE_5MIN = 5 * 60 * 1000;
const STALE_2MIN = 2 * 60 * 1000;

// ---------------------------------------------------------------------------
// useDashboardKpis — all headline KPI numbers (single view call)
// ---------------------------------------------------------------------------
export function useDashboardKpis() {
  return useQuery({
    queryKey: ['dashboard', 'kpis'],
    queryFn: fetchDashboardKpis,
    staleTime: STALE_5MIN,
    refetchOnWindowFocus: true,
  });
}

// ---------------------------------------------------------------------------
// usePipelineByStage — data for the pipeline bar chart
// ---------------------------------------------------------------------------
export function usePipelineByStage() {
  return useQuery({
    queryKey: ['dashboard', 'pipeline-by-stage'],
    queryFn: fetchPipelineByStage,
    staleTime: STALE_5MIN,
  });
}

// ---------------------------------------------------------------------------
// useOverdueTasksSummary — overdue task count for KPI card
// ---------------------------------------------------------------------------
export function useOverdueTasksSummary() {
  return useQuery({
    queryKey: ['dashboard', 'overdue-tasks-summary'],
    queryFn: fetchOverdueTasksSummary,
    staleTime: STALE_2MIN,
    refetchOnWindowFocus: true,
  });
}

// ---------------------------------------------------------------------------
// useUpcomingFollowupsSummary — follow-up count for KPI card
// ---------------------------------------------------------------------------
export function useUpcomingFollowupsSummary() {
  return useQuery({
    queryKey: ['dashboard', 'followups-summary'],
    queryFn: fetchUpcomingFollowupsSummary,
    staleTime: STALE_2MIN,
    refetchOnWindowFocus: true,
  });
}

// ---------------------------------------------------------------------------
// useDealsClosingThisMonth — closing panel data
// ---------------------------------------------------------------------------
export function useDealsClosingThisMonth() {
  return useQuery({
    queryKey: ['dashboard', 'closing-this-month'],
    queryFn: fetchDealsClosingThisMonth,
    staleTime: STALE_5MIN,
  });
}

// ---------------------------------------------------------------------------
// useUpcomingFollowups — follow-up tasks panel
// ---------------------------------------------------------------------------
export function useUpcomingFollowups() {
  return useQuery({
    queryKey: ['dashboard', 'upcoming-followups'],
    queryFn: fetchUpcomingFollowups,
    staleTime: STALE_2MIN,
    refetchOnWindowFocus: true,
  });
}

// ---------------------------------------------------------------------------
// useRecentActivity — timeline feed panel
// ---------------------------------------------------------------------------
export function useRecentActivity() {
  return useQuery({
    queryKey: ['dashboard', 'recent-activity'],
    queryFn: fetchRecentActivity,
    staleTime: STALE_2MIN,
    refetchOnWindowFocus: true,
  });
}

// ---------------------------------------------------------------------------
// useUpcomingMeetings — meetings panel
// ---------------------------------------------------------------------------
export function useUpcomingMeetings() {
  return useQuery({
    queryKey: ['dashboard', 'upcoming-meetings'],
    queryFn: fetchUpcomingMeetings,
    staleTime: STALE_2MIN,
    refetchOnWindowFocus: true,
  });
}

// ---------------------------------------------------------------------------
// useUpcomingTasks — tasks panel
// ---------------------------------------------------------------------------
export function useUpcomingTasks() {
  return useQuery({
    queryKey: ['dashboard', 'upcoming-tasks'],
    queryFn: fetchUpcomingTasks,
    staleTime: STALE_2MIN,
    refetchOnWindowFocus: true,
  });
}
