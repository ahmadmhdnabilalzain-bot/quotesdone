import { sql } from '../phase_b/lib/db.mjs';
const q = async (l,s)=>{try{const r=await sql(s);console.log('=== '+l);console.log(JSON.stringify(r).slice(0,5000));}catch(e){console.log('=== '+l+' ERR '+String(e).slice(0,400));}};
await q('object_record counts', `select object_id, count(*) n, count(*) filter (where state='approved') appr from public.phase_d_object_record group by 1 order by 1`);
await q('founder identity', `select identity, kind, active, auth_user_id is not null has_sub from public.phase_c_founder_identity`);
await q('skip locked lines', `select p.proname, (regexp_match(p.prosrc, '(?is)(from\s+[a-z_.]+[^;]{0,200}?skip\s+locked)'))[1] frag from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosrc ~* 'skip[[:space:]]+locked'`);
await q('advisory frag', `select (regexp_match(prosrc,'(?is)(pg_[a-z_]*advisory[a-z_]*\([^)]*\))'))[1] f from pg_proc where proname='fn_assign_founding_rank'`);
