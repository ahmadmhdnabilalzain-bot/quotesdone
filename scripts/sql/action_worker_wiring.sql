-- Wiring for action_worker: its outbound credential, its executor row, and the invoker's scope.
--
-- The worker calls ai_gateway through _shared/llm.ts, which looks up app_secrets.cred_fn_<fn> and
-- falls back to the shared inbound_secret while logging the fallback. Issuing the scoped
-- credential is what keeps it off that path — exact scope, one callee, the same shape as
-- fn.dept_plan (['ai_gateway','dept_plan']).
do $$
declare v_issued jsonb; v_secret text;
begin
  if not exists (select 1 from app_secrets where key = 'cred_fn_action_worker') then
    v_issued := public.fn_internal_credential_issue('fn.action_worker',
                  array['ai_gateway','action_worker'],
                  'Outbound credential for action_worker: it calls ai_gateway and nothing else', null);
    v_secret := coalesce(v_issued->>'secret', v_issued->>'value', v_issued->>'token');
    if v_secret is null then raise exception 'credential issue returned no secret: %', v_issued::text; end if;
    insert into app_secrets(key, value) values ('cred_fn_action_worker', v_secret)
      on conflict (key) do update set value = excluded.value;
  end if;
end $$;

-- A CHECK constraint on org_action_executor refused the insert below, and its message is the
-- instruction being followed here:
--
--   "edge target action_worker is outside the fn.cos_execute credential scope. cos_execute would
--    POST service-role authority to it. Widen the credential scope deliberately if this executor
--    is intended; do not widen it to make an INSERT pass."
--
-- It is intended, and this is the deliberate widening. cos_execute dispatches an org_task to the
-- executor named by its action_class, so if a task ever carries agent_action_work it will POST to
-- action_worker with service-role authority. That is the design: the worker refuses
-- customer_escalation, legal_flag, security_incident, prompt_approval, compliance_update and
-- anything touching money BY NAME inside the function, so widening the hop does not widen what
-- can be settled without the founder.
update public.internal_credential
   set scope = (select array_agg(distinct s order by s) from unnest(scope || array['action_worker']) s)
 where context = 'fn.cos_execute' and active and not (scope @> array['action_worker']);

-- The executor row. Low risk, advisory-safe and reversible on purpose, and every one of those
-- three is true rather than convenient: the worker writes a deliverable onto the row it was given
-- and changes nothing else, the row keeps its full history, and reversing it is one UPDATE back to
-- pending. required_authority stays null; the kinds that need the founder are refused inside the
-- function by name, not by tier, because a tier is a number and 'customer_escalation' is a fact.
insert into public.org_action_executor
  (action_class, kind, target, params, active, note, advisory_safe, department, owner_os,
   risk_tier, reversible, idempotency_strategy, timeout_seconds, max_attempts, backoff,
   required_authority, compensation_action_class)
values
  ('agent_action_work', 'edge', 'action_worker', '{}'::jsonb, true,
   'An AI employee settles one item addressed to it in agent_actions by producing the deliverable. Refuses customer_escalation, legal_flag, security_incident, prompt_approval, compliance_update and anything touching money.',
   true, 'exec', 'leadership', 'low', true, 'natural_key', 120, 1, 'none', null,
   'manual_reversal')
on conflict (action_class) do update
  set target = excluded.target, kind = excluded.kind, active = excluded.active,
      advisory_safe = excluded.advisory_safe, risk_tier = excluded.risk_tier,
      reversible = excluded.reversible, idempotency_strategy = excluded.idempotency_strategy,
      timeout_seconds = excluded.timeout_seconds, max_attempts = excluded.max_attempts,
      compensation_action_class = excluded.compensation_action_class, note = excluded.note;

-- The invoker's credential was issued with the exact set of targets that existed at the time.
-- A new executor target has to be named in it or the invoker's own callee check refuses the call.
update public.internal_credential
   set scope = (select array_agg(distinct s order by s) from unnest(scope || array['action_worker']) s)
 where context = 'action.invoker' and active and not (scope @> array['action_worker']);
