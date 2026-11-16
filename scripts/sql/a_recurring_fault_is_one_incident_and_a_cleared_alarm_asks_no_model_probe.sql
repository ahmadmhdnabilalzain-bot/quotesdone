-- PROBE for a_recurring_fault_is_one_incident_and_a_cleared_alarm_asks_no_model.sql (it_engineer, 16 Nov 2026, ledger 1557).
-- A pure probe: it always raises CHK<<...>>, so every row it writes is rolled back. LOCAL Postgres 16 only, never production.
-- Its own rows are new hand-overs whose issue keys start 'duty:heartbeat:zzprobe' / 'duty:sanctions:zzprobe' /
-- 'duty:latency_slo:zzprobe'; it touches no existing incident, finding or hand-over (it counts them before and after).
-- The founder address is replaced, inside the rolled-back transaction, by a reserved .invalid address and the mobile is
-- removed, so nothing it queues could reach a person even if the transaction committed.
-- Before the file: the first check fails ("2 incident rows for one cause"). After it: CHK<<PROBE OK ...>>.
do $p$
declare
  v_fail text := ''; v_before_inc int; v_before_fnd int; v_root bigint; v_r bigint; v_n int; v_j jsonb; v_kind text;
  h1 bigint; h2 bigint; h3 bigint; h4 bigint; h5 bigint; h6 bigint; h7 bigint; h8 bigint; h9 bigint; q1 bigint; q2 bigint; q3 bigint; q4 bigint;
  v_live timestamptz; v_live2 timestamptz;
  c_hb constant text := 'playbook:heartbeat_step:resilience_ping';
