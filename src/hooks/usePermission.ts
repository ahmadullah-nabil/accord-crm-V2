// src/hooks/usePermission.ts
// Central permission check. Reads from auth.store permissionMap synchronously.
// Zero API calls. Returns false if permission map is not yet resolved.
import { useAuthStore } from '@/features/auth/stores/auth.store';

export function usePermission(module: string, action: string): boolean {
  const permissionMap = useAuthStore((s) => s.permissionMap);
  return permissionMap[`${module}.${action}`] === true;
}
