import { sql } from '../lib/db.mjs';
const q = async (label, s) => { try { const r = await sql(s); console.log('=== ' + label); console.log(JSON.stringify(r).slice(0, 7000)); } catch(e){ console.log('=== '+label+' ERR '+String(e).slice(0,400)); } };

await q('fns after schema_validate', `select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname like 'fn_phase_d%' and p.proname > 'fn_phase_d_schema_validate' order by 1`);
await q('section8_defect_map cols', `select column_name,data_type from information_schema.columns where table_schema='public' and table_name='phase_d_section8_defect_map' order by ordinal_position`);
await q('section8_defect_map rows', `select * from public.phase_d_section8_defect_map order by 1`);
await q('section8_probe_result cols', `select column_name from information_schema.columns where table_schema='public' and table_name='phase_d_section8_probe_result' order by ordinal_position`);
await q('section8_probe_result count', `select count(*) n, max(created_at::text) from public.phase_d_section8_probe_result`);
