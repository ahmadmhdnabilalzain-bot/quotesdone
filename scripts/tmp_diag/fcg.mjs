import { sql } from '../lib/db.mjs';
const r = await sql(`select substring(prosrc from greatest(position('root trace' in prosrc)-1400,1) for 1600) src from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname='fn_founder_command_trace_guard'`);
console.log(r[0].src);
