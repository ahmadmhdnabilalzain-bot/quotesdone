import { sql } from '../phase_b/lib/db.mjs';
for (const t of ['customers','inquiries','notifications','company_event','customer_preference','doc_versions','founder_alerts','documents','kernel_trigger_inbox','phase_c_event_outbox','undo_log','phase_c_trace','phase_c_task','phase_c_handoff_run','phase_c_step_completion','event_delivery','event_assessment','org_tasks','agent_runs']) {
  const r = await sql(`select column_name, is_nullable, column_default is not null hasdef from information_schema.columns where table_schema='public' and table_name='${t}' order by ordinal_position`);
  console.log(`\n${t}: ` + r.map(x=>x.column_name + (x.is_nullable==='NO' && !x.hasdef ? '*' : '')).join(', '));
}
