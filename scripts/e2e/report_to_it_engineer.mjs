// Hands the newest e2e run to the IT engineer: public.fn_it_journey_ingest turns every failed step
// into a finding for the seat that owns that part of the funnel, and a passing run closes it.
// Run by .github/workflows/nightly-journey.yml after scripts/e2e/run.mjs.
//
//   node scripts/e2e/report_to_it_engineer.mjs <reports dir>
//   node scripts/e2e/report_to_it_engineer.mjs <reports dir> --smoke <sha> <changed-files.txt>
//     (.github/workflows/it-post-deploy-smoke.yml: fn_it_smoke_ingest, owners from the changed files)
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { sql, lit } from '../lib/db.mjs';

const root = process.argv[2];
const smokeAt = process.argv.indexOf('--smoke');
const smoke = smokeAt > 0 ? { sha: process.argv[smokeAt + 1], files: process.argv[smokeAt + 2] } : null;
if (smoke && (!/^[0-9a-f]{7,40}$/.test(smoke.sha || '') || !existsSync(smoke.files || ''))) {
  console.error('usage: ... --smoke <commit sha> <file listing the changed paths, one per line>');
  process.exit(2);
}
if (!root || !existsSync(root)) {
  console.error('usage: node scripts/e2e/report_to_it_engineer.mjs <reports dir written by scripts/e2e/run.mjs>');
  process.exit(2);
}
const runs = readdirSync(root).map((d) => join(root, d)).filter((d) => existsSync(join(d, 'run.json')))
  .sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
if (!runs.length) { console.error(`no run with a run.json under ${root}: the harness did not finish`); process.exit(3); }

const run = JSON.parse(readFileSync(join(runs[0], 'run.json'), 'utf8'));
const all = JSON.parse(readFileSync(join(runs[0], 'steps.json'), 'utf8'))
  .map(({ journey, name, status, detail }) => ({ journey, name, status, detail: String(detail ?? '').slice(0, 600) }));
// A DEAD HARNESS SESSION IS NOT HANDED TO A SEAT. fn_it_journey_ingest assigns an owner from the
// journey LETTER alone, so this FAIL step would become a finding titled "Nightly journey failed"
// addressed to the sales_engineer or the accountant — a harness failure delivered to a person as
// their product defect, which is the mislabelling browser.mjs throws HarnessSignedOut to stop. It
// is NOT hidden: it stays in report.md and steps.json, it is printed below, it sets run.json's
// harness_signed_out, and it already made the run INCOMPLETE — which is the field the ingest does
// understand, and which stops it closing any finding on this run's silence.
// Identified by run.json's own value rather than by a shared string: this file would otherwise have
// to import scripts/e2e/browser.mjs for one constant, and that pulls playwright into a script whose
// only other dependency is the database client. run.mjs writes this step's detail and this field
// from the same variable, so matching on it cannot drift.
const dead = run.harness_signed_out || null;
const steps = dead ? all.filter((s) => !(s.status === 'FAIL' && s.detail === dead)) : all;
// complete: did the harness look at everything? fn_it_journey_ingest settles the journey duty —
// closing every open duty:journey:% finding this run did not re-raise — and that is only sound on a
// run that actually ran every journey. A run cut short by its deadline (QD_E2E_DEADLINE_MS) or by
// --journey still reports its heartbeat and its failures; it just may not close anything.
// Older reports have no such field; those runs predate truncation and are treated as complete.
const report = { tag: run.tag, leftovers: run.leftovers ?? null, complete: run.complete !== false, steps };
if (smoke) {
  report.sha = smoke.sha;
  report.changed_files = readFileSync(smoke.files, 'utf8').split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
}
const fn = smoke ? 'fn_it_smoke_ingest' : 'fn_it_journey_ingest';
const [r] = await sql(`select public.${fn}(${lit(JSON.stringify(report))}::jsonb) r`);
console.log(`reported run ${run.tag}: ${steps.length} steps ->`, JSON.stringify(r.r));
if (dead) {
  console.error(`\n!! ${dead}`);
  console.error(`!! Run ${run.tag} is INCOMPLETE and settles nothing. ${all.length - steps.length} harness step(s) were` +
    ' kept out of the per-seat ingest: this is the harness, not a product defect, and it belongs to no seat.');
  process.exitCode = 1;
}
