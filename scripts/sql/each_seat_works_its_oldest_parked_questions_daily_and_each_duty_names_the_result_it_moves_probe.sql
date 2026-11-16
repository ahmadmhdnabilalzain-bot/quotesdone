-- each_seat_works_its_oldest_parked_questions_daily_and_each_duty_names_the_result_it_moves_probe.sql (ceo, OPS_LOOPS, 16 Nov 2026)
-- A pure probe, run AFTER the file in the SAME transaction on a LOCAL Postgres 16 (scripts/db/local_pg16.mjs), after
-- an_incident_is_one_per_cause_... and every_calendar_entry_... (the routines read their columns). It always aborts
-- (raise 'CHK<<...>>'), so nothing it writes survives. The model's answers are stubs handed to fn_reason_held_resolve;
-- nothing is sent to anyone. Run twice on 16 Nov 2026: PROBE OK.
do $probe$
declare
  v_h bigint; v_inc bigint; q_pm bigint; q_wa bigint; q_kr bigint; q_rc bigint; q_cl bigint; q_un bigint; q_again bigint;
  a_pm bigint; a_wa bigint; a_kr bigint; a_rc bigint; a_cl bigint; a_un bigint; a_again bigint; v_review bigint; v_res jsonb; r jsonb;
  v_ceo bigint; v_src bigint; v_short text[];
