-- PROBE: AN INVITATION OPEN IS MEASURED, ON A TRACKED SHARE, AND REACHES THE CEO.
--
-- Seat: marketing. 3 Nov 2026. Pure probe: no DDL, never applied. Run after
-- an_invitation_open_is_measured_on_a_tracked_share_and_reaches_the_ceo.sql (apply-on-merge runs both in one rolled-back
-- transaction, then the probe alone after the apply). It always raises, so every write below is rolled back: two fixture
-- leads, three notifications inserted already 'sent' (send_outbox only ever claims 'queued' rows, and the addresses are on
-- a subdomain that has no MX, so nothing here can reach a person even if a step were committed), their tokens, opens and
-- one inbound message, and the share switch, set to 100 and then 0 inside the transaction only.
--
-- PROBE OK only if
--   1. the switch reads 'off'/'20%'/'250'/'x' as 0/20/100/0, and the arm is a fixed function of the lead;
--   2. a supplier invitation gets one 32-hex token, the same on a second call; a control-arm row (share 0), a customer
--      row and a placement seed get none;
--   3. an Apple-proxy load is machine_prefetch, an Outlook load four days later is likely_human; a bad and an unknown
--      token are refused; no stored column holds the raw address, and ip_hash is 64 hex;
--   4. the classifier gives the documented answer on twelve sample user agents, addresses and timings;
--   5. the funnel counts the fixtures exactly once in their arms (tracked: sent, opened_any, opened_human; control: sent,
--      replied), its sent / bounced / complained over both arms equal fn_invite_send_health over the same window, and
--      the follow-up list names the tracked lead (opened by a person 3.5 days ago, not registered) and not the control;
--   6. the marketing seat's figures and the CEO's seat board carry invitation_opens, and anon / authenticated can run none
--      of the new routines.
do $probe$
declare
  fails text := '';
  v_from timestamptz := now() - interval '6 days';
  l1 bigint; l2 bigint; n1 bigint; n2 bigint; n3 bigint; n4 bigint;
  tok text; tok2 text; r1 text; r2 text; r3 text; r4 text;
  b jsonb; a jsonb; h record; s_sent int; s_b int; s_c int; c record;
