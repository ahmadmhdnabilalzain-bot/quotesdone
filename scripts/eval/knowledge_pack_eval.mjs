// DOES EACH SEAT FIND ITS VERIFIED PACK WHEN IT DECIDES? recall@5 per pack and per seat. Seat: it_engineer, 23 Sep 2026.
//
// Every pack under knowledge/ carries eval questions, each in English and Arabic, with the entry ids that
// answer it. Each question is embedded by the SAME free gte-small path think() uses and put to the SAME
// routine the seat calls at decision time -- public.fn_reason_retrieve(seat, vector, 6) -- for every seat
// that reads the pack (a trade pack: sales_engineer and customer_support; a seat pack: its seat). The first
// five rows it returns are the "top 5"; an Arabic row '<id>@ar' counts as its entry. recall@5 of a question
// is |expected entries in the top 5| / |expected|. Nothing here matches a word.
//
// TWO MODES, one routine.
//   live   (the packs are loaded and the SQL file is applied): fn_reason_retrieve is called read-only.
//   staged (before either): one ABORTED transaction per pack replays the pending SQL file, inserts the
//          pack rows that could reach the top of any source for these questions, calls the same routine,
//          and raises the hit counts back. Nothing commits. Which rows are staged is chosen by exact cosine: the
//          routine takes the top k of each source by distance, so the top 6 of a table over (live rows +
//          every pack row) equals its top 6 over (live rows + each question's own top 6 pack rows). The
//          ranking is the database's, not this file's.
//
//   node scripts/eval/knowledge_pack_eval.mjs [--mode live|staged] [--out results.json]
//
// Exit 1 when any (pack, seat) is below FLOOR. The floor is set from the first measured baseline and is
// never lowered to turn a run green (founder: never soften a check).
import { writeFileSync, existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readPacks, rowsOf, upsertSql, makeEmbedder, seatsOf, cosine, vecLit, lit, SEAT_TABLE } from '../kb/verified_packs.mjs';

export const K_RETRIEVE = 6;   // what think() passes (supabase/functions/_shared/think.ts, fn_reason_retrieve p_k)
export const TOP = 5;
// THE FLOOR, from the first baseline (staged, 23 Sep 2026, 45 packs, 1,094 question-seat pairs per language):
// English recall@5 per (pack, seat) ranged 0.378 (sales_engineer seat pack) to 0.850; seats EN 0.41-0.72.
// Floor 0.35 on English: every pack clears it today, and a pack that falls below it has lost its seat's reach.
// ARABIC IS NOT GATED BECAUSE IT DOES NOT WORK YET, and that is the finding, not a pass: Arabic recall@5 was
// 0.00-0.08 per seat (max 0.50 on one pack). gte-small is an English model; an Arabic question lands nowhere
// near its own Arabic row. The remedy is a multilingual embedder on the same free in-region path (a separate
// change: every vector column in the estate moves together), not a word list. Raise AR from 0 when it lands.
export const FLOOR = { en: 0.35, ar: 0 };

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SQL_FILE = 'scripts/sql/every_verified_pack_has_a_home_and_every_seat_reads_its_own.sql';
const PENDING_NOTE = join(REPO, 'scripts/sql/pending/every_verified_pack_has_a_home_and_every_seat_reads_its_own.txt');
const at = (f) => { const i = process.argv.indexOf(f); return i >= 0 ? process.argv[i + 1] : null; };

const { sql, PROJECT_REF } = await import('../lib/db.mjs');
const packs = readPacks(join(REPO, 'knowledge'));
const bad = packs.filter((p) => p.errors.length);
if (bad.length) { console.error('refused packs: ' + bad.map((p) => p.rel).join(', ')); process.exit(2); }
const rows = packs.flatMap(rowsOf);

let mode = at('--mode');
if (!mode) {
  const loaded = (await sql(`select (select count(*) from public.sales_knowledge where tags @> array['verified_pack'])::int n`, { readOnly: true }))[0].n;
  mode = !existsSync(PENDING_NOTE) && loaded >= rows.filter((r) => r.table === 'sales_knowledge').length ? 'live' : 'staged';
}
console.log(`mode: ${mode}  (${packs.length} packs, ${rows.length} rows)`);

// The questions: every pack's eval, both languages, for every seat that reads the pack.
const qs = packs.flatMap((p) => (p.pack.eval ?? []).flatMap((q) => ['en', 'ar'].flatMap((lang) =>
  seatsOf(p).map((seat) => ({ pack: p.key, seat, lang, text: lang === 'en' ? q.q_en : q.q_ar, expected: q.expected_entry_ids })))));
const embedder = await makeEmbedder(sql, PROJECT_REF);
const qv = await embedder.many([...new Set(qs.map((q) => q.text))]);
const vOf = new Map([...new Set(qs.map((q) => q.text))].map((t, i) => [t, qv[i]]));
qs.forEach((q) => { q.vec = vOf.get(q.text); });

// The expected entries among the first TOP rows the routine returns, counted in SQL: a staged probe reports
// through an error message the management API cuts at ~2,000 characters, so one integer per question comes back.
const hitsExpr = (q) => `(select count(distinct regexp_replace(x->>'id', '@ar$', '')) from jsonb_array_elements(public.fn_reason_retrieve('${q.seat}', ${vecLit(q.vec)}, ${K_RETRIEVE})) with ordinality t(x, n) where n <= ${TOP} and regexp_replace(x->>'id', '@ar$', '') = any(${lit(q.expected)}))`;

