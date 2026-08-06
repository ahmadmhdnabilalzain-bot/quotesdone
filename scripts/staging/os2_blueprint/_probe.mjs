import { mgmtRead, PROD_REF } from '../qd_guard.mjs';
import { uiClosure } from './ui_closure.mjs';

const q = async (sql) => await mgmtRead(PROD_REF, sql);
const c = await uiClosure(q, process.cwd());
console.log('edge fns:', c.edgeFns.join(' '));
console.log('seeds:', c.seeds.length);
console.log('reachable routines:', c.routines.length);
console.log('reachable views:', c.views.length, c.views.join(','));
const objs = process.argv.slice(2).length ? process.argv.slice(2) : [
  'graph_nodes','graph_edges','company_snapshot','exec_reports','org_tasks','os_objective',
  'department_objective','employee_kpi','ai_quality_snapshots','agent_memory','decision_log',
  'scenario_library','simulations','challenge_record','priority_hierarchy','os_review',
  'kb_usage_log','agent_knowledge','operating_system','v_department_health','v_digital_twin',
  'customers','leads','org_agents','kb_chunks','inquiries','transactions','gl_journal',
  'ai_cost_log','workflow','edge_health_probe','risk_register','expenses','vision_horizon',
  'company_index','founder_alerts','notifications','agent_runs','org_departments','company_event'];
for (const t of objs) {
  const r = await q(`select ${c.UI_READER_NAMES(t)} x`);
  console.log(t.padEnd(26), String(r[0].x).slice(0, 160));
}
