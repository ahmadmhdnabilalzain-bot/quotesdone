-- PROBE for an_order_is_a_conversation_until_its_outcome.sql. Seat: ceo. It always raises CHK<<...>>, so every row it writes is
-- rolled back. Its world is its own (qd.duty_fixtures = 'on': only demo rows are read; ZZ DEMO texts; no model, no sender): the
-- models' turns are planted answers handed to fn_reason_held_resolve exactly as the replay hands a reasoned answer.
-- It plays the founder's example of 16 Nov 2026 end to end: the CEO's order to the it_engineer, Microsoft inbox >= 80%.
--   1. the order opens a conversation and the it_engineer is asked for its plan, with its tools and the tools it lacks;
--   2. a plan whose step is "run a GlockApps test" is REFUSED (the it_engineer lacks the tool; the engineer session has it) and
--      goes back once with the reason; the honest plan ("partly": its own readings, the transport rule and the lane watch; needs a
--      GlockApps re-test by the engineer session, engaged recipients from the sales engineer, the CEO's daily volume) is recorded;
--   3. the CEO's answer asking the founder is REFUSED; one spending over the company limits is REFUSED; the third ADJUSTS the
--      date, files the GlockApps re-test for the engineer session, decides 20 a day of warm-up and pulls in the sales engineer
--      (a sub-order in the same thread, which writes its own plan: it lacks a reply lane on M365, so the CEO commissions it);
--   4. at the first milestone code reads no re-test: behind, so the it_engineer writes a status (blocked on the engineer
--      session) and the CEO responds; the summary line says blocked on the engineer session;
--   5. the engineer session records a GlockApps test (Microsoft 70%) and closes the request; at the due date the it_engineer
--      writes its retro; the CEO's "close met" at 70 < 80 is REFUSED; he extends it once with a lesson, written to the seat's
--      case memory and the shared pool (order.lesson); the sales engineer's sub-order ends dropped with its own lesson;
--   6. (2c) a second order whose plan is refused twice is blocked and handed to the CEO; nothing reaches the founder.
--   7. review orderconv, fix round 1 (16 Nov 2026), rows R1-R8 (each failed on a28d85ae5, LOCAL): a refusal quoting a model's
--      address never reaches the summary or the pack; a closed hand-over is not re-planned; glockapps_test, code_change and dns_write
--      are never built or flipped and the session reads every request as data; money in words (five thousand dirhams, USD 2,000,
--      AED 5 000, EUR) in seat turns and the CEO's decision after the retro; a turn's spends summed; one row per spend; a later
--      milestone's status after a refused one; easy in the request; a pulled-in sub-order passes the plan bet's checks.
do $probe$
declare
  v_fail text := ''; v_tag text := substr(md5(clock_timestamp()::text), 1, 8); v_plan bigint; v_r jsonb; v_h bigint; v_q bigint; v_sub bigint; v_bet bigint;
  v_plan2 bigint; v_g bigint; v_y bigint; v_fits jsonb; v_left numeric; v_per numeric; v_x numeric;
  v_alerts int; v_fnotices int; v_t public.seat_order_thread; v_txt text; v_req bigint; v_req2 bigint; v_n int; v_mk bigint; v_case jsonb; v_test text := 'zz-demo-' || v_tag;
  d7 text := to_char(now() + interval '7 days', 'YYYY-MM-DD"T"HH24:MI:SSOF'); d14 text := to_char(now() + interval '14 days', 'YYYY-MM-DD"T"HH24:MI:SSOF');
  d20 text := to_char(now() + interval '20 days', 'YYYY-MM-DD"T"HH24:MI:SSOF'); d21 text := to_char(now() + interval '21 days', 'YYYY-MM-DD"T"HH24:MI:SSOF');
  d25 text := to_char(now() + interval '25 days', 'YYYY-MM-DD"T"HH24:MI:SSOF'); d35 text := to_char(now() + interval '35 days', 'YYYY-MM-DD"T"HH24:MI:SSOF');
begin
  perform set_config('qd.duty_fixtures', 'on', true);
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  select count(*) into v_alerts from public.founder_alerts;
  select count(*) into v_fnotices from public.agent_actions where kind = 'handoff' and detail->>'recipient_role' = 'founder';
  -- the probe's own cap and rounds (rolled back): production's turns of today never fill the probe's room
  update public.decision_policy set value = value || '{"turns_per_day": 1000, "aed_per_day": 1000, "max_rounds": 3}'::jsonb where key = 'order_threads';

  begin   -- a step that cannot run is a failure with its reason, never a crash without a verdict
  -- ── 0. THE ORDER: the plan file files the founder's example as any bet (its checks), in the probe's world ─────────────
  insert into public.ceo_plan_week (kind, period, status, task_class, output, pack)
  values ('daily', current_date + 1000, 'asked', 'routine_employee_reasoning', '{}'::jsonb, '{}'::jsonb) returning id into v_plan;
  v_r := public.fn_ceo_plan_file(v_plan, jsonb_build_object('decision', jsonb_build_object('bets', jsonb_build_array(
    jsonb_build_object('channel', 'deliverability_fix', 'seat', 'it_engineer', 'what', 'ZZ DEMO Microsoft inbox placement at least 80% on a GlockApps retest',
      'how', 'Honest warm-up of supplier@ on the one sending domain', 'why', 'The founder''s people on Microsoft-hosted mail must receive our sign-up mail',
      'measure', 'placement_inbox_pct', 'measure_args', jsonb_build_object('provider_class', 'microsoft'), 'target', 80, 'direction', 'at_least', 'due_at', d21,
      'expected_low', 0, 'expected_high', 80, 'cost_aed', 0, 'legal', 'Safe if honest warm-up (Microsoft and Google sender policies)', 'kill_criterion', 'two retests under 50%'),
    jsonb_build_object('channel', 'linkedin_company_page', 'seat', 'marketing', 'what', 'ZZ DEMO three company-page posts a week for the focus trades',
      'how', 'The monthly calendar, organic only', 'why', 'Trust for the founder''s people who look us up', 'measure', 'reported', 'measure_args', '{}'::jsonb,
      'target', 1, 'direction', 'at_least', 'due_at', d14, 'cost_aed', 0, 'legal', 'organic posts only', 'kill_criterion', 'none')))), 'zz-demo/stub', null);
  if (v_r->>'filed')::int <> 2 then v_fail := v_fail || 'the two orders were not filed: ' || v_r::text || '; '; end if;
  select handoff_id, id into v_h, v_bet from public.ceo_plan_bet where plan_id = v_plan and ord = 1;
  select handoff_id into v_mk from public.ceo_plan_bet where plan_id = v_plan and ord = 2;

  -- ── 1. THE CONVERSATION OPENS: the it_engineer is asked for its plan, with what it can and cannot do ───────────────────
  v_r := public.fn_order_threads_tick(now());
  select * into v_t from public.seat_order_thread where handoff_id = v_h;
  if v_t.handoff_id is null or v_t.state <> 'awaiting_plan' or v_t.thread_id <> v_h then v_fail := v_fail || '1: no conversation awaiting the plan: ' || coalesce(v_r::text, '') || '; '; end if;
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'plan' and status = 'asked' order by round desc limit 1);
  select request->'context'->'case' into v_case from public.reasoning_held_question where id = v_q and surface = 'it_engineer.order_plan' and seat = 'it_engineer';
  if v_case is null then v_fail := v_fail || '1: no it_engineer.order_plan question; '; end if;
  if not (v_case->'your_tools' @> '[{"tool": "placement_verdict_read"}]' and v_case->'tools_you_lack' @> '[{"tool": "glockapps_test", "who_can": "engineer_session"}]'
          and v_case->'tools_you_lack' @> '[{"tool": "dns_write"}]' and v_case->'tools_you_lack' @> '[{"tool": "warmup_volume", "who_can": "sales_engineer"}]') then
    v_fail := v_fail || '1: the plan question does not carry the it_engineer''s tools and gaps; ';
  end if;
  if (select request->'decision'->'fields' from public.reasoning_held_question where id = v_q) is null
     or (select request->'decision'->>'authored' from public.reasoning_held_question where id = v_q) is distinct from 'true' then v_fail := v_fail || '1: the plan question asks no authored fields; '; end if;
  if (select detail->>'awaiting' from public.agent_actions where id = v_h) !~ '^it_engineer writes its plan' then v_fail := v_fail || '1: the hand-over does not say the it_engineer owes the plan; '; end if;

  -- ── 2a. REFUSED: a plan whose own step is a tool the it_engineer lacks ───────────────────────────────────────────────
  v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'can', 'fields', jsonb_build_object(
    'reason', 'ZZ DEMO I will run a GlockApps test myself every week and warm up the mailbox until Microsoft places us in the inbox.',
    'steps', jsonb_build_array(jsonb_build_object('tool', 'glockapps_test', 'action', 'run a GlockApps test of supplier@ every Monday', 'by', d7))::text,
    'needs', jsonb_build_array(jsonb_build_object('kind', 'engineer_session', 'tool', 'warmup_volume', 'what', 'the engineer session sends the warm-up volume'))::text,
    'risks', 'none', 'milestones', jsonb_build_array(jsonb_build_object('at', d7, 'expect', 50))::text))));
  if not exists (select 1 from public.seat_order_turn where handoff_id = v_h and kind = 'plan' and round = 1 and status = 'refused'
                  and array_to_string(refusal, ' ') ~ 'glockapps_test, which it_engineer does not have' and array_to_string(refusal, ' ') ~ 'engineer_session'
                  and array_to_string(refusal, ' ') ~ 'the engineer session is asked only for what the register says it alone can do \(who_can engineer_session\): warmup_volume') then
    v_fail := v_fail || '2a: a plan naming a tool the seat lacks was not refused: ' || coalesce(v_r::text, '') || '; ';
  end if;
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'plan' and round = 2 and status = 'asked');
  if v_q is null or (select question from public.reasoning_held_question where id = v_q) !~ 'CODE REFUSED YOUR LAST ANSWER' then v_fail := v_fail || '2a: the refused plan did not go back with its reasons; '; end if;

  -- ── 2b. THE HONEST PLAN: partly, with its own tools, and what it needs from others ───────────────────────────────────
  v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'partly', 'fields', jsonb_build_object(
    'reason', 'ZZ DEMO I can make sure the sending side is clean and read every verdict, but I cannot run a GlockApps test, change DNS or create warm-up volume myself.',
    'steps', jsonb_build_array(
       jsonb_build_object('tool', 'sender_readings', 'action', 'confirm SPF, DKIM and DMARC pass and no blocklist lists the domain', 'by', d7),
       jsonb_build_object('tool', 'exo_transport_rule', 'action', 'make sure the List-Unsubscribe-Post rule exists on supplier@ mail', 'by', d7),
       jsonb_build_object('tool', 'm365_lane_watch', 'action', 'watch the lane for held rows and keep it under its daily ceiling', 'by', d20),
       jsonb_build_object('tool', 'placement_verdict_read', 'action', 'read the Microsoft class of every recorded GlockApps verdict', 'by', d20))::text,
    'needs', jsonb_build_array(
       jsonb_build_object('kind', 'engineer_session', 'tool', 'glockapps_test', 'what', 'a GlockApps re-test of supplier@ after the first warm-up week'),
       jsonb_build_object('kind', 'seat_help', 'seat', 'sales_engineer', 'what', 'engaged recipients (people who reply or registered) routed through the M365 lane as warm-up'),
       jsonb_build_object('kind', 'ceo_decision', 'what', 'the daily warm-up volume within the lane''s ceiling'))::text,
    'risks', 'Microsoft may need more than three weeks of engaged traffic; a re-test before enough volume would read low.',
    'milestones', jsonb_build_array(jsonb_build_object('at', d7, 'expect', 50), jsonb_build_object('at', d20, 'expect', 80))::text))));
  select * into v_t from public.seat_order_thread where handoff_id = v_h;
  if v_t.state <> 'awaiting_ceo' or v_t.feasibility <> 'partly' or jsonb_array_length(v_t.milestones) <> 2 then v_fail := v_fail || '2b: the honest plan was not recorded: ' || coalesce(v_r::text, '') || '; '; end if;
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'ceo_answer' and status = 'asked' order by round desc limit 1);
  if not exists (select 1 from public.reasoning_held_question where id = v_q and surface = 'ceo.order_answer' and seat = 'ceo') then v_fail := v_fail || '2b: the CEO was not asked to answer the plan; '; end if;

  -- ── 2c. A PLAN REFUSED TWICE BLOCKS THE ORDER AND THE CEO DECIDES (the marketing order, two rounds) ─────────────────────
  update public.decision_policy set value = value || '{"max_rounds": 2}'::jsonb where key = 'order_threads';
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_mk and kind = 'plan' and status = 'asked');
  v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'can', 'fields', jsonb_build_object(
    'reason', 'ZZ DEMO I will boost the posts so more suppliers see them.', 'steps', jsonb_build_array(jsonb_build_object('tool', 'company_page_post', 'action', 'post three times a week and boost each post', 'by', d7))::text,
    'needs', '[]', 'risks', 'none', 'milestones', jsonb_build_array(jsonb_build_object('at', d7, 'expect', 0))::text))));
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_mk and kind = 'plan' and round = 2 and status = 'asked');
  v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'yes', 'fields', '{}'::jsonb)));
  select * into v_t from public.seat_order_thread where handoff_id = v_mk;
  if v_t.risk <> 'blocked' or v_t.blocked_on !~ '^the plan of marketing, refused 2 times' or v_t.state <> 'awaiting_ceo'
     or not exists (select 1 from public.seat_order_turn where handoff_id = v_mk and kind = 'plan' and round = 1 and array_to_string(refusal, ' ') ~ 'paid_ads') then
    v_fail := v_fail || '6: a plan refused twice did not block the order and go to the CEO (' || coalesce(v_t.state, '-') || ', ' || coalesce(v_t.blocked_on, '-') || '); ';
  end if;
  update public.decision_policy set value = value || '{"max_rounds": 3}'::jsonb where key = 'order_threads';

  -- ── 3a. REFUSED: the CEO's answer asks the founder ───────────────────────────────────────────────────────────────────
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'ceo_answer' and round = 1 and status = 'asked');
  v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'accept', 'fields', jsonb_build_object(
    'reason', 'ZZ DEMO The plan is sound; ask the founder to approve the warm-up before we start.', 'actions', '[]'))));
  if not exists (select 1 from public.seat_order_turn where handoff_id = v_h and kind = 'ceo_answer' and round = 1 and status = 'refused' and array_to_string(refusal, ' ') ~ 'founder is not asked') then
    v_fail := v_fail || '3a: a CEO turn asking the founder was not refused: ' || coalesce(v_r::text, '') || '; ';
  end if;
  -- ── 3b. REFUSED: money over the company limits ───────────────────────────────────────────────────────────────────────
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'ceo_answer' and round = 2 and status = 'asked');
  v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'accept', 'fields', jsonb_build_object(
    'reason', 'ZZ DEMO The plan stands; I buy a dedicated warm-up service so the mailbox ramps faster.',
    'actions', jsonb_build_array(jsonb_build_object('kind', 'spend', 'aed', 999999, 'what', 'ZZ DEMO a dedicated warm-up service for three weeks'))::text))));
  if not exists (select 1 from public.seat_order_turn where handoff_id = v_h and kind = 'ceo_answer' and round = 2 and status = 'refused' and array_to_string(refusal, ' ') ~ 'over the company limits') then
    v_fail := v_fail || '3b: money over the company limits was not refused: ' || coalesce(v_r::text, '') || '; ';
  end if;
  -- ── 3c. THE CEO ADJUSTS AND ACTS: the date, the re-test, the volume, the sales engineer pulled in ─────────────────────
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'ceo_answer' and round = 3 and status = 'asked');
  v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'adjust', 'fields', jsonb_build_object(
    'reason', 'ZZ DEMO Partly is honest. The re-test goes to the engineer session after the first warm-up week, 20 a day keeps the mailbox far under its ceiling, the sales engineer brings the engaged people, and four more days give the second week of traffic time to count.',
    'actions', jsonb_build_array(
       jsonb_build_object('kind', 'adjust', 'due_at', d25),
       jsonb_build_object('kind', 'engineer_test', 'provider_class', 'microsoft', 'what', 'ZZ DEMO GlockApps re-test of supplier@ after the first warm-up week, Microsoft class read'),
       jsonb_build_object('kind', 'set_volume', 'per_day', 20),
       jsonb_build_object('kind', 'pull_in', 'seat', 'sales_engineer', 'what', 'ZZ DEMO send the replies to engaged suppliers (replied or registered) from supplier@ through the M365 lane, at most 20 a day',
                          'measure', 'm365_engaged_sends', 'measure_args', '{}'::jsonb, 'target', 60, 'direction', 'at_least', 'due_at', d14))::text))));
  select * into v_t from public.seat_order_thread where handoff_id = v_h;
  if v_t.state <> 'in_progress' or (select due_at from public.ceo_plan_bet where id = v_bet) <> d25::timestamptz then v_fail := v_fail || '3c: the CEO''s adjust did not apply: ' || coalesce(v_r::text, '') || '; '; end if;
  select id into v_req from public.engineer_session_request where thread_id = v_h and kind = 'glockapps_retest' and status = 'queued' and provider_class = 'microsoft';
  if v_req is null then v_fail := v_fail || '3c: no GlockApps re-test for the engineer session; '; end if;
  if not exists (select 1 from public.ceo_own_decision where source = 'order_thread' and choice = '20 a day' and world = 'demo') then v_fail := v_fail || '3c: the volume decision was not recorded; '; end if;
  select handoff_id into v_sub from public.seat_order_thread where parent_handoff_id = v_h and seat = 'sales_engineer' and thread_id = v_h;
  if v_sub is null or (select detail->>'volume_per_day' from public.agent_actions where id = v_sub) <> '20' then v_fail := v_fail || '3c: no sub-order to the sales engineer in the thread carrying the volume; '; end if;
  if (select evidence->'ceo_decision'->>'choice' from public.agent_actions where id = v_h) <> 'adjust' then v_fail := v_fail || '3c: the decision is not on the hand-over; '; end if;

  -- ── 3d. THE SUB-ORDER IS ITS OWN CONVERSATION: the sales engineer plans, lacks the M365 reply lane, the CEO commissions it ─
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_sub and kind = 'plan' and status = 'asked');
  v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'partly', 'fields', jsonb_build_object(
    'reason', 'ZZ DEMO I answer every engaged supplier within the hour, but my replies leave through Resend: the M365 lane carries only invitations and nudges.',
    'steps', jsonb_build_array(jsonb_build_object('tool', 'reply_path', 'action', 'answer every reply and registrant question within one business hour', 'by', d14))::text,
    'needs', jsonb_build_array(jsonb_build_object('kind', 'engineer_session', 'tool', 'm365_reply_lane', 'what', 'replies to engaged suppliers sent from supplier@ through the M365 lane'))::text,
    'risks', 'Too few engaged people in two weeks to reach 60 sends.',
    'milestones', jsonb_build_array(jsonb_build_object('at', d7, 'expect', 20))::text))));
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_sub and kind = 'ceo_answer' and status = 'asked');
  v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'accept', 'fields', jsonb_build_object(
    'reason', 'ZZ DEMO The reply lane on M365 is the missing piece of the warm-up; the engineer session builds it while the sales engineer keeps answering within the hour.',
    'actions', jsonb_build_array(jsonb_build_object('kind', 'commission', 'tool', 'm365_reply_lane', 'seat', 'sales_engineer',
       'what', 'ZZ DEMO let a reply to an engaged supplier leave from supplier@ through the M365 lane, inside the lane''s daily ceiling',
       'acceptance', 'a reply to a supplier who wrote to us leaves through Graph with a m365: provider id and counts toward the ceiling'))::text))));
  select id into v_req2 from public.engineer_session_request where thread_id = v_h and kind = 'capability' and tool = 'm365_reply_lane' and seat = 'sales_engineer';
  if v_req2 is null or (select state from public.seat_order_thread where handoff_id = v_sub) <> 'in_progress' then v_fail := v_fail || '3d: the build was not commissioned: ' || coalesce(v_r::text, '') || '; '; end if;

  -- ── 4. THE FIRST MILESTONE: no re-test yet, so behind; the seat writes a status, the CEO responds ──────────────────────
  v_r := public.fn_order_threads_tick(now() + interval '8 days');
  if not exists (select 1 from public.seat_order_turn where handoff_id = v_h and kind = 'checkin' and round = 1 and choice = 'behind') then v_fail := v_fail || '4: no check-in behind the milestone: ' || v_r::text || '; '; end if;
  select * into v_t from public.seat_order_thread where handoff_id = v_h;
  if v_t.state <> 'awaiting_status' or v_t.risk <> 'blocked' or v_t.blocked_on !~ '^the engineer session: glockapps_retest' then
    v_fail := v_fail || '4: the order is not waiting for a status, blocked on the engineer session (' || coalesce(v_t.state, '-') || ', ' || coalesce(v_t.blocked_on, '-') || '); ';
  end if;
  v_txt := public.fn_ceo_plan_summary_text(now() - interval '24 hours');
  if v_txt !~ ('#' || v_h || ' it_engineer: ZZ DEMO Microsoft inbox placement[^\n]* - blocked on the engineer session: glockapps_retest[^\n]* - next: it_engineer writes its status')
     or v_txt !~ ('\n    - #' || v_sub || ' sales_engineer: ') then
    v_fail := v_fail || '4: the founder''s summary does not carry one line per open order with its status and next step; ';
  end if;
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'status' and status = 'asked');
  v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'blocked', 'fields', jsonb_build_object(
    'done', 'ZZ DEMO SPF, DKIM and DMARC pass; the transport rule exists; the lane held nothing this week.',
    'blocker', 'the GlockApps re-test is still queued with the engineer session, so there is no reading after the warm-up week',
    'next_step', 'read the Microsoft class the day the re-test is recorded', 'need', '[]'))));
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'ceo_response' and status = 'asked');
  if v_q is null then v_fail := v_fail || '4: the CEO was not asked to respond to the status: ' || coalesce(v_r::text, '') || '; '; end if;
  v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'hold_course', 'fields', jsonb_build_object(
    'reason', 'ZZ DEMO The sending side is clean; the only gap is the re-test, which the engineer session owes. Hold the course and read it the day it lands.', 'actions', '[]'))));
  select * into v_t from public.seat_order_thread where handoff_id = v_h;
  if v_t.state <> 'in_progress' or v_t.milestone_ix <> 1 then v_fail := v_fail || '4: the response did not move to the next milestone: ' || coalesce(v_r::text, '') || '; '; end if;

  -- ── 5. THE ENGINEER SESSION RECORDS A RE-TEST (Microsoft 70%); THE DUE DATE; THE RETRO; THE CEO DECIDES ─────────────────
  if coalesce((public.fn_engineer_session_request_done(v_req, 'zz-demo-session', 'ZZ DEMO ran the test', 'no-such-test')->>'ok')::boolean, false) then
    v_fail := v_fail || '5: a re-test was closed with no recorded test; ';
  end if;
  insert into public.deliverability_test (test_id, reason, requested_by, marker, verdict, decided_at, lane)
  values (v_test, 'ZZ DEMO order probe re-test', 'zz-demo-session', 'id:' || v_test, 'fail', now(), 'm365');
  insert into public.deliverability_test_provider (test_id, provider, seeds, inbox, spam, tabs, missing, provider_class)
  values (v_test, 'Outlook', 20, 14, 6, 0, 0, 'microsoft');
  v_r := public.fn_engineer_session_request_done(v_req, 'zz-demo-session', 'ZZ DEMO GlockApps test run and recorded with the verdict script', v_test);
  if not coalesce((v_r->>'ok')::boolean, false) or not exists (select 1 from public.seat_order_turn where handoff_id = v_h and kind = 'engineer' and status = 'recorded') then
    v_fail := v_fail || '5: the engineer session could not close the re-test: ' || v_r::text || '; ';
  end if;
  v_r := public.fn_order_threads_tick(now() + interval '26 days');
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'retro' and status = 'asked');
  if v_q is null or (select question from public.reasoning_held_question where id = v_q) !~ 'placement_inbox_pct reads 70.0 against the target 80' then
    v_fail := v_fail || '5: no retro at the due date with the reading: ' || v_r::text || '; ';
  end if;
  v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'partly', 'fields', jsonb_build_object(
    'done', 'ZZ DEMO kept the sending side clean and read the re-test the day it was recorded',
    'result', 'Microsoft inbox 70% on the re-test against the 80% target, up from 0% in November',
    'why', 'one week of engaged traffic at 20 a day moved Microsoft; the reply lane on M365 is not built yet, so most engaged replies still left through Resend',
    'next', 'two more weeks of engaged traffic once the reply lane is built, then one more re-test'))));
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'ceo_next' and status = 'asked');
  v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'close_met', 'fields', jsonb_build_object(
    'reason', 'ZZ DEMO Seventy is close enough to call it done.', 'lesson', 'Close enough is not the target.'))));
  if not exists (select 1 from public.seat_order_turn where handoff_id = v_h and kind = 'ceo_next' and round = 1 and status = 'refused' and array_to_string(refusal, ' ') ~ 'close_met only when the measure is met') then
    v_fail := v_fail || '5: close met at 70 < 80 was not refused: ' || coalesce(v_r::text, '') || '; ';
  end if;
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_h and kind = 'ceo_next' and round = 2 and status = 'asked');
  v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'extend', 'fields', jsonb_build_object(
    'reason', 'ZZ DEMO From 0% to 70% in one week of engaged traffic: the method works. Extend once to give the reply lane and two more weeks of traffic time, then one re-test.',
    'lesson', 'Microsoft placement moves only with engaged traffic and a re-test: order the re-test, the warm-up recipients and any missing lane in the same week as the plan, not after the first milestone.',
    'new_due', d35, 'new_target', '', 'new_seat', ''))));
  select * into v_t from public.seat_order_thread where handoff_id = v_h;
  if v_t.state <> 'in_progress' or v_t.extensions <> 1 or v_t.lesson !~ '^Microsoft placement moves only with engaged traffic' then v_fail := v_fail || '5: the extension was not applied: ' || coalesce(v_r::text, '') || '; '; end if;
  if not exists (select 1 from public.seat_case_memory where seat = 'it_engineer' and case_kind = 'ceo_order' and source_table = 'seat_order_thread' and lessons[1] ~ '^Microsoft placement') then
    v_fail := v_fail || '5: the lesson is not in the it_engineer''s case memory; ';
  end if;
  if not exists (select 1 from public.company_event where event_type = 'order.lesson' and entity_id = v_h::text) then v_fail := v_fail || '5: the lesson is not in the shared pool; '; end if;
  if (select count(*) from public.event_subscription where event_type = 'order.lesson' and delivery = 'digest' and active) <> 6 then v_fail := v_fail || '5: not every seat hears order.lesson; '; end if;
  if (select due_at from public.ceo_plan_bet where id = v_bet) <> d35::timestamptz then v_fail := v_fail || '5: the bet''s date did not move; '; end if;
  -- every later order turn reads the lesson (the sales engineer's retro question, asked by the same tick)
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_sub and kind = 'retro' and status = 'asked');
  if v_q is null then v_fail := v_fail || '5: the sub-order got no retro at its due date; ';
  elsif not (select public.fn_order_case(v_sub)->'lessons_from_recent_orders' @> '[{"seat": "it_engineer"}]') then v_fail := v_fail || '5: a later turn does not read the lesson; '; end if;
  v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'missed', 'fields', jsonb_build_object(
    'done', 'ZZ DEMO answered every engaged supplier within the hour', 'result', 'no send left through the M365 lane: the reply lane is not built',
    'why', 'the lane carries only invitations and nudges; the commissioned build is still queued', 'next', 'resume the moment the build is done'))));
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_sub and kind = 'ceo_next' and status = 'asked');
  v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'drop', 'fields', jsonb_build_object(
    'reason', 'ZZ DEMO Without the reply lane this order cannot move; the parent order carries the warm-up until the build lands.',
    'lesson', 'An order that rides a missing lane waits on the build: commission the lane first and order the volume after it.',
    'new_due', '', 'new_target', '', 'new_seat', ''))));
  if (select state from public.seat_order_thread where handoff_id = v_sub) <> 'closed' or (select status from public.agent_actions where id = v_sub) <> 'done' then
    v_fail := v_fail || '5: the dropped sub-order did not close: ' || coalesce(v_r::text, '') || '; ';
  end if;

  -- ── 6. NOTHING REACHED THE FOUNDER; NOTHING WAS WRITTEN IN THE REAL WORLD ────────────────────────────────────────────────
  if (select count(*) from public.founder_alerts) <> v_alerts
     or (select count(*) from public.agent_actions where kind = 'handoff' and detail->>'recipient_role' = 'founder') <> v_fnotices then
    v_fail := v_fail || 'something reached the founder; ';
  end if;
  if exists (select 1 from public.seat_order_thread where world = 'real' and handoff_id in (v_h, v_sub, v_mk)) then v_fail := v_fail || 'the probe wrote a real-world conversation; '; end if;
  select count(*) into v_n from public.seat_order_turn where thread_id in (v_h, v_mk);

  -- ── 7. REVIEW ORDERCONV, FIX ROUND 1 (16 Nov 2026): every row below failed on a28d85ae5 (LOCAL) ──────────────────────────
  -- Two more orders in the probe's world (other provider classes, so one open order per seat and measure still holds).
  update public.decision_policy set value = value || '{"max_rounds": 2}'::jsonb where key = 'order_threads';
  insert into public.ceo_plan_week (kind, period, status, task_class, output, pack)
  values ('daily', current_date + 1001, 'asked', 'routine_employee_reasoning', '{}'::jsonb, '{}'::jsonb) returning id into v_plan2;
  v_r := public.fn_ceo_plan_file(v_plan2, jsonb_build_object('decision', jsonb_build_object('bets', jsonb_build_array(
    jsonb_build_object('channel', 'deliverability_fix', 'seat', 'it_engineer', 'what', 'ZZ DEMO Google inbox placement at least 80% on a GlockApps retest',
      'how', 'Honest warm-up of supplier@ on the one sending domain', 'why', 'Google-hosted suppliers must receive our sign-up mail', 'measure', 'placement_inbox_pct',
      'measure_args', jsonb_build_object('provider_class', 'google'), 'target', 80, 'direction', 'at_least', 'due_at', d21, 'cost_aed', 0, 'legal', 'safe', 'kill_criterion', 'none'),
    jsonb_build_object('channel', 'deliverability_fix', 'seat', 'it_engineer', 'what', 'ZZ DEMO Yahoo and AOL inbox placement at least 80% on a GlockApps retest',
      'how', 'Honest warm-up of supplier@ on the one sending domain', 'why', 'Yahoo-hosted suppliers must receive our sign-up mail', 'measure', 'placement_inbox_pct',
      'measure_args', jsonb_build_object('provider_class', 'yahoo_aol'), 'target', 80, 'direction', 'at_least', 'due_at', d21, 'cost_aed', 0, 'legal', 'safe', 'kill_criterion', 'none')))), 'zz-demo/stub', null);
  select handoff_id into v_g from public.ceo_plan_bet where plan_id = v_plan2 and ord = 1;
  select handoff_id into v_y from public.ceo_plan_bet where plan_id = v_plan2 and ord = 2;
  if v_g is null or v_y is null then v_fail := v_fail || 'R0: the two review orders were not filed: ' || v_r::text || '; '; end if;
  v_r := public.fn_order_threads_tick(now());
  -- R5: a status refused once at milestone 1 (so its round 2 was used) still gets milestone 2's status question
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_y and kind = 'plan' and status = 'asked');
  if v_q is not null then
    v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'partly', 'fields', jsonb_build_object(
      'reason', 'ZZ DEMO I can keep the sending side clean and read every verdict, but cannot run a GlockApps test myself.',
      'steps', jsonb_build_array(jsonb_build_object('tool', 'sender_readings', 'action', 'confirm SPF, DKIM and DMARC pass every day', 'by', d7))::text,
      'needs', jsonb_build_array(jsonb_build_object('kind', 'engineer_session', 'tool', 'glockapps_test', 'what', 'a GlockApps re-test after the warm-up week'))::text,
      'risks', 'a re-test before enough volume reads low', 'milestones', jsonb_build_array(jsonb_build_object('at', d7, 'expect', 50), jsonb_build_object('at', d14, 'expect', 70))::text))));
  end if;
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_y and kind = 'ceo_answer' and status = 'asked');
  if v_q is not null then
    v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'accept', 'fields', jsonb_build_object(
      'reason', 'ZZ DEMO The plan stands and the re-test goes to the engineer session.', 'actions', '[]'))));
  end if;
  v_r := public.fn_order_threads_tick(now() + interval '8 days');
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_y and kind = 'status' and status = 'asked');
  if v_q is not null then
    v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'at_risk', 'fields', jsonb_build_object(
      'done', 'x', 'next_step', 'y', 'blocker', '', 'need', '[]'))));
  end if;
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_y and kind = 'status' and status = 'asked');
  if v_q is not null then
    v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'at_risk', 'fields', jsonb_build_object(
      'done', 'ZZ DEMO the sender is clean every day', 'next_step', 'ZZ DEMO read the re-test the day it lands', 'blocker', '', 'need', '[]'))));
  end if;
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_y and kind = 'ceo_response' and status = 'asked');
  if v_q is not null then
    v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'hold_course', 'fields', jsonb_build_object(
      'reason', 'ZZ DEMO Hold the course, the re-test is the only gap left.', 'actions', '[]'))));
  end if;
  v_r := public.fn_order_threads_tick(now() + interval '15 days');
  if not exists (select 1 from public.seat_order_turn u join public.reasoning_held_question h on h.id = u.held_id
                  where u.handoff_id = v_y and u.kind = 'status' and u.status = 'asked' and h.status = 'held') then
    v_fail := v_fail || 'R5: milestone 2 asked no status after a refused status at milestone 1: ' || coalesce(v_r::text, '') || '; ';
  end if;

  -- R1 + R3 + R4a/R8: a step's tool holds an address and a number; a capability need for glockapps_test; money in words in a seat turn
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_g and kind = 'plan' and status = 'asked');
  if (select request->>'easy' from public.reasoning_held_question where id = v_q) is distinct from 'false' then v_fail := v_fail || 'R6: a seat''s turn does not say easy false; '; end if;
  if v_q is not null then
    v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'can', 'fields', jsonb_build_object(
      'reason', 'ZZ DEMO I can do this with my own tools, reading the sender every day.', 'steps', '[{"tool":"zz.demo@example.org +971501234567","action":"call him about the mailbox setup","by":"' || d7 || '"}]',
      'needs', jsonb_build_array(jsonb_build_object('kind', 'capability', 'tool', 'glockapps_test', 'what', 'my own GlockApps key so I run the tests myself'))::text, 'risks', 'none',
      'milestones', jsonb_build_array(jsonb_build_object('at', d7, 'expect', 50))::text))));
  end if;
  if not exists (select 1 from public.seat_order_turn where handoff_id = v_g and kind = 'plan' and round = 1 and status = 'refused' and array_to_string(refusal, ' ') ~ 'glockapps_test is never built for a seat') then
    v_fail := v_fail || 'R3: a capability need for glockapps_test was not refused: ' || coalesce(v_r::text, '') || '; ';
  end if;
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_g and kind = 'plan' and status = 'asked' order by round desc limit 1);
  if v_q is not null then
    v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'can', 'fields', jsonb_build_object(
      'reason', 'ZZ DEMO I will buy a warm-up service for five thousand dirhams and read the sender every day.', 'steps', '[{"tool":"zz.demo@example.org +971501234567","action":"call him about the mailbox setup","by":"' || d7 || '"}]',
      'needs', '[]', 'risks', 'none', 'milestones', jsonb_build_array(jsonb_build_object('at', d7, 'expect', 50))::text))));
  end if;
  if not exists (select 1 from public.seat_order_turn where handoff_id = v_g and kind = 'plan' and round = 2 and status = 'refused' and array_to_string(refusal, ' ') ~ 'the words name AED 5000,') then
    v_fail := v_fail || 'R4a/R8: a seat''s plan naming five thousand dirhams was not refused: ' || coalesce(v_r::text, '') || '; ';
  end if;
  select * into v_t from public.seat_order_thread where handoff_id = v_g;
  if v_t.risk <> 'blocked' or v_t.blocked_on ~ '(@|example\.org|971501234567)' or v_t.blocked_on !~ '\[address\]' then v_fail := v_fail || 'R1: blocked_on quotes the model raw: ' || coalesce(v_t.blocked_on, '-') || '; '; end if;
  if public.fn_ceo_plan_summary_text(now() - interval '1 day') ~ '(example\.org|971501234567)' or public.fn_order_threads_pack()::text ~ '(example\.org|971501234567)' then
    v_fail := v_fail || 'R1: an address or a number reached the founder''s summary or the pack; ';
  end if;
  -- R6: the CEO's turn says easy in its request (the routine route even before routing.ts is deployed)
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_g and kind = 'ceo_answer' and status = 'asked');
  if (select request->>'easy' from public.reasoning_held_question where id = v_q) is distinct from 'true' then v_fail := v_fail || 'R6: the CEO''s turn does not say easy true; '; end if;
  -- R3 + R4b + R7 + R8: forbidden builds, three spends that only fit one by one, two alike sub-orders on switched-off invitations,
  -- dollars and a spaced amount in the words
  v_fits := public.fn_company_spend_fits(0.01);
  v_left := coalesce((v_fits->>'left_today_aed')::numeric, 0); v_per := coalesce((v_fits->>'per_action_aed')::numeric, 0);
  v_x := greatest(least(v_per, v_left), 0.01);
  if v_q is not null then
    v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'accept', 'fields', jsonb_build_object(
      'reason', 'ZZ DEMO The plan stands. Budget: USD 2,000 or AED 5 000 for the warm-up tool.',
      'actions', jsonb_build_array(
        jsonb_build_object('kind', 'commission', 'tool', 'glockapps_test', 'seat', 'it_engineer', 'what', 'ZZ DEMO give the it_engineer its own GlockApps key', 'acceptance', 'the it_engineer runs a test without the session'),
        jsonb_build_object('kind', 'commission', 'tool', 'code_change', 'seat', 'it_engineer', 'what', 'ZZ DEMO let the it_engineer deploy edge functions itself', 'acceptance', 'it deploys a function without any person reviewing it'),
        jsonb_build_object('kind', 'spend', 'aed', v_x, 'what', 'ZZ DEMO a warm-up service for the first week of traffic'),
        jsonb_build_object('kind', 'spend', 'aed', v_x, 'what', 'ZZ DEMO a warm-up service for the second week of traffic'),
        jsonb_build_object('kind', 'pull_in', 'seat', 'marketing', 'what', 'ZZ DEMO send invitation batches to Google-hosted suppliers to warm the mailbox', 'measure', 'invitations', 'measure_args', '{}'::jsonb, 'target', 500, 'direction', 'at_least', 'due_at', d14),
        jsonb_build_object('kind', 'pull_in', 'seat', 'marketing', 'what', 'ZZ DEMO send invitation batches to Google-hosted suppliers to warm the mailbox', 'measure', 'invitations', 'measure_args', '{}'::jsonb, 'target', 500, 'direction', 'at_least', 'due_at', d14))::text))));
  end if;
  v_txt := (select array_to_string(refusal, ' | ') from public.seat_order_turn where handoff_id = v_g and kind = 'ceo_answer' and round = 1 and status = 'refused');
  if coalesce(v_txt, '') !~ 'glockapps_test is never built for a seat' or v_txt !~ 'code_change is never built for a seat' then v_fail := v_fail || 'R3: a forbidden build was commissioned: ' || coalesce(v_r::text, '') || '; '; end if;
  if 2 * v_x > v_left and coalesce(v_txt, '') !~ 'the spends of this turn sum to AED' then v_fail := v_fail || 'R4b: spends that fit only one by one passed together; '; end if;
  if coalesce(v_txt, '') !~ 'action 6: an order to marketing on invitations is already open'
     or (coalesce((select value from public.app_secrets where key = 'invite_enabled'), '') <> 'true' and v_txt !~ 'action 5: invitations are switched off') then
    v_fail := v_fail || 'R7: a pulled-in sub-order skipped the plan bet''s checks: ' || coalesce(v_txt, '-') || '; ';
  end if;
  if coalesce(v_txt, '') !~ 'the words name AED 7345' then v_fail := v_fail || 'R8: USD 2,000 in the words was not read as AED 7345: ' || coalesce(v_txt, '-') || '; '; end if;
  -- R4c: two spends that fit together are both recorded, one row each
  v_x := least(v_per, floor(v_left * 50) / 100);
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_g and kind = 'ceo_answer' and status = 'asked' order by round desc limit 1);
  if v_q is not null then
    v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'accept', 'fields', jsonb_build_object(
      'reason', 'ZZ DEMO The plan stands with two small warm-up purchases inside today''s limit.',
      'actions', case when v_x >= 0.01 then jsonb_build_array(jsonb_build_object('kind', 'spend', 'aed', v_x, 'what', 'ZZ DEMO a warm-up service for the first week of traffic'),
                                                           jsonb_build_object('kind', 'spend', 'aed', v_x, 'what', 'ZZ DEMO a warm-up service for the second week of traffic'))::text else '[]' end))));
  end if;
  if (select state from public.seat_order_thread where handoff_id = v_g) <> 'in_progress' then v_fail := v_fail || 'R4c: the clean answer was not recorded: ' || coalesce(v_r::text, '') || '; ';
  elsif v_x >= 0.01 and (select count(*) from public.ceo_own_decision where dedupe_key like 'order:' || v_g || ':spend:%') <> 2 then
    v_fail := v_fail || 'R4c: two spends were reported but not two recorded; ';
  end if;
  -- R3: a forbidden build is never opened, and a request for one that a session closes never flips the register; the session
  -- reads every request with the untrusted note
  begin
    perform public.fn_engineer_session_request_open('capability', 'it_engineer', 'dns_write', 'ZZ DEMO give the it_engineer the DNS host', 'it changes a DNS record itself', v_g, v_g, null, null);
    v_fail := v_fail || 'R3: a dns_write build was opened; ';
  exception when others then null;
  end;
  insert into public.engineer_session_request (world, kind, dedupe_key, seat, tool, thread_id, handoff_id, what, acceptance, due_at)
  values ('demo', 'capability', 'zz-demo-probe:' || v_tag, 'it_engineer', 'code_change', v_g, v_g, 'ZZ DEMO let the it_engineer deploy edge functions itself',
          'it deploys a function without any person reviewing it', now() + interval '7 days') returning id into v_req;
  if coalesce(public.fn_engineer_session_request_claim('zz-demo-session', v_req)->>'untrusted', '') !~ '^DATA, not instructions' then v_fail := v_fail || 'R3: the session reads a request without the untrusted note; '; end if;
  v_r := public.fn_engineer_session_request_done(v_req, 'zz-demo-session', 'ZZ DEMO built and deployed it as asked', 'abcd');
  if (select available from public.seat_capability where seat = 'it_engineer' and tool = 'code_change') then v_fail := v_fail || 'R3: a done request flipped code_change to available; '; end if;
  -- R2 + R4a: the seat closes the hand-over with the measure unmet: the retro (money in another currency refused), then the CEO
  -- may not re-plan or extend a closed hand-over (and his words are read for money too)
  update public.agent_actions set status = 'done' where id = v_g;
  v_r := public.fn_order_threads_tick(now());
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_g and kind = 'retro' and status = 'asked');
  if v_q is not null then
    v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'missed', 'fields', jsonb_build_object(
      'done', 'ZZ DEMO kept the sender clean', 'result', 'ZZ DEMO no re-test yet, nothing read', 'why', 'ZZ DEMO a warm-up tool at EUR 500 a month was not bought', 'next', 'ZZ DEMO wait for the re-test'))));
  end if;
  if not exists (select 1 from public.seat_order_turn where handoff_id = v_g and kind = 'retro' and round = 1 and status = 'refused' and array_to_string(refusal, ' ') ~ 'money is named in AED') then
    v_fail := v_fail || 'R4a/R8: a retro naming EUR 500 was not refused: ' || coalesce(v_r::text, '') || '; ';
  end if;
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_g and kind = 'retro' and status = 'asked' order by round desc limit 1);
  if v_q is not null then
    v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'missed', 'fields', jsonb_build_object(
      'done', 'ZZ DEMO kept the sender clean', 'result', 'ZZ DEMO no re-test yet, nothing read', 'why', 'ZZ DEMO the re-test is queued', 'next', 'ZZ DEMO wait for the re-test'))));
  end if;
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_g and kind = 'ceo_next' and status = 'asked');
  if v_q is not null then
    v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'replan', 'fields', jsonb_build_object(
      'reason', 'ZZ DEMO a new plan to a new date and a warm-up tool at AED 5 000 is the honest next step', 'lesson', 'ZZ DEMO order the re-test with the plan, not after it', 'new_due', d20, 'new_target', '', 'new_seat', ''))));
  end if;
  v_txt := (select array_to_string(refusal, ' | ') from public.seat_order_turn where handoff_id = v_g and kind = 'ceo_next' and round = 1 and status = 'refused');
  if coalesce(v_txt, '') !~ 'the order''s hand-over is done: close it met, drop it or reassign it' then v_fail := v_fail || 'R2: a closed hand-over was re-planned: ' || coalesce(v_r::text, '') || '; '; end if;
  if coalesce(v_txt, '') !~ 'the words name AED 5000,' then v_fail := v_fail || 'R4a/R8: the CEO''s decision after the retro naming AED 5 000 was not refused; '; end if;
  v_q := (select held_id from public.seat_order_turn where handoff_id = v_g and kind = 'ceo_next' and status = 'asked' order by round desc limit 1);
  if v_q is not null then
    v_r := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO stub', 'model', 'zz-demo/stub', 'decision', jsonb_build_object('choice', 'drop', 'fields', jsonb_build_object(
      'reason', 'ZZ DEMO the hand-over is closed, and the re-test decides the next order', 'lesson', 'ZZ DEMO order the re-test with the plan, not after it', 'new_due', '', 'new_target', '', 'new_seat', ''))));
  end if;
  if (select state from public.seat_order_thread where handoff_id = v_g) <> 'closed' then v_fail := v_fail || 'R2: the closed hand-over did not end in drop: ' || coalesce(v_r::text, '') || '; '; end if;
  exception when others then
    v_fail := v_fail || 'the probe stopped (' || sqlerrm || '); ';
  end;
  if v_fail <> '' then raise exception 'CHK<<PROBE FAILED: %>>', v_fail; end if;
  raise exception 'CHK<<PROBE OK: % turns in two conversations, the founder''s example end to end>>', v_n;
end $probe$;
