// marketing — the Marketing seat's runtime. The company's SIXTH seat (founder instruction 721, 22 Sep 2026):
// SEO, social, digital, business development and LinkedIn. It reports the overall picture to the CEO — for
// the picture, not for approval — hands ad spend to the accountant, and hands a social conversation to the
// founder the moment someone asks for a person. Job description: docs/positions/marketing.md.
//
// THE CREDENTIAL DECIDES THE SEAT, NOT THE CALLER (the rule every seat runtime follows since ceo_agent's
// 8 Sep confused-deputy defect). fn.marketing is the seat; the founder's own session may read `health`.
//
// ACTIONS
//   health  — is the seat real: role, edge, grants, credential, owner, conversations, last runs, and which
//             held credentials are SET (presence only; a value never leaves the database).
//   duties  — resilience_ping's 30-minute call: every entry in ./duties.ts, then fn_marketing_tick (the daily
//             report to the CEO and the ad-spend loops). A failing duty is an IT finding owned by marketing.
//   lead_sourcing — one supplier lead sourcing batch (./lead_sourcing.ts), started by pg_cron lead_sourcing_batch.
//   assist  — company knowledge for a question (fn_marketing_assist, gte-small in-region, no paid model).
//
// MODEL CALLS: only through ./duties.ts -> _shared/marketing_judgement.ts (one class per step, dept 'marketing',
// asked of the founder's hold first; while it stands each step records "held, not run"). Deterministic first.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { observe } from '../_shared/observe.ts';
import { signedInUser } from '../_shared/signed_in_user.ts';
import { DUTIES } from './duties.ts';
import { PAUSED, pausedDuties } from '../_shared/duty_pause.ts';
import { recallCases } from '../_shared/case_recall.ts';
import { makeLlmRich } from '../_shared/llm.ts';
import { runLeadBatch } from './lead_sourcing.ts';

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const J = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });

async function sec(k: string): Promise<string | undefined> {
  const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle();
  return data?.value as string | undefined;
}

// The credentials held for this seat alone (rule 641). Read here for presence only.
const HELD_KEYS = ['meta_access_token', 'meta_ad_account_id', 'postiz_api_key', 'postiz_publish_key', 'postiz_integrations', 'meta_ig_user_id'];

type Caller = { kind: 'marketing' | 'founder' } | null;
async function whoami(req: Request, body: Record<string, unknown>): Promise<Caller> {
  if (body?.__secret) {
    const r = await requireInternal(admin, String(body.__secret), 'marketing');
    return r.ok && r.context === 'fn.marketing' ? { kind: 'marketing' } : null;
  }
  // Local refusal first and a bounded auth call (_shared/signed_in_user.ts), never an inline getUser.
  const who = await signedInUser(admin, req.headers.get('Authorization'));
  if (!who.ok) return null;
  const email = String(who.email || '').toLowerCase();
  const allow = (await sec('admin_emails') || '').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
  return email && allow.includes(email) ? { kind: 'founder' } : null;
}

// Every call leaves a row, so the CEO's board can tell a quiet seat from a dead one.
async function run(action: string, status: string, counts: Record<string, unknown>, note?: string) {
  try {
    const now = new Date().toISOString();
    await admin.from('agent_runs').insert({ agent: 'marketing', status, started_at: now, finished_at: now,
      counts: { action, ...counts }, note: note ?? null });
  } catch { /* an unwritten log must not turn a good answer into a 500 */ }
}

// deno-lint-ignore no-explicit-any
let _emb: any = null;
async function embed(text: string): Promise<string | null> {
  try {
    // deno-lint-ignore no-explicit-any
    if (_emb === null) _emb = new (globalThis as any).Supabase.ai.Session('gte-small');
    const v = await _emb.run(String(text).slice(0, 1200), { mean_pool: true, normalize: true }) as number[];
    return '[' + v.join(',') + ']';
  } catch (_e) { return null; }
}

export async function runDuties(): Promise<Record<string, unknown>> {
  const results: Record<string, unknown> = {};
  const failing: Record<string, unknown>[] = [];
  // A duty public.duty_pause names ('marketing.<name>') is skipped and reported, never run (_shared/duty_pause.ts).
  const pause = await pausedDuties(admin);
  if (pause.error) results.duty_pause = { ok: false, error: pause.error };
  for (const d of DUTIES) {
    if (pause.has('marketing.' + d.name)) { results[d.name] = PAUSED; continue; }
    try {
      results[d.name] = await d.run({ admin, sec, now: new Date() });
    } catch (e) {
      const error = String((e as Error)?.message || e).slice(0, 300);
      results[d.name] = { ok: false, error };
      failing.push({ item: d.name, title: 'marketing duty ' + d.name + ' failed: ' + error, owner_seat: 'marketing',
        subject: 'marketing', blast: 'agent_facing', affected: 1, evidence: { duty: d.name, error } });
    }
  }
  // One call per run, failures or not, so a duty that passes again closes its own finding.
  const settled = await admin.rpc('fn_it_duty_settle', { p_duty: 'marketing_duties', p_items: failing });
  const tick = await admin.rpc('fn_marketing_tick');
  return { duties: DUTIES.length, results, failing: failing.length,
           settle_error: settled.error?.message ?? null, tick: tick.error ? { ok: false, error: tick.error.message } : tick.data };
}

