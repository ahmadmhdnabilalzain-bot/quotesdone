// import_packs.mjs — the streaming, resumable importer for the v2026.07.31 knowledge packs.
//
// The packs' own 02_TOKEN_EFFICIENT_METHOD.md is explicit: understand the importer and the
// schema, never consume the corpus as conversation tokens. 115,148 unique records at ~200
// tokens each is ~23M tokens, so the corpus is read here and only counts come back.
//
//   node scripts/kb/import_packs.mjs --ref=<project> --corpus=kb  --root=<_kbpkgs dir>
//   node scripts/kb/import_packs.mjs --ref=<project> --corpus=ops --root=<COMPANY_OPERATIONS dir>
//
// It writes the EXISTING kb_stage.records / ops_kb_stage.records that the packs' staging schema
// defines — it does not invent a parallel shape — and checkpoints per file in the existing
// kb_stage.file_hashes, so a killed run resumes at file granularity instead of restarting.
// Re-running a fully imported corpus inserts nothing; that is the test, and it is how this was
// verified against production.
//
// NOTHING IS ACTIVATED. The packs' 03_IMPORT_ORDER.md ends "run tests and STOP before
// production activation", and every category manifest carries
// status = production_research_draft_not_sme_approved.
//
// qd_guard.mjs is deliberately NOT used and NOT weakened: its mgmtWrite refuses production
// because it guards migration and fixture tooling against reaching production by accident.
// This import is founder-ordered onto BOTH projects, so it carries its own door — --ref is
// mandatory, has no default, and the target is echoed before the first write.
import { createHash } from 'node:crypto';
import { createReadStream, readFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import { createInterface } from 'node:readline';

const arg = (n) => (process.argv.find(a => a.startsWith(`--${n}=`)) || '').split('=').slice(1).join('=');
const REF = arg('ref'), CORPUS = arg('corpus'), ROOT = arg('root');
const BATCH_BYTES = Number(arg('batch') || 600_000);
const FORCE = process.argv.includes('--force');
if (!/^[a-z]{20}$/.test(REF)) throw new Error('--ref=<20-char project ref> is required');
if (!['ops', 'kb'].includes(CORPUS)) throw new Error('--corpus=ops|kb is required');
if (!ROOT) throw new Error('--root=<extracted pack dir> is required');

const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

async function q(sql, attempt = 0) {
  let r, body;
  try {
    r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: sql }), signal: AbortSignal.timeout(180_000),
    });
    body = await r.text();
  } catch (e) {
    if (attempt < 6) { await sleep(1500 * 2 ** attempt); return q(sql, attempt + 1); }
    throw new Error(`transport failed after ${attempt + 1}: ${e.name}: ${e.message}`);
  }
  if ([429, 500, 502, 503, 504].includes(r.status) && attempt < 6) {
    await sleep(1500 * 2 ** attempt); return q(sql, attempt + 1);
  }
  if (!r.ok) throw new Error(`management API ${r.status}: ${body.slice(0, 400)}`);
  return body ? JSON.parse(body) : null;
}

