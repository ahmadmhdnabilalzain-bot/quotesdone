-- PROBE for an_m365_invitation_says_whether_it_left_and_whether_it_bounced.sql. Seat: sales_engineer. Always raises, so every
-- row it touches is rolled back; it writes no row of its own that could survive. Each step fails on the reviewed head of #1792.
--  1. A report quoting our exact Message-ID from an unauthenticated sender that is not our tenant's stamped Exchange marks
--     nothing (neither the lead nor the send); the same report stamped exchange_internal marks the lead and the send.
--  2. A report naming our send only in References writes nothing.
--  3. A delay notice carrying a dotted number (5.62.10.1) writes nothing; a report with no 5.x.x code writes nothing.
--  4. Five 503s are not five tries; five 200s with no such message are, and read 'unreadable'.
--  Also: the claim hands out only M365 sends with no status, and 'sent' is written once.
do $probe$
declare
  v_a bigint; v_b bigint; v_r jsonb; v_inb bigint; v_nid bigint; v_lead bigint; v_auth bigint; v_anid bigint; i int; v_backfilled int; v_list text;
begin
  select count(*) into v_backfilled from public.notifications where provider_message_id like 'm365:<%>' and provider_status = 'undelivered';

  -- 0. CONTROLS ON THE 7 REAL REPORTS of 29-30 Oct (inbound 1484, 1611-1614, 1617, 1618; review of #1792).
  --    Negative: with no tenant stamp, only Gmail's authenticated report marks its send. Positive: once the re-read records
  --    the tenant's stamp on the other six, all 7 sends read undelivered with the code each report carries.
  update public.notifications set provider_status = null, provider_error_code = null
   where id in (117550, 117555, 117557, 117559, 117560, 117580, 117584);
  update public.inbound_messages set raw = raw - 'exchange_internal' where id in (1484, 1611, 1612, 1613, 1614, 1617, 1618);
  perform public.fn_mail_bounce_marks_its_send(x) from unnest(array[1484, 1611, 1612, 1613, 1614, 1617, 1618]::bigint[]) x;
  select string_agg(id || '=' || provider_error_code, ', ' order by id) into v_list from public.notifications
   where id in (117550, 117555, 117557, 117559, 117560, 117580, 117584) and provider_status = 'undelivered';
  if v_list is distinct from '117557=bounce:gmail:NoSuchUser' then
    raise exception 'PROBE FAILED: unstamped reports gave [%], expected Gmail''s alone', v_list;
  end if;
  perform public.fn_mail_bounce_headers_record(x, true) from unnest(array[1611, 1612, 1613, 1614, 1617, 1618]::bigint[]) x;
  select string_agg(id || '=' || provider_error_code, ', ' order by id) into v_list from public.notifications
   where id in (117550, 117555, 117557, 117559, 117560, 117580, 117584) and provider_status = 'undelivered';
  if v_list is distinct from '117550=bounce:5.1.1, 117555=bounce:5.1.1, 117557=bounce:gmail:NoSuchUser, 117559=bounce:5.4.310, 117560=bounce:5.4.316, 117580=bounce:5.1.1, 117584=bounce:5.4.311' then
    raise exception 'PROBE FAILED: the 7 real reports gave [%]', v_list;
  end if;
  update public.inbound_messages set raw = raw - 'exchange_internal' where id in (1611, 1612, 1613, 1614, 1617, 1618);

  -- 1. our tenant's report 1611-style: unauthenticated, exact In-Reply-To, a 5.1.1
  select m.id, n.id, n.lead_id into v_inb, v_nid, v_lead
    from public.inbound_messages m
    join public.notifications n on n.id = nullif(substring(coalesce(m.raw->>'in_reply_to', '') from 'qd-notif-([0-9]+)\.'), '')::bigint
   where coalesce(m.raw->>'sender_authenticated', 'false') <> 'true' and n.provider_message_id like 'm365:<%>'
     and position(substr(n.provider_message_id, 6) in coalesce(m.raw->>'in_reply_to', '')) > 0
     and m.body ~ '5\.1\.1' and position(lower(btrim(n.to_email)) in lower(m.body)) > 0
   order by m.id limit 1;
  if v_inb is null then raise exception 'PROBE FAILED: no unauthenticated report of our tenant to replay'; end if;
  update public.notifications set provider_status = null, provider_error_code = null where id = v_nid;
  update public.leads set invite_status = 'sent' where id = v_lead;
  update public.inbound_messages set owner_role = null, raw = raw - 'exchange_internal' where id = v_inb;
  perform public.fn_supplier_mailbox_mail_gets_its_owner(v_inb);
  if (select invite_status from public.leads where id = v_lead) = 'bounced' or (select provider_status from public.notifications where id = v_nid) is not null then
    raise exception 'PROBE FAILED: an unauthenticated report that only knew the Message-ID marked lead % or send %', v_lead, v_nid;
  end if;
  -- final review of #1792: an authenticated sender that is not Gmail's mailer-daemon (a DMARC pass anyone on a shared SPF
  -- sender can get) marks nothing either
  update public.inbound_messages set owner_role = null, raw = raw || '{"sender_authenticated": true}'::jsonb, from_email = 'postmaster@quotesdone.com' where id = v_inb;
  perform public.fn_supplier_mailbox_mail_gets_its_owner(v_inb);
  if (select invite_status from public.leads where id = v_lead) = 'bounced' or (select provider_status from public.notifications where id = v_nid) is not null then
    raise exception 'PROBE FAILED: an authenticated sender that is neither our tenant nor Gmail marked lead % or send %', v_lead, v_nid;
  end if;
  update public.inbound_messages set owner_role = null, raw = (raw - 'sender_authenticated') || '{"sender_authenticated": false, "exchange_internal": true}'::jsonb,
         from_email = 'microsoftexchange329e71ec88ae4615bbc36ab6ce41109e@netorgft20811795.onmicrosoft.com' where id = v_inb;
  perform public.fn_supplier_mailbox_mail_gets_its_owner(v_inb);
  if (select invite_status from public.leads where id = v_lead) <> 'bounced' or (select provider_status from public.notifications where id = v_nid) is distinct from 'undelivered' then
    raise exception 'PROBE FAILED: our tenant''s stamped report did not mark lead % and send %', v_lead, v_nid;
  end if;

  -- 2 and 3 on an authenticated report (1484-style)
  select m.id, n.id into v_auth, v_anid
    from public.inbound_messages m
    join public.notifications n on n.id = nullif(substring(coalesce(m.raw->>'in_reply_to', '') from 'qd-notif-([0-9]+)\.'), '')::bigint
   where coalesce(m.raw->>'sender_authenticated', 'false') = 'true' and n.provider_message_id like 'm365:<%>'
     and public.fn_inbound_is_bounce(m.from_email, m.subject, m.raw)
   order by m.id limit 1;
  if v_auth is not null then
    update public.inbound_messages set raw = jsonb_set(jsonb_set(raw, '{references}', to_jsonb(raw->>'in_reply_to')), '{in_reply_to}', '""'::jsonb) where id = v_auth;
    update public.notifications set provider_status = null, provider_error_code = null where id = v_anid;
    perform public.fn_mail_bounce_marks_its_send(v_auth);
    if (select provider_status from public.notifications where id = v_anid) is not null then
      raise exception 'PROBE FAILED: a report naming our send only in References marked it';
    end if;
    update public.inbound_messages set raw = jsonb_set(raw, '{in_reply_to}', raw->'references'),
           subject = 'Delivery Status Notification (Delay)', body = 'Delivery to the recipient is delayed; we will retry. Remote host 5.62.10.1.'
     where id = v_auth;
    perform public.fn_mail_bounce_marks_its_send(v_auth);
    if (select provider_status from public.notifications where id = v_anid) is not null then
      raise exception 'PROBE FAILED: a delay notice with an IP address marked the send undelivered';
    end if;
    update public.inbound_messages set subject = 'Undeliverable: Delivery Status Notification (Failure)', body = 'The message could not be delivered.' where id = v_auth;
    perform public.fn_mail_bounce_marks_its_send(v_auth);
    if (select provider_status from public.notifications where id = v_anid) is not null then
      raise exception 'PROBE FAILED: a report with no 5.x.x code wrote a status';
    end if;
  end if;

  -- 4 and the claim
  select min(c.notification_id), max(c.notification_id) into v_a, v_b from public.fn_m365_sent_status_claim(50) c;
  if v_a is null or v_a = v_b then raise exception 'PROBE FAILED: the claim returned fewer than two M365 sends with no status'; end if;
  if exists (select 1 from public.notifications where id in (v_a, v_b) and (provider_status is not null or provider_message_id not like 'm365:<%>')) then
    raise exception 'PROBE FAILED: the claim handed out a send that is not an M365 send with no status';
  end if;
  perform public.fn_m365_sent_status_record(v_a, true, '2026-10-30T06:02:08Z', 200, null);
  v_r := public.fn_m365_sent_status_record(v_a, true, now(), 200, null);
  if (select provider_status from public.notifications where id = v_a) <> 'sent' or (v_r->>'applied')::boolean then
    raise exception 'PROBE FAILED: found in Sent Items did not read sent once: %', v_r;
  end if;
  for i in 1..5 loop perform public.fn_m365_sent_status_record(v_b, false, null, 503, 'http:503'); end loop;
  if (select provider_status from public.notifications where id = v_b) is not null or (select coalesce(provider_poll_failures, 0) from public.notifications where id = v_b) <> 0 then
    raise exception 'PROBE FAILED: five 503s were counted as tries';
  end if;
  for i in 1..5 loop perform public.fn_m365_sent_status_record(v_b, false, null, 200, 'm365:not_in_sent_items'); end loop;
  if (select provider_status || '/' || provider_error_code from public.notifications where id = v_b) <> 'unreadable/m365:not_in_sent_items' then
    raise exception 'PROBE FAILED: five 200s with no such message did not read unreadable';
  end if;
  raise exception 'PROBE OK: backfill marked % undelivered; forged-sender report marked nothing, stamped one marked lead % and send %; References-only, delay+IP and no-code wrote nothing (report %); 503s not counted, five empty 200s unreadable',
    v_backfilled, v_lead, v_nid, coalesce(v_auth::text, 'none');
end
$probe$;
