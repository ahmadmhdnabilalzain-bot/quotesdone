// LOAD QuotesDone_Sales_Engineer_Knowledge_v1 INTO public.sales_knowledge / sales_sector /
// sales_qualification_field.
//
// Forked from load_support_knowledge_pack.mjs, which established the pattern this estate keeps:
// read the pack's OWN allowlist, validate at the door, name every refusal, and never let an
// invalid record touch a row that is already correct.
//
// WHY THE ALLOWLIST MATTERS HERE MORE THAN IT DID THERE. Measured on the extracted pack: recursive
// folder ingestion imports 2,532 records against manifest.json's 1,136 -- a 2.23x inflation from
// the Markdown mirrors under knowledge/ (+212), the SQLite index (+1,136) and the eval scenarios
// (+48). manifest.json -> runtime_files names exactly one file, and this loader refuses any path
// that is not records/*.jsonl even if a future manifest names one.
//
// content_sha256 IS NOT sha256(content) -- it is the pack's canonical hash over the whole record
// minus that field (tools/knowledge.py:canonical_hash). It is stored VERBATIM. body_sha256 is ours,
// over title + '\n' + content, and it is what dedupe and collision reporting use.
//
//   node scripts/kb/load_sales_knowledge_pack.mjs --root <extracted pack dir> [--apply]

import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { sql } from '../lib/db.mjs';

const at = (f) => { const i = process.argv.indexOf(f); return i >= 0 ? process.argv[i + 1] : null; };
const ROOT = at('--root');
const APPLY = process.argv.includes('--apply');
if (!ROOT) { console.error('--root <extracted pack dir> is required'); process.exit(2); }

const manifest = JSON.parse(readFileSync(join(ROOT, 'manifest.json'), 'utf8'));
const FILES = manifest.runtime_files;
if (!Array.isArray(FILES) || !FILES.length) { console.error('manifest.json has no runtime_files'); process.exit(2); }
console.log('runtime allowlist from the pack itself: ' + FILES.join(', '));

const PACK_ID = manifest.package_id || 'QD-SALES-ENGINEER';
const PACK_VERSION = manifest.version || '1.0.0';

// The 17 fields contracts/record.schema.json marks required. A record missing any of them is
// refused BY NAME rather than defaulted, because a default here is an invented fact.
const REQUIRED = ['record_id', 'version', 'record_type', 'domain', 'title', 'content',
  'structured_data', 'source_ids', 'epistemic_status', 'jurisdiction', 'language',
  'runtime_eligible', 'updated_at', 'tags', 'authority_effect', 'review_status', 'content_sha256'];

const bodyHash = (r) => createHash('sha256').update(String(r.title) + '\n' + String(r.content), 'utf8').digest('hex');

// ---------------------------------------------------------------------------------------------
// READ AND VALIDATE. Every refusal is collected BEFORE anything is written, and a fatal one aborts
// the whole run: a partially valid file must not partially overwrite a correct corpus.
// ---------------------------------------------------------------------------------------------
const rows = [], refused = [], seenId = new Map(), seenBody = new Map(), collisions = [];
for (const rel of FILES) {
  // The allowlist gate. records/*.jsonl and nothing else -- not the mirrors, not the SQLite index,
  // not evaluation/.
  const norm = String(rel).replace(/\\/g, '/');
  if (!/^records\/[A-Za-z0-9_.-]+\.jsonl$/.test(norm)) {
    console.error('REFUSED RUNTIME FILE ' + rel + ' :: only records/*.jsonl may be ingested');
    process.exit(2);
  }
  const p = join(ROOT, norm);
  if (!existsSync(p)) { console.error('MISSING ' + p); process.exit(2); }
  let n = 0;
  for (const line of readFileSync(p, 'utf8').split('\n')) {
    if (!line.trim()) continue;
    n++;
    let r;
    try { r = JSON.parse(line); } catch (e) { refused.push([norm + ':' + n, 'unparseable JSON']); continue; }
    const id = r.record_id || (norm + ':' + n);

    const missing = REQUIRED.filter((k) => r[k] === undefined || r[k] === null);
    if (missing.length) { refused.push([id, 'missing required field(s): ' + missing.join(',')]); continue; }
    // The schema's three consts, checked rather than assumed.
    if (r.authority_effect !== 'none')  { refused.push([id, 'authority_effect=' + r.authority_effect]); continue; }
    if (r.runtime_eligible !== true)    { refused.push([id, 'runtime_eligible=' + r.runtime_eligible]); continue; }
    if (!/^[a-f0-9]{64}$/.test(String(r.content_sha256))) { refused.push([id, 'content_sha256 is not a 64-hex digest']); continue; }
    if (!Array.isArray(r.source_ids) || r.source_ids.length < 1) { refused.push([id, 'source_ids must have at least one entry']); continue; }
    if (typeof r.structured_data !== 'object' || Array.isArray(r.structured_data)) { refused.push([id, 'structured_data is not an object']); continue; }
    if (typeof r.content !== 'string' || !r.content.trim()) { refused.push([id, 'empty content']); continue; }

    if (seenId.has(r.record_id)) { refused.push([id, 'duplicate record_id, first seen at line ' + seenId.get(r.record_id)]); continue; }
    seenId.set(r.record_id, n);

    // BODY DEDUPE -- the gap in every existing ingester in this repo. Two records with different
    // IDs and identical text are two answers to one question, and the retrieval will rank both.
    const bs = bodyHash(r);
    if (seenBody.has(bs)) { collisions.push([r.record_id, seenBody.get(bs), bs]); }
    else seenBody.set(bs, r.record_id);

    r.__body_sha256 = bs;
    rows.push(r);
  }
}

