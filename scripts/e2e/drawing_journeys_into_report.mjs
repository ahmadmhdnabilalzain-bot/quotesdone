// scripts/e2e/drawing_journeys_into_report.mjs — runs the three drawing journeys and writes their results INTO the
// nightly run's steps.json, so report_to_it_engineer.mjs hands every failure to its seat. Assigned: sales_engineer.
//
// WHY (review of #967, 24 Sep 2026). The drawing journeys ran after the report step with continue-on-error, so a
// failure reached nobody: a red step in a job no one reads is the same as no test. Each journey's PASS / FAIL
// lines become steps of journey "f-drawings/<script>". fn_it_journey_ingest owns steps by the journey's first letter,
// and 'f' is the sales engineer's (the comparison and the documents a supplier receives). A script that dies
// before printing a result is one FAIL step saying so, never silence.
//
//   node scripts/e2e/drawing_journeys_into_report.mjs <reports dir written by scripts/e2e/run.mjs>
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const root = process.argv[2];
const SCRIPTS = ['drawing_reaches_suppliers.mjs', 'cad_identity_reaches_no_supplier.mjs', 'every_drawing_format_is_read.mjs'];
const PER_SCRIPT_MS = 12 * 60_000;

/** PASS / FAIL lines of one journey's output as steps. */
export function stepsOf(script, stdout, status) {
  const journey = 'f-drawings/' + script.replace(/\.mjs$/, '');
  const steps = [];
  for (const line of String(stdout || '').split(/\r?\n/)) {
    const m = /^(PASS|FAIL)\s{2}(.+?)(?: - (.*))?$/.exec(line);
    if (m) steps.push({ journey, name: m[2].slice(0, 200), status: m[1], detail: (m[3] || '').slice(0, 600) });
  }
  if (!steps.length || (status !== 0 && !steps.some((s) => s.status === 'FAIL'))) {
    steps.push({ journey, name: 'the journey ran to its end', status: 'FAIL', detail: `exit ${status}; ${steps.length} result line(s) before it stopped` });
  }
  return steps;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  if (!root || !existsSync(root)) { console.error('usage: node scripts/e2e/drawing_journeys_into_report.mjs <reports dir>'); process.exit(2); }
  const runs = readdirSync(root).map((d) => join(root, d)).filter((d) => existsSync(join(d, 'steps.json'))).sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
  if (!runs.length) { console.error(`no nightly run with a steps.json under ${root}`); process.exit(3); }
  const file = join(runs[0], 'steps.json');
  const added = [];
  for (const s of SCRIPTS) {
    const r = spawnSync('node', [join('scripts', 'e2e', s)], { encoding: 'utf8', timeout: PER_SCRIPT_MS, env: process.env });
    process.stdout.write(r.stdout || ''); process.stderr.write(r.stderr || '');
    added.push(...stepsOf(s, r.stdout, r.status ?? -1));
  }
  const steps = JSON.parse(readFileSync(file, 'utf8'));
  writeFileSync(file, JSON.stringify([...steps, ...added], null, 1));
  const failed = added.filter((s) => s.status === 'FAIL').length;
  console.log(`drawing journeys: ${added.length} step(s) added to ${file}, ${failed} failed`);
  process.exitCode = failed ? 1 : 0;
}
