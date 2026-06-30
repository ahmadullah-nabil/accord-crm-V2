// =============================================================================
// Accord CRM V1 — UpcomingMeetingsPanel
// Shows meetings scheduled within the next 7 days.
// Direct query on meetings + deals join.
// =============================================================================

import { Link } from 'react-router-dom';
import { Calendar, ArrowRight, Video, MapPin, ExternalLink } from 'lucide-react';
import { format, isToday, isTomorrow, parseISO } from 'date-fns';
import { useUpcomingMeetings } from '../../hooks/useDashboard';
import { cn } from '@/utils/cn';
import type { UpcomingMeetingRow } from '../../types/dashboard.types';

// ---------------------------------------------------------------------------
// Meeting type icon
// ---------------------------------------------------------------------------
function MeetingTypeIcon({ type }: { type: string }) {
  if (type === 'Online' || type === 'Hybrid') {
    return <Video className="h-3.5 w-3.5 text-blue-400 flex-shrink-0" strokeWidth={1.5} />;
  }
  return <MapPin className="h-3.5 w-3.5 text-gray-400 flex-shrink-0" strokeWidth={1.5} />;
}

// ---------------------------------------------------------------------------
// Format meeting time
// ---------------------------------------------------------------------------
function formatMeetingTime(scheduledAt: string): { dateLabel: string; time: string; urgent: boolean } {
  const date = parseISO(scheduledAt);
  let dateLabel: string;
  if (isToday(date)) {
    dateLabel = 'Today';
  } else if (isTomorrow(date)) {
    dateLabel = 'Tomorrow';
  } else {
    dateLabel = format(date, 'EEE, d MMM');
  }
  return {
    dateLabel,
    time: format(date, 'h:mm a'),
    urgent: isToday(date) || isTomorrow(date),
  };
}

// ---------------------------------------------------------------------------
// Single meeting row
// ---------------------------------------------------------------------------
function MeetingRow({ meeting }: { meeting: UpcomingMeetingRow }) {
  const { dateLabel, time, urgent } = formatMeetingTime(meeting.scheduled_at);

  return (
    <div className="flex items-start gap-3 py-3 first:pt-0 last:pb-0">
      {/* Type icon */}
      <div className="flex-shrink-0 w-8 h-8 rounded-full bg-blue-50 flex items-center justify-center mt-0.5">
        <MeetingTypeIcon type={meeting.meeting_type} />
      </div>

      {/* Content */}
      <div className="flex-1 min-w-0">
        <div className="flex items-start justify-between gap-2">
          <p className="text-[13px] font-medium text-gray-800 truncate flex-1">{meeting.title}</p>
          {meeting.meeting_url && (
            <a
              href={meeting.meeting_url}
              target="_blank"
              rel="noopener noreferrer"
              className="flex-shrink-0 text-blue-400 hover:text-blue-600 transition-colors"
              title="Join meeting"
            >
              <ExternalLink className="h-3.5 w-3.5" />
            </a>
          )}
        </div>

        <Link
          to={`/pipeline/${meeting.deal_id}`}
          className="text-[12px] text-gray-400 hover:text-blue-500 transition-colors truncate block"
        >
          {meeting.company_name} · {meeting.deal_number}
        </Link>

        {meeting.contact_name && (
          <p className="text-[12px] text-gray-400 truncate">with {meeting.contact_name}</p>
        )}
      </div>

      {/* Time */}
      <div className="flex-shrink-0 text-right">
        <p
          className={cn(
            'text-[12px] font-medium',
            urgent ? 'text-blue-600' : 'text-gray-500',
          )}
        >
          {dateLabel}
        </p>
        <p className="text-[12px] text-gray-400">{time}</p>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main panel
// ---------------------------------------------------------------------------
export function UpcomingMeetingsPanel() {
  const { data: meetings, isLoading, isError } = useUpcomingMeetings();

  return (
    <div className="bg-white rounded-xl shadow-sm p-6">
      {/* Header */}
      <div className="flex items-center justify-between mb-5">
        <div>
          <h3 className="text-sm font-semibold text-gray-900">Upcoming Meetings</h3>
          <p className="text-[13px] text-gray-500 mt-0.5">Next 7 days</p>
        </div>
        <Link
          to="/meetings"
          className="flex items-center gap-1 text-[13px] text-blue-600 hover:text-blue-700 transition-colors"
        >
          All meetings <ArrowRight className="h-3.5 w-3.5" />
        </Link>
      </div>

      {/* Loading */}
      {isLoading && (
        <div className="space-y-3">
          {[...Array(3)].map((_, i) => (
            <div key={i} className="flex gap-3 py-3 first:pt-0">
              <div className="w-8 h-8 rounded-full bg-gray-100 animate-pulse flex-shrink-0" />
              <div className="flex-1 space-y-1.5">
                <div className="h-3 bg-gray-100 rounded animate-pulse w-3/4" />
                <div className="h-2.5 bg-gray-50 rounded animate-pulse w-1/2" />
              </div>
              <div className="space-y-1">
                <div className="h-3 w-16 bg-gray-100 rounded animate-pulse" />
                <div className="h-2.5 w-12 bg-gray-50 rounded animate-pulse" />
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Error */}
      {isError && (
        <div className="flex items-center justify-center py-8">
          <p className="text-sm text-gray-400">Unable to load meetings</p>
        </div>
      )}

      {/* Empty */}
      {!isLoading && !isError && (!meetings || meetings.length === 0) && (
        <div className="flex flex-col items-center justify-center py-8 text-center">
          <Calendar className="h-10 w-10 text-gray-200 mb-3" strokeWidth={1} />
          <p className="text-sm font-medium text-gray-600">No meetings scheduled</p>
          <p className="text-[13px] text-gray-400 mt-1">No meetings in the next 7 days</p>
        </div>
      )}

      {/* Meeting list */}
      {!isLoading && !isError && meetings && meetings.length > 0 && (
        <div className="divide-y divide-gray-50">
          {meetings.map((meeting) => (
            <MeetingRow key={meeting.id} meeting={meeting} />
          ))}
        </div>
      )}
    </div>
  );
}
