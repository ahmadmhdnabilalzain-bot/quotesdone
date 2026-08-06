import { mgmtRead, PROD_REF } from '../qd_guard.mjs';
const q = async (sql) => await mgmtRead(PROD_REF, sql);
const show = async (label, sql) => {
  try { const r = await q(sql); console.log('\n== ' + label + '\n' + JSON.stringify(r).slice(0, 2000)); }
  catch (e) { console.log('\n== ' + label + '\n  ERR ' + String(e.message).slice(0, 240)); }
};

await show('volatility', `select p.proname, p.provolatile from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in ('fn_ws_agent_ops','fn_ws_exec','fn_agents_board','fn_os_dashboard_viz',
  'fn_ws_reports','fn_ws_strategy','fn_ws_finance','fn_health_index','fn_os_command','fn_what_if','fn_simulate',
  'fn_ops_dashboard','fn_os_record','fn_entity_activity','fn_ws_company','fn_ws_ai') order by 1`);
await show('ws_agent_ops keys', `select string_agg(k,',') from jsonb_object_keys(public.fn_ws_agent_ops('cfo')) k`);
await show('ws_agent_ops perf', `select public.fn_ws_agent_ops('cfo')->'performance'`);
await show('ws_exec keys', `select string_agg(k,',') from jsonb_object_keys(public.fn_ws_exec()) k`);
await show('ws_exec health', `select public.fn_ws_exec()->'command'->'health'`);
await show('agents_board keys', `select string_agg(k,',') from jsonb_object_keys(public.fn_agents_board()) k`);
await show('agents_board depts', `select jsonb_pretty(public.fn_agents_board()->'departments')`);
await show('exec_reports shapes', `select officer, created_at::text, jsonb_typeof(findings) ft, jsonb_typeof(recommendations) rt,
  left(summary, 90) s from public.exec_reports order by created_at desc limit 12`);
await show('exec_reports finding keys', `select officer, (select string_agg(k,',') from jsonb_object_keys(findings) k) ks
  from public.exec_reports where jsonb_typeof(findings)='object' order by created_at desc limit 10`);
await show('employee_kpi per agent', `select count(*) ags_with_2plus from (
  select agent_key from public.employee_kpi group by agent_key having count(distinct created_at) > 1) z`);
await show('aiqs cols', `select string_agg(column_name,',') c from information_schema.columns
  where table_schema='public' and table_name in ('ai_quality_snapshots')`);
await show('scenario_library keys', `select scenario_key, category, last_result from public.scenario_library order by 1`);
await show('graph freshness', `select (select count(*) from public.graph_nodes) nodes,
  (select count(*) from public.graph_edges) edges, (select max(updated_at)::text from public.graph_nodes) mx,
  (select string_agg(distinct kind,',') from public.graph_nodes) kinds`);
await show('twin tables', `select t, (select to_regclass('public.'||t) is not null) ex from unnest(array[
  'customers','leads','org_agents','kb_chunks','inquiries','transactions','gl_journal','ai_cost_log',
  'workflow','edge_health_probe','risk_register','expenses','vision_horizon']) t`);
await show('twin counts', `select 'customers' t, count(*) n from public.customers
 union all select 'leads', count(*) from public.leads
 union all select 'org_agents', count(*) from public.org_agents
 union all select 'kb_chunks', count(*) from public.kb_chunks
 union all select 'inquiries', count(*) from public.inquiries
 union all select 'transactions', count(*) from public.transactions
 union all select 'gl_journal', count(*) from public.gl_journal
 union all select 'ai_cost_log', count(*) from public.ai_cost_log
 union all select 'workflow', count(*) from public.workflow
 union all select 'edge_health_probe', count(*) from public.edge_health_probe
 union all select 'risk_register', count(*) from public.risk_register
 union all select 'expenses', count(*) from public.expenses
 union all select 'vision_horizon', count(*) from public.vision_horizon`);
await show('agent_runs dept', `select string_agg(column_name,',') from information_schema.columns
  where table_schema='public' and table_name='agent_runs'`);
await show('org_tasks cols', `select string_agg(column_name,',') from information_schema.columns
  where table_schema='public' and table_name='org_tasks'`);
