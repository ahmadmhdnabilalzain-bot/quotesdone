import { sql } from '../lib/db.mjs';
const q = async (label, s) => { try { const r = await sql(s); console.log('=== ' + label); console.log(JSON.stringify(r).slice(0, 9000)); } catch(e){ console.log('=== '+label+' ERR '+String(e).slice(0,600)); } };

await q('routines touching quotes with auth.uid', `select p.proname, p.prosecdef,
   (select array_agg(rolname) from pg_roles r where has_function_privilege(r.rolname, p.oid, 'EXECUTE') and r.rolname in ('anon','authenticated','service_role')) grants
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.prosrc ~* 'public[.]quotes|from quotes' and p.prosrc ~* 'auth[.]uid|jwt' order by 1`);

await q('all routines mentioning auth.uid + supplier', `select p.proname, p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.prosrc ~* 'auth[.]uid' and p.proname ~* 'supplier|quote' order by 1`);

await q('overlay objects', `select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.prosrc ~* 'overlay' and p.proname ~* 'phase_c|phase_d|kernel' order by 1`);

await q('actor_may_own src', `select pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_c_actor_may_own'`);
