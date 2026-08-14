-- video_produce needs a credential and an entry point.
--
-- Same two doors as artifact_review and agent_train: action.invoker holds the HTTP-invoker
-- credential, and fn_org_action_executor_guard requires the target inside fn.cos_execute's
-- scope because cos_execute is what POSTs service-role authority to an edge executor.
--
-- It also calls artifact_review and ai_gateway, so its own outbound credential needs those.
update internal_credential
   set scope = (select array_agg(distinct x) from unnest(scope || array['video_produce','artifact_review']) x)
 where context in ('action.invoker', 'fn.cos_execute')
   and not ('video_produce' = any(scope) and 'artifact_review' = any(scope));

insert into org_action_executor
  (action_class, kind, target, params, active, note, advisory_safe, department, owner_os,
   risk_tier, reversible, idempotency_strategy, timeout_seconds, max_attempts, backoff,
   required_authority, notifies_human, unattended_ok)
values
  ('video.produce', 'edge', 'video_produce',
   '{"platform":"instagram","kind":"reel","attempts":2}'::jsonb, true,
   'Generates a video, reviews the real frames, and rewrites its own prompt from the named failures. Publishes nothing: the publish gate is separate and still applies.',
   true, 'marketing', 'marketing_os', 'low', true, 'natural_key', 300, 1, 'exponential',
   null, false, true)
on conflict (action_class) do update set
  target = excluded.target, kind = excluded.kind, active = true, note = excluded.note;
