// =============================================================================
// Accord CRM V1 — KpiCard
// Single metric card per ATL-CRM-DS-2025-001:
//   White bg · shadow-md · 16px radius · 24px padding
//   Label: 12px all-caps Gray 500
//   Value: 30px SemiBold Gray 900
//   Subtitle: 13px Gray 500
//   Full card clickable → navigates to linked view
// =============================================================================

import React from 'react';
import { useNavigate } from 'react-router-dom';
import { cn } from '@/utils/cn';

interface KpiCardProps {
  label: string;
  value: string | number;
  subtitle?: string;
  /** Lucide icon component */
  icon?: React.ElementType;
  iconClassName?: string;
  /** React Router path to navigate on click */
  href?: string;
  loading?: boolean;
  className?: string;
}

export function KpiCard({
  label,
  value,
  subtitle,
  icon: Icon,
  iconClassName,
  href,
  loading = false,
  className,
}: KpiCardProps) {
  const navigate = useNavigate();

  if (loading) {
    return (
      <div
        className={cn(
          'bg-white rounded-xl shadow-md p-6 animate-pulse',
          className,
        )}
      >
        <div className="h-3 w-24 bg-gray-200 rounded mb-4" />
        <div className="h-8 w-32 bg-gray-200 rounded mb-2" />
        <div className="h-3 w-20 bg-gray-100 rounded" />
      </div>
    );
  }

  const inner = (
    <div className={cn('flex items-start justify-between', Icon ? 'gap-4' : '')}>
      <div className="flex-1 min-w-0">
        <p className="text-xs font-medium tracking-wider uppercase text-gray-500 mb-1 truncate">
          {label}
        </p>
        <p className="text-3xl font-bold text-gray-900 leading-none mb-1 tabular-nums">
          {value}
        </p>
        {subtitle && (
          <p className="text-[13px] text-gray-500 truncate">{subtitle}</p>
        )}
      </div>
      {Icon && (
        <div
          className={cn(
            'flex-shrink-0 p-2.5 rounded-lg',
            iconClassName ?? 'bg-blue-50',
          )}
        >
          <Icon className="h-5 w-5 text-blue-600" strokeWidth={1.5} />
        </div>
      )}
    </div>
  );

  if (href) {
    return (
      <button
        type="button"
        onClick={() => navigate(href)}
        className={cn(
          'bg-white rounded-xl shadow-md p-6 text-left w-full',
          'transition-all duration-150 hover:shadow-lg hover:bg-blue-50/30',
          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2',
          'cursor-pointer',
          className,
        )}
      >
        {inner}
      </button>
    );
  }

  return (
    <div className={cn('bg-white rounded-xl shadow-md p-6', className)}>
      {inner}
    </div>
  );
}
