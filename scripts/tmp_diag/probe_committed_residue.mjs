import { q } from './q.mjs';
const sql = `
do $p$
declare v jsonb; v2 jsonb; v_before bigint; v_after bigint; v_close bigint;
begin
  select count(*) into v_before from public.phase_d_file_revision;
  v := public.fn_phase_d_committed_scenario_open(jsonb_build_object('label','o12-residue-probe'));
  select count(*) into v_after from public.phase_d_file_revision;
  v2 := public.fn_phase_d_committed_scenario_close((v->>'scenario_id')::bigint);
  select count(*) into v_close from public.phase_d_file_revision;
  raise exception '%', 'RESIDUE before=' || v_before || ' after_open=' || v_after
    || ' after_close=' || v_close || ' close_ok=' || coalesce(v2->>'ok','?')
    || ' fxrev=' || (select count(*) from public.phase_d_file_revision where revision_ref like 'fxrev:%');
end $p$;`;
try { await q(sql); console.log('DID NOT RAISE'); }
catch(e){ const m=String(e.message); const i=m.indexOf('RESIDUE'); console.log(i<0?m.slice(0,900):m.slice(i).split('\nCONTEXT')[0]); }
