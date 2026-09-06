-- THE SUPPLY DEPARTMENT HAS A PACKAGED NAME (6 Sep 2026). Follows the_packaged_assurance_departments_resolve_to_platform_and_reliability.sql.
--
-- MEASURED by v3_runtime_behaviour: "these active departments are named by no alias, so a packaged
-- import for them lands nowhere: supply". The Supply department (bd, onboarding, partnerships_mgr,
-- supplier_coverage, supplier_retention, supplier_verification) came out of the 3 Sep 2026 re-carve
-- with no org_department_alias row, so a knowledge package addressed to it had no door. It is named
-- by itself and by the business-development name the packages use.
--
--   node scripts/apply_sql.mjs scripts/sql/the_supply_department_has_a_packaged_name.sql --apply --ddl

begin;

insert into public.org_department_alias (packaged_department, dept_key, is_second_home, note)
values ('supply', 'supply', false, 'Supply (3 Sep 2026 re-carve): supplier acquisition, onboarding, verification, coverage and retention'),
       ('business_development', 'supply', false, 'packaged business-development imports land in Supply (6 Sep 2026)')
on conflict do nothing;

do $$
declare n int;
begin
  select count(*) into n from public.org_departments dp
   where dp.active and not exists (select 1 from public.org_department_alias a where a.dept_key = dp.dept_key);
  if n <> 0 then raise exception '% active department(s) still have no packaged name', n; end if;
end $$;

commit;
