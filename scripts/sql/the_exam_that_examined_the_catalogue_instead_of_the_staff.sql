-- One round-robin over two unlike populations, and the catalogue was winning it.
--
-- fn_exam_pick_agent draws from every distinct agent_knowledge.agent_key, ordered by last exam with
-- nulls first and ties broken on the key itself. MEASURED on production 13 Aug 2026: 233 keys - 101
-- employees and 132 trade categories (`cat:...`). Every one of them started unexamined, so the tie
-- break decided the order, and 'cat:' sorts before 'finance_ai', 'ops_director' and almost every
-- other employee key. The result after weeks of sittings: 85 of 132 trade categories have sat an
-- exam and only 16 of 101 employees have.
--
-- Two consequences, both bad and neither visible as a failure. The company's own staff are the
-- least examined thing in it. And because the catalogue grows as suppliers are onboarded, ADDING A
-- TRADE CATEGORY silently pushes every employee's next examination further away - a knob nobody
-- thinks of as a knob, changing a cadence nobody is watching.
--
-- The fix is to stop pretending they are one queue. The picker now alternates: if the last exam sat
-- was a trade category, the next is an employee, and vice versa. Within the chosen population the
-- rule is unchanged - least recently examined, unexamined first, ties on the key. If the preferred
-- population is empty the other is served, so nothing stalls.
--
-- At the current 6 sittings a day that is 3 employees and 3 categories: 101 employees cycle in ~34
-- days and 132 categories in ~44, and the employee cadence no longer moves when the catalogue does.
CREATE OR REPLACE FUNCTION public.fn_exam_pick_agent()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  with last_sat as (
    select (select agent_key from knowledge_exam_results order by created_at desc limit 1) as k
  ),
  -- Want a category next only if the last one sat was NOT a category. A null last_sat (no exam has
  -- ever been sat) starts with an employee, which is the population that matters more.
  want as (
    select coalesce((select k from last_sat) not like 'cat:%', false) as want_cat
  ),
  ranked as (
    select k.agent_key,
           (k.agent_key like 'cat:%') as is_cat,
           e.last_exam
    from (select distinct agent_key from agent_knowledge where agent_key <> '_global') k
    left join (select agent_key, max(created_at) last_exam from knowledge_exam_results group by agent_key) e
      on e.agent_key = k.agent_key
  )
  select agent_key from ranked
  -- false sorts first, so rows whose population matches what we want come first; everything after
  -- that is the original ordering, and the second population is still reachable when the first is
  -- empty.
  order by (is_cat is distinct from (select want_cat from want)), last_exam asc nulls first, agent_key
  limit 1;
$function$;
