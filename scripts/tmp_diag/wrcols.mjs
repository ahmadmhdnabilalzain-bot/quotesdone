import { sql } from '../lib/db.mjs';
const r = await sql(`select column_name, is_nullable, column_default is not null d from information_schema.columns where table_schema='public' and table_name='phase_c_workflow_run' order by ordinal_position`);
console.log(r.map(x=>x.column_name+(x.is_nullable==='NO'&&!x.d?'*':'')).join(', '));
