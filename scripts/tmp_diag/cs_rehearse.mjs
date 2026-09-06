import { sql } from '../phase_b/lib/db.mjs';
const q = `do $emit$
declare v_open jsonb; v_close jsonb; v_id bigint; v_out text := '';
begin
  v_open := public.fn_phase_d_committed_scenario_open(jsonb_build_object('label','rehearsal'));
  v_id := (v_open->>'scenario_id')::bigint;
  v_out := 'OPEN=' || left(v_open::text, 1200) || ' ;; ';
  v_close := public.fn_phase_d_committed_scenario_close(v_id);
  v_out := v_out || 'CLOSE=' || left(v_close::text, 1200);
  raise exception 'PROBE<<%>>', v_out;
end $emit$;`;
try { await sql(q); } catch (e) { const m=String(e.message); const i=m.indexOf('PROBE<<'); console.log(i>=0?m.slice(i+7,m.lastIndexOf('>>')).replace(/ ;; /g,'\n\n'):m.slice(0,2500)); }
