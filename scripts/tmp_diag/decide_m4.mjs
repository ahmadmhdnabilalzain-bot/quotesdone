import { sql } from '../phase_b/lib/db.mjs';
const q = async (label, s) => { try { const r = await sql(s); console.log('=== ' + label); console.log(JSON.stringify(r).slice(0, 8000)); } catch(e){ console.log('=== '+label+' ERR '+String(e).slice(0,600)); } };

await q('whoami', `select current_user, session_user, current_setting('is_superuser') su`);
await q('gate contracts', `select gate_id, left(coalesce(evidence_contract::text,''),200) ev from public.phase_d_gate_contract order by gate_id`);
