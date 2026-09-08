import { sql } from '../lib/db.mjs';
const q = async (label, s) => { try { const r = await sql(s); console.log('=== ' + label); console.log(JSON.stringify(r).slice(0, 9000)); } catch(e){ console.log('=== '+label+' ERR '+String(e).slice(0,500)); } };

await q('probe results', `select probe_id, verdict, http_status, left(observed,140) obs, ran_at::text from public.phase_d_section8_probe_result order by ran_at`);
