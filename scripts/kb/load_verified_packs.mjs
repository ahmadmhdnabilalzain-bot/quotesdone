// LOAD THE VERIFIED KNOWLEDGE PACKS INTO EACH SEAT'S DECISION-TIME RETRIEVAL. Seat: it_engineer, 23 Sep 2026.
//
// Two steps, both named on the command line:
//
//   node scripts/kb/load_verified_packs.mjs --import <dir>   # copy every VERIFIED pack from <dir>/packs and
//                                                           # <dir>/seats into knowledge/ (the repo copy is the
//                                                           # source of truth: version-controlled, auditable)
//   node scripts/kb/load_verified_packs.mjs                  # DRY RUN: validate knowledge/, print the plan
//   node scripts/kb/load_verified_packs.mjs --apply          # embed (free gte-small) + upsert + retire
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
// Nothing here calls a paid model: the embedder is ai_gateway {action:'embed'}, gte-small in the edge runtime.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readPacks, listPackFiles, validate, rowsOf, upsertSql, makeEmbedder, TABLES, lit } from './verified_packs.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const KNOWLEDGE = join(REPO, 'knowledge');
const at = (f) => { const i = process.argv.indexOf(f); return i >= 0 ? process.argv[i + 1] : null; };
const IMPORT = at('--import');
const APPLY = process.argv.includes('--apply');

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
if (!APPLY) { console.log('DRY RUN: nothing written. --apply to embed and load.'); process.exit(0); }

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
  // Retire: a verified_pack row this load does not carry. The id list is this table's complete load.
  const gone = await sql(`delete from public.${table} where tags @> array['verified_pack']
      and not (record_id = any(${rs.length ? lit(rs.map((r) => r.record_id)) : `'{}'::text[]`})) returning record_id`);
  const [c] = await sql(`select count(*)::int n, count(embedding_gte)::int embedded from public.${table} where tags @> array['verified_pack']`, { readOnly: true });
  console.log(`  ${table.padEnd(22)} upserted ${rs.length}, retired ${gone.length}, in the table ${c.n} (embedded ${c.embedded})`);
  if (c.n !== rs.length || c.embedded !== rs.length) { console.error(`  MISMATCH in ${table}: loaded ${rs.length}, table holds ${c.n}/${c.embedded}`); process.exit(1); }
}
console.log('LOADED');
