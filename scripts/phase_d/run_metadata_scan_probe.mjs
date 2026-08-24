// PD-PRIV-005 — scan the committed fixtures and record what was actually found.
//
// The verdict is a MEASUREMENT, never a constant: this reads the committed bytes, extracts their
// metadata, judges it against the identifier classes the DATABASE registers, and records the result
// in public.phase_d_metadata_scan. Nothing here decides in advance what the answer should be; the
// assertions below say what the answer must be and fail the run when it is not.
//
//   node scripts/phase_d/run_metadata_scan_probe.mjs            # scan and print, write nothing
//   node scripts/phase_d/run_metadata_scan_probe.mjs --write    # scan and record the verdicts
//
// ZERO COST. No model, no provider, no network beyond the Supabase management endpoint.

import { q } from '../tmp_diag/q.mjs';
import { scan, sha256, mediaTypeOf, readFixture, FIXTURES, SCANNER, SCANNER_VERSION }
  from './metadata_scan.mjs';

const WRITE = process.argv.includes('--write');
const lit = (s) => (s === null || s === undefined ? 'null' : `'${String(s).replace(/'/g, "''")}'`);

const classes = await q(
  `select identifier_class, detection, pattern from public.phase_d_personal_identifier_class
    order by identifier_class`);
if (!classes.length) {
  console.error('public.phase_d_personal_identifier_class is empty — apply O04 first. '
    + 'A scan against an empty class list would report CLEAN for everything.');
  process.exit(1);
}
console.log(`identifier classes registered: ${classes.length} `
  + `(${classes.filter((c) => c.detection === 'REGEX').length} REGEX, `
  + `${classes.filter((c) => c.detection !== 'REGEX').length} not machine-decidable)`);

// Which committed revision each fixture is the bytes of. The migration that registered the
// revisions carries the same digests; a mismatch here means the fixtures were regenerated without
// the registry being updated, and that is a failure rather than something to paper over.
const REVISIONS = {
  'supplier_drawing_dirty.pdf': 'zz-demo-rev-drawing-unredacted',
  'supplier_drawing_clean.pdf': 'zz-demo-rev-drawing-safe',
  'supplier_photo_dirty.png': 'zz-demo-rev-photo-unredacted',
  'supplier_photo_clean.png': 'zz-demo-rev-photo-safe',
};
// zz-disp-003-rev-safe is the SAME clean PDF bytes under a second revision_ref, registered by O10
// so PD-DISP-003's control package satisfies the file-set leg O07 gave BR-012. The scan is looked
// up by (revision_ref, safe_sha256), so identical bytes still need a row per revision claiming them.
const EXTRA_REVISIONS = { 'supplier_drawing_clean.pdf': 'zz-disp-003-rev-safe' };
const EXPECTED = {
  'supplier_drawing_dirty.pdf': 'IDENTIFIERS_FOUND',
  'supplier_drawing_clean.pdf': 'CLEAN',
  'supplier_photo_dirty.png': 'IDENTIFIERS_FOUND',
  'supplier_photo_clean.png': 'CLEAN',
};

let bad = 0;
const rows = [];
for (const name of Object.keys(FIXTURES)) {
  const buf = readFixture(name);
  const digest = sha256(buf);
  const media = mediaTypeOf(name);
  const r = scan(buf, media, classes);
  const ok = r.outcome === EXPECTED[name];
  if (!ok) bad++;
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${name.padEnd(30)} ${r.outcome.padEnd(18)} `
    + `sha ${digest.slice(0, 12)}  ${r.findings.length} finding(s) `
    + `[${[...new Set(r.findings.map((f) => f.identifier_class))].join(',')}]`);
  rows.push({ name, digest, revision: REVISIONS[name], r });
  if (EXTRA_REVISIONS[name]) rows.push({ name, digest, revision: EXTRA_REVISIONS[name], r });
}

// The two arms that make the scanner's silence meaningful, recorded as measurements too: a file it
// cannot parse and a media type it does not handle must NOT come back CLEAN.
for (const [label, buf, media, want] of [
  ['(corrupt png)', Buffer.from('not a png'), 'image/png', 'SCAN_FAILED'],
  ['(unsupported type)', Buffer.from('x'), 'application/zip', 'UNSUPPORTED'],
]) {
  const r = scan(buf, media, classes);
  const ok = r.outcome === want;
  if (!ok) bad++;
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${label.padEnd(30)} ${r.outcome.padEnd(18)} (fail-closed arm)`);
}

if (bad) {
  console.error(`\n${bad} arm(s) did not produce the outcome the control requires. Nothing written.`);
  process.exit(1);
}

if (!WRITE) {
  console.log('\nno --write: the database was read and not written.');
  process.exit(0);
}

// Verify the registry agrees with the bytes BEFORE writing a verdict about them. A scan recorded
// against a digest no revision claims is a verdict about nothing.
const known = await q(
  `select revision_ref, source_sha256, safe_sha256 from public.phase_d_file_revision
    where revision_ref in (${[...Object.values(REVISIONS), ...Object.values(EXTRA_REVISIONS)].map(lit).join(',')})`);
const byRef = new Map(known.map((k) => [k.revision_ref, k]));
for (const row of rows) {
  const k = byRef.get(row.revision);
  if (!k) {
    console.error(`revision ${row.revision} is not registered. Apply O05 first.`); process.exit(1);
  }
  if (k.source_sha256 !== row.digest && k.safe_sha256 !== row.digest) {
    console.error(`revision ${row.revision} names source ${k.source_sha256.slice(0, 12)} / `
      + `safe ${String(k.safe_sha256).slice(0, 12)} and the committed fixture hashes to `
      + `${row.digest.slice(0, 12)}. Regenerate the registry, do not adjust the scan.`);
    process.exit(1);
  }
}

const values = rows.map((row) => `(${lit(row.revision)}, ${lit(row.digest)}, ${lit(SCANNER)}, `
  + `${lit(SCANNER_VERSION)}, ${lit(`{${row.r.classes_inspected.join(',')}}`)}::text[], `
  + `${lit(row.r.outcome)}, ${lit(JSON.stringify(row.r.findings))}::jsonb, ${lit(row.r.detail)})`).join(',\n  ');

await q(`
insert into public.phase_d_metadata_scan
  (revision_ref, scanned_sha256, scanner, scanner_version, classes_inspected, outcome, findings, detail)
values
  ${values}
on conflict (revision_ref, scanned_sha256, scanner, scanner_version) do update
  set outcome = excluded.outcome, findings = excluded.findings, detail = excluded.detail,
      classes_inspected = excluded.classes_inspected, scanned_at = now();`);

const back = await q(`select revision_ref, outcome, jsonb_array_length(findings) as n
  from public.phase_d_metadata_scan where scanner = ${lit(SCANNER)} order by revision_ref`);
console.log('\nrecorded:');
for (const b of back) console.log(`  ${b.revision_ref.padEnd(34)} ${b.outcome.padEnd(18)} ${b.n} finding(s)`);
