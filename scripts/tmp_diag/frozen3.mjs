import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`select subject, object_kind, object_identity from public.phase_c_frozen_subject order by subject, object_identity`);
for (const x of r) console.log(`${x.subject}\t${x.object_kind}\t${x.object_identity}`);
console.log('n=' + r.length);
