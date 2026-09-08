import { sql } from '../lib/db.mjs';
import fs from 'node:fs';
const r = await sql(`select p.proname, p.oid::regprocedure::text as sig, pg_get_functiondef(p.oid) as def
  from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
 where ns.nspname='public' and p.proname in ('fn_phase_d_step_context','fn_phase_d_rule_gate','fn_phase_d_fixture_build','fn_phase_d_fixture_stage_build')
 order by 1`);
let out='';
for (const row of r) out += '\n\n========== ' + row.sig + ' ==========\n' + row.def;
fs.writeFileSync(new URL('./w09_ctx_bodies.txt', import.meta.url), out);
console.log(r.map(x=>x.sig).join('\n'), '\nbytes', out.length);
const all = await sql(`select p.proname, p.oid::regprocedure::text as sig from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname like 'fn_phase_d%' order by 1`);
console.log(JSON.stringify(all.map(x=>x.sig), null, 1));
