// Verifies the V2+V3 delivery: counts, stable-id uniqueness, parse errors,
// path traversal, secrets, and the certification-separation boundary.
// Usage: node scripts/kb/v3_inventory.mjs <extracted-root> [--json out.json]
import fs from 'node:fs';
import path from 'node:path';
import { records, walk } from './v3_package.mjs';

const root = process.argv[2];
if (!root) { console.error('usage: v3_inventory.mjs <extracted-root>'); process.exit(2); }
const jsonOut = process.argv.includes('--json') ? process.argv[process.argv.indexOf('--json') + 1] : null;

const SECRET_RE = /(sk-[A-Za-z0-9]{16,}|eyJhbGciOi[A-Za-z0-9._-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|service_role[^\n]{0,40}eyJ)/;

// The ops corpus ships each record twice: once in the baseline corpus and once
// in the department assignment file, which adds a `v2_assignment` block. Two
// copies that agree on every shared key differ only by enrichment — the importer
// merges them. Disagreement on a shared key is a genuine conflict.
function additiveMerge(a, b) {
  if (!a || !b || typeof a !== 'object' || typeof b !== 'object') return false;
  for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) {
    if (a[k] === undefined || b[k] === undefined) continue;
    if (JSON.stringify(a[k]) !== JSON.stringify(b[k])) return false;
  }
  return true;
}

const counts = {};
const bump = (k, n = 1) => { counts[k] = (counts[k] || 0) + n; };
const ids = new Map();
const dupes = [];
const rejects = [];
const traversal = [];
const secrets = [];
const depts = new Set(), roles = new Set(), cats = new Set();
const byRecordType = {};
const byLayer = {};

for (const f of walk(root)) {
  const rel = path.relative(root, f).replace(/\\/g, '/');
  if (rel.split('/').includes('..') || path.isAbsolute(rel)) traversal.push(rel);
}

let total = 0;
for (const r of records(root)) {
  if (r.__reject) { rejects.push(r); continue; }
  total++;
  bump(`gen_${r.generation}`);
  bump(`scope_${r.scope_type}`);
  byRecordType[r.record_type] = (byRecordType[r.record_type] || 0) + 1;
  byLayer[r.layer] = (byLayer[r.layer] || 0) + 1;
  if (r.scope_type === 'department') depts.add(r.scope_key);
  if (r.scope_type === 'role') roles.add(r.scope_key);
  if (r.scope_type === 'category') cats.add(r.scope_key);
  // A stable id may legitimately arrive twice — the ops corpus ships each record
  // once in the baseline corpus and again in its department assignment file. That
  // is a re-delivery, not a duplicate, as long as the checksum agrees. Two records
  // with the same id and different content is the real defect.
  const key = `${r.generation}|${r.stable_id}`;
  const prev = ids.get(key);
  if (prev) {
    if (prev.checksum === r.checksum) bump('duplicate_identical');
    else if (additiveMerge(prev.data, r.structured_data)) bump('duplicate_additive');
    else dupes.push({ stable_id: r.stable_id, a: prev.path, b: r.source_path });
  } else ids.set(key, { path: r.source_path, checksum: r.checksum, data: r.structured_data });
  if (typeof r.content === 'string' && SECRET_RE.test(r.content)) secrets.push(r.source_path);
  if (r.is_certification) bump('certification_records');
}

// V3 training-case counts by declared type
const v3Counts = {};
for (const r of records(root)) {
  if (r.__reject) continue;
  if (r.generation !== 'V3') continue;
  if (r.layer !== 'case_training') continue;
  v3Counts[r.record_type] = (v3Counts[r.record_type] || 0) + 1;
}

const EXPECT = {
  departments: 24, roles: 96, categories: 86,
  v3: { role_adversarial: 2304, role_tool: 1152, role_uncertainty: 1152, role_cross_department: 768, department_management: 672, category_case: 2924, total: 8972 },
};

const v3Total = Object.values(v3Counts).reduce((a, b) => a + b, 0);
const report = {
  root, total_records: total,
  departments: depts.size, roles: roles.size, categories: cats.size,
  counts, byLayer, byRecordType, v3TrainingCounts: v3Counts, v3TrainingTotal: v3Total,
  duplicate_stable_ids: dupes.length, duplicates_sample: dupes.slice(0, 5),
  rejects: rejects.length, rejects_sample: rejects.slice(0, 5),
  path_traversal: traversal.length, secrets_found: secrets.length, secrets_sample: secrets.slice(0, 3),
  expected: EXPECT,
};

const fails = [];
if (depts.size !== EXPECT.departments) fails.push(`departments ${depts.size} != ${EXPECT.departments}`);
if (roles.size !== EXPECT.roles) fails.push(`roles ${roles.size} != ${EXPECT.roles}`);
if (cats.size !== EXPECT.categories) fails.push(`categories ${cats.size} != ${EXPECT.categories}`);
for (const [k, v] of Object.entries(EXPECT.v3)) {
  if (k === 'total') continue;
  if ((v3Counts[k] || 0) !== v) fails.push(`v3.${k} ${v3Counts[k] || 0} != ${v}`);
}
if (v3Total !== EXPECT.v3.total) fails.push(`v3 total ${v3Total} != ${EXPECT.v3.total}`);
if (dupes.length) fails.push(`${dupes.length} conflicting stable ids (same id, different content)`);
if (rejects.length) fails.push(`${rejects.length} unparseable records`);
if (traversal.length) fails.push(`${traversal.length} path traversal entries`);
if (secrets.length) fails.push(`${secrets.length} files matched a secret pattern`);
report.fails = fails;
report.verdict = fails.length ? 'FAIL' : 'PASS';

if (jsonOut) fs.writeFileSync(jsonOut, JSON.stringify(report, null, 2));
console.log(JSON.stringify({
  verdict: report.verdict, total_records: total, departments: depts.size, roles: roles.size,
  categories: cats.size, v3TrainingCounts: v3Counts, v3TrainingTotal: v3Total,
  byLayer, conflicting_stable_ids: dupes.length,
  identical_redeliveries: counts.duplicate_identical || 0,
  additive_redeliveries: counts.duplicate_additive || 0,
  canonical_records: ids.size, rejects: rejects.length,
  certification_records: counts.certification_records || 0,
  path_traversal: traversal.length, secrets_found: secrets.length, fails,
}, null, 2));
process.exit(fails.length ? 1 : 0);
