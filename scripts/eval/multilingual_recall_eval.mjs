// WHICH EMBEDDER FINDS EACH SEAT'S KNOWLEDGE, IN ENGLISH AND IN ARABIC? recall@5 per seat and language.
// Seat: it_engineer (the shared knowledge platform). 23 Sep 2026.
//
// Measured 23 Sep 2026 (PR #897's staged eval): recall@5 EN ceo 0.411, accountant 0.465; Arabic 0.00-0.08
// on every seat, because gte-small is an English-only model. This file compares embedders on the SAME
// questions, the SAME pool and the SAME ranking, so a before/after is one variable at a time:
//
//   questions  every verified pack's eval (knowledge/packs|seats/*.json), each asked in English AND Arabic,
//              with the entry ids that answer it; an Arabic row '<id>@ar' counts as its entry.
//   pool       per seat, what fn_reason_retrieve_ml reads for that seat, fetched READ-ONLY from production:
//              ops_knowledge (company-wide), agent_knowledge (the seat + _global), company_faq, the seat's own
//              table(s) — plus the pack rows that seat reads (a trade pack: sales_engineer and customer_support).
//              kb_chunks (150k rows, read for every seat) enters as candidates: --kb N (see below).
//              NOT in the pool: the research candidates (0 rows today).
//   ranking    fn_reason_retrieve's (today) and fn_reason_retrieve_ml's (fused), mirrored step for step: the top
//              K of each source, the union by score, and for the new routine the seat's own rows first (up to
//              OWN). recall@5 is over the first five rows in the order the routine returns them.
//
// Embedding runs HERE, locally, with @huggingface/transformers (ONNX, CPU; not a dependency of the app: install it
// for the run with `npm i --no-save @huggingface/transformers@3.8.1`): gte-small is Supabase/gte-small
// (the weights Supabase.ai.Session('gte-small') runs) and the multilingual model is the one the edge path
// loads (_shared/ml_embed.ts). Nothing is written to production. Vectors are cached by sha256 in the OS
// temp directory, never the repository.
//
//   node scripts/eval/multilingual_recall_eval.mjs --knowledge <dir with packs/ and seats/> [--kb 20] [--out r.json]
//
// It also prints the CORROBORATION floor equivalent: the multilingual similarity below which the same share
// of English questions' best row falls as falls below 0.84 under gte-small (think.ts CORROBORATION_FLOOR_ML).
//
// Exit 1 when a seat's English recall under the chosen path (the LAST variant) falls below today's (the first),
// or its Arabic falls below AR_FLOOR. The floors are set from the first measured run and never lowered.
//
// RUN 23 Sep 2026, --kb 20 (9,257 kb_chunks candidates; pool 17,116; 1,094 questions per language), recall@5:
//                     today (gte-small)   gte + own first   e5 + own first    fused + own first (fn_reason_retrieve_ml)
//   sales_engineer    EN .617 AR .059     EN .684 AR .094   EN .672 AR .630   EN .717 AR .547
//   customer_support  EN .626 AR .059     EN .696 AR .091   EN .687 AR .646   EN .730 AR .529
//   accountant        EN .465 AR .000     EN .715 AR .021   EN .653 AR .646   EN .715 AR .569
//   ceo               EN .396 AR .000     EN .547 AR .057   EN .583 AR .672   EN .583 AR .609
//   it_engineer       EN .728 AR .000     EN .794 AR .178   EN .675 AR .817   EN .811 AR .589
//   marketing         EN .600 AR .067     EN .711 AR .200   EN .683 AR .694   EN .750 AR .517
// RUN 24 Sep 2026, same flags, with the model production loads (the Arabic+English trim, _shared/ml_embed_recipe.ts):
//   sales_engineer    today EN .617 AR .059 | e5 EN .676 AR .631 | fused EN .716 AR .540
//   customer_support  today EN .626 AR .059 | e5 EN .686 AR .647 | fused EN .727 AR .536
//   accountant        today EN .444 AR .000 | e5 EN .653 AR .653 | fused EN .715 AR .604
//   ceo               today EN .396 AR .000 | e5 EN .583 AR .646 | fused EN .542 AR .625
//   it_engineer       today EN .728 AR .000 | e5 EN .675 AR .833 | fused EN .828 AR .589
//   marketing         today EN .600 AR .067 | e5 EN .683 AR .678 | fused EN .767 AR .517
// Against the 23 Sep full-model run: e5 within 0.02 everywhere; fused within 0.05 (ceo EN .583 -> .542). EVAL OK.
// Without kb_chunks the fused path is EN .578-.833, AR .544-.656. Corroboration equivalent: 0.833 (both runs).
// Chunking rows by paragraph (an earlier variant) lowered every seat and was dropped.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import { ML_MODEL, ML_QUERY_PREFIX, ML_PASSAGE_PREFIX, rowText, modelHost } from '../kb/ml_embed_recipe.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const at = (f) => { const i = process.argv.indexOf(f); return i >= 0 ? process.argv[i + 1] : null; };
export const K = 6, TOP = 5, OWN = 3;
// FLOORS, from the first run (23 Sep 2026, see the PR): Arabic recall@5 under the multilingual path per seat.
// English is gated against the gte-small baseline on the same pool: the switch must not cost English recall.
export const AR_FLOOR = 0.5;

