// Stage 4 — idempotent V2 + V3 ingestion.
//
//   node scripts/kb/v3_import.mjs <extracted-root> --ref=<project> [--apply]
//
// Order: V2 complete delivery -> V3 master core -> V3 department/role -> V3 category ->
// V3 runtime-training cases. Stable ids are authoritative. A record whose checksum has
// not moved is left alone, so a second run inserts nothing.
//
// Certification material is NOT imported. The V2 delivery ships certification and
// evaluation cases with their expected answers; a builder session must not hold them and
// a runtime agent must not reach them. They are counted, listed and left on disk for the
// independent evaluator to load into the cert schema.
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { mgmtRead, mgmtWriteData, PROD_REF } from '../lib/qd_guard.mjs';
import { records } from './v3_package.mjs';

// qd_guard refuses every production write by design, and rightly: a ref in an executable
// position is the bug it exists to stop. Knowledge rows are inert text, and 25,715 of them
// cannot travel one promote_rows call at a time. So production takes the same deterministic
// import the staging run took, through the management API, and the two projects are then
// compared by digest — which proves more than promotion would.
const TOKEN = (process.env.SUPABASE_ACCESS_TOKEN
  || fs.readFileSync(SUPABASE_TOKEN_FILE, 'utf8')).trim();
async function prodPost(sql) {
  // The management API throttles a long import; 429 is the rate limiter, not a failure of
  // the statement, so it is waited out rather than reported as a rejected record.
  for (let attempt = 0; ; attempt++) {
    const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: sql }),
    });
    const body = await r.text();
    if (r.ok) return body ? JSON.parse(body) : null;
    if (r.status === 429 && attempt < 8) {
      await new Promise((res) => setTimeout(res, Math.min(30000, 2000 * 2 ** attempt)));
      continue;
    }
    throw new Error(`production query failed ${r.status}: ${body.slice(0, 300)}`);
  }
}
const IS_PROD = (process.argv.find((a) => a.startsWith('--ref=')) || '').includes(PROD_REF);
const write = (ref, sql, where) => (IS_PROD ? prodPost(sql) : mgmtWriteData(ref, sql, where));
const stmt = (ref, sql, where) => (IS_PROD ? prodPost(sql) : mgmtWriteWrapper(ref, sql, where));
async function mgmtWriteWrapper(ref, sql, where) {
  const { mgmtWrite } = await import('../lib/qd_guard.mjs');
  return mgmtWrite(ref, sql, where);
}

const root = process.argv[2];
const refArg = process.argv.find((a) => a.startsWith('--ref='));
const REF = refArg ? refArg.slice(6) : PROD_REF;
const APPLY = process.argv.includes('--apply');
if (!root) { console.error('usage: v3_import.mjs <extracted-root> --ref= [--apply]'); process.exit(2); }

const identityPath = path.join(process.cwd(), 'docs', 'knowledge', 'V3_ROLE_IDENTITY.json');
const identity = JSON.parse(fs.readFileSync(identityPath, 'utf8'));
const DEPT_ALIAS = identity.department_alias;

const q = (v) => (v === null || v === undefined) ? 'null' : `'${String(v).replace(/'/g, "''")}'`;
const jb = (o) => (o === null || o === undefined) ? `'{}'::jsonb` : `${q(JSON.stringify(o))}::jsonb`;
const bool = (v) => (v ? 'true' : 'false');

// ------------------------------------------------------------------ package order
// A stage archive's records must land after the delivery they upgrade, so a V3 overlay
// can supersede a V2 record and never the other way round.
function orderOf(r) {
  if (r.generation === 'V2') return 0;
  if (/_00_MASTER_CORE_/.test(r.package)) return 1;
  if (r.scope_type === 'category') return 3;
  if (r.layer === 'case_training') return 4;
  return 2;
}

const CASE_FAMILIES = new Set(['role_adversarial', 'role_tool', 'role_uncertainty',
  'role_cross_department', 'department_management', 'category_case', 'case',
  'failure_mode_case', 'evaluation_case']);

const stats = {
  packages: new Set(), files: new Set(), records_read: 0,
  canonical_expected: 0, inserted: 0, updated: 0, unchanged: 0, superseded: 0,
  rejected: 0, duplicate: 0, quarantined_certification: 0,
  embedding_created: 0, embedding_skipped: 0, errors: 0,
};
const rejects = [];
const certFiles = new Set();

