// LOAD QuotesDone_Customer_Support_Knowledge_v1_1 INTO public.support_knowledge
//
// Imports ONLY the five files MANIFEST.json -> runtime_files names. Not the Markdown mirrors (they
// duplicate every record and inflate every relevance score), and not evaluation/, tests/ or qa/ --
// the pack is explicit that evaluation answers must never enter runtime retrieval.
//
//   node scripts/kb/load_support_knowledge_pack.mjs --root <extracted pack dir> [--apply]

import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { sql } from '../lib/db.mjs';

const at = (f) => { const i = process.argv.indexOf(f); return i >= 0 ? process.argv[i + 1] : null; };
const ROOT = at('--root');
const APPLY = process.argv.includes('--apply');
if (!ROOT) { console.error('--root <extracted pack dir> is required'); process.exit(2); }

const manifest = JSON.parse(readFileSync(join(ROOT, 'MANIFEST.json'), 'utf8'));
const FILES = manifest.runtime_files;
if (!Array.isArray(FILES) || !FILES.length) { console.error('MANIFEST.json has no runtime_files'); process.exit(2); }
console.log('runtime allowlist from the pack itself: ' + FILES.join(', '));

const PACK_ID = manifest.pack_id || 'quotesdone-support-knowledge-v1';
const PACK_VERSION = manifest.release || manifest.version || '1.1.0';

const rows = [], refused = [];
for (const rel of FILES) {
  const p = join(ROOT, rel);
  if (!existsSync(p)) { console.error('MISSING ' + p); process.exit(2); }
  for (const line of readFileSync(p, 'utf8').split('\n').filter((l) => l.trim())) {
    const r = JSON.parse(line);
    // The pack's own rules, enforced at the door and NAMED when they refuse. Silently dropping a
    // record hides exactly the thing worth knowing.
    if ((r.authority_effect ?? 'none') !== 'none') { refused.push([r.record_id, 'authority_effect=' + r.authority_effect]); continue; }
    if (r.external_execution_enabled === true)     { refused.push([r.record_id, 'external_execution_enabled']); continue; }
    if (r.runtime_index_eligible === false)        { refused.push([r.record_id, 'runtime_index_eligible=false']); continue; }
    if (!String(r.record_id || '').startsWith('supportkb.')) { refused.push([r.record_id, 'not a supportkb.* id']); continue; }
    rows.push(r);
  }
}
console.log('read ' + rows.length + ' record(s)');
const byKind = {}; for (const r of rows) byKind[r.record_kind] = (byKind[r.record_kind] || 0) + 1;
console.log('by kind: ' + JSON.stringify(byKind));
console.log('review_status values: ' + JSON.stringify([...new Set(rows.map((r) => r.review_status))]));
console.log('record versions: ' + JSON.stringify([...new Set(rows.map((r) => r.record_version))]));
if (refused.length) { console.log('REFUSED ' + refused.length + ':'); for (const [i, w] of refused.slice(0, 10)) console.log('  ' + i + ' :: ' + w); }
if (!APPLY) { console.log('\nDRY RUN — nothing written.'); process.exit(0); }

const lit = (v) => (v === null || v === undefined ? 'null' : "'" + String(v).replace(/'/g, "''") + "'");
const arr = (a) => (Array.isArray(a) && a.length ? 'array[' + a.map(lit).join(',') + ']::text[]' : "'{}'::text[]");
const bool = (b) => (b ? 'true' : 'false');

let done = 0;
for (let i = 0; i < rows.length; i += 25) {
  const chunk = rows.slice(i, i + 25);
  const values = chunk.map((r) => {
    const body = r.body ?? JSON.stringify(r.structured_data ?? {});
    return `(${[
      lit(r.record_id), lit(r.schema_version), lit(r.record_version || PACK_VERSION), lit(r.record_kind),
      lit(r.parent_id), lit(r.title), lit(r.domain), arr(r.tags), lit(r.language || 'en'),
      lit(r.review_status || 'authored_not_independently_reviewed'), lit(r.content_origin),
      lit(r.authority_effect || 'none'), lit(r.runtime_use),
      bool(r.runtime_index_eligible !== false), bool(!!r.contains_synthetic_example),
      bool(!!r.requires_current_verification), arr(r.source_ids), lit(r.source_path),
      lit(JSON.stringify(r.structured_data ?? {})) + '::jsonb', lit(body),
      lit(r.body_sha256 || createHash('sha256').update(body, 'utf8').digest('hex')),
      lit(PACK_ID), lit(PACK_VERSION),
    ].join(', ')})`;
  }).join(',\n');
  await sql(`insert into public.support_knowledge (record_id, schema_version, record_version, record_kind,
      parent_id, title, domain, tags, language, review_status, content_origin, authority_effect,
      runtime_use, runtime_index_eligible, contains_synthetic_example, requires_current_verification,
      source_ids, source_path, structured_data, body, body_sha256, pack_id, pack_version)
    values ${values}
    on conflict (record_id) do update set
      title = excluded.title, body = excluded.body, body_sha256 = excluded.body_sha256,
      tags = excluded.tags, record_version = excluded.record_version,
      structured_data = excluded.structured_data, review_status = excluded.review_status,
      pack_version = excluded.pack_version, imported_at = now()`);
  done += chunk.length;
  process.stdout.write(done + ' ');
}
console.log('\nloaded ' + done);
// EMBED ON WRITE (23 Sep 2026): the pack is read by meaning only, so a row loaded without a vector is invisible.
// Every new or changed row (the update trigger clears a changed row's vector) is embedded now, free and in-region.
const { embedMissing } = await import('./embed_sales_knowledge.mjs');
await embedMissing('support_knowledge');
const c = await sql(`select count(*) total, count(*) filter (where search is not null) with_vector,
  count(distinct record_kind) kinds, count(*) filter (where authority_effect='none') no_authority,
  count(distinct pack_version) versions from public.support_knowledge`);
console.log('IN THE DATABASE: ' + JSON.stringify(c[0]));
process.exit(0);
