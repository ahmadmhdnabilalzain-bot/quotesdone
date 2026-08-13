-- A FAILED ATTEMPT WAS A LIFE SENTENCE
--
-- Ask whether a recovery path has ever actually run, and for this one the answer is that it does
-- not exist. `fn_agent_action_work_sweep` skips any agent_action that already has an
-- action_execution row — ANY row, at any status, deliberately:
--
--     -- ALL statuses, not just the live ones: idempotency_key is UNIQUE, so an item that already
--     -- FAILED once collides on re-sweep. Cycle 3 of the first drain died on 23505 for exactly
--     -- that. A failed attempt is a recorded attempt.
--
-- The reasoning is sound and the consequence was not noticed: **one failure is permanent**. The
-- item stays `pending` for ever, the sweep will never look at it again, and nothing anywhere says
-- so. Measured on production just now: **10 auto-policy rows are pending and blocked by a failed
-- attempt with no live or succeeded attempt beside it.**
--
-- Eight of those ten failed for one reason, and it was ours: the 70-second client timeout against a
-- ceiling that had been raised to 8,000 tokens (see the same commit). We hung up on eight employees
-- mid-sentence, recorded "the model returned nothing", and made that verdict final.
--
-- The fix keeps the property the comment was protecting — the key is UNIQUE and must stay unique —
-- by making the key carry the attempt: `agent_action:<id>` then `agent_action:<id>#2`. Two attempts
-- and no more, so an item that genuinely cannot be settled stops rather than looping on the bill.
-- After the second failure it stays pending, which is correct and is now VISIBLE, because
-- fn_founder_queue's `machine_is_working_on` counts it and the daily brief prints the total.
create or replace function public.fn_agent_action_work_sweep(p_limit integer default 10)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_q int := 0; r record; v_key text;
begin
  for r in
    select a.id, a.kind,
           (select count(*) from public.action_execution x
             where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
               and x.status = 'failed') as failures
      from public.agent_actions a
      join public.org_agents o on o.agent_key = a.agent and o.active
      join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
     where a.status = 'pending'
       -- Nothing live and nothing already settled for this item...
       and not exists (select 1 from public.action_execution x
                        where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
                          and x.status in ('queued','running','succeeded'))
       -- ...and fewer than two attempts have failed. Equality, not LIKE: `_` is a single-character
       -- wildcard in LIKE and 'agent_action:' is full of them, so `like 'agent_action:'||id` would
       -- also match keys this function never wrote.
       and (select count(*) from public.action_execution x
             where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
               and x.status = 'failed') < 2
     order by a.created_at
     limit greatest(coalesce(p_limit, 10), 1)
  loop
    v_key := 'agent_action:' || r.id || case when r.failures >= 1 then '#2' else '' end;
    insert into public.action_execution(id, correlation_id, action_class, executor, idempotency_key,
                                        risk_tier, reversible, request, status, attempts)
    values (gen_random_uuid(), gen_random_uuid(), 'agent_action_work', 'action_worker',
            v_key, 'low', true,
            jsonb_build_object('action_id', r.id, 'kind', r.kind,
                               'source', 'fn_agent_action_work_sweep',
                               'attempt', r.failures + 1),
            'queued', 0)
    on conflict (idempotency_key) do nothing;
    v_q := v_q + 1;
  end loop;

  return jsonb_build_object('queued', v_q, 'ran_at', now(),
    'eligible_remaining', (select count(*) from public.agent_actions a
                             join public.org_agents o on o.agent_key = a.agent and o.active
                             join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
                            where a.status = 'pending'
                              and not exists (select 1 from public.action_execution x
                                               where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
                                                 and x.status in ('queued','running','succeeded'))
                              and (select count(*) from public.action_execution x
                                    where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
                                      and x.status = 'failed') < 2),
    -- Named separately so "we have stopped trying" is never counted as "we are working on it".
    'exhausted_two_attempts', (select count(*) from public.agent_actions a
                                 join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
                                where a.status = 'pending'
                                  and (select count(*) from public.action_execution x
                                        where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
                                          and x.status = 'failed') >= 2),
    'never_auto_settled', (select count(*) from public.agent_actions a
                             join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'founder'
                            where a.status = 'pending'),
    'unrouted', (select count(*) from public.agent_actions a
                  where a.status = 'pending'
                    and not exists (select 1 from public.agent_action_kind_policy p where p.kind = a.kind)));
end $function$;