begin
  -- 1. the switch
  insert into public.app_secrets (key, value, updated_at) values ('invite_open_tracking', 'off', now())
    on conflict (key) do update set value = excluded.value;
  if public.fn_invite_open_share() <> 0 then fails := fails || ' 1:off'; end if;
  update public.app_secrets set value = '20%' where key = 'invite_open_tracking';
  if public.fn_invite_open_share() <> 20 then fails := fails || ' 1:20pct'; end if;
  update public.app_secrets set value = '250' where key = 'invite_open_tracking';
  if public.fn_invite_open_share() <> 100 then fails := fails || ' 1:clamp'; end if;
  update public.app_secrets set value = 'x' where key = 'invite_open_tracking';
  if public.fn_invite_open_share() <> 0 then fails := fails || ' 1:garbage'; end if;
  if public.fn_invite_open_arm('4711', 37) is distinct from public.fn_invite_open_arm('4711', 37)
     or (select count(*) filter (where public.fn_invite_open_arm(g::text, 20)) from generate_series(1, 2000) g) not between 300 and 500 then
    fails := fails || ' 1:arm'; end if;

  b := public.fn_invite_open_summary(v_from, now());

  -- 2. tokens (fixtures: never-deliverable subdomain, rows already 'sent')
  insert into public.leads (company_name, email) values ('Open Probe Tracked Trading LLC', 'open-probe-a@open-probe.quotesdone.com') returning id into l1;
  insert into public.leads (company_name, email) values ('Open Probe Control Trading LLC', 'open-probe-b@open-probe.quotesdone.com') returning id into l2;
  -- a07 (fn_notifications_supplier_invite_is_whole) is BEFORE INSERT and asks for an eligible, MX-checked, email-verified
  -- lead; a fixture cannot be one without writing to those registers. The two invitations are therefore inserted as
  -- nudges and re-typed: an UPDATE of type fires none of the invitation triggers (z81 is on sent_at, a01 on seeds).
  insert into public.notifications (type, to_role, to_email, lead_id, subject, body, status, sent_at, channel, lang)
  values ('supplier_invite_nudge', 'supplier', 'open-probe-a@open-probe.quotesdone.com', l1, 'A question about your work in the UAE', 'Hi Open Probe Tracked Trading LLC team,', 'sent', now() - interval '4 days', 'email', 'en')
  returning id into n1;
  insert into public.notifications (type, to_role, to_email, lead_id, subject, body, status, sent_at, channel, lang)
  values ('supplier_invite_nudge', 'supplier', 'open-probe-b@open-probe.quotesdone.com', l2, 'A question about your work in the UAE', 'Hi Open Probe Control Trading LLC team,', 'sent', now() - interval '4 days', 'email', 'en')
  returning id into n2;
  update public.notifications set type = 'supplier_invite' where id in (n1, n2);
  insert into public.notifications (type, to_role, to_email, subject, body, status, sent_at, channel, lang)
  values ('quote_received', 'customer', 'open-probe-c@open-probe.quotesdone.com', 'x', 'x', 'sent', now(), 'email', 'en') returning id into n3;
  insert into public.notifications (type, to_role, to_email, lead_id, subject, body, status, sent_at, channel, lang)
  values ('supplier_invite_seed', 'supplier', 'open-probe-a@open-probe.quotesdone.com', l1, 'x', 'x', 'sent', now(), 'email', 'en') returning id into n4;

  update public.app_secrets set value = '100' where key = 'invite_open_tracking';
  tok := public.fn_invite_open_token(n1);
  tok2 := public.fn_invite_open_token(n1);
  if tok is null or tok !~ '^[0-9a-f]{32}$' or tok2 is distinct from tok then fails := fails || ' 2:token'; end if;
  if strpos(tok, l1::text) > 0 and length(l1::text) > 3 then fails := fails || ' 2:token_carries_lead'; end if;
  if public.fn_invite_open_token(n3) is not null or public.fn_invite_open_token(n4) is not null then fails := fails || ' 2:not_a_tracked_kind'; end if;
  update public.app_secrets set value = '0' where key = 'invite_open_tracking';
  if public.fn_invite_open_token(n2) is not null then fails := fails || ' 2:control_got_a_token'; end if;
  if public.fn_invite_open_token(n1) is distinct from tok then fails := fails || ' 2:token_moved_when_share_changed'; end if;

  -- 3. opens
  r1 := public.fn_email_open_record(tok, 'Mozilla/5.0', '17.58.1.2');
  r2 := public.fn_email_open_record(tok, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Microsoft Outlook 16.0.17126', '203.0.113.9, 10.0.0.1');
  r3 := public.fn_email_open_record('nothex', 'x', '1.2.3.4');
  r4 := public.fn_email_open_record(repeat('0', 32), 'x', '1.2.3.4');
  if r1 <> 'machine_prefetch' or r2 <> 'likely_human' or r3 <> 'bad_token' or r4 <> 'unknown_token' then
    fails := fails || ' 3:record(' || r1 || ',' || r2 || ',' || r3 || ',' || r4 || ')'; end if;
  if exists (select 1 from public.email_open_event e where e.token = tok
              and (to_jsonb(e)::text like '%203.0.113.9%' or to_jsonb(e)::text like '%17.58.1.2%' or e.ip_hash !~ '^[0-9a-f]{64}$')) then
    fails := fails || ' 3:raw_ip_or_hash'; end if;
  if (select array_agg(ip_class order by id) from public.email_open_event where token = tok) is distinct from array['apple', null]::text[] then
    fails := fails || ' 3:ip_class'; end if;
  update public.email_open_event set opened_at = now() - interval '3 days 12 hours' where token = tok;
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, created_at)
  values (l2, 'open-probe-b@open-probe.quotesdone.com', 'supplier@quotesdone.com', 're', 'stop', now() - interval '3 days');

  -- 4. the classifier on samples (user agent, address, seconds after the send) -> expected
  for c in select * from (values
      ('GoogleImageProxy', null, 10, 'machine_prefetch'),
      ('Mozilla/5.0 (Windows NT 5.1; rv:11.0) Gecko Firefox/11.0 (via ggpht.com GoogleImageProxy)', null, 900, 'likely_human'),
      ('YahooMailProxy; https://help.yahoo.com/kb/yahoo-mail-proxy-SLN28749.html', null, 5, 'machine_prefetch'),
      ('Mozilla/5.0', null, 7200, 'machine_prefetch'),
      ('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15', '17.0.0.9', 7200, 'machine_prefetch'),
      ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0 Safari/537.36', '40.92.18.4', 900, 'machine_prefetch'),
      ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0 Safari/537.36', '2a01:111:f400::5', 900, 'machine_prefetch'),
      ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0 Safari/537.36', '198.51.100.7', 30, 'machine_prefetch'),
      ('python-requests/2.31.0', '198.51.100.7', 900, 'machine_prefetch'),
      ('Microsoft Office/16.0 (Windows NT 10.0; Microsoft Outlook 16.0.17126; Pro)', '198.51.100.7', 900, 'likely_human'),
      ('', '198.51.100.7', 900, 'unknown'),
      ('Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)', '198.51.100.7', null, 'unknown')) v(ua, ip, secs, want) loop
    if (select x.classification from public.fn_email_open_classify(c.ua, c.ip::inet, c.secs::numeric) x) is distinct from c.want then
      fails := fails || ' 4:' || left(c.ua, 24) || '@' || coalesce(c.secs::text, 'null'); end if;
  end loop;

  -- 5. the funnel, the follow-up list, the summary
  a := public.fn_invite_open_summary(v_from, now());
  if coalesce((a #>> '{by_arm,tracked,sent}')::int, 0) - coalesce((b #>> '{by_arm,tracked,sent}')::int, 0) <> 1
     or coalesce((a #>> '{by_arm,tracked,opened_any}')::int, 0) - coalesce((b #>> '{by_arm,tracked,opened_any}')::int, 0) <> 1
     or coalesce((a #>> '{by_arm,tracked,opened_human}')::int, 0) - coalesce((b #>> '{by_arm,tracked,opened_human}')::int, 0) <> 1
     or coalesce((a #>> '{by_arm,untracked,sent}')::int, 0) - coalesce((b #>> '{by_arm,untracked,sent}')::int, 0) <> 1
     or coalesce((a #>> '{by_arm,untracked,replied}')::int, 0) - coalesce((b #>> '{by_arm,untracked,replied}')::int, 0) <> 1
     or coalesce((a #>> '{by_arm,untracked,opened_any}')::int, 0) <> 0 then
    fails := fails || ' 5:funnel'; end if;
  select coalesce(sum(f.sent), 0), coalesce(sum(f.bounced), 0), coalesce(sum(f.complained), 0) into s_sent, s_b, s_c from public.fn_invite_open_funnel(v_from, now()) f;
  select * into h from public.fn_invite_send_health(v_from);
  if (s_sent, s_b, s_c) is distinct from (h.sent, h.bounced, h.complained) then
    fails := fails || ' 5:send_health(' || s_sent || '/' || h.sent || ')'; end if;
  if not exists (select 1 from public.fn_invite_opened_not_registered(3) x where x.lead_id = l1 and x.human_opens = 1 and x.days_since_first_open = 3)
     or exists (select 1 from public.fn_invite_opened_not_registered(3) x where x.lead_id = l2)
     or exists (select 1 from public.fn_invite_opened_not_registered(4) x where x.lead_id = l1) then
    fails := fails || ' 5:follow_up_list'; end if;

  -- 6. wiring and grants
  if not (public.fn_marketing_report_figures(now() - interval '1 day', now()) -> 'measured' ? 'invitation_opens')
     or public.fn_marketing_report_figures(now() - interval '1 day', now()) ->> 'headline' not like '%Invitations:%'
     or not (public.fn_ceo_seat_board(7) #> '{seats,marketing,achievement}' ? 'invitation_opens') then
    fails := fails || ' 6:wiring'; end if;
  if has_function_privilege('anon', 'public.fn_email_open_record(text,text,text)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_invite_open_token(bigint)', 'execute')
     or has_function_privilege('anon', 'public.fn_invite_opened_not_registered(integer)', 'execute')
     or has_table_privilege('anon', 'public.email_open_event', 'select') then
    fails := fails || ' 6:grants'; end if;

  raise exception 'CHK<<%>>', case when fails = ''
    then 'PROBE OK token=' || left(tok, 6) || '... opens=' || r1 || ',' || r2 || ' tracked_sent+1 human+1 control_sent+1 replied+1 send_health=' || s_sent
    else 'PROBE FAILED:' || fails end;
end $probe$;
