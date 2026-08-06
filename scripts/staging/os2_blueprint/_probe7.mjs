import { mgmtRead, PROD_REF } from '../qd_guard.mjs';
const q = async (sql) => await mgmtRead(PROD_REF, sql);
const show = async (label, sql) => {
  const t0 = Date.now();
  try { const r = await q(sql); console.log('\n== ' + label + ' [' + (Date.now()-t0) + 'ms]\n' + JSON.stringify(r).slice(0, 1800)); }
  catch (e) { console.log('\n== ' + label + ' [' + (Date.now()-t0) + 'ms]\n  ERR ' + String(e.message).slice(0, 240)); }
};
const MEET = `(select id from public.exec_reports where officer='ceo' order by created_at desc limit 1)`;
await show('meeting coverage', `with f as (select jsonb_array_elements(findings) e from public.exec_reports where id = ${MEET})
  select (select count(*) from f) items,
   (select count(*) from public.operating_system o where o.active
      and not exists (select 1 from f where f.e->>'item' ilike '%'||o.name||'%')) os_missing,
   (select count(*) from f where coalesce(f.e->>'owner','')='') no_owner,
   (select string_agg(distinct k,',') from f, jsonb_object_keys(f.e) k) keys`);
await show('agenda six', `with f as (select jsonb_array_elements(findings) e from public.exec_reports where id = ${MEET}),
  d(sec, rx) as (values ('wins','win|achiev|success'),('problems','problem|issue|blocker'),
    ('kpis','kpi|metric|attainment'),('risks','risk'),('opportunities','opportunit'),('requests','request|ask|need'))
  select d.sec, (select count(*) from f where exists (select 1 from jsonb_object_keys(f.e) k where k ~* d.rx)) hits from d`);
await show('report_registry def', `select left(definition, 900) d from pg_views where schemaname='public' and viewname='report_registry'`);
await show('ws_reports keys', `select string_agg(k,',') from jsonb_object_keys(public.fn_ws_reports()) k`);
await show('agent goal universal TIMING', `select count(*) n from public.org_agents a where a.active
  and (public.fn_ws_agent_ops(a.agent_key) ?| array['goal','goals','objective','objectives','current_goal'])`);
await show('recs numeric', `select count(*) tot, count(*) filter (where recommendations::text ~ '[0-9]') num
  from public.exec_reports where created_at > now() - interval '14 days'`);
await show('summaries causal', `select count(*) tot,
  count(*) filter (where summary ~* '\\y(because|due to|driven by|caused by|owing to|as a result of|since)\\y') caus,
  count(*) filter (where summary ~ '[0-9]') numeric
  from public.exec_reports where created_at > now() - interval '14 days'`);
await show('decision sources', `select count(*) n, count(*) filter (where sources is not null and sources::text <> '[]' and sources::text <> 'null') src
  from public.decision_log where created_at > now() - interval '7 days'`);
await show('org_tasks near meeting', `select count(*) n from public.org_tasks t, public.exec_reports r
  where r.id = ${MEET} and t.created_at between r.created_at - interval '1 hour' and r.created_at + interval '2 hours'`);
await show('meetings 60d', `select count(*) n from public.exec_reports where officer='ceo' and created_at > now() - interval '60 days'`);
await show('scenario coverage', `with d(cls, rx) as (values ('pricing','pric|fee|discount|tariff'),
   ('vendor cost shock','vendor|supplier cost|cost shock|price increase|key_supplier'),
   ('channel failure','channel|outage|campaign fail|traffic|meta|google'),
   ('geographic expansion','geograph|expansion|new (city|market|country|emirate)|abu dhabi|saudi'))
  select d.cls, (select count(*) from public.scenario_library s
    where (s.scenario_key||' '||s.name||' '||coalesce(s.situation,'')||' '||coalesce(s.category,'')) ~* d.rx) hits from d`);
