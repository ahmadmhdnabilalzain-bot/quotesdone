// The browser Supabase client, built on first use and never at import.
//
// 15 Sep 2026. Both portals called createClient(SUPA_URL, SUPA_ANON) at module top level. On a
// preview build with NEXT_PUBLIC_SUPABASE_URL unset, supaEnv deliberately resolves NO target (the
// 3 Sep guard), and createClient('') throws "supabaseUrl is required" - during module evaluation,
// so prerendering /ar/me failed and every Preview build with it. Building the client lazily keeps
// the guard (a preview still gets no target; the first auth call throws, inside the caller's
// existing try/catch) while the page itself imports, prerenders and renders its shell.
//
// Production is unchanged: the same URL and key from supaEnv, the same options, and one instance
// per storage key for the life of the page. scripts/checks/no_module_level_supabase_client.test.mjs
// fails if a createClient( call appears anywhere in src/ outside this file.
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { SUPA_URL, SUPA_ANON } from './supaEnv';

const clients = new Map<string, SupabaseClient>();

export function supaClient(storageKey: string): SupabaseClient {
  let c = clients.get(storageKey);
  if (!c) {
    if (!SUPA_URL) throw new Error('[qd] this deployment has no database target (NEXT_PUBLIC_SUPABASE_URL is unset on a preview build)');
    c = createClient(SUPA_URL, SUPA_ANON, { auth: { persistSession: true, autoRefreshToken: true, storageKey } });
    clients.set(storageKey, c);
  }
  return c;
}
