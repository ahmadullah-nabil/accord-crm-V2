// =============================================================================
// Accord CRM V1 — RecentActivityPanel
// Shows the last 10 deal timeline events across all accessible deals.
// Data from v_deal_timeline_display (008_timeline.sql).
// Design inspired by Attio CRM timeline cards (ATL-CRM-DS-2025-001 §19).
// =============================================================================

import { Link } from 'react-router-dom';
import {
  Phone, Calendar, CheckSquare, FileText, Paperclip,
  ArrowRight, User, Flag, Trophy, XCircle, Building2,
  Clock,
} from 'lucide-react';
import { useRecentActivity } from '../../hooks/useDashboard';
import { formatRelativeDate } from '@/utils/format';
import { cn } from '@/utils/cn';
import type { RecentActivityRow } from '../../types/dashboard.types';

// ---------------------------------------------------------------------------
// Event type → icon + colour configuration
// ---------------------------------------------------------------------------
interface EventConfig {
  icon: React.ElementType;
  bgClass: string;
  iconClass: string;
}

const EVENT_CONFIG: Record<string, EventConfig> = {
  deal_created:       { icon: Flag,         bgClass: 'bg-gray-100',    iconClass: 'text-gray-500' },
  stage_changed:      { icon: ArrowRight,   bgClass: 'bg-blue-50',     iconClass: 'text-blue-500' },
  assignment_changed: { icon: User,         bgClass: 'bg-purple-50',   iconClass: 'text-purple-500' },
  call_logged:        { icon: Phone,        bgClass: 'bg-green-50',    iconClass: 'text-green-600' },
  meeting_logged:     { icon: Calendar,     bgClass: 'bg-blue-50',     iconClass: 'text-blue-500' },
  task_created:       { icon: CheckSquare,  bgClass: 'bg-amber-50',    iconClass: 'text-amber-600' },
  task_completed:     { icon: CheckSquare,  bgClass: 'bg-green-50',    iconClass: 'text-green-600' },
  note_added:         { icon: FileText,     bgClass: 'bg-gray-100',    iconClass: 'text-gray-500' },
  document_uploaded:  { icon: Paperclip,    bgClass: 'bg-gray-100',    iconClass: 'text-gray-500' },
  deal_won:           { icon: Trophy,       bgClass: 'bg-blue-50',     iconClass: 'text-blue-700' },
  deal_lost:          { icon: XCircle,      bgClass: 'bg-red-50',      iconClass: 'text-red-500' },
  deal_cancelled:     { icon: XCircle,      bgClass: 'bg-gray-100',    iconClass: 'text-gray-400' },
  customer_created:   { icon: Building2,    bgClass: 'bg-green-50',    iconClass: 'text-green-600' },
};

const DEFAULT_CONFIG: EventConfig = {
  icon: Clock,
  bgClass: 'bg-gray-100',
  iconClass: 'text-gray-400',
};

// ---------------------------------------------------------------------------
// Single activity row
// ---------------------------------------------------------------------------
function ActivityRow({ event }: { event: RecentActivityRow }) {
  const config = EVENT_CONFIG[event.event_type] ?? DEFAULT_CONFIG;
  const Icon = config.icon;

  return (
    <div className="flex gap-3 py-3 first:pt-0 last:pb-0">
      {/* Icon */}
      <div className={cn('flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center', config.bgClass)}>
        <Icon className={cn('h-4 w-4', config.iconClass)} strokeWidth={1.75} />
      </div>

      {/* Content */}
      <div className="flex-1 min-w-0">
        <p className="text-[13px] text-gray-700 leading-snug line-clamp-2">
          {event.event_description ?? event.event_title}
        </p>
        <div className="flex items-center gap-1.5 mt-0.5">
          <span className="text-[12px] text-gray-400">{event.performed_by_name}</span>
          <span className="text-gray-300">·</span>
          <span className="text-[12px] text-gray-400">
            {formatRelativeDate(event.event_date)}
          </span>
        </div>
      </div>

      {/* Deal link */}
      <Link
        to={`/pipeline/${event.deal_id}`}
        className="flex-shrink-0 self-start mt-0.5"
        title="View deal"
      >
        <ArrowRight className="h-3.5 w-3.5 text-gray-300 hover:text-blue-500 transition-colors" />
      </Link>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Skeleton loader
// ---------------------------------------------------------------------------
function ActivitySkeleton() {
  return (
    <div className="space-y-3">
      {[...Array(5)].map((_, i) => (
        <div key={i} className="flex gap-3 py-3 first:pt-0">
          <div className="w-8 h-8 rounded-full bg-gray-100 animate-pulse flex-shrink-0" />
          <div className="flex-1 space-y-1.5">
            <div className="h-3 bg-gray-100 rounded animate-pulse w-full" />
            <div className="h-3 bg-gray-100 rounded animate-pulse w-2/3" />
            <div className="h-2.5 bg-gray-50 rounded animate-pulse w-1/3 mt-1" />
          </div>
        </div>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main panel
// ---------------------------------------------------------------------------
export function RecentActivityPanel() {
  const { data: events, isLoading, isError } = useRecentActivity();

  return (
    <div className="bg-white rounded-xl shadow-sm p-6 flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between mb-5">
        <div>
          <h3 className="text-sm font-semibold text-gray-900">Recent Activity</h3>
          <p className="text-[13px] text-gray-500 mt-0.5">Latest events across all deals</p>
        </div>
        <Link
          to="/pipeline"
          className="flex items-center gap-1 text-[13px] text-blue-600 hover:text-blue-700 transition-colors"
        >
          View pipeline <ArrowRight className="h-3.5 w-3.5" />
        </Link>
      </div>

      {/* Content */}
      {isLoading && <ActivitySkeleton />}

      {isError && (
        <div className="flex items-center justify-center flex-1 py-8">
          <p className="text-sm text-gray-400">Unable to load recent activity</p>
        </div>
      )}

      {!isLoading && !isError && (!events || events.length === 0) && (
        <div className="flex flex-col items-center justify-center py-10 text-center flex-1">
          <Clock className="h-10 w-10 text-gray-200 mb-3" strokeWidth={1} />
          <p className="text-sm font-medium text-gray-600">No activity yet</p>
          <p className="text-[13px] text-gray-400 mt-1">
            Activity will appear here as deals progress
          </p>
        </div>
      )}

      {!isLoading && !isError && events && events.length > 0 && (
        <div className="divide-y divide-gray-50">
          {events.map((event) => (
            <ActivityRow key={event.id} event={event} />
          ))}
        </div>
      )}
    </div>
  );
}
