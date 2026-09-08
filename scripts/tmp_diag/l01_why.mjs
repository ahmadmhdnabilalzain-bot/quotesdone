import { sql } from '../lib/db.mjs';
import { readFileSync } from 'node:fs';
const R = f => readFileSync('scripts/tmp_diag/' + f, 'utf8');
const WF = process.argv[2], STEP = process.argv[3];
const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := ''; v_run bigint; v_sr bigint;
        v_ref_key text; v_boid text;
begin
  create table public.phase_d_acceptance_document(
    object_id text primary key, document_slug text not null, why text not null);
  insert into public.phase_d_acceptance_document values
    ('customer_terms_acceptance','customer-terms','x'),('supplier_terms_acceptance','supplier-agreement','x');
  alter table public.phase_d_context_key_object add column key_role text not null default 'IDENTIFIES';
  alter table public.phase_d_context_key_object drop constraint phase_d_context_key_object_pkey;
  alter table public.phase_d_context_key_object add primary key (context_key, object_id);
  insert into public.phase_d_context_key_object(context_key, object_id, why, key_role) values
    ('terms_version','customer_terms_acceptance','x','DESCRIBES'),
    ('terms_version','supplier_terms_acceptance','x','DESCRIBES'),
    ('terms_hash','customer_terms_acceptance','x','DESCRIBES'),
    ('terms_hash','supplier_terms_acceptance','x','DESCRIBES');
  execute $ra$${R('l01_rule_applies.sql')}$ra$;
  execute $sc$${R('l01_step_context.sql')}$sc$;
  execute $he$${R('l01_handler_execute.sql')}$he$;
  execute $fi$${R('l01_fixture_input.sql')}$fi$;
  execute $fp$${R('l01_fixture_effect_payload.sql')}$fp$;
  execute $ds$${R('l01_dispatch_step.sql')}$ds$;

  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_workflow_drive','label','why1'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','why1','execution_context','test','for_workflow','${WF}'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='${WF}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='${WF}') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>''
    then (select primary_object from public.phase_b_workflow where workflow_id='${WF}')||':'||(v_fx->'parent_refs'->>v_ref_key)
    else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','${WF}','label','why1',
       'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands)
       || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_run := (v->>'run_id')::bigint;
  v_out := 'REASON=' || left(coalesce((select d.reason from public.phase_d_dispatch d
              where d.run_id=v_run and d.step_id='${STEP}' order by d.dispatch_id desc limit 1),'(none)'), 900) || ' ;; ';
  select step_run_id into v_sr from public.phase_c_workflow_step_run where run_id=v_run and step_id='${STEP}' order by step_run_id desc limit 1;
  if v_sr is not null then
    v_out := v_out || 'CTX=' || left(coalesce(public.fn_phase_d_step_context(v_sr)->'context'::text,'{}'::jsonb)::text, 900) || ' ;; ';
  end if;
  v_out := v_out || 'RECORDS=' || coalesce((select string_agg(o.object_id||'/'||o.business_key||'/owner='||coalesce(o.owner_ref,'-'), ' , ')
              from public.phase_d_object_record o where o.run_id=v_run),'(none)');
  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;
try { await sql(q); } catch (e) {
  const m = String(e.message); const i = m.indexOf('PROBE<<');
  console.log(i >= 0 ? m.slice(i + 7, m.lastIndexOf('>>')).replace(/ ;; /g, '\n\n') : m.slice(0, 2500));
}
