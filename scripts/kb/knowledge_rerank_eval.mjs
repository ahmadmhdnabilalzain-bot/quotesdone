// Measurement only (never called by production): reruns the blind eval questions' fused top-20 ($S/sR_new.json) through
// an LLM rerank inside a tagged rehearsal window, with the breaker guard, spend ceiling and abort-after-3 required by the
// release operator (12 Oct). Run from the repo root by the window wrapper with QD_RUN_TAG, QD_SUBJECT, QD_SERVICE, QD_E2E_SECRET.
// Scratch measurement: an LLM rerank over the fused top-20 candidates the staged routine returned (sR_new.json).
// Same blind questions, same scoring (recall@5 per pack x seat pair, expected_mode 'any' honoured).
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
const S = process.env.S, REPO = process.cwd().replaceAll(String.fromCharCode(92), '/');
const { readPacks, rowsOf, lit } = await import('file:///' + REPO + '/scripts/kb/verified_packs.mjs');
const { sql, PROJECT_REF } = await import('file:///' + REPO + '/scripts/lib/db.mjs');
const TASK = process.env.TASK || 'internal_judgement';
const FN = 'canon_eval';
const EXC = +(process.env.EXC || 300);
const qs = JSON.parse(readFileSync(S + '/sR_new.json', 'utf8'));

// candidate texts: pack rows from the repo (the staged state), every other source read-only from production
const text = new Map();
for (const p of readPacks(REPO + '/knowledge')) for (const r of rowsOf(p)) text.set(r.table + '|' + r.record_id, { title: r.cols.title, body: r.cols.content ?? r.cols.body });
const need = new Map();
for (const q of qs) for (const c of q.cands) if (!text.has(c)) { const [src, id] = c.split('|'); (need.get(src) ?? need.set(src, new Set()).get(src)).add(id); }
const Q = {
  kb_chunks: (ids) => `select id::text id, title, content body from public.kb_chunks where id = any(${lit(ids.map(Number))}::bigint[])`,
  company_faq: (ids) => `select id::text id, question title, answer body from public.company_faq where id = any(${lit(ids.map(Number))}::bigint[])`,
  agent_knowledge: (ids) => `select id::text id, topic title, content body from public.agent_knowledge where id = any(${lit(ids.map(Number))}::bigint[])`,
  ops_knowledge: (ids) => `select case when length(record_id) > 60 then 'md5:' || left(md5(record_id),16) else record_id end id, title, content body from public.ops_knowledge where record_id = any(${lit(ids)}) or 'md5:' || left(md5(record_id),16) = any(${lit(ids)})`,
  support_knowledge: (ids) => `select record_id id, title, body from public.support_knowledge where record_id = any(${lit(ids)})`,
  sales_knowledge: (ids) => `select record_id id, title, content body from public.sales_knowledge where record_id = any(${lit(ids)})`,
  ceo_knowledge: (ids) => `select record_id id, title, body from public.ceo_knowledge where record_id = any(${lit(ids)})`,
};
for (const [src, ids] of need) { if (!Q[src]) continue; const list = [...ids];
  for (let i = 0; i < list.length; i += 400) for (const r of await sql(Q[src](list.slice(i, i + 400)), { readOnly: true })) text.set(src + '|' + r.id, { title: r.title, body: r.body }); }

// THE SANCTIONED ROUTE: this run's own tagged rehearsal window (x-qd-e2e-run + the service-role bearer + the internal
// secret), a ZZ DEMO subject, the generic gateway credential, and the seat's REAL calling function name. The paid gate
// enforces the window's cap; ai_cost_log tags every row with the run.
const secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
const RUN = process.env.QD_RUN_TAG, SUBJECT = JSON.parse(process.env.QD_SUBJECT || 'null');
if (!/^[a-z0-9]{4,16}$/.test(RUN || '') || !SUBJECT || !process.env.QD_SERVICE || !process.env.QD_E2E_SECRET) { console.error('needs QD_RUN_TAG, QD_SUBJECT, QD_SERVICE, QD_E2E_SECRET'); process.exit(2); }
const HEAD = { 'Content-Type': 'application/json', Authorization: 'Bearer ' + process.env.QD_SERVICE, 'x-qd-e2e-run': RUN, 'x-qd-e2e-secret': process.env.QD_E2E_SECRET };
const FN_OF = { sales_engineer: 'sales_engineer', customer_support: 'wa_inbound' };
const LIMIT = +(process.env.LIMIT || 0);
const K = await import('file:///' + REPO + '/scripts/kb/knowledge_rerank.mjs');
const SYS = K.RERANK_SYSTEM;
const cp = S + '/rerank_cache.json'; const cache = existsSync(cp) ? JSON.parse(readFileSync(cp, 'utf8')) : {};
// Breaker guard: the shared breaker opens at 3 consecutive failures per model, so this run stops at 3 consecutive
// empty/failed replies of its own, before it can be the one that opens it.
let streak = 0; const bad = () => { if (++streak >= 3) { console.error('ABORT: 3 consecutive empty or failed replies'); writeFileSync(cp, JSON.stringify(cache)); process.exit(4); } };
let calls = 0, cached = 0, failed = 0, inTok = 0, outTok = 0; const models = {};
async function rerank(q) {
  const input = K.rerankInput(q.text, q.cands.map((c) => { const t = text.get(c) ?? {}; return { title: t.title, excerpt: String(t.body ?? '').slice(0, 1200) }; }));
  const key = createHash('sha256').update(TASK + '|' + input).digest('hex');
  if (cache[key]) { cached++; return cache[key]; }
  for (let a = 0; a < 3; a++) {
    const r = await fetch(`https://${PROJECT_REF}.supabase.co/functions/v1/ai_gateway`, { method: 'POST', headers: HEAD,
      body: JSON.stringify({ __secret: secret, fn: FN_OF[q.seat] ?? 'sales_engineer', subject: SUBJECT, task_class: TASK, agent: q.seat, sys: SYS, input, max: K.MAX_OUT, temperature: 0, cache_ttl_min: 0, // gateway flag not deployed (train): no gateway cache; the local exact-key cache dedupes
 client_timeout_ms: 30000, response_format: { type: 'json_object' } }) }).catch(() => null);
    const j = r ? await r.json().catch(() => null) : null;
    const content = j?.content ?? null;
    if (j?.outcome && j.outcome !== 'generated' && !content) { console.error('REFUSED', j.outcome, String(j.error ?? '').slice(0, 160)); if (/cap|gate|hold|fixture/i.test(String(j.outcome) + String(j.error))) { failed++; return null; } }
    if (content) { calls++; models[j.model] = (models[j.model] ?? 0) + 1;
      const ap = K.applyRanking(q.cands, content); if (ap.reranked) streak = 0; else bad(); const ids = ap.reranked ? ap.order.slice(0, K.RERANK_TOP) : [];
      cache[key] = ids; return ids; }
    bad(); if (a === 2) { failed++; return null; }
    await new Promise((s) => setTimeout(s, 3000));
  }
}

