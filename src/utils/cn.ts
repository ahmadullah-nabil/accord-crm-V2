// src/utils/cn.ts
// Combines clsx (conditional class logic) with tailwind-merge (deduplication).
// Every component in the project uses this for className composition.
// Dependencies: clsx, tailwind-merge (both listed in ATL-CRM-IMPL-2025-001)
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
