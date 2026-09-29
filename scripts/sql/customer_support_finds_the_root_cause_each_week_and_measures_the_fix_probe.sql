-- PROBE: CUSTOMER SUPPORT FINDS THE ROOT CAUSE EACH WEEK AND MEASURES THE FIX. Seat: customer_support.
--
-- Pure probe: no DDL, never applied. Run it through node scripts/qsql.mjs AFTER
-- customer_support_finds_the_root_cause_each_week_and_measures_the_fix.sql is live. Before merge it was run as
-- #1036's file, that file and this one in ONE transaction that the final raise rolls back.
--
-- Everything happens inside a block that always raises, so nothing survives; pg_net sends only committed rows.
-- The parties are ZZ DEMO customers on @example.invalid and the reserved demo handset +971 50 000 0077, created
-- inside the block, and the weekly run is made with qd.duty_fixtures = 'on', so it reads only ZZ DEMO cases.
--
-- VERDICT (in the error text): CHK<<PROBE OK ...>> only if
--   1. two WhatsApp cases whose menu choice is qd_problem are category problem_report with tag topic:uploads —
--      although their text says "invoice refund", which is billing wording: the category comes from the menu,
--      never from the words;
--   2. two widget cases the assistant could not answer are knowledge_gap / unanswered;
--   3. the weekly run groups them into those two causes, hands problem_report to it_engineer as a
--      support.root_cause handoff (accepted by the handler, awaiting customer_support), and opens knowledge_gap for
--      support itself;
--   4. the fix door refuses a missing target and a cause another seat owns; an FAQ tagged root_cause:<id> records
--      the fix by itself and moves the cause to measuring;
--   5. two weeks on: the handed-off cause with no new case FELL and its handoff is done (closed by
--      customer_support); the support cause with a new case at its baseline did NOT fall and is open again;
--   6. no real (non-fixture) root cause or cause-week row was touched.
do $probe$
declare
  v_a uuid; v_b uuid; v_rc_it public.support_root_cause; v_rc_kg public.support_root_cause; v_n int; v_r jsonb; v_faq bigint;
  v_real_rc_before bigint; v_real_rc_after bigint; v_real_w_before bigint; v_real_w_after bigint; v_fail text := ''; v_err text;
  v_cases text; v_h public.agent_actions;
