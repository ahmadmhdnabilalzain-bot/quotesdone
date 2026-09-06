import { sql } from '../phase_c/lib/db.mjs';
const q = `do $emit$
declare v_fx jsonb; v jsonb; v_out text := ''; v_cands jsonb; v_sr bigint; v_cx jsonb;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build','label','ctx10'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','ctx10','execution_context','test'));
  v_out := v_out || 'ctx_after_factory=' || coalesce(public.fn_phase_d_fixture_context()::text,'NULL') || ' runs_live=' || (select count(*) from public.phase_c_workflow_run where opened_at > now() - interval '5 minutes') || chr(10);
  v_out := v_out || 'trigger_runs=' || coalesce((select string_agg(workflow_id || ':' || left(business_object_id,30) || ':' || state, ' ') from public.phase_c_workflow_run where opened_at > now() - interval '5 minutes'),'') || chr(10);
  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands from public.phase_b_workflow_step s where coalesce(btrim(s.independent_reviewer_role_id),'') <> '';
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','W06','label','ctx10','execution_context','production','reviewer_role_id','risk_and_governance_manager','reviewer_candidates',v_cands));
  v_out := v_out || 'ctx_after_drive=' || coalesce(public.fn_phase_d_fixture_context()::text,'NULL') || ' exec=' || (v->>'dispatches_executed') || '/' || (v->>'dispatches_seen') || ' dup=' || coalesce(v->>'premature_arrival_run','?') || chr(10);
  select step_run_id into v_sr from public.phase_c_workflow_step_run where run_id = (v->>'run_id')::bigint order by step_run_id limit 1;
  v_cx := public.fn_phase_d_step_context(v_sr);
  v_out := v_out || 'now ctx inquiry_id=' || coalesce(v_cx->'context'->>'inquiry_id','NULL') || ' unresolved=' || coalesce((v_cx->'unresolved')::text,'?') || chr(10);
  v_out := v_out || 'first dispatch unresolved=' || coalesce((select d.unresolved_keys::text from public.phase_d_dispatch d where d.step_run_id = v_sr order by d.dispatch_id limit 1),'(none)') || chr(10);
  v_out := v_out || 'scn inquiry=' || coalesce((select sc.canonical_ref->>'canonical_identity' from public.phase_d_scenario_record sc where sc.fixture_run_id = public.fn_phase_d_fixture_context() and sc.object_id='inquiry' limit 1),'NULL') || chr(10);
  raise exception 'CX<<%>>', left(v_out, 1900);
end $emit$;`;
try { await sql(q); console.log('no raise'); } catch (e) { const m = String(e.message); const a = m.indexOf('CX<<'); console.log(a < 0 ? m.slice(0, 1500) : m.slice(a + 4, m.lastIndexOf('>>')).replace(/\n/g, '\n').replace(/\\"/g,'"')); }
