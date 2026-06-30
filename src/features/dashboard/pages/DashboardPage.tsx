// =============================================================================
// Accord CRM V1 — DashboardPage
// Landing page for all roles. Layout per ATL-CRM-DS-2025-001 §17:
//   Gray 50 page background
//   Row 1: Greeting
//   Row 2: Primary KPI cards (4 cards)
//   Row 3: Secondary KPI cards (4 cards)
//   Row 4: Pipeline chart (left) + Recent Activity (right)
//   Row 5: Upcoming Tasks (left) + Upcoming Meetings (right)
//
// All data fetched in parallel via independent React Query hooks.
// No waterfalls. Skeleton loaders per component.
// RLS in Supabase ensures each role sees only their permitted data.
// =============================================================================

import { useNavigate } from 'react-router-dom';
import {
  TrendingUp, DollarSign, TrendingDown, Users,
  Briefcase, CalendarCheck, AlertCircle, Bell,
} from 'lucide-react';
import { format } from 'date-fns';

import { KpiCard } from '../components/KpiCard';
import { PipelineByStageChart } from '../components/charts/PipelineByStageChart';
import { RecentActivityPanel } from '../components/panels/RecentActivityPanel';
import { UpcomingTasksPanel } from '../components/panels/UpcomingTasksPanel';
import { UpcomingMeetingsPanel } from '../components/panels/UpcomingMeetingsPanel';

import {
  useDashboardKpis,
  useOverdueTasksSummary,
  useUpcomingFollowupsSummary,
} from '../hooks/useDashboard';

import { formatCurrency, formatNumber } from '@/utils/format';
import { useCurrentUser } from '@/hooks/useCurrentUser';

// ---------------------------------------------------------------------------
// Greeting
// ---------------------------------------------------------------------------
function Greeting() {
  const { currentUser } = useCurrentUser();
  const firstName = currentUser?.full_name?.split(' ')[0] ?? 'there';
  const hour = new Date().getHours();
  const greeting =
    hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

  return (
    <div className="flex items-baseline justify-between">
      <h1 className="text-xl font-semibold text-gray-900">
        {greeting}, {firstName}
      </h1>
      <p className="text-[13px] text-gray-400">
        {format(new Date(), "EEEE, d MMMM yyyy")}
      </p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Primary KPI row — Pipeline Revenue, Won Revenue, Lost Revenue, Headcount
// ---------------------------------------------------------------------------
function PrimaryKpiRow() {
  const { data: kpis, isLoading } = useDashboardKpis();

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
      <KpiCard
        label="Pipeline Revenue"
        value={kpis ? formatCurrency(kpis.pipeline_revenue) : '—'}
        subtitle={kpis ? `${kpis.active_deals} active deal${kpis.active_deals !== 1 ? 's' : ''}` : undefined}
        icon={TrendingUp}
        iconClassName="bg-blue-50"
        href="/pipeline?status=Active"
        loading={isLoading}
      />
      <KpiCard
        label="Won Revenue"
        value={kpis ? formatCurrency(kpis.won_revenue) : '—'}
        subtitle={kpis ? `${kpis.won_deals} deal${kpis.won_deals !== 1 ? 's' : ''} won` : undefined}
        icon={DollarSign}
        iconClassName="bg-green-50"
        href="/pipeline?status=Won"
        loading={isLoading}
      />
      <KpiCard
        label="Lost Revenue"
        value={kpis ? formatCurrency(kpis.lost_revenue) : '—'}
        subtitle={kpis ? `${kpis.lost_deals} deal${kpis.lost_deals !== 1 ? 's' : ''} lost` : undefined}
        icon={TrendingDown}
        iconClassName="bg-red-50"
        href="/pipeline?status=Lost"
        loading={isLoading}
      />
      <KpiCard
        label="Pipeline Headcount"
        value={kpis ? formatNumber(kpis.pipeline_headcount) : '—'}
        subtitle="Across active deals"
        icon={Users}
        iconClassName="bg-purple-50"
        href="/pipeline?status=Active"
        loading={isLoading}
      />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Secondary KPI row — Active Deals, Closing This Month, Overdue Tasks, Follow-ups
// ---------------------------------------------------------------------------
function SecondaryKpiRow() {
  const { data: kpis, isLoading: kpisLoading } = useDashboardKpis();
  const { data: overdue, isLoading: overdueLoading } = useOverdueTasksSummary();
  const { data: followups, isLoading: followupsLoading } = useUpcomingFollowupsSummary();

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
      <KpiCard
        label="Active Deals"
        value={kpis ? formatNumber(kpis.active_deals) : '—'}
        subtitle={
          kpis
            ? `${kpis.global_conversion_rate.toFixed(1)}% conversion rate`
            : undefined
        }
        icon={Briefcase}
        iconClassName="bg-blue-50"
        href="/pipeline?status=Active"
        loading={kpisLoading}
      />
      <KpiCard
        label="Closing This Month"
        value={kpis ? formatNumber(kpis.deals_closing_this_month) : '—'}
        subtitle={
          kpis
            ? `${formatCurrency(kpis.closing_this_month_value)} pipeline`
            : undefined
        }
        icon={CalendarCheck}
        iconClassName="bg-amber-50"
        href="/pipeline?closing=this-month"
        loading={kpisLoading}
      />
      <KpiCard
        label="Overdue Tasks"
        value={overdue ? formatNumber(overdue.overdue_count) : '—'}
        subtitle={
          overdue && overdue.my_overdue_count > 0
            ? `${overdue.my_overdue_count} assigned to you`
            : 'None assigned to you'
        }
        icon={AlertCircle}
        iconClassName="bg-red-50"
        href="/tasks?tab=overdue"
        loading={overdueLoading}
      />
      <KpiCard
        label="Upcoming Follow-ups"
        value={followups ? formatNumber(followups.followup_count) : '—'}
        subtitle={
          followups && followups.nearest_followup_date
            ? `Next: ${format(new Date(followups.nearest_followup_date), 'd MMM')}`
            : 'None in next 7 days'
        }
        icon={Bell}
        iconClassName="bg-green-50"
        href="/tasks?tab=followups"
        loading={followupsLoading}
      />
    </div>
  );
}

// ---------------------------------------------------------------------------
// DashboardPage
// ---------------------------------------------------------------------------
export function DashboardPage() {
  return (
    <div className="min-h-full bg-gray-50 px-6 py-6 space-y-6">
      {/* Greeting */}
      <Greeting />

      {/* Primary KPI cards */}
      <PrimaryKpiRow />

      {/* Secondary KPI cards */}
      <SecondaryKpiRow />

      {/* Charts + Activity row */}
      <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
        <PipelineByStageChart />
        <RecentActivityPanel />
      </div>

      {/* Tasks + Meetings row */}
      <div className="grid grid-cols-1 xl:grid-cols-2 gap-6 pb-6">
        <UpcomingTasksPanel />
        <UpcomingMeetingsPanel />
      </div>
    </div>
  );
}
