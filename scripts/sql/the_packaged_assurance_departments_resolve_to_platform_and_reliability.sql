-- THE PACKAGED ASSURANCE DEPARTMENTS RESOLVE TO PLATFORM & RELIABILITY (6 Sep 2026).
--
-- MEASURED by v3_runtime_behaviour ("every packaged department resolves to a live runtime department"):
-- the delivered department names it_cybersecurity and qa_testing (and assurance_security_reliability)
-- still pointed at dept_key 'assurance', which the 3 Sep 2026 re-carve (PACR-004) deactivated when
-- QA, security and IT moved under product_eng ("Platform & Reliability" — qa_manager, security and the
-- cto all live there today). Three alias rows were not re-pointed with the department, so a packaged
-- name resolved to nothing. They point at product_eng now; nothing else about the departments moves.
--
--   node scripts/apply_sql.mjs scripts/sql/the_packaged_assurance_departments_resolve_to_platform_and_reliability.sql --apply --ddl

begin;

update public.org_department_alias
   set dept_key = 'product_eng',
       note = coalesce(note || ' | ', '') || 'PACR-004 3 Sep 2026: assurance deactivated; QA, security and IT live in product_eng (Platform & Reliability); re-pointed 6 Sep 2026'
 where packaged_department in ('assurance_security_reliability', 'it_cybersecurity', 'qa_testing')
   and dept_key = 'assurance';

do $$
declare n int;
begin
  select count(*) into n from public.org_department_alias a
    join public.org_departments d on d.dept_key = a.dept_key and d.active
   where a.packaged_department in ('assurance_security_reliability', 'it_cybersecurity', 'qa_testing');
  if n <> 3 then raise exception 'expected the three packaged assurance names to resolve to an active department, found %', n; end if;
end $$;

commit;
