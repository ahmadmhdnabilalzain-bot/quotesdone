// accountant — what every module of this function shares: the service-role client, the CORS headers, the JSON
// responder, the secret reader, the base URL, the expense mailbox, the run log, and the request context index.ts
// hands each action group. ONE copy of each; nothing here is declared anywhere else.
// Moved here verbatim from index.ts on 9 Nov 2026 (the 1,715-line index.ts split into modules, a pure move).
import { createClient } from 'jsr:@supabase/supabase-js@2';

export const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
export const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
export const J = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });

export async function sec(k: string): Promise<string | undefined> {
  const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
  return data?.value as string | undefined;
}

export const SUPA_URL = Deno.env.get('SUPABASE_URL')!;
// The founder confirmed this address on 9 Sep 2026: the accountant "collects expenses from the
// email expenses@mail.quotesdone.com". The same literal resend_inbound uses.
export const EXPENSE_MAILBOX = 'expenses@mail.quotesdone.com';

// EVERY CALL LEAVES A ROW. fn_it_detect (D2) reads each subject's own rhythm in agent_runs, so a seat
// that never writes one has no rhythm to watch: its silence is indistinguishable from a seat that is down. This
// is the only measurable liveness signal the estate has. Best-effort: attribution must never fail
// the call it is attributing.
export async function run(action: string, status: string, counts: Record<string, unknown>, note?: string) {
  try {
    await admin.from('agent_runs').insert({
      agent: 'accountant',
      status,
      started_at: new Date().toISOString(),
      finished_at: new Date().toISOString(),
      counts: { action, ...counts },
      note: note ?? null,
    });
  } catch { /* an unwritten log must not turn a good answer into a 500 */ }
}

/** One request, as the actions read it: built once by index.ts after the caller is admitted. */
export type ActionCtx = {
  // the parsed body, exactly as untyped as `await req.json()` gave it in the single-file handler
  // deno-lint-ignore no-explicit-any
  body: any;
  action: string;
  // whoami's answer once it is not null: the credential decided it, never the payload
  caller: { kind: 'accountant' | 'founder' };
};
