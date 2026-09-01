-- UNCLASSIFIED WORK ESCALATES INSTEAD OF ROTTING (autonomy audit, gap 15).
--
-- fn_agent_action_work_sweep queued/officer-routed/notified agent_actions that HAVE a policy, but an
-- emitted kind with NO agent_action_kind_policy row was only counted, never acted on — no employee owns
-- it and it cannot settle. The sweep now ESCALATES each unclassified item to the founder as a
-- classify-this notice (0 such rows today, so it notifies no one now). Body reproduced from live prosrc
-- with the escalate loop only; the auto/decision.* kinds still settle through the model-bound worker and
-- are unchanged. Refund routing is untouched.
--
--   node scripts/apply_sql.mjs scripts/sql/unclassified_work_escalates.sql --apply --ddl

begin;

CREATE OR REPLACE FUNCTION public.fn_agent_action_work_sweep(p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_q int := 0; v_officer int := 0; v_notify int := 0; r record; v_key text; v_escalated int := 0;
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

  -- OFFICER decisions: route to the accountable AI authority, never the founder. The determination
  -- itself is the authority's own work; this only makes the authority the owner and removes the
  -- founder as the bottleneck.
  for r in
    select a.id, p.authority_role,
           coalesce(ro.runtime_agent_key, p.authority_role) as authority_agent
      from public.agent_actions a
      join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'officer'
      left join public.org_role ro on ro.role_id = p.authority_role and ro.status = 'active'
     where a.status in ('pending','needs_review','held_for_review','proposed','open')
       and (a.detail->>'routed_at') is null
  loop
    update public.agent_actions
       set agent = coalesce(r.authority_agent, agent),
           escalated = true,
           escalation_reason =
             case when coalesce(escalation_reason,'') = '' then '' else escalation_reason || ' | ' end
             || 'routed to accountable AI authority ' || coalesce(r.authority_role,'(unset)')
             || ' — only refunds require the founder',
           detail = coalesce(detail,'{}'::jsonb) || jsonb_build_object(
                      'routed_at', now(),
                      'routed_to', coalesce(r.authority_agent, r.authority_role),
                      'route_basis', 'officer_policy')
     where id = r.id;
    v_officer := v_officer + 1;
  end loop;

  -- NOTIFY alerts: tell the founder (Stage 4), non-blocking, and hand the response to the authority.
  for r in
    select a.id, a.kind, a.title, a.recommendation, a.risk, a.agent, p.authority_role,
           coalesce(ro.runtime_agent_key, p.authority_role) as authority_agent
      from public.agent_actions a
      join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'notify'
      left join public.org_role ro on ro.role_id = p.authority_role and ro.status = 'active'
     where a.status in ('pending','needs_review','held_for_review','proposed','open')
       and (a.detail->>'routed_at') is null
  loop
    perform public.fn_notify_founder(
      coalesce(nullif(r.title,''), r.kind),
      coalesce(nullif(r.recommendation,''), nullif(r.title,''), r.kind)
        || E'\n\nRaised by ' || coalesce(r.agent,'?')
        || '. Handling owner: ' || coalesce(r.authority_role,'(unset)')
        || '. This is a notification — open the OS to review; no approval is required of you.',
      case when lower(coalesce(r.risk,'')) in ('high','critical') then 'high' else 'warn' end);
    update public.agent_actions
       set agent = coalesce(r.authority_agent, agent),
           detail = coalesce(detail,'{}'::jsonb) || jsonb_build_object(
                      'routed_at', now(),
                      'routed_to', coalesce(r.authority_agent, r.authority_role),
                      'route_basis', 'notify_policy',
                      'founder_notified_at', now())
     where id = r.id;
    v_notify := v_notify + 1;
  end loop;

  -- ESCALATE the unclassified: an emitted kind with no agent_action_kind_policy row is owned by no one,
  -- so the sweep can neither settle nor route it. Tell the founder it needs a classification rather than
  -- leaving it to rot unrouted. (0 such rows today, so this notifies no one now.)
  for r in
    select a.id, a.kind, a.title, a.recommendation, a.risk, a.agent from public.agent_actions a
     where a.status in ('pending','needs_review','held_for_review','proposed','open')
       and (a.detail->>'routed_at') is null
       and not exists (select 1 from public.agent_action_kind_policy p where p.kind = a.kind)
  loop
    perform public.fn_notify_founder(
      'Unclassified work item: ' || coalesce(nullif(r.kind,''),'(no kind)'),
      coalesce(nullif(r.title,''), r.kind) || E'

Raised by ' || coalesce(r.agent,'?')
        || '. This kind has no agent_action_kind_policy row, so no employee owns it and the sweep cannot '
        || 'settle or route it. Classify it (auto/officer/notify).',
      'warn');
    update public.agent_actions
       set escalated = true,
           escalation_reason = case when coalesce(escalation_reason,'')='' then '' else escalation_reason||' | ' end
                               || 'no agent_action_kind_policy for kind '||coalesce(r.kind,'(none)'),
           detail = coalesce(detail,'{}'::jsonb) || jsonb_build_object('routed_at', now(), 'route_basis', 'escalated_unclassified')
     where id = r.id;
    v_escalated := v_escalated + 1;
  end loop;

  return jsonb_build_object('queued', v_q, 'officer_routed', v_officer, 'notify_sent', v_notify, 'escalated', v_escalated,
    'ran_at', now(),
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
    -- No kind routes to the founder any more; this is retained as a tripwire and must read 0.
    'never_auto_settled', (select count(*) from public.agent_actions a
                             join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'founder'
                            where a.status = 'pending'),
    'unrouted', (select count(*) from public.agent_actions a
                  where a.status = 'pending'
                    and not exists (select 1 from public.agent_action_kind_policy p where p.kind = a.kind)));
end $function$
;

commit;
