import { sql } from '../phase_b/lib/db.mjs';
const q = `
do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb;
  v_srid bigint; v_run bigint; v_psr bigint; v_pk text; v_pacct text; v_pstep text;
  F text; G text; N text;
  c0 int; c1 int; s0 int; s1 int;
  v_src text; p_claim int; p_lost int; p_adv int; p_open int; p_first int;
begin
  perform set_config('app.phase_d_hold_step','W10-S05', true);
  perform public.fn_phase_d_test_context_open(jsonb_build_object(
    'operation_key','pdop_workflow_drive','label','m03-p5'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','m03-p5','execution_context','test','for_workflow','W10'));
  v := public.fn_phase_d_drive_workflow(jsonb_build_object(
    'workflow_id','W10','label','m03-p5','execution_context','production',
    'reviewer_role_id','risk_and_governance_manager','reviewer_candidates',v_cands,
    'hold_at_step_id','W10-S05'));
  v_run := (v->>'run_id')::bigint;

  select c.idempotency_key, c.step_run_id, x.accountable_role_id, x.step_id
    into v_pk, v_psr, v_pacct, v_pstep
    from public.phase_c_step_completion c
    join public.phase_c_workflow_step_run x on x.step_run_id = c.step_run_id
   where x.run_id = v_run order by c.completion_id desc limit 1;

  select count(*) into c0 from public.phase_c_step_completion where step_run_id = v_psr;
  select count(*) into s0 from public.phase_c_workflow_step_run where run_id = v_run;
  begin
    v := public.fn_kernel_step_complete(jsonb_build_object('step_run_id',v_psr,
      'actor_role_id',v_pacct,'outcome','pass','idempotency_key',v_pk,
      'inputs',jsonb_build_object('p','x'),'output',jsonb_build_object('status','completed','output','x')));
    select count(*) into c1 from public.phase_c_step_completion where step_run_id = v_psr;
    select count(*) into s1 from public.phase_c_workflow_step_run where run_id = v_run;
    F := 'replay=' || coalesce(v->>'replay','-') || ' comps ' || c0 || '->' || c1 || ' srs ' || s0 || '->' || s1
      || ' state=' || coalesce((select state from public.phase_c_workflow_step_run where step_run_id=v_psr),'-')
      || ' step=' || v_pstep || ' runstate=' || coalesce((select state from public.phase_c_workflow_run where run_id=v_run),'-');
  exception when others then F := SQLSTATE || ' ' || left(SQLERRM,160);
  end;
  begin
    perform public.fn_kernel_step_complete(jsonb_build_object('step_run_id',v_psr,
      'actor_role_id',v_pacct,'outcome','pass','idempotency_key', v_pk || ':different',
      'inputs',jsonb_build_object('p','x'),'output',jsonb_build_object('status','completed','output','x')));
    G := 'NOT_REFUSED';
  exception when others then G := SQLSTATE || ' ' || left(SQLERRM,200);
  end;
  select count(*) into c1 from public.phase_c_step_completion where step_run_id = v_psr;
  G := G || ' comps ' || c0 || '->' || c1;

  -- static ordering measurement for PD-TRACE-004(a)
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='fn_kernel_step_complete';
  p_claim := strpos(v_src, 'insert into public.phase_c_step_completion');
  p_lost  := strpos(v_src, 'return v_prior || jsonb_build_object(''replay'', true);');
  p_adv   := strpos(v_src, 'fn_phase_c_trace_advance(');
  p_open  := strpos(v_src, 'fn_kernel_open_step(');
  p_first := least(nullif(p_adv,0), nullif(p_open,0));
  N := 'claim=' || p_claim || ' lost=' || p_lost || ' adv=' || p_adv || ' open=' || p_open || ' first_trace=' || p_first
     || ' lost_returns_before_any_trace=' || (p_lost > 0 and p_lost < p_first)::text
     || ' n_lost_returns=' || (length(v_src) - length(replace(v_src,'return v_prior || jsonb_build_object(''replay'', true);','')))/length('return v_prior || jsonb_build_object(''replay'', true);');

  raise exception 'P5<<F=% ~ G=% ~ N=%>>', F, G, N;
end $emit$;`;
try { await sql(q); console.log('no raise'); } catch (e) { console.log(String(e.message).split(' ~ ').join('\n ~ ').slice(0, 4000)); }
