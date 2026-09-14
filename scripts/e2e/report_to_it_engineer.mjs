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
const steps = JSON.parse(readFileSync(join(runs[0], 'steps.json'), 'utf8'))
  .map(({ journey, name, status, detail }) => ({ journey, name, status, detail: String(detail ?? '').slice(0, 600) }));
const report = { tag: run.tag, leftovers: run.leftovers ?? null, steps };
if (smoke) {
  report.sha = smoke.sha;
  report.changed_files = readFileSync(smoke.files, 'utf8').split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
}
const fn = smoke ? 'fn_it_smoke_ingest' : 'fn_it_journey_ingest';
const [r] = await sql(`select public.${fn}(${lit(JSON.stringify(report))}::jsonb) r`);
console.log(`reported run ${run.tag}: ${steps.length} steps ->`, JSON.stringify(r.r));