console.log('read ' + rows.length + ' record(s) from ' + FILES.length + ' allowlisted file(s)');
const byType = {}; for (const r of rows) byType[r.record_type] = (byType[r.record_type] || 0) + 1;
console.log('by record_type: ' + JSON.stringify(byType));
console.log('epistemic_status: ' + JSON.stringify([...new Set(rows.map((r) => r.epistemic_status))]));
console.log('review_status:    ' + JSON.stringify([...new Set(rows.map((r) => r.review_status))]));
console.log('jurisdiction:     ' + JSON.stringify([...new Set(rows.map((r) => r.jurisdiction))]));
console.log('record versions:  ' + JSON.stringify([...new Set(rows.map((r) => r.version))]));

if (collisions.length) {
  console.log('BODY_SHA256 COLLISIONS ' + collisions.length + ' (same title+content under different IDs):');
  for (const [a, b, h] of collisions.slice(0, 20)) console.log('  ' + a + ' == ' + b + '  (' + h.slice(0, 12) + ')');
} else {
  console.log('body_sha256 collisions: 0 (' + seenBody.size + ' distinct bodies across ' + rows.length + ' records)');
}
if (refused.length) {
  console.log('REFUSED ' + refused.length + ':');
  for (const [i, w] of refused.slice(0, 20)) console.log('  ' + i + ' :: ' + w);
} else {
  console.log('refused: 0');
}
// A record that fails validation is not a record to skip past. The corpus is one thing; importing
// 90% of it over a corpus that was 100% correct is a worse state than not importing at all.
if (refused.length) { console.error('\nABORTING: ' + refused.length + ' refusal(s). Nothing written; existing rows untouched.'); process.exit(1); }

// ---------------------------------------------------------------------------------------------
// THE TAXONOMY AND THE FIELDS. sector_registry.json is the source for both -- it nests the 896
// questions under their 128 families, so the sector_id on each field is READ, never derived from
// the field_key's prefix. field_catalog.json is then checked against it: same 896 keys or abort.
// ---------------------------------------------------------------------------------------------
const sectors = JSON.parse(readFileSync(join(ROOT, 'contracts/sector_registry.json'), 'utf8'));
const catalog = JSON.parse(readFileSync(join(ROOT, 'contracts/field_catalog.json'), 'utf8'));
const fields = [];
for (const s of sectors) {
  if (!s.sector_id || !s.title) { console.error('sector_registry entry without sector_id/title'); process.exit(2); }
  for (const q of (s.questions || [])) fields.push({ ...q, sector_id: s.sector_id });
}
const catKeys = new Set(catalog.map((f) => f.field_key));
const regKeys = new Set(fields.map((f) => f.field_key));
if (catKeys.size !== regKeys.size || [...catKeys].some((k) => !regKeys.has(k))) {
  console.error('field_catalog.json and sector_registry.json disagree: ' + catKeys.size + ' vs ' + regKeys.size + ' keys');
  process.exit(2);
}
console.log('sectors: ' + sectors.length + ' | qualification fields: ' + fields.length
  + ' (field_catalog.json agrees on all ' + catKeys.size + ' keys)');

if (!APPLY) { console.log('\nDRY RUN -- nothing written.'); process.exit(0); }

