// audit_packs.mjs — what actually landed, per file, against the corpus on disk.
//
// The part-8 brief measured `kb_chunks where citation ilike '%QD-KB%'` and got 0, and concluded
// the knowledge half was not deployed. It is deployed — into kb_stage / ops_kb_stage, which is
// exactly where the packs' own staging schema puts it. kb_chunks is a different corpus.
//
// This compares the 1,006 module JSONL files on disk to kb_stage.file_hashes and
// kb_stage.records, and prints only the deltas.
//
//   node scripts/kb/audit_packs.mjs --ref=<project> --root=<extracted _kbpkgs dir>
import { supabaseAccessToken } from '../lib/supabase_token.mjs';
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const arg = (n) => (process.argv.find(a => a.startsWith(`--${n}=`)) || '').split('=').slice(1).join('=');
const REF = arg('ref'), ROOT = arg('root');
if (!/^[a-z]{20}$/.test(REF) || !ROOT) throw new Error('--ref and --root are required');
const token = supabaseAccessToken();

async function q(sql, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }), signal: AbortSignal.timeout(180_000),
  });
  const body = await r.text();
  if (!r.ok) {
    if (attempt < 5) { await new Promise(s => setTimeout(s, 1500 * 2 ** attempt)); return q(sql, attempt + 1); }
    throw new Error(`management API ${r.status}: ${body.slice(0, 300)}`);
  }
  return JSON.parse(body);
}

// ---- disk side: package_id -> file_name -> {lines, sha}
const disk = new Map();
for (const d of readdirSync(ROOT, { withFileTypes: true })) {
  if (!d.isDirectory()) continue;
  const pkg = d.name.split('-v')[0];                       // QD-KB-001-construction-... -> QD-KB-001-construction-...
  const short = d.name.match(/^(QD-KB-\d+)/)[1];
  for (const f of readdirSync(join(ROOT, d.name))) {
    // The aggregate is every module concatenated, so counting it doubles the package. It was
    // skipped by exact name, and QD-KB-086 numbers its aggregate 24_ rather than 23_ — which made
    // that one package read as short by exactly its own record count, 2,047.
    if (!f.endsWith('.jsonl') || /_all_records\.jsonl$/.test(f)) continue;
    const buf = readFileSync(join(ROOT, d.name, f));
    const lines = buf.toString('utf8').split('\n').filter(l => l.trim()).length;
    if (!disk.has(short)) disk.set(short, { dir: pkg, files: new Map(), lines: 0 });
    disk.get(short).files.set(f, { lines, sha: createHash('sha256').update(buf).digest('hex') });
    disk.get(short).lines += lines;
  }
}
const diskTotal = [...disk.values()].reduce((a, p) => a + p.lines, 0);
const diskFiles = [...disk.values()].reduce((a, p) => a + p.files.size, 0);

// ---- db side
const fh = await q(`select package_id, file_name, sha256, rows_seen from kb_stage.file_hashes;`);
const dbRec = await q(`select package_id, count(*)::bigint as n from kb_stage.records group by 1;`);
const dbByPkg = new Map(dbRec.map(r => [r.package_id, Number(r.n)]));
const fhByPkg = new Map();
for (const r of fh) {
  if (!fhByPkg.has(r.package_id)) fhByPkg.set(r.package_id, new Map());
  fhByPkg.get(r.package_id).set(r.file_name, r);
}

console.log(`disk: ${disk.size} packages, ${diskFiles} module files, ${diskTotal} records`);
console.log(`db  : ${fhByPkg.size} packages in file_hashes, ${fh.length} file rows, ` +
  `${[...dbByPkg.values()].reduce((a, b) => a + b, 0)} records in kb_stage.records`);

// BOTH SHAPES EXIST AT ONCE, AND PICKING ONE INVENTS A HOLE (13 Aug 2026).
//
// package_id is written as the short id by one import and as the full directory name by another,
// and kb_stage.records carries BOTH for the first six categories: QD-KB-002 holds 667 records in
// one module, QD-KB-002-mep-mechanical-electrical-plumbing-v2026.07.31 holds 3,634 across
// eighteen. 667 + 3,634 = 4,301 = exactly the file count on disk. Nothing is missing.
//
// The previous resolve() returned the FIRST match and `dbByPkg.has(short)` is true, so it compared
// the 667-row remnant against 4,301 on disk and reported the category as short by 3,634. Across six
// categories that came to "TOTAL MISSING: 16608" — a 16,608-record hole in the company's own
// knowledge corpus that does not exist. file_hashes was worse: it is keyed ONLY by the full
// directory name, so looking it up under the short id matched nothing and 91 files were reported
// as NEVER RECORDED while every one of them was checkpointed.
//
// Both sides now take EVERY key that resolves to the package and sum. A tool that manufactures a
// missing-knowledge figure is worse than no tool: the next session budgets a re-import against it.
const resolveAll = (short) => {
  const keys = [...dbByPkg.keys(), ...fhByPkg.keys()]
    .filter((k) => k === short || k.startsWith(short + '-'));
  return [...new Set(keys)];
};

let missingFiles = [], shortFiles = [], shortPkgs = [];
for (const [short, p] of [...disk.entries()].sort()) {
  const keys = resolveAll(short);
  const key = keys[0] || short;
  const dbFiles = new Map();
  for (const k of keys) for (const [fn, row] of (fhByPkg.get(k) || new Map())) dbFiles.set(fn, row);
  for (const [fname, info] of p.files) {
    const row = dbFiles.get(fname);
    if (!row) missingFiles.push(`${short}/${fname} (${info.lines} records, NEVER RECORDED)`);
    else if (row.sha256 !== info.sha) shortFiles.push(`${short}/${fname} SHA MISMATCH`);
    else if (Number(row.rows_seen) !== info.lines) shortFiles.push(`${short}/${fname} rows_seen=${row.rows_seen} disk=${info.lines}`);
  }
  const got = keys.reduce((a, k) => a + (dbByPkg.get(k) ?? 0), 0);
  if (got !== p.lines) shortPkgs.push({ short, key, db: got, disk: p.lines, delta: p.lines - got });
}

console.log(`\nfiles on disk never recorded in file_hashes: ${missingFiles.length}`);
missingFiles.forEach(m => console.log('  ' + m));
console.log(`\nfiles recorded with a different sha or row count: ${shortFiles.length}`);
shortFiles.slice(0, 40).forEach(m => console.log('  ' + m));
console.log(`\npackages whose kb_stage.records count != disk: ${shortPkgs.length}`);
shortPkgs.sort((a, b) => b.delta - a.delta)
  .forEach(p => console.log(`  ${p.short.padEnd(12)} db=${String(p.db).padStart(6)} disk=${String(p.disk).padStart(6)} missing=${p.delta}`));
console.log(`\nTOTAL MISSING: ${shortPkgs.reduce((a, p) => a + p.delta, 0)}`);
