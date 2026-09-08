import { sql } from '../lib/db.mjs';
const r = await sql(`select source_component_id, source_class, target_workflow, target_step_or_signal, current_activation from public.phase_c_source_cutover where source_component_id in ('edge:customer_documents','edge:sup_dob') order by 1`);
for (const x of r) console.log([x.source_component_id, x.source_class, x.target_workflow, x.target_step_or_signal, x.current_activation].join(' | '));
console.log('n=' + r.length);
