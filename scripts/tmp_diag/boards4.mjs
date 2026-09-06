import { sql } from '../phase_b/lib/db.mjs';
const q = `
  select p.proname as caller, r.path_name as primitive
    from public.kernel_retired_path r
    join pg_proc p on regexp_replace(regexp_replace(p.prosrc, '/[*].*?[*]/', ' ', 'g'), '--[^' || chr(10) || ']*', ' ', 'g')
                      ~ ('\\y' || r.path_name || '\\y[[:space:]]*[(]')
    join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
   where r.disposition = 'KERNEL_INTERNAL_PRIMITIVE'
     and p.proname <> r.path_name
     and p.proname not like 'fn_kernel_%'`;
console.log(JSON.stringify(await sql(q)));
console.log(JSON.stringify(await sql(
  `select routine_name, table_name from public.kernel_write_authority
    where table_name in ('phase_c_workflow_run','phase_c_workflow_step_run','phase_c_task',
                         'phase_c_handoff_run','phase_c_event_outbox','kernel_trigger_inbox')
    order by table_name, routine_name`)).slice(0, 1600));
