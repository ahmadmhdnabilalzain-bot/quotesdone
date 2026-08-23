// PHASE D — THE 1,799 STEP-CONTRACT CASES, DECIDED AGAINST A LIVE STEP RUN.
//
//   node scripts/phase_d/run_step_cases_live.mjs [--only=W01,W02] [--jobs=3]
//
// The committed matrix passed 1,799 of 1,799 and its own `decided_at` column said where each case
// was settled: 771 at `step_contract`, 771 at `executor_boundary`, 257 at `structural_constraint`,
// and NONE against a live step run. A contract that refuses a hand-built payload is a real
// assertion about the contract; it is not a claim that the HANDLER refuses that payload when the
// kernel hands it one. The session brief of 23 Aug 2026 says exactly that, and adds: a step held
// open by `pd_handler_held_for_branch_probe` proves the KERNEL's fail edge and nothing about the
// handler's.
//
// This driver settles six of the seven kinds against a real step run of a real drive, in one
// aborted transaction per step. For each step:
//
//   1. the workflow is driven with app.phase_d_hold_step set to this step, so the step run is OPEN
//      and un-dispatched -- the handler declines and says so;
//   2. THE HOLD IS THEN RELEASED, inside the same transaction, so every call below reaches the real
//      handler rather than the probe's own refusal;
//   3. the five negative cases run against that live step run, each varying ONE thing from the
//      positive and each asserting that the effect ledger did not move;
//   4. the positive runs LAST, through fn_phase_d_dispatch_step -- the kernel's own door, which
//      supplies the context, the gate evidence, the business key and the owner exactly as it does
//      in production. Nothing here re-implements it;
//   5. the duplicate runs after the positive: the same door again, and the assertion is the ledger
//      row count.
//
// DISCRIMINATION IS THE POINT, not the refusal. Every negative is paired with a control that
// differs in exactly one respect, and a case passes only when the two answers DIFFER. A negative
// that refuses for the same reason as its control has discriminated nothing -- that is the defect
// this estate has recorded as NOT_DISCRIMINATED twice, and scoring it as a pass would repeat it.
//
// WHAT IS NOT DRIVEN, said out loud. `malformed_output` is decided at the kernel door
// (fn_kernel_step_complete with an empty output, refusal k3_output_empty) rather than inside the
// handler: the handler BUILDS its own output from the frozen registry and a caller has no lever on
// it, so there is no input that makes a handler produce an output its own contract rejects. The row
// records decided_at = 'kernel_boundary' and says so.
import { sql } from '../phase_c/lib/db.mjs';

const arg = (k, d) => (process.argv.find(a => a.startsWith(`--${k}=`)) || `--${k}=${d}`).split('=').slice(1).join('=');
const ONLY = arg('only', '').split(',').filter(Boolean);
const JOBS = Math.max(1, Number(arg('jobs', 3)));

const STEPS = await sql(`select s.step_id, s.workflow_id, s.step_no
  from public.phase_b_workflow_step s order by s.workflow_id, s.step_no`);
const WORK = STEPS.filter(s => !ONLY.length || ONLY.includes(s.workflow_id));

const CASE_ORDER = ['positive', 'missing_input', 'wrong_actor', 'invalid_state',
                    'duplicate', 'failed_rule_or_gate', 'malformed_output'];

// A transport failure is not a measurement.
async function emit(q, marker) {
  for (let attempt = 1; ; attempt++) {
    try { await sql(q); return 'ERROR:the probe did not raise its marker'; }
    catch (e) {
      const m = String(e.message); const a = m.indexOf(marker + '<<');
      if (a >= 0) return m.slice(a + marker.length + 2, m.indexOf('>>', a));
      if (/fetch failed|ECONNRESET|ETIMEDOUT|socket hang up|HTTP 429|HTTP 5\d\d/i.test(m) && attempt < 4) {
        await new Promise(r => setTimeout(r, 3000 * attempt)); continue;
      }
      return 'ERROR:' + m.slice(0, 300).replace(/[\s|~]+/g, ' ');
    }
  }
}

