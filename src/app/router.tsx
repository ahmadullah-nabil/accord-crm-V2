// src/app/router.tsx
// createBrowserRouter — all application routes.
// DashboardPage is the production implementation from features/dashboard.
// All other feature pages are stubs pending Phase 2–4 implementation.
import { createBrowserRouter, Navigate } from 'react-router-dom';

import { AppLayout } from '@/layouts/AppLayout';
import { AuthLayout } from '@/layouts/AuthLayout';
import { AuthGuard } from '@/components/guards/AuthGuard';

// Auth
import { LoginPage } from '@/features/auth/pages/LoginPage';

// Dashboard — PRODUCTION (replaces any placeholder)
import { DashboardPage } from '@/features/dashboard/pages/DashboardPage';

// Feature stubs (Phase 2–4)
import { PipelinePage } from '@/features/pipeline/pages/PipelinePage';
import { CustomersPage } from '@/features/customers/pages/CustomersPage';
import { TasksPage } from '@/features/tasks/pages/TasksPage';
import { MeetingsPage } from '@/features/meetings/pages/MeetingsPage';
import { ReportsPage } from '@/features/reports/pages/ReportsPage';
import { SettingsPage } from '@/features/settings/pages/SettingsPage';

export const router = createBrowserRouter([
  // ── Auth routes (no guard, no sidebar) ────────────────────────────────────
  {
    element: <AuthLayout />,
    children: [
      { path: '/login', element: <LoginPage /> },
    ],
  },

  // ── Authenticated routes (AuthGuard + AppLayout) ──────────────────────────
  {
    element: (
      <AuthGuard>
        <AppLayout />
      </AuthGuard>
    ),
    children: [
      // Default: redirect / → /dashboard
      { index: true, element: <Navigate to="/dashboard" replace /> },

      // Dashboard — production
      { path: '/dashboard', element: <DashboardPage /> },

      // Pipeline
      { path: '/pipeline', element: <PipelinePage /> },
      { path: '/pipeline/new', element: <PipelinePage /> },
      { path: '/pipeline/:dealId', element: <PipelinePage /> },

      // Customers
      { path: '/customers', element: <CustomersPage /> },
      { path: '/customers/:customerId', element: <CustomersPage /> },

      // Tasks
      { path: '/tasks', element: <TasksPage /> },

      // Meetings
      { path: '/meetings', element: <MeetingsPage /> },

      // Reports
      { path: '/reports', element: <Navigate to="/reports/pipeline" replace /> },
      { path: '/reports/pipeline', element: <ReportsPage /> },
      { path: '/reports/revenue', element: <ReportsPage /> },
      { path: '/reports/deals', element: <ReportsPage /> },
      { path: '/reports/users', element: <ReportsPage /> },
      { path: '/reports/sources', element: <ReportsPage /> },
      { path: '/reports/industry', element: <ReportsPage /> },
      { path: '/reports/modules', element: <ReportsPage /> },
      { path: '/reports/conversion', element: <ReportsPage /> },

      // Settings
      { path: '/settings', element: <Navigate to="/settings/users" replace /> },
      { path: '/settings/users', element: <SettingsPage /> },
      { path: '/settings/roles', element: <SettingsPage /> },
      { path: '/settings/pipeline', element: <SettingsPage /> },
      { path: '/settings/lookups', element: <SettingsPage /> },
      { path: '/settings/products', element: <SettingsPage /> },
      { path: '/settings/data', element: <SettingsPage /> },

      // 404
      {
        path: '*',
        element: (
          <div className="p-8 text-center">
            <h1 className="text-xl font-semibold text-gray-900">404 — Page not found</h1>
            <a href="/dashboard" className="text-blue-600 hover:underline text-sm mt-2 inline-block">
              Return to Dashboard
            </a>
          </div>
        ),
      },
    ],
  },
]);
