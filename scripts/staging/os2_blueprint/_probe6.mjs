import { mgmtRead, PROD_REF } from '../qd_guard.mjs';
const q = async (sql) => await mgmtRead(PROD_REF, sql);
const show = async (label, sql) => {
  try { const r = await q(sql); console.log('\n== ' + label + '\n' + JSON.stringify(r).slice(0, 2200)); }
  catch (e) { console.log('\n== ' + label + '\n  ERR ' + String(e.message).slice(0, 240)); }
};
await show('operating_system cols', `select string_agg(column_name,',') c from information_schema.columns
  where table_schema='public' and table_name='operating_system'`);
await show('operating_system names', `select os_key, name from public.operating_system order by 1`);
await show('company_index cols', `select string_agg(column_name,',') c from information_schema.columns
  where table_schema='public' and table_name='company_index'`);
await show('ceo meeting coverage', `with f as (select jsonb_array_elements(findings) e from public.exec_reports
    where officer='ceo' order by created_at desc limit 1)
  select count(*) items, count(distinct e->>'owner') owners,
    (select count(*) from public.operating_system o where o.active
       and not exists (select 1 from f where f.e->>'item' ilike '%'||o.name||'%')) os_missing,
    string_agg(distinct e->>'owner', ',') own from f`);
await show('ceo meeting agenda keys', `with f as (select jsonb_array_elements(findings) e from public.exec_reports
    where officer='ceo' order by created_at desc limit 1)
  select string_agg(distinct k, ',') keys from f, jsonb_object_keys(f.e) k`);
await show('edge_health_probe readers', `select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prokind in ('f','p') and pg_get_functiondef(p.oid) ~* '\\yedge_health_probe\\y'`);
await show('risk_register readers', `select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prokind in ('f','p') and pg_get_functiondef(p.oid) ~* '\\yrisk_register\\y'`);
await show('aiqs per agent', `select count(*) n, count(distinct agent) ags, max(at)::text mx,
  (select count(*) from (select agent from public.ai_quality_snapshots group by agent having count(distinct at)>1) z) ags2
  from public.ai_quality_snapshots`);
await show('agent_runs by dept', `select count(distinct a.department) depts_with_runs,
  (select count(distinct dept_key) from public.org_departments) depts
  from public.agent_runs r join public.org_agents a on a.agent_key = r.agent
  where r.started_at > now() - interval '24 hours'`);
await show('decision_log knowledge cols', `select string_agg(column_name,',') c from information_schema.columns
  where table_schema='public' and table_name in ('decision_log')`);
await show('exec_reports transcript?', `select count(*) with_summary, count(*) filter (where length(coalesce(summary,''))>200) long
  from public.exec_reports`);
await show('graph_nodes readers (all)', `select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prokind in ('f','p') and pg_get_functiondef(p.oid) ~* '\\ygraph_(nodes|edges)\\y'`);
await show('company_snapshot readers', `select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prokind in ('f','p') and pg_get_functiondef(p.oid) ~* '\\ycompany_snapshot\\y'`);
await show('scenario_library / whatif readers', `select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prokind in ('f','p') and pg_get_functiondef(p.oid) ~* '\\y(scenario_library|fn_what_if|fn_simulate)\\y'`);
