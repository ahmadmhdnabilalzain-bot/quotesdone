import { sql } from '../lib/db.mjs';
const q = async (l,s)=>{try{const r=await sql(s);console.log('=== '+l);console.log(JSON.stringify(r).slice(0,6000));}catch(e){console.log('=== '+l+' ERR '+String(e).slice(0,400));}};
await q('fixture stages', `select stage_no, stage_key, object_id from public.phase_d_fixture_stage order by stage_no`);
await q('object state contracts drawing/redaction/safe/acceptance', `select object_id, policy_family from public.phase_d_object_state_contract where object_id ~* 'draw|redact|safe|accept|certificat|quote|quotation' order by 1`);
await q('W23 W24 W30 names', `select workflow_id, workflow_name from public.phase_b_workflow where workflow_id in ('W23','W24','W30','W09','W04','W14')`);
await q('quote_comparisons cols', `select column_name from information_schema.columns where table_schema='public' and table_name='quote_comparisons' order by ordinal_position`);
await q('skip locked / advisory', `select p.proname, (p.prosrc ~* 'skip[[:space:]]+locked') skiplocked, (p.prosrc ~* 'pg_(try_)?advisory') advisory
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and (p.prosrc ~* 'skip[[:space:]]+locked' or p.prosrc ~* 'pg_(try_)?advisory') order by 1`);
