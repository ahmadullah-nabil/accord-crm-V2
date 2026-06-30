// src/services/supabase.ts
// Single typed Supabase client instance for the entire application.
// Import ONLY this file anywhere a Supabase call is needed:
//   import { supabase } from '@/services/supabase'
//
// Database type is auto-generated:
//   npx supabase gen types typescript --project-id <id> > src/types/database.types.ts
//   npm run gen:types
import { createClient } from '@supabase/supabase-js';
import type { Database } from '@/types/database.types';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    'Missing Supabase environment variables. ' +
    'Ensure VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY are set in .env.local',
  );
}

export const supabase = createClient<Database>(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});