begin
  select count(*) into v_real_rc_before from public.support_root_cause where not fixture;
  select count(*) into v_real_w_before from public.support_cause_week where not fixture;
  perform set_config('qd.duty_fixtures', 'on', true);

  insert into public.customers (full_name, email, phone, phone_verified, whatsapp_opt, email_verified)
  values ('ZZ DEMO root cause A', 'zz.demo.rootcause.a@example.invalid', '+971500000077', true, 'same', true) returning id into v_a;
  insert into public.customers (full_name, email, email_verified)
  values ('ZZ DEMO root cause B', 'zz.demo.rootcause.b@example.invalid', true) returning id into v_b;

  -- 1. WhatsApp, menu qd_problem, twice (the first case is closed before the second message)
  insert into public.wa_messages (wa_from, wa_to, inbound, reply, lang, sent, meta)
  values ('whatsapp:+971500000077', 'whatsapp:+971000000000', 'ZZ DEMO my invoice refund upload fails', 'Checking', 'en', true,
          '{"audience":"customer","choice":"qd_problem","topics":["uploads"]}');
  update public.support_case set state = 'closed', closed_at = now(), close_reason = 'ZZ DEMO probe'
   where customer_profile_id = (select id from public.support_customer_profile where customer_id = v_a) and state <> 'closed';
  insert into public.wa_messages (wa_from, wa_to, inbound, reply, lang, sent, meta)
  values ('whatsapp:+971500000077', 'whatsapp:+971000000000', 'ZZ DEMO invoice refund upload still fails', 'Checking', 'en', true,
          '{"audience":"customer","choice":"qd_problem","topics":["uploads"]}');
  select string_agg(coalesce(c.category, 'NULL') || '[' || array_to_string(c.topic_tags, ',') || ']', ' ') into v_cases
    from public.support_case c join public.support_customer_profile p on p.id = c.customer_profile_id where p.customer_id = v_a;
  select count(*) into v_n from public.support_case c join public.support_customer_profile p on p.id = c.customer_profile_id
   where p.customer_id = v_a and c.category = 'problem_report' and 'topic:uploads' = any (c.topic_tags);
  if v_n <> 2 then v_fail := v_fail || ' whatsapp cases: ' || coalesce(v_cases, 'none') || ';'; end if;

  -- 2. the widget could not answer, twice
  insert into public.assistant_logs (message, reply, audience, path, answered, seat)
  values ('ZZ DEMO can I pay by cheque', null, 'customer:' || v_b, '/en/how-it-works', false, 'customer_support');
  update public.support_case set state = 'closed', closed_at = now(), close_reason = 'ZZ DEMO probe'
   where customer_profile_id = (select id from public.support_customer_profile where customer_id = v_b) and state <> 'closed';
  insert into public.assistant_logs (message, reply, audience, path, answered, seat)
  values ('ZZ DEMO cheque payment again', null, 'customer:' || v_b, '/en/how-it-works', false, 'customer_support');
  select count(*) into v_n from public.support_case c join public.support_customer_profile p on p.id = c.customer_profile_id
   where p.customer_id = v_b and c.category = 'knowledge_gap' and 'unanswered' = any (c.topic_tags);
  if v_n <> 2 then v_fail := v_fail || ' widget cases ' || v_n || ';'; end if;

  -- 3. the weekly run
  v_r := public.fn_customer_support_root_cause_week();
  select * into v_rc_it from public.support_root_cause where fixture and cause_key = 'problem_report/topic:uploads';
  select * into v_rc_kg from public.support_root_cause where fixture and cause_key = 'knowledge_gap/unanswered';
  if v_rc_it.id is null or v_rc_it.status <> 'handed_off' or v_rc_it.owner_seat <> 'it_engineer' or v_rc_it.baseline_per_week <> 2 then
    v_fail := v_fail || ' it cause: ' || coalesce(to_jsonb(v_rc_it)::text, 'none') || ' run ' || v_r::text || ';'; end if;
  select * into v_h from public.agent_actions where id = v_rc_it.handoff_id;
  if v_h.id is null or v_h.agent <> 'it_engineer' or v_h.detail->>'type' <> 'support.root_cause' or v_h.status <> 'pending'
     or v_h.evidence->>'accepted' is distinct from 'true' then
    v_fail := v_fail || ' handoff: ' || coalesce(to_jsonb(v_h)::text, 'none') || ';'; end if;
  if v_rc_kg.id is null or v_rc_kg.status <> 'open' or v_rc_kg.handoff_id is not null then
    v_fail := v_fail || ' support cause: ' || coalesce(to_jsonb(v_rc_kg)::text, 'none') || ';'; end if;

  -- 4. the fix door
  begin
    perform public.fn_support_root_cause_fix(v_rc_kg.id, 'faq', 'company_faq', '-1');
    v_fail := v_fail || ' a missing FAQ was accepted as a fix;';
  exception when others then v_err := sqlerrm; end;
  begin
    perform public.fn_support_root_cause_fix(v_rc_it.id, 'wording', 'support_signal_category', 'wa_choice:qd_problem');
    v_fail := v_fail || ' support recorded a fix on the IT engineer''s cause;';
  exception when others then null; end;
  insert into public.company_faq (section, question, answer, status, tags)
  values ('Payments', 'ZZ DEMO Can I pay by cheque?', 'ZZ DEMO No: card payments only.', 'draft', array['root_cause:' || v_rc_kg.id])
  returning id into v_faq;
  select * into v_rc_kg from public.support_root_cause where id = v_rc_kg.id;
  select count(*) into v_n from public.support_root_cause_fix where root_cause_id = v_rc_kg.id and target_table = 'company_faq' and target_id = v_faq::text;
  if v_n <> 1 or v_rc_kg.status <> 'measuring' then v_fail := v_fail || ' FAQ fix not recorded: ' || v_n || ' ' || v_rc_kg.status || ';'; end if;

  -- 5. two weeks on: the four cases fall before the change; one new knowledge-gap case after it, at a baseline of 0.5
  update public.support_root_cause set acted_at = now() - interval '15 days' where id in (v_rc_it.id, v_rc_kg.id);
  update public.support_root_cause set baseline_per_week = 0.5 where id = v_rc_kg.id;
  update public.support_case c set opened_at = now() - interval '20 days'
    from public.support_customer_profile p where p.id = c.customer_profile_id and p.customer_id in (v_a, v_b);
  update public.support_case set state = 'closed', closed_at = now(), close_reason = 'ZZ DEMO probe'
   where customer_profile_id = (select id from public.support_customer_profile where customer_id = v_b) and state <> 'closed';
  insert into public.assistant_logs (message, reply, audience, path, answered, seat)
  values ('ZZ DEMO cheque once more', null, 'customer:' || v_b, '/en/how-it-works', false, 'customer_support');
  v_r := public.fn_customer_support_root_cause_week();
  select * into v_rc_it from public.support_root_cause where id = v_rc_it.id;
  select * into v_rc_kg from public.support_root_cause where id = v_rc_kg.id;
  select * into v_h from public.agent_actions where id = v_rc_it.handoff_id;
  if v_rc_it.status <> 'fell' or v_h.status <> 'done' or v_h.evidence->>'verified_by' <> 'customer_support' then
    v_fail := v_fail || ' it cause did not close on the fall: ' || to_jsonb(v_rc_it)::text || ' handoff ' || v_h.status || ';'; end if;
  if v_rc_kg.status <> 'not_fallen' or v_rc_kg.measurements->-1->>'verdict' <> 'not_fallen' then
    v_fail := v_fail || ' support cause: ' || to_jsonb(v_rc_kg)::text || ';'; end if;

  -- 6. nothing real touched
  select count(*) into v_real_rc_after from public.support_root_cause where not fixture;
  select count(*) into v_real_w_after from public.support_cause_week where not fixture;
  if v_real_rc_after <> v_real_rc_before or v_real_w_after <> v_real_w_before then v_fail := v_fail || ' real rows changed;'; end if;

  if v_fail = '' then
    raise exception 'CHK<<PROBE OK: menu qd_problem -> problem_report despite billing words; unanswered -> knowledge_gap; it cause handed off (handoff %, accepted) and FELL %/wk vs 2 -> done by customer_support; support cause fixed by FAQ % then NOT fallen %/wk vs 0.5 -> open again; missing target refused (%); nothing real touched>>',
      v_h.id, v_rc_it.measurements->-1->>'after_per_week', v_faq, v_rc_kg.measurements->-1->>'after_per_week', v_err;
  end if;
  raise exception 'CHK<<PROBE FAILED:%>>', v_fail;
end $probe$;
