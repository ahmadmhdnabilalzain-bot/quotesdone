-- artifact_review needs a caller and a credential, or it is one more finished capability
-- with no entry point.
--
-- No new secret is minted here. action.invoker already holds the HTTP-invoker credential for
-- low-risk, advisory-safe, reversible edge executors, and a design review is exactly that:
-- it reads bytes, writes a review row and changes nothing a customer can see. Widening that
-- credential by one function name is smaller than adding a secret the founder would have to
-- hold, and the scope stays an explicit list rather than a wildcard.
-- fn_org_action_executor_guard refuses an edge executor whose target is outside the
-- fn.cos_execute scope, because cos_execute is what POSTs service-role authority to it. The
-- guard is right and the widening is deliberate: this executor is intended, it is
-- advisory-safe and reversible, and it notifies nobody.
update internal_credential
   set scope = (select array_agg(distinct x) from unnest(scope || array['artifact_review']) x)
 where context in ('action.invoker', 'fn.cos_execute')
   and not ('artifact_review' = any(scope));

-- Give the review a runner. Every executor KIND needs one; an action class with no runner is
-- a queue that fills and never drains.
insert into org_action_executor
  (action_class, kind, target, params, active, note, advisory_safe, department, owner_os,
   risk_tier, reversible, idempotency_strategy, timeout_seconds, max_attempts, backoff,
   required_authority, notifies_human, unattended_ok)
values
  ('artifact.review', 'edge', 'artifact_review',
   '{"subject_type":"social_post"}'::jsonb, true,
   'Vision + deterministic review of the rendered artifact before it can be published.',
   true, 'marketing', 'marketing_os', 'low', true, 'natural_key', 60, 2, 'exponential',
   null, false, true)
on conflict (action_class) do update set
  target = excluded.target, kind = excluded.kind, active = true, note = excluded.note;
