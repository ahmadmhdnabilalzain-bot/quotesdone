// resend_inbound: the service client, JSON reply, secrets reader and the agent_runs log line. Moved out of index.ts unchanged (9 Nov 2026).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { makeLlmRich } from '../../_shared/llm.ts';

export const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
export const SUPA_URL = Deno.env.get('SUPABASE_URL')!;
export const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
export const MODEL = 'anthropic/claude-sonnet-5';
export const classify = makeLlmRich([MODEL], { max: 500, temperature: 0.1, fn: 'resend_inbound' });
export async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// Observability -------------------------------------------------------------
export const T0 = Date.now();
export async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'resend_inbound', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging drop an inbound email */ }
}