Deno.serve(observe('marketing', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  const body = await req.json().catch(() => ({} as Record<string, unknown>));
  const caller = await whoami(req, body);
  if (!caller) return J({ error: 'unauthorized' }, 401);
  const action = String(body.action || '').trim();

  if (action === 'health' || action === 'status') {
    const [role, edge, grants, cred, owned, kinds, runs, held] = await Promise.all([
      admin.from('org_role').select('role_id,status,authority_level,responsibilities,forbidden_decisions,handoff_targets,escalation_targets').eq('role_id', 'marketing').maybeSingle(),
      admin.from('org_reporting_edge').select('parent_role_id').eq('child_role_id', 'marketing'),
      admin.from('ceo_standing_grant').select('grant_key,action_class,active').eq('grantee_role_id', 'marketing').order('grant_key'),
      admin.from('internal_credential').select('context,scope,active,last_used_at').eq('context', 'fn.marketing').maybeSingle(),
      admin.from('function_owner').select('function_slug').eq('owner', 'marketing'),
      admin.from('seat_handoff_kind').select('type,from_seat,to_seat,handler').or('from_seat.eq.marketing,to_seat.eq.marketing'),
      admin.from('agent_runs').select('status,finished_at,counts').eq('agent', 'marketing').order('id', { ascending: false }).limit(5),
      admin.from('app_secrets').select('key,value').in('key', HELD_KEYS),
    ]);
    const set = new Set(((held.data || []) as Array<{ key: string; value: string | null }>)
      .filter((r) => String(r.value ?? '').trim() !== '').map((r) => r.key));
    const out = { seat: 'marketing', role: role.data, reports_to: (edge.data || []).map((e) => e.parent_role_id),
      grants: grants.data, credential: cred.data, owns: (owned.data || []).map((o) => o.function_slug),
      conversations: kinds.data, duties: DUTIES.map((d) => d.name), last_runs: runs.data,
      credentials_set: Object.fromEntries(HELD_KEYS.map((k) => [k, set.has(k)])) };
    await run('health', 'ok', { duties: DUTIES.length });
    return J(out);
  }

  if (action === 'duties') {
    if (caller.kind !== 'marketing') return J({ error: 'duties run under the seat credential only' }, 403);
    const r = await runDuties();
    await run('duties', r.failing ? 'error' : 'ok', { duties: r.duties, failing: r.failing });
    return J({ ok: !r.failing, result: r });
  }

  if (action === 'assist') {
    const q = String(body.question || body.text || '').slice(0, 2000);
    const vec = q ? await embed(q) : null;
    const { data, error } = await admin.rpc('fn_marketing_assist', { p_text: q, p_embedding: vec });
    // Past cases before the answer (23 Sep 2026): the plans he approved, the replies that worked.
    const memory = await recallCases(admin, { seat: 'marketing', path: 'assist', situation: q, embedding: vec });
    await run('assist', error ? 'error' : 'ok', { answered: (data as { answered?: boolean })?.answered ?? null }, error?.message);
    return error ? J({ error: error.message }, 500) : J({ ...(data as Record<string, unknown>), precedent: memory });
  }

  if (action === 'lead_sourcing') {
    // pg_cron lead_sourcing_batch -> fn_lead_sourcing_kick, every 10 minutes, on its OWN schedule (never the
    // resilience tick). 202 at once; the batch runs in the background under the 150 s cap and logs its own row.
    if (caller.kind !== 'marketing') return J({ error: 'lead sourcing runs under the seat credential only' }, 403);
    const llm = makeLlmRich(undefined, { fn: 'marketing', taskClass: 'routine_employee_reasoning', dept: 'marketing',
      agent: 'marketing', max: 300, timeoutMs: 25000, temperature: 0, json: true });
    const batch = runLeadBatch(admin, async (prompt) => {
      const x = await llm('', '', 300, '', { messages: [{ role: 'user', content: prompt }] });
      return { content: x.content, cost_usd: x.cost_usd ?? 0 };   // the gateway's own charge, summed per batch against the cap
    })
      .then((r) => run('lead_sourcing', r.ok === false ? 'error' : 'ok', r, r.ok === false ? String(r.error) : undefined))
      .catch((e) => run('lead_sourcing', 'error', {}, String((e as Error)?.message || e)));
    // deno-lint-ignore no-explicit-any
    (globalThis as any).EdgeRuntime?.waitUntil ? (globalThis as any).EdgeRuntime.waitUntil(batch) : await batch;
    return J({ started: true }, 202);
  }

  return J({ error: 'unknown action', actions: ['health', 'duties', 'assist', 'lead_sourcing'] }, 400);
}));
