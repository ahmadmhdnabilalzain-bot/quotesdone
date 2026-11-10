// THE MODEL-ROUTING EVALS' SHARED PLUMBING (it_engineer, cost seat; 10 Nov 2026; ruling 1571, design
// docs/reports/2026-11-10-design-model-routing.md section 5c). Used by eval_a.ts and eval_c.ts (eval_b.mjs drives the
// deployed intake from node).
//
//   * THE WINDOW. Every call runs inside its own rehearsal_window 'qd_run:<tag>' (models_allowed, cap_usd): the gateway lets a
//     tagged call through only inside it (ruling 1260) and refuses one more call at its cap (fn_rehearsal_spend_reserve).
//   * THE HARD CAP, IN THIS SCRIPT TOO. Before every call the run's spend is read from ai_cost_log (cost_usd_reported, else
//     cost_aed / 3.6725, for e2e_run_tag = tag) and the run STOPS when spend + the next call's estimate would reach the cap.
//     A gateway that let one through anyway (a reservation race) cannot take the run past it: the next check stops it.
//   * IDENTITIES. Every party is ZZ DEMO with a fixture mobile (9715000000NN) or an @example.invalid address; the subject is
//     {fixture: true}, so no seat files work for it and nothing reaches a real person. Nothing is written but the window,
//     the cost rows the calls themselves make, and (direct mode, eval C) those rows written here.
//   * THE JUDGE IS NEVER THE MODEL UNDER TEST. judge() asks knowledge_validation with counterpart_model = the model under test,
//     so the gateway's review router (fn_ai_route_review_for) picks another family (Sonnet 5.5 over Luna Pro today).
import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { pickApiKey } from '../../lib/supabase_keys.mjs';

export const REF = 'htdblwldjkcgjvmqkbeh';
export const AED_PER_USD = 3.6725;
// THE FUNCTION A JUDGE OR REVIEWER CALL IS BOOKED UNDER. fn_it_engineer_model_spend files an 'unlisted:<fn>:<class>' finding for
// any fn:class it_model_consumer does not list; wa_inbound's think() entry covers knowledge_validation, and the drafts reviewed
// are WhatsApp replies. Every such row also carries the run's e2e_run_tag, which is what marks it test spend.
export const JUDGE_FN = 'wa_inbound';

export const arg = (f: string): string | null => { const i = Deno.args.indexOf(f); return i >= 0 ? Deno.args[i + 1] ?? null : null; };
export const flag = (f: string): boolean => Deno.args.includes(f);

export interface Ctx { admin: SupabaseClient; tag: string; secret: string; capUsd: number }

/** The service client and the internal credential that proves a run tag at the gateway. Sets the env llm.ts reads. */
export async function connect(): Promise<{ admin: SupabaseClient; secret: string }> {
  const home = Deno.env.get('HOME') ?? '';
  const mgmt = (Deno.env.get('SUPABASE_ACCESS_TOKEN') ?? await Deno.readTextFile(`${home}/.supabase/access-token`).catch(() => '')).trim();
  if (!mgmt) throw new Error('SUPABASE_ACCESS_TOKEN is not set (docs/runbooks/cloud-sessions.md)');
  const keys = await (await fetch(`https://api.supabase.com/v1/projects/${REF}/api-keys?reveal=true`, { headers: { Authorization: `Bearer ${mgmt}` } })).json();
  const service = pickApiKey(keys, 'secret');
  if (!service) throw new Error('no service_role key from the management API');
  const admin = createClient(`https://${REF}.supabase.co`, service, { auth: { persistSession: false } });
  Deno.env.set('SUPABASE_URL', `https://${REF}.supabase.co`);
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', service);
  const secret = (await admin.from('app_secrets').select('value').eq('key', 'cred_db_internal').maybeSingle()).data?.value as string | undefined;
  if (!secret) throw new Error('app_secrets.cred_db_internal could not be read; a run tag could not be proved');
  return { admin, secret };
}

