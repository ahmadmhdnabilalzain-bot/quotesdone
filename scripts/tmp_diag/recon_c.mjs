import { sql } from '../phase_b/lib/db.mjs';
const q = async (label, s) => { try { console.log('\n=== '+label); console.log(JSON.stringify(await sql(s), null, 1)); } catch(e){ console.log('\n=== '+label+' ERROR '+e.message); } };
await q('v_obj_customer_terms_acceptance def', `select pg_get_viewdef('public.v_obj_customer_terms_acceptance'::regclass, true) as def`);
await q('founder identity rows (structural)', `
select identity_id, kind, active, auth_user_id is not null as has_auth_user_id,
       case when kind='email' then split_part(identity,'@',2) else '(nonemail)' end as domain,
       created_at
from public.phase_c_founder_identity order by active desc, identity_id`);
await q('founder identity columns', `select column_name,data_type from information_schema.columns where table_schema='public' and table_name='phase_c_founder_identity' order by ordinal_position`);
await q('phase_c_founder_auth_event columns + count', `select (select count(*) from public.phase_c_founder_auth_event) as n_events`);
await q('routines mentioning sealed_at', `
select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and pg_get_functiondef(p.oid) ilike '%sealed_at%' order by 1`);
