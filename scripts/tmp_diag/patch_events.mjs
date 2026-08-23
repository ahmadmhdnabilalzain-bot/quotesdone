import { readFileSync, writeFileSync } from 'node:fs';
const f = 'scripts/phase_d/observe_events_live.mjs';
let s = readFileSync(f, 'utf8');

// 1. ONE QUEUE, NOT ONE PER WORKER. Array.from({length: JOBS}, () => worker([...WFS])) hands every
//    worker its own full copy, so each workflow was driven JOBS times.
const OLDQ = `await Promise.all(Array.from({ length: JOBS }, () => worker([...WFS])));`;
const NEWQ = `const queue = [...WFS];
await Promise.all(Array.from({ length: JOBS }, () => worker(queue)));`;
if (!s.includes(OLDQ)) throw new Error('queue anchor missing');
s = s.split(OLDQ).join(NEWQ);
s = s.split(`async function worker(queue) {`).join(`async function worker(queue) {`);

// 2. THE FAIL ARM NEVER FAILED ANYTHING. hold_at_first_open_step alone does not hold the handler:
//    the kernel dispatches at step OPENING and the deterministic handler completes the step in the
//    same statement, so by the time fn_kernel_step_complete was called there was no open step and
//    the swallowed exception hid it. Every FAIL arm reported the run still `active` and not one of
//    the 30 blocked events was emitted. The hold is app.phase_d_hold_step, set BEFORE the scenario
//    is built, exactly as scripts/phase_d/build_step_branch_coverage.mjs sets it.
const OLDP = `const PRE = (wf, label, hold) => \``;
const NEWP = `const PRE = (wf, label, hold) => \`
  \${hold ? \`perform set_config('app.phase_d_hold_step',
    (select s.step_id from public.phase_b_workflow_step s
      where s.workflow_id = '\${wf}' order by s.step_no limit 1), true);\` : ''}`;
if (!s.includes(OLDP)) throw new Error('PRE anchor missing');
s = s.split(OLDP).join(NEWP);

const OLDH = `    'reviewer_candidates', v_cands\${hold ? \`, 'hold_at_first_open_step', true\` : ''}));`;
const NEWH = `    'reviewer_candidates', v_cands\${hold ? \`, 'hold_at_step_id',
      (select s.step_id from public.phase_b_workflow_step s
        where s.workflow_id = '\${wf}' order by s.step_no limit 1)\` : ''}));`;
if (!s.includes(OLDH)) throw new Error('hold anchor missing');
s = s.split(OLDH).join(NEWH);

// 3. AND A SWALLOWED FAILURE IS NOT A MEASUREMENT. If fn_kernel_step_complete raises, say so.
const OLDE = `  exception when others then null;
  end;`;
const NEWE = `  exception when others then
    v_out := 'stepfail=' || left(regexp_replace(SQLERRM,'[|~<>]',' ','g'), 120) || ' ';
  end;
  perform set_config('app.phase_d_hold_step','', true);`;
if (!s.includes(OLDE)) throw new Error('exception anchor missing');
s = s.split(OLDE).join(NEWE);

writeFileSync(f, s);
console.log('patched');
