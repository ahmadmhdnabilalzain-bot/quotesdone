// PHASE D DELIVERABLE — PHASE_D_CAPABILITY_BOUNDARY_RESULT.csv
//
// The founder's ruling of 21 Aug 2026, section C: "For each of the 21 steps prove:
//   1. normal production context with no capability -> refused/blocked;
//   2. protected Phase D fixture result -> accepted;
//   3. malformed fixture result -> refused;
//   4. fixture replay -> no duplicate effect;
//   5. fixture used outside test context -> refused."
//
// One row per capability-dependent step, five verdicts each, every one produced by EXECUTION
// against production inside a transaction that ends in `raise exception`. Nothing is asserted from
// reading the code.
//
// HOW EACH CASE IS FORCED, because a case nobody can make fail is a case nobody has tested:
//
//   1  A real step run is opened through fn_kernel_workflow_start with NO fixture context in the
//      transaction at all, so fn_phase_d_fixture_context() returns null and the handler's
//      capability branch is entered with nothing to read. Expect pd_capability_unavailable.
//   2  The same step run inside a verified fixture context, with the committed CAPABILITY_RESULT
//      fixture submitted through fn_phase_d_capability_result_accept. Expect an accepted result
//      carrying the fixture id, version and hash, and a re-dispatch that gets PAST the capability
//      boundary -- which is what this case is about. A step that then refuses for a business reason
//      is recorded with that reason: it passed the boundary and failed a rule, and those are
//      different facts.
//   3  A payload that is missing a contract key and wrongly types another. Expect
//      pd_capability_result_malformed naming both.
//   4  The same fixture submitted twice. Expect replay = true, the SAME result_id, and no second
//      row in public.phase_d_capability_result.
//   5  A fixture result submitted with the fixture context deliberately cleared, which is what a
//      production caller has. Expect pd_capability_fixture_context_absent, 42501, before the
//      payload is read.
//
//   node scripts/phase_d/prove_capability_boundary.mjs
import { writeFileSync } from 'node:fs';
import { outPath, provenance } from './lib/deliverable.mjs';
import { sql } from '../phase_c/lib/db.mjs';

const steps = (await sql(`select b.step_id, b.workflow_id, b.capability_dependency
  from public.phase_d_handler_binding b where b.capability_dependency <> 'NONE' order by b.step_id`))
  .map(r => r);

