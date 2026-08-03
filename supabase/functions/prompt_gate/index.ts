// prompt_gate — benchmark-scores prompt versions and decides auto-promote vs escalate.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { makeLlm, SONNET_FIRST } from '../_shared/llm.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return data?.value as string | undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;

const _llm = makeLlm(SONNET_FIRST, { max: 1200, temperature: 0 });
const llm = async (sys: string, user: string, max?: number): Promise<string> => (await _llm(sys, user, max)) ?? ''; // shared client, Sonnet-first + 25s timeout

async function contentOf(key: string, version?: number | null): Promise<{ version: number | null; content: string }> {
  if (version == null) { const { data: p } = await admin.from('prompts').select('active_version').eq('key', key).maybeSingle(); version = (p as any)?.active_version ?? null; }
  if (version == null) return { version: null, content: '' };
  const { data } = await admin.from('prompt_versions').select('content').eq('prompt_key', key).eq('version', version).maybeSingle();
  return { version, content: (data as any)?.content || '' };
}

async function scoreVersion(key: string, version: number | null, content: string) {
  const { data: cases } = await admin.from('prompt_benchmarks').select('name,input,rubric,weight').eq('prompt_key', key).eq('active', true);
  const list = cases || [];
  const detail: any[] = []; let wsum = 0, acc = 0;
  for (const c of list) {
    const answer = await llm(content, String((c as any).input), 1200);
    const judged = await llm(
      'You are a strict evaluator for a UAE B2B quotation marketplace. Given an INPUT, a RUBRIC and an ANSWER, score 0-100 how well the ANSWER satisfies the RUBRIC. Punish fabrication of prices/brands/specs and reward flagging missing detail. Reply with ONLY compact JSON: {"score": <0-100 integer>, "note": "<=15 words"}.',
      'INPUT:\n' + String((c as any).input) + '\n\nRUBRIC:\n' + String((c as any).rubric) + '\n\nANSWER:\n' + (answer || '(empty)'), 200);
    let sc = 0, note = '';
    try { const m = judged.match(/\{[\s\S]*\}/); const j = m ? JSON.parse(m[0]) : {}; sc = Math.max(0, Math.min(100, Number(j.score) || 0)); note = String(j.note || ''); } catch (_e) { /* 0 */ }
    const w = Number((c as any).weight) || 1; wsum += w; acc += sc * w;
    detail.push({ case: (c as any).name, score: sc, note });
  }
  const score = wsum ? Math.round((acc / wsum) * 10) / 10 : null;
  await admin.from('prompt_eval_runs').insert({ prompt_key: key, version, score, cases_total: list.length, detail });
  if (version != null && score != null) await admin.from('prompt_versions').update({ eval_score: score }).eq('prompt_key', key).eq('version', version);
  return { score, cases_total: list.length, detail };
}

async function annotate(key: string, candV: number, patch: any) {
  try { const { data: rows } = await admin.from('agent_actions').select('id,detail').eq('kind', 'prompt_approval').eq('detail->>key', key).eq('detail->>version', String(candV)); for (const row of (rows || [])) { const nd = { ...((row as any).detail || {}), eval: patch }; await admin.from('agent_actions').update({ detail: nd }).eq('id', (row as any).id); } } catch (_e) { /* ignore */ }
}

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'prompt_gate');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    const action = String(body.action || 'gate');
    const key = String(body.key || '');
    if (!key) return J({ error: 'key_required' }, 400);

    if (action === 'view') {
      const active = await contentOf(key, null);
      const cand = body.version != null ? await contentOf(key, Number(body.version)) : { version: null, content: '' };
      const { data: runs } = await admin.from('prompt_eval_runs').select('version,score,detail,created_at').eq('prompt_key', key).order('created_at', { ascending: false }).limit(6);
      return J({ ok: true, active, candidate: cand, recent_runs: runs || [] });
    }

    if (action === 'eval') {
      const v = body.version != null ? Number(body.version) : null;
      const c = await contentOf(key, v);
      if (!c.content) return J({ error: 'no_content' }, 400);
      const r = await scoreVersion(key, c.version, c.content);
      return J({ ok: true, key, version: c.version, ...r });
    }

    const candV = Number(body.version);
    if (!candV) return J({ error: 'version_required' }, 400);
    const active = await contentOf(key, null);
    const cand = await contentOf(key, candV);
    if (!cand.content) return J({ error: 'candidate_not_found' }, 400);
    const evA = active.content ? await scoreVersion(key, active.version, active.content) : { score: null };
    const evC = await scoreVersion(key, candV, cand.content);
    const aS = Number((evA as any).score ?? 0), cS = Number(evC.score ?? 0); const delta = Math.round((cS - aS) * 10) / 10;
    const { data: dp } = await admin.from('decision_policy').select('value').eq('key', 'prompt_sensitive_pattern').maybeSingle();
    const pat = (dp as any)?.value || 'legal|finance|complian|security|quote_review';
    const sensitive = new RegExp(String(pat), 'i').test(key);
    const MARGIN = 5, FLOOR = 60;
    let decision = 'escalate';
    if (!sensitive && delta >= MARGIN && cS >= FLOOR) {
      decision = 'auto_promoted';
      await admin.rpc('fn_prompt_approve_draft', { p_key: key, p_version: candV, p_by: 'auto:eval +' + delta });
      await admin.from('agent_actions').update({ status: 'auto_done', decided_at: new Date().toISOString(), decided_by: 'auto-promoted (benchmark +' + delta + ')' }).eq('kind', 'prompt_approval').eq('detail->>key', key).eq('detail->>version', String(candV)).in('status', ['pending', 'needs_review']);
    }
    await annotate(key, candV, { active_score: aS, candidate_score: cS, delta, sensitive, floor: FLOOR, margin: MARGIN, decision });
    return J({ ok: true, key, candidate_version: candV, active_score: aS, candidate_score: cS, delta, sensitive, decision });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
