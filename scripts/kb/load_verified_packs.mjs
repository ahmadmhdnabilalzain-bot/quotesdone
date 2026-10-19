// LOAD THE VERIFIED KNOWLEDGE PACKS INTO EACH SEAT'S DECISION-TIME RETRIEVAL. Seat: it_engineer, 23 Sep 2026.
//
// Two steps, both named on the command line:
//
//   node scripts/kb/load_verified_packs.mjs --import <dir>   # copy every VERIFIED pack from <dir>/packs and
//                                                           # <dir>/seats into knowledge/ (the repo copy is the
//                                                           # source of truth: version-controlled, auditable)
//   node scripts/kb/load_verified_packs.mjs                  # DRY RUN: validate knowledge/, print the plan
//   node scripts/kb/load_verified_packs.mjs --apply          # embed (free gte-small) + upsert + retire, then
//                                                           # enqueue the multilingual (ml) vectors and wait
//   --wait-minutes=N   how long --apply polls for the ml vectors before reporting what is left (default 20)
//
// WHERE EACH PACK GOES (scripts/sql/every_verified_pack_has_a_home_and_every_seat_reads_its_own.sql):
// a trade pack -> sales_knowledge tagged 'trade:<code>', read by sales_engineer and customer_support; a seat
// pack -> that seat's own table. Every entry is two rows, '<id>' in English and '<id>@ar' in Arabic, each
// embedded, so a question in either language is matched by meaning (never by a word).
//
// WHAT IS REFUSED AT THE DOOR, before any write: a pack the gate does not pass (no `verified` block, or more
// than 10% unsourced / low-confidence technical entries), a malformed entry, an id outside its pack's prefix,
// an id in two packs, an eval question expecting an entry the pack does not hold, and a trade code that is
// not in public.taxonomy_trade (the tag would point at nothing). A refused pack stops the whole run: a partial
// load would retire the refused pack's rows as if it had been withdrawn.
//
// RELOAD. Upsert on record_id (re-running replaces, never duplicates); then every verified_pack row whose
// record_id is not in this load is deleted, table by table. A retired entry, or a pack removed from
// knowledge/, is gone from retrieval after the next run. Only rows tagged 'verified_pack' are ever touched.
//
// THE ML VECTOR (19 Oct 2026). think() reads the multilingual space, and this loader embeds gte-small only. After
// that day's reload 0 of 268 marketing and 0 of 4,674 eligible trade-pack rows had an ml vector. The ml vectors come
// from the queue (fn_ml_embed_claim / fn_ml_embed_write); a written row is already due there (no vector, or
// z_ml_vectors_stale dropped the stale one), so --apply records the load in agent_runs (job verified_pack_load, the
// clock duty:pack_ml_vectors measures ceo/support rows from), dispatches ml-embed-backfill.yml, polls for exactly
// the rows it wrote, and reports how many still lack a fresh vector. The dry run prints that plan with today's counts.
//
// Nothing here calls a paid model: the embedder is ai_gateway {action:'embed'}, gte-small in the edge runtime.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { readPacks, listPackFiles, validate, rowsOf, upsertSql, makeEmbedder, TABLES, lit, vecLit } from './verified_packs.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const KNOWLEDGE = join(REPO, 'knowledge');
const at = (f) => { const i = process.argv.indexOf(f); return i >= 0 ? process.argv[i + 1] : null; };
const IMPORT = at('--import');
const APPLY = process.argv.includes('--apply');
const WAIT_MINUTES = Number((process.argv.find((a) => a.startsWith('--wait-minutes=')) || '--wait-minutes=20').split('=')[1]);

if (IMPORT) {
  // Copy what is verified; name what is not. The copy is byte-for-byte, so its sha is the pack version.
  let copied = 0; const refused = [];
  for (const p of listPackFiles(IMPORT)) {
    const text = readFileSync(p.file, 'utf8');
    let err;
    try { err = validate(JSON.parse(text), p.kind, p.code); } catch (e) { err = ['not JSON: ' + e.message]; }
    if (err.length) { refused.push(`${p.rel}: ${err.slice(0, 3).join('; ')}`); continue; }
    mkdirSync(join(KNOWLEDGE, dirname(p.rel)), { recursive: true });
    writeFileSync(join(KNOWLEDGE, p.rel), text);
    copied++;
  }
  console.log(`imported ${copied} verified pack(s) into knowledge/`);
  for (const r of refused) console.log('  NOT IMPORTED ' + r);
  if (!APPLY) process.exit(0);
}

const packs = readPacks(KNOWLEDGE);
const refused = packs.filter((p) => p.errors.length);
for (const p of refused) console.log(`REFUSED ${p.rel}\n  ${p.errors.slice(0, 8).join('\n  ')}`);
if (!packs.length) { console.error('no packs under knowledge/'); process.exit(2); }
if (refused.length) process.exit(2);

