-- fn_agent_action_work_sweep: A HELD AGENT ACTION ALWAYS ENDS WITH AN OWNER WHO IS NOT THE FOUNDER.
--
-- Measured on production 5 Sep 2026 22:31Z: 13 agent_actions pending + 1 needs_review, none a refund,
-- the oldest from 17 August. agent_action_kind_policy says every one of their kinds is 'auto' (execute),
-- 'notify' (a fact he is told) or 'officer' (an AI authority's determination). The sweep already routed
-- them — and then left every row at 'pending', which is the state the OS shows him as a decision of his:
--
--   auto    the action_worker ran (action_execution 'succeeded') and answered worked:0 — "no company
--           playbook covers this item; awaiting a specialist or the ~5% model path" — and the row stayed
--           pending with nobody named. One more (3913) had its execution CANCELLED by launch_safe_unblock,
--           and the idempotency key it left behind meant the sweep could never queue it again. One more
--           (6409) is addressed to an employee no longer active, so the queueing join skipped it forever.
--   notify  fn_notify_founder was called, detail.routed_at was stamped, status stayed 'pending'.
--   officer detail.routed_at was stamped, status stayed 'pending' (0 such rows today).
--
-- What changes, all inside this one routine so the sweep and its settlement cannot drift:
--   1. FIXTURES are cancelled with the reason 'fixture' (ZZ DEMO / example.invalid); a demo row is never
--      real work and must not open a real task.
--   2. AUTO kinds the worker could not settle are handed to their owner through the org_task lane:
--      an objective_step that already names an org_task is settled on that task's fact (auto_done when the
--      task is closed; superseded by the task when the lane still owns it — the same work is not opened
--      twice); everything else opens ONE org_task in the addressee's department, assigned to the addressee
--      (or the department head), and the action row is superseded by it. The worker's own verdict is the
--      trigger: a finished execution (succeeded/failed/cancelled) with the row still pending, an addressee
--      who is no longer active, or two failed attempts.
--   3. NOTIFY kinds: the founder is told exactly as before (non-blocking) AND the accountable authority
--      role receives the response as an org_task; the row closes at status 'notified'.
--   4. OFFICER kinds: the accountable authority role receives the determination as an org_task; the row
--      is superseded by it.
--   5. Proposed decision_records are routed through fn_decision_record_route on the same tick.
--
-- Every settled row carries detail.settled_reason, settled_by and (when one was opened) org_task_id.
-- Nothing here writes 'done': a deliverable is still the worker's or the lane's to produce.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_agent_action_work_sweep_held_rows_go_to_their_owners.sql --apply

-- The one place an agent_action becomes an org_task. Resolves the owner (the addressee when active, else
-- the head of the addressee's department, else the executive office) and opens the task assigned there.
create or replace function public.fn_agent_action_hand_to_owner(p_action_id bigint, p_owner text, p_basis text)
returns bigint
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare a record; v_owner text; v_dept text; v_task bigint;
begin
  select * into a from public.agent_actions where id = p_action_id;
  if not found then return null; end if;

  v_owner := coalesce(public.fn_org_agent_resolve(p_owner), public.fn_org_agent_resolve(a.agent));
  select o.department into v_dept from public.org_agents o where o.agent_key = v_owner and o.active;
  if v_dept is null or not exists (select 1 from public.org_departments x where x.dept_key = v_dept and x.active) then
    v_dept := 'exec';
    select x.lead_agent into v_owner from public.org_departments x where x.dept_key = 'exec';
  end if;
  if not exists (select 1 from public.org_agents o where o.agent_key = v_owner and o.active and coalesce(o.available, true)) then
    v_owner := null;   -- a05_org_task_fill_ownership picks the least-loaded colleague
  end if;

  insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, decided_by,
                                action_class, assigned_agent, priority, result)
  values (v_dept, left(coalesce(nullif(a.title, ''), a.kind), 200),
          '[agent_action:' || a.id || '] ' || coalesce(nullif(a.recommendation, ''), a.title, a.kind)
            || E'\n\nRaised by ' || coalesce(a.agent, '?') || ' as ' || a.kind || ' at ' || a.created_at
            || '. ' || p_basis
            || ' Determine it from company knowledge or park it with a reason; only a Stripe refund reaches the founder.',
          'assigned', 'advisory', false, 'fn_agent_action_work_sweep',
          'analysis', v_owner, case when lower(coalesce(a.risk, '')) in ('high', 'critical') then 2 else 1 end,
          jsonb_build_object('source', jsonb_build_object('agent_action_id', a.id, 'kind', a.kind,
                             'basis', p_basis, 'handed_at', now())))
  returning id into v_task;
  return v_task;