begin
  select count(*) into v_before_inc from public.it_incident where issue_key not like '%zzprobe%';
  select count(*) into v_before_fnd from public.it_engineer_finding where issue_key not like '%zzprobe%';

  -- the hand-overs, as fn_it_loop_open writes them (type, from, issue key, subject, title, severity, occurrence)
  create or replace function pg_temp.zz_handoff(p_key text, p_status text, p_sev text, p_at timestamptz, p_subject text default 'resilience_ping')
  returns bigint language plpgsql as $f$
  declare v bigint;
  begin
    insert into public.agent_actions (agent, kind, title, status, detail, evidence, decided_at, target_table, target_id)
    values ('it_engineer', 'handoff', 'probe ' || p_key, p_status,
            jsonb_build_object('type', 'it.finding', 'from', 'it_engineer', 'issue_key', p_key, 'subject', p_subject,
                               'title', 'probe step failed: ' || p_key, 'where_it_is', 'probe', 'severity', p_sev,
                               'occurrence_started_at', p_at),
            case when p_status = 'done' then '{"not_cited": {"reason": "probe", "by": "probe"}}'::jsonb else '{}'::jsonb end,
            case when p_status = 'done' then now() end, 'it_engineer_finding', p_key || '@' || extract(epoch from p_at)::bigint)
    returning id into v;
    return v;
  end $f$;

  -- 1. TWO OCCURRENCES OF ONE CAUSE (a heartbeat step failing, clearing, failing again) ARE ONE INCIDENT
  h1 := pg_temp.zz_handoff('duty:heartbeat:zzprobe_outbox', 'done', 'high', now() - interval '3 hours');
  h2 := pg_temp.zz_handoff('duty:heartbeat:zzprobe_whatsapp', 'done', 'high', now() - interval '2 hours');
  v_root := public.fn_it_incident_open(h1);
  v_r := public.fn_it_incident_open(h2);
  select count(*) into v_n from public.it_incident where issue_key like 'duty:heartbeat:zzprobe%';
  if v_n <> 1 then v_fail := v_fail || v_n || ' incident rows for one cause (want 1); '; end if;
  if v_r is distinct from v_root then v_fail := v_fail || 'the recurrence did not return the open incident; '; end if;
  select occurrences into v_n from public.it_incident where id = v_root;
  if v_n is distinct from 2 then v_fail := v_fail || 'occurrences ' || coalesce(v_n::text, 'null') || ' (want 2); '; end if;
  if (select cause_key from public.it_incident where id = v_root) is distinct from c_hb then v_fail := v_fail || 'cause_key not set at open; '; end if;
  if (select detail->>'incident_id' from public.agent_actions where id = h2) is distinct from v_root::text then
    v_fail := v_fail || 'the recurrence hand-over does not carry its incident; '; end if;
  -- asked again for the same hand-over: the same incident, never a second count
  perform public.fn_it_incident_open(h2);
  if (select occurrences from public.it_incident where id = v_root) is distinct from 2 then v_fail := v_fail || 'a repeated open counted twice; '; end if;

  -- 2. A DIFFERENT CAUSE KEEPS ITS OWN INCIDENT: a sanctions finding is never folded into the heartbeat (a true alarm stays visible)
  h3 := pg_temp.zz_handoff('duty:sanctions:zzprobe_hit', 'done', 'critical', now() - interval '1 hour', 'sanctions_screen');
  v_r := public.fn_it_incident_open(h3);
  if v_r is null or v_r = v_root or not exists (select 1 from public.it_incident where id = v_r and handoff_id = h3) then
    v_fail := v_fail || 'the sanctions occurrence did not open its own incident; '; end if;

  -- 3. A LIVE RECURRENCE REOPENS THE INCIDENT; IT CLOSES WHEN THE CAUSE MEASURES HEALTHY AGAIN
  if to_regprocedure('public.fn_it_incident_settle()') is null then
    raise exception 'CHK<<PROBE FAILED: %fn_it_incident_settle does not exist>>', v_fail;
  end if;
  update public.it_incident set ended_at = now() - interval '90 minutes' where id = v_root;
  perform public.fn_it_engineer_finding_upsert('duty:heartbeat:zzprobe_outbox', 'probe step failed: duty:heartbeat:zzprobe_outbox', 'probe',
    'agent_facing', 1, '{"subject": "resilience_ping"}'::jsonb, '{}', '{}', 'probe');
  select started_at into v_live from public.it_engineer_finding where issue_key = 'duty:heartbeat:zzprobe_outbox';
  h4 := pg_temp.zz_handoff('duty:heartbeat:zzprobe_outbox', 'pending', 'high', v_live);
  if public.fn_it_incident_open(h4) is distinct from v_root then v_fail := v_fail || 'the live recurrence opened a new incident; '; end if;
  if (select ended_at from public.it_incident where id = v_root) is not null then v_fail := v_fail || 'a live recurrence did not reopen it; '; end if;
  perform public.fn_it_incident_settle();
  if (select ended_at from public.it_incident where id = v_root) is not null then v_fail := v_fail || 'settle closed it while its cause is open; '; end if;
  perform public.fn_it_engineer_finding_close('duty:heartbeat:zzprobe_outbox', 'probe: healthy again');
  v_j := public.fn_it_incident_settle();
  if (select ended_at from public.it_incident where id = v_root) is null then v_fail := v_fail || 'settle left it open after the cause measured healthy; '; end if;
  if not (v_j->'incident_ids') @> to_jsonb(v_root) then v_fail := v_fail || 'settle did not name it; '; end if;
  -- fn_it_incident_impact_tick runs the settle every 15 minutes
  if public.fn_it_incident_impact_tick() ? 'settled' is not true then v_fail := v_fail || 'the 15-minute tick does not settle; '; end if;

  -- 4. QUIET FOR MORE THAN 24 HOURS, THE SAME CAUSE IS A NEW INCIDENT
  h5 := pg_temp.zz_handoff('duty:heartbeat:zzprobe_outbox', 'done', 'high', now() + interval '25 hours');
  v_r := public.fn_it_incident_open(h5);
  if v_r = v_root then v_fail := v_fail || 'a recurrence after 25 quiet hours was folded; '; end if;

  -- 5. A LIVE CUSTOMER-FACING OCCURRENCE NEVER COUNTS ON AN ENDED INCIDENT (it is a new outage, told on its own)
  h6 := pg_temp.zz_handoff('duty:latency_slo:zzprobe_portal', 'pending', 'critical', now() - interval '2 hours', 'customer_api');
  v_r := public.fn_it_incident_open(h6);
  update public.it_incident set ended_at = now() - interval '1 hour' where id = v_r;
  h7 := pg_temp.zz_handoff('duty:latency_slo:zzprobe_portal', 'pending', 'critical', now(), 'customer_api');
  if public.fn_it_incident_open(h7) = v_r then v_fail := v_fail || 'a live customer-facing outage was folded into an ended one; '; end if;

  -- 6. THE POSTMORTEM NEITHER RE-OPENS NOR ASKS ABOUT AN OCCURRENCE COUNTED ON AN OPEN INCIDENT
  h8 := pg_temp.zz_handoff('duty:heartbeat:zzprobe_archive', 'done', 'high', now() + interval '25 hours' + interval '10 minutes');
  v_j := public.fn_it_engineer_postmortem();
  if exists (select 1 from public.it_incident where handoff_id = h8) then v_fail := v_fail || 'the postmortem wrote a second incident row; '; end if;
  if coalesce((v_j->>'counted_on_an_open_incident')::int, 0) < 1 then v_fail := v_fail || 'the postmortem did not count it on the open incident: ' || v_j::text || '; '; end if;
  if exists (select 1 from public.reasoning_held_question where surface = 'it_engineer.postmortem' and subject->>'incident_id' is not null
              and (subject->>'incident_id')::bigint not in (select id from public.it_incident where same_cause_as is null)) then
    v_fail := v_fail || 'a postmortem was asked about a recurrence; '; end if;

  -- 7. THE MODEL REASONS ONLY WHILE SOMETHING IS WRONG: a CEO judgement of a finding that has cleared expires unasked
  insert into public.reasoning_held_question (seat, surface, question, request, reason, subject, dedupe_key)
          values ('ceo', 'ceo.it_finding', 'probe: judge finding ' || h4, '{}'::jsonb, 'probe', jsonb_build_object('handoff_id', h4, 'round', 1),
                  'ceo.it_finding:' || h4 || ':1') returning id into q1;
  perform public.fn_it_engineer_finding_upsert('duty:heartbeat:zzprobe_live', 'probe step failed: live', 'probe',
    'agent_facing', 1, '{"subject": "resilience_ping"}'::jsonb, '{}', '{}', 'probe');
  select started_at into v_live2 from public.it_engineer_finding where issue_key = 'duty:heartbeat:zzprobe_live';
  h9 := pg_temp.zz_handoff('duty:heartbeat:zzprobe_live', 'pending', 'high', v_live2);
  insert into public.reasoning_held_question (seat, surface, question, request, reason, subject, dedupe_key)
          values ('ceo', 'ceo.it_finding', 'probe: judge finding ' || h9, '{}'::jsonb, 'probe', jsonb_build_object('handoff_id', h9, 'round', 1),
                  'ceo.it_finding:' || h9 || ':1') returning id into q2;
  -- one postmortem per fault holds after a FAILED ask too
  insert into public.reasoning_held_question (seat, surface, question, request, reason, subject, status, attempts, last_attempt_at, dedupe_key)
          values ('it_engineer', 'it_engineer.postmortem', 'probe: root cause A', '{}'::jsonb, 'probe', '{"fault_key": "zzprobe:fault"}'::jsonb, 'failed', 3, now(), 'postmortem:zzprobe-a')
          returning id into q3;
  insert into public.reasoning_held_question (seat, surface, question, request, reason, subject, dedupe_key)
          values ('it_engineer', 'it_engineer.postmortem', 'probe: root cause B', '{}'::jsonb, 'probe', '{"fault_key": "zzprobe:fault"}'::jsonb, 'postmortem:zzprobe-b')
          returning id into q4;
  v_j := public.fn_reason_held_sweep();
  if (select status from public.reasoning_held_question where id = q1) <> 'expired' then v_fail := v_fail || 'a judgement of a cleared finding is still queued for a model; '; end if;
  if (select status from public.reasoning_held_question where id = q2) <> 'held' then v_fail := v_fail || 'a judgement of a live finding was dropped; '; end if;
  if (select status from public.reasoning_held_question where id = q4) <> 'expired' then v_fail := v_fail || 'a postmortem was asked again after its fault failed; '; end if;

  -- 8. EVERY ALARM HIS RULINGS STILL ROUTE TO HIM STILL REACHES HIM; AN IT FAULT NEVER MAILS HIM DIRECTLY
  delete from public.app_secrets where key in ('admin_emails', 'admin_mfa_phone');
  insert into public.app_secrets (key, value) values ('admin_emails', 'zz-probe-founder@example.invalid');
  foreach v_kind in array array['finance_reminder', 'unexpected_charge', 'backup_failed_after_retry', 'integration_reauth_needed',
                                'escalation_by_law', 'security_critical', 'platform_down', 'uptime_alert', 'person_request'] loop
    v_j := public.fn_notify_founder('ZZ DEMO probe ' || v_kind, 'probe', 'critical', v_kind, 'zzprobe:' || v_kind, 'customer_support');
    if not coalesce((v_j->>'emailed')::boolean, false)
       or not exists (select 1 from public.notifications where kind = v_kind and to_role = 'founder' and subject like '%ZZ DEMO probe ' || v_kind) then
      v_fail := v_fail || v_kind || ' no longer reaches the founder; '; end if;
  end loop;
  v_j := public.fn_notify_founder('ZZ DEMO probe it_new_bug', 'probe', 'high', 'it_new_bug', 'zzprobe:it_new_bug', 'customer_support');
  if coalesce((v_j->>'emailed')::boolean, true) then v_fail := v_fail || 'an IT bug emailed the founder directly; '; end if;

  -- nothing outside the probe's own rows moved
  if (select count(*) from public.it_incident where issue_key not like '%zzprobe%') <> v_before_inc then v_fail := v_fail || 'a real incident row changed count; '; end if;
  if (select count(*) from public.it_engineer_finding where issue_key not like '%zzprobe%') <> v_before_fnd then v_fail := v_fail || 'a real finding changed count; '; end if;

  if v_fail <> '' then raise exception 'CHK<<PROBE FAILED: %>>', v_fail; end if;
  raise exception 'CHK<<PROBE OK: one incident per cause (2 occurrences on incident %), healthy cause closes it, cleared alarm asks no model, 9 founder kinds kept>>', v_root;
end $p$;