const rows = packs.flatMap(rowsOf);
const byTable = Object.fromEntries(TABLES.map((t) => [t, rows.filter((r) => r.table === t)]));
console.log(`${packs.length} pack(s), ${rows.length / 2} entries, ${rows.length} rows (EN + AR):`);
for (const [t, rs] of Object.entries(byTable)) console.log(`  ${t.padEnd(22)} ${rs.length}`);
// The ml vectors of exactly these rows: eligible (in v_knowledge_ml_source, with a body) and fresh (text_hash
// matches the text the database holds now). An ineligible row is never retrieved, so it is not owed a vector.
async function mlState(run) {
  const out = {};
  for (const [table, rs] of Object.entries(byTable)) {
    if (!rs.length) continue;
    const [c] = await run(`select count(*)::int eligible, count(v.row_id)::int fresh
        from public.v_knowledge_ml_source s
        left join public.knowledge_vector_ml v on v.src = s.src and v.row_id = s.row_id
             and v.text_hash = md5(coalesce(s.title, '') || E'\\n' || coalesce(s.body, ''))
       where s.src = ${lit(table)} and s.row_id = any(${lit(rs.map((r) => r.record_id))}) and btrim(coalesce(s.body, '')) <> ''`);
    out[table] = c;
  }
  return out;
}
const owed = (st) => Object.values(st).reduce((n, c) => n + c.eligible - c.fresh, 0);
const printMl = (st) => { for (const [t, c] of Object.entries(st)) console.log(`  ${t.padEnd(22)} eligible ${c.eligible}, fresh ml vector ${c.fresh}, still owed ${c.eligible - c.fresh}`); };

if (!APPLY) {
  console.log(`ENQUEUE PLAN after --apply: record the load (agent_runs job verified_pack_load), dispatch ml-embed-backfill.yml,`
    + ` poll up to ${WAIT_MINUTES} min for the ml vectors of these ${rows.length} rows, report what is left.`);
  try {
    const { sql } = await import('../lib/db.mjs');
    console.log('ml vectors of these record_ids in production now (a row whose text the load changes becomes owed again):');
    printMl(await mlState((q) => sql(q, { readOnly: true })));
  } catch (e) { console.log(`  (production not read: ${String(e.message || e).slice(0, 160)})`); }
  console.log('DRY RUN: nothing written. --apply to embed and load.');
  process.exit(0);
}

const { sql, PROJECT_REF } = await import('../lib/db.mjs');

const trades = new Set((await sql(`select code from public.taxonomy_trade`, { readOnly: true })).map((r) => r.code));
const unknown = packs.filter((p) => p.kind === 'trade' && !trades.has(p.code)).map((p) => p.code);
if (unknown.length) { console.error(`REFUSED: not in taxonomy_trade: ${unknown.join(', ')}`); process.exit(2); }

const embedder = await makeEmbedder(sql, PROJECT_REF);
const vecs = await embedder.many(rows.map((r) => r.text));
rows.forEach((r, i) => { r.vec = vecs[i]; });
console.log(`embedded ${rows.length} rows (gte-small, free path)`);

for (const [table, rs] of Object.entries(byTable)) {
  for (let i = 0; i < rs.length; i += 20) await sql(upsertSql(table, rs.slice(i, i + 20)));
  // A text change past gte-small's cut embeds to the SAME vector, and the table's text-change trigger then clears
  // it (it cannot tell a fresh vector from a stale one that equals it). Measured 24 Sep 2026: 5 support and 2 ceo
  // rows. Their text is unchanged now, so writing the vector alone is not undone.
  const bare = new Set((await sql(`select record_id from public.${table} where tags @> array['verified_pack'] and embedding_gte is null`)).map((r) => r.record_id));
  for (const r of rs.filter((x) => bare.has(x.record_id))) await sql(`update public.${table} set embedding_gte = ${vecLit(r.vec)} where record_id = ${lit(r.record_id)}`);
  // Retire: a verified_pack row this load does not carry. The id list is this table's complete load.
  const gone = await sql(`delete from public.${table} where tags @> array['verified_pack']
      and not (record_id = any(${rs.length ? lit(rs.map((r) => r.record_id)) : `'{}'::text[]`})) returning record_id`);
  const [c] = await sql(`select count(*)::int n, count(embedding_gte)::int embedded from public.${table} where tags @> array['verified_pack']`, { readOnly: true });
  console.log(`  ${table.padEnd(22)} upserted ${rs.length}, retired ${gone.length}, in the table ${c.n} (embedded ${c.embedded})`);
  if (c.n !== rs.length || c.embedded !== rs.length) { console.error(`  MISMATCH in ${table}: loaded ${rs.length}, table holds ${c.n}/${c.embedded}`); process.exit(1); }
}
console.log('LOADED');

// Enqueue the ml vectors. The rows are already due in fn_ml_embed_claim; what was missing was a run and a count.
await sql(`insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), now(), ${lit({ job: 'verified_pack_load', rows: rows.length, packs: packs.length })}, null)`);
try {
  execFileSync('gh', ['workflow', 'run', 'ml-embed-backfill.yml', '-f', 'minutes=40'], { stdio: 'inherit' });
  console.log('dispatched ml-embed-backfill.yml');
} catch (e) {
  console.error(`COULD NOT DISPATCH ml-embed-backfill.yml (${e.message}); its 02:50 UTC schedule and the resilience_ping trickle remain`);
}
let st = await mlState(sql);
const until = Date.now() + WAIT_MINUTES * 60_000;
while (owed(st) > 0 && Date.now() < until) {
  console.log(`  ${owed(st)} row(s) still owed an ml vector; next look in 60 s`);
  await new Promise((r) => setTimeout(r, 60_000));
  st = await mlState(sql);
}
printMl(st);
console.log(owed(st) ? `NOT YET EMBEDDED: ${owed(st)} row(s) still lack a fresh ml vector after ${WAIT_MINUTES} min. `
  + 'The queue keeps serving them; duty:pack_ml_vectors raises any still owed an hour after this load.'
  : 'ML EMBEDDED: every loaded row has a fresh ml vector');