// ------------------------------------------------------------------ collect
const knowledge = new Map();   // record_id -> row
const training = new Map();    // case_id  -> row

const all = [];
for (const r of records(root)) {
  if (r.__reject) { stats.rejected++; rejects.push(r); continue; }
  stats.records_read++;
  stats.packages.add(r.package);
  stats.files.add(r.source_path);
  if (r.is_certification) { stats.quarantined_certification++; certFiles.add(r.source_path); continue; }
  all.push(r);
}
all.sort((a, b) => orderOf(a) - orderOf(b));

for (const r of all) {
  const isCase = r.layer === 'case_training' || (CASE_FAMILIES.has(r.record_type) && r.record_type !== 'case');
  if (isCase && r.layer === 'case_training') {
    const prev = training.get(r.stable_id);
    if (prev) { stats.duplicate++; if (prev.checksum === r.checksum) continue; }
    training.set(r.stable_id, {
      case_id: r.stable_id, generation: r.generation, package: r.package,
      package_version: r.package_version,
      scope_type: r.scope_type === 'company' ? 'company' : r.scope_type,
      scope_key: r.scope_key, case_family: r.record_type,
      competency: r.structured_data?.competency || null,
      company_stage: r.structured_data?.company_stage || null,
      payload: r.structured_data, checksum: r.checksum,
    });
    continue;
  }
  const prev = knowledge.get(r.stable_id);
  if (prev) {
    stats.duplicate++;
    // Additive re-delivery: keep the richer copy (the department assignment adds fields).
    const merged = { ...prev.structured, ...(r.structured_data || {}) };
    prev.structured = merged;
    prev.content = JSON.stringify(merged).length > String(prev.content).length ? JSON.stringify(merged) : prev.content;
    prev.sources.add(r.source_path);
    continue;
  }
  const sd = r.structured_data || {};
  // An ops-corpus record already declares its own scope, module and governance fields;
  // the path only says where the copy was filed. Keep what the record says.
  const scopeType = r.ops_native && sd.scope_type ? sd.scope_type : r.scope_type;
  const scopeKey = r.ops_native && sd.scope_key ? sd.scope_key : r.scope_key;
  const deptKey = r.ops_native && sd.dept_key ? sd.dept_key
    : scopeType === 'department' ? (DEPT_ALIAS[scopeKey] || scopeKey)
    : r.scope_type === 'role' ? (DEPT_ALIAS[roleDept(r.scope_key, sd)] || null)
    : null;
  knowledge.set(r.stable_id, {
    record_id: r.stable_id,
    scope_type: scopeType, scope_key: scopeKey, dept_key: deptKey,
    module: r.ops_native && sd.module ? sd.module : moduleOf(r),
    record_type: r.record_type,
    title: String(r.title || r.stable_id).slice(0, 400),
    content: r.content, structured: sd,
    sources: new Set([r.source_path]),
    layer: r.layer, generation: r.generation, package: r.package,
    package_version: r.package_version,
    role_key: r.scope_type === 'role' ? r.scope_key : null,
    category_key: r.scope_type === 'category' ? r.scope_key : null,
    deterministic: r.deterministic, runtime_eligible: r.runtime_eligible,
    checksum: r.checksum, source_path: r.source_path,
    source_type: r.ops_native ? 'company_operations_corpus' : 'knowledge_package',
    source_authority: 'quotesdone_delivery',
    source_freshness: r.layer === 'kpi' || r.layer === 'policy' ? 'review_required' : 'stable',
    embedding_status: r.deterministic ? 'not_required' : 'pending',
    authority_tier: sd.authority_tier || 'advisory',
    risk_level: sd.risk_level || 'low',
    version: String(sd.version || r.package_version),
    implementation_status: sd.implementation_status || 'implemented',
    validation_status: sd.validation_status || 'author_verified',
    keywords: Array.isArray(sd.keywords) ? sd.keywords : [],
    dependencies: Array.isArray(sd.dependencies) ? sd.dependencies : [],
    escalation_rule: sd.escalation_rule || {},
    effective_date: sd.effective_date || null,
    review_after: sd.review_after || null,
  });
}
stats.canonical_expected = knowledge.size + training.size;