/** A fresh run tag (the gateway's shape: 4-16 lower-case letters and digits). */
export const newTag = (prefix: string) => (prefix + crypto.randomUUID().replace(/-/g, '')).slice(0, 16).toLowerCase();

export async function openWindow(admin: SupabaseClient, tag: string, capUsd: number, minutes: number, note: string): Promise<void> {
  if (!(capUsd > 0 && capUsd <= 15)) throw new Error('cap must be in (0, 15] USD (the window CHECK maximum)');
  const { error } = await admin.from('rehearsal_window').insert({ run_tag: 'qd_run:' + tag, opened_by: 'scripts/eval/model_routing', note,
    models_allowed: true, cap_usd: capUsd, expires_at: new Date(Date.now() + Math.min(120, minutes) * 60_000).toISOString() });
  if (error) throw new Error('rehearsal window not opened: ' + error.message);
}
export async function closeWindow(admin: SupabaseClient, tag: string): Promise<void> {
  await admin.from('rehearsal_window').update({ ended_at: new Date().toISOString(), models_allowed: false }).eq('run_tag', 'qd_run:' + tag).is('ended_at', null);
}

/** USD this run has spent, as ai_cost_log records it. */
export async function spentUsd(admin: SupabaseClient, tag: string): Promise<number> {
  const { data, error } = await admin.from('ai_cost_log').select('cost_usd_reported,cost_aed').eq('e2e_run_tag', tag).limit(5000);
  if (error) throw new Error('spend unreadable, the run stops: ' + error.message);
  return (data ?? []).reduce((s, r: { cost_usd_reported: number | null; cost_aed: number | null }) =>
    s + (r.cost_usd_reported != null ? Number(r.cost_usd_reported) : Number(r.cost_aed ?? 0) / AED_PER_USD), 0);
}

export class CapReached extends Error {}
/** Throws CapReached when spend + `nextUsd` would reach the cap. Called before EVERY model call. */
export async function guardSpend(c: Ctx, nextUsd: number, what: string): Promise<number> {
  const s = await spentUsd(c.admin, c.tag);
  if (s + nextUsd >= c.capUsd) throw new CapReached(`spend cap: USD ${s.toFixed(4)} spent + ${nextUsd.toFixed(4)} for ${what} would reach the USD ${c.capUsd} cap`);
  return s;
}

/** fn_ai_route as the gateway reads it: the primary and fallback a class gives a seat today. */
export async function routeOf(admin: SupabaseClient, cls: string, seat: string | null): Promise<{ model: string | null; fallback: string | null }> {
  const { data } = await admin.rpc('fn_ai_route', { p_task_class: cls, p_agent_key: seat });
  return { model: (data as { model?: string } | null)?.model ?? null, fallback: (data as { fallback?: string } | null)?.fallback ?? null };
}

export const ARABIC = /[؀-ۿ]/;
/** 'ar' when the text is mostly Arabic script, 'en' when it has none. */
export function scriptOf(t: string): 'ar' | 'en' | 'mixed' {
  const ar = (t.match(/[؀-ۿ]/g) ?? []).length, la = (t.match(/[A-Za-z]/g) ?? []).length;
  return ar === 0 ? 'en' : ar > la ? 'ar' : 'mixed';
}
/** A deferral or "I don't know" (the reply standard forbids them, ruling 903). */
export const DEFERRAL = /\b(?:I(?:'| wi)ll (?:check|confirm|get back)|get back to you|let me check|I(?:'m| am) not sure|I don'?t know)\b|سأتحقق|سأعود إليك|لا أعرف|لست متأكد/i;

export async function writeJson(path: string, v: unknown): Promise<void> {
  await Deno.mkdir(path.replace(/\/[^/]+$/, ''), { recursive: true }).catch(() => {});
  await Deno.writeTextFile(path, JSON.stringify(v, null, 1));
}
