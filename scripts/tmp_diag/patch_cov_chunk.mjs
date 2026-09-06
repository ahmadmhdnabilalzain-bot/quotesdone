import { readFileSync, writeFileSync } from 'node:fs';
const p = 'scripts/phase_d/build_step_branch_coverage.mjs';
let s = readFileSync(p, 'utf8');
const rep = (o, n) => { const c = s.split(o).length - 1; if (c !== 1) throw new Error(`anchor ${c}: ${o.slice(0, 70)}`); s = s.replace(o, n); };

rep(`async function passArm(wf) {
  const q = \`do $emit$`,
`// ONE DRIVE PER CHUNK OF STEPS, BECAUSE THE TRANSPORT CUTS AT 2000 CHARACTERS. Measured 23 Aug
// 2026: the single-drive pass arms for W17 and W30 -- eleven steps each -- ran over it, the last
// step's line lost its tail fields, and the matrix reported W17-S11 and W30-S11 as "reached only by
// a direct step-complete call" while both carried an EXECUTED dispatch and an effect. The guard
// below now makes an overrun a stop; this is what keeps it from happening. Each chunk is its own
// transaction, its own audited fixture scenario and its own drive of the whole workflow -- so every
// step's row still comes from a drive that reached that step through the canonical path -- and it
// reports only the steps in its own window.
const CHUNK = 7;
async function passArm(wf, lo, hi) {
  const q = \`do $emit$`);

rep(`     where s.workflow_id = '\${wf}'
     order by s.step_no`,
`     where s.workflow_id = '\${wf}' and s.step_no between \${lo} and \${hi}
     order by s.step_no`);

rep(`  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','\${label}'));`,
`  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','\${label}'));`);

rep(`    const p = await passArm(wf);`,
`    const chunks = [];
    for (let lo = 1; lo <= steps.length; lo += CHUNK) chunks.push([lo, Math.min(lo + CHUNK - 1, steps.length)]);
    const parts = [];
    for (const [lo, hi] of chunks) parts.push(await passArm(wf, lo, hi));
    const p = parts.join('');`);

// The label must differ per chunk so two chunks of one workflow are two audited fixture runs.
rep("const q = `do $emit$\ndeclare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := ''; r record; v_run bigint;\n        v_ref_key text; v_boid text;\nbegin${PRE(wf, `cov-${wf.toLowerCase()}`)}",
    "const q = `do $emit$\ndeclare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := ''; r record; v_run bigint;\n        v_ref_key text; v_boid text;\nbegin${PRE(wf, `cov-${wf.toLowerCase()}-${lo}`)}");

rep("    'workflow_id','${wf}','label','cov-${wf.toLowerCase()}',",
    "    'workflow_id','${wf}','label','cov-${wf.toLowerCase()}-${lo}',");

rep("    scenario: `cov-${s.workflow_id.toLowerCase()} (pass), cvf-${s.step_id.toLowerCase()} (fail)`,",
    "    scenario: `cov-${s.workflow_id.toLowerCase()}-${Math.floor((s.step_no - 1) / CHUNK) * CHUNK + 1} (pass), cvf-${s.step_id.toLowerCase()} (fail)`,");

writeFileSync(p, s);
console.log('patched');
