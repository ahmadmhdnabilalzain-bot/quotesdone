import { sql } from '../lib/db.mjs';
const q = async (l,s)=>{try{const r=await sql(s);console.log('=== '+l);console.log(JSON.stringify(r).slice(0,2500));}catch(e){console.log('=== '+l+' ERR '+String(e).slice(0,300));}};
await q('drawing/redaction objects', `select count(*) n from public.phase_d_object_state_contract where object_id ~* 'draw|redact|metadata'`);
await q('render routines', `select count(*) n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname like 'fn_phase_d%' and p.prosrc ~* 'render|pdf|exif|docx|html'`);
await q('acceptance_document cols', `select column_name from information_schema.columns where table_schema='public' and table_name='phase_d_acceptance_document' order by ordinal_position`);
await q('quotes policies count', `select count(*) n from pg_policy where polrelid='public.quotes'::regclass`);
await q('quote_comparisons publish col', `select count(*) n from information_schema.columns where table_schema='public' and table_name in ('quote_comparisons','quotes') and column_name ~* 'publish|visib'`);
