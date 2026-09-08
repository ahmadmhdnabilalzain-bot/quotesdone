import { sql } from '../lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);const r=await sql(t);console.log(typeof r==='string'?r:JSON.stringify(r,null,1).slice(0,9000));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,400)}`)}};
await q('outbox deliver body', `select pg_get_functiondef('public.fn_kernel_outbox_deliver(integer,text)'::regprocedure) def`);
