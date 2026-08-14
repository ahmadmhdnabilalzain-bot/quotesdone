-- agent_train needs a credential and an entry point, or the training loop still has no runner.
--
-- The same two doors as artifact_review: action.invoker holds the HTTP-invoker credential and
-- fn.cos_execute is what POSTs service-role authority to an edge executor, so
-- fn_org_action_executor_guard requires the target to be inside its scope. Widened
-- deliberately: training is advisory-safe, reversible and notifies nobody, and it is the only
-- way a role can ever honestly reach training_passed.
update internal_credential
   set scope = (select array_agg(distinct x) from unnest(scope || array['agent_train']) x)
 where context in ('action.invoker', 'fn.cos_execute')
   and not ('agent_train' = any(scope));

-- NOT on a cron. Every case is two model calls and the founder pays for them, so this runs
-- when a remediation opens or when it is asked for, never on a timer.
insert into org_action_executor
  (action_class, kind, target, params, active, note, advisory_safe, department, owner_os,
   risk_tier, reversible, idempotency_strategy, timeout_seconds, max_attempts, backoff,
   required_authority, notifies_human, unattended_ok)
values
  ('agent.train', 'edge', 'agent_train',
   '{"purpose":"practice","n":3}'::jsonb, true,
   'Drives an agent through unseen packaged training cases and scores the answers against the case''s own required moves.',
   true, 'knowledge_eng', 'knowledge_os', 'low', true, 'natural_key', 120, 1, 'exponential',
   null, false, true)
on conflict (action_class) do update set
  target = excluded.target, kind = excluded.kind, active = true, note = excluded.note;
