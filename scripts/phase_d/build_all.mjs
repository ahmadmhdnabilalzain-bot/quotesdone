// EVERY PHASE D DELIVERABLE, IN ORDER, IN ONE COMMAND.
//
//   npm run build:phase-d
//   node scripts/phase_d/build_all.mjs
//
// Before this file the nine builders were run by hand, one at a time, in whatever order the person
// remembered. The order is fixed in lib/deliverable.mjs so the npm script, this runner and the
// deliverable check all agree on one sequence.
//
// NO BUILDER HERE FILLS A TABLE ANOTHER ONE READS. This header used to claim one did — "the
// step-case export reads the same table after fn_phase_d_run_step_cases() has written it" — and
// that dependency does not exist in this file. Measured 20 Aug 2026: `grep -rn
// fn_phase_d_run_step_cases scripts/phase_d/` names it only in prose, in this header and in
// build_step_case_result.mjs's own instructions. Two builders READ public.phase_d_step_case_result
// (the crosswalk's `result` column and the step-case export) and neither writes it; the routine
// that writes it is run separately, by hand, before this command:
//
//   node scripts/phase_d/run_step_cases_live.mjs
// (NOT select public.fn_phase_d_run_step_cases() — retired by phase_d_p02; its first act was to
//  DELETE public.phase_d_step_case_result and repopulate it from the superseded matrix.)
//
// Say it here because neither reader can tell you it is owed. build_step_case_result.mjs refuses a
// SHORT table (`rows.length !== 7 × frozen steps`, :44) but cannot tell a stale full table from a
// fresh one, and build_d0_crosswalk.mjs has no guard at all — it falls back to 'NOT_RUN' per step.
// So a run of this command over a stale table produces nine deliverables and no complaint.
//
// TWO OF THE NINE DRIVE PRODUCTION. build_workflow_implementation_result.mjs drives all 30 frozen
// workflows and build_injected_defect_result.mjs injects all 75 catalogue defects, each inside a
// transaction that ends in `raise exception` and leaves nothing. They are marked in the run log,
// they are slow, and they are the reason this is not a command to run idly.
//
// The whole set is regenerated AFTER the final apply of a programme, never per increment — a
// deliverable rebuilt halfway through records a halfway state as if it were the answer.
import { spawnSync } from 'node:child_process';
import { BUILDERS, OUT_DIR } from './lib/deliverable.mjs';

console.log(`writing ${BUILDERS.length} deliverable(s) into ${OUT_DIR}/\n`);

const failed = [];
for (const b of BUILDERS) {
  console.log(`── ${b.script}${b.drives ? '   (drives production in an aborted transaction)' : ''}`);
  const started = Date.now();
  const r = spawnSync(process.execPath, [b.script], { stdio: 'inherit', timeout: 15 * 60 * 1000 });
  const took = ((Date.now() - started) / 1000).toFixed(1);
  if (r.status !== 0) {
    failed.push(`${b.script} exited ${r.status} after ${took}s`);
    // KEEP GOING. One builder failing is a fact about that builder; stopping here would hide
    // whether the other eight still work and turn one defect into an unknown number of them.
    console.error(`   FAILED (${r.status}) after ${took}s\n`);
  } else {
    console.log(`   ok, ${took}s\n`);
  }
}

if (failed.length) {
  console.error(`${failed.length} of ${BUILDERS.length} builder(s) failed:`);
  for (const f of failed) console.error(`  ${f}`);
  console.error('\nNothing partial was committed by this run, but the deliverables on disk are now a '
    + 'mixture of fresh and stale. Fix the builders and re-run the whole set before committing any '
    + 'of it.');
  process.exit(1);
}
console.log(`all ${BUILDERS.length} deliverables rebuilt. Confirm they match what is committed:`);
console.log('  node --test scripts/checks/phase_d_deliverables_match_production.test.mjs');
