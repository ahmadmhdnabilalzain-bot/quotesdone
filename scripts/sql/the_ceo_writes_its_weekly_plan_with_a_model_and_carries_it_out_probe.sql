-- PROBE of the_ceo_writes_its_weekly_plan_with_a_model_and_carries_it_out.sql. Seat: ceo (agent: L1_CEO). 16 Nov 2026.
-- LOCAL ONLY (a Postgres 16 built from the schema mirror, scripts/db/local_pg16.mjs). NEVER on production: it writes a week of
-- plans, orders, model costs and invitation sends. It always raises CHK<<...>>, so everything it writes rolls back. Its world is
-- its own (qd.duty_fixtures = 'on': plans, decisions and planted spend of the demo world; production's are invisible to it).
-- What it proves, each with the line that fails on the body before this file:
--   0. the heartbeat's door (fn_ceo_plan_handover) opens no plan and builds no pack on a Monday morning: before, the heartbeat
--      called fn_ceo_plan_due, which built the pack inside the API's 8 s and timed out every hour (the cause of id 12);
--   1-2. the duty opens the weekly plan with its pack; the heartbeat hands it over at once (never handed: attempts 0), writes
--      nothing, and offers it again only after two hours;
--   3-4. asked -> answered by a stub model -> a refused bet comes back once -> filed: the passed bets are ceo.order hand-overs to
--      their seats, the CEO's raise_invite_cap is recorded as his ask, the request carried the registration target;
--   5. measured a week later against the registration target (registration_result);
--   6. cost: an unpriced call counts its measured tokens x model_rate; the call cap closes a plan;
--   7. the ramp keeps the last word: the ask lifts a healthy growth step, never a hold, a back-off or a pause;
--   8. the daily number is on, with the CEO's reason.
create function pg_temp.probe_lead(p_dom text, p_i int) returns bigint language plpgsql as $h$
declare v_id bigint; v_to text := 'buyer' || p_i || '.' || md5(random()::text) || '@' || p_dom;
begin
  insert into public.leads (company_name, email, email_verified) values ('Probe ' || p_dom || ' ' || p_i, v_to, 'verified') returning id into v_id;
  perform public.fn_sales_engineer_records_email_checks(jsonb_build_array(jsonb_build_object('lead_id', v_id, 'email', v_to,
    'verdict', 'verified', 'reason', 'probe', 'mailbox', 'named', 'mx_kind', 'mx')), '[]'::jsonb);
  return v_id;
end $h$;
create function pg_temp.probe_send(p_lead bigint, p_at timestamptz, p_bounce boolean) returns bigint language plpgsql as $h$
declare v_nid bigint; v_to text := (select email from public.leads where id = p_lead);
begin
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, lang, status)
  values ('supplier_invite', v_to, 'supplier', p_lead, 'A question', replace((select value from public.app_secrets where key = 'invite_body'), '{{company}}', 'Probe'), 'en', 'queued')
  returning id into v_nid;
  update public.notifications set status = 'sent', sent_at = p_at, provider_status = case when p_bounce then 'undelivered' else 'sent' end,
         provider_error_code = case when p_bounce then 'bounce:5.1.1' end where id = v_nid;
  update public.leads set invite_status = case when p_bounce then 'bounced' else 'sent' end where id = p_lead;
  return v_nid;
end $h$;
create function pg_temp.ramp_note() returns text language sql as $h$
  select coalesce(note, '') || ' ' || coalesce(counts::text, '') from public.agent_runs where agent = 'invite_ramp' order by id desc limit 1
$h$;

do $probe$
declare
  v_tag text := substr(md5(clock_timestamp()::text), 1, 8); v_fail text := ''; v_r jsonb; v_q jsonb; v_n bigint; v_plan bigint; v_daily bigint;
  v_monday timestamptz; v_week date; v_due text := to_char(now() + interval '3 days', 'YYYY-MM-DD"T"HH24:MI:SSOF'); v_bets jsonb; v_out jsonb;
  v_dom text := 'qd-probe-ceo-' || md5(random()::text) || '.ae'; i int; v_cap int; v_spent numeric; v_calls int; v_orders int;
