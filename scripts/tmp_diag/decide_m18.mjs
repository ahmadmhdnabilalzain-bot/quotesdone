import { sql } from '../phase_b/lib/db.mjs';
const q = async (l,s)=>{try{const r=await sql(s);console.log('=== '+l);console.log(JSON.stringify(r).slice(0,5000));}catch(e){console.log('=== '+l+' ERR '+String(e).slice(0,400));}};
await q('write guard src', `select prosrc from pg_proc where proname='fn_kernel_write_guard'`);
