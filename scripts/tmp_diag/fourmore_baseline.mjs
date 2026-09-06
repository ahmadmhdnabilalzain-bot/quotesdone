import { sql } from '../phase_b/lib/db.mjs';
const B = `
do $emit$
declare v_out text := ''; r record;
begin
  perform public.fn_phase_d_test_context_open(jsonb_build_object('operation_key','pdop_deliverable_build','label','fm-base'));
  for r in select * from public.fn_phase_d_run_injected_defects() order by defect_id loop
    v_out := v_out || ' ' || r.defect_id || ':' || case r.status when 'REFUSED_AS_REQUIRED' then 'R' when 'NOT_REFUSED' then 'N' when 'NOT_RUN' then 'x' else r.status end;
  end loop;
  raise exception 'BASE<<%>>', v_out;
end $emit$;`;
try { await sql(B); } catch(e){ const m=/BASE<<([\s\S]*)>>/.exec(e.message); console.log(m[1].trim()); }
