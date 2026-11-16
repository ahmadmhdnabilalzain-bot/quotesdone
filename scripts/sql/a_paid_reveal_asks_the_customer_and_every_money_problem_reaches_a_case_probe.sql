-- a_paid_reveal_asks_the_customer_and_every_money_problem_reaches_a_case_probe.sql (AFTER_REVEAL, customer_support builder, 16 Nov 2026)
-- A pure probe: run AFTER the file, in the SAME transaction, which this probe always aborts (raise 'CHK<<...>>'), so nothing it does
-- survives. Every subject is created here, ZZ DEMO, with an @example.invalid address and a number no person holds; the duty fixtures
-- switch is on (the ticks select only demo rows), and every message is demo-captured (written suppressed, never sent). The one
-- escalation to the CEO is filed under qd.probe_files_demo_handoff for this transaction only, so its row can be read.
-- 21 scenarios, each named in its failure. Run on a local Postgres 16 built from the schema mirror (scripts/db/local_pg16.mjs),
-- twice, 16 Nov 2026: PROBE OK both times.
do $probe$
declare
  v_cust uuid; v_other uuid; v_lead bigint; v_inq uuid; v_inq2 uuid; v_q uuid; v_q2 uuid; v_q3 uuid; v_q4 uuid;
  v_tx uuid; v_tx2 uuid; v_tx3 uuid; v_tx4 uuid; v_tx5 uuid; v_tx6 uuid; v_q5 uuid; v_tok uuid; v_h bigint; v_d bigint; v_rev timestamptz; k int;
  r jsonb; w jsonb; st jsonb; v_n int; v_real_refunds int; v_real_disputes int; v_real_statements int;
  v_phone constant text := '+971 50 000 7313';
  v_inq3 uuid; v_lead2 bigint; v_lead3 bigint; v_q7 uuid; v_q8 uuid; v_q9 uuid; v_tx7 uuid; v_tx8 uuid; v_tx9 uuid; v_d2 bigint; v_d3 bigint;