// Postgres text cannot hold a NUL, and standard_conforming_strings means a single-quoted
// literal needs only the doubled quote.
const lit = (s) => "'" + s.replace(/\u0000/g, '').replace(/'/g, "''") + "'";
const sha = (s) => createHash('sha256').update(s).digest('hex');

// ------------------------------------------------------------------ per-corpus specification
// [column, recordset type, insert expression]. An empty date arrives as '' in some packages and
// text '' does not cast to date, so every date column goes through nullif().
const D = (c) => `nullif(${c},'')::date`;
const SPECS = {
  kb: {
    table: 'kb_stage.records',
    cols: [
      ['record_id', 'text'], ['category_slug', 'text'], ['subcategory_slug', 'text'],
      ['module', 'text'], ['record_type', 'text'], ['title', 'text'], ['content', 'text'],
      ['structured_data', 'jsonb'], ['jurisdiction', 'text'], ['authority', 'text'],
      ['source_ids', 'jsonb'], ['effective_date', 'text'], ['superseded_date', 'text'],
      ['version', 'text'], ['confidence', 'numeric'], ['validation_status', 'text'],
      ['review_after', 'text'], ['keywords_en', 'jsonb'], ['keywords_ar', 'jsonb'],
      ['applies_when', 'jsonb'], ['exceptions', 'jsonb'], ['escalation_rule', 'jsonb'],
      ['package_id', 'text'], ['content_sha256', 'text'],
    ],
    required: ['record_id', 'category_slug', 'subcategory_slug', 'module', 'record_type',
      'title', 'content', 'version', 'validation_status'],
    // Every package's 23_all_records.jsonl is an exact union of its module files (verified per
    // package), 7 of the 67 ship none, and QD-KB-086 calls its union 24_all_records.jsonl.
    // Streaming the module files covers all 67 exactly once; including the union files would
    // double-count 98,050 of the 213,198 lines the manifest advertises. 115,148 is the corpus.
    files: (root) => {
      const out = [];
      for (const d of readdirSync(root, { withFileTypes: true })) {
        if (!d.isDirectory()) continue;
        for (const f of readdirSync(join(root, d.name))) {
          if (f.endsWith('.jsonl') && !/^2[34]_all_records\.jsonl$/.test(f)) out.push(join(root, d.name, f));
        }
      }
      return out.sort();
    },
    pkgOf: (rel) => rel.split('/')[0].match(/^(QD-KB-\d+)/)[1],
  },
  ops: {
    table: 'ops_kb_stage.records',
    cols: [
      ['record_id', 'text'], ['scope_type', 'text'], ['scope_key', 'text'], ['module', 'text'],
      ['record_type', 'text'], ['title', 'text'], ['content', 'text'],
      ['structured_data', 'jsonb'], ['source_ids', 'text[]'], ['implementation_status', 'text'],
      ['validation_status', 'text'], ['authority_tier', 'text'], ['risk_level', 'text'],
      ['version', 'text'], ['effective_date', 'text', D('effective_date')],
      ['review_after', 'text', D('review_after')], ['keywords', 'jsonb'],
      ['dependencies', 'jsonb'], ['escalation_rule', 'jsonb'], ['content_sha256', 'text'],
      ['package_version', 'text'], ['source_file', 'text'],
    ],
    required: ['record_id', 'scope_type', 'scope_key', 'module', 'record_type', 'title',
      'content', 'implementation_status', 'validation_status', 'authority_tier', 'risk_level',
      'version'],
    // 06_ALL_RECORDS is an exact superset of the other 227 files (3,959 = 7,918/2), verified.
    files: (root) => [join(root, '06_ALL_RECORDS', '01_ALL_OPERATIONAL_RECORDS.jsonl')],
    pkgOf: () => 'COMPANY_OPERATIONS',
  },
};
const S = SPECS[CORPUS];
const NAMES = S.cols.map(c => c[0]);
const RECORDSET = S.cols.map(c => `${c[0]} ${c[1]}`).join(', ');
const SELECT = S.cols.map(c => c[2] || c[0]).join(', ');
const UPDATES = NAMES.filter(c => c !== 'record_id').map(c => `${c}=excluded.${c}`)
  .concat('updated_at=now()').join(', ');
const JSONB = new Set(S.cols.filter(c => c[1] === 'jsonb').map(c => c[0]));
const ARRAYCOL = new Set(S.cols.filter(c => c[1] === 'text[]').map(c => c[0]));
const ARRAY_DEFAULT = new Set(['source_ids', 'keywords', 'keywords_en', 'keywords_ar',
  'dependencies', 'exceptions']);
const NULLABLE_JSON = new Set(['applies_when', 'escalation_rule']);

// ------------------------------------------------------------------ validation, in code
function shape(o, pkg, relPath) {
  for (const k of S.required) {
    const v = o[k];
    if (v === undefined || v === null || (typeof v === 'string' && !v.trim())) return { bad: `missing ${k}` };
  }
  if (typeof o.content !== 'string' || o.content.length < 20) return { bad: 'content under 20 chars' };
  if (o.confidence != null && !(Number(o.confidence) >= 0 && Number(o.confidence) <= 1)) {
    return { bad: `confidence out of range ${o.confidence}` };
  }
  const row = {};
  for (const [c] of S.cols) {
    if (c === 'content_sha256') { row[c] = sha(o.content); continue; }
    if (c === 'package_id') { row[c] = pkg; continue; }
    if (c === 'package_version') { row[c] = 'v2026.07.31'; continue; }
    if (c === 'source_file') { row[c] = relPath; continue; }
    let v = o[c];
    if (v === undefined) v = null;
    if (ARRAYCOL.has(c)) v = Array.isArray(v) ? v : (v == null ? [] : [String(v)]);
    else if (JSONB.has(c) && v === null && !NULLABLE_JSON.has(c)) v = ARRAY_DEFAULT.has(c) ? [] : {};
    row[c] = v;
  }
  return { row };
}

async function flush(rows, runId) {
  if (!rows.length) return { inserted: 0, updated: 0 };
  const r = await q(
    `with src as (select * from jsonb_to_recordset(${lit(JSON.stringify(rows))}::jsonb) as x(${RECORDSET})),
     w as (insert into ${S.table} (${NAMES.join(', ')}, ingestion_run_id)
           select ${SELECT}, '${runId}'::uuid from src
           on conflict (record_id) do update set ${UPDATES}
           returning (xmax = 0) as fresh)
     select count(*) filter (where fresh) inserted, count(*) filter (where not fresh) updated from w;`);
  return { inserted: Number(r[0].inserted), updated: Number(r[0].updated) };
}

// ------------------------------------------------------------------ run
const t0 = Date.now();
console.log(`target ref = ${REF}   corpus = ${CORPUS}`);
const files = S.files(ROOT);
console.log(`module files on disk: ${files.length}`);

// Resume off the checkpoint table the corpus already uses. kb_stage.file_hashes is keyed
// (package_id, file_name) and carries the sha of what was imported.
let done = new Map();
if (CORPUS === 'kb') {
  for (const r of await q(`select package_id, file_name, sha256 from kb_stage.file_hashes;`)) {
    done.set(`${r.package_id.match(/^(QD-KB-\d+)/)?.[1] ?? r.package_id}/${r.file_name}`, r.sha256);
  }
}
console.log(`checkpointed files: ${done.size}${FORCE ? '  (--force: ignored)' : ''}`);

// THE HEADER'S OWN TEST DID NOT PASS (13 Aug 2026).
//
// Twelve lines up this file says: "Re-running a fully imported corpus inserts nothing; that is the
// test, and it is how this was verified against production." Run it a second time and it does not
// insert nothing — it dies before reading a single file:
//
//   ERROR 23505: duplicate key value violates unique constraint "kb_stage_runs_pkg_idx"
//   Key (package_id, package_version, COALESCE(package_sha256, ''))
//        =(ALL_KNOWLEDGE_86_CATEGORIES, v2026.07.31, ) already exists.
//
// kb_stage.ingestion_runs is unique on (package_id, package_version, coalesce(package_sha256,'')),
// so it is ONE ROW PER PACKAGE VERSION — a state record, not a per-execution log. The plain insert
// contradicted its own table. It went unnoticed because the claim was written once and never
// re-executed: the corpus was imported, the header recorded that re-running is the test, and
// nobody ran it again until a session tried to repair what it thought was a 16,608-record hole.
//
// Upserted onto that exact expression, so a resumed or repeated run re-opens the same row and the
// checkpoint loop below decides what actually gets read. ops_kb_stage.ingestion_runs carries only
// its pkey — no equivalent constraint — so that branch never had the fault and is left alone.
const runId = (await q(CORPUS === 'kb'
  ? `insert into kb_stage.ingestion_runs (package_id, package_version) values ('ALL_KNOWLEDGE_86_CATEGORIES','v2026.07.31')
     on conflict (package_id, package_version, coalesce(package_sha256,''))
     do update set status='started', started_at=now(), completed_at=null
     returning id;`
  : `insert into ops_kb_stage.ingestion_runs (package_name, package_version) values ('COMPANY_OPERATIONS_KNOWLEDGE','v2026.07.31') returning id;`))[0].id;

let totIns = 0, totUpd = 0, totRej = 0, totLines = 0, skipped = 0;
const rejectSamples = [];

for (const abs of files) {
  const rel = relative(ROOT, abs).split('\\').join('/');
  const bytes = readFileSync(abs);
  const fileSha = createHash('sha256').update(bytes).digest('hex');
  const pkg = S.pkgOf(rel);
  const key = `${pkg}/${rel.split('/').pop()}`;
  if (!FORCE && done.get(key) === fileSha) { skipped++; continue; }

  let rows = [], approx = 0, ins = 0, upd = 0, rej = 0, lines = 0;
  const rl = createInterface({ input: createReadStream(abs, 'utf8'), crlfDelay: Infinity });
  for await (const line of rl) {
    const s = line.trim(); if (!s) continue;
    lines++;
    let o;
    try { o = JSON.parse(s); }
    catch { rej++; if (rejectSamples.length < 20) rejectSamples.push(`${key}:${lines} unparseable`); continue; }
    const { row, bad } = shape(o, pkg, rel);
    if (bad) { rej++; if (rejectSamples.length < 20) rejectSamples.push(`${key}:${lines} ${bad}`); continue; }
    rows.push(row); approx += s.length;
    if (approx >= BATCH_BYTES) { const r = await flush(rows, runId); ins += r.inserted; upd += r.updated; rows = []; approx = 0; }
  }
  const r = await flush(rows, runId); ins += r.inserted; upd += r.updated;

  if (CORPUS === 'kb') {
    await q(`insert into kb_stage.file_hashes (package_id, file_name, sha256, rows_seen, last_run_id)
      values (${lit(pkg)}, ${lit(rel.split('/').pop())}, '${fileSha}', ${ins + upd}, '${runId}'::uuid)
      on conflict (package_id, file_name) do update set sha256=excluded.sha256,
        rows_seen=excluded.rows_seen, last_run_id=excluded.last_run_id, updated_at=now();`);
  }
  totIns += ins; totUpd += upd; totRej += rej; totLines += lines;
  process.stdout.write(`\r${key}  lines=${lines} ins=${ins} upd=${upd} rej=${rej}   total ${totIns + totUpd}/${totLines}        `);
}

await q(CORPUS === 'kb'
  ? `update kb_stage.ingestion_runs set status='completed', completed_at=now(),
       inserted_count=${totIns}, updated_count=${totUpd}, rejected_count=${totRej},
       report=${lit(JSON.stringify({ files: files.length, skipped, lines: totLines, rejectSamples }))}::jsonb
     where id='${runId}'::uuid;`
  : `update ops_kb_stage.ingestion_runs set status='completed', completed_at=now(),
       inserted_count=${totIns}, updated_count=${totUpd}, rejected_count=${totRej},
       detail=${lit(JSON.stringify({ files: files.length, skipped, lines: totLines, rejectSamples }))}::jsonb
     where id='${runId}'::uuid;`);

const final = (await q(`select count(*)::bigint n from ${S.table};`))[0].n;
console.log(`\n--- ${CORPUS} @ ${REF} ---`);
console.log(`files ${files.length} (skipped ${skipped})  lines read ${totLines}  inserted ${totIns}  updated ${totUpd}  rejected ${totRej}`);
console.log(`${S.table} now ${final}   elapsed ${Math.round((Date.now() - t0) / 1000)}s`);
if (rejectSamples.length) console.log('reject samples:\n  ' + rejectSamples.slice(0, 10).join('\n  '));
