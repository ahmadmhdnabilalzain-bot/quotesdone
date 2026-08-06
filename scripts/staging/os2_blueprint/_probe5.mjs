import { mgmtRead, PROD_REF } from '../qd_guard.mjs';
const q = async (sql) => await mgmtRead(PROD_REF, sql);
const show = async (label, sql) => {
  try { const r = await q(sql); console.log('\n== ' + label + '\n' + JSON.stringify(r).slice(0, 2600)); }
  catch (e) { console.log('\n== ' + label + '\n  ERR ' + String(e.message).slice(0, 240)); }
};
const W = `('(inse'||'rt\\s+into|upd'||'ate\\s|del'||'ete\\s+from)')`;
await show('volatile writers?', `select p.proname, p.provolatile,
   (pg_get_functiondef(p.oid) ~* ${W}) writes
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
   and p.proname in ('fn_ws_agent_ops','fn_ws_finance','fn_os_command','fn_what_if','fn_simulate') order by 1`);
await show('ws_agent_ops build keys', `select (select string_agg(m[1], ',') from
   regexp_matches(pg_get_functiondef(p.oid), '''([a-z_]+)''\\s*,\\s*(?:to_jsonb|coalesce|jsonb)', 'g') m) k
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='fn_ws_agent_ops'`);
await show('edge_health_probe readers?', `select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and pg_get_functiondef(p.oid) ~* '\\yedge_health_probe\\y'`);
await show('os_health def snippet', `select left(pg_get_functiondef(p.oid), 900) d from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_os_health'`);
await show('exec_reports findings arrays', `select officer, jsonb_array_length(findings) nf,
  left(findings::text, 400) f from public.exec_reports order by created_at desc limit 3`);
await show('exec_reports recs', `select officer, left(recommendations::text, 400) r
  from public.exec_reports order by created_at desc limit 4`);
await show('ceo latest meeting findings', `select left(findings::text, 2000) f from public.exec_reports
  where officer='ceo' order by created_at desc limit 1`);
await show('fn_exec_meeting calls fn_challenge?', `select
  (pg_get_functiondef(p.oid) ~* '\\yfn_challenge\\s*\\(') ch,
  (pg_get_functiondef(p.oid) ~* '\\ypriority_hierarchy\\y') ph,
  (pg_get_functiondef(p.oid) ~* '\\yoperating_system\\y') os,
  (pg_get_functiondef(p.oid) ~* '\\yexec_reports\\y') er,
  length(pg_get_functiondef(p.oid)) len
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_exec_meeting'`);
await show('day_cadence / os_review', `select (select count(*) from public.os_review) osr,
  (select max(created_at)::text from public.os_review) osr_mx,
  (select count(*) from public.day_cadence) dc`);
await show('founder_alerts recent', `select count(*) n, max(created_at)::text mx from public.founder_alerts`);
await show('company_index', `select index_name, value, band, measured_on::text from public.company_index
  where measured_on=(select max(measured_on) from public.company_index)`);
await show('simulations rows', `select id, left(scenario::text,160) s, left(result::text,220) r, created_at::text
  from public.simulations order by created_at desc limit 5`);
