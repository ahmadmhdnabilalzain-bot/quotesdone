import { sql } from '../lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);console.log(JSON.stringify(await sql(t)).slice(0,2200));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,220)}`)}};
await q('retired path detail', `select substring(prosrc from position('kernel_primitives_called_from_outside_the_kernel' in prosrc)-1200 for 2000) src from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname='fn_kernel_retired_path_state'`);
