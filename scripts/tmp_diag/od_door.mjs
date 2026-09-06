import { sql } from '../phase_b/lib/db.mjs';
const cols = await sql(`select column_name, data_type from information_schema.columns where table_schema='public' and table_name='phase_d_outbound_door' order by ordinal_position`);
console.log('COLUMNS:', JSON.stringify(cols));
const rows = await sql(`select * from public.phase_d_outbound_door order by 1`);
console.log('ROWS:', JSON.stringify(rows, null, 1));
