import { sql } from '../lib/db.mjs';
console.log(JSON.stringify(await sql(`select count(*) n from public.phase_d_injected_defect_result`)));
console.log(JSON.stringify(await sql(`select count(*) n from public.phase_d_section8_probe_result`)));
console.log(JSON.stringify(await sql(`select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname like 'fn_phase_d%' order by 1`)));
