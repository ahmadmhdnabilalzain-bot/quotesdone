import { sql } from '../phase_c/lib/db.mjs';
import { writeFileSync } from 'node:fs';
let out = '';
const q = async (label, s) => { try { const r = await sql(s); out += `## ${label}\n${JSON.stringify(r).slice(0, 14000)}\n`; } catch (e) { out += `## ${label} ERR ${String(e.message).slice(0, 400)}\n`; } };
await q('defaults', `select table_name, column_name, is_nullable, column_default from information_schema.columns where table_schema='public' and ((table_name='refunds' and column_name in ('status','decided_by','decided_at','reason_code','requested_by','amount_fils','customer_id','transaction_id')) or (table_name='department_objective' and column_name in ('status','objective','dept_key','goal_key')) or (table_name='org_tasks' and column_name in ('status','title','dept_key','tier')) or table_name='customers' or (table_name='quote_comparisons') or table_name='legal_reviews' or (table_name='documents' and column_name in ('bucket','path','kind','status','ref_table','ref_id')) or (table_name='inquiry_matches' and column_name in ('supplier_id','inquiry_id','sent_at','status')) or (table_name='leads' and column_name in ('id','approval_status','verified'))) order by table_name, ordinal_position`);
await q('W17 steps', `select step_id, step_name, left(required_action,200) ra, left(required_output,120) ro, founder_gate, left(acceptance_criteria,160) ac, independent_reviewer_role_id from public.phase_b_workflow_step where workflow_id='W17' order by step_no`);
await q('W05 W16 W04 steps', `select step_id, step_name, left(required_output,100) ro, founder_gate from public.phase_b_workflow_step where workflow_id in ('W05','W16','W04','W14','W15') order by step_id`);
await q('policy families', `select object_id, policy_family, relation_kind, ownership_scope, canonical_relation from public.phase_d_business_object_binding order by 1`);
await q('W17 binding gates', `select b.step_id, b.founder_gate, b.gate_ids, b.handler_class from public.phase_d_handler_binding b where b.workflow_id='W17' order by 1`);
// scenario records for one scenario, aborted
const SCN = `do $emit$ declare v_fx jsonb; v_out text := ''; r record; begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build','label','scnprobe'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','scnprobe','execution_context','test'));
  for r in select object_id, business_key, owner_ref, ownership_scope, contributes_ref, contributed_value, canonical_ref->>'canonical_identity' ci, canonical_ref->>'version' ver, (select string_agg(k, ',') from jsonb_object_keys(coalesce(payload,'{}'::jsonb)) k) pk from public.phase_d_scenario_record where fixture_run_id = public.fn_phase_d_fixture_context() order by scenario_record_id loop
    v_out := v_out || r.object_id || '|' || coalesce(r.business_key,'') || '|' || coalesce(r.owner_ref,'') || '|' || coalesce(r.ownership_scope,'') || '|' || coalesce(r.contributes_ref,'') || '|' || coalesce(r.contributed_value,'') || '|' || coalesce(r.ci,'') || '|' || coalesce(r.ver,'') || '|' || coalesce(r.pk,'') || chr(10);
  end loop;
  raise exception 'SCN<<%>>', v_out; end $emit$;`;
try { await sql(SCN); out += '## scenario: no raise\n'; } catch (e) { const m = String(e.message); const a = m.indexOf('SCN<<'); out += '## scenario records\n' + (a < 0 ? m.slice(0, 1500) : m.slice(a + 5, m.indexOf('>>', a)).replace(/\n/g, '\n')) + '\n'; }
writeFileSync('scripts/tmp_diag/measure_s5.out', out);
console.log('written', out.length);
