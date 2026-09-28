// The browser Supabase AUTH client, built on first use and never at import.
//
// 15 Sep 2026. Both portals called createClient(SUPA_URL, SUPA_ANON) at module top level. On a
// preview build with NEXT_PUBLIC_SUPABASE_URL unset, supaEnv deliberately resolves NO target (the
// 3 Sep guard), and createClient('') throws "supabaseUrl is required" - during module evaluation,
// so prerendering /ar/me failed and every Preview build with it. Building the client lazily keeps
// the guard (a preview still gets no target; the first auth call throws, inside the caller's
// existing try/catch) while the page itself imports, prerenders and renders its shell.
//
// 28 Sep 2026 (portal cold load, it_engineer). Both portals only ever touch `.auth`; every data call
// goes through the edge functions with fetch. The full supabase-js client also bundled realtime,
// phoenix, postgrest, storage and functions into the /me first load. This builds the same
// GoTrueClient supabase-js builds for `.auth` (same URL, the same apikey + Bearer headers, the same
// options and storageKey, so a session already in localStorage is read unchanged) and nothing else.
// One instance per storage key for the life of the page, as before.
// scripts/checks/no_module_level_supabase_client.test.mjs fails if a client is constructed anywhere
// in src/ outside this file.
import { GoTrueClient } from '@supabase/auth-js';
import { SUPA_URL, SUPA_ANON } from './supaEnv';

type AuthOnly = { auth: GoTrueClient };
const clients = new Map<string, AuthOnly>();

export function supaClient(storageKey: string): AuthOnly {
  let c = clients.get(storageKey);
  if (!c) {
    if (!SUPA_URL) throw new Error('[qd] this deployment has no database target (NEXT_PUBLIC_SUPABASE_URL is unset on a preview build)');
    // detectSessionInUrl OFF (audit 21 Sep 2026, item 29): auth-js clears a magic-link fragment with
    // `location.hash = ''`, which pushes a history entry and leaves the token one Back press away.
    // The portals take the fragment themselves, in place — src/lib/authFragment.ts.
    c = { auth: new GoTrueClient({
      url: new URL('auth/v1', SUPA_URL.replace(/\/?$/, '/')).href,
      headers: { Authorization: `Bearer ${SUPA_ANON}`, apikey: SUPA_ANON },
      storageKey, persistSession: true, autoRefreshToken: true, detectSessionInUrl: false,
    }) };
    clients.set(storageKey, c);
  }
  return c;
}
