-- PROBE of every_inbound_message_is_answered_or_closed_with_its_reason_and_a_complaint_on_any_channel_is_registered.sql.
-- LOCAL only (a Postgres 16 built from the schema mirror, scripts/db/local_pg16.mjs). Always raises CHK<<...>>, so every row it
-- writes rolls back and nothing reaches a person. Its senders are example.invalid / qd-probe-* addresses and the reserved
-- fixture mobile range. Run it twice: the second run must answer the same verdict.
do $probe$
declare
  v_p text[] := '{}'; v_dom text := 'qd-probe-ic-' || md5(random()::text) || '.ae';
  v_cust uuid; v_other uuid; v_inq1 uuid; v_inq2 uuid; v_rfq1 int; v_rfq2 int; v_lead bigint;
  r jsonb; r2 jsonb; t public.complaint_tickets; v_t1 text; v_t2 text; v_t3 text;
  m1 bigint; m2 bigint; m3 bigint; m4 bigint; m5 bigint; m6 bigint; m7 bigint; v_wa bigint; v_case text; d public.customer_support_inbound_drive;
  v_m text;
begin
  -- the hand-off kinds the duty files (the local database holds only a few seed rows)
  insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file) values
    ('support.case_open', 'customer_support', 'customer_support', 'probe', 'fn_customer_support_waits_for_a_person', interval '24 hours', false, 'scripts/sql/every_inbound_message_is_answered_or_closed_with_its_reason_and_a_complaint_on_any_channel_is_registered_probe.sql'),
    ('review.requested', 'customer_support', 'ceo', 'probe', 'fn_customer_support_waits_for_a_person', interval '24 hours', false, 'scripts/sql/every_inbound_message_is_answered_or_closed_with_its_reason_and_a_complaint_on_any_channel_is_registered_probe.sql'),
    ('complaint.due', 'customer_support', 'customer_support', 'probe', 'fn_complaint_due_waits_for_the_response', null, false, 'scripts/sql/every_inbound_message_is_answered_or_closed_with_its_reason_and_a_complaint_on_any_channel_is_registered_probe.sql')
  on conflict do nothing;

  -- ── H2: A COMPLAINT FROM ANY CHANNEL ───────────────────────────────────────────────────────────────────────────────
  insert into public.customers (email, full_name) values ('zz-demo-complainer-' || md5(random()::text) || '@example.invalid', 'ZZ DEMO Complainer') returning id into v_cust;
  insert into public.customers (email, full_name) values ('zz-demo-other-' || md5(random()::text) || '@example.invalid', 'ZZ DEMO Other') returning id into v_other;
  insert into public.inquiries (customer_id, category, summary) values (v_cust, 'joinery', 'ZZ DEMO wardrobe') returning id, rfq_no into v_inq1, v_rfq1;
  insert into public.inquiries (customer_id, category, summary) values (v_other, 'joinery', 'ZZ DEMO kitchen') returning id, rfq_no into v_inq2, v_rfq2;
  select email into v_m from public.customers where id = v_cust;

  -- 1. e-mail (English): linked to the person by the address the channel holds, to THEIR job only
  r := public.fn_complaint_open_from_message('email', 'email:probe-' || v_dom, 'ZZ DEMO The supplier on job ' || v_rfq1 || ' never came, and job '
         || v_rfq2 || ' is not even mine. I want this fixed.', 'the model read a complaint about a supplier no-show', upper(v_m), null, 'ZZ DEMO Complainer',
         null, null, null, 'en', true);
  v_t1 := r->>'ticket';
  select * into t from public.complaint_tickets where ticket_no = v_t1;
  if t.id is null or (r->>'ok')::boolean is not true or (r->>'duplicate')::boolean then v_p := v_p || ('e-mail complaint not opened: ' || r::text); end if;
  if t.channel <> 'email' or t.party_kind <> 'customer' or t.party_id <> v_cust::text or t.email <> lower(v_m) then v_p := v_p || 'e-mail complaint not linked to the person'::text; end if;
  if t.inquiry_refs <> array[v_rfq1::text] then v_p := v_p || ('the job numbers linked are not exactly theirs: ' || t.inquiry_refs::text); end if;
  if t.acknowledged_at is not null or t.respond_due <= t.acknowledge_due or t.status <> 'acknowledged' then v_p := v_p || 'the deadlines or the owed acknowledgement are wrong'::text; end if;
  if t.ticket_no !~ '^QD-C-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{6}$' then v_p := v_p || 'ticket number shape'::text; end if;
  -- 2. idempotent per message
  r2 := public.fn_complaint_open_from_message('email', 'email:probe-' || v_dom, 'the same message read again', null, v_m);
  if (r2->>'duplicate')::boolean is not true or r2->>'ticket' <> v_t1 or (select count(*) from public.complaint_tickets where source_key = 'email:probe-' || v_dom) <> 1 then
    v_p := v_p || ('a second reading of one message opened a second ticket: ' || r2::text); end if;
  -- 3. WhatsApp (Arabic): no e-mail, the phone and the party the door resolved; no address looked up from the phone
  r := public.fn_complaint_open_from_message('whatsapp', 'whatsapp:SMprobe' || v_dom, 'ZZ DEMO المورد لم يحضر في الطلب ' || v_rfq1 || ' وأريد استرداد المبلغ',
         'the model read a complaint and a refund demand', null, '+971 50 000 0071', null, 'customer', v_cust::text, null, 'ar', true);
  v_t2 := r->>'ticket';
  select * into t from public.complaint_tickets where ticket_no = v_t2;
  if t.id is null or t.email is not null or t.phone <> '+971500000071' or t.party_id <> v_cust::text or t.lang <> 'ar' or t.inquiry_refs <> array[v_rfq1::text] then
    v_p := v_p || ('the WhatsApp complaint is not registered as the channel holds it: ' || r::text); end if;
  -- 3b. an unconfirmed number names nobody, and no e-mail is looked up from it
  r := public.fn_complaint_open_from_message('whatsapp', 'whatsapp:SMprobe2' || v_dom, 'ZZ DEMO bad service', 'complaint', null, '+971 50 000 0073', null, null, null, null, 'en', true);
  if (select party_kind is not null or email is not null from public.complaint_tickets where ticket_no = r->>'ticket') then v_p := v_p || 'an unconfirmed number selected a person'::text; end if;
  -- 4. an anonymous widget visitor: registered on its own key, nothing to link
  r := public.fn_complaint_open_from_message('widget', 'widget:probe' || md5(v_dom), 'ZZ DEMO your site charged me twice', 'complaint', null, null, null, null, null, null, 'en', true);
  v_t3 := r->>'ticket';
  if v_t3 is null or (select party_kind from public.complaint_tickets where ticket_no = v_t3) is not null then v_p := v_p || ('the widget complaint: ' || r::text); end if;
  -- 5. what is refused
  if (public.fn_complaint_open_from_message('fax', 'x', 'm')->>'ok')::boolean then v_p := v_p || 'an unknown channel was accepted'::text; end if;
  if (public.fn_complaint_open_from_message('email', ' ', 'm')->>'ok')::boolean then v_p := v_p || 'a ticket without a source key'::text; end if;
  if (public.fn_complaint_open_from_message('portal', 'portal:x', ' ')->>'ok')::boolean then v_p := v_p || 'an empty complaint'::text; end if;
  -- 6. the acknowledgement: owed by e-mail when the channel gave an address, never for the phone-only ticket; stamped once
  perform set_config('qd.duty_fixtures', 'on', true);
  r := public.fn_customer_support_complaint_deadline_tick();
  if not exists (select 1 from public.customer_support_voice_owed where stage = 'complaint.acknowledge' and subject_key = v_t1 and v_t1 = any (must)) then
    v_p := v_p || ('the e-mail complaint is not owed a model-written acknowledgement carrying its ticket: ' || r::text); end if;
  if exists (select 1 from public.customer_support_voice_owed where subject_key in (v_t2, v_t3)) then v_p := v_p || 'an acknowledgement was owed to no address'::text; end if;
  insert into public.customer_support_duty_message (stage, subject_key, to_email, outcome) values ('complaint.acknowledge', v_t1, lower(v_m), 'queued');
  perform public.fn_customer_support_complaint_deadline_tick();
  if (select acknowledged_at from public.complaint_tickets where ticket_no = v_t1) is null then v_p := v_p || 'the sent acknowledgement was not stamped'::text; end if;
  if not public.fn_complaint_acknowledge(v_t2, 'whatsapp reply carried the ticket') or public.fn_complaint_acknowledge(v_t2, 'again') then
    v_p := v_p || 'fn_complaint_acknowledge is not once'::text; end if;
  -- 7. the weekly review counts the channel complaints of a fixture week
  r := public.fn_customer_support_case_review_tick();
  if coalesce((r#>>'{complaints,opened}')::int, 0) < 3 or coalesce((r#>>'{complaints,by_channel,whatsapp}')::int, 0) < 1 then v_p := v_p || ('the review does not count channel complaints: ' || coalesce(r->>'complaints', 'null')); end if;

  -- ── H1: A REPLY, OR A CLOSE WITH ITS REASON ─────────────────────────────────────────────────────────────────────────
  insert into public.leads (company_name, email, email_verified) values ('ZZ DEMO Probe Supplier', 'zz-demo-sup-' || md5(v_dom) || '@example.invalid', 'verified') returning id into v_lead;
  -- m1 a machine's mail the reading refused (Auto-Submitted: auto-generated from an unknown sender), 3 h old
  insert into public.inbound_messages (from_email, to_email, subject, body, created_at, triaged_at, ai_category, ai_summary, raw)
  values ('zz-demo-desk@example.invalid', 'supplier@quotesdone.com', 'ZZ DEMO Ticket received', 'We received your mail.', now() - interval '3 hours', now() - interval '3 hours',
          'no_auto_reply', 'Not answered automatically: read as automated_notice (auto_submitted)', jsonb_build_object('auto_submitted', 'auto-generated')) returning id into m1;
  insert into public.mailbox_reply_decision (inbound_message_id, reading, hard_rule, why, method) values (m1, 'automated_notice', 'auto_submitted', 'code rule auto_submitted', 'code');
  -- m2 read 'unclear', from a KNOWN supplier
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, created_at, triaged_at, ai_category, needs_review, owner_role)
  values (v_lead, (select email from public.leads where id = v_lead), 'supplier@quotesdone.com', 'ZZ DEMO about the platform', 'Please see the attached.', now() - interval '3 hours',
          now() - interval '3 hours', 'no_auto_reply', true, 'customer_support') returning id into m2;
  insert into public.mailbox_reply_decision (inbound_message_id, reading, why, method) values (m2, 'unclear', 'probe: cannot tell', 'model');
  -- m3 the founder's own test reply
  insert into public.inbound_messages (from_email, to_email, subject, body, created_at, triaged_at, ai_category)
  values ('zz-demo-founder@example.invalid', 'hello@quotesdone.com', 'ZZ DEMO test', 'test', now() - interval '3 hours', now() - interval '3 hours', 'test_reply') returning id into m3;
  -- m4 a customer's question still owed (triaged, no answer yet)
  insert into public.inbound_messages (from_email, to_email, subject, body, created_at, triaged_at, ai_category)
  values (v_m, 'hello@quotesdone.com', 'ZZ DEMO where is my quote', 'Where is my quote?', now() - interval '3 hours', now() - interval '3 hours', 'customer_question') returning id into m4;
  -- m5 a KNOWN supplier's auto-generated mail the old rule refused by code: the rule no longer decides it alone
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, created_at, triaged_at, ai_category, raw)
  values (v_lead, (select email from public.leads where id = v_lead), 'supplier@quotesdone.com', 'ZZ DEMO Re: your invitation', 'Yes, we want to register. How?',
          now() - interval '3 hours', now() - interval '3 hours', 'no_auto_reply', jsonb_build_object('auto_submitted', 'auto-generated')) returning id into m5;
  insert into public.mailbox_reply_decision (inbound_message_id, reading, hard_rule, why, method) values (m5, 'automated_notice', 'auto_submitted', 'code rule auto_submitted', 'code');
  -- m6 the same supplier's out-of-office (auto-replied): still refused by code, for everyone
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, created_at, raw)
  values (v_lead, (select email from public.leads where id = v_lead), 'supplier@quotesdone.com', 'ZZ DEMO away', 'I am away.', now() - interval '3 hours',
          jsonb_build_object('auto_submitted', 'auto-replied')) returning id into m6;

  if public.fn_mailbox_reply_hard_rule(m5) is not null then v_p := v_p || ('a known supplier''s auto-generated mail is still refused by code: ' || public.fn_mailbox_reply_hard_rule(m5)); end if;
  if public.fn_mailbox_reply_hard_rule(m6) is distinct from 'auto_submitted' then v_p := v_p || 'an out-of-office (auto-replied) is no longer refused'::text; end if;
  if public.fn_mailbox_reply_hard_rule(m1) is distinct from 'auto_submitted' then v_p := v_p || 'an unknown sender''s auto-generated mail is no longer refused'::text; end if;
  if public.fn_inbound_email_reply_owed(m1)->>'state' <> 'no_reply_needed' then v_p := v_p || 'm1 state'::text; end if;
  if public.fn_inbound_email_reply_owed(m2)->>'state' <> 'decide' then v_p := v_p || 'm2 state'::text; end if;
  if public.fn_inbound_email_reply_owed(m3)->>'state' <> 'no_reply_needed' then v_p := v_p || 'm3 state'::text; end if;
  if public.fn_inbound_email_reply_owed(m4)->>'state' <> 'owed' then v_p := v_p || 'm4 state'::text; end if;
  if public.fn_inbound_email_reply_owed(m5)->>'state' <> 'decide' then v_p := v_p || ('m5 state: ' || (public.fn_inbound_email_reply_owed(m5))::text); end if;

  r := public.fn_customer_support_unanswered_inbound_tick();
  select * into d from public.customer_support_inbound_drive where channel = 'email' and message_id = m1;
  if d.closed_at is null or d.case_ref is not null or d.handoff_id is not null or coalesce(d.no_reply_reason, '') not like '%automated_notice%' then
    v_p := v_p || ('the machine''s mail was not closed with its reason: ' || r::text); end if;
  if (select no_reply_reason from public.customer_support_inbound_drive where channel = 'email' and message_id = m3) is null then v_p := v_p || 'the test reply was not closed with its reason'::text; end if;
  select * into d from public.customer_support_inbound_drive where channel = 'email' and message_id = m4;
  if d.case_ref is null or d.closed_at is not null then v_p := v_p || 'the owed customer question did not become a case'::text; end if;
  select * into d from public.customer_support_inbound_drive where channel = 'email' and message_id = m2;
  if d.case_ref is null then v_p := v_p || 'the unclear mail did not become a case'::text; end if;
  -- the next tick asks the model for a second reading of the unclear mail and of the mail the old rule refused
  r := public.fn_customer_support_unanswered_inbound_tick();
  if not exists (select 1 from public.inbound_messages where id = m2 and triaged_at is null and needs_review and owner_role is null and raw ? 'second_reading_requested_at') then
    v_p := v_p || ('the unclear mail was not put back for a second reading: ' || r::text); end if;
  if not exists (select 1 from public.inbound_messages where id = m5 and triaged_at is null and raw ? 'second_reading_requested_at') then
    v_p := v_p || 'the mail the old rule refused was not read again'::text; end if;
  -- once answered, the row and its hand-off close
  update public.inbound_messages set replied_at = now(), replied_by = 'customer_support' where id = m4;
  r := public.fn_customer_support_unanswered_inbound_tick();
  select * into d from public.customer_support_inbound_drive where channel = 'email' and message_id = m4;
  if d.answered_at is null or exists (select 1 from public.agent_actions a where a.id = d.handoff_id and a.status = 'pending') then v_p := v_p || 'the answered mail did not close'::text; end if;
  -- a fixture run never hands anything to the CEO
  if exists (select 1 from public.customer_support_inbound_drive where message_id in (m1, m2, m3, m4, m5) and escalated_at is not null) then v_p := v_p || 'a fixture went to the CEO'::text; end if;

  -- the weekly figure: an owed mail is timed at its age; a closed one is counted apart
  r := public.fn_customer_support_case_review_tick();
  if coalesce((r#>>'{email,closed_no_reply_needed}')::int, 0) < 2 or (r#>>'{email,times_include_owed}') <> 'true'
     or coalesce((r#>>'{email,p90_first_reply_minutes}')::numeric, 0) < 100 then
    v_p := v_p || ('the weekly figure leaves owed mail out: ' || coalesce(r->>'email', 'null')); end if;
  perform set_config('qd.duty_fixtures', '', true);

  -- REPAIR (a real-mode run, local only): a row the old duty opened for a reserved fixture number closes as test traffic, and its
  -- case closes when nothing else is on it; a mail owed past the SLA goes to the CEO seat once
  insert into public.wa_messages (wa_from, inbound, reply, sent, created_at, meta)
  values ('whatsapp:+971500000072', 'probe hello', 'probe reply', false, now() - interval '30 hours', '{"send_error":"captured: reserved fixture mobile"}') returning id into v_wa;
  r := public.fn_support_touch('whatsapp', 'in', 'unknown', null, null, '+971500000072', 'probe hello');
  v_case := r->>'case_ref';
  insert into public.customer_support_inbound_drive (channel, message_id, case_ref, outcome, fixture, acted_at) values ('whatsapp', v_wa, v_case, 'case opened', false, now() - interval '28 hours');
  insert into public.inbound_messages (from_email, to_email, subject, body, created_at, triaged_at, ai_category)
  values ('owner@' || v_dom, 'hello@quotesdone.com', 'probe question', 'Where is it?', now() - interval '30 hours', now() - interval '30 hours', 'customer_question') returning id into m7;
  insert into public.customer_support_inbound_drive (channel, message_id, outcome, fixture, acted_at) values ('email', m7, 'case opened', false, now() - interval '28 hours');
  r := public.fn_customer_support_unanswered_inbound_tick();
  select * into d from public.customer_support_inbound_drive where channel = 'whatsapp' and message_id = v_wa;
  if d.closed_at is null or d.no_reply_reason not like '%fixture%' then v_p := v_p || ('the fixture-number row did not close: ' || r::text); end if;
  if v_case is not null and (select state from public.support_case where case_ref = v_case) <> 'closed' then v_p := v_p || 'its case did not close'::text; end if;
  select * into d from public.customer_support_inbound_drive where channel = 'email' and message_id = m7;
  if d.escalated_at is null or not exists (select 1 from public.agent_actions a where a.id = d.escalation_handoff_id and a.agent = 'ceo') then
    v_p := v_p || ('a mail owed past the SLA did not reach the CEO seat: ' || r::text); end if;
  r := public.fn_customer_support_unanswered_inbound_tick();
  if (select count(*) from public.agent_actions a where a.agent = 'ceo' and a.target_id like '%' || m7::text) > 1 then v_p := v_p || 'the CEO was asked twice'::text; end if;

  -- the e-mail case summary catch-up lists nothing for a fixture outside a rehearsal window (and does not fail)
  if jsonb_typeof(public.fn_support_case_email_summaries_owed(3)) <> 'array' then v_p := v_p || 'the e-mail catch-up list'::text; end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when cardinality(v_p) = 0 then 'PROBE OK' else 'PROBE FAILED' end, 'problems', to_jsonb(v_p));
end $probe$;
