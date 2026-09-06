import { sql } from '../phase_b/lib/db.mjs';
const r = await sql(`
with recursive poster as (
  select p.oid, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosrc ~* 'net[.]http_(post|get)'
),
reach as (
  select p.oid, p.proname from poster p
  union
  select q.oid, q.proname
    from pg_proc q
    join pg_namespace nq on nq.oid = q.pronamespace
    join reach r on q.prosrc ~ ('\m' || r.proname || '[[:space:]]*[(]')
   where nq.nspname = 'public' and q.oid <> r.oid
)
select count(*) n, count(*) filter (where proname='trg_self_reg_category') hit from reach`);
console.log(JSON.stringify(r));
const t = await sql(`select (prosrc ~ ('\m' || 'fn_provision_category_call' || '[[:space:]]*[(]')) m, position('fn_provision_category_call' in prosrc) p from pg_proc where proname='trg_self_reg_category'`);
console.log(JSON.stringify(t));