begin
  delete from public.agent_actions where kind = 'held_question';      -- the local cluster holds none; a clean start
  -- an incident whose postmortem question failed, as on production (196 such rows)
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('it_engineer', 'handoff', 'pending', 'high', 'Probe finding',
          jsonb_build_object('type', 'it.finding', 'from', 'it_engineer', 'severity', 'high', 'issue_key', 'duty:probe_backlog:1',
                             'title', 'Probe: a duty failed', 'occurrence_started_at', now() - interval '12 days'),
          'it_engineer_finding', 'it.finding:probe_backlog') returning id into v_h;
  v_inc := public.fn_it_incident_open(v_h);
  insert into public.reasoning_held_question (seat, surface, question, request, subject, status, attempts, created_at, reason)
  values ('it_engineer', 'it_engineer.postmortem', 'Postmortem: root cause?', jsonb_build_object('context', jsonb_build_object('audience', 'internal')),
          jsonb_build_object('incident_id', v_inc), 'failed', 5, now() - interval '12 days', 'probe') returning id into q_pm;
  insert into public.reasoning_held_question (seat, surface, question, request, subject, status, attempts, created_at, reason)
  values ('it_engineer', 'wa_inbound.unwritten_reply', 'ZZ DEMO a person asked', '{}'::jsonb, jsonb_build_object('phone', '+971500000001'), 'failed', 3, now() - interval '11 days', 'probe') returning id into q_wa;
  insert into public.reasoning_held_question (seat, surface, question, request, subject, status, attempts, created_at, reason)
  values ('it_engineer', 'it_engineer.knowledge_refresh', 'ZZ DEMO refresh entry 1', jsonb_build_object('decision', jsonb_build_object('name', 'x')), '{"k":1}'::jsonb, 'failed', 3, now() - interval '10 days', 'probe') returning id into q_kr;
  insert into public.reasoning_held_question (seat, surface, question, request, subject, status, attempts, created_at, reason)
  values ('it_engineer', 'it_engineer.root_cause', 'ZZ DEMO root cause', '{}'::jsonb, '{"k":2}'::jsonb, 'failed', 3, now() - interval '9 days', 'probe') returning id into q_rc;
  insert into public.reasoning_held_question (seat, surface, question, request, subject, status, attempts, created_at, reason)
  values ('it_engineer', 'it_engineer.ceo_revision', 'ZZ DEMO revision', '{}'::jsonb, '{"k":3}'::jsonb, 'held', 0, now() - interval '9 days', 'probe') returning id into q_cl;
  insert into public.reasoning_held_question (seat, surface, question, request, subject, status, attempts, created_at, reason)
  values ('it_engineer', 'it_engineer.ceo_revision', 'ZZ DEMO unclear', '{}'::jsonb, '{"k":4}'::jsonb, 'failed', 3, now() - interval '8 days', 'probe') returning id into q_un;
  insert into public.reasoning_held_question (seat, surface, question, request, subject, status, attempts, result, created_at, reason)
  values ('it_engineer', 'it_engineer.knowledge_refresh', 'ZZ DEMO refresh entry 2', '{}'::jsonb, '{"k":5}'::jsonb, 'failed', 3,
          jsonb_build_object('backlog_retried_at', now() - interval '3 days'), now() - interval '8 days', 'probe') returning id into q_again;
  -- the parked rows, as fn_reason_held_escalate files them
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id, created_at)
  select 'it_engineer', 'held_question', 'pending', 'low', 'A question held on ' || q.surface || ' needs you',
         jsonb_build_object('held_id', q.id, 'surface', q.surface, 'question', q.question), 'reasoning_held_question', q.id::text, q.created_at
    from public.reasoning_held_question q where q.id in (q_pm, q_wa, q_kr, q_rc, q_cl, q_un, q_again);
  select id into a_pm from public.agent_actions where kind = 'held_question' and detail->>'held_id' = q_pm::text;
  select id into a_wa from public.agent_actions where kind = 'held_question' and detail->>'held_id' = q_wa::text;
  select id into a_kr from public.agent_actions where kind = 'held_question' and detail->>'held_id' = q_kr::text;
  select id into a_rc from public.agent_actions where kind = 'held_question' and detail->>'held_id' = q_rc::text;
  select id into a_cl from public.agent_actions where kind = 'held_question' and detail->>'held_id' = q_cl::text;
  select id into a_un from public.agent_actions where kind = 'held_question' and detail->>'held_id' = q_un::text;
  select id into a_again from public.agent_actions where kind = 'held_question' and detail->>'held_id' = q_again::text;
  -- the earlier retry of q_again, as the queue's history holds it (a failed try replaces result, so the marker lives here)
  insert into public.agent_actions (agent, kind, status, risk, title, detail, evidence, target_table, target_id, created_at, decided_at)
  values ('it_engineer', 'held_question', 'dismissed', 'low', 'an earlier parked row', jsonb_build_object('held_id', q_again, 'surface', 'it_engineer.knowledge_refresh'),
          jsonb_build_object('verdict', 'asked again by the seat''s backlog review: probe', 'held_id', q_again, 'review_held_id', 0),
          'reasoning_held_question', q_again::text, now() - interval '20 days', now() - interval '3 days');

  -- 1. the seat's model is given its oldest overdue items, once
  r := public.fn_seat_backlog_review(8);
  select (detail->>'backlog_held_id')::bigint into v_review from public.agent_actions where id = a_pm;
  if v_review is null or (select surface from public.reasoning_held_question where id = v_review) is distinct from 'it_engineer.backlog_review' then
    raise exception 'CHK<<PROBE FAILED: the it_engineer''s backlog was not offered to its model: %>>', r; end if;
  if (select jsonb_array_length(request->'context'->'case'->'items') from public.reasoning_held_question where id = v_review) <> 7 then
    raise exception 'CHK<<PROBE FAILED: the question does not carry the seven items>>'; end if;
  if (select request->'context'->'case'->'items'->0->>'last_failure' is not distinct from null
             and request->'context'->'case'->'items'->0 ? 'a_person_is_waiting' from public.reasoning_held_question where id = v_review) is not true then
    raise exception 'CHK<<PROBE FAILED: an item lacks its facts>>'; end if;
  r := public.fn_seat_backlog_review(8);
  if (select count(*) from public.reasoning_held_question where surface = 'it_engineer.backlog_review') <> 1 then
    raise exception 'CHK<<PROBE FAILED: the same items were offered twice>>'; end if;

  -- 2. the model decides each item
  v_res := public.fn_reason_held_resolve(v_review, jsonb_build_object('status', 'answered', 'model', 'stub', 'answer', 'decided',
    'decision', jsonb_build_object('fields', jsonb_build_object(
      'item_' || a_pm, jsonb_build_object('value', 'answer: the duty timed out because its query scanned the whole table'),
      'item_' || a_wa, jsonb_build_object('value', 'answer: tell him his quote is ready'),
      'item_' || a_kr, jsonb_build_object('value', 'retry: the model outage of 10-13 Nov is over'),
      'item_' || a_rc, jsonb_build_object('value', 'raise: decide whether the vendor contract is renewed'),
      'item_' || a_cl, jsonb_build_object('value', 'close: superseded by the revision of 14 Nov'),
      'item_' || a_un, jsonb_build_object('value', 'maybe later'),
      'item_' || a_again, jsonb_build_object('value', 'retry: try again')))));
  if (v_res->>'status') is distinct from 'applied' then raise exception 'CHK<<PROBE FAILED: the review was not applied: %>>', v_res; end if;
  -- answer: the parked row is done and the postmortem's own surface wrote the cause
  if (select status from public.agent_actions where id = a_pm) is distinct from 'done'
     or (select cause from public.it_incident where id = v_inc) not like 'the duty timed out%' then
    raise exception 'CHK<<PROBE FAILED: the answered postmortem did not reach its incident>>'; end if;
  -- a person-facing answer is recorded, never applied (a days-old reply never reaches a person unreviewed)
  if (select status from public.reasoning_held_question where id = q_wa) is distinct from 'failed'
     or (select detail->>'draft_answer' from public.agent_actions where id = a_wa) is distinct from 'tell him his quote is ready'
     or (select status from public.agent_actions where id = a_wa) is distinct from 'pending'
     or (select detail->>'needs_founder' from public.agent_actions where id = a_wa) is distinct from 'true' then
    raise exception 'CHK<<PROBE FAILED: a person-facing answer was applied, lost or closed>>'; end if;
  -- retry: back to held with fresh tries, once
  if (select status || '/' || attempts from public.reasoning_held_question where id = q_kr) is distinct from 'held/0'
     or (select status from public.agent_actions where id = a_kr) is distinct from 'dismissed' then
    raise exception 'CHK<<PROBE FAILED: the retry did not put the question back>>'; end if;
  -- raise: a new item in the CEO's queue, due at once; the seat's row closed and pointing at it
  select (evidence->>'raised_to')::bigint into v_ceo from public.agent_actions where id = a_rc;
  if v_ceo is null or (select agent || '/' || status from public.agent_actions where id = v_ceo) is distinct from 'ceo/pending'
     or not (select detail ? 'overdue_at' from public.agent_actions where id = v_ceo) then
    raise exception 'CHK<<PROBE FAILED: the raise did not reach the CEO''s queue>>'; end if;
  -- close: the still-held question is expired with the seat's reason
  if (select status from public.reasoning_held_question where id = q_cl) is distinct from 'expired'
     or (select evidence->>'verdict' from public.agent_actions where id = a_cl) not like 'closed by the seat: superseded%' then
    raise exception 'CHK<<PROBE FAILED: the close did not carry its reason>>'; end if;
  -- an unclear answer is offered again tomorrow
  if (select status from public.agent_actions where id = a_un) is distinct from 'pending'
     or (select detail ? 'backlog_held_id' from public.agent_actions where id = a_un) then
    raise exception 'CHK<<PROBE FAILED: an unclear answer was acted on or not released>>'; end if;
  -- a second retry becomes a raise
  if (select status from public.agent_actions where id = a_again) is distinct from 'dismissed'
     or (select evidence->>'raised_to' from public.agent_actions where id = a_again) is null then
    raise exception 'CHK<<PROBE FAILED: a second retry was allowed>>'; end if;

  -- 3. a duty that ran on time but did not move its result is not on its clock in the CEO's verdict
  insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file, last_ok_at, last_started_at)
  values ('ceo.register_review', 'ceo', interval '1 day', 'fn_ceo_register_review', 'ZZ DEMO probe: the register review', 'scripts/sql/each_seat_works_its_oldest_parked_questions_daily_and_each_duty_names_the_result_it_moves.sql', now(), now())
  on conflict (duty) do update set last_ok_at = now(), enabled = true;
  insert into public.compliance_sources (authority, topic, url, active, last_checked_at)
  values ('ZZ DEMO authority', 'ZZ DEMO topic', 'https://example.invalid/', true, now() - interval '98 days') returning id into v_src;
  r := public.fn_seat_duty_results_measure();
  if (select met from public.seat_duty_result where duty = 'ceo.register_review') is not false then
    raise exception 'CHK<<PROBE FAILED: a stale register read as met: %>>', r; end if;
  r := public.fn_ceo_seat_senior_verdict(now());
  select shortfalls into v_short from public.seat_senior_verdict where seat = 'ceo' and week = date_trunc('week', now() at time zone 'Asia/Dubai')::date;
  if array_to_string(v_short, ' | ') not like '%did not move their result (ceo.register_review: active compliance sources not checked in 35 days%' then
    raise exception 'CHK<<PROBE FAILED: the verdict does not name the missed result: %>>', v_short; end if;
  -- the source is checked: the result is met and the shortfall is gone
  update public.compliance_sources set last_checked_at = now() where active;
  r := public.fn_seat_duty_results_measure();
  r := public.fn_ceo_seat_senior_verdict(now());
  select shortfalls into v_short from public.seat_senior_verdict where seat = 'ceo' and week = date_trunc('week', now() at time zone 'Asia/Dubai')::date;
  if array_to_string(v_short, ' | ') like '%ceo.register_review%' then
    raise exception 'CHK<<PROBE FAILED: a met result is still a shortfall: %>>', v_short; end if;
  -- a measurement older than 2 days counts as missed
  update public.seat_duty_result set measured_at = now() - interval '3 days' where duty = 'ceo.register_review';
  if not public.fn_seat_duty_result_missed('ceo.register_review', now()) then
    raise exception 'CHK<<PROBE FAILED: a stale measurement counted as met>>'; end if;

  raise exception 'CHK<<PROBE OK>>';
end $probe$;
