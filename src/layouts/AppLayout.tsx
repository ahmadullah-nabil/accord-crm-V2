// src/layouts/AppLayout.tsx
// Authenticated shell: fixed sidebar (240px) + topbar (60px) + scrollable content.
// All authenticated routes render inside <Outlet /> here.
import { Outlet, NavLink, useNavigate } from 'react-router-dom';
import {
  LayoutDashboard, Briefcase, Users, BarChart2,
  CheckSquare, Calendar, Settings, LogOut,
} from 'lucide-react';
import { supabase } from '@/services/supabase';
import { useAuthStore } from '@/features/auth/stores/auth.store';
import { useUiStore } from '@/stores/ui.store';
import { cn } from '@/utils/cn';

const NAV_ITEMS = [
  { to: '/dashboard',  label: 'Dashboard',  icon: LayoutDashboard },
  { to: '/pipeline',   label: 'Pipeline',   icon: Briefcase },
  { to: '/customers',  label: 'Customers',  icon: Users },
  { to: '/reports',    label: 'Reports',    icon: BarChart2 },
  { to: '/tasks',      label: 'Tasks',      icon: CheckSquare },
  { to: '/meetings',   label: 'Meetings',   icon: Calendar },
];

export function AppLayout() {
  const navigate = useNavigate();
  const currentUser = useAuthStore((s) => s.currentUser);
  const clearAuth = useAuthStore((s) => s.clearAuth);
  const sidebarOpen = useUiStore((s) => s.sidebarOpen);

  async function handleLogout() {
    await supabase.auth.signOut();
    clearAuth();
    navigate('/login');
  }

  return (
    <div className="flex h-screen overflow-hidden bg-gray-50">
      {/* Sidebar */}
      <aside
        className={cn(
          'flex-shrink-0 flex flex-col bg-[#1E3A5F] transition-all duration-200',
          sidebarOpen ? 'w-60' : 'w-16',
        )}
      >
        {/* Logo */}
        <div className="h-[60px] flex items-center px-4 border-b border-white/10">
          <span className={cn('text-white font-bold text-lg', !sidebarOpen && 'hidden')}>
            Accord CRM
          </span>
        </div>

        {/* Nav */}
        <nav className="flex-1 overflow-y-auto py-4 space-y-0.5 px-2">
          {NAV_ITEMS.map(({ to, label, icon: Icon }) => (
            <NavLink
              key={to}
              to={to}
              className={({ isActive }) =>
                cn(
                  'flex items-center gap-3 px-3 py-2.5 rounded-md text-sm transition-colors',
                  isActive
                    ? 'bg-blue-500/10 text-white border-l-[3px] border-blue-500'
                    : 'text-white/70 hover:text-white hover:bg-white/10',
                )
              }
            >
              <Icon className="h-5 w-5 flex-shrink-0" strokeWidth={1.5} />
              {sidebarOpen && <span>{label}</span>}
            </NavLink>
          ))}
        </nav>

        {/* Settings + user */}
        <div className="border-t border-white/10 py-3 px-2 space-y-0.5">
          <NavLink
            to="/settings"
            className={({ isActive }) =>
              cn(
                'flex items-center gap-3 px-3 py-2.5 rounded-md text-sm transition-colors',
                isActive
                  ? 'bg-blue-500/10 text-white border-l-[3px] border-blue-500'
                  : 'text-white/70 hover:text-white hover:bg-white/10',
              )
            }
          >
            <Settings className="h-5 w-5 flex-shrink-0" strokeWidth={1.5} />
            {sidebarOpen && <span>Settings</span>}
          </NavLink>

          <button
            onClick={handleLogout}
            className="flex items-center gap-3 px-3 py-2.5 rounded-md text-sm text-white/70 hover:text-white hover:bg-white/10 transition-colors w-full"
          >
            <LogOut className="h-5 w-5 flex-shrink-0" strokeWidth={1.5} />
            {sidebarOpen && <span>Log out</span>}
          </button>

          {sidebarOpen && currentUser && (
            <div className="flex items-center gap-2.5 px-3 pt-3 pb-1">
              <div className="w-8 h-8 rounded-full bg-blue-500/30 flex items-center justify-center flex-shrink-0">
                <span className="text-white text-xs font-semibold">
                  {currentUser.full_name.charAt(0).toUpperCase()}
                </span>
              </div>
              <div className="min-w-0">
                <p className="text-white text-[13px] font-medium truncate">{currentUser.full_name}</p>
                <p className="text-white/50 text-[11px] truncate">{currentUser.email}</p>
              </div>
            </div>
          )}
        </div>
      </aside>

      {/* Main content */}
      <div className="flex-1 flex flex-col overflow-hidden">
        {/* Topbar */}
        <header className="h-[60px] bg-white border-b border-gray-200 flex items-center px-6 flex-shrink-0">
          <button
            onClick={() => useUiStore.getState().toggleSidebar()}
            className="mr-4 text-gray-400 hover:text-gray-600 transition-colors"
            aria-label="Toggle sidebar"
          >
            <LayoutDashboard className="h-5 w-5" />
          </button>
        </header>

        {/* Page content */}
        <main className="flex-1 overflow-y-auto">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