begin
  perform set_config('qd.duty_fixtures', 'on', true);
  select count(*) into v_real_refunds from public.refunds;
  select count(*) into v_real_disputes from public.post_reveal_dispute;
  select count(*) into v_real_statements from public.reveal_contact_statement;
  -- the conversation production holds (seat_handoff_kind is data, not schema)
  insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
  values ('sales.escalation', 'sales_engineer', 'ceo', 'probe copy of the production row', 'fn_ceo_takes_sales_escalation', interval '1 day', false, 'scripts/sql/the_sales_engineer_can_escalate_a_decision_to_the_ceo.sql')
  on conflict (type, from_seat, to_seat) do nothing;
  -- the lookup row production holds (fn_refund_request files a ceo_task in state open)
  insert into public.ceo_task_state (state, is_terminal, meaning) values ('open', false, 'probe copy') on conflict do nothing;

  insert into public.customers (full_name, email, phone, phone_verified, whatsapp_opt, locale)
  values ('ZZ DEMO afrev customer', 'zz-afrev-customer@example.invalid', v_phone, true, 'same', 'en') returning id into v_cust;
  insert into public.customers (full_name, email) values ('ZZ DEMO afrev other', 'zz-afrev-other@example.invalid') returning id into v_other;
  insert into public.leads (company_name, email) values ('ZZ DEMO afrev Waterproofing', 'zz-afrev-supplier@example.invalid') returning id into v_lead;
  insert into public.inquiries (customer_id, summary, status, rfq_no) values (v_cust, 'ZZ DEMO afrev roof waterproofing', 'revealed', 990731) returning id into v_inq;
  insert into public.inquiries (customer_id, summary, status, rfq_no) values (v_cust, 'ZZ DEMO afrev tiling', 'revealed', 990732) returning id into v_inq2;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, scope, warranty, lead_time, validity, status)
  values (v_inq, v_lead, 18000, 'ZZ DEMO 220 m2 torch-on membrane, two layers', '10 years on the membrane', '7 days', '30 days', 'revealed') returning id into v_q;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status) values (v_inq2, v_lead, 5000, 'revealed') returning id into v_q2;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, option_no) values (v_inq, v_lead, 19000, 'submitted', 2) returning id into v_q3;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, option_no) values (v_inq2, v_lead, 5100, 'submitted', 2) returning id into v_q4;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, total_charged, payment_ref, fee_status, revealed_at)
  values (v_q, v_inq, v_lead, v_cust, 18000, 540, 540, 'pi_zzdemo_afrev_1', 'paid', now() - interval '1 day') returning id into v_tx;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, total_charged, payment_ref, fee_status, revealed_at)
  values (v_q2, v_inq2, v_lead, v_cust, 5000, 150, 150, 'pi_zzdemo_afrev_2', 'paid', now() - interval '1 day') returning id into v_tx2;

  -- 1. the old signals still count: a supplier's acknowledgement alone is a response; the customer is TOLD of it, with the question
  r := public.fn_supplier_ack_record(v_tx);
  if not coalesce((r->>'recorded')::boolean, false) then raise exception 'CHK<<PROBE FAILED 1: the acknowledgement was not recorded: %>>', r; end if;
  if not coalesce((public.fn_refund_state(v_tx)->>'supplier_responded')::boolean, false) then
    raise exception 'CHK<<PROBE FAILED 1: an unanswered acknowledgement no longer counts as a response>>'; end if;
  if not exists (select 1 from public.customer_support_duty_message where stage = 'supplier_ack.customer' and subject_key = v_tx::text and customer_id = v_cust) then
    raise exception 'CHK<<PROBE FAILED 1: the customer was not written to about the acknowledgement>>'; end if;
  if not exists (select 1 from public.customer_followup where transaction_id = v_tx and stage = 'day_two_contact') then
    raise exception 'CHK<<PROBE FAILED 1: the acknowledgement notice carries no one-tap question>>'; end if;
  if exists (select 1 from public.notifications n where n.inquiry_id = v_inq and n.to_role = 'admin') then
    raise exception 'CHK<<PROBE FAILED 1: the acknowledgement went to role admin>>'; end if;
  -- 2. a second click changes nothing and writes to nobody again
  r := public.fn_supplier_ack_record(v_tx);
  if not coalesce((r->>'already')::boolean, false) then raise exception 'CHK<<PROBE FAILED 2: a second click recorded again: %>>', r; end if;

  -- 3. the customer says NO after the click: a conflict, the ladder keeps running, the CEO is handed both statements
  select token into v_tok from public.customer_followup where transaction_id = v_tx and stage = 'day_two_contact';
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  r := public.fn_customer_followup_answer(v_tok, null, null, 'ZZ DEMO nobody called me', 'no');
  perform set_config('qd.probe_files_demo_handoff', '', true);
  st := public.fn_refund_state(v_tx);
  if coalesce((st->>'supplier_responded')::boolean, true) or not coalesce((st->>'contact_conflict')::boolean, false) then
    raise exception 'CHK<<PROBE FAILED 3: a denial after the click did not keep the ladder running: %>>', st; end if;
  select a.id into v_h from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'sales.escalation'
     and a.detail->>'transaction_id' = v_tx::text order by a.id desc limit 1;
  if v_h is null then raise exception 'CHK<<PROBE FAILED 3: the CEO was not handed the conflict (%)>>', r; end if;
  if (select detail->>'escalation' from public.agent_actions where id = v_h) <> 'disputed_reveal'
     or (select detail->'case'->'customer_statement'->>'said' from public.agent_actions where id = v_h) <> 'no'
     or (select detail->'case'->'supplier_statement'->>'acknowledged_at' from public.agent_actions where id = v_h) is null then
    raise exception 'CHK<<PROBE FAILED 3: the escalation does not carry both statements: %>>', (select detail from public.agent_actions where id = v_h); end if;

  -- 4. working day 2 asked again after a "no": a "yes" now stands, and the ladder stops
  r := public.fn_customer_followup_answer(v_tok, null, null, null, 'yes');
  if not coalesce((public.fn_refund_state(v_tx)->>'supplier_responded')::boolean, false) then
    raise exception 'CHK<<PROBE FAILED 4: the customer''s yes did not stop the ladder>>'; end if;
  r := public.fn_customer_followup_answer(v_tok, null, null, null, 'no');
  if not coalesce((r->>'already')::boolean, false) then raise exception 'CHK<<PROBE FAILED 4: a yes was overwritten by a later tap: %>>', r; end if;
  -- 5. a yes followed by a no from another door: the yes stands (Terms clause 5: a response once given), no new conflict
  r := public.fn_reveal_contact_record(v_tx, 'no', 'whatsapp', 'ZZ DEMO he stopped answering', 'probe');
  w := public.fn_reveal_contact_word(v_tx);
  if not coalesce((w->>'responded')::boolean, false) or coalesce((w->>'conflict')::boolean, true) then
    raise exception 'CHK<<PROBE FAILED 5: a later no undid the customer''s own yes: %>>', w; end if;
  if (r->>'conflict_handoff') is not null then raise exception 'CHK<<PROBE FAILED 5: a no after a yes was escalated as a conflict>>'; end if;

  -- 6. no acknowledgement, the customer says YES on the page: a phone call is a response (Terms clause 5); the view knows it
  insert into public.customer_followup (transaction_id, stage, lang) values (v_tx2, 'day_two_contact', 'en') returning token into v_tok;
  r := public.fn_customer_followup_answer(v_tok, null, null, null, 'not_yet');
  if coalesce((public.fn_refund_state(v_tx2)->>'supplier_responded')::boolean, true) then
    raise exception 'CHK<<PROBE FAILED 6: "not yet" counted as a response>>'; end if;
  r := public.fn_customer_followup_answer(v_tok, null, null, null, 'yes');
  st := public.fn_refund_state(v_tx2);
  if st->>'state' <> 'supplier_responded' or st->>'customer_said' <> 'yes' then
    raise exception 'CHK<<PROBE FAILED 6: the customer''s yes without a click did not stop the ladder: %>>', st; end if;
  if not coalesce((public.fn_customer_followup_view(v_tok)->>'contact_known')::boolean, false) then
    raise exception 'CHK<<PROBE FAILED 6: the page would ask the contact question again>>'; end if;

  -- 7. a denial BEFORE the supplier's click: the click is newer, so it counts; the customer is asked again by the click's notice
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, total_charged, payment_ref, fee_status, revealed_at)
  values (v_q3, v_inq, v_lead, v_cust, 19000, 570, 570, 'pi_zzdemo_afrev_3', 'paid', now() - interval '2 days') returning id into v_tx3;
  r := public.fn_reveal_contact_record(v_tx3, 'no', 'portal', 'ZZ DEMO no call yet', 'probe');
  if coalesce((public.fn_refund_state(v_tx3)->>'supplier_responded')::boolean, true) then
    raise exception 'CHK<<PROBE FAILED 7: a denial with no claim counted as a response>>'; end if;
  perform pg_sleep(0.01);
  r := public.fn_supplier_ack_record(v_tx3);
  w := public.fn_reveal_contact_word(v_tx3);
  if not coalesce((w->>'responded')::boolean, false) or coalesce((w->>'conflict')::boolean, true) then
    raise exception 'CHK<<PROBE FAILED 7: a click after an earlier denial was not read as the newer statement: %>>', w; end if;

  -- 8. DAY 3: "No, never called, 1 star" writes NO review, keeps the refund door open, and is the customer's word for the ladder
  insert into public.customer_followup (transaction_id, stage, lang) values (v_tx3, 'day_three', 'en') returning token into v_tok;
  r := public.fn_customer_followup_answer(v_tok, 'no', 1, 'ZZ DEMO he never called back', 'no');
  if exists (select 1 from public.reviews where transaction_id = v_tx3) then
    raise exception 'CHK<<PROBE FAILED 8: a "never contacted" answer wrote a review: %>>', r; end if;
  if public.fn_refund_rating_shows_dealing(v_tx3) then raise exception 'CHK<<PROBE FAILED 8: the answer reads as dealing>>'; end if;
  r := public.fn_refund_open_from_customer(v_tx3, 'customer', null, 'portal');
  if not coalesce((r->>'ok')::boolean, false) then raise exception 'CHK<<PROBE FAILED 8: our own survey still bars the refund: %>>', r; end if;

  -- 8b. a 1-star rating pressed in the portal, then "he never contacted me": the rating is not a record of dealing, the door opens
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, option_no) values (v_inq, v_lead, 17500, 'revealed', 3) returning id into v_q5;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, total_charged, payment_ref, fee_status, revealed_at)
  values (v_q5, v_inq, v_lead, v_cust, 17500, 525, 525, 'pi_zzdemo_afrev_6', 'paid', now() - interval '3 days') returning id into v_tx6;
  insert into public.reviews (supplier_id, customer_id, inquiry_id, transaction_id, rating) values (v_lead, v_cust, v_inq, v_tx6, 1);
  r := public.fn_reveal_contact_record(v_tx6, 'no', 'widget', 'ZZ DEMO I rated him one star because he never called', 'probe');
  r := public.fn_refund_open_from_customer(v_tx6, 'customer', null, 'widget');
  if not coalesce((r->>'ok')::boolean, false) then raise exception 'CHK<<PROBE FAILED 8b: a rating given for silence bars the refund: %>>', r; end if;

  -- 9. a REAL rating (contact confirmed) still bars a non-response refund: the exclusion stays for dealing
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, total_charged, payment_ref, fee_status, revealed_at)
  values (v_q4, v_inq2, v_lead, v_cust, 5100, 153, 153, 'pi_zzdemo_afrev_4', 'paid', now() - interval '4 days') returning id into v_tx4;
  insert into public.customer_followup (transaction_id, stage, lang) values (v_tx4, 'day_three', 'en') returning token into v_tok;
  r := public.fn_customer_followup_answer(v_tok, 'no', 2, 'ZZ DEMO he came but charged more than quoted', 'yes');
  if not exists (select 1 from public.reviews where transaction_id = v_tx4) then
    raise exception 'CHK<<PROBE FAILED 9: a rating after contact was not written>>'; end if;
  if not (r->'recorded' ? 'dispute_intake') then
    raise exception 'CHK<<PROBE FAILED 9: a low rating after contact did not reach the dispute intake: %>>', r; end if;
  r := public.fn_refund_open_from_customer(v_tx4, 'customer', null, 'portal');
  if coalesce((r->>'ok')::boolean, true) or r->>'code' <> 'supplier_rated' then
    raise exception 'CHK<<PROBE FAILED 9: a real rating no longer bars a non-response refund: %>>', r; end if;

  -- 10. THE DOOR picks the job: none for a stranger, "which job" with two and no number, the right one by its number, never another's
  r := public.fn_customer_after_reveal_message(v_other, 'ZZ DEMO the supplier raised the price', 'portal', null);
  if r->>'code' <> 'no_revealed_job' then raise exception 'CHK<<PROBE FAILED 10: a customer with no reveal: %>>', r; end if;
  r := public.fn_customer_after_reveal_message(v_cust, 'ZZ DEMO the supplier raised the price', 'whatsapp', null);
  if r->>'code' <> 'which_job' or r->>'refs' !~ '990731' or r->>'refs' !~ '990732' then raise exception 'CHK<<PROBE FAILED 10: two jobs and no number: %>>', r; end if;
  r := public.fn_customer_after_reveal_message(v_cust, 'ZZ DEMO request ٩٩٠٧٣١: he now wants 24,000', 'whatsapp', null);
  if not coalesce((r->>'ok')::boolean, false) or r->>'rfq_no' <> '990731' then raise exception 'CHK<<PROBE FAILED 10: the job was not picked by its (Arabic-Indic) number: %>>', r; end if;
  r := public.fn_customer_after_reveal_message(v_other, 'ZZ DEMO help', 'portal', v_tx);
  if r->>'code' <> 'not_your_revealed_job' then raise exception 'CHK<<PROBE FAILED 10: another customer''s job was accepted: %>>', r; end if;
  r := public.fn_customer_after_reveal_message(v_cust, '   ', 'portal', v_tx);
  if r->>'code' <> 'empty' then raise exception 'CHK<<PROBE FAILED 10: an empty message was taken: %>>', r; end if;
  begin
    r := public.fn_customer_after_reveal_message(v_cust, 'ZZ DEMO x', 'fax', v_tx);
    raise exception 'CHK<<PROBE FAILED 10: an unknown door was accepted>>';
  exception when invalid_parameter_value then null; end;

  -- 11. WHATSAPP: the reasoned intent after_reveal from his confirmed number reaches the door and answers with what it did
  r := public.fn_wa_answer(v_phone, 'ZZ DEMO job 990732 the tiler left half the floor undone', 'after_reveal');
  if r->>'intent' <> 'after_reveal' or r->'actions'->0->'after_reveal'->>'rfq_no' <> '990732' or r->>'reply' !~ 'customer support' then
    raise exception 'CHK<<PROBE FAILED 11: the WhatsApp door did not reach the intake: %>>', r; end if;
  r := public.fn_wa_answer('+971 50 000 7399', 'ZZ DEMO my supplier never came', 'after_reveal');
  if r->>'reply' !~ 'do not recognise this number' then raise exception 'CHK<<PROBE FAILED 11: an unknown number reached the door: %>>', r; end if;

  -- 12-15. THE INTAKE'S READING ACTS (the apply, on held questions written as the reasoning queue writes them)
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, qhash, expires_at)
  values ('customer_support', 'customer_support.dispute_intake', 'ZZ DEMO probe', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('transaction_id', v_tx2, 'party', 'customer', 'statement', 'ZZ DEMO yes he phoned me on Sunday', 'channel', 'whatsapp'),
          'probe', 'probe:afrev:12', md5('afrev12'), now() + interval '1 day') returning id into v_h;
  r := public.fn_reason_apply_customer_support__dispute_intake(v_h, '{"decision":{"choice":"supplier_contacted"}}'::jsonb);
  if not exists (select 1 from public.reveal_contact_statement where transaction_id = v_tx2 and said = 'yes' and channel = 'whatsapp') then
    raise exception 'CHK<<PROBE FAILED 12: "the supplier contacted me" was not recorded: %>>', r; end if;
  -- 12b (review AFTERREVEAL item 5): that reading still answers him: a ticket (Terms clause 18) and a reply written by the model
  if r->>'ticket' !~ '^QD-C-' or not exists (select 1 from public.complaint_tickets where ticket_no = r->>'ticket' and email = 'zz-afrev-customer@example.invalid')
     or not exists (select 1 from public.customer_support_voice_owed where stage = 'dispute_intake.answer' and subject_key = v_h::text
                      and draft like '%' || (r->>'ticket') || '%' and to_email = 'zz-afrev-customer@example.invalid') then
    raise exception 'CHK<<PROBE FAILED 12b: "the supplier contacted me" left the customer without a ticket and a reply: %>>', r; end if;
  -- 12c (item 6): the SAME reading of a website-chat turn records nothing; he is asked to confirm with one tap, and told so
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, qhash, expires_at)
  values ('customer_support', 'customer_support.dispute_intake', 'ZZ DEMO probe', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('transaction_id', v_tx, 'party', 'customer', 'statement', 'ZZ DEMO ok thanks he called', 'channel', 'widget'),
          'probe', 'probe:afrev:12c', md5('afrev12c'), now() + interval '1 day') returning id into v_h;
  v_n := (select count(*) from public.reveal_contact_statement where transaction_id = v_tx);
  r := public.fn_reason_apply_customer_support__dispute_intake(v_h, '{"decision":{"choice":"supplier_contacted"}}'::jsonb);
  if (select count(*) from public.reveal_contact_statement where transaction_id = v_tx) <> v_n then
    raise exception 'CHK<<PROBE FAILED 12c: a widget reading wrote the customer''s word on contact: %>>', r; end if;
  if not coalesce((r->>'confirm_link')::boolean, false) or not exists (select 1 from public.customer_support_voice_owed where stage = 'dispute_intake.answer'
       and subject_key = v_h::text and draft like '%quotesdone.ae/u/followup?t=' || (select token from public.customer_followup where transaction_id = v_tx and stage = 'day_two_contact') || '%') then
    raise exception 'CHK<<PROBE FAILED 12c: the widget reading did not ask him to confirm with one tap: %>>', r; end if;
  -- 12d (item 5): "not a dispute" answers him too, with a ticket that stays open for the substantive answer
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, qhash, expires_at)
  values ('customer_support', 'customer_support.dispute_intake', 'ZZ DEMO probe', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('transaction_id', v_tx2, 'party', 'customer', 'statement', 'ZZ DEMO كم مدة الضمان على البلاط؟', 'channel', 'portal'),
          'probe', 'probe:afrev:12d', md5('afrev12d'), now() + interval '1 day') returning id into v_h;
  r := public.fn_reason_apply_customer_support__dispute_intake(v_h, '{"decision":{"choice":"not_dispute"}}'::jsonb);
  if (select status from public.complaint_tickets where ticket_no = r->>'ticket') is distinct from 'acknowledged'
     or not exists (select 1 from public.customer_support_voice_owed where stage = 'dispute_intake.answer' and subject_key = v_h::text and draft like '%' || (r->>'ticket') || '%') then
    raise exception 'CHK<<PROBE FAILED 12d: "not a dispute" left the customer without a ticket and a reply: %>>', r; end if;
  -- 13: "he never contacted me" opens the refund case through the one door, his word recorded once
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, total_charged, payment_ref, fee_status, revealed_at)
  values (null, v_inq2, v_lead, v_cust, 5200, 156, 156, 'pi_zzdemo_afrev_5', 'paid', now() - interval '3 days') returning id into v_tx5;
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, qhash, expires_at)
  values ('customer_support', 'customer_support.dispute_intake', 'ZZ DEMO probe', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('transaction_id', v_tx5, 'party', 'customer', 'statement', 'ZZ DEMO المورد ما رد، أبغى فلوسي', 'channel', 'whatsapp'),
          'probe', 'probe:afrev:13', md5('afrev13'), now() + interval '1 day') returning id into v_h;
  r := public.fn_reason_apply_customer_support__dispute_intake(v_h, '{"decision":{"choice":"supplier_not_contacted"}}'::jsonb);
  if not exists (select 1 from public.refunds where transaction_id = v_tx5 and reason_code = 'supplier_unresponsive' and requested_by = 'customer') then
    raise exception 'CHK<<PROBE FAILED 13: "he never contacted me" opened no refund case: %>>', r; end if;
  if (select count(*) from public.reveal_contact_statement where transaction_id = v_tx5 and said = 'no') <> 1 then
    raise exception 'CHK<<PROBE FAILED 13: his word was recorded % times, not once>>', (select count(*) from public.reveal_contact_statement where transaction_id = v_tx5); end if;
  -- 14: a dispute opens a case that carries the quotation he was given and the door it came through
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, qhash, expires_at)
  values ('customer_support', 'customer_support.dispute_intake', 'ZZ DEMO probe', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('transaction_id', v_tx, 'party', 'customer', 'statement', 'ZZ DEMO he quoted 18,000 and now says 24,000', 'channel', 'portal'),
          'probe', 'probe:afrev:14', md5('afrev14'), now() + interval '1 day') returning id into v_h;
  r := public.fn_reason_apply_customer_support__dispute_intake(v_h, '{"decision":{"choice":"dispute"}}'::jsonb);
  v_d := (r->>'dispute_id')::bigint;
  if v_d is null or (select job_facts->'quote'->>'amount_aed' from public.post_reveal_dispute where id = v_d) <> '18000'
     or (select job_facts->'quote'->>'warranty' from public.post_reveal_dispute where id = v_d) <> '10 years on the membrane'
     or (select channel from public.post_reveal_dispute where id = v_d) <> 'portal' then
    raise exception 'CHK<<PROBE FAILED 14: the case does not carry the quotation and its door: % / %>>', r, (select job_facts from public.post_reveal_dispute where id = v_d); end if;
  -- 15: a reading that is not an option is refused (and reasoned again); a supplier's message cannot be read as the customer's word
  begin
    r := public.fn_reason_apply_customer_support__dispute_intake(v_h, '{"decision":{"choice":"refund_now"}}'::jsonb);
    raise exception 'CHK<<PROBE FAILED 15: a reading outside the options was applied>>';
  exception when raise_exception then if sqlerrm !~ '^CHOICE_NOT_AN_OPTION' then raise; end if; end;
  update public.reasoning_held_question set subject = subject || '{"party":"supplier"}'::jsonb where id = v_h;
  begin
    r := public.fn_reason_apply_customer_support__dispute_intake(v_h, '{"decision":{"choice":"supplier_contacted"}}'::jsonb);
    raise exception 'CHK<<PROBE FAILED 15: a supplier''s message was applied as the customer''s word>>';
  exception when raise_exception then if sqlerrm !~ '^CHOICE_NOT_AN_OPTION' then raise; end if; end;

  -- 16. THE CEO DECIDES, AND THE DECISION ACTS: a remedy only on an upheld complaint; refund + matching paused + a strike on record
  update public.post_reveal_dispute set stage = 'ceo_decision' where id = v_d;
  begin
    r := public.fn_ceo_decides_post_reveal_dispute(v_d, 'supplier_upheld', 'ZZ DEMO', 'refund_reveal_fee', 'none');
    raise exception 'CHK<<PROBE FAILED 16: a refund followed a decision for the supplier>>';
  exception when raise_exception then if sqlerrm !~ 'follows only a complaint' then raise; end if; end;
  r := public.fn_ceo_decides_post_reveal_dispute(v_d, 'customer_upheld', 'ZZ DEMO the revealed quotation was 18,000 within validity', 'refund_reveal_fee', 'pause_matching');
  if not exists (select 1 from public.refunds where transaction_id = v_tx and reason_code = 'fraud_or_dispute' and requested_by = 'ceo_dispute_decision') then
    raise exception 'CHK<<PROBE FAILED 16: the CEO''s refund was not filed: %>>', r; end if;
  if not (select matching_blocked from public.leads where id = v_lead) or (select matching_block_reason from public.leads where id = v_lead) <> 'dispute_upheld' then
    raise exception 'CHK<<PROBE FAILED 16: matching was not paused>>'; end if;
  if not exists (select 1 from public.supplier_strike_event where lead_id = v_lead and kind = 'dispute_upheld' and detail->>'dispute_id' = v_d::text) then
    raise exception 'CHK<<PROBE FAILED 16: the upheld complaint is not on the supplier''s record>>'; end if;
  if public.fn_refund_dispute_basis(v_tx)->>'dispute_id' <> v_d::text then
    raise exception 'CHK<<PROBE FAILED 16: the refund does not name the decision it stands on>>'; end if;
  if not exists (select 1 from public.customer_support_duty_message where stage = 'dispute.decided' and subject_key = v_d || ':customer') then
    raise exception 'CHK<<PROBE FAILED 16: the customer was not told the decision>>'; end if;

  -- 17. "the next reveal refunded": filed when he pays it, on the same request, once
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, qhash, expires_at)
  values ('customer_support', 'customer_support.dispute_intake', 'ZZ DEMO probe', '{}'::jsonb, '{}'::jsonb,
          jsonb_build_object('transaction_id', v_tx4, 'party', 'customer', 'statement', 'ZZ DEMO he left the floor half done', 'channel', 'email'),
          'probe', 'probe:afrev:17', md5('afrev17'), now() + interval '1 day') returning id into v_h;
  v_d := (public.fn_reason_apply_customer_support__dispute_intake(v_h, '{"decision":{"choice":"dispute"}}'::jsonb)->>'dispute_id')::bigint;
  update public.post_reveal_dispute set stage = 'ceo_decision' where id = v_d;
  r := public.fn_ceo_decides_post_reveal_dispute(v_d, 'shared', 'ZZ DEMO', 'next_reveal_free', 'warning');
  r := public.fn_accountant_dispute_remedy_tick();
  if (select remedy_done_at from public.post_reveal_dispute where id = v_d) is not null then
    raise exception 'CHK<<PROBE FAILED 17: the remedy was spent before he revealed anyone: %>>', r; end if;
  update public.transactions set revealed_at = now() + interval '1 second' where id = v_tx5;   -- his next paid reveal on that request
  delete from public.refunds where transaction_id = v_tx5;  -- (scenario 13's case is set aside so the remedy's own filing is seen)
  update public.transactions set refund_status = null, refund_requested_at = null where id = v_tx5;
  perform pg_sleep(1.1);
  r := public.fn_accountant_dispute_remedy_tick();
  if not exists (select 1 from public.refunds where transaction_id = v_tx5 and reason_code = 'goodwill' and requested_by = 'ceo_dispute_decision')
     or (select remedy_transaction_id from public.post_reveal_dispute where id = v_d) <> v_tx5 then
    raise exception 'CHK<<PROBE FAILED 17: the next reveal was not refunded: %>>', r; end if;
  r := public.fn_accountant_dispute_remedy_tick();
  if (select count(*) from public.refunds where transaction_id = v_tx5) <> 1 then raise exception 'CHK<<PROBE FAILED 17: the remedy was filed twice>>'; end if;

  -- 18. WORKING DAY 2: the tick asks once, inside the ladder's window, and not someone who already said yes
  for k in 40..400 loop
    v_rev := now() - make_interval(hours => k);
    exit when public.fn_add_working_days(v_rev, 2) <= now() and now() < public.fn_add_working_days(v_rev, 5);
  end loop;
  update public.transactions set revealed_at = v_rev, refund_status = null, refund_requested_at = null where id = v_tx3;
  delete from public.refunds where transaction_id = v_tx3;
  delete from public.customer_followup where transaction_id = v_tx3;
  delete from public.reveal_contact_statement where transaction_id = v_tx3;
  update public.transactions set revealed_at = v_rev where id = v_tx2;   -- he said yes on v_tx2: not asked
  delete from public.customer_followup where transaction_id = v_tx2;
  r := public.fn_customer_support_contact_check_tick();
  if not exists (select 1 from public.customer_followup where transaction_id = v_tx3 and stage = 'day_two_contact') then
    raise exception 'CHK<<PROBE FAILED 18: working day 2 did not ask (revealed %): %>>', v_rev, r; end if;
  if exists (select 1 from public.customer_followup where transaction_id = v_tx2 and stage = 'day_two_contact') then
    raise exception 'CHK<<PROBE FAILED 18: a customer who already said yes was asked again>>'; end if;
  select count(*) into v_n from public.customer_support_duty_message where stage = 'followup.day_two_contact' and subject_key = v_tx3::text;
  r := public.fn_customer_support_contact_check_tick();
  if (select count(*) from public.customer_support_duty_message where stage = 'followup.day_two_contact' and subject_key = v_tx3::text) <> v_n or v_n <> 1 then
    raise exception 'CHK<<PROBE FAILED 18: working day 2 asked twice>>'; end if;

  -- 19. EVERY CHANNEL'S FACTS: his refunds, his disputes and each revealed job's ladder, with his own word
  w := public.fn_customer_money_cases(v_cust);
  if jsonb_array_length(w->'disputes') < 2 or jsonb_array_length(w->'refunds') < 2
     or not exists (select 1 from jsonb_array_elements(w->'revealed_jobs') j where j->>'customer_said' = 'yes')
     or not exists (select 1 from jsonb_array_elements(w->'refunds') j where j->>'ref' ~ '^QD-RF-') then
    raise exception 'CHK<<PROBE FAILED 19: the money cases are incomplete: %>>', w; end if;
  if jsonb_array_length(public.fn_customer_money_cases(v_other)->'refunds') <> 0 then
    raise exception 'CHK<<PROBE FAILED 19: another customer sees his refunds>>'; end if;

  -- 22 (review AFTERREVEAL item 4). A DENIAL AFTER THE CLICK IS NEVER LOST: "no", the supplier clicks, "no" again through the same door
  -- within ten minutes is a new statement (a denial after the claim), not a duplicate: the ladder keeps running and the CEO is told.
  insert into public.leads (company_name, email) values ('ZZ DEMO afrev Tiling 2', 'zz-afrev-supplier2@example.invalid') returning id into v_lead2;
  insert into public.leads (company_name, email) values ('ZZ DEMO afrev Tiling 3', 'zz-afrev-supplier3@example.invalid') returning id into v_lead3;
  insert into public.inquiries (customer_id, summary, status, rfq_no) values (v_cust, 'ZZ DEMO afrev skirting', 'revealed', 990733) returning id into v_inq3;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status) values (v_inq3, v_lead2, 6000, 'revealed') returning id into v_q7;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status) values (v_inq3, v_lead3, 6100, 'revealed') returning id into v_q8;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status, option_no) values (v_inq3, v_lead3, 6200, 'revealed', 2) returning id into v_q9;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, total_charged, payment_ref, fee_status, revealed_at)
  values (v_q7, v_inq3, v_lead2, v_cust, 6000, 180, 180, 'pi_zzdemo_afrev_7', 'paid', now() - interval '2 days') returning id into v_tx7;
  insert into public.reveal_contact_statement (transaction_id, said, channel, words, source_ref, said_at)
  values (v_tx7, 'no', 'followup_page', 'ZZ DEMO nobody called', 'probe', now() - interval '5 minutes');
  perform public.fn_supplier_ack_record(v_tx7);
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  r := public.fn_reveal_contact_record(v_tx7, 'no', 'followup_page', 'ZZ DEMO still nobody', 'probe');
  perform set_config('qd.probe_files_demo_handoff', '', true);
  w := public.fn_reveal_contact_word(v_tx7);
  if coalesce((r->>'duplicate')::boolean, false) or coalesce((w->>'responded')::boolean, true) or not coalesce((w->>'conflict')::boolean, false)
     or (r->>'conflict_handoff') is null then
    raise exception 'CHK<<PROBE FAILED 22: a denial after the supplier''s click was swallowed as a duplicate: % / %>>', r, w; end if;
  r := public.fn_reveal_contact_record(v_tx7, 'no', 'followup_page', 'ZZ DEMO a double tap', 'probe');
  if not coalesce((r->>'duplicate')::boolean, false) then raise exception 'CHK<<PROBE FAILED 22: a real double tap was recorded twice: %>>', r; end if;

  -- 23 (item 2). AN OVERCHARGE RETURN IS NOT AN OPEN CASE: the CEO's dispute refund is still filed, for what remains of the payment
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, total_charged, payment_ref, fee_status, revealed_at)
  values (v_q8, v_inq3, v_lead3, v_cust, 6100, 183, 183, 'pi_zzdemo_afrev_8', 'paid', now() - interval '4 days') returning id into v_tx8;
  set local session_replication_role = replica;   -- the fixture row only: an accountant's overcharge return already on the payment
  insert into public.refunds (transaction_id, quote_id, inquiry_id, customer_id, supplier_lead_id, stripe_payment_intent, amount_fils, currency,
                              reason_code, reason_note, status, requested_by, requested_at, amount_source)
  values (v_tx8, v_q8, v_inq3, v_cust, v_lead3, 'pi_zzdemo_afrev_8', 1000, 'AED', 'overcharge_return', 'ZZ DEMO overcharge', 'requested', 'accountant', now(), 'in_platform_request');
  set local session_replication_role = origin;
  insert into public.post_reveal_dispute (transaction_id, inquiry_id, customer_id, supplier_id, raised_by, statement, stage, evidence_due, decision_due)
  values (v_tx8, v_inq3, v_cust, v_lead3, 'customer', 'ZZ DEMO he charged more than the quotation', 'ceo_decision', now(), now()) returning id into v_d2;
  r := public.fn_ceo_decides_post_reveal_dispute(v_d2, 'customer_upheld', 'ZZ DEMO the revealed quotation was 6,100', 'refund_reveal_fee', 'none');
  if r->'effect'->>'refund' = 'already_open'
     or not exists (select 1 from public.refunds where transaction_id = v_tx8 and reason_code = 'fraud_or_dispute' and amount_fils = 18300 - 1000) then
    raise exception 'CHK<<PROBE FAILED 23: the overcharge return blocked the CEO''s refund or its amount is wrong: % / %>>', r,
      (select jsonb_agg(jsonb_build_object('reason', reason_code, 'fils', amount_fils)) from public.refunds where transaction_id = v_tx8); end if;
  if (select count(*) from public.customer_support_duty_message where stage = 'dispute.decided' and subject_key = v_d2 || ':customer') <> 1 then
    raise exception 'CHK<<PROBE FAILED 23: the customer was not told>>'; end if;

  -- 24 (item 6). THE CEO SEAT'S REASONING DECIDES A DISPUTE: the duty asks once per dispute; the answer is one option naming the
  -- outcome, the remedy and the supplier action; a reasonless answer is refused; the apply calls fn_ceo_decides_post_reveal_dispute.
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, total_charged, payment_ref, fee_status, revealed_at)
  values (v_q9, v_inq3, v_lead3, v_cust, 6200, 186, 186, 'pi_zzdemo_afrev_9', 'paid', now() - interval '4 days') returning id into v_tx9;
  insert into public.post_reveal_dispute (transaction_id, inquiry_id, customer_id, supplier_id, raised_by, statement, stage, evidence_due, decision_due, finding)
  values (v_tx9, v_inq3, v_cust, v_lead3, 'customer', 'ZZ DEMO he never finished the skirting', 'ceo_decision', now(), now() + interval '3 days', 'customer_upheld') returning id into v_d3;
  r := public.fn_ceo_post_reveal_dispute_tick();
  if coalesce((r->>'asked')::int, 0) < 1 then raise exception 'CHK<<PROBE FAILED 24: the duty did not ask the CEO: %>>', r; end if;
  if jsonb_array_length(public.fn_ceo_post_reveal_dispute_options()) <> 20 then raise exception 'CHK<<PROBE FAILED 24: the option set is not 20>>'; end if;
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, qhash, expires_at)
  values ('ceo', 'ceo.post_reveal_dispute', 'ZZ DEMO probe', jsonb_build_object('decision', jsonb_build_object('options', public.fn_ceo_post_reveal_dispute_options())),
          '{}'::jsonb, jsonb_build_object('dispute_id', v_d3), 'probe', 'probe:afrev:24', md5('afrev24'), now() + interval '1 day') returning id into v_h;
  begin
    r := public.fn_reason_apply_ceo__post_reveal_dispute(v_h, '{"decision":{"choice":"customer_upheld|none|warning"},"answer":"ok"}'::jsonb);
    raise exception 'CHK<<PROBE FAILED 24: a reasonless CEO decision was applied>>';
  exception when check_violation then if sqlerrm !~ '^REASONLESS_DECISION' then raise; end if; end;
  begin
    r := public.fn_reason_apply_ceo__post_reveal_dispute(v_h, '{"decision":{"choice":"customer_upheld|refund_everything|none"},"answer":"x"}'::jsonb);
    raise exception 'CHK<<PROBE FAILED 24: a choice outside the options was applied>>';
  exception when raise_exception then if sqlerrm !~ '^CHOICE_NOT_AN_OPTION' then raise; end if; end;
  r := public.fn_reason_apply_ceo__post_reveal_dispute(v_h, jsonb_build_object('decision', jsonb_build_object('choice', 'customer_upheld|none|pause_matching'),
         'answer', 'ZZ DEMO the photos show the skirting unfinished and the supplier did not answer the evidence request'));
  if (select stage || ':' || outcome || ':' || supplier_action from public.post_reveal_dispute where id = v_d3) <> 'decided:customer_upheld:pause_matching' then
    raise exception 'CHK<<PROBE FAILED 24: the CEO''s reasoned answer did not decide the dispute: %>>', r; end if;
  r := public.fn_reason_apply_ceo__post_reveal_dispute(v_h, jsonb_build_object('decision', jsonb_build_object('choice', 'no_fault'),
         'answer', 'ZZ DEMO a second answer to the same question after it was decided'));
  if coalesce((r->>'applied')::boolean, true) then raise exception 'CHK<<PROBE FAILED 24: a decided dispute was decided again: %>>', r; end if;

  -- 25 (item 6). THE PAUSE: v_lead3 was not blocked, so it is paused with an end date. Then: skipped-and-recorded when the supplier is
  -- already blocked for another reason, applied late once that block lifts; lifted by the CEO with reasons, or at its end.
  if not (select matching_blocked from public.leads where id = v_lead3) or (select pause_until from public.post_reveal_dispute where id = v_d3) is null then
    raise exception 'CHK<<PROBE FAILED 25: the pause was not applied with an end>>'; end if;
  begin
    r := public.fn_ceo_lifts_dispute_pause(v_d3, 'ceo', 'ok');
    raise exception 'CHK<<PROBE FAILED 25: a reasonless lift was applied>>';
  exception when check_violation then if sqlerrm !~ '^REASONLESS_DECISION' then raise; end if; end;
  r := public.fn_ceo_lifts_dispute_pause(v_d3, 'expiry', null);
  if coalesce((r->>'lifted')::boolean, true) then raise exception 'CHK<<PROBE FAILED 25: a pause was lifted before its end: %>>', r; end if;
  r := public.fn_ceo_lifts_dispute_pause(v_d3, 'ceo', 'ZZ DEMO the supplier finished the skirting and sent photos of the completed work');
  if (select matching_blocked from public.leads where id = v_lead3)
     or (select pause_lift->>'by' from public.post_reveal_dispute where id = v_d3) <> 'ceo'
     or not exists (select 1 from public.customer_support_duty_message where stage = 'dispute.pause_lifted' and subject_key = v_d3::text) then
    raise exception 'CHK<<PROBE FAILED 25: the CEO''s lift did not unpause and tell the supplier: %>>', r; end if;
  -- already blocked (a licence): skipped, recorded with that reason, then applied by the duty once the licence block lifts
  update public.leads set matching_blocked = true, matching_block_reason = 'licence_expired' where id = v_lead2;
  insert into public.post_reveal_dispute (transaction_id, inquiry_id, customer_id, supplier_id, raised_by, statement, stage, evidence_due, decision_due)
  values (v_tx7, v_inq3, v_cust, v_lead2, 'customer', 'ZZ DEMO he never came back to fix the leak', 'ceo_decision', now(), now()) returning id into v_d;
  r := public.fn_ceo_decides_post_reveal_dispute(v_d, 'customer_upheld', 'ZZ DEMO', 'none', 'pause_matching');
  if r->'effect'->>'pause_skipped' is distinct from 'already blocked' or r->'effect'->>'blocked_for' is distinct from 'licence_expired'
     or (select matching_block_reason from public.leads where id = v_lead2) <> 'licence_expired' then
    raise exception 'CHK<<PROBE FAILED 25: a pause on an already blocked supplier was not recorded as skipped: %>>', r; end if;
  update public.leads set matching_blocked = false, matching_block_reason = null where id = v_lead2;
  r := public.fn_ceo_dispute_pause_tick();
  if (select matching_block_reason from public.leads where id = v_lead2) is distinct from 'dispute_upheld' then
    raise exception 'CHK<<PROBE FAILED 25: the skipped pause was not applied once the other block lifted: %>>', r; end if;
  update public.post_reveal_dispute set pause_until = now() - interval '1 minute' where id = v_d;
  r := public.fn_ceo_dispute_pause_tick();
  if (select matching_blocked from public.leads where id = v_lead2) or (select pause_lift->>'by' from public.post_reveal_dispute where id = v_d) <> 'expiry' then
    raise exception 'CHK<<PROBE FAILED 25: a pause that ended was not lifted: %>>', r; end if;

  -- 26 (item 6). THE WIDGET NAMES NO JOB: a chat turn is filed onto a revealed job only when the model's reading names it; the
  -- result is written to him.
  r := public.fn_customer_after_reveal_message(v_cust, 'ZZ DEMO the supplier I paid for raised the price', 'widget', null);
  if r->>'code' <> 'reading_the_job' or r ? 'transaction_id' then
    raise exception 'CHK<<PROBE FAILED 26: the widget door picked a job itself: %>>', r; end if;
  r := public.fn_customer_after_reveal_message(v_other, 'ZZ DEMO help', 'widget', null);
  if r->>'code' <> 'no_revealed_job' then raise exception 'CHK<<PROBE FAILED 26: a customer with no reveal: %>>', r; end if;
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, qhash, expires_at)
  values ('customer_support', 'customer_support.after_reveal_job', 'ZZ DEMO probe',
          jsonb_build_object('decision', jsonb_build_object('options', jsonb_build_array(jsonb_build_object('id', v_tx::text, 'meaning', 'x'), jsonb_build_object('id', 'none', 'meaning', 'y')))),
          '{}'::jsonb, jsonb_build_object('customer_id', v_cust, 'message', 'ZZ DEMO the waterproofer wants 24,000 now', 'channel', 'widget'),
          'probe', 'probe:afrev:26', md5('afrev26'), now() + interval '1 day') returning id into v_h;
  r := public.fn_reason_apply_customer_support__after_reveal_job(v_h, jsonb_build_object('decision', jsonb_build_object('choice', v_tx::text)));
  if not coalesce((r->>'filed')::boolean, false) or (r->>'transaction_id')::uuid <> v_tx
     or not exists (select 1 from public.customer_support_voice_owed where stage = 'after_reveal.widget_filed' and subject_key = v_h::text) then
    raise exception 'CHK<<PROBE FAILED 26: the named job was not filed and told: %>>', r; end if;
  r := public.fn_reason_apply_customer_support__after_reveal_job(v_h, '{"decision":{"choice":"none"}}'::jsonb);
  if coalesce((r->>'filed')::boolean, true) then raise exception 'CHK<<PROBE FAILED 26: "none" filed a job: %>>', r; end if;

  -- 20. nothing real moved; the new table is closed to the public roles
  if (select count(*) from public.refunds where customer_id not in (v_cust, v_other)) <> v_real_refunds
     or (select count(*) from public.post_reveal_dispute where customer_id not in (v_cust, v_other)) <> v_real_disputes
     or (select count(*) from public.reveal_contact_statement s join public.transactions t on t.id = s.transaction_id where t.customer_id not in (v_cust, v_other)) <> v_real_statements then
    raise exception 'CHK<<PROBE FAILED 20: real rows moved>>'; end if;
  if has_table_privilege('anon', 'public.reveal_contact_statement', 'select') or has_function_privilege('anon', 'public.fn_reveal_contact_record(uuid, text, text, text, text)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_customer_after_reveal_message(uuid, text, text, uuid)', 'execute') then
    raise exception 'CHK<<PROBE FAILED 20: a public role can reach the new table or routines>>'; end if;

  raise exception 'CHK<<PROBE OK %>>', jsonb_build_object('scenarios', 29, 'conflict_handoff', true, 'disputes', 2);
end $probe$;
