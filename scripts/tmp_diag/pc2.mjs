import { sql } from '../lib/db.mjs';
const q = async (label, text) => {
  try { const r = await sql(text); console.log(`\n### ${label}`); console.log(JSON.stringify(r, null, 1).slice(0, 12000)); }
  catch (e) { console.log(`\n### ${label}\nERROR ${String(e.message).slice(0,600)}`); }
};
await q('injected defect result cols', `select column_name, data_type from information_schema.columns where table_schema='public' and table_name='phase_d_injected_defect_result' order by ordinal_position`);
await q('outcome tally', `select outcome, count(*) from public.phase_d_injected_defect_result group by 1 order by 2 desc`);
