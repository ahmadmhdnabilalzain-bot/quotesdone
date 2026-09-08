import { sql } from '../lib/db.mjs';
const r = await sql(`select defect_id, category, status, left(injected,160) injected, left(expected,90) expected, left(blocker,400) blocker, left(observed,200) observed from public.phase_d_injected_defect_result where status <> 'REFUSED_AS_REQUIRED' order by defect_id`);
for (const x of r) {
  console.log(`\n--- ${x.defect_id} [${x.category}] ${x.status}`);
  console.log(`INJ : ${x.injected}`);
  console.log(`EXP : ${x.expected}`);
  console.log(`BLK : ${x.blocker}`);
  if (x.observed) console.log(`OBS : ${x.observed}`);
}
console.log(`\ncount=${r.length}`);
