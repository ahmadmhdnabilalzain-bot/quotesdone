-- THE SPECIFIC SENDERS (6 Sep 2026). Companion to the_founder_is_emailed_exceptions_only.sql; founder's order:
-- "so many errors were sent to me from the engine."
--
-- MEASURED, notifications to the founder, 30 days to 6 Sep 2026, and what each routine here did about it:
--   fn_smoke               20 "data-integrity check failed" (6 sent, 14 expired in the stand-down), ONE body: it counted the
--                          6-10 WhatsApp rows waiting on an unapproved Twilio template as an email backlog. Counts email only.
--   fn_backup_watch        THREE emails for ONE missed backup on 4 Sep 08:00: its own "backup overdue" row, "[HIGH] Backup may
--                          have failed" from trg_page_high_agent_action, "[Attention] Backup may have failed" from
--                          fn_agent_action_work_sweep. The direct row goes; the agent_action is routed once (backup_alert);
--                          after 48h the backup_failed_after_retry kind, which the policy allows, reaches him once per 24h.
--   fn_handoff_watchdog    6 "Stalled handoff run #80/#82" — one real stall, H-W20-01-02, chief_revenue_officer to
--                          content_strategy_and_copy, unaccepted since 17 Aug. Now ONE org_task for the receiving role's
--                          department lead (growth: sales_director); a week-old stall may email him only if
--                          founder_mail_policy.handoff_stalled_7d allows (seeded: it does not).
--   fn_agent_action_work_sweep  10 "[Attention] Auth hardening review / Core legal documents missing / Customers have not
--                          accepted current terms / High-severity security events / Regulatory change" — each ending
--                          "no approval is required of you". The action's own kind is the policy key now.
--   fn_action_invoke_dispatch, fn_agent_remediation_escalate_consume, fn_org_task_sla_watch, fn_os_incident_watchdog
--                          0 emails in the window; they name their kind so the policy, not the caller, decides.
--
-- Every other line is the live definition (pg_get_functiondef, 6 Sep 2026).
--
--   node scripts/apply_sql.mjs scripts/sql/founder_mail_the_specific_senders.sql --apply

CREATE OR REPLACE FUNCTION public.fn_smoke()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_run bigint; v_owner text; v jsonb:='[]'::jsonb; v_fail int:=0; v_sig text;
  a int; b int; c int; d int; e int;
