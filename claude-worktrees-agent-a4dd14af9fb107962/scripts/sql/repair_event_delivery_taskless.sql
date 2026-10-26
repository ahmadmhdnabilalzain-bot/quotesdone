-- REPAIR: the 179 task-less deliveries that a text column was retro-stamped onto.
--
-- SCORER_DEFECTS_ROUND3 [xos-05-internal-tasks], real-system-gap: leg 2 of xos-05 is
-- `task_id is null and unroutable_reason is null and delivered_at > now()-24h = 0`, and 173 rows
-- inside that window were excused by an `unroutable_reason` backfilled on 2026-08-06 reading
-- "Delivered by the pre-2026-08-06 dispatcher, which recorded the delivery without raising a
-- task". Strip that string and the leg reads 173, not 0. 171 of the 179 went to
-- knowledge_director, which EXISTS in org_agents and IS actively subscribed — so the event
-- reached a live employee and produced no work, and the excuse text does not even describe the
-- situation.
--
-- This file does not delete the excuse; it makes the excuse unnecessary. Both statements apply
-- the CORRECTED dispatcher's own rule (fn_event_dispatch, promoted in the same session) to the
-- rows the previous body wrote. Nothing is invented: every value written here is read out of the
-- event's own payload or out of org_agents.

-- 1. THE EVENT REPORTS ON A TASK THAT EXISTS, SO THE DELIVERY BELONGS TO THAT TASK.
-- All 171 are review.step, whose payload carries subject_type='org_task' and subject_id — the
-- review_chain row copied wholesale by fn_emit_event. The dispatcher now attaches these instead
-- of minting a duplicate task per review step; this is that same rule applied backwards. The
-- excuse column is cleared because the delivery is no longer silent: it names its work.
update public.event_delivery d
   set task_id = (e.payload->>'subject_id')::bigint,
       unroutable_reason = null
  from public.company_event e
 where e.id = d.event_id
   and d.task_id is null
   and e.payload->>'subject_type' = 'org_task'
   and coalesce(e.payload->>'subject_id','') ~ '^[0-9]+$'
   and exists (select 1 from public.org_tasks t where t.id = (e.payload->>'subject_id')::bigint);

-- 2. THE REMAINDER ARE GENUINELY UNROUTABLE, AND THE STORED REASON SAID SOMETHING ELSE.
-- 8 of the 11 remaining task-less rows are cybersecurity_mgr, an agent_key with NO org_agents
-- row, carrying the "pre-2026-08-06 dispatcher" sentence. The true reason is the one the live
-- dispatcher writes today, and it is verifiable: xos-05 can now assert that an excused delivery
-- names a subscriber that really does not resolve, which prose could never be checked against.
update public.event_delivery d
   set unroutable_reason = format(
         'no org_agents row for subscriber %s — this subscription points at an '
      || 'employee who does not exist, so the event reaches nobody', d.agent_key)
 where d.task_id is null
   and not exists (select 1 from public.org_agents a where a.agent_key = d.agent_key);
