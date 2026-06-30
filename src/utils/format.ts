// =============================================================================
// Accord CRM V1 — Format Utilities
// Shared formatting helpers used across all features.
// No dependencies beyond date-fns.
// =============================================================================

import {
  formatDistanceToNow,
  parseISO,
  isValid,
  differenceInDays,
  isToday,
  isYesterday,
} from 'date-fns';

// ---------------------------------------------------------------------------
// formatCurrency
// Formats a number as currency with commas and 2 decimal places.
// Uses the BDT/USD symbol depending on locale — defaulting to USD for now.
// ---------------------------------------------------------------------------
export function formatCurrency(
  value: number | null | undefined,
  options: { symbol?: string; decimals?: number } = {},
): string {
  if (value === null || value === undefined) return '—';
  const { symbol = '৳', decimals = 0 } = options;

  const formatted = new Intl.NumberFormat('en-BD', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  }).format(value);

  return `${symbol}${formatted}`;
}

// ---------------------------------------------------------------------------
// formatNumber
// Formats a number with commas, no decimal places.
// ---------------------------------------------------------------------------
export function formatNumber(value: number | null | undefined): string {
  if (value === null || value === undefined) return '—';
  return new Intl.NumberFormat('en-US').format(value);
}

// ---------------------------------------------------------------------------
// formatRelativeDate
// Returns a human-readable relative date:
//   "just now", "5 minutes ago", "2 hours ago", "Yesterday", "3 days ago",
//   or a formatted date for older entries.
// ---------------------------------------------------------------------------
export function formatRelativeDate(dateStr: string | null | undefined): string {
  if (!dateStr) return '';

  const date = typeof dateStr === 'string' ? parseISO(dateStr) : dateStr;
  if (!isValid(date)) return '';

  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60_000);
  const diffHours = Math.floor(diffMs / 3_600_000);
  const diffDays = differenceInDays(now, date);

  if (diffMins < 1) return 'just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  if (isToday(date)) return 'Today';
  if (isYesterday(date)) return 'Yesterday';
  if (diffDays < 7) return `${diffDays} days ago`;

  return date.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
}

// ---------------------------------------------------------------------------
// formatDate
// Formats a date string to a readable date like "12 Jun 2025"
// ---------------------------------------------------------------------------
export function formatDate(dateStr: string | null | undefined): string {
  if (!dateStr) return '—';
  const date = parseISO(dateStr);
  if (!isValid(date)) return '—';
  return date.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
}

// ---------------------------------------------------------------------------
// formatDateTime
// Formats a datetime string to "12 Jun 2025, 2:30 PM"
// ---------------------------------------------------------------------------
export function formatDateTime(dateStr: string | null | undefined): string {
  if (!dateStr) return '—';
  const date = parseISO(dateStr);
  if (!isValid(date)) return '—';
  return date.toLocaleString('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  });
}

// ---------------------------------------------------------------------------
// formatDuration
// Converts seconds to "2m 34s" or "1h 5m"
// ---------------------------------------------------------------------------
export function formatDuration(seconds: number | null | undefined): string {
  if (!seconds) return 'Not connected';
  if (seconds < 60) return `${seconds}s`;
  const mins = Math.floor(seconds / 60);
  const secs = seconds % 60;
  if (mins < 60) return secs > 0 ? `${mins}m ${secs}s` : `${mins}m`;
  const hours = Math.floor(mins / 60);
  const remainingMins = mins % 60;
  return remainingMins > 0 ? `${hours}h ${remainingMins}m` : `${hours}h`;
}