if (mode === 'live') {
  for (let i = 0; i < qs.length; i += 25) {
    const part = qs.slice(i, i + 25);
    // Not the API read_only flag: its role cannot EXECUTE fn_reason_retrieve (service_role only, 42501 measured
    // 23 Sep 2026). The routine is STABLE and this is one SELECT, so nothing can be written either way.
    const [r] = await sql(`select jsonb_build_array(${part.map(hitsExpr).join(',')}) got`);
    part.forEach((q, j) => { q.hits = r.got[j]; });
  }
} else {
  const rv = await embedder.many(rows.map((r) => r.text));
  rows.forEach((r, i) => { r.vec = rv[i]; });
  // The pack rows each seat's retrieval reads, per table (mirrors the WHERE clauses of fn_reason_retrieve).
  const pools = (seat) => {
    const own = rows.filter((r) => r.table === SEAT_TABLE[seat]);   // sales_engineer: its pack AND every trade pack
    if (seat === 'customer_support') return [rows.filter((r) => r.table === 'sales_knowledge' && r.cols.pack_id.startsWith('verified:trade:')), own];
    return [own];
  };
  const pending = existsSync(PENDING_NOTE) ? readFileSync(join(REPO, SQL_FILE), 'utf8') + '\n' : '';
  for (const p of packs) {
    const mine = qs.filter((q) => q.pack === p.key);
    if (!mine.length) continue;
    const stage = new Map();
    for (const q of mine) for (const pool of pools(q.seat)) {
      pool.map((r) => [r, cosine(q.vec, r.vec)]).sort((a, b) => b[1] - a[1]).slice(0, K_RETRIEVE).forEach(([r]) => stage.set(r.record_id, r));
    }
    const byTable = {};
    for (const r of stage.values()) (byTable[r.table] ??= []).push(r);
    const inserts = Object.entries(byTable).map(([t, rs]) => upsertSql(t, rs)).join('\n');
    const block = `do $qdeval$ declare o jsonb := '[]'::jsonb; begin\n${mine.map((q) => `o := o || jsonb_build_array(${hitsExpr(q)});`).join('\n')}\nraise exception 'CHK<<%>>', o::text; end $qdeval$;`;
    try { await sql(pending + inserts + block, { retry: false }); throw new Error('the probe committed instead of rolling back'); }
    catch (e) {
      const m = String(e.message).match(/CHK<<(.*?)>>/s);
      if (!m) throw new Error(`${p.key}: the probe failed before it could report: ${String(e.message).slice(0, 400)}`);
      JSON.parse(m[1]).forEach((h, j) => { mine[j].hits = h; });
    }
    process.stdout.write(`${p.key} `);
  }
  console.log();
}

// ── scoring ──────────────────────────────────────────────────────────────────────────────────────
for (const q of qs) {
  if (typeof q.hits !== 'number') throw new Error(`no answer for ${q.pack}/${q.seat}/${q.lang}: ${q.text}`);
  q.recall = q.hits / new Set(q.expected).size;
}
const mean = (a) => (a.length ? a.reduce((s, x) => s + x, 0) / a.length : NaN);
const fmt = (x) => (Number.isNaN(x) ? '  -  ' : x.toFixed(3));
const report = { mode, at: new Date().toISOString(), k: K_RETRIEVE, top: TOP, floor: FLOOR, packs: [], seats: [] };
console.log(`\nrecall@${TOP}            seat               EN     AR     all   (questions)`);
for (const p of packs) for (const seat of seatsOf(p)) {
  const m = qs.filter((q) => q.pack === p.key && q.seat === seat);
  if (!m.length) continue;
  const r = { pack: p.key, kind: p.kind, seat, en: mean(m.filter((q) => q.lang === 'en').map((q) => q.recall)),
    ar: mean(m.filter((q) => q.lang === 'ar').map((q) => q.recall)), all: mean(m.map((q) => q.recall)), questions: m.length / 2 };
  report.packs.push(r);
  console.log(`  ${p.key.padEnd(24)}${seat.padEnd(18)} ${fmt(r.en)}  ${fmt(r.ar)}  ${fmt(r.all)}  (${r.questions})`);
}
console.log('\nper seat (every question of every pack it reads):');
for (const seat of [...new Set(report.packs.map((r) => r.seat))]) {
  const m = qs.filter((q) => q.seat === seat);
  const r = { seat, en: mean(m.filter((q) => q.lang === 'en').map((q) => q.recall)), ar: mean(m.filter((q) => q.lang === 'ar').map((q) => q.recall)), all: mean(m.map((q) => q.recall)), questions: m.length / 2 };
  report.seats.push(r);
  console.log(`  ${seat.padEnd(18)} EN ${fmt(r.en)}  AR ${fmt(r.ar)}  all ${fmt(r.all)}  (${r.questions})`);
}
if (at('--out')) writeFileSync(at('--out'), JSON.stringify({ ...report, questions: qs.map(({ vec, ...q }) => q) }, null, 1));
const below = report.packs.filter((r) => !(r.en >= FLOOR.en) || !(r.ar >= FLOOR.ar));
for (const r of below) console.log(`BELOW FLOOR (EN ${FLOOR.en}, AR ${FLOOR.ar}): ${r.pack} / ${r.seat} = EN ${fmt(r.en)} AR ${fmt(r.ar)}`);
console.log(below.length ? 'EVAL FAILED' : 'EVAL OK');
process.exit(below.length ? 1 : 0);
