import { readFileSync, writeFileSync } from 'node:fs';
const p = 'scripts/phase_d/build_step_branch_coverage.mjs';
let s = readFileSync(p, 'utf8');
const rep = (o, n) => { const c = s.split(o).length - 1; if (c !== 1) throw new Error(`anchor ${c}: ${o.slice(0, 70)}`); s = s.replace(o, n); };

// ---- the emitted per-step line: shorter, and the two constant fields move to the RUN line -------
rep(`      || '|' || coalesce(left(r.result_reference,64),'-')
      || '|' || coalesce(r.state_before,'-') || '>' || coalesce(r.state_after,'-')
      || '|' || coalesce(r.provider_mode,'-')
      || '|' || r.gates_n::text
      || '|' || coalesce(r.reviewer_role_id,'-')`,
`      || '|' || coalesce(left(r.result_reference,28),'-')
      || '|' || coalesce(r.state_before,'-') || '>' || coalesce(r.state_after,'-')
      || '|' || coalesce(r.provider_mode,'-')
      || '|' || r.gates_n::text
      || '|' || coalesce(left(r.reviewer_role_id,22),'-')`);

// ---- the guard: a truncated payload must fail loudly, never quietly -----------------------------
rep(`  raise exception 'COVP<<%>>', v_out;`,
`  -- A TRUNCATED PAYLOAD IS NOT A SHORT ANSWER. The management endpoint cuts an exception message at
  -- 2000 characters. Measured 23 Aug 2026: the pass arms for W17 and W30 -- eleven steps each --
  -- ran over it, the LAST step's line lost its tail fields, and the matrix reported W17-S11 and
  -- W30-S11 as "reached only by a direct step-complete call" when both carried an EXECUTED dispatch
  -- and an effect. A silent cut is the defect; this makes it a stop.
  if length(v_out) > 1750 then
    raise exception 'PHASE_D_COVERAGE_OVERFLOW __WF__ produced % characters over the 1750 this transport carries. Shorten the per-step fields; do not let a step fall off the end.', length(v_out);
  end if;
  raise exception 'COVP<<%>>', v_out;`);

rep(`begin\${PRE(wf, \`cov-\${wf.toLowerCase()}\`)}`,
    `begin\${PRE(wf, \`cov-\${wf.toLowerCase()}\`)}`);

// The guard names the workflow; substitute it the same way the driver's SQL does.
rep(`  return emit(q, 'COVP');`,
`  return emit(q.split('__WF__').join(wf), 'COVP');`);

writeFileSync(p, s);
console.log('patched');
