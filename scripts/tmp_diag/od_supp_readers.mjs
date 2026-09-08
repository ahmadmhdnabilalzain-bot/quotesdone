import { sql } from '../lib/db.mjs';
const r = await sql(`
select n.nspname||'.'||p.proname as fn, pg_get_function_identity_arguments(p.oid) as args,
       length(p.prosrc) as len
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where p.prosrc like '%phase_d_outbound_door%'
order by 1`);
console.log(JSON.stringify(r,null,1));
