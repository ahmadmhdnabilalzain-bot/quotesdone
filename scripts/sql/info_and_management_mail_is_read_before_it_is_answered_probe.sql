-- PROBE: info@ AND management@ MAIL IS READ BEFORE IT IS ANSWERED (ledger 1446, 1453, 1543; it_engineer).
--
-- A pure probe: it always raises CHK<<...>>, so every row it writes is rolled back. Nothing can reach a person: the senders are
-- on example.invalid, no notification is sent (fn_inbox_send only queues, and the queue row is rolled back).
--   1. a mail to info@ and one to management@ are the reading's (fn_mailbox_reply_rules says supplier_mailbox true); a mail to
--      info@mail.quotesdone.com (the Resend address) is not;
--   2. read as legal_or_press: recorded, may_reply false, and a seat's answer is refused by fn_inbox_send;
--   3. read as spam_or_irrelevant on management@: the same refusal;
--   4. read as customer: may_reply true and the seat's answer is queued under the mailbox_auto_reply key send_outbox checks;
--   5. mail.routed is registered from customer_support to accountant, it_engineer, marketing and ceo (never a founder seat),
--      and its handler answers.
-- Before info_and_management_mail_is_read_before_it_is_answered.sql it fails at 1.
do $probe$
declare v_info bigint; v_mgmt bigint; v_resend bigint; v_r jsonb; v_d jsonb; v_s jsonb; v_kinds text;
begin
  insert into public.inbound_messages (from_email, to_email, subject, body, raw)
  values ('qd-probe-l5-legal@example.invalid', 'info@quotesdone.com', 'Notice on behalf of our client', 'We write regarding your use of the mark.', '{}')
  returning id into v_info;
  insert into public.inbound_messages (from_email, to_email, subject, body, raw)
  values ('qd-probe-l5-spam@example.invalid', 'management@quotesdone.com', 'You have won', 'Send your bank details.', '{}')
  returning id into v_mgmt;
  insert into public.inbound_messages (from_email, to_email, subject, body, raw)
  values ('qd-probe-l5-buyer@example.invalid', 'info@mail.quotesdone.com', 'Quote', 'How do I get quotes?', '{}')
  returning id into v_resend;

  v_r := public.fn_mailbox_reply_rules(v_info);
  if coalesce((v_r ->> 'supplier_mailbox')::boolean, false) is not true or coalesce((public.fn_mailbox_reply_rules(v_mgmt) ->> 'supplier_mailbox')::boolean, false) is not true then
    raise exception 'CHK<<PROBE FAILED: info@ or management@ mail is not read before it is answered (rules: %)>>', v_r;
  end if;
  if coalesce((public.fn_mailbox_reply_rules(v_resend) ->> 'supplier_mailbox')::boolean, false) then
    raise exception 'CHK<<PROBE FAILED: info@mail.quotesdone.com mail was taken into the reading>>';
  end if;

  v_d := public.fn_mailbox_reply_decide(v_info, 'legal_or_press', 'probe: a law firm writes about our mark', 'on behalf of our client', 'model', 'probe/model', 'high');
  if v_d ->> 'reading' <> 'legal_or_press' or (v_d ->> 'may_reply')::boolean then
    raise exception 'CHK<<PROBE FAILED: legal_or_press was not recorded as a reading that is never answered: %>>', v_d;
  end if;
  v_s := public.fn_inbox_send(v_info, 'probe answer', 'customer_support');
  if coalesce(v_s ->> 'error', '') not like 'refused: this mail was read as legal_or_press%' then
    raise exception 'CHK<<PROBE FAILED: a seat could answer legal mail to info@: %>>', v_s;
  end if;

  perform public.fn_mailbox_reply_decide(v_mgmt, 'spam_or_irrelevant', 'probe: a lottery scam', 'Send your bank details.', 'model', 'probe/model', 'high');
  v_s := public.fn_inbox_send(v_mgmt, 'probe answer', 'customer_support');
  if coalesce(v_s ->> 'error', '') not like 'refused: this mail was read as spam_or_irrelevant%' then
    raise exception 'CHK<<PROBE FAILED: a seat could answer spam to management@: %>>', v_s;
  end if;

  v_d := public.fn_mailbox_reply_decide(v_info, 'customer', 'probe: a buyer asks for quotes', 'How do I get quotes?', 'model', 'probe/model', 'high');
  v_s := public.fn_inbox_send(v_info, 'probe answer', 'customer_support');
  if not coalesce((v_d ->> 'may_reply')::boolean, false) or coalesce((v_s ->> 'ok')::boolean, false) is not true
     or not exists (select 1 from public.notifications where id = (v_s ->> 'notification_id')::bigint and dedupe_key like 'mailbox_auto_reply:%') then
    raise exception 'CHK<<PROBE FAILED: a customer read on info@ was not answerable through the gated key: decide % send %>>', v_d, v_s;
  end if;

  select string_agg(to_seat, ',' order by to_seat) into v_kinds from public.seat_handoff_kind where type = 'mail.routed' and from_seat = 'customer_support';
  if v_kinds is distinct from 'accountant,ceo,it_engineer,marketing' or to_regprocedure('public.fn_mail_routed_waits(bigint)') is null then
    raise exception 'CHK<<PROBE FAILED: mail.routed kinds are %>>', v_kinds;
  end if;
  raise exception 'CHK<<PROBE OK: info@ and management@ are read first (Resend info@ is not); legal_or_press and spam are refused to a seat, a customer is answered under the gated key; mail.routed reaches %>>', v_kinds;
end $probe$;
