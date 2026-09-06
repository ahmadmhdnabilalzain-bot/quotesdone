import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`select b.object_id, b.ownership_scope, b.relation_kind, b.governing_workflow_id,
   (select w.primary_object from public.phase_b_workflow w where w.workflow_id=b.governing_workflow_id) prim,
   (select count(*) from public.phase_d_object_write_map m where m.object_id=b.object_id) wm
  from public.phase_d_business_object_binding b order by b.ownership_scope, b.object_id`);
for (const x of r) console.log(`${x.ownership_scope}\t${x.object_id}\t${x.relation_kind}\twm=${x.wm}\tgov=${x.governing_workflow_id}\tprim=${x.prim}`);
console.log('n='+r.length);
