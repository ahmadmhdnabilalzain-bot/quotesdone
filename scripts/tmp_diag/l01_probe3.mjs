import { sql } from '../phase_b/lib/db.mjs';
import { readFileSync } from 'node:fs';
const R = f => readFileSync('scripts/tmp_diag/' + f, 'utf8');
const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := ''; r record; v_run bigint;
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

  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_workflow_drive','label','l01r'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','l01r','execution_context','test','for_workflow','W09'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='W09' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id='supplier_account' limit 1;
  v_boid := 'supplier_account:'||(v_fx->'parent_refs'->>v_ref_key);
  v_out := v_out || 'boid='||v_boid||' // ';
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','W09','label','l01r',
       'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands,
       'business_object_id', v_boid));
  v_run := (v->>'run_id')::bigint;
  for r in select o.object_id, o.business_key, coalesce(o.owner_ref,'(null)') owner,
                  coalesce(o.payload->>'terms_version','-') tv, left(coalesce(o.payload->>'terms_hash','-'),12) th
             from public.phase_d_object_record o where o.run_id = v_run order by o.record_id
  loop v_out := v_out || r.object_id||' key='||r.business_key||' owner='||r.owner||' tv='||r.tv||' th='||r.th||' // '; end loop;
  for r in select o.object_id, o.business_key, coalesce(o.owner_ref,'(null)') owner
             from public.phase_d_object_record o
            where o.object_id in ('supplier_account','supplier_terms_acceptance') and o.run_id is null
            order by o.record_id desc limit 4
  loop v_out := v_out || 'FIX '||r.object_id||' key='||r.business_key||' owner='||r.owner||' // '; end loop;
  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;
try { await sql(q); } catch (e) {
  const m = String(e.message); const i = m.indexOf('PROBE<<');
  console.log(i >= 0 ? m.slice(i + 7, m.lastIndexOf('>>')).replace(/ \/\/ /g, '\n') : m.slice(0, 2500));
}
