-- PROBE of every_interested_supplier_reply_is_answered_the_same_day_and_the_parked_get_one_last_note.sql. LOCAL only (a
-- Postgres 16 built from the schema mirror). Always raises CHK<<...>>, so every row rolls back and nothing reaches a sender.
-- The clock is passed in (p_now): Monday 16 Nov 2026 10:00 Dubai, a working day, whatever day the probe runs.
do $probe$
declare
  v_p text[] := '{}'; v_dom text := 'qd-probe-s-' || md5(random()::text) || '.ae'; v_mon timestamptz := timestamptz '2026-11-16 06:00:00+00';
  v_lead bigint; v_m1 bigint; v_m2 bigint; v_m3 bigint; r jsonb; s public.supplier_reply_same_day; i int; v_ids bigint[] := '{}';
begin
  -- 1. what kind of reply it is
  if public.fn_supplier_reply_kind('Yes, we are interested.') <> 'interested' then v_p := v_p || 'kind: interested'::text; end if;
  if public.fn_supplier_reply_kind('How do we register our company?') <> 'question' then v_p := v_p || 'kind: question'::text; end if;
  if public.fn_supplier_reply_kind(E'Thanks\nwhat is the fee') <> 'question' then v_p := v_p || 'kind: a question without a question mark'::text; end if;
  if public.fn_supplier_reply_kind('Not interested, remove us.') <> 'decline' then v_p := v_p || 'kind: decline'::text; end if;
  if public.fn_supplier_reply_kind('Maybe next month, we are busy.') <> 'later' then v_p := v_p || 'kind: later'::text; end if;

  -- 2. the working-day promise (no public holiday is seeded locally)
  if public.fn_supplier_reply_due_by(v_mon) <> timestamptz '2026-11-16 13:00:00+00' then v_p := v_p || ('Monday 10:00 is due ' || public.fn_supplier_reply_due_by(v_mon)); end if;
  if public.fn_supplier_reply_due_by(timestamptz '2026-11-16 12:00:00+00') <> timestamptz '2026-11-17 08:00:00+00' then v_p := v_p || 'Monday 16:00 is not due Tuesday noon'::text; end if;
  if public.fn_supplier_reply_due_by(timestamptz '2026-11-20 12:00:00+00') <> timestamptz '2026-11-23 08:00:00+00' then v_p := v_p || 'Friday 16:00 is not due Monday noon'::text; end if;
  if public.fn_supplier_reply_due_by(timestamptz '2026-11-21 06:00:00+00') <> timestamptz '2026-11-23 08:00:00+00' then v_p := v_p || 'a Saturday mail is not due Monday noon'::text; end if;

  -- 3. THE SAME-DAY ANSWER. Three replies to the supplier mailbox 40 minutes before Monday 10:00: a question (owed), an
  --    interested reply the reading refused (not owed), and a decline (never owed).
  insert into public.leads (company_name, email, email_verified) values ('Probe Reply Trading', 'owner@' || v_dom, 'verified') returning id into v_lead;
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, created_at, owner_role, needs_review, triaged_at)
  values (v_lead, 'Owner <owner@' || v_dom || '>', 'supplier@quotesdone.com', 'Re: A question', 'Yes please, how do we register?', v_mon - interval '40 minutes', 'sales_engineer', false, v_mon - interval '39 minutes')
  returning id into v_m1;
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, created_at, owner_role, needs_review, triaged_at)
  values (v_lead, 'sales@' || v_dom, 'supplier@quotesdone.com', 'Our services', 'We are interested in selling you our software.', v_mon - interval '40 minutes', 'sales_engineer', false, v_mon - interval '39 minutes')
  returning id into v_m2;
  insert into public.mailbox_reply_decision (inbound_message_id, reading, method, why) values (v_m2, 'vendor_our_account', 'code', 'probe: a vendor');
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, created_at, owner_role, needs_review, triaged_at)
  values (v_lead, 'boss@' || v_dom, 'supplier@quotesdone.com', 'Re: A question', 'Not interested, remove us.', v_mon - interval '40 minutes', 'sales_engineer', false, v_mon - interval '39 minutes')
  returning id into v_m3;

  r := public.fn_sales_engineer_answers_supplier_replies_same_day(v_mon);
  select * into s from public.supplier_reply_same_day where inbound_message_id = v_m1;
  if s.inbound_message_id is null or s.kind <> 'question' or s.state <> 'owed' or s.attempts <> 1 then v_p := v_p || ('the question is not owed and requested once: ' || r::text); end if;
  if s.due_by <> timestamptz '2026-11-16 13:00:00+00' then v_p := v_p || ('the question is due ' || s.due_by); end if;
  if not exists (select 1 from public.inbound_messages where id = v_m1 and triaged_at is null and owner_role is null and needs_review and raw ? 'same_day_answer_requested_at') then
    v_p := v_p || 'the question was not put back to the model''s answerer'::text; end if;
  if (select state from public.supplier_reply_same_day where inbound_message_id = v_m2) is distinct from 'not_owed' then v_p := v_p || 'a reply the reading refused is owed'::text; end if;
  if (select reason from public.supplier_reply_same_day where inbound_message_id = v_m2) not like '%reading refused%' then v_p := v_p || 'a not-owed reply has no reason'::text; end if;
  if exists (select 1 from public.supplier_reply_same_day where inbound_message_id = v_m3) then v_p := v_p || 'a decline was owed an answer'::text; end if;

  -- ten minutes later nothing is asked again; thirty-one minutes later the second request
  r := public.fn_sales_engineer_answers_supplier_replies_same_day(v_mon + interval '10 minutes');
  if (select attempts from public.supplier_reply_same_day where inbound_message_id = v_m1) <> 1 then v_p := v_p || 'asked again inside 30 minutes'::text; end if;
  r := public.fn_sales_engineer_answers_supplier_replies_same_day(v_mon + interval '31 minutes');
  if (select attempts from public.supplier_reply_same_day where inbound_message_id = v_m1) <> 2 then v_p := v_p || 'no second request after 30 minutes'::text; end if;

  -- answered by the model through fn_inbox_send (here: replied_at written), on time
  update public.inbound_messages set replied_at = v_mon + interval '35 minutes', replied_by = 'customer_support' where id = v_m1;
  r := public.fn_sales_engineer_answers_supplier_replies_same_day(v_mon + interval '40 minutes');
  if (select state || ':' || reason from public.supplier_reply_same_day where inbound_message_id = v_m1) not like 'answered:%on time%' then
    v_p := v_p || ('an answered reply is not recorded answered on time: ' || coalesce((select reason from public.supplier_reply_same_day where inbound_message_id = v_m1), 'no row')); end if;

  -- past its due time unanswered: the CEO seat holds it, never a silent drop
  update public.inbound_messages set replied_at = null, created_at = v_mon - interval '20 minutes' where id = v_m1;
  delete from public.supplier_reply_same_day where inbound_message_id = v_m1;
  r := public.fn_sales_engineer_answers_supplier_replies_same_day(v_mon);
  r := public.fn_sales_engineer_answers_supplier_replies_same_day(timestamptz '2026-11-16 13:01:00+00');
  if (select state from public.supplier_reply_same_day where inbound_message_id = v_m1) <> 'escalated' then v_p := v_p || ('an overdue reply was not escalated: ' || r::text); end if;
  if not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'review.requested' and a.target_id = v_m1::text) then
    v_p := v_p || 'the escalation filed no CEO handoff'::text; end if;

  -- 4. THE ONE LAST NOTE: the text carries the click-to-chat link and the registration link, and no WhatsApp message is sent
  r := public.fn_supplier_final_touch_text('Probe Parked Trading', 'https://quotesdone.com/en/portal?x=1', '+1 218 316 6814');
  if r->>'body' not like '%https://wa.me/12183166814%' or r->>'body' not like '%https://quotesdone.com/en/portal?x=1%' or r->>'body' not like 'Dear Probe Parked Trading,%' then
    v_p := v_p || ('the last note is not as written: ' || (r->>'body')); end if;
  if r->>'body' ~ '[؀-ۿ]' then v_p := v_p || 'the last note carries Arabic'::text; end if;
  if (public.fn_supplier_final_touch_text('شركة', 'x', '1')->>'body') not like 'Dear Sir or Madam,%' then v_p := v_p || 'an Arabic company name reached the greeting'::text; end if;

  -- six parked fixture leads, the cap of 5, on a Monday with the campaign open; then nobody twice (the duty's fixture switch)
  insert into public.app_secrets (key, value) values ('invite_enabled', 'true'), ('supplier_outreach_golive', 'true'), ('supplier_final_touch_daily', '5'),
    ('supplier_whatsapp_click_to_chat', '12183166814')
  on conflict (key) do update set value = excluded.value;
  perform set_config('qd.duty_fixtures', 'on', true);
  for i in 1..6 loop
    insert into public.leads (company_name, email, lifecycle_stage, is_demo) values ('ZZ DEMO Parked ' || i, 'parked' || i || '.' || md5(random()::text) || '@example.invalid', 'no_response', true)
    returning id into v_lead;
    v_ids := v_ids || v_lead;
  end loop;
  r := public.fn_sales_engineer_final_touch_parked_suppliers(v_mon);
  if coalesce((r->>'queued')::int, -1) <> 5 then v_p := v_p || ('the cap of 5 queued ' || r::text); end if;
  if (select count(*) from public.supplier_final_touch where lead_id = any (v_ids)) <> 5 then v_p := v_p || 'the last notes were not recorded'::text; end if;
  r := public.fn_sales_engineer_final_touch_parked_suppliers(v_mon + interval '1 hour');
  if coalesce((r->>'queued')::int, -1) <> 0 then v_p := v_p || ('the same day went over the cap: ' || r::text); end if;
  r := public.fn_sales_engineer_final_touch_parked_suppliers(v_mon + interval '1 day');
  if coalesce((r->>'queued')::int, -1) <> 1 or (select count(*) from public.supplier_final_touch where lead_id = any (v_ids)) <> 6 then v_p := v_p || ('the next day did not take the sixth only: ' || r::text); end if;
  r := public.fn_sales_engineer_final_touch_parked_suppliers(v_mon + interval '2 days');
  if coalesce((r->>'queued')::int, -1) <> 0 then v_p := v_p || 'a parked lead was touched twice'::text; end if;
  if exists (select 1 from public.leads where id = any (v_ids) and lifecycle_stage <> 'no_response') then v_p := v_p || 'a touched lead left the parked stage'::text; end if;
  if exists (select 1 from public.notifications where lead_id = any (v_ids) and channel = 'whatsapp') then v_p := v_p || 'a WhatsApp message was queued'::text; end if;
  -- held on a weekend and when the campaign is closed
  if (public.fn_sales_engineer_final_touch_parked_suppliers(timestamptz '2026-11-21 08:00:00+00')->>'queued')::int <> 0 then v_p := v_p || 'a Saturday sent a last note'::text; end if;
  update public.app_secrets set value = 'false' where key = 'invite_enabled';
  if (public.fn_sales_engineer_final_touch_parked_suppliers(v_mon + interval '3 days')->>'held') not like '%not open%' then v_p := v_p || 'a closed campaign sent a last note'::text; end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when cardinality(v_p) = 0 then 'PROBE OK' else 'PROBE FAILED' end, 'problems', to_jsonb(v_p));
end $probe$;