const SEAT_OWN = {
  sales_engineer: ['sales_knowledge'], customer_support: ['support_knowledge'], accountant: ['accountant_knowledge'],
  it_engineer: ['it_engineer_knowledge'], ceo: ['ceo_knowledge'], marketing: ['marketing_knowledge'],
};
const TRADE_SEATS = ['sales_engineer', 'customer_support'];
const sha = (s) => createHash('sha256').update(s).digest('hex');

// ── questions and pack rows ─────────────────────────────────────────────────────────────────────
const kdir = at('--knowledge') ?? join(REPO, 'knowledge');
const packs = [];
for (const [dir, kind] of [['packs', 'trade'], ['seats', 'seat']]) {
  const d = join(kdir, dir);
  if (!existsSync(d)) continue;
  for (const f of (await import('node:fs')).readdirSync(d).sort()) {
    const m = f.match(/^([a-z_]+)(\.market)?\.json$/);
    if (!m || (kind === 'seat' && m[2])) continue;
    packs.push({ kind, code: m[1], key: m[1] + (m[2] ?? ''), pack: JSON.parse(readFileSync(join(d, f), 'utf8')) });
  }
}
if (!packs.length) { console.error(`no packs under ${kdir}`); process.exit(2); }
const seatsOf = (p) => (p.kind === 'trade' ? TRADE_SEATS : [p.code]);
const packRows = packs.flatMap((p) => p.pack.entries.flatMap((e) => ['en', 'ar'].map((lang) => ({
  src: p.kind === 'trade' ? 'sales_knowledge' : SEAT_OWN[p.code][0], trade: p.kind === 'trade',
  id: lang === 'en' ? e.id : e.id + '@ar', title: lang === 'ar' && e.topic_ar ? e.topic_ar : e.topic, body: lang === 'en' ? e.body_en : e.body_ar, seat: p.kind === 'trade' ? null : p.code,
}))));
const qs = packs.flatMap((p) => (p.pack.eval ?? []).flatMap((q) => ['en', 'ar'].flatMap((lang) => seatsOf(p).map((seat) =>
  ({ pack: p.key, seat, lang, text: lang === 'en' ? q.q_en : q.q_ar, expected: [...new Set(q.expected_entry_ids)] })))));

