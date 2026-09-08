import { sql } from '../lib/db.mjs';
console.log(JSON.stringify(await sql(`
select source_component_id, source_class, target_workflow, target_step_or_signal, current_activation
  from public.phase_c_source_cutover
 where source_component_id like 'dbtrigger:%'
   and (source_component_id like '%documents%' or source_component_id like '%leads%'
     or source_component_id like '%inquiries%' or source_component_id like '%quotes%'
     or source_component_id like '%customers%' or source_component_id like '%notifications%'
     or source_component_id like '%inquiry_matches%' or source_component_id like '%transactions%')
 order by 1`), null, 1));
