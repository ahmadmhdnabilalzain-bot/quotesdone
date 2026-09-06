import { readCsv } from './readcsv.mjs';
const R = readCsv(process.argv[2]);
console.log('rows', R.length);
const p = (t, f) => { console.log('--- ' + t + ' ---'); for (const r of R.filter(f)) console.log(r.step_id, '|', r.step_type, '| fail:', r.fail_branch_exercised, r.fail_step_state, r.fail_run_state, '| declared', r.fail_declared_run_state, '|', r.fail_refusal, '|', r.dispatch_refusal); };
p('STEP_NEVER_OPENED', x => x.result === 'STEP_NEVER_OPENED');
p('FAIL_BRANCH_NOT_AS_DECLARED', x => x.result === 'FAIL_BRANCH_NOT_AS_DECLARED');
p('direct complete', x => x.reached_only_by_direct_step_complete === 'YES');
const m = {}; for (const r of R.filter(x => x.result === 'NO_EFFECT_ON_PASS')) m[r.dispatch_refusal] = (m[r.dispatch_refusal] || 0) + 1;
console.log('NO_EFFECT_ON_PASS by refusal:', m);