// ── the live pool, read-only ────────────────────────────────────────────────────────────────────
const { sql, PROJECT_REF } = await import('../lib/db.mjs');
const Q = [
  `select 'ops_knowledge' src, record_id id, title, content body, null seat from public.ops_knowledge where runtime_eligible and supersession_state = 'current' and scope_type in ('company','external_source','category')`,
  `select 'agent_knowledge' src, id::text id, topic title, content body, agent_key seat from public.agent_knowledge where agent_key in ('_global','ceo','accountant','sales_engineer','customer_support','it_engineer','marketing')`,
  `select 'company_faq' src, id::text id, question title, answer body, null seat from public.company_faq where status = 'approved'`,
  `select 'sales_knowledge' src, record_id id, title, content body, null seat from public.sales_knowledge where runtime_index_eligible`,
  `select 'accountant_knowledge' src, record_id id, title, content body, null seat from public.accountant_knowledge where runtime_index_eligible`,
  `select 'it_engineer_knowledge' src, record_id id, title, content body, null seat from public.it_engineer_knowledge where runtime_index_eligible`,
  `select 'support_knowledge' src, record_id id, title, body, null seat from public.support_knowledge`,
  `select 'ceo_knowledge' src, record_id id, title, body, null seat from public.ceo_knowledge`,
];
const packIds = new Set(packRows.map((p) => p.id));
const live = (await Promise.all(Q.map((s) => sql(s, { readOnly: true })))).flat().filter((r) => !packIds.has(r.id));

// ── the embedders ───────────────────────────────────────────────────────────────────────────────
const { pipeline, env } = await import('@huggingface/transformers');
const cachePath = join(tmpdir(), 'qd_ml_recall_eval_vectors.json');
const cache = existsSync(cachePath) ? JSON.parse(readFileSync(cachePath, 'utf8')) : {};
async function embedder(model) {
  Object.assign(env, modelHost(model, `https://${PROJECT_REF}.supabase.co`));
  const f = await pipeline('feature-extraction', model, { dtype: 'q8' });
  return async (texts) => {
    const out = new Array(texts.length), todo = [];
    texts.forEach((t, i) => { const k = model + ':' + sha(t); if (cache[k]) out[i] = cache[k]; else todo.push(i); });
    for (let i = 0; i < todo.length; i += 16) {
      const part = todo.slice(i, i + 16);
      const v = (await f(part.map((j) => texts[j]), { pooling: 'mean', normalize: true })).tolist();
      part.forEach((j, n) => { out[j] = v[n].map((x) => +x.toFixed(6)); cache[model + ':' + sha(texts[j])] = out[j]; });
      if (i % 320 === 0) process.stdout.write(`\r  ${model}: ${i}/${todo.length}   `);
    }
    writeFileSync(cachePath, JSON.stringify(cache));
    return out;
  };
}
const dot = (a, b) => { let s = 0; for (let i = 0; i < a.length; i++) s += a[i] * b[i]; return s; };

// kb_chunks (150k rows) is read by the routine for every seat and is where the seats' own knowledge gets
// crowded out, so it cannot be left out; it cannot be embedded whole locally either. --kb N takes, for each
// English question, the N nearest kb_chunks by the LIVE gte-small index (read-only), and puts the union in
// every seat's pool for every variant. The Arabic question shares its English twin's candidates. What this
// cannot see: a chunk outside every question's gte top N that the multilingual model would rank high. That
// can only add crowding to the multilingual variants, so their numbers here are an upper bound on that side.
const KB_N = Number(at('--kb') ?? 0);
const kbRows = [];
if (KB_N > 0) {
  const gte = await embedder('Supabase/gte-small');
  const en = [...new Set(qs.filter((q) => q.lang === 'en').map((q) => q.text))];
  const ev = await gte(en);
  const ids = new Set();
  for (let i = 0; i < en.length; i += 20) {
    const part = ev.slice(i, i + 20);
    const r = await sql(`select array[${part.map((v) => `array(select id from public.kb_chunks where embedding_gte is not null order by embedding_gte <=> '[${v.join(',')}]'::vector(384) limit ${KB_N})`).join(',')}] ids`, { readOnly: true });
    r[0].ids.flat().forEach((x) => ids.add(x));
  }
  const list = [...ids];
  for (let i = 0; i < list.length; i += 2000) {
    kbRows.push(...await sql(`select 'kb_chunks' src, id::text id, title, content body, null seat from public.kb_chunks where id = any('{${list.slice(i, i + 2000).join(',')}}'::bigint[])`, { readOnly: true }));
  }
  console.log(`kb_chunks candidates: ${kbRows.length} (top ${KB_N} per English question by the live gte-small index)`);
}
const pool = [...live, ...kbRows, ...packRows];
console.log(`packs ${packs.length}, questions ${qs.length}, pool ${pool.length} (${live.length} live + ${kbRows.length} kb_chunks + ${packRows.length} pack rows)`);

