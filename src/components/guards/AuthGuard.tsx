// src/components/guards/AuthGuard.tsx
// Redirects unauthenticated users to /login, preserving the intended URL.
import { Navigate, useLocation } from 'react-router-dom';
import { useAuthStore } from '@/features/auth/stores/auth.store';

export function AuthGuard({ children }: { children: React.ReactNode }) {
  const session = useAuthStore((s) => s.session);
  const isAuthLoading = useAuthStore((s) => s.isAuthLoading);
  const location = useLocation();

  if (isAuthLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="w-8 h-8 border-2 border-blue-600 border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  if (!session) {
    return <Navigate to="/login" state={{ from: location }} replace />;
  }

  return <>{children}</>;
}
