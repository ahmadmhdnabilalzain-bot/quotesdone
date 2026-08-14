-- REORGANISING THE AGENT COMPANY — company goals follow the work, not the old department key.
--
-- The migration repointed company_goals.owner_dept mechanically, through fn_dept_canonical. That is
-- correct for a merge and wrong for a SPLIT: two departments absorbed goals for work that moved
-- elsewhere in the same reorganisation, and two departments ended up owning none at all.
--
--  * Independent Assurance owns platform reliability — and also ended up owning
--    `classification_accuracy`, `hallucination_rate`, `missing_info_detection` and
--    `production_bugs`. Those are AI and engineering OUTPUT quality: Product, Engineering & AI
--    delivers them and Assurance gates them. An independent control function owning the target it
--    audits is the same conflict this reorganisation removed from review, from release and from
--    incident fixing; leaving it in the goal table would put it straight back.
--  * People & Company Operations inherited the five knowledge goals because the old `knowledge`
--    department was named "Administration & Operations" while carrying the knowledge corpus. The
--    corpus, its director, its engineer, its validator, the taxonomy manager and the category
--    curator all sit in Data, Intelligence & Knowledge now. The goals follow them.
--
-- No target, metric, unit, period or measure is changed by this file. Only who is answerable.
-- After it, product_eng and data_intel each own four company goals where they owned none, and
-- every one of the ten departments has at least one line to the AED 1,000,000 objective.

begin;

update public.company_goals set owner_dept = 'product_eng', updated_at = now()
 where active and owner_dept = 'assurance'
   and key in ('classification_accuracy','hallucination_rate','missing_info_detection','production_bugs');

update public.company_goals set owner_dept = 'data_intel', updated_at = now()
 where active and owner_dept = 'people_ops'
   and key in ('categories_covered','knowledge_accuracy','knowledge_modules_complete','knowledge_review_cycle');

-- sop_coverage stays with People & Company Operations deliberately: an SOP is a process artefact
-- owned by process improvement and document operations, not a knowledge-corpus record.

-- Re-run the unambiguous objective link now that two more departments own goals. Same rule as
-- before — only where the department owns exactly one active goal, so nothing is guessed.
update public.department_objective o set goal_key = g.key, updated_at = now()
  from (select owner_dept, min(key) as key, count(*) as n
          from public.company_goals where active group by owner_dept) g
 where o.active and coalesce(o.goal_key,'') = '' and g.owner_dept = o.dept_key and g.n = 1;

commit;