// THE SPACES: each model embeds every pool row once (rowText: title + body, cut at 1,200 characters, as the
// gateway cuts) and every question once. Chunking a row by paragraph was measured and made every seat WORSE
// (23 Sep 2026: e5 EN 0.625-0.705 chunked vs 0.646-0.722 whole), so a row is one vector.
const SPACES = {
  gte: { model: 'Supabase/gte-small', row: (r) => rowText(r.title, r.body), q: (t) => t },
  ml: { model: ML_MODEL, row: (r) => ML_PASSAGE_PREFIX + rowText(r.title, r.body), q: (t) => ML_QUERY_PREFIX + t },
};
const sims = {};
for (const [name, sp] of Object.entries(SPACES)) {
  const emb = await embedder(sp.model);
  const rv = await emb(pool.map(sp.row));
  const qv = await emb(qs.map((q) => sp.q(q.text)));
  sims[name] = (qi, i) => dot(rv[i], qv[qi]);
}
// A VARIANT: which space ranks ('fused' = fn_reason_retrieve_ml's fusion, mirrored line for line below), and
// whether the seat's own rows come first (up to OWN of them).
export const FUSE_N = 20;
const variants = [
  { name: 'gte-small (today: fn_reason_retrieve)', space: 'gte', own: false },
  { name: 'gte-small, own knowledge first', space: 'gte', own: true },
  { name: 'multilingual-e5-small, own knowledge first', space: 'ml', own: true },
  { name: 'both spaces fused, own knowledge first (fn_reason_retrieve_ml)', space: 'fused', own: true },
];
const only = at('--variants');
const runVariants = only ? variants.filter((_, i) => only.split(',').includes(String(i))) : variants;

