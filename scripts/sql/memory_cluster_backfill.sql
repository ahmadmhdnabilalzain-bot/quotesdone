-- Spec file #2, components 11-13 — two backfills, each one applying an EXISTING rule to the rows
-- that were written before the rule could reach them. Neither invents a value.
--
-- Apply: node scripts/apply_sql.mjs scripts/sql/memory_cluster_backfill.sql --promote --ddl
--
-- 1. org_tasks.root_cause. The trigger captures the cause out of the deliverable the owner already
--    wrote, and it matched the literal 'root cause'. org_tasks #163 closed on 2026-08-06 with an
--    empty column because its deliverable heads that paragraph "Root-cause hypothesis,
--    evidence-linked:" — a hyphen. The needle is fixed in fn_org_task_root_cause_guard; this is the
--    same regexp, run once over the closed KPI-miss tasks the old needle passed over. Nothing is
--    written where the deliverable states no cause: the where-clause requires the extraction to be
--    non-null, so a task with no diagnosis anywhere stays empty and stays visible as a miss.
update public.org_tasks o
   set root_cause = left(nullif(btrim(regexp_replace(
         coalesce(substring(coalesce(o.result ->> 'deliverable', '')
                            from '(?i)root[-_ ]?cause[^\n]{0,250}'), ''),
         '\s+', ' ', 'g')), ''), 500)
 where o.title ilike 'KPI missed%'
   and o.status = 'done'
   and coalesce(btrim(o.root_cause), '') = ''
   and nullif(btrim(regexp_replace(
         coalesce(substring(coalesce(o.result ->> 'deliverable', '')
                            from '(?i)root[-_ ]?cause[^\n]{0,250}'), ''),
         '\s+', ' ', 'g')), '') is not null;

-- 2. os_runbooks.os_key. fn_sop_update now writes it; the 21 lesson runbooks it wrote before that
--    carry null. Same derivation as the function: the lesson's own os_key, else the operating
--    system of the department that did the task, else the operating system of the department that
--    recorded the lesson. A lesson that resolves through none of the three keeps its null.
update public.os_runbooks b
   set os_key = coalesce(m.os_key,
         (select d.os_key from public.org_tasks o
            join public.os_department d on d.dept_key = o.dept_key
           where m.subject_type = 'org_task' and o.id::text = m.subject_id limit 1),
         (select d.os_key from public.os_department d where d.dept_key = m.learned_by limit 1))
  from public.institutional_memory m
 where b.slug = 'lesson-' || m.id
   and b.os_key is null;
