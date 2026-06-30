// =============================================================================
// Accord CRM V1 — UpcomingTasksPanel
// Shows open tasks due within 14 days, scoped to current user's accessible deals.
// Direct query on tasks table (not a view) — includes deal context.
// =============================================================================

import { Link } from 'react-router-dom';
import { CheckSquare, ArrowRight, AlertCircle } from 'lucide-react';
import { format, isToday, isTomorrow, parseISO } from 'date-fns';
import { useUpcomingTasks } from '../../hooks/useDashboard';
import { cn } from '@/utils/cn';
import type { UpcomingTaskRow } from '../../types/dashboard.types';

// ---------------------------------------------------------------------------
// Priority dot colours
// ---------------------------------------------------------------------------
const PRIORITY_DOT: Record<string, string> = {
  High: 'bg-red-500',
  Medium: 'bg-amber-500',
  Low: 'bg-gray-300',
};

// ---------------------------------------------------------------------------
// Format due date label
// ---------------------------------------------------------------------------
function formatDueDate(dateStr: string): { label: string; urgent: boolean } {
  const date = parseISO(dateStr);
  if (isToday(date)) return { label: 'Due today', urgent: true };
  if (isTomorrow(date)) return { label: 'Due tomorrow', urgent: true };
  return { label: format(date, 'd MMM'), urgent: false };
}

// ---------------------------------------------------------------------------
// Single task row
// ---------------------------------------------------------------------------
function TaskRow({ task }: { task: UpcomingTaskRow }) {
  const { label, urgent } = formatDueDate(task.due_date ?? '');

  return (
    <div className="flex items-start gap-3 py-3 first:pt-0 last:pb-0">
      {/* Priority dot + check icon */}
      <div className="flex-shrink-0 flex items-center gap-1.5 pt-0.5">
        <span
          className={cn(
            'inline-block w-1.5 h-1.5 rounded-full flex-shrink-0',
            PRIORITY_DOT[task.priority ?? 'Low'] ?? 'bg-gray-300',
          )}
        />
        <CheckSquare
          className={cn(
            'h-4 w-4',
            task.is_overdue ? 'text-red-400' : 'text-gray-300',
          )}
          strokeWidth={1.5}
        />
      </div>

      {/* Content */}
      <div className="flex-1 min-w-0">
        <p className="text-[13px] font-medium text-gray-800 truncate">{task.title}</p>
        <Link
          to={`/pipeline/${task.deal_id}`}
          className="text-[12px] text-gray-400 hover:text-blue-500 transition-colors truncate block"
        >
          {task.company_name} · {task.deal_number}
        </Link>
      </div>

      {/* Due date */}
      <div className="flex-shrink-0 text-right">
        <span
          className={cn(
            'text-[12px] font-medium',
            task.is_overdue
              ? 'text-red-500'
              : urgent
              ? 'text-amber-600'
              : 'text-gray-400',
          )}
        >
          {task.is_overdue ? (
            <span className="flex items-center gap-0.5">
              <AlertCircle className="h-3 w-3" />
              Overdue
            </span>
          ) : (
            label
          )}
        </span>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main panel
// ---------------------------------------------------------------------------
export function UpcomingTasksPanel() {
  const { data: tasks, isLoading, isError } = useUpcomingTasks();

  return (
    <div className="bg-white rounded-xl shadow-sm p-6">
      {/* Header */}
      <div className="flex items-center justify-between mb-5">
        <div>
          <h3 className="text-sm font-semibold text-gray-900">Upcoming Tasks</h3>
          <p className="text-[13px] text-gray-500 mt-0.5">Due in the next 14 days</p>
        </div>
        <Link
          to="/tasks"
          className="flex items-center gap-1 text-[13px] text-blue-600 hover:text-blue-700 transition-colors"
        >
          All tasks <ArrowRight className="h-3.5 w-3.5" />
        </Link>
      </div>

      {/* Loading */}
      {isLoading && (
        <div className="space-y-3">
          {[...Array(4)].map((_, i) => (
            <div key={i} className="flex gap-3 py-3 first:pt-0">
              <div className="w-4 h-4 rounded bg-gray-100 animate-pulse mt-0.5" />
              <div className="flex-1 space-y-1.5">
                <div className="h-3 bg-gray-100 rounded animate-pulse w-3/4" />
                <div className="h-2.5 bg-gray-50 rounded animate-pulse w-1/2" />
              </div>
              <div className="h-3 w-14 bg-gray-100 rounded animate-pulse" />
            </div>
          ))}
        </div>
      )}

      {/* Error */}
      {isError && (
        <div className="flex items-center justify-center py-8">
          <p className="text-sm text-gray-400">Unable to load tasks</p>
        </div>
      )}

      {/* Empty */}
      {!isLoading && !isError && (!tasks || tasks.length === 0) && (
        <div className="flex flex-col items-center justify-center py-8 text-center">
          <CheckSquare className="h-10 w-10 text-gray-200 mb-3" strokeWidth={1} />
          <p className="text-sm font-medium text-gray-600">All caught up</p>
          <p className="text-[13px] text-gray-400 mt-1">No tasks due in the next 14 days</p>
        </div>
      )}

      {/* Task list */}
      {!isLoading && !isError && tasks && tasks.length > 0 && (
        <div className="divide-y divide-gray-50">
          {tasks.map((task) => (
            <TaskRow key={task.id} task={task} />
          ))}
        </div>
      )}
    </div>
  );
}
