import { sql } from '../lib/db.mjs';
const q = async (label, s) => { try { console.log('\n=== '+label); console.log(JSON.stringify(await sql(s), null, 1)); } catch(e){ console.log('\n=== '+label+' ERROR '+e.message); } };
await q('founder identity rows', `
select kind, active, auth_user_id is not null as has_auth_user_id, display_name,
       case when kind='email' then '***@'||split_part(identity,'@',2) else left(identity,12)||'...' end as identity_redacted,
       added_at, left(coalesce(note,''),120) as note
from public.phase_c_founder_identity order by active desc, kind`);
await q('routines mentioning sealed_at', `
select p.proname, p.prokind from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.prokind='f' and p.prolang <> 12
  and pg_get_functiondef(p.oid) ilike '%sealed_at%' order by 1`);
await q('phase_c_trace columns', `select column_name,data_type,is_nullable from information_schema.columns where table_schema='public' and table_name='phase_c_trace' order by ordinal_position`);
await q('fn_phase_c_trace_append_only body', `select pg_get_functiondef(p.oid) as def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_c_trace_append_only'`);
