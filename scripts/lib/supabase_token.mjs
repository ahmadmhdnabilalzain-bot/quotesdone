// The one place a script finds the Supabase management token (owner: it_engineer, 26 Oct 2026).
//
// The contract is the environment: SUPABASE_ACCESS_TOKEN. A claude.ai/code cloud session has no
// laptop, no home-directory login and no Windows credential store, so every script must work from
// that variable alone (docs/runbooks/cloud-sessions.md lists every variable a session needs).
//
// The one fallback is the file the Supabase CLI's own `supabase login` writes,
// <home>/.supabase/access-token, resolved from the running user's home directory on any OS. It is
// kept because the founder's laptop sessions still rely on it; it is never a fixed laptop path.
// Until 26 Oct 2026 more than a hundred scripts hard-coded that file under one Windows user's
// home folder, so on Linux a missing variable surfaced as an ENOENT on a Windows path rather than as a name.
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

export const SUPABASE_TOKEN_FILE = join(homedir(), '.supabase', 'access-token');

export const MISSING_TOKEN =
  'SUPABASE_ACCESS_TOKEN is not set. Set it as an environment variable (a cloud session: the ' +
  "environment's variables, see docs/runbooks/cloud-sessions.md), or run `supabase login` on this machine.";

// The token, or '' when there is none. For callers that skip politely without one.
export function supabaseTokenOrEmpty() {
  // `npm run gate -- --offline` sets QD_OFFLINE=1 for every step it runs: an offline run must not reach production
  // through a token in the environment or in ~/.supabase/access-token (review of #1874, 9 Nov 2026).
  if (process.env.QD_OFFLINE === '1') return '';
  const env = (process.env.SUPABASE_ACCESS_TOKEN || '').trim();
  if (env) return env;
  return existsSync(SUPABASE_TOKEN_FILE) ? readFileSync(SUPABASE_TOKEN_FILE, 'utf8').trim() : '';
}

// The token, or an error that names the variable.
export function supabaseAccessToken() {
  const t = supabaseTokenOrEmpty();
  if (!t) throw new Error(MISSING_TOKEN);
  return t;
}
