// LOAD CEO_Knowledge_Pack_v1 INTO public.ceo_knowledge
//
// Imports ONLY the four record files the pack's MANIFEST names as the runtime corpus:
//   records/knowledge.jsonl · records/worked_cases.jsonl · records/decision_cards.jsonl · records/metrics.jsonl
//
// It does NOT import knowledge/ (a human-readable duplicate of the same records -- indexing both
// would double every hit and inflate every relevance score), and it does NOT import evaluation/
// (feeding the evaluation answers into the knowledge search and then reporting a good score would
// be marking my own homework).
//
//   node scripts/kb/load_ceo_knowledge_pack.mjs --root <extracted pack dir> [--apply]
//
// Without --apply it is a dry run: it reads, validates and reports, and writes nothing.

import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { sql } from '../phase_c/lib/db.mjs';

const args = process.argv.slice(2);
const rootAt = args.indexOf('--root');
const ROOT = rootAt >= 0 ? args[rootAt + 1] : null;
const APPLY = args.includes('--apply');
if (!ROOT) { console.error('--root <extracted CEO_Knowledge_Pack_v1 dir> is required'); process.exit(2); }

const FILES = ['knowledge.jsonl', 'worked_cases.jsonl', 'decision_cards.jsonl', 'metrics.jsonl'];

// The pack's own fingerprint, so every row can say which build of the pack it came from. Read from
// the validator output rather than recomputed here: recomputing it would be a second opinion, and a
// second opinion that disagreed would be indistinguishable from a corrupted download.
// v1.2 Full Autonomy, from the pack's own validator: 508 records, 278 manifest files verified.
// The v1.1 value was 73a55921dcf3...9471; it is replaced rather than kept beside, because two
// fingerprints on one corpus would mean nobody can say which build a record came from.
const FINGERPRINT = 'ff3f5f9007218e4971158cb87f733ca11191ac2bbf34749d0fcbd8e9f1584e32';

const KNOWN = new Set(['schema_version','record_id','record_version','record_kind','parent_id','title',
  'domain','tags','language','company_scope','audience','created_on','review_status','content_origin',
  'authority_effect','runtime_use','runtime_index_eligible','external_execution_enabled',
  'contains_synthetic_example','requires_current_verification','verification_note','source_ids',
  'source_support','related_modules','source_path','body','body_sha256']);

const rows = [];
const refused = [];
for (const f of FILES) {
  const p = join(ROOT, 'records', f);
  if (!existsSync(p)) { console.error('MISSING ' + p); process.exit(2); }
  const lines = readFileSync(p, 'utf8').split('\n').filter((l) => l.trim());
  for (const line of lines) {
    const r = JSON.parse(line);
    // THE PACK'S OWN RULES, ENFORCED AT THE DOOR rather than trusted. A record that claims authority
    // or claims it may execute is refused and named, not quietly filtered: silently dropping it
    // would hide exactly the thing worth knowing about.
    if (r.authority_effect !== 'none')        { refused.push([r.record_id, 'authority_effect=' + r.authority_effect]); continue; }
    if (r.external_execution_enabled !== false) { refused.push([r.record_id, 'external_execution_enabled=true']); continue; }
    if (!r.runtime_index_eligible)            { refused.push([r.record_id, 'runtime_index_eligible=false']); continue; }
    if (!['generic','industry'].includes(r.company_scope)) { refused.push([r.record_id, 'company_scope=' + r.company_scope]); continue; }

    // body_sha256 is the pack's identifier for the exact text retrieved. Where the pack supplies it
    // we keep theirs; where it does not, we compute one so every row can be matched to its text later.
    const bodyHash = r.body_sha256 || createHash('sha256').update(r.body || '', 'utf8').digest('hex');
    const extra = {};
    for (const k of Object.keys(r)) if (!KNOWN.has(k)) extra[k] = r[k];
    rows.push({ ...r, body_sha256: bodyHash, extra });
  }
}

console.log('read ' + rows.length + ' record(s) from ' + FILES.length + ' file(s)');
if (refused.length) {
  console.log('REFUSED ' + refused.length + ':');
  for (const [id, why] of refused.slice(0, 20)) console.log('  ' + id + ' :: ' + why);
}
const byKind = {};
for (const r of rows) byKind[r.record_kind] = (byKind[r.record_kind] || 0) + 1;
console.log('by kind: ' + JSON.stringify(byKind));
const synthetic = rows.filter((r) => r.contains_synthetic_example).length;
const needsVerify = rows.filter((r) => r.requires_current_verification).length;
console.log('labelled synthetic: ' + synthetic + ' · requires current verification: ' + needsVerify);
console.log('review_status values: ' + JSON.stringify([...new Set(rows.map((r) => r.review_status))]));

if (!APPLY) { console.log('\nDRY RUN — nothing written. Re-run with --apply.'); process.exit(0); }

const lit = (v) => (v === null || v === undefined ? 'null' : "'" + String(v).replace(/'/g, "''") + "'");
const arr = (a) => (Array.isArray(a) && a.length
  ? "array[" + a.map((x) => lit(x)).join(',') + "]::text[]" : "'{}'::text[]");
const bool = (b) => (b ? 'true' : 'false');

let done = 0;
for (let i = 0; i < rows.length; i += 25) {
  const chunk = rows.slice(i, i + 25);
  const values = chunk.map((r) => `(${[
    lit(r.record_id), lit(r.schema_version), lit(r.record_version), lit(r.record_kind), lit(r.parent_id),
    lit(r.title), lit(r.domain), arr(r.tags), lit(r.language || 'en'), lit(r.company_scope), arr(r.audience),
    lit(r.created_on), lit(r.review_status), lit(r.content_origin), lit(r.authority_effect), lit(r.runtime_use),
    bool(r.runtime_index_eligible), bool(r.external_execution_enabled), bool(r.contains_synthetic_example),
    bool(r.requires_current_verification), lit(r.verification_note), arr(r.source_ids), lit(r.source_support),
    arr(r.related_modules), lit(r.source_path), lit(r.body), lit(r.body_sha256),
    lit(JSON.stringify(r.extra)) + '::jsonb', lit(FINGERPRINT),
  ].join(', ')})`).join(',\n');
  await sql(`insert into public.ceo_knowledge (record_id, schema_version, record_version, record_kind,
      parent_id, title, domain, tags, language, company_scope, audience, created_on, review_status,
      content_origin, authority_effect, runtime_use, runtime_index_eligible, external_execution_enabled,
      contains_synthetic_example, requires_current_verification, verification_note, source_ids,
      source_support, related_modules, source_path, body, body_sha256, extra, pack_fingerprint)
    values ${values}
    on conflict (record_id) do update set
      title = excluded.title, body = excluded.body, body_sha256 = excluded.body_sha256,
      tags = excluded.tags, record_version = excluded.record_version,
      review_status = excluded.review_status, extra = excluded.extra,
      pack_fingerprint = excluded.pack_fingerprint, imported_at = now()`);
  done += chunk.length;
  process.stdout.write(done + ' ');
}
console.log('\nloaded ' + done);

const check = await sql(`select count(*) total,
  count(*) filter (where search is not null) with_vector,
  count(distinct record_kind) kinds,
  count(*) filter (where review_status = 'authored_not_independently_reviewed') carried_review_status,
  count(*) filter (where authority_effect = 'none') no_authority
  from public.ceo_knowledge`);
console.log('IN THE DATABASE: ' + JSON.stringify(check[0]));
process.exit(0);
