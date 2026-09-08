import { sql } from '../lib/db.mjs';
const r = await sql(`select probe_id, verdict, http_status, left(observed,150) o from public.phase_d_section8_probe_result order by 1 offset 8`);
console.log(JSON.stringify(r,null,1));
