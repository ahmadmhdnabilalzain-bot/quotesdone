// NEUTRALISE THE cron.schedule CALLS THAT LIVE INSIDE FUNCTION BODIES
//
// The 110 top-level schedule statements were removed by strip_cron_schedules.mjs. Eleven files still
// contain cron.schedule, all of them INSIDE a function body, and a regex is exactly the wrong tool
// there -- it already cut a line out of fn_schema_export and the routine manifest caught it.
//
// TWO OF THE ELEVEN ARE CORRECT AND ARE NOT TOUCHED: fn_schema_export and the Phase C export
// tiebreaker do not schedule anything. They EMIT the text 'cron.schedule(' as part of a schema dump,
// which is what a schema dump is supposed to do.
//
// The other nine would recreate a deleted job the moment their function is called. Each has its
// cron.schedule replaced by a raise notice naming the job and saying it was deleted -- so the
// function still runs, still returns, and tells whoever called it what would once have happened
// instead of silently doing nothing.
//
//   node scripts/kb/neutralise_inbody_cron.mjs [--apply]

import { readFileSync, writeFileSync } from 'node:fs';

const APPLY = process.argv.includes('--apply');
const D = 'scripts/sql/';

// Only these nine. The two export routines are deliberately absent.
const TARGETS = [
  'ads_autopilot_schedule.sql', 'fn_agent_daily_thought.sql', 'fn_knowledge_exam_retrieval.sql',
  'period_report_competitive_section.sql', 'red_view_alerter.sql',
  'schedule_supplier_suspension_emitter.sql', 'staging_monitoring_parity.sql',
  'supply_engine_crons_run_through_the_kernel.sql', 'the_resilience_drill_probes_every_capability.sql',
];

let changed = 0, statements = 0;
for (const f of TARGETS) {
  const p = D + f;
  const src = readFileSync(p, 'utf8');
  const lines = src.split('\n');
  const out = [];
  let i = 0, here = 0;
  while (i < lines.length) {
    if (!/cron\.schedule\(/.test(lines[i])) { out.push(lines[i]); i++; continue; }
    const start = i;
    let stmt = lines[i];
    while (!/;\s*$/.test(lines[i]) && i + 1 < lines.length) { i++; stmt += '\n' + lines[i]; }
    i++;
    // The job name is the first quoted literal in the call.
    const m = stmt.match(/cron\.schedule\(\s*'([^']+)'/);
    const job = m ? m[1] : '(unnamed)';
    const indent = (lines[start].match(/^\s*/) || [''])[0];
    out.push(indent + '-- CRON REMOVED 7 Sep 2026 (founder: "Remove it from the code. Delete, not archive.").');
    out.push(indent + '-- This scheduled ' + job + ', which was deleted from cron.job in the same change.');
    out.push(indent + '-- The notice replaces the call so this routine still runs and still reports, rather');
    out.push(indent + '-- than silently doing nothing or quietly recreating a job nobody asked for.');
    out.push(indent + "raise notice 'cron scheduling removed on 7 Sep 2026: " + job + " is not recreated';");
    here++; statements++;
  }
  if (here) {
    changed++;
    if (APPLY) writeFileSync(p, out.join('\n'));
    console.log((APPLY ? 'edited ' : 'would edit ') + here + '  ' + f);
  }
}
console.log('\nfiles ' + changed + ' · statements ' + statements);
if (!APPLY) console.log('DRY RUN — nothing written.');
