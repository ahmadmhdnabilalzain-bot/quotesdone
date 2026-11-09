// inquiry_intake/shared.ts — the service client, response helpers and per-worker state every part of the intake uses. Moved verbatim from index.ts (9 Nov 2026).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { serviceVocab } from '../_shared/service_vocabulary.ts';
import { keptFor } from './turn_clock.ts';

export const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
export const T0 = Date.now();
export async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'inquiry_intake', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
export const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json' };
export const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: CORS });
export async function sec(k: string): Promise<string | null> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || null; }

// detectEmirate, detectUrgency and isArabic live in ./classify.ts (tested there); the trade map is deleted (reasoned_trades.ts).
export function sanitizeInput(text: string): string { return String(text || '').replace(/\bignore (all |any |previous )?(above|prior|earlier)?\s*(instructions|prompts?|rules?)\b/gi, '[removed]').replace(/\b(system|assistant|developer)\s*:/gi, '$1 -').slice(0, 4000); }
// THE SERVICE VOCABULARY IS READ ONCE PER WARM WORKER, NOT ON EVERY READY TURN (27 Oct 2026, turn_clock.ts). The
// supplier count reads every active service with both of its vectors (about 1,047 rows twice, in pages); measured on a
// local serve against production that was 10.7-10.9 s of each turn that reached ready, after the model. The list
// changes when a service is added, which is rare: a worker keeps it 5 minutes, it is fetched while the interview call
// runs, and dispatch itself always reads it fresh, so the inquiry still reaches exactly the suppliers it matches.
export const serviceVocabKept = keptFor(5 * 60_000, () => serviceVocab(admin));
export function parseJson(s: string): any { try { return JSON.parse(s); } catch (_e) {} const m = String(s || '').match(/\{[\s\S]*\}/); if (m) { try { return JSON.parse(m[0]); } catch (_e2) {} } return null; }
