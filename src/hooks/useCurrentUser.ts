// src/hooks/useCurrentUser.ts
// Reads the resolved CRM user from auth.store.ts (Zustand).
// Synchronous — no API call. Store is populated during the auth flow in providers.tsx.
// Shape consumed by DashboardPage: { currentUser: { full_name: string } | null }
import { useAuthStore } from '@/features/auth/stores/auth.store';

export function useCurrentUser() {
  const currentUser = useAuthStore((s) => s.currentUser);
  const isAuthLoading = useAuthStore((s) => s.isAuthLoading);

  return { currentUser, isAuthLoading };
}
