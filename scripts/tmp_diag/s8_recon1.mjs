import { sql } from '../lib/db.mjs';
const out = {};
out.schema = await sql(`select column_name, data_type, is_nullable, column_default
  from information_schema.columns where table_schema='public' and table_name='phase_d_section8_probe_result'
  order by ordinal_position`);
out.rows = await sql(`select probe_id, verdict, http_status, left(coalesce(observed,''),200) as observed, ran_at::text
  from public.phase_d_section8_probe_result order by probe_id`);
out.count = await sql(`select count(*)::int n from public.phase_d_section8_probe_result`);
out.defectmap_schema = await sql(`select column_name, data_type from information_schema.columns
  where table_schema='public' and table_name='phase_d_section8_defect_map' order by ordinal_position`);
out.defectmap = await sql(`select * from public.phase_d_section8_defect_map`);
console.log(JSON.stringify(out, null, 1));