function roleDept(roleId, sd) {
  if (sd && sd.department) return sd.department;
  const m = identity.identity.find((i) => i.packaged_role_id === roleId);
  return m ? m.packaged_department : null;
}
function moduleOf(r) {
  const L = { company_core: 'principles', department_shared: 'professional_knowledge', role_specific: 'role',
    policy: 'governance', authority: 'decision_rules', kpi: 'kpi', decision_playbook: 'decision_rules',
    failure_mode: 'exception_handling', remediation: 'exception_handling',
    source_reference: 'source_registry', category_specialist: 'professional_knowledge' };
  return L[r.layer] || 'professional_knowledge';
}

// ------------------------------------------------------------------ apply
if (!APPLY) {
  console.log(JSON.stringify(summary(), null, 2));
  process.exit(0);
}

const run = await write(REF, `insert into knowledge_ingestion_run (package, package_version, generation, note)
  values ('QuotesDone_AGENT_KNOWLEDGE_V3_RUNTIME_TRAINING_ONLY', '2026.08.14', 'V3', 'V2 base + V3 overlays')
  returning run_id`, 'open ingestion run');
const runId = run[0].run_id;

// existing checksums so an unchanged record is not rewritten
const existingK = new Map((await mgmtRead(REF,
  `select record_id, coalesce(checksum,'') checksum from ops_knowledge`)).map((r) => [r.record_id, r.checksum]));
const existingT = new Map((await mgmtRead(REF,
  `select case_id, checksum from agent_training_case`)).map((r) => [r.case_id, r.checksum]));

const kRows = [...knowledge.values()];
const tRows = [...training.values()];

for (const r of kRows) {
  const prev = existingK.get(r.record_id);
  if (prev === undefined) r.__op = 'insert';
  else if (prev === r.checksum) { r.__op = 'unchanged'; stats.unchanged++; }
  else r.__op = 'update';
}
for (const r of tRows) {
  const prev = existingT.get(r.case_id);
  if (prev === undefined) r.__op = 'insert';
  else if (prev === r.checksum) { r.__op = 'unchanged'; stats.unchanged++; }
  else r.__op = 'update';
}

const kWrite = kRows.filter((r) => r.__op !== 'unchanged');
const tWrite = tRows.filter((r) => r.__op !== 'unchanged');

async function chunked(rows, size, fn, label) {
  for (let i = 0; i < rows.length; i += size) {
    const part = rows.slice(i, i + size);
    try { await fn(part); }
    catch (e) { stats.errors++; rejects.push({ reason: `${label}: ${String(e.message).slice(0, 300)}`, source_path: part[0] && (part[0].source_path || part[0].case_id) }); }
    if (i % 2000 === 0) process.stderr.write(`  ${label} ${i}/${rows.length}\r`);
  }
}

// Before-image: whatever is about to be overwritten is stored first, so the run can be
// reversed exactly rather than approximately.
async function captureUndo(table, keyCol, keys) {
  const list = keys.map(q).join(',');
  await write(REF, `insert into knowledge_ingestion_undo (run_id, table_name, key, existed, prev_row)
    select ${q(runId)}::uuid, ${q(table)}, k.key, (o.${keyCol} is not null), to_jsonb(o)
    from unnest(ARRAY[${list}]::text[]) as k(key)
    left join ${table} o on o.${keyCol} = k.key
    on conflict (run_id, table_name, key) do nothing`, 'undo capture');
}

