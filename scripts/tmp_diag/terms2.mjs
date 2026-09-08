import { sql } from '../lib/db.mjs';
const q=async(l,t)=>{try{console.log(`\n### ${l}`);console.log(JSON.stringify(await sql(t),null,1).slice(0,5000));}catch(e){console.log(`\n### ${l}\nERR ${String(e.message).slice(0,300)}`)}};
await q('catalogue cols', `select column_name from information_schema.columns where table_schema='public' and table_name='phase_d_fixture_catalogue' order by ordinal_position`);
await q('who mentions phase-d-fixture-terms', `select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosrc like '%phase-d-fixture-terms%'`);
await q('catalogue rows for terms', `select * from public.phase_d_fixture_catalogue where (value #>> '{}') like '%terms%' or field_key like '%terms%'`);
await q('legal_documents cols', `select column_name from information_schema.columns where table_schema='public' and table_name='legal_documents' order by ordinal_position`);
