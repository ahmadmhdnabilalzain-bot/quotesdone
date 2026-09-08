import { sql } from '../lib/db.mjs';
for (const t of ['phase_c_workflow_step_run','phase_d_dispatch','phase_d_effect_ledger']) {
  const r = await sql(`select column_name from information_schema.columns where table_schema='public' and table_name='${t}' order by ordinal_position`);
  console.log(t + ': ' + r.map(x=>x.column_name).join(', '));
}
