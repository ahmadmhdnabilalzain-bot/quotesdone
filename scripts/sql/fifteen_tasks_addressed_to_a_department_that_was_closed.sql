-- FIFTEEN OPEN TASKS ADDRESSED TO A DEPARTMENT THAT WAS CLOSED.
--
-- 15 Aug 2026. The reorg deactivated `procurement` ("Marketplace & Procurement") and folded it into
-- `marketplace` ("Marketplace & Supplier Network"). Fifteen org_tasks created the same day were
-- still addressed to `procurement`: 10 `assigned`, 5 `in_progress`. Nothing failed and nothing
-- errored — the rows simply sit in a department with no active members, so no employee can ever
-- pick them up. This is the recurring shape in this estate: work addressed to an identity nobody
-- models, found by a check rather than by an outage.
--
-- Measured before the move:
--   select t.dept_key, t.status, count(*)
--     from org_tasks t join org_departments d on d.dept_key = t.dept_key
--    where t.status in ('assigned','in_progress') and not d.active group by 1,2;
--   -> procurement/assigned 10, procurement/in_progress 5
--
-- The mapping is not a guess: org_departments records exactly one closed department whose name
-- begins "Marketplace &", and exactly one open one. The status is NOT touched — an in_progress task
-- stays in_progress. Only the address changes.
--
-- Scoped to open work on purpose. Completed and cancelled tasks keep their historical dept_key,
-- because rewriting them would falsify the record of which department did the work.
update public.org_tasks t
   set dept_key = 'marketplace'
  from public.org_departments d
 where d.dept_key = t.dept_key
   and t.dept_key = 'procurement'
   and not d.active
   and t.status in ('assigned', 'in_progress');

-- AN OVERLAY ADDED WITHOUT AN EVALUATION SUITE.
--
-- tax_overlay_uae was created 15 Aug 01:21 as a knowledge overlay ("UAE tax responsibility explicit
-- without another persistent agent"), which is the right shape. Its evaluation_suite was left null,
-- so fn_org_role_violations() reported `no_evaluation:tax_overlay_uae` and the canonical-rules check
-- failed. The 86 category overlays all carry one; this is a gap in the new row, not a rule that
-- needs relaxing. It takes the same suite the category overlays use, read from them rather than
-- typed in, so it cannot drift from whatever they are set to.
update public.org_role
   set evaluation_suite = (
         select r.evaluation_suite
           from public.org_role r
          where r.runtime_mode = 'knowledge_overlay'
            and r.role_id <> 'tax_overlay_uae'
            and r.evaluation_suite is not null
          group by r.evaluation_suite
          order by count(*) desc
          limit 1),
       updated_at = now()
 where role_id = 'tax_overlay_uae'
   and evaluation_suite is null;
