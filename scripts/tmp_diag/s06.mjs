import { sql } from '../lib/db.mjs';
const q = `do $emit$
declare v_fx jsonb; v_out text := ''; v jsonb;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_workflow_drive','label','s06probe'));
  v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object('label','s06probe','execution_context','test','for_workflow','W09'));
  v_out := v_out || 'EFFECT_PAYLOAD W09-S06 = ' || coalesce(public.fn_phase_d_fixture_effect_payload('W09-S06')::text,'(null)') || E'\n';
  v_out := v_out || 'INPUTS W09-S06 = ' || coalesce(public.fn_phase_d_step_inputs('W09-S06')::text,'(null)') || E'\n';
  v_out := v_out || 'LEGAL = ' || coalesce((select string_agg(d.slug||'|'||d.version||'|'||left(encode(sha256(convert_to(coalesce(d.body_html,''),'UTF8')),'hex'),16), ' ; ') from public.legal_documents d),'(none)') || E'\n';
  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;
try { await sql(q); } catch (e) { const m=String(e.message); const i=m.indexOf('PROBE<<'); console.log(i>=0?m.slice(i+7,m.indexOf('>>',i)).replace(/\n/g,'\n'):m.slice(0,2500)); }
