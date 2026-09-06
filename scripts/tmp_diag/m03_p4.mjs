import { sql } from '../phase_b/lib/db.mjs';
const q = `
do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb;
  v_srid bigint; v_run bigint; v_acct text; v_task bigint; v_d jsonb; v_d2 jsonb;
  v_clo text := 'W10-S08'; v_clo_owner text; v_o jsonb; v_csrid bigint;
  A text; B text; C text; E text; F text; G text; H text; I text; J text; K text; L text; M text;
  n0 int; n1 int; h0 int; h1 int; v_tr bigint; v_t2 bigint;
begin
  perform set_config('app.phase_d_hold_step','W10-S05', true);
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','m03-p4a'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','m03-p4a','execution_context','test','for_workflow','W10'));
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W10','label','m03-p4a','execution_context','production',
    'reviewer_role_id','risk_and_governance_manager','reviewer_candidates',v_cands,
    'hold_at_step_id','W10-S05'));
  v_srid := nullif(v->>'held_step_run_id','')::bigint;
  v_run  := (v->>'run_id')::bigint;
  if v_srid is null then raise exception 'P4<<A no hold: % / %>>', coalesce(v->'stopped'->>'refused_with','-'), coalesce(v->'stopped'->>'reason','-'); end if;
  select accountable_role_id into v_acct from public.phase_c_workflow_step_run where step_run_id=v_srid;
  select task_id into v_task from public.phase_c_task where run_id=v_run and step_id='W10-S05' order by task_id limit 1;

  -- A: STATE-002 injection
  select accountable_role_id into v_clo_owner from public.phase_b_workflow_step where step_id=v_clo;
  begin
    perform set_config('app.phase_d_hold_step', v_clo, true);
    v_o := public.fn_kernel_open_step(jsonb_build_object('run_id',v_run,'step_id',v_clo,
      'owner_role_id',v_clo_owner,'source_kind','workflow_progression','source_ref','probe',
      'opened_because','probe'));
    v_csrid := (v_o->>'step_run_id')::bigint;
    perform public.fn_kernel_step_complete(jsonb_build_object('step_run_id',v_csrid,
      'actor_role_id',v_clo_owner,'outcome','pass','idempotency_key','m03p4:clo',
      'inputs',jsonb_build_object('p','x'),'output',jsonb_build_object('status','completed','output','x')));
    A := 'NOT_REFUSED';
  exception when others then A := SQLSTATE || ' ' || left(SQLERRM,420);
  end;

  -- B: REV-002 injection
  begin
    perform public.fn_kernel_step_complete(jsonb_build_object('step_run_id',v_srid,
      'actor_role_id',v_acct,'outcome','pass','idempotency_key','m03p4:b',
      'inputs',jsonb_build_object('p','x'),'output',jsonb_build_object('status','completed','output','x')));
    B := 'NOT_REFUSED';
  exception when others then B := SQLSTATE || ' ' || left(SQLERRM,140);
  end;

  -- C: REV-004 injection
  v_d := public.fn_kernel_review_decide(jsonb_build_object('task_id',v_task,
    'reviewer_role_id','risk_and_governance_manager','decision','rejected','reason','probe rejection'));
  select count(*) into n0 from public.phase_c_workflow_step_run where run_id=v_run;
  select count(*) into h0 from public.phase_c_handoff_run where run_id=v_run;
  begin
    perform public.fn_kernel_step_complete(jsonb_build_object('step_run_id',v_srid,
      'actor_role_id',v_acct,'outcome','pass','idempotency_key','m03p4:c',
      'inputs',jsonb_build_object('p','x'),'output',jsonb_build_object('status','completed','output','x')));
    C := 'NOT_REFUSED';
  exception when others then C := SQLSTATE || ' ' || left(SQLERRM,110);
  end;
  select count(*) into n1 from public.phase_c_workflow_step_run where run_id=v_run;
  select count(*) into h1 from public.phase_c_handoff_run where run_id=v_run;
  C := C || ' dsr=' || (n1-n0) || ' dho=' || (h1-h0) || ' rejtrace=' || coalesce(v_d->>'trace_id','-') || ' ok=' || coalesce(v_d->>'ok','-') || coalesce(' err='||(v_d->>'error'),'');

  -- E: control approved + STATE-003 injection
  v_d2 := public.fn_kernel_review_decide(jsonb_build_object('task_id',v_task,
    'reviewer_role_id','risk_and_governance_manager','decision','approved','reason','probe approval'));
  begin
    perform public.fn_kernel_step_complete(jsonb_build_object('step_run_id',v_srid,
      'actor_role_id',v_acct,'outcome','pass','idempotency_key','m03p4:e',
      'inputs',jsonb_build_object('p','x'),'output',jsonb_build_object('status','completed','output','x')));
    E := 'COMPLETED';
  exception when others then E := SQLSTATE || ' ' || left(SQLERRM,180);
  end;
  select count(*) into n1 from public.phase_c_workflow_step_run where run_id=v_run;
  select count(*) into h1 from public.phase_c_handoff_run where run_id=v_run;
  E := E || ' dsr=' || (n1-n0) || ' dho=' || (h1-h0)
    || ' kind=' || coalesce((select c.kind from public.fn_kernel_step_successor('W10-S05') c),'-')
    || ' srstate=' || coalesce((select state from public.phase_c_workflow_step_run where step_run_id=v_srid),'-')
    || ' runstate=' || coalesce((select state from public.phase_c_workflow_run where run_id=v_run),'-');

  -- F/G: IDEM-002
  begin
    v := public.fn_kernel_step_complete(jsonb_build_object('step_run_id',v_srid,
      'actor_role_id',v_acct,'outcome','pass','idempotency_key','m03p4:e',
      'inputs',jsonb_build_object('p','x'),'output',jsonb_build_object('status','completed','output','x')));
    F := 'replay=' || coalesce(v->>'replay','-') || ' comps=' || (select count(*) from public.phase_c_step_completion where step_run_id=v_srid);
  exception when others then F := SQLSTATE || ' ' || left(SQLERRM,120);
  end;
  begin
    perform public.fn_kernel_step_complete(jsonb_build_object('step_run_id',v_srid,
      'actor_role_id',v_acct,'outcome','pass','idempotency_key','m03p4:g',
      'inputs',jsonb_build_object('p','x'),'output',jsonb_build_object('status','completed','output','x')));
    G := 'NOT_REFUSED';
  exception when others then G := SQLSTATE || ' ' || left(SQLERRM,110);
  end;

  -- H/I: REV-005
  begin
    update public.phase_c_trace set evidence_refs='[{"tamper":true}]'::jsonb where trace_id=(v_d->>'trace_id')::bigint;
    H := 'PERMITTED';
  exception when others then H := SQLSTATE || ' ' || left(SQLERRM,90);
  end;
  begin
    update public.phase_c_trace set superseded_by=(v_d2->>'trace_id')::bigint where trace_id=(v_d->>'trace_id')::bigint;
    I := 'PERMITTED';
  exception when others then I := SQLSTATE || ' ' || left(SQLERRM,90);
  end;

  -- ---- ARM B: closure control ----
  perform set_config('app.phase_d_hold_step','W10-S08', true);
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','m03-p4b'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','m03-p4b','execution_context','test','for_workflow','W10'));
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W10','label','m03-p4b','execution_context','production',
    'reviewer_role_id','risk_and_governance_manager','reviewer_candidates',v_cands,
    'hold_at_step_id','W10-S08'));
  v_csrid := nullif(v->>'held_step_run_id','')::bigint;
  n0 := (v->>'run_id')::bigint;
  if v_csrid is null then
    J := 'no hold: ' || coalesce(v->'stopped'->>'refused_with','-') || ' / ' || left(coalesce(v->'stopped'->>'reason','-'),200);
  else
    select count(*) into h0 from public.phase_c_workflow_step_run where run_id=n0;
    begin
      perform public.fn_kernel_step_complete(jsonb_build_object('step_run_id',v_csrid,
        'actor_role_id',(select accountable_role_id from public.phase_c_workflow_step_run where step_run_id=v_csrid),
        'outcome','pass','idempotency_key','m03p4:b8',
        'inputs',jsonb_build_object('p','x'),'output',jsonb_build_object('status','completed','output','x')));
      J := 'COMPLETED';
    exception when others then J := SQLSTATE || ' ' || left(SQLERRM,300);
    end;
    select count(*) into h1 from public.phase_c_workflow_step_run where run_id=n0;
    J := J || ' kind=' || coalesce((select c.kind from public.fn_kernel_step_successor('W10-S08') c),'-')
      || ' dsr=' || (h1-h0)
      || ' runstate=' || coalesce((select state from public.phase_c_workflow_run where run_id=n0),'-')
      || ' closed=' || coalesce((select closed_at from public.phase_c_workflow_run where run_id=n0)::text,'null');
  end if;

  -- ---- ARM C: TRACE-003 ----
  v_tr := public.fn_phase_c_trace_write('TRACE-ROLE-ACTION', jsonb_build_object(
    'subject_kind','task','subject_ref', v_task::text, 'task_id', v_task,
    'actor_role_id','risk_and_governance_manager','system_actor_id','system.workflow_engine',
    'evidence_refs', jsonb_build_array(jsonb_build_object('probe','trace-003')), 'status','open'));
  begin
    update public.phase_c_trace set status='sealed' where trace_id=v_tr;
    K := 'NOT_REFUSED';
  exception when others then K := SQLSTATE || ' ' || left(SQLERRM,120);
  end;
  begin
    update public.phase_c_trace set status='sealed', sealed_at=now() where trace_id=v_tr;
    L := 'ACCEPTED sealed_at=' || coalesce((select sealed_at from public.phase_c_trace where trace_id=v_tr)::text,'null');
  exception when others then L := SQLSTATE || ' ' || left(SQLERRM,120);
  end;

  -- ---- ARM C: TRACE-004 constraint forcing ----
  begin
    set constraints all immediate;
    M := 'control_silent';
    raise exception 'PD_UNWIND_A';
  exception when others then
    if position('PD_UNWIND_A' in SQLERRM) = 0 then M := 'control ' || SQLSTATE || ' ' || left(SQLERRM,140); end if;
  end;
  select t.task_id, t.trace_id into v_t2, v_tr from public.phase_c_task t where t.run_id=v_run and t.trace_id is not null order by t.task_id limit 1;
  begin
    delete from public.phase_c_trace where trace_id = v_tr;
    set constraints all immediate;
    M := M || ' | inj NOT_REFUSED';
    raise exception 'PD_UNWIND_B';
  exception when others then
    if position('PD_UNWIND_B' in SQLERRM) = 0 then M := M || ' | inj ' || SQLSTATE || ' ' || left(SQLERRM,160); end if;
  end;

  raise exception 'P4<<A=% ~ B=% ~ C=% ~ E=% ~ F=% ~ G=% ~ H=% ~ I=% ~ J=% ~ K=% ~ L=% ~ M=%>>', A,B,C,E,F,G,H,I,J,K,L,M;
end $emit$;`;
try { await sql(q); console.log('no raise'); } catch (e) { console.log(String(e.message).split(' ~ ').join('\n ~ ').slice(0, 6000)); }