const CODE = "coalesce((regexp_match(SQLERRM,'[(]((pd|k[0-9]+|br[0-9]+|gate[0-9]+)_[a-z0-9_]+)[)]'))[1], 'other:' || left(regexp_replace(SQLERRM,'[|~<>]',' ','g'),60))";

function query(step, wf) {
  return `do $case$
declare
  v jsonb; v_fx jsonb; v_cands jsonb; v_srid bigint; v_actor text; v_out text := '';
  v_full jsonb; v_ctx jsonb; v_k text; ins public.phase_d_handler_schema%rowtype;
  v_e0 bigint; v_e1 bigint; v_e bigint; v_neg text; v_gk text; v_hit text; v_cand text;
  v_gbase jsonb; v_rbase jsonb; v_ref_key text; v_boid text;
begin
  perform set_config('app.phase_d_hold_step','${step}', true);
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','case-${step.toLowerCase()}'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','case-${step.toLowerCase()}','execution_context','test',
    'for_workflow', '${wf}'));
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id='${wf}')
   limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'') <> ''
    then (select primary_object from public.phase_b_workflow where workflow_id='${wf}')
         || ':' || (v_fx->'parent_refs'->>v_ref_key)
    else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','${wf}','label','case-${step.toLowerCase()}','execution_context','production',
    'reviewer_role_id', coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
      where x.workflow_id='${wf}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
      order by x.step_id limit 1),'risk_and_governance_manager'),
    'reviewer_candidates', v_cands, 'hold_at_step_id','${step}')
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id', v_boid) end);
  v_srid := nullif(v->>'held_step_run_id','')::bigint;
  -- THE HOLD IS RELEASED HERE. Everything below reaches the real handler.
  perform set_config('app.phase_d_hold_step','', true);
  if v_srid is null then
    raise exception 'CASE<<NO_OPEN_STEP|%>>', coalesce(v->'stopped'->>'refused_with','-');
  end if;

  select accountable_role_id into v_actor from public.phase_c_workflow_step_run where step_run_id = v_srid;
  v_full := (public.fn_phase_d_step_inputs(v_srid))->'inputs';
  v_ctx  := (public.fn_phase_d_step_context(v_srid))->'context';
  select * into ins from public.phase_d_handler_schema
   where step_id = '${step}' and schema_kind = 'input';
  select count(*) into v_e0 from public.phase_d_effect_ledger;

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

  -- NO NEGATIVE MAY EXECUTE THE STEP. Every negative below is a call that must be refused, and each
  -- one's effect delta is measured on its own -- not once around the block -- so a case that wrote
  -- cannot hide behind a case that did not. The CONTROL for every negative is the positive dispatch
  -- at the end of this transaction: the same step run, through the kernel's own door, with nothing
  -- varied. A negative whose refusal code is the positive's outcome has discriminated nothing.

  -- ---- missing_input: the real handler, the real step run, one declared key removed -----------
  v_k := coalesce(ins.required_keys[1], '(none)');
  if v_k = '(none)' then
    v_out := v_out || 'missing_input|no_declared_input|false|0|the frozen step declares no required input, so this case has no subject~';
  else
    begin
      perform public.fn_phase_d_handler_execute(jsonb_build_object(
        'step_run_id', v_srid, 'actor_role_id', v_actor, 'idempotency_key','case-mi-${step}',
        'inputs', v_full - v_k, 'context', v_ctx, 'gate_evidence', v_ctx,
        'execution_context','production'));
      v_neg := 'ACCEPTED';
    exception when others then v_neg := ${CODE}; end;
    select count(*) into v_e1 from public.phase_d_effect_ledger;
    v_out := v_out || 'missing_input|' || v_neg || '|'
          || case when v_neg = 'pd_input_schema_invalid' then 'true' else 'false' end
          || '|' || (v_e1 - v_e0)::text
          || '|removing the declared input key ' || v_k || ' gives ' || v_neg || '~';
  end if;

  -- ---- wrong_actor: the kernel's own dispatch door, one identity nobody models ----------------
  -- fn_phase_d_dispatch_step RECORDS a refusal and returns; it does not raise. Reading the absence
  -- of an exception as acceptance is the '201 with no row' defect one layer up, so the verdict is
  -- read off the dispatch row the door itself wrote.
  begin
    perform public.fn_phase_d_dispatch_step(jsonb_build_object(
      'step_run_id', v_srid, 'actor_role_id','zz_not_a_canonical_role_${step}',
      'opened_by_kind','step_case_probe','opened_by_ref','wrong_actor',
      'idempotency_key','case-wa-${step}'));
    select coalesce(nullif(d.refusal_code,''), d.outcome) into v_neg
      from public.phase_d_dispatch d where d.step_run_id = v_srid
       and d.opened_by_ref = 'wrong_actor' order by d.dispatch_id desc limit 1;
    v_neg := coalesce(v_neg, 'NO_DISPATCH_ROW');
  exception when others then v_neg := ${CODE}; end;
  select count(*) into v_e from public.phase_d_effect_ledger;
  v_out := v_out || 'wrong_actor|' || v_neg || '|'
        || case when v_neg not in ('EXECUTED','ACCEPTED','NO_DISPATCH_ROW') then 'true' else 'false' end
        || '|' || (v_e - v_e1)::text
        || '|an identity nobody models was refused with ' || v_neg || '~';
  v_e1 := v_e;

  -- ---- invalid_state: the real handler against a step run that does not exist ------------------
  begin
    perform public.fn_phase_d_handler_execute(jsonb_build_object(
      'step_run_id', -1, 'actor_role_id', v_actor, 'idempotency_key','case-is-${step}',
      'inputs', v_full, 'execution_context','production'));
    v_neg := 'ACCEPTED';
  exception when others then v_neg := ${CODE}; end;
  select count(*) into v_e from public.phase_d_effect_ledger;
  v_out := v_out || 'invalid_state|' || v_neg || '|'
        || case when v_neg = 'pd_step_state_invalid' then 'true' else 'false' end
        || '|' || (v_e - v_e1)::text
        || '|step run -1 gives ' || v_neg || '~';
  v_e1 := v_e;

  -- ---- failed_rule_or_gate: the real handler with one key of the live evidence removed ---------
  -- EVERY candidate is tried, not the alphabetically first. A key a rule declares but no predicate
  -- reads is not load-bearing, and removing it proves nothing; the loop stops at the first key whose
  -- removal actually makes a rule or gate of this step refuse. Where no key is load-bearing the row
  -- says that rather than scoring a refusal it did not obtain.
  -- THE LOAD-BEARING KEY IS FOUND BY PURE EVALUATION FIRST. Invoking the handler with a key that is
  -- NOT load-bearing does not refuse -- it EXECUTES the step, which both spends the case and
  -- contaminates every measurement after it. So each candidate is first tested against the step's
  -- APPLICABLE gates and rules, which are pure functions of the evidence and write nothing, and only
  -- the key that actually flips one of them is then removed from a real handler call.
  v_hit := null; v_gk := null;
  for v_cand in
    select k from (
      select unnest(gc.evidence_keys) k from public.phase_d_gate_contract gc
       where gc.gate_id = any (coalesce((select b2.gate_ids from public.phase_d_handler_binding b2
                                          where b2.step_id = '${step}'),'{}'))
         and (select ga.applies from public.fn_phase_d_gate_applies(gc.gate_id, '${step}') ga)
      union
      select unnest(re.required_context) k from public.phase_d_rule_enforcement re
       where re.rule_id = any (coalesce((select b3.rule_ids from public.phase_d_handler_binding b3
                                          where b3.step_id = '${step}'),'{}'))
         and (select ra.applies from public.fn_phase_d_rule_applies(re.rule_id, '${step}') ra)) q
     where v_ctx ? k and not (v_gbase ? k) and not (v_rbase ? k) order by k
  loop
    if exists (
      select 1 from public.phase_d_gate_contract gc
       where gc.gate_id = any (coalesce((select b4.gate_ids from public.phase_d_handler_binding b4
                                          where b4.step_id = '${step}'),'{}'))
         and (select ga.applies from public.fn_phase_d_gate_applies(gc.gate_id, '${step}') ga)
         and coalesce((select ge.passed from public.fn_phase_d_gate_evaluate(gc.gate_id, v_gbase || v_ctx) ge), false)
         and not coalesce((select ge2.passed from public.fn_phase_d_gate_evaluate(gc.gate_id, v_gbase || (v_ctx - v_cand)) ge2), false))
       or exists (
      select 1 from public.phase_d_rule_enforcement re
       where re.rule_id = any (coalesce((select b5.rule_ids from public.phase_d_handler_binding b5
                                          where b5.step_id = '${step}'),'{}'))
         and (select ra.applies from public.fn_phase_d_rule_applies(re.rule_id, '${step}') ra)
         and coalesce((select rc.ok from public.fn_phase_d_rule_check(re.rule_id, v_rbase || v_ctx) rc), false)
         and not coalesce((select rc2.ok from public.fn_phase_d_rule_check(re.rule_id, v_rbase || (v_ctx - v_cand)) rc2), false))
    then
      v_gk := v_cand; exit;
    end if;
  end loop;

  if v_gk is null then
    v_out := v_out || 'failed_rule_or_gate|no_load_bearing_evidence|false|0'
          || '|every applicable gate and rule of this step answers the same with and without each '
          || 'key the live context resolved, so removing one proves nothing~';
  else
    begin
      perform public.fn_phase_d_handler_execute(jsonb_build_object(
        'step_run_id', v_srid, 'actor_role_id', v_actor,
        'idempotency_key','case-fg-${step}',
        'inputs', v_full, 'context', v_ctx - v_gk, 'gate_evidence', v_ctx - v_gk,
        'execution_context','production'));
      v_hit := 'ACCEPTED';
    exception when others then v_hit := ${CODE}; end;
    select count(*) into v_e from public.phase_d_effect_ledger;
    v_out := v_out || 'failed_rule_or_gate|' || v_hit || '|'
          || case when v_hit in ('pd_rule_refused','pd_gate_refused','pd_evidence_absent')
                  then 'true' else 'false' end
          || '|' || (v_e - v_e1)::text
          || '|removing ' || v_gk || ' from the live evidence flips an applicable predicate, and the '
          || 'real handler then answers ' || v_hit || '~';
  end if;
  select count(*) into v_e from public.phase_d_effect_ledger;
  v_e1 := v_e;

  -- ---- malformed_output: the kernel's own door, an empty output --------------------------------
  begin
    perform public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', v_srid, 'actor_role_id', v_actor, 'outcome','pass',
      'idempotency_key','case-mo-${step}', 'inputs', jsonb_build_object('mode','malformed output'),
      'output', '{}'::jsonb,
      'evidence_refs', jsonb_build_array(jsonb_build_object('mode','malformed output'))));
    v_neg := 'ACCEPTED';
  exception when others then v_neg := ${CODE}; end;
  select count(*) into v_e from public.phase_d_effect_ledger;
  v_out := v_out || 'malformed_output|' || v_neg || '|'
        || case when v_neg ~ '^(k[0-9]+|pd)_' then 'true' else 'false' end
        || '|' || (v_e - v_e1)::text
        || '|an empty output at the frozen kernel door gives ' || v_neg || '~';
  v_e1 := v_e;

  raise exception 'CASE<<%>>', v_out;
end $case$;`;
}