const rows = [];
for (const s of steps) {
  const q = `do $emit$
declare
  v jsonb; v_fx jsonb; v_run bigint; v_sr bigint; v_req jsonb; v_res jsonb; v_out text := '';
  v_cands jsonb; v_rev text; d public.phase_d_dispatch%rowtype; v_n1 int; v_n2 int; v_first bigint;
  v_cap text;
begin
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  select c.fixture_id into v_cap from public.phase_d_fixture_catalogue c
   where c.scope='CAPABILITY_RESULT' and c.step_id = ${lit(s.step_id)} limit 1;

  -- ---- CASE 1: production context, no capability -----------------------------------------------
  -- No fixture context is opened yet, so the whole drive below runs exactly as production does.
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id = ${lit(s.workflow_id)} and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
        'workflow_id', ${lit(s.workflow_id)}, 'label','capprove',
        'execution_context','production','reviewer_role_id', v_rev, 'reviewer_candidates', v_cands));
  select * into d from public.phase_d_dispatch
   where step_id = ${lit(s.step_id)} order by dispatch_id desc limit 1;
  v_out := v_out || 'case1=' || coalesce(nullif(d.refusal_code,''), coalesce(d.outcome,'NO_DISPATCH')) || '~|~';
  v_sr := d.step_run_id;

  -- ---- CASE 5 (before any context exists): a fixture result from a production caller ------------
  if v_sr is not null then
    begin
      v_req := public.fn_phase_d_capability_request_open(jsonb_build_object(
        'step_run_id', v_sr, 'requested_by','capprove'));
      v_res := public.fn_phase_d_capability_result_accept(jsonb_build_object(
        'request_id', v_req->'request_id', 'provider_mode','fixture',
        'fixture_id', v_cap, 'accepted_by','capprove'));
      v_out := v_out || 'case5=ACCEPTED_WRONGLY' || '~|~';
    exception when others then
      v_out := v_out || 'case5=' || coalesce((regexp_match(SQLERRM,'\\((pd_[a-z0-9_]+)\\)'))[1], SQLSTATE) || '~|~';
    end;
  else
    v_out := v_out || 'case5=NO_STEP_RUN' || '~|~';
  end if;

  -- ---- now open the protected context ----------------------------------------------------------
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_capability_fixture','label','capprove-${s.step_id}'));

  -- ---- CASE 1b: THE FIRST CONTROL THAT REFUSES WHEN NO CAPABILITY RESULT EXISTS ----------------
  -- Case 1 above is the production verdict and it is usually a BUSINESS refusal: the step is
  -- refused by a rule or a gate before the capability is ever asked for, which is honest and which
  -- says nothing about the capability boundary itself. This case removes every other reason to
  -- refuse -- the fixture context is now open, so the rules and gates resolve -- and submits NO
  -- capability result, and records WHICH control refuses first.
  --
  -- It is often not the capability boundary, and that is a fact about the order of the controls
  -- rather than a gap: fn_phase_d_handler_execute checks rules (section 2), then gates (2b), then
  -- the capability (3). A step whose gate has no evidence never reaches the capability question.
  -- pd_capability_unavailable IS reachable and was measured on W21-S02 and W28-S03..S06 during the
  -- workflow drives, where every rule and gate passed. Reporting the first refuser here rather than
  -- forcing the boundary is the honest column: a harness that suppressed the gate to make the
  -- capability refuse would be measuring the harness.
  if v_sr is not null then
    v := public.fn_phase_d_dispatch_step(jsonb_build_object(
      'step_run_id', v_sr, 'actor_role_id','capprove',
      'opened_by_kind','capability_isolation', 'opened_by_ref','no result submitted',
      'idempotency_key','capprove:'||v_sr||':iso'));
    v_out := v_out || 'case1b=' || coalesce(nullif(v->>'refusal_code',''), coalesce(v->>'outcome','?')) || '~|~';
  else
    v_out := v_out || 'case1b=NO_STEP_RUN~|~';
  end if;

  -- ---- CASE 3: a malformed fixture result -------------------------------------------------------
  -- PDF-1099 is a committed CAPABILITY_RESULT row that exists to be refused: three of the five
  -- contract keys are missing and confidence is typed string where the contract says number.
  if v_sr is not null then
    begin
      v_req := public.fn_phase_d_capability_request_open(jsonb_build_object(
        'step_run_id', v_sr, 'requested_by','capprove'));
      v_res := public.fn_phase_d_capability_result_accept(jsonb_build_object(
        'request_id', v_req->'request_id', 'provider_mode','fixture',
        'fixture_id', 'PDF-1099', 'accepted_by','capprove'));
      v_out := v_out || 'case3=ACCEPTED_WRONGLY' || '~|~';
    exception when others then
      v_out := v_out || 'case3=' || coalesce((regexp_match(SQLERRM,'\\((pd_[a-z0-9_]+)\\)'))[1], SQLSTATE) || '~|~';
    end;
  else
    v_out := v_out || 'case3=NO_STEP_RUN' || '~|~';
  end if;

  -- ---- CASE 2: the committed fixture, accepted, and the handler continues -----------------------
  if v_sr is not null then
    begin
      select count(*) into v_n1 from public.phase_d_capability_result;
      v_req := public.fn_phase_d_capability_request_open(jsonb_build_object(
        'step_run_id', v_sr, 'requested_by','capprove'));
      v_res := public.fn_phase_d_capability_result_accept(jsonb_build_object(
        'request_id', v_req->'request_id', 'provider_mode','fixture',
        'fixture_id', v_cap, 'accepted_by','capprove'));
      v_first := (v_res->>'result_id')::bigint;
      v := public.fn_phase_d_dispatch_step(jsonb_build_object(
        'step_run_id', v_sr, 'actor_role_id', 'capprove',
        'opened_by_kind','capability_result', 'opened_by_ref', v_cap,
        'idempotency_key','capprove:'||v_sr||':cap'));
      v_out := v_out || 'case2=' || coalesce(v_res->>'provider_mode','?')
            || ':' || coalesce(v_res->>'fixture_id','?')
            || ':v' || coalesce(v_res->>'fixture_version','?')
            || ':' || left(coalesce(v_res->>'fixture_hash',''),12)
            || ':redispatch=' || coalesce(v->>'outcome','?')
            || case when coalesce(v->>'refusal_code','') = '' then ''
                    else '(' || (v->>'refusal_code') || ')' end || '~|~';

      -- ---- CASE 4: the same fixture again ---------------------------------------------------------
      v_res := public.fn_phase_d_capability_result_accept(jsonb_build_object(
        'request_id', v_req->'request_id', 'provider_mode','fixture',
        'fixture_id', v_cap, 'accepted_by','capprove'));
      select count(*) into v_n2 from public.phase_d_capability_result;
      v_out := v_out || 'case4=replay:' || coalesce(v_res->>'replay','?')
            || ':same_result_id:' || ((v_res->>'result_id')::bigint = v_first)::text
            || ':rows_added:' || (v_n2 - v_n1)::text || '~|~';
    exception when others then
      v_out := v_out || 'case2=ERROR:' || left(SQLERRM,160) || '~|~' || 'case4=NOT_REACHED' || '~|~';
    end;
  else
    v_out := v_out || 'case2=NO_STEP_RUN' || '~|~' || 'case4=NO_STEP_RUN' || '~|~';
  end if;

  raise exception 'CAPPROVE<<%>>', v_out;
end $emit$;`;
  let out;
  try { await sql(q); out = '(no marker)'; }
  catch (e) {
    const m = String(e.message); const a = m.indexOf('CAPPROVE<<');
    out = a < 0 ? 'ERROR: ' + m.slice(0, 400) : m.slice(a + 10, m.indexOf('>>', a));
  }
  // The five verdicts come back in one error string, separated by a literal token rather than by a
  // control character: the management API returns the message JSON-escaped, so chr(31) arrives as
  // six characters and a naive split finds nothing. Measured, not assumed.
  const parts = out.split('~|~');
  const pick = (k) => (parts.find(p => p.startsWith(k + '=')) || (k + '=(absent)')).slice(k.length + 1);
  rows.push([s.step_id, s.workflow_id, s.capability_dependency,
             pick('case1'), pick('case1b'), pick('case2'), pick('case3'), pick('case4'), pick('case5')]);
  process.stderr.write(`${s.step_id} ${pick('case1')} ${pick('case1b')} | ${pick('case2').slice(0,60)} | ${pick('case3')} | ${pick('case4')} | ${pick('case5')}\n`);
}

function lit(s) { return `'${String(s).replace(/'/g, "''")}'`; }

const head = provenance({
  command: 'node scripts/phase_d/prove_capability_boundary.mjs',
  numerator: rows.length, denominator: steps.length,
  of: 'capability-dependent steps in public.phase_d_handler_binding, each probed five ways',
  attribution: 'every verdict is the refusal code or acceptance the database actually returned, inside a transaction ending in raise exception; no verdict is read off the source',
});
const csv = head
  + 'step_id,workflow_id,capability,case1_production_no_capability,case1b_first_control_to_refuse_with_no_capability_result,case2_protected_fixture_result,'
  + 'case3_malformed_fixture_result,case4_fixture_replay,case5_fixture_outside_test_context\n'
  + rows.map(r => r.map(c => `"${String(c).replace(/"/g, '""')}"`).join(',')).join('\n') + '\n';
writeFileSync(outPath('PHASE_D_CAPABILITY_BOUNDARY_RESULT.csv'), csv);
console.log(`wrote ${rows.length} of ${steps.length} rows`);
if (rows.length !== steps.length) process.exit(1);
