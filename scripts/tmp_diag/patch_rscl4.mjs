import { readFileSync, writeFileSync } from 'node:fs';
const f = 'scripts/phase_d/run_step_cases_live.mjs';
let s = readFileSync(f, 'utf8');
const D = String.fromCharCode(36);

// THE PURE TEST MUST PREDICT THE HANDLER EXACTLY, OR IT IS PREDICTING SOMETHING ELSE.
// fn_phase_d_handler_execute does not hand a gate the caller's evidence alone: it builds its own
// base object -- step_id, run_id, step_run_id, actor_role_id, reviewer_role_id for a gate;
// accountable_role_id, workflow_id, founder_gate, execution_context as well for a rule -- and MERGES
// the caller's on top. So a key in that base can never be removed by a caller, and a pure test that
// removed it predicted a refusal the handler cannot produce. Measured on W03: five steps whose
// "load-bearing" key was actor_role_id, where the handler sailed past every gate and failed at
// pd_effect_owner_or_key_missing instead. The base is built here, the same way, and the candidates
// exclude every key it holds.
const OLD_DECL = `  v_e0 bigint; v_e1 bigint; v_e bigint; v_neg text; v_gk text; v_hit text; v_cand text;`;
const NEW_DECL = `  v_e0 bigint; v_e1 bigint; v_e bigint; v_neg text; v_gk text; v_hit text; v_cand text;
  v_gbase jsonb; v_rbase jsonb;`;
if (!s.includes(OLD_DECL)) throw new Error('decl anchor missing');
s = s.split(OLD_DECL).join(NEW_DECL);

const OLD_SETUP = `  select count(*) into v_e0 from public.phase_d_effect_ledger;

  -- NO NEGATIVE MAY EXECUTE THE STEP.`;
const NEW_SETUP = `  select count(*) into v_e0 from public.phase_d_effect_ledger;

  -- The two base objects fn_phase_d_handler_execute merges the caller's evidence over, built here
  -- exactly as it builds them so the pure test below predicts the handler and not a hypothetical.
  select jsonb_build_object('step_id', sr.step_id, 'run_id', sr.run_id, 'step_run_id', v_srid,
                            'actor_role_id', v_actor,
                            'reviewer_role_id', nullif(b.independent_reviewer_role_id,'')),
         jsonb_build_object('accountable_role_id', sr.accountable_role_id,
                            'reviewer_role_id', nullif(b.independent_reviewer_role_id,''),
                            'actor_role_id', v_actor, 'step_id', sr.step_id,
                            'workflow_id', b.workflow_id, 'run_id', sr.run_id,
                            'founder_gate', b.founder_gate, 'execution_context', 'production')
    into v_gbase, v_rbase
    from public.phase_c_workflow_step_run sr
    join public.phase_d_handler_binding b on b.step_id = sr.step_id
   where sr.step_run_id = v_srid;

  -- NO NEGATIVE MAY EXECUTE THE STEP.`;
if (!s.includes(OLD_SETUP)) throw new Error('setup anchor missing');
s = s.split(OLD_SETUP).join(NEW_SETUP);

// candidate list: exclude every key the handler's own base supplies
s = s.split(`     where k <> 'step_id' and v_ctx ? k order by k
  loop
    if exists (`)
     .join(`     where v_ctx ? k and not (v_gbase ? k) and not (v_rbase ? k) order by k
  loop
    if exists (`);

// the pure test, against the same base the handler uses
s = s.split(`         and coalesce((select ge.passed from public.fn_phase_d_gate_evaluate(gc.gate_id, v_ctx) ge), false)
         and not coalesce((select ge2.passed from public.fn_phase_d_gate_evaluate(gc.gate_id, v_ctx - v_cand) ge2), false))`)
     .join(`         and coalesce((select ge.passed from public.fn_phase_d_gate_evaluate(gc.gate_id, v_gbase || v_ctx) ge), false)
         and not coalesce((select ge2.passed from public.fn_phase_d_gate_evaluate(gc.gate_id, v_gbase || (v_ctx - v_cand)) ge2), false))`);
s = s.split(`         and coalesce((select rc.ok from public.fn_phase_d_rule_check(re.rule_id, v_ctx) rc), false)
         and not coalesce((select rc2.ok from public.fn_phase_d_rule_check(re.rule_id, v_ctx - v_cand) rc2), false))`)
     .join(`         and coalesce((select rc.ok from public.fn_phase_d_rule_check(re.rule_id, v_rbase || v_ctx) rc), false)
         and not coalesce((select rc2.ok from public.fn_phase_d_rule_check(re.rule_id, v_rbase || (v_ctx - v_cand)) rc2), false))`);

writeFileSync(f, s);
console.log('patched');
