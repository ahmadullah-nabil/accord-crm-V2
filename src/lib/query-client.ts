// src/lib/query-client.ts
// TanStack Query v5 client with project-wide defaults.
// Feature hooks override staleTime per their requirements.
import { QueryClient } from '@tanstack/react-query';

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 2 * 60 * 1000,        // 2 minutes default
      gcTime: 5 * 60 * 1000,           // 5 minutes garbage collection
      retry: 3,
      retryDelay: (attempt) => Math.min(1000 * 2 ** attempt, 30_000),
      refetchOnWindowFocus: true,
    },
    mutations: {
      retry: 0,
    },
  },
});
