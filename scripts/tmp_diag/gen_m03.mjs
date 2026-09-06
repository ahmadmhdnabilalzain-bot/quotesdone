import { sql } from '../phase_b/lib/db.mjs';
import { writeFileSync, readFileSync } from 'node:fs';
let d = (await sql(`select pg_get_functiondef('public.fn_phase_d_outbound_state()'::regprocedure) def`))[0].def;
const lines = d.split('\n');
const i0 = lines.findIndex(l => l.trim() === 'scanned as (');
const i1 = lines.findIndex((l, i) => i > i0 && l.trim() === '),');
if (i0 < 0 || i1 < 0) { console.error('anchor not found'); process.exit(1); }
const A = lines.slice(i0, i1 + 1).join('\n');
const NEW = [
"-- M03. THE SCAN WAS DIRECT-ONLY, SO A DOOR ONE CALL DEEP WAS INVISIBLE TO ITS OWN DENOMINATOR.",
"-- This matched net.http_post in the TRIGGER FUNCTION's own body. public.leads carries",
"-- trg_self_reg_category, whose body posts nothing and calls fn_provision_category_call, which",
"-- posts to /functions/v1/category_provision. The board reported 4 of 4 registered and green while",
"-- a fifth door existed that it could not see -- an instrument reporting on a narrower subject than",
"-- its name claims. Measured 23 Aug 2026 across all 345 public triggers. Reachability is now the",
"-- transitive closure over public routines, so a helper, and a helper's helper, counts as the door",
"-- it is.",
"poster as (",
"  select p.oid, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace",
"   where n.nspname = 'public' and p.prosrc ~* 'net[.]http_(post|get)'",
"),",
"reach as (",
"  select p.oid, p.proname from poster p",
"  union",
"  select q.oid, q.proname",
"    from pg_proc q",
"    join pg_namespace nq on nq.oid = q.pronamespace",
"    join reach r on q.prosrc ~ ('\m' || r.proname || '[[:space:]]*[(]')",
"   where nq.nspname = 'public' and q.oid <> r.oid",
"),",
"scanned as (",
"  select 'public.' || c.relname as relation, tg.tgname as trigger_name, p.proname as function_name,",
"         pg_get_triggerdef(tg.oid) as triggerdef",
"    from pg_trigger tg",
"    join pg_proc  p on p.oid = tg.tgfoid",
"    join pg_class c on c.oid = tg.tgrelid",
"    join pg_namespace n on n.oid = c.relnamespace",
"   where not tg.tgisinternal and n.nspname = 'public'",
"     and p.oid in (select oid from reach)",
"     and ('public.' || c.relname) in (select relation from pd_rel)",
"),",
].join('\n');
d = d.replace(A, NEW).replace('with pd_rel as (', 'with recursive pd_rel as (');
writeFileSync('scripts/tmp_diag/m03_outbound_state.sql', d);
console.log('ok len=' + d.length);
