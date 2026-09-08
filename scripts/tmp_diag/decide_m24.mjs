import { sql } from '../lib/db.mjs';
const q = async (l,s)=>{try{const r=await sql(s);console.log('=== '+l);console.log(JSON.stringify(r).slice(0,3000));}catch(e){console.log('=== '+l+' ERR '+String(e).slice(0,300));}};
await q('trace policies', `select * from public.phase_c_trace_policy limit 20`);
await q('trace state board', `select * from public.fn_kernel_system_trace_state()`);