// THE POSITIVE AND ITS REPLAY, IN THEIR OWN TRANSACTION AND THEIR OWN DRIVE.
function queryPositive(step, wf) {
  return `do $pos$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_srid bigint; v_actor text; v_out text := '';
        v_e0 bigint; v_e bigint; v_neg text; v_ref_key text; v_boid text;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','pos-${step.toLowerCase()}'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','pos-${step.toLowerCase()}','execution_context','test',
    'for_workflow', '${wf}'));
  select count(*) into v_e0 from public.phase_d_effect_ledger;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id='${wf}')
   limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'') <> ''
    then (select primary_object from public.phase_b_workflow where workflow_id='${wf}')
         || ':' || (v_fx->'parent_refs'->>v_ref_key)
    else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','${wf}','label','pos-${step.toLowerCase()}','execution_context','production',
    'reviewer_role_id', coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
      where x.workflow_id='${wf}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
      order by x.step_id limit 1),'risk_and_governance_manager'),
    'reviewer_candidates', v_cands)
    || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id', v_boid) end);
  select sr.step_run_id, sr.accountable_role_id into v_srid, v_actor
    from public.phase_c_workflow_step_run sr
   where sr.run_id = (v->>'run_id')::bigint and sr.step_id = '${step}'
   order by sr.step_run_id limit 1;
  if v_srid is null then
    raise exception 'CASE<<NO_OPEN_STEP|the drive never opened this step>>';
  end if;
  select coalesce(nullif(d.refusal_code,''), d.outcome) into v_neg
    from public.phase_d_dispatch d where d.step_run_id = v_srid order by d.dispatch_id desc limit 1;
  v_neg := coalesce(v_neg, 'NO_DISPATCH_ROW');
  select count(*) into v_e from public.phase_d_effect_ledger
   where step_run_id = v_srid;
  v_out := 'positive|' || v_neg || '|'
        || case when v_neg = 'EXECUTED' and v_e = 1 then 'true' else 'false' end
        || '|0|the canonical drive answered ' || v_neg || ' and the ledger holds '
        || v_e::text || ' effect(s) for this step run~';

  -- THE REPLAY: the same step run, the same door, the same idempotency key the kernel used.
  begin
    perform public.fn_phase_d_dispatch_step(jsonb_build_object(
      'step_run_id', v_srid, 'actor_role_id', v_actor,
      'opened_by_kind','step_case_probe','opened_by_ref','duplicate',
      'idempotency_key','case-dup-${step}'));
    v_neg := 'REPLAYED';
  exception when others then v_neg := ${CODE}; end;
  v_out := v_out || 'duplicate|' || v_neg || '|'
        || case when (select count(*) from public.phase_d_effect_ledger where step_run_id = v_srid) <= 1
                then 'true' else 'false' end
        || '|0|a replay of the same step run left '
        || (select count(*) from public.phase_d_effect_ledger where step_run_id = v_srid)::text
        || ' effect(s) on it~';
  raise exception 'CASE<<%>>', v_out;
end $pos$;`;
}