if (LIMIT) qs.splice(LIMIT);
// Release-operator conditions: no start / stop at once while any route the seats use has an open breaker, and a hard
// spend ceiling read from ai_cost_log by this run's tag. Checked before the first call and every 25 questions.
const CEIL_AED = 5.5; // = USD 1.50, under the window's USD 2 cap
async function guard(where) {
  const open = await sql(`select model_id from public.llm_route_health where open_until > now() and model_id in ('openai/gpt-6-luna','google/gemini-3.8-flash')`, { readOnly: true });
  if (open.length) { console.error('BREAKER OPEN (' + where + '):', open.map((r) => r.model_id).join(',')); writeFileSync(cp, JSON.stringify(cache)); process.exit(6); }
  const [sp] = await sql(`select coalesce(sum(cost_aed),0)::float aed from public.ai_cost_log where e2e_run_tag = ${lit(RUN)}`, { readOnly: true });
  if (sp.aed >= CEIL_AED) { console.error('SPEND CEILING', sp.aed); writeFileSync(cp, JSON.stringify(cache)); process.exit(7); }
}
await guard('start');
const conc = 2; let i = 0; // throttle: two lanes, 1.5 s between calls per lane
await Promise.all(Array.from({ length: conc }, async () => { while (i < qs.length) {
  // quiet window 02:00-05:00 Dubai (22:00-01:00Z); hold 02:50-03:10 (22:50-23:10Z); stop at 04:55
  for (;;) { const d = new Date(), m = d.getUTCHours() * 60 + d.getUTCMinutes();
    if (!(m >= 22 * 60 || m < 55)) { console.error('STOP: outside the quiet window'); writeFileSync(cp, JSON.stringify(cache)); process.exit(5); }
    if (m >= 22 * 60 + 50 && m < 23 * 60 + 10) { await new Promise((r) => setTimeout(r, 30000)); continue; } break; }
  if (i % 25 === 0) await guard('q' + i);
  const q = qs[i++]; if (!q) break; const ids = await rerank(q); await new Promise((s) => setTimeout(s, 1500));
  const order = ids ? [...ids, ...q.cands.filter((c) => !ids.includes(c))] : q.cands;
  const top = order.slice(0, 5).map((c) => c.split('|')[1].replace(/@ar$/, ''));
  const f = new Set(top.filter((x) => q.expected.includes(x))).size; q.rr = q.any ? (f > 0 ? 1 : 0) : f / new Set(q.expected).size;
  if (i % 200 === 0) { writeFileSync(cp, JSON.stringify(cache)); process.stderr.write('r' + i + ' '); } } }));
writeFileSync(cp, JSON.stringify(cache));
const mean = (a) => a.reduce((s, x) => s + x, 0) / a.length;
for (const key of ['recall', 'rr']) {
  const pairs = {}; for (const q of qs) (pairs[q.pack + '|' + q.seat + '|' + q.lang] ??= []).push(q[key]);
  for (const set of ['market', 'trade']) for (const lang of ['en', 'ar']) { const v = Object.entries(pairs).filter(([k]) => k.endsWith('|' + lang) && (k.split('|')[0].endsWith('.market')) === (set === 'market')).map(([, a]) => mean(a));
    console.log('RERANK', key === 'rr' ? 'after ' : 'before', set, lang, 'pairs', v.length, 'mean', mean(v).toFixed(3), 'below.35', v.filter((x) => x < 0.35).length); }
}
console.log('CALLS', JSON.stringify({ calls, cached, failed, inTok, outTok, models }));
writeFileSync(S + '/rerank_out.json', JSON.stringify(qs.map(({ cands, ...q }) => q)));
