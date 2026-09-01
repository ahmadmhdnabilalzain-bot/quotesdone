-- NO OPERATING SYSTEM IS AN ORPHAN (autonomy audit, degrading gap 16).
--
-- MEASURED. Two active operating systems — Knowledge (#8) and Evolution (#10) — carry NO os_department
-- mapping, so the weekly exec meeting attributes their departments weakly and the departments named
-- knowledge / knowledge_eng / supplier_knowledge / evolution sit unmapped to any OS (which is also why
-- gap 9's KPIs under them cannot resolve an OS objective). No invariant guarded OS<->department coverage,
-- so the drift survived silently.
--
-- THIS FILE:
--   1. maps the two orphan operating systems to their matching departments (idempotent inserts). os_
--      department is NOT part of the frozen Phase A digest — verified: an insert drifts fn_phase_a_
--      baseline_drift by 0 — so this needs no PACR.
--   2. adds fn_org_structure_invariants(), a read-only guard that returns every active OS or department
--      left without an os_department row, so the next drift is visible instead of silent.
--
--   node scripts/apply_sql.mjs scripts/sql/no_operating_system_is_an_orphan.sql --apply --ddl

begin;

insert into public.os_department (os_key, dept_key, note) values
  ('knowledge', 'knowledge',          'Knowledge OS owns the knowledge department'),
  ('knowledge', 'knowledge_eng',      'Knowledge OS owns knowledge engineering'),
  ('knowledge', 'supplier_knowledge', 'Knowledge OS owns supplier knowledge'),
  ('evolution', 'evolution',          'Evolution OS owns the evolution department')
on conflict do nothing;

CREATE OR REPLACE FUNCTION public.fn_org_structure_invariants()
 RETURNS TABLE(invariant text, subject text, detail text)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- every active operating system must own at least one department
  select 'os_without_department', o.os_key,
         'active operating system "'||coalesce(o.name,o.os_key)||'" maps to no department'
    from public.operating_system o
   where coalesce(o.active, true)
     and not exists (select 1 from public.os_department d where d.os_key = o.os_key)
  union all
  -- every active department must roll up to an operating system
  select 'department_without_os', d.dept_key,
         'active department "'||d.dept_key||'" maps to no operating system'
    from public.org_departments d
   where coalesce(d.active, true)
     and not exists (select 1 from public.os_department m where m.dept_key = d.dept_key)
$function$;

revoke execute on function public.fn_org_structure_invariants() from public;

commit;
