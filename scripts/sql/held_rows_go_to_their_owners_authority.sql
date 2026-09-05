-- THE CONFIGURATION GAP THAT HELD 34 PROPOSALS WITH NOBODY TO OWN THEM.
--
-- Measured on production 5 Sep 2026 22:31Z: 34 org_tasks at status='proposed', every one annotated by
-- fn_task_approve with "the authority model itself grants no more than gated — no org_authority row for
-- this department and action class - defaulting to gated". fn_dept_authority fails closed to 'gated'
-- when a (dept, action_class) pair has no row, and fn_task_approve holds a gated proposal. A hold with
-- no owner is what the founder's standing rule forbids: nothing waits on him except a Stripe refund.
--
-- Across the ten active departments and the five determination classes the lane produces
-- (analysis, exec_review, recommend, investigate, incident_fix) sixteen pairs had no row. They are
-- filled here at the SAME tiers their peers already hold: analysis is 'autonomous' in all 28 departments
-- that have it; the other four are 'advisory' — a written determination, the lowest tier, which
-- fn_task_approve approves into the org_task lane (advisory ranks below gated, so the AUTONOMOUS_CEILING
-- clamp never touches it). No department's power is widened past what a peer already has.
--
-- fn_org_authority_guard requires app.change_reason for a grant; it is set once for the transaction.
--
--   node scripts/apply_sql.mjs scripts/sql/held_rows_go_to_their_owners_authority.sql --apply --ddl
begin;
set local app.change_reason = 'held rows go to their owners, 5 Sep 2026: 34 proposals were held on missing org_authority rows for the department/class pair; filled at the tiers peers already hold (analysis autonomous, the four determination classes advisory)';

insert into public.org_authority (dept_key, action_class, max_tier, threshold_aed, note)
select d.dept_key, c.cls,
       case when c.cls = 'analysis' then 'autonomous' else 'advisory' end,
       null,
       'filled 5 Sep 2026 (held_rows_go_to_their_owners_authority.sql): the pair had no row, so every '
       || 'proposal of this class was held gated with nobody to own it; the tier is what peers hold'
  from public.org_departments d
 cross join (values ('analysis'), ('exec_review'), ('recommend'), ('investigate'), ('incident_fix')) c(cls)
 where d.active
   and not exists (select 1 from public.org_authority a
                    where a.dept_key = d.dept_key and a.action_class = c.cls);
commit;