function poolFor(seat) {
  const own = SEAT_OWN[seat];
  return pool.filter((r) => own.includes(r.src) && (r.seat == null || r.seat === seat)
    || (seat === 'customer_support' && r.trade)
    || ['ops_knowledge', 'company_faq', 'kb_chunks'].includes(r.src)
    || (r.src === 'agent_knowledge' && [seat, '_global'].includes(r.seat)));
}
const isOwn = (seat, r) => SEAT_OWN[seat].includes(r.src) || (seat === 'customer_support' && r.trade) || (r.src === 'agent_knowledge' && r.seat === seat);
const report = { at: new Date().toISOString(), k: K, top: TOP, own_slots: OWN, fuse_n: FUSE_N, pool: pool.length, kb_candidates: kbRows.length, variants: [] };
const bySeat = {};
const groupBySrc = (idx) => { const o = {}; for (const i of idx) (o[pool[i].src] ??= []).push(i); return o; };
for (const v of runVariants) {
  for (const [qi, q] of qs.entries()) {
    const idx = (bySeat[q.seat] ??= poolFor(q.seat).map((r) => pool.indexOf(r)));
    let scored;
    if (v.space === 'fused') {
      // candidates: per source, the FUSE_N nearest in each space
      const cand = new Set();
      for (const rows of Object.values(groupBySrc(idx))) for (const sp of ['gte', 'ml']) {
        rows.map((i) => [i, sims[sp](qi, i)]).sort((x, y) => y[1] - x[1]).slice(0, FUSE_N).forEach(([i]) => cand.add(i));
      }
      const c = [...cand];
      const rankOf = (sp) => { const o = c.map((i) => [i, sims[sp](qi, i)]).sort((x, y) => y[1] - x[1]); return { r: new Map(o.map(([i], n) => [i, n + 1])), d: o[0][1] - o[Math.min(FUSE_N, o.length - 1)][1] }; };
      const g = rankOf('gte'), m = rankOf('ml');
      const [wg, wm] = g.d + m.d > 0 ? [g.d / (g.d + m.d), m.d / (g.d + m.d)] : [0, 1];
      scored = c.map((i) => ({ r: pool[i], s: wg / (60 + g.r.get(i)) + wm / (60 + m.r.get(i)), ml: sims.ml(qi, i) }));
    } else scored = idx.map((i) => ({ r: pool[i], s: sims[v.space](qi, i) }));
    const bySrc = {};
    for (const h of scored) (bySrc[h.r.src] ??= []).push(h);
    const union = Object.values(bySrc).flatMap((x) => x.sort((p, r) => r.s - p.s).slice(0, K)).sort((x, y) => y.s - x.s);
    // the order a caller reads: the seat's own best first (up to OWN), then the rest by score
    const mine = v.own ? union.filter((h) => isOwn(q.seat, h.r)).slice(0, OWN) : [];
    const order = [...mine, ...union.filter((h) => !mine.includes(h))];
    const got = new Set(order.slice(0, TOP).map((h) => String(h.r.id).replace(/@ar$/, '')));
    if (v.space !== 'fused') q[v.space + ':best'] = union[0]?.s ?? 0;
    q[v.name] = q.expected.filter((e) => got.has(e)).length / q.expected.length;
  }
  const seats = [...new Set(qs.map((q) => q.seat))];
  const mean = (x) => x.reduce((s, y) => s + y, 0) / x.length;
  const res = { name: v.name, seats: Object.fromEntries(seats.map((s) => [s, {
    en: +mean(qs.filter((q) => q.seat === s && q.lang === 'en').map((q) => q[v.name])).toFixed(3),
    ar: +mean(qs.filter((q) => q.seat === s && q.lang === 'ar').map((q) => q[v.name])).toFixed(3),
    questions: qs.filter((q) => q.seat === s).length / 2 }])) };
  report.variants.push(res);
  console.log('\n' + v.name);
  for (const [s, r] of Object.entries(res.seats)) console.log(`  ${s.padEnd(18)} EN ${r.en.toFixed(3)}  AR ${r.ar.toFixed(3)}  (${r.questions})`);
}
// The corroboration floor in the ml space, matched by share: the fraction of English questions whose best row
// is below 0.84 under gte-small, and the multilingual similarity with the same fraction below it.
{
  const en = qs.filter((q) => q.lang === 'en' && q['gte:best'] != null && q['ml:best'] != null);
  if (en.length) {
    const share = en.filter((q) => q['gte:best'] < 0.84).length / en.length;
    const b = en.map((q) => q['ml:best']).sort((x, y) => x - y);
    const eq = b[Math.min(b.length - 1, Math.floor(share * b.length))];
    report.corroboration_floor_ml = +eq.toFixed(3);
    console.log(`corroboration: ${(share * 100).toFixed(1)}% of English questions are below 0.84 under gte-small; the same share is below ${eq.toFixed(3)} under multilingual-e5-small`);
  }
}
if (at('--out')) writeFileSync(at('--out'), JSON.stringify(report, null, 1));

// ── the gate: the chosen path (the LAST variant) against today's (the first) ────────────────────────
if (runVariants.length === variants.length) {
  const base = report.variants[0], chosen = report.variants.at(-1);
  const bad = Object.entries(chosen.seats).filter(([s, r]) => r.en < base.seats[s].en || r.ar < AR_FLOOR);
  for (const [s, r] of bad) console.log(`BELOW: ${s} EN ${r.en} (gte ${base.seats[s].en}) AR ${r.ar} (floor ${AR_FLOOR})`);
  console.log(bad.length ? 'EVAL FAILED' : 'EVAL OK');
  process.exitCode = bad.length ? 1 : 0;
}
