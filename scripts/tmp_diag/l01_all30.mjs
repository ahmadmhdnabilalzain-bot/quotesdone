// Drive every workflow with the candidate L01-L04 bodies applied inside one aborted transaction
// per workflow, withholding the object the workflow under test produces on ALL 30.
import { sql } from '../phase_b/lib/db.mjs';
import { readFileSync } from 'node:fs';
const R = f => readFileSync('scripts/tmp_diag/' + f, 'utf8');
const CAND = process.argv.includes('--baseline') ? '' : `
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
  execute $ds$${R('l01_dispatch_step.sql')}$ds$;`;

const WFS = (await sql(`select distinct workflow_id from public.phase_b_workflow_step order by 1`)).map(r => r.workflow_id);

const one = async (WF) => {
  const q = `do $emit$
declare v jsonb; v_fx jsonb; v_cands jsonb; v_rev text; v_out text := ''; r record; v_run bigint;
        v_ref_key text; v_boid text;
begin${CAND}
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_workflow_drive','label','a30-${WF.toLowerCase()}'));
  select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step x where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
    'label','a30-${WF.toLowerCase()}','execution_context','test','for_workflow','${WF}'));
  select coalesce((select x.independent_reviewer_role_id from public.phase_b_workflow_step x
    where x.workflow_id='${WF}' and coalesce(btrim(x.independent_reviewer_role_id),'')<>''
    order by x.step_id limit 1),'risk_and_governance_manager') into v_rev;
  select st.contributes_ref into v_ref_key from public.phase_d_fixture_stage st
   where st.object_id=(select primary_object from public.phase_b_workflow where workflow_id='${WF}') limit 1;
  v_boid := case when v_ref_key is not null and coalesce(v_fx->'parent_refs'->>v_ref_key,'')<>''
    then (select primary_object from public.phase_b_workflow where workflow_id='${WF}')||':'||(v_fx->'parent_refs'->>v_ref_key)
    else null end;
  v := public.fn_phase_d_drive_workflow(jsonb_build_object('workflow_id','${WF}','label','a30-${WF.toLowerCase()}',
       'execution_context','production','reviewer_role_id',v_rev,'reviewer_candidates',v_cands)
       || case when v_boid is null then '{}'::jsonb else jsonb_build_object('business_object_id',v_boid) end);
  v_run := (v->>'run_id')::bigint;
  for r in select s.step_id,
             coalesce((select d.outcome from public.phase_d_dispatch d
               where d.run_id=v_run and d.step_id=s.step_id order by d.dispatch_id desc limit 1),'NONE') oc,
             (select count(*) from public.phase_d_effect_ledger e where e.run_id=v_run and e.step_id=s.step_id) ef,
             coalesce((select left(coalesce(d.refusal_code,'-')||' '||replace(coalesce(d.reason,''),chr(10),' '),170) from public.phase_d_dispatch d
               where d.run_id=v_run and d.step_id=s.step_id order by d.dispatch_id desc limit 1),'') rr
           from public.phase_b_workflow_step s where s.workflow_id='${WF}' order by s.step_no
  loop
    if r.oc <> 'EXECUTED' or r.ef = 0 then
      v_out := v_out || r.step_id||' '||r.oc||' eff='||r.ef||' '||r.rr||' ;; ';
    end if;
  end loop;
  v_out := '${WF} effects=' || (select count(*) from public.phase_d_effect_ledger where run_id=v_run)::text
        || ' of ' || (select count(*) from public.phase_b_workflow_step where workflow_id='${WF}')::text
        || ' | ' || coalesce(nullif(v_out,''),'ALL OK');
  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;
  for (let a = 1; ; a++) {
    try { await sql(q); return `${WF} NO MARKER`; }
    catch (e) {
      const m = String(e.message); const i = m.indexOf('PROBE<<');
      if (i >= 0) return m.slice(i + 7, m.lastIndexOf('>>')).replace(/ ;; /g, '\n     ');
      if (/fetch failed|ECONNRESET|ETIMEDOUT|socket hang up|HTTP 429|HTTP 5\d\d|UND_ERR/i.test(m) && a < 4) {
        await new Promise(r => setTimeout(r, 4000 * a)); continue;
      }
      return `${WF} ERROR ${m.slice(0, 300).replace(/\s+/g, ' ')}`;
    }
  }
};

const JOBS = 3;
const queue = [...WFS]; const out = [];
await Promise.all(Array.from({ length: JOBS }, async () => {
  while (queue.length) { const wf = queue.shift(); const r = await one(wf); out.push([wf, r]); console.log(r); }
}));