end
$function$;

create or replace function public.fn_agent_action_work_sweep(p_limit integer default 10)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_q int := 0; v_officer int := 0; v_notify int := 0; r record; v_key text; v_escalated int := 0;
        v_fixture int := 0; v_on_fact int := 0; v_handed int := 0; v_notified int := 0; v_officer_handed int := 0;
        v_task bigint; v_tstatus text; v_tagent text; v_tsummary text; v_reason text; v_decisions jsonb;
begin
  -- 1. a fixture is never real work
  update public.agent_actions a
     set status = 'cancelled', decided_at = now(), decided_by = 'fn_agent_action_work_sweep',
         detail = coalesce(a.detail, '{}'::jsonb) || jsonb_build_object(
           'settled_reason', 'fixture', 'settled_by', 'fn_agent_action_work_sweep', 'settled_at', now())
   where a.status in ('pending', 'needs_review')
     and (a.title ilike '%ZZ DEMO%' or a.title ilike '%example.invalid%'
          or a.recommendation ilike '%ZZ DEMO%' or a.detail::text ilike '%example.invalid%' or a.detail::text ilike '%ZZ DEMO%');
  get diagnostics v_fixture = row_count;

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

  -- 2. AUTO kinds the worker could not settle go to their owner through the org_task lane
  for r in
    select a.id, a.kind, a.agent, a.detail, a.status, a.escalation_reason,
           nullif(regexp_replace(coalesce(a.detail->>'task_id', ''), '[^0-9]', '', 'g'), '')::bigint as task_id,
           exists (select 1 from public.org_agents o where o.agent_key = a.agent and o.active) as agent_active,
           (select count(*) from public.action_execution x
             where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
               and x.status in ('succeeded', 'failed', 'cancelled')) as finished,
           (select count(*) from public.action_execution x
             where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
               and x.status = 'failed') as failures,
           (select string_agg(left(coalesce(x.response::text, x.status), 300), ' | ')
              from public.action_execution x
             where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')) as verdict
      from public.agent_actions a
      join public.agent_action_kind_policy p on p.kind = a.kind and p.policy = 'auto'
     where a.status in ('pending', 'needs_review')
       and not exists (select 1 from public.action_execution x
                        where x.idempotency_key in ('agent_action:' || a.id, 'agent_action:' || a.id || '#2')
                          and x.status in ('queued', 'running'))
     order by a.created_at
  loop
    -- a pending row nobody has attempted is the worker's turn; a needs_review row was held by the action
    -- gate and the worker never takes it, so its review IS the hand-off
    continue when r.status = 'pending' and r.agent_active and r.finished = 0 and r.failures < 2;

    v_task := null; v_tstatus := null;
    if r.task_id is not null then
      select o.id, o.status, coalesce(o.assigned_agent, o.dept_key),
             left(coalesce(o.result->>'summary', o.result->>'deliverable', o.result->'parked'->>'note', ''), 300)
        into v_task, v_tstatus, v_tagent, v_tsummary
        from public.org_tasks o where o.id = r.task_id;
    end if;

    if v_task is not null and v_tstatus in ('done', 'cancelled') then
      v_reason := 'the org_task this reported on (' || v_task || ') is ' || v_tstatus || ' by ' || v_tagent
                  || case when coalesce(v_tsummary, '') = '' then '' else ': ' || v_tsummary end;
      update public.agent_actions
         set status = 'auto_done', decided_at = now(), decided_by = 'fn_agent_action_work_sweep',
             detail = coalesce(detail, '{}'::jsonb) || jsonb_build_object(
               'org_task_id', v_task, 'settled_reason', v_reason,
               'settled_by', 'fn_agent_action_work_sweep', 'settled_at', now())
       where id = r.id;
      v_on_fact := v_on_fact + 1;
    else
      if v_task is null then
        v_task := public.fn_agent_action_hand_to_owner(r.id, r.agent,
                    case when r.status = 'needs_review'
                         then 'The action gate held it for review (' || coalesce(left(r.escalation_reason, 300), 'no reason recorded') || ').'
                         else 'The action_worker could not settle it (' || coalesce(left(r.verdict, 400),
                                case when r.agent_active then 'no attempt recorded' else 'the addressee is no longer an active employee' end) || ').' end);
        v_reason := 'handed to the org_task lane as org_task ' || v_task
                    || case when r.status = 'needs_review' then ': the action gate held it for review and the department is the reviewer'
                            else ': the worker found no company playbook covering it' end
                    || case when r.agent_active then '' else ' and ' || coalesce(r.agent, '?') || ' is no longer an active employee' end;
        v_handed := v_handed + 1;
      else
        v_reason := 'org_task ' || v_task || ' owns this work in the lane (status ' || v_tstatus || ', ' || v_tagent || ')'
                    || case when coalesce(v_tsummary, '') = '' then '' else ': ' || v_tsummary end;
        v_on_fact := v_on_fact + 1;
      end if;
      update public.agent_actions
         set status = 'superseded', decided_at = now(), decided_by = 'fn_agent_action_work_sweep',
             detail = coalesce(detail, '{}'::jsonb) || jsonb_build_object(
               'org_task_id', v_task, 'superseded_by', 'org_task:' || v_task, 'settled_reason', v_reason,
               'settled_by', 'fn_agent_action_work_sweep', 'settled_at', now())
       where id = r.id;
    end if;
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

  -- 3 and 4. a routed notify/officer row is not settled until the authority role HOLDS it: the response
  -- (notify) or the determination (officer) is an org_task assigned to that role's employee, and the
  -- action row closes — 'notified' for a fact he was told, 'superseded' by the task for a determination.
  for r in
    select a.id, a.kind, a.agent, p.policy, p.authority_role,
           coalesce(a.detail->>'routed_to', ro.runtime_agent_key, p.authority_role) as authority_agent
      from public.agent_actions a
      join public.agent_action_kind_policy p on p.kind = a.kind and p.policy in ('notify', 'officer')
      left join public.org_role ro on ro.role_id = p.authority_role and ro.status = 'active'
     where a.status in ('pending','needs_review','held_for_review','proposed','open')
       and (a.detail->>'routed_at') is not null
     order by a.created_at
  loop
    v_task := public.fn_agent_action_hand_to_owner(r.id, r.authority_agent,
                case when r.policy = 'notify'
                     then 'Policy notify: the founder has been told; the response is ' || coalesce(r.authority_role, 'the accountable role') || '''s to own.'
                     else 'Policy officer: the determination is ' || coalesce(r.authority_role, 'the accountable role') || '''s to make, never the founder''s.' end);
    update public.agent_actions
       set status = case when r.policy = 'notify' then 'notified' else 'superseded' end,
           decided_at = now(), decided_by = 'fn_agent_action_work_sweep',
           detail = coalesce(detail, '{}'::jsonb) || jsonb_build_object(
             'org_task_id', v_task, 'superseded_by', 'org_task:' || v_task,
             'settled_reason', case when r.policy = 'notify'
               then 'notified: the founder was told and the response is owned by ' || coalesce(r.authority_role, '?') || ' as org_task ' || v_task
               else 'handed to accountable authority ' || coalesce(r.authority_role, '?') || ' as org_task ' || v_task end,
             'settled_by', 'fn_agent_action_work_sweep', 'settled_at', now())
     where id = r.id;
    if r.policy = 'notify' then v_notified := v_notified + 1; else v_officer_handed := v_officer_handed + 1; end if;
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
      coalesce(nullif(r.title,''), r.kind) || E'\n\nRaised by ' || coalesce(r.agent,'?')
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

  -- 5. proposed decisions go to their department on the same tick
  begin
    v_decisions := public.fn_decision_record_route(null);
  exception when others then
    v_decisions := jsonb_build_object('error', sqlerrm);
  end;

  return jsonb_build_object('queued', v_q, 'officer_routed', v_officer, 'notify_sent', v_notify, 'escalated', v_escalated,
    'fixtures_cancelled', v_fixture, 'settled_on_task_fact', v_on_fact, 'handed_to_owner', v_handed,
    'notified', v_notified, 'officer_handed', v_officer_handed, 'decision_records', v_decisions,
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
end $function$;
