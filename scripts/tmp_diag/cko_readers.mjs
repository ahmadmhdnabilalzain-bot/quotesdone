import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`select p.proname, (length(p.prosrc)-length(replace(p.prosrc,'phase_d_context_key_object','')))/26 n
  from pg_proc p join pg_namespace nn on nn.oid=p.pronamespace
 where nn.nspname='public' and p.prosrc like '%phase_d_context_key_object%' order by 1`);
console.log(JSON.stringify(r));
const s = await sql(`select p.proname, substring(p.prosrc from position('phase_d_context_key_object' in p.prosrc)-300 for 500) ctx
  from pg_proc p join pg_namespace nn on nn.oid=p.pronamespace
 where nn.nspname='public' and p.prosrc like '%phase_d_context_key_object%' and p.proname <> 'fn_phase_d_step_context'`);
for (const x of s) console.log(`\n--- ${x.proname}\n${x.ctx}`);
