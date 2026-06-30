// src/app/providers.tsx
// Composes all providers and installs the Supabase auth listener.
// Runs once on app mount. Populates auth.store on every session event.
import { type ReactNode, useEffect } from 'react';
import { QueryClientProvider } from '@tanstack/react-query';
import { queryClient } from '@/lib/query-client';
import { supabase } from '@/services/supabase';
import { useAuthStore } from '@/features/auth/stores/auth.store';
import { fetchCrmUser, resolvePermissions } from '@/features/auth/services/auth.service';

function AuthProvider({ children }: { children: ReactNode }) {
  const { setSession, setCurrentUser, setPermissionMap, setUserRoles, setIsAuthLoading, clearAuth } =
    useAuthStore();

  useEffect(() => {
    // Resolve existing session on mount
    supabase.auth.getSession().then(async ({ data: { session } }) => {
      if (session) {
        setSession(session);
        const user = await fetchCrmUser();
        if (user) {
          setCurrentUser(user);
          const { map, roles } = await resolvePermissions(user.id);
          setPermissionMap(map);
          setUserRoles(roles);
        }
      }
      setIsAuthLoading(false);
    });

    // Listen for auth state changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange(async (event, session) => {
      if (event === 'SIGNED_IN' && session) {
        setSession(session);
        const user = await fetchCrmUser();
        if (user) {
          setCurrentUser(user);
          const { map, roles } = await resolvePermissions(user.id);
          setPermissionMap(map);
          setUserRoles(roles);
        }
        setIsAuthLoading(false);
      }

      if (event === 'TOKEN_REFRESHED' && session) {
        setSession(session);
      }

      if (event === 'SIGNED_OUT') {
        clearAuth();
        queryClient.clear();
      }
    });

    return () => subscription.unsubscribe();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  return <>{children}</>;
}

export function Providers({ children }: { children: ReactNode }) {
  return (
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        {children}
      </AuthProvider>
    </QueryClientProvider>
  );
}
