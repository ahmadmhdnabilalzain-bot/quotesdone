import { readCsv } from './readcsv.mjs';
const R = readCsv('docs/phase-d/PHASE_D_STEP_BRANCH_COVERAGE.csv');
for (const r of R.filter(x => x.reached_only_by_direct_step_complete === 'YES'))
  console.log(r.step_id, '| dispatches', r.dispatches, '| opened_by', r.opened_by, '| outcome', r.dispatch_outcome, '| state', r.pass_step_state, '| effect', r.actual_effect, '| declared', r.declared_effect);
