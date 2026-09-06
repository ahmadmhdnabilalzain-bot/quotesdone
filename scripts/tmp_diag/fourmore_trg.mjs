import { sql } from '../phase_b/lib/db.mjs';
const q = async (s,l)=>{console.log('\n### '+l); console.log(JSON.stringify(await sql(s),null,1));};
await q(`select t.tgname, p.proname, pg_get_triggerdef(t.oid) as def
 from pg_trigger t join pg_proc p on p.oid=t.tgfoid
 where t.tgrelid='public.inquiry_matches'::regclass and not t.tgisinternal order by t.tgname`,'inquiry_matches triggers');
await q(`select t.tgname, p.proname
 from pg_trigger t join pg_proc p on p.oid=t.tgfoid
 where t.tgrelid='public.phase_d_object_record'::regclass and not t.tgisinternal order by t.tgname`,'phase_d_object_record triggers');
await q(`select column_name, data_type, is_nullable from information_schema.columns where table_schema='public' and table_name='inquiry_matches' order by ordinal_position`,'inquiry_matches cols');
await q(`select column_name, data_type from information_schema.columns where table_schema='public' and table_name='phase_d_object_record' order by ordinal_position`,'phase_d_object_record cols');
await q(`select rule_id, left(rule_text,200) as t from public.phase_d_business_rule where rule_id in ('BR-015','BR-025')`,'BR-015');
