// =============================================================================
// Accord CRM V1 — PipelineByStageChart
// Horizontal bar chart: deal count per active stage.
// Data from v_pipeline_by_stage (011_views_and_reporting.sql).
// Chart library: Recharts (as per ATL-CRM-FE-2025-001).
// Design tokens from ATL-CRM-DS-2025-001.
// =============================================================================

import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Cell,
} from 'recharts';
import { ArrowRight } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { usePipelineByStage } from '../../hooks/useDashboard';
import { formatCurrency } from '@/utils/format';

// Stage colour map — matches ATL-CRM-DS-2025-001 stage colour progression
const STAGE_COLOURS: Record<string, string> = {
  Opportunity: '#6366F1',   // Indigo 500
  Qualified: '#3B82F6',     // Blue 500
  Demonstration: '#14B8A6', // Teal 500
  Proposal: '#A855F7',      // Purple 500
  Negotiation: '#F59E0B',   // Amber 500
  Won: '#2563EB',           // Blue 700
  Lost: '#EF4444',          // Red 500
};

const DEFAULT_COLOUR = '#3B82F6';

interface TooltipProps {
  active?: boolean;
  payload?: Array<{ payload: { stage_name: string; deal_count: number; total_value: number; avg_deal_value: number } }>;
}

function CustomTooltip({ active, payload }: TooltipProps) {
  if (!active || !payload?.length) return null;
  const d = payload[0].payload;
  return (
    <div className="bg-white rounded-lg shadow-lg border border-gray-100 px-4 py-3 text-sm min-w-[180px]">
      <p className="font-semibold text-gray-900 mb-1.5">{d.stage_name}</p>
      <div className="space-y-0.5">
        <div className="flex justify-between gap-4">
          <span className="text-gray-500">Deals</span>
          <span className="font-medium text-gray-900 tabular-nums">{d.deal_count}</span>
        </div>
        <div className="flex justify-between gap-4">
          <span className="text-gray-500">Total value</span>
          <span className="font-medium text-gray-900 tabular-nums">{formatCurrency(d.total_value)}</span>
        </div>
        <div className="flex justify-between gap-4">
          <span className="text-gray-500">Avg value</span>
          <span className="font-medium text-gray-900 tabular-nums">{formatCurrency(d.avg_deal_value)}</span>
        </div>
      </div>
    </div>
  );
}

export function PipelineByStageChart() {
  const navigate = useNavigate();
  const { data, isLoading, isError } = usePipelineByStage();

  // Filter to active pipeline stages only (exclude Won/Lost for pipeline health view)
  const chartData = (data ?? []).filter(
    (s) => !s.stage_name?.toLowerCase().includes('won') && !s.stage_name?.toLowerCase().includes('lost'),
  );

  if (isLoading) {
    return (
      <div className="bg-white rounded-xl shadow-sm p-6">
        <div className="h-4 w-36 bg-gray-200 rounded animate-pulse mb-1" />
        <div className="h-3 w-24 bg-gray-100 rounded animate-pulse mb-6" />
        <div className="space-y-3">
          {[...Array(5)].map((_, i) => (
            <div key={i} className="flex items-center gap-3">
              <div className="h-3 w-20 bg-gray-100 rounded animate-pulse" />
              <div
                className="h-7 bg-gray-100 rounded animate-pulse"
                style={{ width: `${60 - i * 10}%` }}
              />
            </div>
          ))}
        </div>
      </div>
    );
  }

  if (isError) {
    return (
      <div className="bg-white rounded-xl shadow-sm p-6 flex items-center justify-center h-64">
        <p className="text-sm text-gray-400">Unable to load pipeline data</p>
      </div>
    );
  }

  if (!chartData.length) {
    return (
      <div className="bg-white rounded-xl shadow-sm p-6">
        <h3 className="text-sm font-semibold text-gray-900 mb-1">Pipeline by Stage</h3>
        <p className="text-[13px] text-gray-500 mb-6">Active deals per stage</p>
        <div className="flex flex-col items-center justify-center h-48 text-center">
          <p className="text-sm text-gray-400">No active deals in the pipeline yet.</p>
        </div>
      </div>
    );
  }

  const maxCount = Math.max(...chartData.map((d) => d.deal_count), 1);

  return (
    <div className="bg-white rounded-xl shadow-sm p-6">
      {/* Header */}
      <div className="flex items-start justify-between mb-6">
        <div>
          <h3 className="text-sm font-semibold text-gray-900">Pipeline by Stage</h3>
          <p className="text-[13px] text-gray-500 mt-0.5">Active deals per stage</p>
        </div>
        <button
          type="button"
          onClick={() => navigate('/pipeline')}
          className="flex items-center gap-1 text-[13px] text-blue-600 hover:text-blue-700 transition-colors"
        >
          View pipeline <ArrowRight className="h-3.5 w-3.5" />
        </button>
      </div>

      {/* Chart */}
      <ResponsiveContainer width="100%" height={chartData.length * 52 + 20}>
        <BarChart
          data={chartData}
          layout="vertical"
          margin={{ top: 0, right: 40, bottom: 0, left: 0 }}
          barCategoryGap="28%"
        >
          <CartesianGrid
            horizontal={false}
            strokeDasharray="0"
            stroke="#F3F4F6"
            strokeWidth={1}
          />
          <XAxis
            type="number"
            domain={[0, maxCount + 1]}
            tick={{ fontSize: 12, fill: '#9CA3AF' }}
            axisLine={false}
            tickLine={false}
            allowDecimals={false}
          />
          <YAxis
            type="category"
            dataKey="stage_name"
            tick={{ fontSize: 13, fill: '#374151', fontWeight: 500 }}
            axisLine={false}
            tickLine={false}
            width={110}
          />
          <Tooltip
            content={<CustomTooltip />}
            cursor={{ fill: '#F9FAFB', radius: 4 }}
          />
          <Bar dataKey="deal_count" radius={[0, 4, 4, 0]} maxBarSize={28}>
            {chartData.map((entry) => (
              <Cell
                key={entry.stage_id}
                fill={STAGE_COLOURS[entry.stage_name] ?? DEFAULT_COLOUR}
                fillOpacity={0.9}
              />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
