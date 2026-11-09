// supplier_api — what every module of this function shares: the CORS headers, the JSON responder, the error
// answer that never carries a database sentence, the service-role client and URL, the secret reader and the
// feature switch, and the request context index.ts hands each action group. ONE copy of each.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,116-line index.ts split into modules, a pure move).
import { createClient, type User } from 'jsr:@supabase/supabase-js@2';
import type { SafeInquiry } from './quote_review.ts';

export const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
export const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: cors });
// NO DATABASE SENTENCE REACHES A RESPONSE (28 Oct 2026, review of #1712; ledger 1401 audit S7). Six actions answered a
// refused write with the Postgres message itself, eight put a database, storage or exception message in `detail`, and
// the outer catch answered String(e) on every action, create_company's included (sanctionedEmail throws the PostgREST
// error when its read fails). The message is logged here; the caller gets the portal's existing unexpected_error copy.
const SERVER_ERROR = { error: 'Something went wrong. Please try again.', code: 'unexpected_error' } as const;
export const failed = (where: string, e: unknown, status = 500) => {
  console.error(`supplier_api ${where}:`, String((e as { message?: unknown } | null)?.message ?? e));
  return J({ ...SERVER_ERROR }, status);
};
export const logged = (where: string, e: unknown) => { console.error(`supplier_api ${where}:`, String((e as { message?: unknown } | null)?.message ?? e)); };
export const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
export const SUPA_URL = Deno.env.get('SUPABASE_URL')!;

export async function secretVal(key: string) { const { data } = await admin.from('app_secrets').select('value').eq('key', key).maybeSingle(); return data?.value || null; }

// The same switch supplier_portal reads: the model may be asked about a document only when the
// founder has turned it on (22 Sep 2026, SEATS-02).
export async function flagOn(key: string): Promise<boolean> { return /^(on|true|1)$/i.test(String(await secretVal(key) || '').trim()); }

/** One request, as the actions read it: built once by index.ts after the caller is signed in and cleared. */
export type ActionCtx = {
  req: Request;
  jwt: string;
  user: User;
  email: string;
  // the parsed body and its action, exactly as untyped as `await req.json()` gave them in the single-file handler
  // deno-lint-ignore no-explicit-any
  body: any;
  // deno-lint-ignore no-explicit-any
  action: any;
  /** This function's own handler (index.ts), for the actions that run it in-process with the caller's session. */
  handle: (req: Request) => Promise<Response>;
  /** index.ts safeInquiryOf: the job as the review may read it, through `inbox`. */
  safeInquiryOf: (req: Request, jwt: string, inquiryId: string) => Promise<SafeInquiry | null>;
};
