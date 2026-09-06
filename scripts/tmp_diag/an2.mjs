import { readCsv } from './readcsv.mjs';
const R = readCsv('docs/phase-d/PHASE_D_STEP_BRANCH_COVERAGE.csv');
for (const r of R.filter(x => x.result !== 'COVERED'))
  console.log(r.step_id, '|', r.result, '|', r.dispatch_outcome, r.dispatch_refusal, '| declared', r.declared_effect, '| actual', r.actual_effect, '| fail', r.fail_branch_exercised, r.fail_step_state, r.fail_run_state, r.fail_refusal);