const results = [];
let done = 0;
async function worker(queue) {
  for (;;) {
    const s = queue.shift();
    if (!s) return;
    const neg = await emit(query(s.step_id, s.workflow_id), 'CASE');
    const pos = await emit(queryPositive(s.step_id, s.workflow_id), 'CASE');
    results.push([s.step_id, (neg.startsWith('ERROR:') || neg.startsWith('NO_OPEN_STEP') ? neg : neg)
                             + (pos.startsWith('ERROR:') || pos.startsWith('NO_OPEN_STEP') ? '' : pos)]);
    done++;
    if (done % 10 === 0) process.stderr.write(`-- ${done}/${WORK.length}\n`);
  }
}
const queue = [...WORK];
await Promise.all(Array.from({ length: JOBS }, () => worker(queue)));

// ---- fold the raw lines into rows -------------------------------------------------------------
const DECIDED = {
  positive: 'live_step_run', missing_input: 'live_step_run', wrong_actor: 'live_step_run',
  invalid_state: 'live_step_run', duplicate: 'live_step_run',
  failed_rule_or_gate: 'live_step_run', malformed_output: 'kernel_boundary',
};
const EXPECT = {
  positive: 'the kernel dispatch executes this step run and the ledger holds exactly one effect for it',
  missing_input: 'the real handler refuses a payload missing a declared input key, with pd_input_schema_invalid, and writes nothing',
  wrong_actor: 'the kernel dispatch records a refusal for an identity nobody models, and writes nothing',
  invalid_state: 'the real handler refuses a step run that does not exist, with pd_step_state_invalid, and writes nothing',
  duplicate: 'a second dispatch of the same step run produces no second effect',
  failed_rule_or_gate: 'the real handler refuses when a load-bearing key of the live evidence is removed, and writes nothing',
  malformed_output: 'the frozen kernel door refuses an empty output with a stable code, and writes nothing',
};
const NEGATIVE = new Set(['missing_input', 'wrong_actor', 'invalid_state',
                          'failed_rule_or_gate', 'malformed_output']);

