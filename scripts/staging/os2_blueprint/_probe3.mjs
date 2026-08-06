import { mgmtRead, PROD_REF } from '../qd_guard.mjs';
const q = async (sql) => await mgmtRead(PROD_REF, sql);
const show = async (label, sql) => {
  try { const r = await q(sql); console.log('\n== ' + label + '\n' + JSON.stringify(r).slice(0, 2200)); }
  catch (e) { console.log('\n== ' + label + '\n  ERR ' + String(e.message).slice(0, 260)); }
};

await show('fn signatures', `select p.proname, pg_get_function_identity_arguments(p.oid) args
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
   and p.proname in ('fn_ws_agent_ops','fn_what_if','fn_simulate','fn_exec_meeting','fn_challenge',
   'fn_company_snapshot','fn_founder_brief','fn_officer_recs','fn_ws_exec','fn_ws_reports','fn_agents_board',
   'fn_os_dashboard_viz','fn_graph_rebuild','fn_os_command','fn_health_index','fn_finance_forecast') order by 1`);
await show('exec_reports cols', `select column_name, data_type from information_schema.columns
  where table_schema='public' and table_name='exec_reports' order by ordinal_position`);
await show('exec_reports latest', `select max(created_at)::text mx, count(*) n,
  (select count(distinct officer) from public.exec_reports) offs from public.exec_reports`);
await show('exec_reports newest batch', `select officer, created_at::text, (select string_agg(k,',') from jsonb_object_keys(findings) k) keys
  from public.exec_reports order by created_at desc limit 12`);
await show('operating_system', `select os_key, active from public.operating_system order by 1`);
await show('cron exec meeting', `select j.jobname, j.schedule, j.active,
  (select max(d.end_time)::text from cron.job_run_details d where d.jobid=j.jobid and d.status='succeeded') last_ok,
  (select count(*) from cron.job_run_details d where d.jobid=j.jobid) runs
  from cron.job j where j.command ~* 'fn_exec_meeting|exec_meeting'`);
await show('company_snapshot', `select snapshot_on::text, (select string_agg(k,',') from jsonb_object_keys(state) k) keys
  from public.company_snapshot order by 1 desc limit 12`);
await show('company_snapshot cols', `select column_name from information_schema.columns
  where table_schema='public' and table_name='company_snapshot' order by ordinal_position`);
await show('scenario_library', `select * from public.scenario_library limit 14`);
await show('simulations cols', `select column_name from information_schema.columns
  where table_schema='public' and table_name='simulations' order by ordinal_position`);
await show('graph freshness', `select (select count(*) from public.graph_nodes) nodes,
  (select count(*) from public.graph_edges) edges,
  (select max(built_at)::text from public.graph_nodes) mx`);
await show('graph_nodes cols', `select column_name from information_schema.columns
  where table_schema='public' and table_name='graph_nodes' order by ordinal_position`);
await show('kb_usage_log', `select count(*) n, max(created_at)::text mx from public.kb_usage_log`);
await show('employee_kpi trend', `select count(*) n, count(distinct agent_key) ags, count(distinct created_at::date) days,
  max(created_at)::text mx from public.employee_kpi`);
await show('ai_quality_snapshots', `select count(*) n, max(created_at)::text mx,
  (select string_agg(column_name,',') from information_schema.columns where table_schema='public' and table_name='ai_quality_snapshots') cols
  from public.ai_quality_snapshots`);
await show('realtime publication', `select schemaname, tablename from pg_publication_tables where pubname='supabase_realtime' order by 2`);
await show('priority_hierarchy', `select * from public.priority_hierarchy limit 8`);
await show('challenge_record recent', `select count(*) n, max(created_at)::text mx, count(distinct stance) st from public.challenge_record`);
