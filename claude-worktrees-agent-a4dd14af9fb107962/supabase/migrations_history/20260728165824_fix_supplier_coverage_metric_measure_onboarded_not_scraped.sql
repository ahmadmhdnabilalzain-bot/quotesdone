-- WRONG BEFORE: averaged lead_category rows per category, i.e. SCRAPED CONTACTS.
-- It returned 198.92 against a target of 5 -> 3978% attainment, while the number of
-- suppliers that have actually completed onboarding is ZERO. A metric that reports
-- 40x target on an empty marketplace is worse than no metric: it would have told the
-- CEO agent that supplier coverage was solved.
-- NOW: counts categories holding at least one ONBOARDED supplier (claimed account,
-- verified owner email, approved, not banned, not matching-blocked).
update employee_kpi
set measure_sql = $q$
select round(avg(n),2) from (
  select c.slug,
         count(distinct lc.lead_id) filter (
           where l.claimed
             and l.owner_email_verified
             and l.approval_status = 'approved'
             and coalesce(l.banned,false) = false
             and coalesce(l.matching_blocked,false) = false
         ) as n
  from catalog_supplier_categories c
  left join lead_category lc on lc.slug = c.slug
  left join leads l on l.id = lc.lead_id
  group by c.slug
) y
$q$
where metric = 'Coverage across active supplier categories' and active;

-- Companion: how many categories can actually be served at all.
insert into employee_kpi (agent_key, kpi, metric, target_value, unit, cadence, serves_goal, measure_sql, active)
select 'onboarding',
       'Categories with live supply',
       'Categories holding at least one onboarded supplier',
       '86', 'categories', 'monthly', 'supplier_coverage',
       $q$
select count(*)::numeric from (
  select lc.slug
  from lead_category lc
  join leads l on l.id = lc.lead_id
  where l.claimed and l.owner_email_verified and l.approval_status = 'approved'
    and coalesce(l.banned,false) = false and coalesce(l.matching_blocked,false) = false
  group by lc.slug
) z
$q$, true
where not exists (
  select 1 from employee_kpi where kpi = 'Categories with live supply'
);