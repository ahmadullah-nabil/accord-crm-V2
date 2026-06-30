// src/features/auth/stores/auth.store.ts
// Zustand store for authentication state.
// Populated by providers.tsx on session resolution.
// All consumers import via useCurrentUser hook (@/hooks/useCurrentUser).
import { create } from 'zustand';
import type { Session } from '@supabase/supabase-js';

// CRM user profile (from public.users table, not auth.users)
export interface CrmUser {
  id: string;
  auth_user_id: string | null;
  full_name: string;
  email: string;
  phone: string | null;
  avatar_url: string | null;
  is_active: boolean;
}

// Flat permission map resolved at login
// Key format: "module.action" → boolean
// e.g. { "pipeline.create": true, "settings.manage": false }
export type PermissionMap = Record<string, boolean>;

interface AuthState {
  // Data
  currentUser: CrmUser | null;
  session: Session | null;
  permissionMap: PermissionMap;
  userRoles: string[];
  isAuthLoading: boolean;

  // Actions
  setSession: (session: Session | null) => void;
  setCurrentUser: (user: CrmUser | null) => void;
  setPermissionMap: (map: PermissionMap) => void;
  setUserRoles: (roles: string[]) => void;
  setIsAuthLoading: (loading: boolean) => void;
  clearAuth: () => void;
}

export const useAuthStore = create<AuthState>()((set) => ({
  // Initial state
  currentUser: null,
  session: null,
  permissionMap: {},
  userRoles: [],
  isAuthLoading: true,

  // Actions
  setSession: (session) => set({ session }),
  setCurrentUser: (user) => set({ currentUser: user }),
  setPermissionMap: (map) => set({ permissionMap: map }),
  setUserRoles: (roles) => set({ userRoles: roles }),
  setIsAuthLoading: (loading) => set({ isAuthLoading: loading }),
  clearAuth: () =>
    set({
      currentUser: null,
      session: null,
      permissionMap: {},
      userRoles: [],
      isAuthLoading: false,
    }),
}));