begin
  insert into agent_runs(agent,started_at) values('smoke',now()) returning id into v_run;
  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner from app_secrets where key='admin_emails';

  select count(*) into a from quotes q where q.status='revealed' and not exists(select 1 from transactions t where t.quote_id=q.id);
  if a>0 then v:=v||jsonb_build_object('check','revealed_quote_without_transaction','count',a); v_fail:=v_fail+1; end if;

  select count(*) into b from transactions where fee_status='paid' and coalesce(reveal_fee,0)<=0;
  if b>0 then v:=v||jsonb_build_object('check','paid_tx_zero_fee','count',b); v_fail:=v_fail+1; end if;

  -- 6 SEP 2026: EMAIL only. This counted the WhatsApp rows that wait on an unapproved Twilio template
  -- (the founder's input, not a broken write path) and paged him "data-integrity check failed" 20 times.
  select count(*) into c from notifications where status='queued' and channel='email' and created_at < now()-interval '2 hours';
  if c>0 then v:=v||jsonb_build_object('check','email_backlog_stuck','count',c); v_fail:=v_fail+1; end if;

  select count(*) into d from supplier_dues where coalesce(amount_due,0)<0 or amount_due is null;
  if d>0 then v:=v||jsonb_build_object('check','bad_due_amount','count',d); v_fail:=v_fail+1; end if;

  select count(*) into e from inquiries i where i.status='revealed' and not exists(select 1 from transactions t where t.inquiry_id=i.id);
  if e>0 then v:=v||jsonb_build_object('check','revealed_inquiry_without_tx','count',e); v_fail:=v_fail+1; end if;

  if v_fail>0 then
    insert into error_events(source,kind,severity,detail) values('smoke','integrity_violation','high',v);
    select coalesce(string_agg(x->>'check', ',' order by x->>'check'),'') into v_sig from jsonb_array_elements(v) x;
    if v_owner is not null and not exists(
         select 1 from notifications where type='smoke_alert'
           and created_at >= now() - interval '24 hours'
           and body like '%[sig:'||v_sig||']%') then
      insert into notifications(type,to_email,to_role,channel,subject,body)
        values('smoke_alert',v_owner,'admin','email','QuotesDone: data-integrity check failed',
          v_fail||' integrity check(s) failed: '||v::text||'. This usually means a recent change broke a write path. Open the IT agent. [sig:'||v_sig||']');
    end if;
  end if;
  update agent_runs set finished_at=now(),status='ok',counts=jsonb_build_object('checks',5,'failures',v_fail,'detail',v) where id=v_run;
  return jsonb_build_object('checks',5,'failures',v_fail,'detail',v);
end; $function$;

CREATE OR REPLACE FUNCTION public.fn_backup_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_last timestamptz; v_status text; v_stale boolean; v_owner text; v_open int;
begin
  select started_at, status into v_last, v_status
    from agent_runs where agent='backup' order by started_at desc limit 1;
  v_stale := (v_last is null) or (v_last < now() - interval '26 hours') or (coalesce(v_status,'')='error');
  if not v_stale then
    return jsonb_build_object('ok',true,'last',v_last,'status',v_status);
  end if;
  select count(*) into v_open from agent_actions
    where kind='backup_alert' and coalesce(status,'') in ('pending','needs_review')
  -- A DEDUPE WINDOW THE SAME LENGTH AS THE CHECK INTERVAL SUPPRESSES ON A KNIFE EDGE (13 Aug 2026).
  -- The backup was broken from 10 to 12 August and this watcher produced exactly ONE alert:
  -- agent_action 2662 at 2026-08-11 08:00:00.63, one email, still pending. The watcher runs daily
  -- at 08:00, and the previous row was 24 hours old minus a fraction of a second, so it was still
  -- inside `created_at > now() - 24 hours` and the second day's alert was skipped. Twenty hours is
  -- strictly shorter than the cadence, so a daily check always re-alerts on a continuing outage
  -- while a ten-minute caller still cannot spam.
      and created_at > now()-interval '20 hours';

  if v_open = 0 then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,target_table,detail)
    values('security','backup_alert','pending','high',
      'Backup may have failed or is overdue',
      'The daily logical backup has not completed successfully in the last 26 hours (last: '||coalesce(v_last::text,'never')||', status: '||coalesce(v_status,'unknown')||'). Check the backup function and logs. Managed daily backups and the Dropbox mirror remain as fallbacks.',
      'agent_runs', jsonb_build_object('last_backup',v_last,'last_status',v_status));
    insert into security_events(kind,severity,source,subject,detail)
    values('backup_overdue','high','backup','logical backup',
      jsonb_build_object('last_backup',v_last,'last_status',v_status));
    -- 6 SEP 2026: ONE page per event. The agent_action above is paged by trg_page_high_agent_action with the
    -- backup_alert kind, which founder_mail_policy routes to the IT operations engineer as one org_task; the
    -- direct notifications row that used to sit here was the second of THREE emails for one missed backup.
    -- AN OUTAGE THAT LASTS MUST GET LOUDER, NOT REPEAT ITSELF. One identical email a day says the
    -- same thing on day one and on day five, and the day-five reader has already filed the day-one
    -- copy. Past 48 hours this also raises a founder_alert and states the age in hours, which is
    -- the number that decides whether this is a hiccup or a company with no restorable backup.
    if v_last is null or v_last < now() - interval '48 hours' then
      -- backup_failed_after_retry is the kind the policy ALLOWS: two daily retries have failed and there may
      -- be no restorable backup. Once per 24h while it lasts, and it states the age in hours each time.
      perform public.fn_notify_founder(
        'Backup failing after retry: no successful backup for '
        || coalesce(round(extract(epoch from (now()-v_last))/3600)::text || ' hours', 'as long as there are records'),
        'The daily logical backup has now been failing for '
        || coalesce(round(extract(epoch from (now()-v_last))/3600)::text || ' hours', 'as long as there are records')
        || ' (last run: '||coalesce(v_last::text,'never')||', status: '||coalesce(v_status,'unknown')
        || '). This is past the point where one more day of silence is acceptable: verify the backup '
        || 'function itself, then run dr_drill to prove the newest backup still restores.',
        'critical', p_kind => 'backup_failed_after_retry', p_dedupe_key => 'backup_failed_after_retry');
    end if;

  end if;
  return jsonb_build_object('alerted',true,'last',v_last,'status',v_status,'existing_open',v_open);
end $function$;

-- ROUTINE REMOVED 7 September 2026. public.fn_handoff_watchdog was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


