// src/features/auth/services/auth.service.ts
// Supabase Auth wrappers + CRM profile resolution.
import { supabase } from '@/services/supabase';
import type { CrmUser, PermissionMap } from '../stores/auth.store';

export async function signIn(email: string, password: string) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data;
}

export async function signOut() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

export async function getSession() {
  const { data, error } = await supabase.auth.getSession();
  if (error) throw error;
  return data.session;
}

// Fetches the CRM users row by auth_user_id
export async function fetchCrmUser(): Promise<CrmUser | null> {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;

  const { data, error } = await supabase
    .from('users')
    .select('id, auth_user_id, full_name, email, phone, avatar_url, is_active')
    .eq('auth_user_id', user.id)
    .eq('is_active', true)
    .single();

  if (error) return null;
  return data as CrmUser;
}

// Builds the flat permission map from the current user's role assignments
export async function resolvePermissions(userId: string): Promise<{ map: PermissionMap; roles: string[] }> {
  const { data, error } = await supabase
    .from('user_roles')
    .select(`
      roles!inner (
        name,
        role_permissions!inner (
          permissions!inner (
            name
          )
        )
      )
    `)
    .eq('user_id', userId)
    .eq('is_active', true);

  if (error || !data) return { map: {}, roles: [] };

  const roles: string[] = [];
  const map: PermissionMap = {};

  for (const ur of data as any[]) {
    const role = ur.roles;
    if (role?.name) roles.push(role.name);
    for (const rp of role?.role_permissions ?? []) {
      const permName = rp.permissions?.name;
      if (permName) map[permName] = true;
    }
  }

  return { map, roles };
}
