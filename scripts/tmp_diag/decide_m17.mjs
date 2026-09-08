import { sql } from '../lib/db.mjs';
const r = await sql(`select p.proname, regexp_replace(substring(p.prosrc from '(?is).{0,160}skip\s+locked'), '\s+',' ','g') frag
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosrc ~* 'skip[[:space:]]+locked' order by 1`);
for (const x of r) console.log(x.proname + ' :: ' + x.frag);
