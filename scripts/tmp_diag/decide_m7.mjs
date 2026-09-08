import { sql } from '../lib/db.mjs';
const q = async (label, s) => { try { const r = await sql(s); console.log('=== ' + label); console.log(JSON.stringify(r).slice(0, 9000)); } catch(e){ console.log('=== '+label+' ERR '+String(e).slice(0,600)); } };
await q('write map', `select object_id, target_relation, key_column from public.phase_d_object_write_map order by 1`);
await q('test operations', `select * from public.phase_d_test_operation order by 1`);
