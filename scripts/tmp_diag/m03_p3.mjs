import { sql } from '../phase_b/lib/db.mjs';
const q = `
do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_out text := '';
  v_srid bigint; v_run bigint; v_acct text; v_task bigint; v_d jsonb; v_d2 jsonb;
  v_clo text := 'W04-S07'; v_clo_owner text; v_o jsonb; v_csrid bigint;
  A text; B text; C text; E text; F text; G text; H text; I text;
  n0 int; n1 int; h0 int; h1 int;
begin
  perform set_config('app.phase_d_hold_step','W04-S04', true);
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','m03-p3'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','m03-p3','execution_context','test','for_workflow','W04'));
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W04','label','m03-p3','execution_context','production',
    'reviewer_role_id','compliance_and_privacy_officer','reviewer_candidates',v_cands,
    'hold_at_step_id','W04-S04'));
  v_srid := nullif(v->>'held_step_run_id','')::bigint;
  v_run  := (v->>'run_id')::bigint;
  if v_srid is null then raise exception 'P3<<no hold: %>>', coalesce(v->'stopped'->>'refused_with','-'); end if;
  select accountable_role_id into v_acct from public.phase_c_workflow_step_run where step_run_id=v_srid;
  select task_id into v_task from public.phase_c_task where run_id=v_run and step_id='W04-S04' order by task_id limit 1;

  select accountable_role_id into v_clo_owner from public.phase_b_workflow_step where step_id=v_clo;
  begin
    perform set_config('app.phase_d_hold_step', v_clo, true);
    v_o := public.fn_kernel_open_step(jsonb_build_object('run_id',v_run,'step_id',v_clo,
      'owner_role_id',v_clo_owner,'source_kind','workflow_progression','source_ref','probe',
      'opened_because','probe'));
    v_csrid := (v_o->>'step_run_id')::bigint;
    perform public.fn_kernel_step_complete(jsonb_build_object('step_run_id',v_csrid,
      'actor_role_id',v_clo_owner,'outcome','pass','idempotency_key','m03p3:clo',
      'inputs',jsonb_build_object('p','x'),'output',jsonb_build_object('status','completed','output','x')));
    A := 'NOT_REFUSED opened=' || coalesce(v_csrid::text,'-');
  exception when others then A := SQLSTATE || ' ' || left(SQLERRM,300);
  end;

  begin
    perform public.fn_kernel_step_complete(jsonb_build_object('step_run_id',v_srid,
      'actor_role_id',v_acct,'outcome','pass','idempotency_key','m03p3:b',
      'inputs',jsonb_build_object('p','x'),'output',jsonb_build_object('status','completed','output','x')));
    B := 'NOT_REFUSED';
  exception when others then B := SQLSTATE || ' ' || left(SQLERRM,200);
  end;

  v_d := public.fn_kernel_review_decide(jsonb_build_object('task_id',v_task,
    'reviewer_role_id','compliance_and_privacy_officer','decision','rejected','reason','probe rejection'));
  select count(*) into n0 from public.phase_c_workflow_step_run where run_id=v_run;
  select count(*) into h0 from public.phase_c_handoff_run where run_id=v_run;
  begin
    perform public.fn_kernel_step_complete(jsonb_build_object('step_run_id',v_srid,
      'actor_role_id',v_acct,'outcome','pass','idempotency_key','m03p3:c',
      'inputs',jsonb_build_object('p','x'),'output',jsonb_build_object('status','completed','output','x')));
    C := 'NOT_REFUSED';
  exception when others then C := SQLSTATE || ' ' || left(SQLERRM,160);
  end;
  select count(*) into n1 from public.phase_c_workflow_step_run where run_id=v_run;
  select count(*) into h1 from public.phase_c_handoff_run where run_id=v_run;
  C := C || ' dsr=' || (n1-n0) || ' dho=' || (h1-h0) || ' rejtrace=' || coalesce(v_d->>'trace_id','-') || ' ok=' || coalesce(v_d->>'ok','-') || ' err=' || coalesce(v_d->>'error','-');

  v_d2 := public.fn_kernel_review_decide(jsonb_build_object('task_id',v_task,
    'reviewer_role_id','compliance_and_privacy_officer','decision','approved','reason','probe approval'));
  begin
    perform public.fn_kernel_step_complete(jsonb_build_object('step_run_id',v_srid,
      'actor_role_id',v_acct,'outcome','pass','idempotency_key','m03p3:e',
      'inputs',jsonb_build_object('p','x'),'output',jsonb_build_object('status','completed','output','x')));
    E := 'COMPLETED';
  exception when others then E := SQLSTATE || ' ' || left(SQLERRM,200);
  end;
  select count(*) into n1 from public.phase_c_workflow_step_run where run_id=v_run;
  select count(*) into h1 from public.phase_c_handoff_run where run_id=v_run;
  E := E || ' dsr=' || (n1-n0) || ' dho=' || (h1-h0)
    || ' srstate=' || coalesce((select state from public.phase_c_workflow_step_run where step_run_id=v_srid),'-')
    || ' runstate=' || coalesce((select state from public.phase_c_workflow_run where run_id=v_run),'-')
    || ' apptrace=' || coalesce(v_d2->>'trace_id','-');

  begin
    v := public.fn_kernel_step_complete(jsonb_build_object('step_run_id',v_srid,
      'actor_role_id',v_acct,'outcome','pass','idempotency_key','m03p3:e',
      'inputs',jsonb_build_object('p','x'),'output',jsonb_build_object('status','completed','output','x')));
    F := 'replay=' || coalesce(v->>'replay','-')
      || ' comps=' || (select count(*) from public.phase_c_step_completion where step_run_id=v_srid);
  exception when others then F := SQLSTATE || ' ' || left(SQLERRM,160);
  end;
  begin
    perform public.fn_kernel_step_complete(jsonb_build_object('step_run_id',v_srid,
      'actor_role_id',v_acct,'outcome','pass','idempotency_key','m03p3:g',
      'inputs',jsonb_build_object('p','x'),'output',jsonb_build_object('status','completed','output','x')));
    G := 'NOT_REFUSED';
  exception when others then G := SQLSTATE || ' ' || left(SQLERRM,160);
  end;

  begin
    update public.phase_c_trace set evidence_refs = '[{"tamper":true}]'::jsonb
     where trace_id = (v_d->>'trace_id')::bigint;
    H := 'PERMITTED';
  exception when others then H := SQLSTATE || ' ' || left(SQLERRM,120);
  end;
  begin
    update public.phase_c_trace set superseded_by = (v_d2->>'trace_id')::bigint
     where trace_id = (v_d->>'trace_id')::bigint;
    I := 'PERMITTED n=' || (select count(*) from public.phase_c_trace where trace_id=(v_d->>'trace_id')::bigint and superseded_by is not null);
  exception when others then I := SQLSTATE || ' ' || left(SQLERRM,120);
  end;

  raise exception 'P3<<A=% ~ B=% ~ C=% ~ E=% ~ F=% ~ G=% ~ H=% ~ I=%>>', A,B,C,E,F,G,H,I;
end $emit$;`;
try { await sql(q); console.log('no raise'); } catch (e) { console.log(String(e.message).split(' ~ ').join('\n ~ ').slice(0, 5000)); }
