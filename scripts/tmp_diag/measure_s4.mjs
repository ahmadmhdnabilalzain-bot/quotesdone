import { sql } from '../phase_c/lib/db.mjs';
const q = async (label, s) => { try { const r = await sql(s); console.log('##', label); console.log(JSON.stringify(r).slice(0, 9000)); } catch (e) { console.log('##', label, 'ERR', String(e.message).slice(0, 400)); } };
await q('s8 map', `select * from public.phase_d_section8_defect_map order by 1`);
await q('s8 results', `select probe_id, verdict, http_status, ran_at, left(observed,120) obs from public.phase_d_section8_probe_result order by 1`);
await q('s8 cols', `select table_name, column_name from information_schema.columns where table_name in ('phase_d_section8_probe_result','phase_d_section8_defect_map','phase_d_event_reconciliation') order by 1, ordinal_position`);
await q('event recon summary', `select structural_status, runtime_status, count(*) from public.phase_d_event_reconciliation group by 1,2 order by 1,2`);
await q('residue def', `select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_fixture_residue'`);
await q('gate contracts', `select gate_id, evidence_keys, refusal_code, predicate_kind from public.phase_d_gate_contract where gate_id in ('GATE-005','GATE-011','GATE-019','GATE-020','GATE-021','GATE-026','GATE-004','GATE-013','GATE-017','GATE-012','GATE-014') order by 1`);
await q('edge fns', `select 1`);
