import { sql } from '../lib/db.mjs';
console.log(JSON.stringify(await sql(`select tgname, tgenabled, pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'public.phase_d_scenario_record'::regclass and not t.tgisinternal`)));
const d = await sql(`select pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_scenario_record_write'`);
console.log(d[0].def.slice(0, 3500));
