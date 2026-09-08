import { sql } from '../lib/db.mjs';
import { readFileSync } from 'node:fs';
const ra = readFileSync('scripts/tmp_diag/l01_rule_applies.sql','utf8');
const sc = readFileSync('scripts/tmp_diag/l01_step_context.sql','utf8');
const WF = process.argv[2] || 'W09';
const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := ''; r record; v_run bigint;
begin
  create table public.phase_d_acceptance_document(
    object_id text primary key, document_slug text not null, why text not null);
  insert into public.phase_d_acceptance_document values
    ('customer_terms_acceptance','customer-terms','W04 records a customer acceptance of the published customer terms'),
    ('supplier_terms_acceptance','supplier-agreement','W09-S06 records a supplier acceptance of the published supplier agreement');
  alter table public.phase_d_context_key_object drop constraint phase_d_context_key_object_pkey;
  alter table public.phase_d_context_key_object add primary key (context_key, object_id);
  insert into public.phase_d_context_key_object(context_key, object_id, why) values
    ('terms_version','customer_terms_acceptance','BR-025 judges the version a customer acceptance names'),
    ('terms_version','supplier_terms_acceptance','BR-025 judges the version a supplier acceptance names'),
    ('terms_hash','customer_terms_acceptance','BR-025 judges the digest a customer acceptance names'),
    ('terms_hash','supplier_terms_acceptance','BR-025 judges the digest a supplier acceptance names'),
    ('acceptance_ref','supplier_terms_acceptance','BR-026 accepts either acceptance record; the register named only one');
  execute $ra$${ra}$ra$;
  execute $sc$${sc}$sc$;

  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_workflow_drive','label','l01p'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','l01p','execution_context','test','for_workflow','${WF}'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='${WF}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>'' order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','${WF}','label','l01p',
       'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands));
  v_run := (v->>'run_id')::bigint;
  for r in select o.object_id, o.business_key, o.owner_ref, left(o.payload::text,700) pl from public.phase_d_object_record o where o.run_id=v_run order by o.record_id loop v_out := v_out || r.object_id||' key='||r.business_key||' owner='||coalesce(r.owner_ref,'-')||' payload='||r.pl||' // '; end loop;
  v_out := v_out || ' EFFECTS='||(select count(*) from public.phase_d_effect_ledger where run_id=v_run)::text;
  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;
try { await sql(q); } catch (e) { const m=String(e.message); const i=m.indexOf('PROBE<<'); console.log(i>=0?m.slice(i+7,m.lastIndexOf('>>')).replace(/ \/\/ /g,'\n'):m.slice(0,2500)); }