CREATE OR REPLACE FUNCTION public.fn_agent_action_work_sweep(p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
      case when lower(coalesce(r.risk,'')) in ('high','critical') then 'high' else 'warn' end,
      -- 6 SEP 2026: the action's own kind is the founder_mail_policy key (backup_alert, security_incident,
      -- legal_flag, ...). finance_alert is allowed; the rest open one org_task for the kind's owner role.
      p_kind => r.kind);
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
      'warn', p_kind => 'agent_action_unclassified');
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

CREATE OR REPLACE FUNCTION public.fn_action_invoke_dispatch(p_limit integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_req bigint; v_sent int := 0; v_refused int := 0; v_skipped int := 0;
        v_url text; v_secret text; v_ref text; v_key text;
        v_awaiting int := 0; v_appr record; v_resolved jsonb; v_entitled text;
        v_amount numeric; v_spend jsonb;   -- D8: amount-aware spend routing
begin
  select value into v_secret from app_secrets where key = 'cred_action_invoker';
  if v_secret is null then
    return jsonb_build_object('error', 'no cred_action_invoker credential', 'ran_at', now());
  end if;
  select value into v_ref from app_secrets where key = 'project_ref';
  if v_ref is null then
    select substring(command from 'https://([a-z]+)[.]supabase[.]co') into v_ref
      from cron.job where command like '%supabase.co/functions/v1/%' limit 1;
  end if;
  if v_ref is null then return jsonb_build_object('error','cannot determine project ref','ran_at',now()); end if;

  for r in
    select a.id, a.action_class, a.request, a.idempotency_key, a.attempts,
           e.target, e.kind, e.active, e.risk_tier, e.advisory_safe, e.reversible,
           e.required_authority, e.compensation_action_class, e.idempotency_strategy, e.params,
           e.notifies_human, e.unattended_ok, e.department, e.second_authority,
           coalesce(e.timeout_seconds, 60) timeout_seconds, coalesce(e.max_attempts, 1) max_attempts
      from public.action_execution a
      join public.org_action_executor e on e.action_class = a.action_class
     where a.status = 'queued' and e.kind = 'edge'
     order by a.created_at
     limit greatest(coalesce(p_limit, 5), 1)
  loop
    -- ---- D9.1: a queuing employee blocked by an open remediation cannot act autonomously ----------
    if coalesce(r.request->>'actor','') <> ''
       and coalesce((public.fn_agent_autonomy_blocked(r.request->>'actor')->>'blocked')::boolean, false) then
      update public.action_execution
         set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','refused','at',now(),
               'reason','the queuing employee ('||(r.request->>'actor')||') is blocked from autonomous action by an open remediation')
       where id = r.id;
      v_refused := v_refused + 1;
      continue;
    end if;

    -- ---- absolute refusals: inactive, founder-reserved (refunds), irreversible-with-no-undo -----
    if not r.active
       or coalesce(r.required_authority,'') = 'founder'
       or (not r.reversible and r.compensation_action_class is null) then
      update public.action_execution
         set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker', 'refused', 'at', now(),
               'reason', case
                 when not r.active then 'executor row is inactive'
                 when coalesce(r.required_authority,'') = 'founder' then 'reserved to the founder'
                 else 'not reversible and declares no compensation_action_class' end)
       where id = r.id;
      v_refused := v_refused + 1;
      continue;
    end if;

    -- ---- D8.2: a request carrying an amount must clear fn_check_spend before anything else ---------
    v_amount := coalesce(nullif(r.request->>'amount_aed',''), nullif(r.request->>'amount',''))::numeric;
    if v_amount is not null then
      v_spend := public.fn_check_spend(coalesce(r.department,'finance'), v_amount, r.request->>'actor');
      if not coalesce((v_spend->>'ok')::boolean, false) then
        update public.action_execution
           set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                 'invoker','refused','at',now(),'reason',v_spend->>'reason','spend',v_spend)
         where id = r.id;
        v_refused := v_refused + 1;
        continue;
      elsif (v_spend->>'route_to') = 'founder' then
        update public.action_execution
           set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                 'invoker','awaiting_founder_approval','at',now(),
                 'reason','spend over AED 10,000 is the founder''s to authorise, not an AI head''s','spend',v_spend)
         where id = r.id;
        begin
          perform public.fn_notify_founder('Spend approval needed: '||r.action_class||' AED '||v_amount,
            coalesce(v_spend->>'reason',''), 'high', p_kind => 'spend_approval_needed');
        exception when others then null; end;
        v_awaiting := v_awaiting + 1;
        continue;
      else
        update public.action_execution set response = coalesce(response,'{}'::jsonb) || jsonb_build_object('spend', v_spend)
         where id = r.id;
      end if;
    end if;

    -- ---- the AI-managerial middle tier. D8.3: a named second_authority always forces this branch ---
    if r.second_authority is not null
       or not (r.risk_tier = 'low' and r.advisory_safe and r.reversible
               and not (coalesce(r.notifies_human,false) and not coalesce(r.unattended_ok,false))) then
      select * into v_appr from public.action_approval where action_execution_id = r.id;

      if found and v_appr.approval_decision = 'approved' and v_appr.consumed_at is null
         and (r.second_authority is null or v_appr.second_approval_decision = 'approved') then
        update public.action_approval set consumed_at = now() where action_execution_id = r.id;
      elsif found and (v_appr.approval_decision = 'rejected'
                       or v_appr.second_approval_decision = 'rejected') then
        update public.action_execution
           set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                 'invoker','refused','at',now(),
                 'approver', coalesce(v_appr.approver_role, v_appr.second_approver_role),
                 'reason','an accountable AI approver rejected this action: '
                          ||coalesce(nullif(v_appr.reason,''),'no reason recorded'))
         where id = r.id;
        v_refused := v_refused + 1;
        continue;
      else
        v_resolved := public.fn_action_resolve_approver(r.department, r.risk_tier);
        v_entitled := v_resolved->>'approver';
        insert into public.action_approval
          (action_execution_id, action_class, department, accountable_approver,
           approval_decision, risk_tier, authority_basis, second_authority, second_approval_decision)
        values (r.id, r.action_class, r.department, coalesce(v_entitled,'(unresolved)'),
                'requested', r.risk_tier, v_resolved->>'basis', r.second_authority,
                case when r.second_authority is not null then 'requested' end)
        on conflict (action_execution_id) do nothing;
        update public.action_execution
           set response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
                 'invoker', case when r.second_authority is not null then 'awaiting_two_approvals'
                                 else 'awaiting_head_approval' end,
                 'at',now(), 'entitled_approver', v_entitled,
                 'second_authority', r.second_authority, 'risk_tier', r.risk_tier,
                 'basis', v_resolved->>'basis')
         where id = r.id;
        v_awaiting := v_awaiting + 1;
        continue;
      end if;
    end if;

    -- ---- idempotency ------------------------------------------------------------------------------
    v_key := coalesce(nullif(btrim(r.idempotency_key),''),
                      r.action_class || ':' || md5(coalesce(r.request::text,'')));
    if r.idempotency_strategy is distinct from 'none_read_only'
       and exists (select 1 from public.action_execution x
                    where x.id <> r.id and x.status = 'succeeded'
                      and x.idempotency_key = v_key
                      and x.finished_at > now() - interval '24 hours') then
      update public.action_execution
         set status = 'succeeded', finished_at = now(),
             response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
               'invoker','deduplicated','at',now(),'idempotency_key',v_key,
               'strategy', r.idempotency_strategy)
       where id = r.id;
      v_skipped := v_skipped + 1;
      continue;
    end if;

    v_url := 'https://' || v_ref || '.supabase.co/functions/v1/' || r.target;
    select net.http_post(
             url := v_url,
             headers := '{"Content-Type":"application/json"}'::jsonb,
             body := coalesce(r.params, '{}'::jsonb) || coalesce(r.request, '{}'::jsonb)
                     || jsonb_build_object('__secret', v_secret),
             timeout_milliseconds := r.timeout_seconds * 1000)
      into v_req;

    update public.action_execution
       set status = 'running', attempts = coalesce(attempts,0) + 1,
           executor = r.target, idempotency_key = v_key,
           started_at = coalesce(started_at, now()),
           response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
             'invoker','dispatched','at',now(),'net_request_id',v_req,'url',v_url,
             'timeout_seconds', r.timeout_seconds, 'attempt', coalesce(r.attempts,0)+1,
             'max_attempts', r.max_attempts)
     where id = r.id;
    v_sent := v_sent + 1;
  end loop;

  return jsonb_build_object('dispatched', v_sent, 'refused', v_refused,
                            'deduplicated', v_skipped, 'awaiting_approval', v_awaiting, 'ran_at', now());
end $function$;

-- ROUTINE REMOVED 7 September 2026. public.fn_agent_remediation_escalate_consume was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ROUTINE REMOVED 7 September 2026. public.fn_org_task_sla_watch was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ROUTINE REMOVED 7 September 2026. public.fn_os_incident_watchdog was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

