-- Pure probe: raises so everything rolls back. The address is on a domain nobody owns and the transaction never commits,
-- so nothing can reach the outbox's sender. Real leads 19398 and inbound 1483, 1485 are only read.
do $probe$
declare v_in bigint; v_h bigint; v_out jsonb; n_notif int; n_fu int; v_status text; v_sub bigint; v_sub_out jsonb; n_sub int; v_before bigint; v_rem jsonb; l public.leads;
begin
  insert into public.inbound_messages (from_email, to_email, subject, body, needs_review, triaged_at, raw)
  values ('qd-probe@qd-probe-nobody.invalid.qd', 'supplier@quotesdone.com', 'Re: Registration', 'Definitely but later', true, now(), '{}')
  returning id into v_in;
  v_h := public.fn_seat_handoff('marketing', 'sales_engineer', 'mailbox.supplier_reply', 'inbound_messages', v_in::text,
    jsonb_build_object('inbound_message_id', v_in, 'from_email', 'qd-probe@qd-probe-nobody.invalid.qd', 'reply_text', 'Definitely but later'));
  select status into v_status from public.agent_actions where id = v_h;
  select count(*) into n_notif from public.notifications where type = 'inbound_reply' and to_email like 'qd-probe@%' and status <> 'x';
  select count(*) into n_fu from public.supplier_reply_followup where inbound_message_id = v_in and intent = 'later';
  if v_status <> 'done' or n_notif <> 1 or n_fu <> 1 then
    raise exception 'CHK<<FAIL later: handoff % status %, % answer(s), % follow-up(s)>>', v_h, v_status, n_notif, n_fu;
  end if;

  insert into public.inbound_messages (from_email, to_email, subject, body, needs_review, raw)
  values ('qd-probe2@qd-probe-nobody.invalid.qd', 'supplier@quotesdone.com', 'Re: x', 'We have a subsidiary company with a separate licence, how do we add it?', true, '{}')
  returning id into v_sub;
  v_h := public.fn_seat_handoff('marketing', 'sales_engineer', 'mailbox.supplier_reply', 'inbound_messages', v_sub::text,
    jsonb_build_object('inbound_message_id', v_sub, 'from_email', 'qd-probe2@qd-probe-nobody.invalid.qd', 'reply_text', 'We have a subsidiary company with a separate licence, how do we add it?'));
  -- not triaged yet: it waits, and answers nothing
  select count(*) into n_sub from public.notifications where to_email like 'qd-probe2@%';
  if n_sub <> 0 or (select status from public.agent_actions where id = v_h) = 'done' then raise exception 'CHK<<FAIL: acted before triage>>'; end if;
  update public.inbound_messages set triaged_at = now() where id = v_sub;
  v_sub_out := public.fn_sales_engineer_follows_up_supplier_replies();
  select count(*) into n_sub from public.notifications where to_email like 'qd-probe2@%' and body like '%different e-mail address: one e-mail address manages one company%';
  if n_sub <> 1 or (select status from public.agent_actions where id = v_h) <> 'done'
     or not exists (select 1 from public.supplier_reply_followup where inbound_message_id = v_sub and intent = 'subsidiary') then
    raise exception 'CHK<<FAIL subsidiary: % answer(s), duty %>>', n_sub, v_sub_out;
  end if;

  -- the real replay: what the duty did for 1483 and 1485 inside this transaction
  select count(*) into n_notif from public.notifications where type = 'inbound_reply' and lower(to_email) like '%666realestate%';
  -- known-bad controls: triage already answered, so a subsidiary mail gets no second answer; another open case stays open
  insert into public.inbound_messages (from_email, to_email, subject, body, needs_review, triaged_at, replied_at, raw)
  values ('qd-probe3@qd-probe-nobody.invalid.qd', 'supplier@quotesdone.com', 'Re: y', 'our subsidiary please', false, now(), now(), '{}') returning id into v_before;
  perform public.fn_seat_handoff('marketing', 'sales_engineer', 'mailbox.supplier_reply', 'inbound_messages', v_before::text,
    jsonb_build_object('inbound_message_id', v_before, 'from_email', 'qd-probe3@qd-probe-nobody.invalid.qd', 'reply_text', 'our subsidiary please'));
  if exists (select 1 from public.notifications where to_email like 'qd-probe3@%') then raise exception 'CHK<<FAIL: a second answer after triage>>'; end if;
  select * into l from public.leads where id = 19398;
  v_rem := public.fn_supplier_registration_reminder_compose(l, 'started', 1);
  if (select status from public.agent_actions where id = 326819) <> 'done' or (select status from public.agent_actions where id = 329843) <> 'done' or n_notif <> 0 then
    raise exception 'CHK<<FAIL replay: 326819 %, 329843 %, 666 answers %>>', (select status from public.agent_actions where id = 326819), (select status from public.agent_actions where id = 329843), n_notif;
  end if;
  if v_rem->>'body' ~ 'verified mobile' or v_rem->>'body' !~ 'trade licence' then raise exception 'CHK<<FAIL reminder names done items: %>>', v_rem->>'body'; end if;

  raise exception 'CHK<<OK duty %; reminder %>>', v_sub_out, left(v_rem->>'body', 220);
end $probe$;