const rows = [];
for (const [step, raw] of results) {
  const got = new Map();
  const broken = raw.startsWith('NO_OPEN_STEP') || raw.startsWith('ERROR:');
  if (!broken) for (const seg of raw.split('~')) {
    if (!seg) continue;
    const p = seg.split('|');
    if (p.length >= 5) got.set(p[0], p);
  }
  for (const kind of CASE_ORDER) {
    if (broken) {
      rows.push([step, kind, DECIDED[kind], EXPECT[kind], false, 'probe_did_not_reach_the_step',
                 raw.slice(0, 300)]);
      continue;
    }
    const p = got.get(kind);
    if (!p) { rows.push([step, kind, DECIDED[kind], EXPECT[kind], false, 'case_not_reported', raw.slice(0, 200)]); continue; }
    const [, code, passedFlag, delta, detail] = p;
    // A NEGATIVE THAT WROTE IS NOT A PASS, whatever it refused with. The delta is this case's own,
    // measured immediately before and after it, so one case cannot hide behind another.
    const wrote = NEGATIVE.has(kind) && delta !== '0';
    const ok = passedFlag === 'true' && !wrote;
    rows.push([step, kind, DECIDED[kind], EXPECT[kind], ok, code,
               detail + (wrote ? ` [this negative added ${delta} effect(s) and cannot pass]` : '')]);
  }
}

