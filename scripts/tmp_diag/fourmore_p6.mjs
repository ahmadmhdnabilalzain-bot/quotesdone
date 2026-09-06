import { sql } from '../phase_b/lib/db.mjs';
const P = `
do $emit$
declare v_out text := ''; v_fx jsonb; v_inq text; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build','label','fourmore-p6'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','fourmore6','execution_context','test'));
  v_inq := v_fx->'parent_refs'->>'inquiry_id';
  select category, emirate, scope_type, budget, coalesce(array_to_string(trades,'|'),'-') tr, left(coalesce(spec::text,'-'),200) sp,
         left(coalesce(summary,'-'),80) su, coalesce(drawing_file_path,'-') dfp, left(coalesce(completeness::text,'-'),400) cp, status, rfq_ready::text rr
    into r from public.inquiries where id::text=v_inq;
  v_out := v_out || format('cat=%s em=%s sc=%s bud=%s tr=%s dfp=%s st=%s rr=%s', r.category,r.emirate,r.scope_type,r.budget,r.tr,r.dfp,r.status,r.rr);
  v_out := v_out || E'\nspec=' || r.sp || E'\ncompleteness=' || r.cp;
  update public.inquiries set spec=null, summary=null, raw_input=null, boq=null, drawing_file_path=null,
     budget=null, trades=null, scope_type=null, status='new' where id::text=v_inq;
  v_out := v_out || E'\nAFTER BLANK: ' || (select coalesce(status,'-')||'/'||coalesce(rfq_ready::text,'-')||'/'||left(coalesce(completeness::text,'-'),300) from public.inquiries where id::text=v_inq);
  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;
try { await sql(P); } catch(e) { console.log(e.message.split('\n').join('\n')); }
