-- PROBE for an_m365_invitation_says_whether_it_left_and_whether_it_bounced.sql. Seat: sales_engineer. Always raises, so every
-- row it touches is rolled back; it writes no row of its own that could survive.
-- 1. Every M365 invitation a delivery report quotes by its exact Message-ID reads 'undelivered' with a 'bounce:' code.
-- 2. The claim hands out only M365 sends with no status; 'sent' is written once and never over a bounce; five failed
--    tries read 'unreadable'.
-- 3. A bounce overwrites 'sent'.
-- 4. A permanent bounce from our own tenant's Exchange (no authentication result, exact Message-ID) marks its lead bounced.
do $probe$
declare
  v_quoted int; v_marked int; v_a bigint; v_b bigint; v_r jsonb; v_inb bigint; v_nid bigint; v_lead bigint; i int;
begin
  select count(distinct n.id), count(distinct n.id) filter (where n.provider_status = 'undelivered' and n.provider_error_code like 'bounce:%')
    into v_quoted, v_marked
    from public.inbound_messages m
    join public.notifications n on n.id = nullif(substring(coalesce(m.raw->>'in_reply_to', '') || ' ' || coalesce(m.raw->>'references', '') from 'qd-notif-([0-9]+)\.'), '')::bigint
   where public.fn_inbound_is_bounce(m.from_email, m.subject, m.raw) and n.provider_message_id like 'm365:<%>'
     and position(substr(n.provider_message_id, 6) in coalesce(m.raw->>'in_reply_to', '') || ' ' || coalesce(m.raw->>'references', '')) > 0
     and coalesce(m.subject, '') !~* 'delay';
  if v_quoted <> v_marked then raise exception 'PROBE FAILED: % sends quoted by a bounce, % marked undelivered', v_quoted, v_marked; end if;

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
  for i in 1..5 loop perform public.fn_m365_sent_status_record(v_b, false, null, 200, 'm365:not_in_sent_items'); end loop;
  if (select provider_status || '/' || provider_error_code from public.notifications where id = v_b) <> 'unreadable/m365:not_in_sent_items' then
    raise exception 'PROBE FAILED: five failed tries did not read unreadable';
  end if;

  -- 3 and 4 on a real report of our own tenant's Exchange, if one exists: its send set back to 'sent', its lead to 'sent'
  select m.id, n.id, n.lead_id into v_inb, v_nid, v_lead
    from public.inbound_messages m
    join public.notifications n on n.id = nullif(substring(coalesce(m.raw->>'in_reply_to', '') from 'qd-notif-([0-9]+)\.'), '')::bigint
   where coalesce(m.raw->>'sender_authenticated', 'false') <> 'true' and n.provider_message_id like 'm365:<%>'
     and position(substr(n.provider_message_id, 6) in coalesce(m.raw->>'in_reply_to', '')) > 0
     and m.body ~ '5\.1\.1\M' and position(lower(btrim(n.to_email)) in lower(m.body)) > 0
   order by m.id limit 1;
  if v_inb is null then
    raise exception 'PROBE OK: % of % quoted sends read undelivered; claim, sent, unreadable as written; no own-tenant report to replay', v_marked, v_quoted;
  end if;
  update public.notifications set provider_status = 'sent' where id = v_nid;
  update public.leads set invite_status = 'sent' where id = v_lead;
  update public.inbound_messages set owner_role = null where id = v_inb;
  v_r := public.fn_supplier_mailbox_mail_gets_its_owner(v_inb);
  if (select provider_status from public.notifications where id = v_nid) <> 'undelivered' then
    raise exception 'PROBE FAILED: a bounce did not overwrite sent on %', v_nid;
  end if;
  if (select invite_status from public.leads where id = v_lead) <> 'bounced' then
    raise exception 'PROBE FAILED: our own tenant''s permanent bounce did not mark lead % bounced: %', v_lead, v_r;
  end if;
  raise exception 'PROBE OK: % of % quoted sends read undelivered; claim, sent, unreadable as written; report % overwrote sent and marked lead % bounced',
    v_marked, v_quoted, v_inb, v_lead;
end
$probe$;