// ---- write them into the deliverable table ----------------------------------------------------
const lit = s => `'${String(s).replace(/'/g, "''")}'`;
for (let i = 0; i < rows.length; i += 200) {
  const chunk = rows.slice(i, i + 200);
  await sql(`insert into public.phase_d_step_case_result
      (step_id, case_kind, decided_at, expectation, passed, refused_with, detail)
    values ${chunk.map(r => `(${lit(r[0])},${lit(r[1])},${lit(r[2])},${lit(r[3])},${r[4]},${lit(r[5])},${lit(String(r[6]).slice(0, 400))})`).join(',')}
    on conflict (step_id, case_kind) do update
      set decided_at = excluded.decided_at, expectation = excluded.expectation,
          passed = excluded.passed, refused_with = excluded.refused_with,
          detail = excluded.detail, run_at = now()`);
}

const pass = rows.filter(r => r[4]).length;
console.log(`\nsteps driven                 ${results.length}`);
console.log(`cases written                ${rows.length}`);
console.log(`cases passed                 ${pass}`);
console.log(`cases failed                 ${rows.length - pass}`);
for (const k of CASE_ORDER) {
  const sub = rows.filter(r => r[1] === k);
  console.log(`  ${k.padEnd(22)} ${sub.filter(r => r[4]).length} of ${sub.length}   (${DECIDED[k]})`);
}
if (pass !== rows.length) {
  const byCode = new Map();
  for (const r of rows.filter(x => !x[4])) byCode.set(`${r[1]}:${r[5]}`, (byCode.get(`${r[1]}:${r[5]}`) || 0) + 1);
  console.log('\nfailures by kind and refusal:');
  for (const [k, n] of [...byCode].sort((a, b) => b[1] - a[1]).slice(0, 25)) console.log(`  ${String(n).padStart(4)}  ${k}`);
  process.exitCode = 1;
}