// ---------------------------------------------------------------------------------------------
// WRITE. Each chunk is ONE statement: a multi-row insert ... on conflict (pk) do update, so it is
// atomic in itself and a repeat import updates in place and can produce no duplicate -- record_id,
// sector_id and field_key are the primary keys AND the conflict targets.
//
// SAID PLAINLY rather than claimed: the run is NOT one database transaction. The corpus is 2.85 MB
// of JSONL and one POST carrying it would be a size gamble, so it goes in 25-row statements. What
// that costs and what covers it: validation completed BEFORE the first write and aborts the run on
// any refusal, so invalid input never reaches a correct row; and every statement is an idempotent
// upsert, so a run that dies halfway is fixed by running it again, not by cleaning up after it.
// There is no state a partial run can leave that a re-run does not converge.
// ---------------------------------------------------------------------------------------------
const lit = (v) => (v === null || v === undefined ? 'null' : "'" + String(v).replace(/'/g, "''") + "'");
const arr = (a) => (Array.isArray(a) && a.length ? 'array[' + a.map(lit).join(',') + ']::text[]' : "'{}'::text[]");
const bool = (b) => (b ? 'true' : 'false');

// What is already there, so inserted / updated / unchanged are MEASURED and not inferred from
// "the statement did not throw".
const before = new Map((await sql('select record_id, body_sha256 from public.sales_knowledge'))
  .map((r) => [r.record_id, r.body_sha256]));
let inserted = 0, updated = 0, unchanged = 0;
for (const r of rows) {
  if (!before.has(r.record_id)) inserted++;
  else if (before.get(r.record_id) === r.__body_sha256) unchanged++;
  else updated++;
}

let done = 0;
for (let i = 0; i < rows.length; i += 25) {
  const values = rows.slice(i, i + 25).map((r) => `(${[
    lit(r.record_id), lit(r.record_type), lit(r.domain), lit(r.title), lit(r.content),
    lit(JSON.stringify(r.structured_data)) + '::jsonb', arr(r.source_ids),
    lit(r.epistemic_status), lit(r.jurisdiction), lit(PACK_ID), lit(PACK_VERSION), lit(r.version),
    lit(r.__body_sha256), lit(r.content_sha256), bool(r.runtime_eligible),
    lit(r.authority_effect), arr(r.tags), lit(r.updated_at) + '::timestamptz',
  ].join(', ')})`).join(',\n');
  await sql(`insert into public.sales_knowledge (record_id, record_type, domain, title, content,
      structured_data, source_ids, epistemic_status, jurisdiction, pack_id, pack_version,
      record_version, body_sha256, content_sha256, runtime_index_eligible, authority_effect,
      tags, updated_at)
    values ${values}
    on conflict (record_id) do update set
      record_type = excluded.record_type, domain = excluded.domain, title = excluded.title,
      content = excluded.content, structured_data = excluded.structured_data,
      source_ids = excluded.source_ids, epistemic_status = excluded.epistemic_status,
      jurisdiction = excluded.jurisdiction, pack_version = excluded.pack_version,
      record_version = excluded.record_version, body_sha256 = excluded.body_sha256,
      content_sha256 = excluded.content_sha256,
      runtime_index_eligible = excluded.runtime_index_eligible,
      authority_effect = excluded.authority_effect, tags = excluded.tags,
      updated_at = excluded.updated_at, ingested_at = now()`);
  done += Math.min(25, rows.length - i);
  process.stdout.write(done + ' ');
}
console.log('\nknowledge rows written: ' + done);

// Sectors before fields -- the field table has an FK to it.
for (let i = 0; i < sectors.length; i += 50) {
  const values = sectors.slice(i, i + 50).map((s) =>
    `(${[lit(s.sector_id), lit(s.group), lit(s.title), lit(s.scope)].join(', ')})`).join(',\n');
  await sql(`insert into public.sales_sector (sector_id, group_key, title, scope)
    values ${values}
    on conflict (sector_id) do update set
      group_key = excluded.group_key, title = excluded.title, scope = excluded.scope`);
}
console.log('sectors written: ' + sectors.length);

for (let i = 0; i < fields.length; i += 50) {
  const values = fields.slice(i, i + 50).map((f) => `(${[
    lit(f.field_key), lit(f.sector_id), lit(f.question), lit(f.answer_type),
    lit(f.ask_only_if), lit(f.criticality), lit(f.unknown_handling),
  ].join(', ')})`).join(',\n');
  await sql(`insert into public.sales_qualification_field (field_key, sector_id, question,
      answer_type, ask_only_if, criticality, unknown_handling)
    values ${values}
    on conflict (field_key) do update set
      sector_id = excluded.sector_id, question = excluded.question,
      answer_type = excluded.answer_type, ask_only_if = excluded.ask_only_if,
      criticality = excluded.criticality, unknown_handling = excluded.unknown_handling`);
}
console.log('qualification fields written: ' + fields.length);

console.log('\nSUMMARY  inserted ' + inserted + ' | updated ' + updated + ' | unchanged ' + unchanged
  + ' | refused ' + refused.length + ' | body collisions ' + collisions.length);

const c = await sql(`select
    (select count(*) from public.sales_knowledge) knowledge,
    (select count(*) from public.sales_knowledge where search is not null) with_search,
    (select count(*) from public.sales_knowledge where embedding_gte is not null) with_embedding,
    (select count(distinct record_type) from public.sales_knowledge) types,
    (select count(*) from public.sales_knowledge where authority_effect <> 'none') carrying_authority,
    (select count(distinct body_sha256) from public.sales_knowledge) distinct_bodies,
    (select count(*) from public.sales_sector) sectors,
    (select count(*) from public.sales_qualification_field) fields`);
console.log('IN THE DATABASE: ' + JSON.stringify(c[0]));
process.exit(0);