begin
  perform set_config('qd.duty_fixtures', 'on', true);
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  update public.decision_policy set value = value || '{"week_aed_cap": 8, "week_calls_cap": 14}'::jsonb where key = 'ceo_planning_loop';
  v_monday := (date_trunc('week', now() at time zone 'Asia/Dubai')::date + 7 + time '08:00') at time zone 'Asia/Dubai';
  v_week := (v_monday at time zone 'Asia/Dubai')::date;

  -- 0. THE HEARTBEAT BUILDS NOTHING: a Monday morning with no plan open; the door opens none and writes nothing
  select count(*) into v_n from public.ceo_plan_week;
  v_r := public.fn_ceo_plan_handover(v_monday + interval '30 minutes');
  if coalesce((v_r->>'call_model')::boolean, true) or (select count(*) from public.ceo_plan_week) <> v_n
    then v_fail := v_fail || '0: the heartbeat''s door opened a plan: ' || v_r::text || '; '; end if;
  if (select prosrc from pg_proc where oid = 'public.fn_ceo_plan_handover(timestamptz)'::regprocedure) ~ 'fn_ceo_planning_pack|fn_ceo_plan_measure|fn_ceo_priors_update|insert into'
    then v_fail := v_fail || '0: the hand-over builds a pack, measures or inserts; '; end if;
  if (select prosrc from pg_proc where oid = 'public.fn_ceo_planning_loop_tick()'::regprocedure) not like '%fn_ceo_plan_due(now(), true)%'
    then v_fail := v_fail || '0: the duty does not open plans; '; end if;

  -- 1. THE DUTY OPENS THE WEEKLY PLAN with its pack, and asks no model
  v_r := public.fn_ceo_plan_due(v_monday, true);
  v_plan := (v_r->>'plan_id')::bigint;
  if v_plan is null or (select status || '/' || attempts || '/' || (pack is not null) from public.ceo_plan_week where id = v_plan) <> 'asked/0/true'
    then v_fail := v_fail || '1: the duty did not open the weekly plan with its pack: ' || v_r::text || '; '; end if;
  if v_plan is null then raise exception 'CHK<<PROBE FAILED: %>>', v_fail; end if;

  -- 2. THE HEARTBEAT HANDS IT OVER AT ONCE, writes nothing, and offers it again only after two hours
  v_r := public.fn_ceo_plan_handover(v_monday + interval '30 minutes');
  if not coalesce((v_r->>'call_model')::boolean, false) or (v_r->>'plan_id')::bigint <> v_plan or (select attempts from public.ceo_plan_week where id = v_plan) <> 0
    then v_fail := v_fail || '2: a plan never handed was not handed at once, or the door wrote: ' || v_r::text || '; '; end if;

  -- 3. ASKED: the request carries the registration target, counts the call and keeps the reading on the plan
  v_q := public.fn_ceo_plan_request(v_plan);
  if not coalesce((v_q->>'ok')::boolean, false) or v_q->'input'->'registration_target'->>'needed_per_week' is null
     or (v_q->'input'->'registration_target'->>'target_low')::int <> 300 or not (v_q->'input' ? 'pack')
     or v_q->>'system' not like '%THE TARGET is 300 to 400 registered suppliers by 31 Dec 2026%' or v_q->>'system' not like '%raise_invite_cap%'
     or v_q->'output_schema'->'decision'->>'ceo_actions' not like '%raise_invite_cap%'
    then v_fail := v_fail || '3: the request does not carry the target or the cap action: ' || left(v_q::text, 300) || '; '; end if;
  if (select attempts from public.ceo_plan_week where id = v_plan) <> 1 or (select registration_target from public.ceo_plan_week where id = v_plan) is null
    then v_fail := v_fail || '3: the call was not counted or the target not kept on the plan; '; end if;
  if coalesce((public.fn_ceo_plan_handover(now() + interval '40 minutes')->>'call_model')::boolean, true)
    then v_fail := v_fail || '3: a plan being answered was handed out again within two hours; '; end if;
  if not coalesce((public.fn_ceo_plan_handover(now() + interval '3 hours')->>'call_model')::boolean, false)
    then v_fail := v_fail || '3: an unanswered plan was not offered again after two hours; '; end if;

  -- 4. ANSWERED (a stub model): two of the seed's safe bets, one bet addressed to the founder (refused), three CEO actions
  select jsonb_agg(b || jsonb_build_object('due_at', v_due)) into v_bets
    from public.ceo_plan_week s, jsonb_array_elements(s.output->'decision'->'bets') b
   where s.world = 'real' and s.kind = 'seed' and b->>'channel' in ('reply_within_1h', 'registration_unblock');
  if jsonb_array_length(coalesce(v_bets, '[]'::jsonb)) <> 2 then raise exception 'CHK<<PROBE FAILED: the seed''s two safe bets are missing>>'; end if;
  insert into public.app_secrets (key, value) values ('invite_daily_cap', '3') on conflict (key) do update set value = excluded.value;
  v_out := jsonb_build_object('situation', 'ZZ DEMO stub: 2 registered against 300 by 31 Dec; behind pace',
    'decision', jsonb_build_object('bets', v_bets || jsonb_build_array((v_bets->0) || '{"seat": "founder"}'::jsonb),
      'ceo_actions', jsonb_build_array(
        jsonb_build_object('kind', 'raise_invite_cap', 'to', 'many', 'reason', 'ZZ DEMO: a malformed ask must be refused with a reason'),
        jsonb_build_object('kind', 'raise_invite_cap', 'to', 20, 'reason', 'ZZ DEMO: the bounce judgement is healthy and 17,409 leads wait'),
        jsonb_build_object('kind', 'set_trade_priority', 'add', jsonb_build_array('hvac'), 'reason', 'ZZ DEMO: hvac has buyers waiting'))));
  v_r := public.fn_ceo_plan_file(v_plan, v_out, 'zz-demo/stub-model', null);
  if not coalesce((v_r->>'revise')::boolean, false) or (v_r->>'filed')::int <> 2 or (v_r->>'refused')::int <> 1
    then v_fail := v_fail || '4: the first answer was not filed 2 / refused 1 with a revision: ' || left(v_r::text, 400) || '; '; end if;
  if not exists (select 1 from jsonb_array_elements(v_r->'ceo_actions') a where a->>'reason' like '%whole number%')
    then v_fail := v_fail || '4: a malformed cap ask was not refused with its reason; '; end if;
  -- the revision: handed out once, answered by dropping the refused bet
  v_r := public.fn_ceo_plan_handover(now() + interval '50 minutes');
  if not coalesce((v_r->>'call_model')::boolean, false) then v_fail := v_fail || '4: the revision was not handed over: ' || v_r::text || '; '; end if;
  v_q := public.fn_ceo_plan_request(v_plan);
  if not (v_q->'input' ? 'refused_by_code') then v_fail := v_fail || '4: the revision request does not carry the refusals; '; end if;
  v_r := public.fn_ceo_plan_file(v_plan, '{"decision": {"bets": [], "dropped": [{"option": "the founder bet", "why": "ledger 1710: no bet on the founder"}]}}'::jsonb, 'zz-demo/stub-model', null);
  if (select status from public.ceo_plan_week where id = v_plan) <> 'filed' then v_fail := v_fail || '4: the plan is not filed after its revision: ' || v_r::text || '; '; end if;
  select count(*) into v_orders from public.ceo_plan_bet b join public.agent_actions a on a.id = b.handoff_id
   where b.plan_id = v_plan and b.status = 'filed' and a.kind = 'handoff' and a.agent = 'sales_engineer' and a.status = 'pending' and a.detail->>'path' = 'plan';
  if v_orders <> 2 then v_fail := v_fail || '4: ' || v_orders || ' ceo.order hand-overs to the sales engineer, not 2; '; end if;
  if public.fn_ceo_invite_cap_ask() is distinct from 20
     or not exists (select 1 from public.ceo_own_decision where world = 'demo' and choice = 'raise_invite_cap' and dedupe_key = 'plan:' || v_plan || ':raise_invite_cap')
    then v_fail := v_fail || '4: the CEO''s cap ask is not recorded as his ask: ' || coalesce(public.fn_ceo_invite_cap_ask()::text, 'none') || '; '; end if;
  if (select value from public.app_secrets where key = 'invite_daily_cap') <> '3' then v_fail := v_fail || '4: the plan moved the cap itself (only the ramp may); '; end if;
  if public.fn_ceo_plan_self_action(v_plan, '{"kind": "raise_invite_cap", "to": 2, "reason": "ZZ DEMO: a lower number is not a raise"}'::jsonb)->>'reason' not like '%asks for more%'
    then v_fail := v_fail || '4: an ask below the cap was accepted; '; end if;

  -- 5. MEASURED A WEEK LATER against the registration target (the daily number's own count)
  insert into public.ceo_supplier_funnel_daily (day, channel, submitted, approved) values (v_week + 1, 'zz_demo_' || v_tag, 2, 1), (v_week + 3, 'zz_demo_' || v_tag, 1, 0);
  v_r := public.fn_ceo_plan_due(v_monday + interval '7 days', true);
  v_q := (select registration_result from public.ceo_plan_week where id = v_plan);
  if v_q is null or (v_q->>'registered')::int <> 3 or (v_q->>'needed_per_week')::numeric is distinct from ((select registration_target from public.ceo_plan_week where id = v_plan)->>'needed_per_week')::numeric
     or (v_q->>'on_pace')::boolean is distinct from (3 >= (v_q->>'needed_per_week')::numeric) or v_q->>'verdict' not like '3 registered in the week of%'
    then v_fail := v_fail || '5: the week was not measured against the target: ' || coalesce(v_q::text, 'nothing') || ' / ' || left(v_r::text, 200) || '; '; end if;
  if (select count(*) from public.ceo_plan_bet where plan_id = v_plan and status in ('filed', 'met', 'missed')) <> 2
    then v_fail := v_fail || '5: the plan''s orders were not measured; '; end if;
  -- the next week's request carries this result
  v_n := (select id from public.ceo_plan_week where world = 'demo' and kind = 'weekly' and period = v_week + 7);
  if v_n is null or public.fn_ceo_plan_request(v_n)->'input'->'last_week_registrations'->>'registered' <> '3'
    then v_fail := v_fail || '5: the next week''s plan is not asked with last week''s result; '; end if;

  -- 6. COST: measured tokens x price for a call the log could not price; the call cap closes a plan without a call
  update public.ceo_plan_week set status = 'held' where world = 'demo' and status in ('asked', 'revise');
  insert into public.model_rate (model, tier, in_aed_per_mtok, out_aed_per_mtok, note) values ('zz-demo/opus-' || v_tag, 'xlarge', 10, 100, 'probe');
  v_spent := public.fn_ceo_plan_spend_7d();
  insert into public.ai_cost_log (occurred_at, fn, task_class, model_used, cached, ok, cost_aed, prompt_tokens, output_tokens)
  values (now() - interval '1 hour', 'ceo_agent', 'ceo_strategic_planning', 'zz-demo/opus-' || v_tag, false, true, 0, 100000, 50000);
  if public.fn_ceo_plan_spend_7d() - v_spent <> 6 then v_fail := v_fail || '6: an unpriced call counted AED ' || (public.fn_ceo_plan_spend_7d() - v_spent) || ', not its tokens x price (6); '; end if;
  v_calls := public.fn_ceo_plan_calls_7d();
  if v_calls < 3 then v_fail := v_fail || '6: the loop''s calls read ' || v_calls || ', not the 3 requests counted on the plans; '; end if;
  update public.decision_policy set value = value || jsonb_build_object('week_calls_cap', v_calls) where key = 'ceo_planning_loop';
  insert into public.ceo_plan_week (kind, period, status, task_class, anomalies, asked_at) values ('daily', (now() at time zone 'Asia/Dubai')::date, 'asked', 'routine_employee_reasoning', '[]', now())
  on conflict (world, kind, period) do update set status = 'asked', attempts = 0, error = null returning id into v_daily;
  v_r := public.fn_ceo_plan_handover(now());
  if coalesce((v_r->>'call_model')::boolean, true) or (select status from public.ceo_plan_week where id = v_daily) <> 'held'
     or (select error from public.ceo_plan_week where id = v_daily) not like '%week_calls_cap%'
    then v_fail := v_fail || '6: at the call cap a plan was handed to the model: ' || v_r::text || '; '; end if;
  update public.decision_policy set value = value || '{"week_calls_cap": 14}'::jsonb where key = 'ceo_planning_loop';
  delete from public.ai_cost_log where model_used = 'zz-demo/opus-' || v_tag;

  -- 7. THE RAMP KEEPS THE LAST WORD (the CEO's ask is 20, from step 4)
  insert into public.app_secrets (key, value) values ('invite_enabled', 'true'), ('supplier_outreach_golive', 'true'), ('invite_reachable_only', 'true'),
    ('invite_body', E'Hi {{company}} team,\n\nWould your company like to receive the requests of its trade?\n\nIf this isn''t relevant, reply "stop" and we won''t contact you again.'),
    ('invite_lane_enabled', 'false'), ('invite_daily_cap', '3'),
    ('invite_warmup', '{"base_cap": 20, "min_step": 2, "ceiling_cap": 50, "growth_factor": 1.5, "grow_if_used_pct": 0.8, "grow_max_hard_rate": 0.03, "backoff_hard_lb": 0.025, "ceo_ask_growth_factor": 2}')
  on conflict (key) do update set value = excluded.value;
  insert into public.email_domain_mx (domain, has_mx, kind, hosts) values (v_dom, true, 'mx', array['aspmx.l.google.com']);
  update public.notifications set sent_at = now() - interval '30 days' where type = 'supplier_invite' and sent_at > now() - interval '30 days';
  delete from public.agent_runs where agent = 'invite_ramp';
  -- 7a. healthy, the last send day full at 3: without an ask the ramp steps 3 -> 5 (the ramp's own probe); with the ask, 3 -> 6
  for i in 1..3 loop perform pg_temp.probe_send(pg_temp.probe_lead(v_dom, 1000 + i), now() - interval '2 hours', false); end loop;
  for i in 1..27 loop perform pg_temp.probe_send(pg_temp.probe_lead(v_dom, 2000 + i), now() - interval '5 days', false); end loop;
  v_cap := public.fn_invite_ramp();
  if v_cap <> 6 or pg_temp.ramp_note() not like '%"ceo_ask_applied": true%' then v_fail := v_fail || '7a: a healthy day with the ask stepped to ' || v_cap || ', not 6: ' || pg_temp.ramp_note() || '; '; end if;
  v_cap := public.fn_invite_ramp();
  if v_cap <> 6 then v_fail := v_fail || '7a: the ask made the ramp grow twice for one send day: ' || v_cap || '; '; end if;
  -- 7b. one hard bounce in 35: still healthy, the ask lifts the step 5 -> 10 (the ramp alone: 8)
  delete from public.agent_runs where agent = 'invite_ramp';
  update public.app_secrets set value = '5' where key = 'invite_daily_cap';
  for i in 1..5 loop perform pg_temp.probe_send(pg_temp.probe_lead(v_dom, 3000 + i), now() - interval '1 hour', i = 1); end loop;
  v_cap := public.fn_invite_ramp();
  if v_cap <> 10 then v_fail := v_fail || '7b: one bounce in 35 with the ask stepped to ' || v_cap || ', not 10: ' || pg_temp.ramp_note() || '; '; end if;
  -- 7c. two hard bounces in 36: the ramp HOLDS, whatever the CEO asked
  delete from public.agent_runs where agent = 'invite_ramp';
  perform pg_temp.probe_send(pg_temp.probe_lead(v_dom, 4001), now() - interval '50 minutes', true);
  update public.app_secrets set value = 'true' where key = 'invite_enabled';
  v_cap := public.fn_invite_ramp();
  if v_cap <> 10 or pg_temp.ramp_note() not like '%hold:%asks for 20: not applied today%' then v_fail := v_fail || '7c: the ask overrode a hold: ' || v_cap || ' ' || pg_temp.ramp_note() || '; '; end if;
  -- 7d. three in 37 (95% lower bound over 2.5%): the ramp BACKS OFF by half, whatever the CEO asked
  perform pg_temp.probe_send(pg_temp.probe_lead(v_dom, 4002), now() - interval '45 minutes', true);
  update public.app_secrets set value = 'true' where key = 'invite_enabled';
  v_cap := public.fn_invite_ramp();
  if v_cap <> 5 or pg_temp.ramp_note() not like '%back off:%not applied today%' then v_fail := v_fail || '7d: the ask overrode a back-off: ' || v_cap || ' ' || pg_temp.ramp_note() || '; '; end if;
  -- 7e. paused: the cap stays, the ask is named and not applied
  update public.app_secrets set value = 'false' where key = 'invite_enabled';
  v_cap := public.fn_invite_ramp();
  if v_cap <> 5 or pg_temp.ramp_note() not like '%not applied while paused%' then v_fail := v_fail || '7e: paused, the ask moved the cap: ' || v_cap || ' ' || pg_temp.ramp_note() || '; '; end if;
  -- 7f. with no ask the ramp is the one it was: healthy 3 -> 5
  delete from public.ceo_own_decision where world = 'demo' and choice = 'raise_invite_cap';
  delete from public.agent_runs where agent = 'invite_ramp';
  update public.notifications set sent_at = now() - interval '30 days' where to_email like '%@' || v_dom;
  update public.app_secrets set value = 'true' where key = 'invite_enabled';
  update public.app_secrets set value = '3' where key = 'invite_daily_cap';
  for i in 1..3 loop perform pg_temp.probe_send(pg_temp.probe_lead(v_dom, 5000 + i), now() - interval '2 hours', false); end loop;
  for i in 1..27 loop perform pg_temp.probe_send(pg_temp.probe_lead(v_dom, 6000 + i), now() - interval '5 days', false); end loop;
  v_cap := public.fn_invite_ramp();
  if v_cap <> 5 then v_fail := v_fail || '7f: without an ask the healthy ramp stepped to ' || v_cap || ', not 5: ' || pg_temp.ramp_note() || '; '; end if;

  -- 8. THE DAILY NUMBER IS ON, with the CEO's reason
  if (select value from public.app_secrets where key = 'ceo_daily_number_golive') <> 'true'
     or not exists (select 1 from public.ceo_own_decision where dedupe_key = 'switch:ceo_daily_number_golive:on:2026-11-16' and reason like '%Ledger 1450%')
    then v_fail := v_fail || '8: the daily number is not on with its reason; '; end if;

  -- 9. GRANTS: nobody outside the service reaches the new and changed routines
  if has_function_privilege('anon', 'public.fn_ceo_plan_handover(timestamptz)', 'execute') or has_function_privilege('authenticated', 'public.fn_ceo_plan_handover(timestamptz)', 'execute')
     or has_function_privilege('anon', 'public.fn_ceo_registration_target(timestamptz)', 'execute') or has_function_privilege('anon', 'public.fn_ceo_plan_calls_7d()', 'execute')
     or has_function_privilege('anon', 'public.fn_ceo_invite_cap_ask()', 'execute') or has_function_privilege('anon', 'public.fn_ceo_plan_score_registrations(timestamptz)', 'execute')
     or has_function_privilege('anon', 'public.fn_invite_ramp()', 'execute')
    then v_fail := v_fail || '9: a routine is open to anon or authenticated; '; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK: heartbeat builds nothing; asked -> answered -> ' || v_orders || ' orders filed -> measured 3 registered; the ramp decides' else 'PROBE FAILED: ' || v_fail end;
end $probe$;
