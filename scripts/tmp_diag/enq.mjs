import { sql } from '../lib/db.mjs';
import { writeFileSync } from 'node:fs';
const d = (await sql(`select pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_enqueue_doc_backups'`));
writeFileSync('scripts/tmp_diag/enq_body.txt', d.map(x=>x.def).join('\n\n'));
console.log('len=' + (d[0]?.def||'').length);
const c = await sql(`select column_name from information_schema.columns where table_schema='public' and table_name='doc_backups' order by ordinal_position`);
console.log('doc_backups: ' + c.map(x=>x.column_name).join(', '));
const hr = await sql(`select status, count(*) from public.phase_c_handoff_run group by 1`);
console.log('handoff_run: ' + JSON.stringify(hr));
