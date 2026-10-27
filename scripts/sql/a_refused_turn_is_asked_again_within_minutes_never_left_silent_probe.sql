-- PROBE for a_refused_turn_is_asked_again_within_minutes_never_left_silent.sql (customer_support + sales_engineer, 27 Oct 2026).
-- A pure probe: no DDL, so it ends with raise exception 'CHK<<...>>' and the whole transaction rolls back. It never calls
-- fn_reask_kick (no request leaves the database) and sends nothing; the rows it makes are ZZ DEMO, created with a
-- created_at in 2000 so they are claimed first, and they vanish with the rollback. Real rows claimed alongside have their
-- attempts restored by the same rollback.
-- It proves: a refused portal turn is claimed by the re-ask and NOT by the 15-minute think() replay; each refusal keeps
-- its problems; the third refusal hands it to sales_engineer (held_question item, portal row 'with_team'); a reviewed
-- reply comes back through the same door; 'sending' is granted once; a delivery closes the row and the seat's item.
do $probe$
declare v_log bigint; v_id bigint; v_stale bigint; v jsonb; r public.reasoning_held_question; v_fail text := ''; n int;
begin
  insert into public.assistant_logs (message, reply, seat, answered, conv_id, audience, path)
  values ('ZZ DEMO reask probe: what thickness for a wardrobe shelf?', null, 'sales_engineer', false, 'a-c-zz-demo-reask-probe', 'customer:zz-demo', 'portal:pending')
  returning id into v_log;
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, created_at)
  values ('sales_engineer', 'sales_engineer.portal_unwritten', 'ZZ DEMO reask probe: what thickness for a wardrobe shelf?',
          jsonb_build_object('seat', 'sales_engineer', 'surface', 'sales_engineer.portal_unwritten', 'question', 'ZZ DEMO reask probe',
            'context', jsonb_build_object('audience', 'customer', 'language', 'en', 'turn_id', 'portal:' || v_log),
            'reask', jsonb_build_object('message', 'ZZ DEMO reask probe', 'audience', 'customer', 'lang', 'en', 'problems', jsonb_build_array('the figure 450'))),
          '{}'::jsonb, jsonb_build_object('channel', 'portal', 'log_id', v_log), 'model_up_no_safe_reply', 'zz_demo_reask_probe:' || v_log,
          '2000-01-01T00:00:00Z')
  returning id into v_id;

  -- the 15-minute replay never claims it
  if public.fn_reason_held_due(10) @> jsonb_build_array(jsonb_build_object('id', v_id)) then v_fail := v_fail || ' think-replay-claimed-it;'; end if;
  -- fn_reason_held_due runs fn_reason_held_sweep, which expires a ZZ DEMO row as a fixture: put the probe's row back
  update public.reasoning_held_question set attempts = 0, last_attempt_at = null, status = 'held', result = null where id = v_id;

  for n in 1..3 loop
    v := public.fn_reask_due(20);
    if not v @> jsonb_build_array(jsonb_build_object('id', v_id)) then v_fail := v_fail || ' not-claimed-' || n || ';'; end if;
    v := public.fn_reask_record(v_id, jsonb_build_object('delivered', false, 'via', 'none', 'problems', jsonb_build_array('problem ' || n)));
    if n < 3 and v ->> 'status' <> 'asked_again_later' then v_fail := v_fail || ' attempt-' || n || '=' || (v ->> 'status') || ';'; end if;
    if n = 3 and v ->> 'status' <> 'handed_off' then v_fail := v_fail || ' third-not-handed-off=' || (v ->> 'status') || ';'; end if;
    update public.reasoning_held_question set last_attempt_at = now() - interval '2 minutes' where id = v_id;
  end loop;
  select * into r from public.reasoning_held_question where id = v_id;
  if r.status <> 'failed' or r.escalated_at is null then v_fail := v_fail || ' not-failed-and-escalated;'; end if;
  if jsonb_array_length(r.result -> 'reask_problems') <> 3 then v_fail := v_fail || ' problems-not-kept=' || coalesce(r.result ->> 'reask_problems', 'null') || ';'; end if;
  if not exists (select 1 from public.agent_actions where agent = 'sales_engineer' and kind = 'held_question' and status = 'pending' and target_id = v_id::text)
    then v_fail := v_fail || ' no-seat-item;'; end if;
  if (select path from public.assistant_logs where id = v_log) <> 'portal:with_team' then v_fail := v_fail || ' portal-not-with-team;'; end if;
  if public.fn_reask_due(20) @> jsonb_build_array(jsonb_build_object('id', v_id)) then v_fail := v_fail || ' claimed-after-hand-off;'; end if;

  -- the reviewed reply: same door, sent once
  perform public.fn_reask_reviewed_reply(v_id, 'ZZ DEMO reviewed reply', 'probe');
  if not public.fn_reask_due(20) @> jsonb_build_array(jsonb_build_object('id', v_id)) then v_fail := v_fail || ' reviewed-not-claimed;'; end if;
  if public.fn_reask_record(v_id, '{"phase":"sending"}') ->> 'status' <> 'sending' then v_fail := v_fail || ' sending-refused;'; end if;
  if public.fn_reask_record(v_id, '{"phase":"sending"}') ->> 'status' <> 'not_yours' then v_fail := v_fail || ' sending-granted-twice;'; end if;
  -- review of #1657: the run that LOST the claim records nothing; the winner's marker and the row stay as they were
  if public.fn_reask_record(v_id, '{"delivered":false,"via":"not_yours","detail":"probe"}') ->> 'status' <> 'not_yours' then v_fail := v_fail || ' lost-claim-recorded;'; end if;
  select * into r from public.reasoning_held_question where id = v_id;
  if not (r.result ? 'reask_sending_at') or r.escalated_at is null or r.status <> 'failed' then v_fail := v_fail || ' lost-claim-changed-the-row;'; end if;
  if public.fn_reask_record(v_id, '{"delivered":true,"via":"portal","reviewed":true}') ->> 'status' <> 'delivered' then v_fail := v_fail || ' not-delivered;'; end if;
  select * into r from public.reasoning_held_question where id = v_id;
  if r.status <> 'applied' then v_fail := v_fail || ' not-applied;'; end if;
  if exists (select 1 from public.agent_actions where kind = 'held_question' and status = 'pending' and target_id = v_id::text)
    then v_fail := v_fail || ' seat-item-left-open;'; end if;

  -- review of #1657: a send that started and never recorded is handed off ONCE and stops matching the kick (its marker
  -- moves to reask_send_unrecorded_at); while it was stale, fn_reask_any_due said a request was worth making
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, created_at, result)
  values ('sales_engineer', 'sales_engineer.portal_unwritten', 'ZZ DEMO reask probe: stale send', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('channel', 'portal', 'log_id', v_log), 'model_up_no_safe_reply', 'zz_demo_reask_probe_stale:' || v_log,
          '2000-01-01T00:00:00Z', jsonb_build_object('reask_sending_at', now() - interval '10 minutes'))
  returning id into v_stale;
  if not public.fn_reask_any_due() then v_fail := v_fail || ' stale-send-not-due;'; end if;
  perform public.fn_reask_due(20);
  select * into r from public.reasoning_held_question where id = v_stale;
  if r.status <> 'failed' or r.result ? 'reask_sending_at' or not (r.result ? 'reask_send_unrecorded_at') or r.notice_delivered_at is null
    then v_fail := v_fail || ' stale-send-not-cleared=' || coalesce(r.result::text, 'null') || ';'; end if;
  if exists (select 1 from public.reasoning_held_question where id = v_stale and (result ->> 'reask_sending_at')::timestamptz < now() - interval '5 minutes')
    then v_fail := v_fail || ' stale-send-still-matches-the-kick;'; end if;

  -- review of #1657: an outage gives the attempt back only in the turn's first 24 hours (bounded; no expires_at here)
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, created_at, attempts)
  values ('sales_engineer', 'sales_engineer.portal_unwritten', 'ZZ DEMO reask probe: old outage', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('channel', 'portal', 'log_id', v_log), 'model_up_no_safe_reply', 'zz_demo_reask_probe_old:' || v_log, '2000-01-01T00:00:00Z', 2),
         ('sales_engineer', 'sales_engineer.portal_unwritten', 'ZZ DEMO reask probe: new outage', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('channel', 'portal', 'log_id', v_log), 'model_up_no_safe_reply', 'zz_demo_reask_probe_new:' || v_log, now() - interval '1 minute', 2);
  perform public.fn_reask_record(h.id, '{"delivered":false,"via":"none","outage":true}')
     from public.reasoning_held_question h where h.dedupe_key in ('zz_demo_reask_probe_old:' || v_log, 'zz_demo_reask_probe_new:' || v_log);
  if (select attempts from public.reasoning_held_question where dedupe_key = 'zz_demo_reask_probe_old:' || v_log) <> 2
    then v_fail := v_fail || ' old-outage-gave-the-attempt-back;'; end if;
  if (select attempts from public.reasoning_held_question where dedupe_key = 'zz_demo_reask_probe_new:' || v_log) <> 1
    then v_fail := v_fail || ' new-outage-kept-the-attempt;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK: claimed by the re-ask only, 3 refusals kept and handed to sales_engineer, reviewed reply sent once, a lost claim changes nothing, a stale send is cleared once, an outage is given back for 24 h only'
                                   else 'PROBE FAILED:' || v_fail end;
end $probe$;