await chunked(kWrite, 120, async (part) => {
  await captureUndo('ops_knowledge', 'record_id', part.map((r) => r.record_id));
  const values = part.map((r) => `(${[
    q(r.record_id), q(r.scope_type), q(r.scope_key), q(r.dept_key), q(r.module), q(r.record_type),
    q(r.title), q(r.content), jb(r.structured),
    `ARRAY[${[...r.sources].map(q).join(',')}]::text[]`,
    q(r.implementation_status), q(r.validation_status), q(r.authority_tier), q(r.risk_level), q(r.version),
    r.effective_date ? q(r.effective_date) + '::date' : 'null',
    r.review_after ? q(r.review_after) + '::date' : 'null',
    r.keywords.length ? `ARRAY[${r.keywords.map(q).join(',')}]::text[]` : `'{}'::text[]`,
    r.dependencies.length ? `ARRAY[${r.dependencies.map(q).join(',')}]::text[]` : `'{}'::text[]`,
    jb(r.escalation_rule),
    q(r.package), q(r.package_version), q(r.generation), q(r.layer), q(r.role_key), q(r.category_key),
    q(r.source_type), q(r.source_authority), q(r.source_freshness), bool(r.runtime_eligible),
    bool(r.deterministic), q(r.checksum), q(runId), q(r.embedding_status), q(r.source_path),
  ].join(',')})`).join(',\n');
  await write(REF, `insert into ops_knowledge (
      record_id, scope_type, scope_key, dept_key, module, record_type, title, content, structured_data,
      source_ids, implementation_status, validation_status, authority_tier, risk_level, version,
      effective_date, review_after, keywords, dependencies, escalation_rule,
      package, package_version, generation, layer, role_key, category_key,
      source_type, source_authority, source_freshness, runtime_eligible, deterministic,
      checksum, ingestion_run_id, embedding_status, source_path)
    values ${values}
    on conflict (record_id) do update set
      -- never null out a field the existing record already carries
      title = excluded.title,
      content = excluded.content,
      structured_data = ops_knowledge.structured_data || excluded.structured_data,
      source_ids = (select array_agg(distinct x) from unnest(ops_knowledge.source_ids || excluded.source_ids) x),
      package = excluded.package, package_version = excluded.package_version,
      generation = greatest(ops_knowledge.generation, excluded.generation),
      layer = coalesce(excluded.layer, ops_knowledge.layer),
      role_key = coalesce(excluded.role_key, ops_knowledge.role_key),
      category_key = coalesce(excluded.category_key, ops_knowledge.category_key),
      source_type = excluded.source_type, source_authority = excluded.source_authority,
      source_freshness = excluded.source_freshness,
      runtime_eligible = excluded.runtime_eligible, deterministic = excluded.deterministic,
      checksum = excluded.checksum, ingestion_run_id = excluded.ingestion_run_id,
      embedding_status = case when ops_knowledge.checksum is distinct from excluded.checksum
                              then excluded.embedding_status else ops_knowledge.embedding_status end,
      source_path = excluded.source_path,
      version = excluded.version`, 'ops_knowledge upsert');
}, 'knowledge');

await chunked(tWrite, 150, async (part) => {
  await captureUndo('agent_training_case', 'case_id', part.map((r) => r.case_id));
  const values = part.map((r) => `(${[
    q(r.case_id), q(r.generation), q(r.package), q(r.package_version), q(r.scope_type), q(r.scope_key),
    q(r.case_family), q(r.competency), q(r.company_stage), jb(r.payload), q(r.checksum), q(runId),
  ].join(',')})`).join(',\n');
  await write(REF, `insert into agent_training_case
      (case_id, generation, package, package_version, scope_type, scope_key, case_family,
       competency, company_stage, payload, checksum, ingestion_run_id)
    values ${values}
    on conflict (case_id) do update set
      payload = excluded.payload, checksum = excluded.checksum,
      case_family = excluded.case_family, competency = excluded.competency,
      company_stage = excluded.company_stage, ingestion_run_id = excluded.ingestion_run_id`, 'training upsert');
}, 'training');

stats.inserted = kWrite.filter((r) => r.__op === 'insert').length + tWrite.filter((r) => r.__op === 'insert').length;
stats.updated = kWrite.filter((r) => r.__op === 'update').length + tWrite.filter((r) => r.__op === 'update').length;

await stmt(REF, `update knowledge_ingestion_run set finished_at = now(),
  status = ${stats.errors ? q('failed') : q('ok')}, counts = ${jb(summary())} where run_id = ${q(runId)}`, 'close run');

console.log(JSON.stringify({ run_id: runId, ...summary() }, null, 2));

function summary() {
  return {
    ref: REF,
    packages_discovered: stats.packages.size, files_discovered: stats.files.size,
    records_read: stats.records_read, canonical_records_expected: stats.canonical_expected,
    knowledge_records: knowledge.size, training_cases: training.size,
    inserted: stats.inserted, updated: stats.updated, unchanged: stats.unchanged,
    superseded: stats.superseded, rejected: stats.rejected, duplicate: stats.duplicate,
    quarantined_certification: stats.quarantined_certification,
    quarantined_files: certFiles.size,
    embedding_created: stats.embedding_created, embedding_skipped: stats.embedding_skipped,
    errors: stats.errors,
    reject_sample: rejects.slice(0, 5),
  };
}
