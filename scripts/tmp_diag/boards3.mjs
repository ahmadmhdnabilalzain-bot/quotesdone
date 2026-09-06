import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`
  select p.proname caller, r.path_name primitive
    from public.kernel_retired_path r
    join pg_proc p on regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', ' ', 'g'), '--[^\n]*', ' ', 'g')
                      ~ ('\y' || r.path_name || '\y\s*\(')
    join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
   where r.disposition = 'KERNEL_INTERNAL_PRIMITIVE'
     and p.proname <> r.path_name
     and p.proname not like 'fn_kernel_%'`);
console.log(JSON.stringify(r));
const w = await sql(`select routine_name, table_name from public.kernel_write_authority order by 1 limit 40`);
console.log(JSON.stringify(w).slice(0,1200));
