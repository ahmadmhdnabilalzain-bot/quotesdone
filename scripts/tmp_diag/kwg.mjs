import { sql } from '../phase_b/lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);console.log(JSON.stringify(await sql(t),null,1).slice(0,3500));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,300)}`)}};
await q('write authority for outbox', `select * from public.kernel_write_authority where relation like '%outbox%' or relation like '%event_outbox%'`);
await q('write guard body', `select left(prosrc, 2500) src from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname='fn_kernel_write_guard'`);
