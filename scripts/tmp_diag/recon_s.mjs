import { sql } from '../phase_b/lib/db.mjs';
const q=async(l,s)=>{try{console.log('\n=== '+l);console.log(JSON.stringify(await sql(s),null,1));}catch(e){console.log('\n=== '+l+' ERR '+e.message);}};
await q('who am I', `select current_user, session_user, current_setting('is_superuser') as superuser, (select rolsuper from pg_roles where rolname=current_user) as rolsuper`);
await q('can I read auth_user_id + does it exist in auth.users', `select f.kind, f.active, f.auth_user_id is not null as has_uid, exists(select 1 from auth.users u where u.id=f.auth_user_id) as user_exists from public.phase_c_founder_identity f order by 1`);
await q('section8 probe results for PRIV-004', `select * from public.phase_d_section8_probe_result order by 1 limit 40`);
