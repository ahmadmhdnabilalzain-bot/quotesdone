-- The last two active employees with no KPI, both in Supplier Success — the department that was
-- switched off. They had no manager, no KPI and their department had no objectives and no OS: four
-- separate consequences of one row reading active=false, and none of them visible from that row.
--
-- The spec's employee object requires KPIs, and fn_agent_context prints them to the employee under
-- "# YOUR KPIs — this is how your work is measured". Without one, that heading is simply absent and
-- the employee has no idea what they are judged on.
begin;

insert into public.employee_kpi (agent_key, kpi, metric, target_value, unit, cadence, active) values
 ('supplier_coverage','Categories with three or more quoting suppliers',
  'share of live trade categories where at least three verified suppliers responded in 90 days',
  70,'%','monthly',true),
 ('supplier_coverage','Demand with no supply',
  'categories carrying inquiry demand and no matchable supplier',
  0,'count','weekly',true),
 ('supplier_retention','Supplier response rate',
  'share of invited suppliers who open or answer an inquiry',
  60,'%','weekly',true),
 ('supplier_retention','Suppliers gone quiet',
  'approved suppliers with no response in 60 days',
  0,'count','monthly',true)
on conflict do nothing;

commit;
