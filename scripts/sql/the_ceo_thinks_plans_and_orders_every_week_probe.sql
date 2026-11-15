-- PROBE for the_ceo_thinks_plans_and_orders_every_week.sql. Seat: ceo. It always raises CHK<<...>>, so every row it writes is
-- rolled back. Its world is its own: qd.duty_fixtures = 'on' makes every reading see ONLY demo rows (production's suppliers,
-- registrations and replies are invisible to it), its people are ZZ DEMO at @example.invalid, and it calls no model and no sender:
-- the model's answers are planted JSON, and the founder's summary is proved on its text, never sent.
-- It proves: the planning pack returns every section on a planted company and none is unavailable; registrations are counted by
-- first-touch source (the founder's people, an e-mail invitation); the founder's people are listed by step with no address; the
-- seeded first plan is filed by the loop's first run through the checks; a weekly plan opens on Monday with its pack and its
-- class; planted unsafe bets are refused with the reason (cold WhatsApp, LinkedIn automation, bulk SMS, ads, Microsoft mail, a
-- recipient who opted out, money over the company limits, asking the founder, a seat that does not exist, a measure code cannot
-- read, a date too far, a hire, a capability nobody has) and safe ones become ceo.order hand-overs with measure, target and due
-- date; a refusal goes back once and the second answer is filed; the bets are measured, met, closed by measure and missed; the
-- priors learn from recorded outcomes and never count a window twice; the daily review asks the model only on an anomaly; the
-- forecast's old "tell_founder" answer is the CEO's own decision and nothing reaches the founder; the stale compliance sources are
-- one directive to the it_engineer; no founder alert is written by any of it.
do $probe$
declare
  v_tag text := substr(md5(clock_timestamp()::text), 1, 8); v_fail text := ''; v_r jsonb; v_p jsonb; v_k text; v_n bigint; v_txt text;
  v_l1 bigint; v_l2 bigint; v_l3 bigint; v_l4 bigint; v_l5 bigint; v_sup bigint; v_im bigint; v_fu bigint; v_seed bigint; v_plan bigint;
  v_monday timestamptz; v_tuesday timestamptz; v_alerts int; v_b record; v_h bigint; v_due text := to_char(now() + interval '3 days', 'YYYY-MM-DD"T"HH24:MI:SSOF');
  v_cust uuid; v_hq bigint; v_week date;
begin
  perform set_config('qd.duty_fixtures', 'on', true);
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  select count(*) into v_alerts from public.founder_alerts;
  update public.app_secrets set value = 'false' where key = 'invite_enabled';
  insert into public.app_secrets (key, value) select 'invite_enabled', 'false' where not exists (select 1 from public.app_secrets where key = 'invite_enabled');
  update public.decision_policy set value = value || '{"max_bets_weekly": 20}'::jsonb where key = 'ceo_planning_loop';
  delete from public.ceo_plan_week where kind in ('weekly', 'daily');    -- the probe's own weeks and days

  -- ── fixtures: the founder's three people (started, submitted, approved), one invited registration, one who opted out, one
  -- verified HVAC supplier in Dubai, one dropped supplier reply
  insert into public.leads (company_name, email, owner_email_verified, portal_updated_at)
  values ('ZZ DEMO Plan Started ' || v_tag, 'plan-st-' || v_tag || '@example.invalid', true, now() - interval '9 days') returning id into v_l1;
  insert into public.leads (company_name, email, owner_email_verified, registration_submitted_at)
  values ('ZZ DEMO Plan Submitted ' || v_tag, 'plan-sb-' || v_tag || '@example.invalid', true, now() - interval '3 days') returning id into v_l2;
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'zz-demo-plan-probe/' || v_tag || '/licence.pdf'), ('supplier-docs', 'zz-demo-plan-probe/' || v_tag || '/profile.pdf');
  insert into public.leads (company_name, email, owner_email_verified, registration_submitted_at, phone, owner_phone_verified, signed_terms_path, license_doc_path, company_profile_doc_path)
  values ('ZZ DEMO Plan Approved ' || v_tag, 'plan-ap-' || v_tag || '@example.invalid', true, now() - interval '8 days', '+971500000001', true,
          'zz-demo-plan-probe/' || v_tag || '/terms.pdf', 'zz-demo-plan-probe/' || v_tag || '/licence.pdf', 'zz-demo-plan-probe/' || v_tag || '/profile.pdf') returning id into v_l3;
  update public.leads set verified = true, approval_status = 'approved', approved_at = now() - interval '7 days', approval_decided_by = 'sales_engineer' where id = v_l3;
  insert into public.marketing_first_touch (lead_id, utm_source, utm_medium, utm_campaign, landing_path, first_seen_at, recorded_at) values
    (v_l1, 'founder', 'whatsapp', '2026-11', '/portal', now() - interval '9 days', now() - interval '9 days'),
    (v_l2, 'founder', 'whatsapp', '2026-11', '/portal', now() - interval '9 days', now() - interval '9 days'),
    (v_l3, 'founder', 'whatsapp', '2026-11', '/portal', now() - interval '9 days', now() - interval '9 days');
  insert into public.leads (company_name, email, owner_email_verified, registration_submitted_at, invite_clicked_at)
  values ('ZZ DEMO Plan Invited ' || v_tag, 'plan-inv-' || v_tag || '@example.invalid', true, now() - interval '18 days', now() - interval '19 days') returning id into v_l4;
  -- the outbox refuses an invitation to a demo lead at insert (a07, BEFORE INSERT only): the probe records one already sent
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, channel, status, sent_at)
  values ('zz_demo_plan_probe', 'plan-inv-' || v_tag || '@example.invalid', 'supplier', v_l4, 'ZZ DEMO plan probe', 'ZZ DEMO plan probe', 'email', 'sent', now() - interval '20 days') returning id into v_n;
  update public.notifications set type = 'supplier_invite' where id = v_n;
  insert into public.leads (company_name, email, invite_status)
  values ('ZZ DEMO Plan Opted Out ' || v_tag, 'plan-out-' || v_tag || '@example.invalid', 'unsubscribed') returning id into v_l5;
  insert into public.leads (company_name, email, phone, owner_phone_verified, owner_email_verified, signed_terms_path, license_doc_path, company_profile_doc_path, service_emirates)
  values ('ZZ DEMO Plan HVAC ' || v_tag, 'plan-hvac-' || v_tag || '@example.invalid', '+971500000000', true, true, 'zz-demo-plan-probe/' || v_tag || '/terms.pdf',
          'zz-demo-plan-probe/' || v_tag || '/licence.pdf', 'zz-demo-plan-probe/' || v_tag || '/profile.pdf', array['Dubai']) returning id into v_sup;
  update public.leads set verified = true, approval_status = 'approved', approval_decided_by = 'sales_engineer' where id = v_sup;
  insert into public.supplier_capabilities (supplier_id, trades, confirmed_at) values (v_sup, array['hvac'], now());
  insert into public.inbound_messages default values returning id into v_im;
  insert into public.supplier_reply_followup (inbound_message_id, lead_id, to_email, intent, due_at, state, created_at)
  values (v_im, v_l4, 'plan-inv-' || v_tag || '@example.invalid', 'interested', now() - interval '20 hours', 'dropped', now() - interval '1 day') returning id into v_fu;

  -- the focus trades as targets (the coverage file's own routine), in the probe's world only
  update public.supplier_coverage_target set status = 'retired', retired_at = now() where status <> 'retired';
  perform public.fn_ceo_focus_targets('ZZ DEMO plan probe: the focus as targets');

  -- 1. THE PACK: every section, none unavailable, read from the probe's own world
  v_p := public.fn_ceo_planning_pack(7);
  foreach v_k in array array['at', 'days', 'world', 'operating_target', 'coverage', 'funnel', 'registrations_by_source', 'founder_network', 'placement',
                             'replies', 'demand', 'pool', 'spend', 'seats', 'rulings', 'channels', 'capabilities', 'last_plan', 'own_decisions'] loop
    if not (v_p ? v_k) then v_fail := v_fail || 'the pack has no ' || v_k || '; ';
    elsif jsonb_typeof(v_p->v_k) = 'object' and (v_p->v_k) ? 'unavailable' then v_fail := v_fail || 'pack section ' || v_k || ' unavailable: ' || (v_p->v_k->>'unavailable') || '; '; end if;
  end loop;
  if v_p->>'world' <> 'demo' then v_fail := v_fail || 'the probe read the real world; '; end if;
  if (v_p->'founder_network'->>'started')::int <> 3 or (v_p->'founder_network'->>'submitted')::int <> 2 or (v_p->'founder_network'->>'approved')::int <> 1
    then v_fail := v_fail || 'the founder''s people are not counted by step: ' || (v_p->'founder_network')::text || '; '; end if;
  if not exists (select 1 from jsonb_array_elements(v_p->'founder_network'->'stuck') x where x->>'company' = 'ZZ DEMO Plan Started ' || v_tag and x->>'step' = 'account made, documents not submitted')
     or not exists (select 1 from jsonb_array_elements(v_p->'founder_network'->'stuck') x where x->>'company' = 'ZZ DEMO Plan Submitted ' || v_tag and x->>'step' = 'submitted, waiting for our review')
     or exists (select 1 from jsonb_array_elements(v_p->'founder_network'->'stuck') x where x->>'company' like 'ZZ DEMO Plan Approved%')
    then v_fail := v_fail || 'the stuck list does not name his people and their step: ' || (v_p->'founder_network'->'stuck')::text || '; '; end if;
  if (v_p->'founder_network')::text like '%@%' or (v_p->'founder_network')::text like '%+971%' then v_fail := v_fail || 'the founder''s list carries a contact detail; '; end if;
  if (v_p->'registrations_by_source'->'totals'->'founder'->>'started')::int <> 3 or (v_p->'registrations_by_source'->'totals'->'email_invitation'->>'submitted')::int <> 1
    then v_fail := v_fail || 'registrations are not counted by first-touch source: ' || (v_p->'registrations_by_source'->'totals')::text || '; '; end if;
  if (v_p->'operating_target'->>'covered')::int <> 1 or (v_p->'operating_target'->>'target')::int <> 30 or not (v_p->'operating_target' ? 'milestone')
    then v_fail := v_fail || 'the operating target is not the focus coverage beside the milestone: ' || (v_p->'operating_target')::text || '; '; end if;
  if jsonb_array_length(v_p->'replies'->'unanswered') <> 1 then v_fail := v_fail || 'the dropped reply is not in the pack; '; end if;
  if (select count(*) from jsonb_array_elements(v_p->'channels') c where c->>'verdict' = 'refused' and coalesce(c->>'alternative', '') = '') > 0
     or (select count(*) from jsonb_array_elements(v_p->'channels') c where c->>'verdict' = 'refused') < 8
    then v_fail := v_fail || 'the register does not carry the refused channels with their alternatives; '; end if;

  -- 2. THE FIRST PLAN AS DATA: filed by the loop's first run, every bet through the checks
  select id into v_seed from public.ceo_plan_week where kind = 'seed';
  if v_seed is null then v_fail := v_fail || 'no seeded first plan; ';
  else
    update public.ceo_plan_week set status = 'asked' where id = v_seed;                  -- as at apply, whatever a local run did
    delete from public.ceo_plan_bet where plan_id = v_seed;
    insert into public.ceo_invite_trade_priority (trade, reason) values ('painting', 'ZZ DEMO plan probe: a priority the seed removes');
    v_r := public.fn_ceo_plan_due(now(), false);
    if not (v_r ? 'seed_filed') or (select status from public.ceo_plan_week where id = v_seed) <> 'filed' then v_fail := v_fail || 'the first run did not file the seed: ' || v_r::text || '; '; end if;
    for v_b in select * from public.ceo_plan_bet where plan_id = v_seed loop
      if v_b.status = 'filed' and (cardinality(v_b.refusal) > 0 or (v_b.handoff_id is null and coalesce(v_b.seat, 'founder') <> 'founder')) then
        v_fail := v_fail || 'seed bet ' || v_b.ord || ' filed without its order or with a refusal; '; end if;
      if v_b.status = 'refused' and cardinality(v_b.refusal) = 0 then v_fail := v_fail || 'seed bet ' || v_b.ord || ' refused with no reason; '; end if;
    end loop;
    if (select status from public.ceo_plan_bet where plan_id = v_seed and channel = 'founder_network') <> 'filed'
      then v_fail := v_fail || 'the founder''s network is not bet 1 of the first plan; '; end if;
    if (select array_to_string(refusal, ' ') from public.ceo_plan_bet where plan_id = v_seed and measure = 'invitations') not like '%invite_enabled%'
      then v_fail := v_fail || 'an invitation order was filed while invitations are off; '; end if;
    if exists (select 1 from public.ceo_invite_trade_priority where trade = 'painting' and cleared_at is null)
      then v_fail := v_fail || 'the seed''s own action did not clear painting; '; end if;
    if (select count(*) from public.ceo_own_decision where dedupe_key like 'plan:' || v_seed || ':%') <> 1 then v_fail := v_fail || 'the seed''s CEO action is not recorded; '; end if;
    if (select array_to_string(refusal, ' ') from public.ceo_plan_bet where plan_id = v_seed and measure = 'invitations') is null
       or (select measure_args->'trades' from public.ceo_plan_bet where plan_id = v_seed and measure = 'invitations') <> '["hvac", "interior_fitout", "building_materials"]'::jsonb
      then v_fail := v_fail || 'the seed''s invitation bet does not point at the focus trades; '; end if;
    if exists (select 1 from public.ceo_plan_bet where plan_id = v_seed and seat = 'founder' and handoff_id is not null) then v_fail := v_fail || 'the founder was handed an order; '; end if;
    -- the seed's orders are withdrawn so the planted week below is checked on its own (one open order per seat and measure)
    update public.ceo_plan_bet set status = 'withdrawn' where plan_id = v_seed and status = 'filed';
  end if;

  -- 3. THE WEEKLY PLAN opens on Monday with its pack and its class, and is handed out once
  v_monday := (date_trunc('week', now() at time zone 'Asia/Dubai')::date + 7 + time '08:00') at time zone 'Asia/Dubai';
  v_r := public.fn_ceo_plan_due(v_monday);
  v_plan := (v_r->>'plan_id')::bigint;
  if not coalesce((v_r->>'call_model')::boolean, false) or v_r->>'kind' <> 'weekly' or v_plan is null then v_fail := v_fail || 'no weekly plan on Monday: ' || v_r::text || '; '; end if;
  v_r := public.fn_ceo_plan_request(v_plan);
  if v_r->>'task_class' <> 'ceo_strategic_planning' or not (v_r->'input'->'pack' ? 'founder_network') or v_r->>'system' not like '%Never ask the founder anything%'
    then v_fail := v_fail || 'the weekly request is not the contract with the pack: ' || left(v_r::text, 300) || '; '; end if;
  perform public.fn_ceo_plan_due(v_monday);
  if (select count(*) from public.ceo_plan_week where kind = 'weekly') <> 1 then v_fail := v_fail || 'a second weekly plan opened the same week; '; end if;

  -- 4. A STUBBED MODEL ANSWER: unsafe bets refused with the reason, safe ones ordered
  v_r := public.fn_ceo_plan_file(v_plan, jsonb_build_object('situation', 'ZZ DEMO plan probe', 'decision', jsonb_build_object('bets', jsonb_build_array(
    jsonb_build_object('channel', 'reply_within_1h', 'seat', 'customer_support', 'what', 'answer every reply within the hour', 'measure', 'replies_unanswered', 'target', 0, 'direction', 'at_most', 'due_at', v_due, 'expected_low', 1, 'expected_high', 2),
    jsonb_build_object('channel', 'whatsapp_cold_scraped', 'seat', 'customer_support', 'what', 'template to scraped mobiles', 'measure', 'reported', 'target', 1, 'due_at', v_due),
    jsonb_build_object('channel', 'linkedin_automation', 'seat', 'marketing', 'what', 'auto-connect', 'measure', 'reported', 'target', 1, 'due_at', v_due),
    jsonb_build_object('channel', 'bulk_sms', 'seat', 'customer_support', 'what', 'SMS blast', 'measure', 'reported', 'target', 1, 'due_at', v_due),
    jsonb_build_object('channel', 'paid_ads', 'seat', 'marketing', 'what', 'LinkedIn ads', 'measure', 'reported', 'target', 1, 'due_at', v_due, 'cost_aed', 500),
    jsonb_build_object('channel', 'email_microsoft_yahoo', 'seat', 'sales_engineer', 'what', 'mail Outlook hosts', 'measure', 'reported', 'target', 1, 'due_at', v_due),
    jsonb_build_object('channel', 'email_invitation_google', 'seat', 'sales_engineer', 'what', 'invite one who opted out', 'measure', 'reported', 'target', 1, 'due_at', v_due, 'lead_ids', jsonb_build_array(v_l5)),
    jsonb_build_object('channel', 'directories_chamber', 'seat', 'founder', 'what', 'ask the founder to apply', 'measure', 'reported', 'target', 1, 'due_at', v_due),
    jsonb_build_object('channel', 'directories_chamber', 'seat', 'ceo_assistant', 'what', 'a seat that does not exist', 'measure', 'reported', 'target', 1, 'due_at', v_due),
    jsonb_build_object('channel', 'directories_chamber', 'seat', 'marketing', 'what', 'no measure', 'measure', 'vibes', 'target', 1, 'due_at', v_due),
    jsonb_build_object('channel', 'directories_chamber', 'seat', 'marketing', 'what', 'too far', 'measure', 'reported', 'target', 1, 'due_at', to_char(now() + interval '90 days', 'YYYY-MM-DD"T"HH24:MI:SSOF')),
    jsonb_build_object('channel', 'hired_caller', 'seat', 'sales_engineer', 'what', 'hire a caller', 'measure', 'reported', 'target', 1, 'due_at', v_due),
    jsonb_build_object('channel', 'supplier_referral', 'seat', 'sales_engineer', 'what', 'run referrals before they exist', 'measure', 'reported', 'target', 1, 'due_at', v_due),
    jsonb_build_object('channel', 'deliverability_fix', 'seat', 'it_engineer', 'what', 'Microsoft at least 80%', 'measure', 'placement_inbox_pct', 'measure_args', jsonb_build_object('provider_class', 'microsoft'), 'target', 80, 'due_at', v_due),
    jsonb_build_object('channel', 'directories_chamber', 'seat', 'marketing', 'what', 'Chamber listing for AED 20', 'measure', 'reported', 'target', 1, 'due_at', v_due, 'cost_aed', 20)
  ))), 'stub/model', null);
  if not coalesce((v_r->>'revise')::boolean, false) or (v_r->>'filed')::int <> 3 or (v_r->>'refused')::int <> 12 then v_fail := v_fail || 'the checks did not split 3 filed / 12 refused with a revision: ' || left(v_r::text, 600) || '; '; end if;
  for v_k, v_txt in values
    (2, '%refused: Meta Business Messaging Policy%The alternative: The click-to-chat link%'), (3, '%LinkedIn User Agreement%'), (4, '%ledger 1185%'),
    (5, '%ledger 1456%'), (6, '%instruction 1537%'), (7, '%opt-out: the person unsubscribed%'), (8, '%the founder is not asked%'), (9, '%no such seat to order: ceo_assistant%'),
    (10, '%no measure code can read: vibes%'), (11, '%a due date between 12 hours%'), (12, '%ledger 1709%'), (13, '%no seat can do supplier_referral today%') loop
    if (select array_to_string(refusal, ' | ') from public.ceo_plan_bet where plan_id = v_plan and revision = 0 and ord = v_k::int) not like v_txt then
      v_fail := v_fail || 'bet ' || v_k || ' not refused with its reason (' || v_txt || '): ' || coalesce((select array_to_string(refusal, ' | ') from public.ceo_plan_bet where plan_id = v_plan and revision = 0 and ord = v_k::int), 'filed') || '; ';
    end if;
  end loop;
  if (select array_to_string(refusal, ' ') from public.ceo_plan_bet where plan_id = v_plan and ord = 5) not like '%company limits: AED 500%per-action limit%'
    then v_fail := v_fail || 'money over the company limit was not refused by the limits; '; end if;
  for v_b in select b.*, a.agent, a.status as hstatus, a.detail from public.ceo_plan_bet b left join public.agent_actions a on a.id = b.handoff_id
              where b.plan_id = v_plan and b.status = 'filed' loop
    if v_b.handoff_id is null or v_b.agent is distinct from v_b.seat or v_b.detail->>'type' <> 'ceo.order' or v_b.detail->>'path' <> 'plan'
       or v_b.detail->>'measure' <> v_b.measure or v_b.detail->>'due_at' is null or v_b.hstatus <> 'pending' then
      v_fail := v_fail || 'filed bet ' || v_b.ord || ' is not a pending ceo.order with its measure and date in the seat''s queue; ';
    end if;
  end loop;
  -- the revision: the request carries the refusals; the second answer is filed whatever is refused in it, and no third call
  v_r := public.fn_ceo_plan_request(v_plan);
  if jsonb_array_length(coalesce(v_r->'input'->'refused_by_code', '[]'::jsonb)) <> 12 then v_fail := v_fail || 'the revision request does not carry the refusals; '; end if;
  v_r := public.fn_ceo_plan_file(v_plan, jsonb_build_object('decision', jsonb_build_object('bets', jsonb_build_array(
    jsonb_build_object('channel', 'linkedin_company_page', 'seat', 'marketing', 'what', 'three company-page posts', 'measure', 'registrations_by_source', 'measure_args', jsonb_build_object('source', 'linkedin'), 'target', 1, 'due_at', v_due),
    jsonb_build_object('channel', 'paid_ads', 'seat', 'marketing', 'what', 'ads again', 'measure', 'reported', 'target', 1, 'due_at', v_due)))), 'stub/model', null);
  if coalesce((v_r->>'revise')::boolean, true) or (v_r->>'filed')::int <> 1 or (select status from public.ceo_plan_week where id = v_plan) <> 'filed'
    then v_fail := v_fail || 'the revision was not filed once and for all: ' || v_r::text || '; '; end if;
  if (public.fn_ceo_plan_request(v_plan)->>'ok')::boolean then v_fail := v_fail || 'a filed plan was handed to the model again; '; end if;
  -- a broken answer is never a plan: asked again, then held
  insert into public.ceo_plan_week (kind, period, status, attempts) values ('daily', date '2099-01-06', 'asked', 1) returning id into v_seed;
  v_r := public.fn_ceo_plan_file(v_seed, null, 'stub/model', 'the answer was not a JSON object');
  if (select status from public.ceo_plan_week where id = v_seed) <> 'asked' then v_fail := v_fail || 'a first broken answer was not asked again; '; end if;
  update public.ceo_plan_week set attempts = 2 where id = v_seed;
  perform public.fn_ceo_plan_file(v_seed, '{"decision": {}}'::jsonb, 'stub/model', null);
  if (select status from public.ceo_plan_week where id = v_seed) <> 'held' or exists (select 1 from public.ceo_plan_bet where plan_id = v_seed)
    then v_fail := v_fail || 'a second broken answer was filed instead of held; '; end if;

  -- 5. MEASURE: the reply order is met once the reply is answered, closed by its measure after 20 hours unreported; a past due
  -- bet is missed
  perform public.fn_ceo_plan_measure(now());
  if (select status from public.ceo_plan_bet where plan_id = v_plan and ord = 1 and revision = 0) <> 'filed' then v_fail := v_fail || 'the reply order counted as met with a dropped reply; '; end if;
  update public.supplier_reply_followup set state = 'sent', done_at = now() where id = v_fu;
  perform public.fn_ceo_plan_measure(now());
  select * into v_b from public.ceo_plan_bet where plan_id = v_plan and ord = 1 and revision = 0;
  if v_b.status <> 'met' or v_b.actual <> 0 then v_fail := v_fail || 'the answered reply did not meet the order: ' || v_b.status || '; '; end if;
  perform public.fn_ceo_plan_measure(now() + interval '21 hours');
  if (select status from public.agent_actions where id = v_b.handoff_id) <> 'done' then v_fail := v_fail || 'a met order unreported for 20 hours was not closed by its measure; '; end if;
  perform public.fn_ceo_plan_measure(now() + interval '30 days');
  if (select status from public.ceo_plan_bet where plan_id = v_plan and channel = 'deliverability_fix') <> 'missed' then v_fail := v_fail || 'a bet past its date was not missed; '; end if;
  if (public.fn_ceo_plan_calibration(v_plan)->>'scored')::int < 1 then v_fail := v_fail || 'the calibration scored nothing; '; end if;

  -- 6. LEARN: the founder's 3 started 9 days ago -> 2 submitted; one invitation 20 days ago -> submitted; no window twice
  update public.ceo_growth_channel set alpha = 1, beta = 1, trials = 0, successes = 0, measured_until = now() - interval '10 days' where channel = 'founder_network';
  update public.ceo_growth_channel set alpha = 1, beta = 114, trials = 0, successes = 0, measured_until = now() - interval '10 days' where channel = 'email_invitation_google';
  update public.ceo_growth_channel set measured_until = now() where channel not in ('founder_network', 'email_invitation_google');
  perform public.fn_ceo_priors_update(now());
  if (select alpha::text || '/' || beta::text from public.ceo_growth_channel where channel = 'founder_network') <> '3/2'
    then v_fail := v_fail || 'the founder prior did not learn 2 of 3: ' || (select alpha || '/' || beta from public.ceo_growth_channel where channel = 'founder_network') || '; '; end if;
  if (select alpha::text || '/' || beta::text from public.ceo_growth_channel where channel = 'email_invitation_google') <> '2/114'
    then v_fail := v_fail || 'the e-mail prior did not learn 1 of 1: ' || (select alpha || '/' || beta from public.ceo_growth_channel where channel = 'email_invitation_google') || '; '; end if;
  perform public.fn_ceo_priors_update(now() + interval '2 hours');
  if (select alpha::text || '/' || beta::text from public.ceo_growth_channel where channel = 'founder_network') <> '3/2' then v_fail := v_fail || 'a window was counted twice; '; end if;

  -- 7. THE DAILY REVIEW asks the model only on an anomaly, on the cheap class
  v_tuesday := v_monday + interval '1 day';
  if (select count(*) from jsonb_array_elements(public.fn_ceo_plan_anomalies(now())) a where a->>'kind' = 'founder_people_stuck') <> 1
    then v_fail := v_fail || 'the founder''s people stuck two days are not an anomaly; '; end if;
  v_r := public.fn_ceo_plan_due(v_tuesday);
  if not coalesce((v_r->>'call_model')::boolean, false) or v_r->>'kind' <> 'daily' or (select task_class from public.ceo_plan_week where id = (v_r->>'plan_id')::bigint) <> 'routine_employee_reasoning'
    then v_fail := v_fail || 'an anomaly did not open a daily review on the routine class: ' || v_r::text || '; '; end if;
  delete from public.marketing_first_touch where lead_id in (v_l1, v_l2, v_l3);
  delete from public.supplier_reply_followup where id = v_fu;
  update public.ceo_plan_bet set status = 'withdrawn' where status = 'missed';
  update public.ceo_plan_week set status = 'filed' where kind = 'daily' and status = 'asked';     -- the Tuesday review was answered
  v_r := public.fn_ceo_plan_due(v_tuesday + interval '1 day');
  if coalesce((v_r->>'call_model')::boolean, true) or v_r->>'daily' <> 'measured' then v_fail := v_fail || 'a day without an anomaly called the model: ' || v_r::text || '; '; end if;

  -- 8. NO FOUNDER ASK: the forecast offers no founder choice, and an old tell_founder answer is the CEO's own decision
  if pg_get_functiondef('public.fn_ceo_target_forecast()'::regprocedure) like '%"id":"tell_founder"%' then v_fail := v_fail || 'the forecast still offers tell_founder; '; end if;
  v_week := date '2099-01-05';
  insert into public.ceo_review (kind, period, facts) values ('target_forecast', v_week, '{"probe": "ZZ DEMO"}'::jsonb);
  insert into public.reasoning_held_question (seat, surface, question, request, reason, subject, dedupe_key)
  values ('ceo', 'ceo.target_forecast', 'ZZ DEMO plan probe forecast', jsonb_build_object('decision', jsonb_build_object('options', '[{"id":"hold_course"},{"id":"tell_founder"}]'::jsonb)),
          'probe', jsonb_build_object('kind', 'target_forecast', 'period', v_week), 'zz-demo-plan-probe:' || v_tag) returning id into v_hq;
  v_r := public.fn_ceo_review_applies(v_hq, jsonb_build_object('decision', jsonb_build_object('choice', 'tell_founder', 'fields', jsonb_build_object('proposal', jsonb_build_object('value', 'raise the daily limit to AED 60 for the Chamber listing'))), 'answer', 'the gap needs money', 'model', 'stub/model'));
  if v_r->'founder' is not null and v_r->>'founder' <> 'null' then v_fail := v_fail || 'the forecast reached the founder: ' || v_r::text || '; '; end if;
  if (select choice from public.ceo_own_decision where dedupe_key = 'target_forecast:' || v_week) is distinct from 'act_within_authority'
    then v_fail := v_fail || 'the old tell_founder answer is not the CEO''s own decision; '; end if;

  -- 8b. THE PLAN CHANGES THE FOCUS through the coverage file's own routine, with its reason
  v_r := public.fn_ceo_plan_self_action(v_plan, jsonb_build_object('kind', 'set_focus_trades', 'trades', jsonb_build_array('hvac'), 'reason', 'ZZ DEMO plan probe: hvac alone has buyers waiting'));
  if not coalesce((v_r->>'ok')::boolean, false) or public.fn_ceo_focus_trades() <> array['hvac']
     or exists (select 1 from public.supplier_coverage_target where trade = 'interior_fitout' and status = 'confirmed')
    then v_fail := v_fail || 'the plan could not change the focus through fn_ceo_sets_focus_trades: ' || v_r::text || '; '; end if;

  -- 9. THE SUMMARY tells the founder his people and the plan, asks nothing, carries no contact detail
  insert into public.marketing_first_touch (lead_id, utm_source, landing_path, recorded_at) values (v_l1, 'founder', '/portal', now() - interval '9 days'), (v_l2, 'founder', '/portal', now() - interval '9 days');
  v_txt := public.fn_ceo_plan_summary_text(now() - interval '1 day');
  if v_txt not like '%YOUR PEOPLE%2 started, 1 submitted, 0 approved%' or v_txt not like '%Plan Started ' || v_tag || ' - account made, documents not submitted%'
     or v_txt not like '%THE CEO''S PLAN%'
    then v_fail := v_fail || 'the summary does not tell the founder his people and the plan: ' || left(v_txt, 700) || '; '; end if;
  if v_txt like '%@%' or v_txt ~* '(please (approve|confirm)|your approval|reply (yes|with)|do you (approve|agree)|needs your decision)' then v_fail := v_fail || 'the summary carries an address or asks him something; '; end if;

  -- 10. BUSY-WORK: stale compliance sources are one directive to the it_engineer, none to the CEO
  insert into public.compliance_sources (authority, topic, url, active, last_checked_at) values
    ('ZZ DEMO authority A', 'plan probe', 'https://example.invalid/a', true, now() - interval '60 days'),
    ('ZZ DEMO authority B', 'plan probe', 'https://example.invalid/b', true, null);
  delete from public.ceo_directive where source_kind = 'register_review' and source_ref like 'compliance_sources:%';
  perform public.fn_ceo_register_review();
  if (select count(*) from public.ceo_directive where source_kind = 'register_review' and source_ref like 'compliance_sources:%' and seat = 'ceo') <> 0
     or (select count(*) from public.ceo_directive where source_kind = 'register_review' and source_ref like 'compliance_sources:batch:%' and seat = 'it_engineer') <> 1
    then v_fail := v_fail || 'the compliance re-checks are not one batch to the it_engineer; '; end if;

  -- nothing in any of it wrote a founder alert
  if (select count(*) from public.founder_alerts) <> v_alerts then v_fail := v_fail || 'a founder alert was written; '; end if;

  if v_fail <> '' then raise exception 'CHK<<PROBE FAILED: %>>', v_fail; end if;
  raise exception 'CHK<<PROBE OK: pack % sections, plan % filed / % refused>>', (select count(*) from jsonb_object_keys(v_p)),
    (select count(*) from public.ceo_plan_bet where plan_id = v_plan and status <> 'refused'), (select count(*) from public.ceo_plan_bet where plan_id = v_plan and status = 'refused');
end $probe$;
