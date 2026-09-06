import { sql } from '../phase_b/lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);console.log(JSON.stringify(await sql(t)).slice(0,1500));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,220)}`)}};
await q('retired path red row', `select * from public.fn_kernel_retired_path_state() where check_name='kernel_primitives_called_from_outside_the_kernel'`);
await q('write guard red row', `select * from public.fn_kernel_write_guard_state() where check_name='routines_that_write_a_protected_table_with_no_authority'`);
await q('phase_c_task writes in injection fn', `select regexp_matches(prosrc, '(.{90}phase_c_task.{60})', 'g') m from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname='fn_phase_d_run_injected_defects' limit 4`);
