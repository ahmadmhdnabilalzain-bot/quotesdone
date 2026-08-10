-- WHAT WAS LEFT IN THE PENDING QUEUE AFTER THE DRAIN, AND WHY IT IS NOT A BUG.
--
-- 82 pending -> 30. The 52 that drained are the ones the addressee fix unblocked. Of the 30:
--
--   24  founder-held kinds. action_worker refuses these BY NAME and always will:
--       customer_escalation 9, legal_flag 6, security_incident 3, prompt_approval 2,
--       compliance_update, finance_alert, finance_marketing_budget, incident.
--    5  worked by an employee at 16:00-16:21 UTC on 10 Aug and REOPENED by the part-9 session,
--       every one with the same recorded reason: "the deliverable is a real written analysis but
--       it ends by ASKING for information rather than settling the item."
--    1  (#2326) action_worker refused its OWN reply: "the reply is an apology, not a deliverable".
--
-- Those last six were invisible: ordinary pending rows carrying a deliverable, a decided_by and a
-- reopen reason buried in detail. They are now escalated with the reason on the row, so they read
-- as exceptions rather than as backlog. No status was changed and nothing was closed.
--
-- They are also UNREACHABLE by fn_agent_action_work_sweep, and deliberately left so: the sweep
-- excludes any action with an existing action_execution row of ANY status (idempotency_key is
-- UNIQUE and a failed attempt is a recorded attempt), so a reopened item can never be re-swept.
-- Re-running the same employee against the same question with the same context returns the same
-- question and spends a model call to do it. What these need is the missing fact, not a retry.
-- If a retry is ever wanted, the key has to carry a generation -- agent_action:<id>:<attempt> --
-- and that is a schema decision, not a predicate tweak.

update public.agent_actions a
   set escalated = true,
       escalation_reason = coalesce(a.escalation_reason,
         case when a.detail ? 'reopened_reason'
              then 'worked by ' || coalesce(a.decided_by,'an employee') ||
                   ' and reopened: the deliverable asked for information instead of settling the item. '
                   'The employee cannot close it from the context it has; it needs the missing fact.'
              else 'action_worker refused its own reply: the reply is an apology, not a deliverable' end)
 where a.status = 'pending'
   and (a.detail ? 'reopened_reason'
        or exists (select 1 from public.action_execution x
                    where x.idempotency_key = 'agent_action:' || a.id and x.status = 'failed'));
