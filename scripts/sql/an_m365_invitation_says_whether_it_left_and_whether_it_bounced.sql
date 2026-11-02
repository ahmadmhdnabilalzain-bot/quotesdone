-- AN M365 INVITATION SAYS WHETHER IT LEFT AND WHETHER IT BOUNCED (2 Nov 2026; memory: a status column is not a delivery record).
-- Seat: sales_engineer
--
-- MEASURED on production, 2 Nov 2026: 46 supplier_invite rows sent through the Microsoft 365 lane since 29 Oct carry
-- provider_message_id 'm365:<qd-notif-...@quotesdone.com>' and provider_status NULL on every one. Graph's sendMail answers
-- 202 with no id and no later event, so nothing ever wrote a delivery result. 7 of the 46 bounced: each has a delivery
-- report in supplier@'s mailbox (inbound_messages 1484, 1611-1614, 1617, 1618) whose In-Reply-To quotes the send's exact
-- Message-ID. Their leads read 'bounced', but the sends themselves still read NULL. 6 of the 7 came from our own tenant's Exchange
-- (microsoftexchange...@...onmicrosoft.com), which carries no authentication result, so fn_supplier_mailbox_mail_gets_its_owner
-- answered "the bounce's sender is not authenticated" and never marked those leads: the bounce brake (fn_invite_send_health
-- counts leads.invite_status 'bounced') only saw them because they were marked by another path.
--
-- WHAT THIS DOES
--  1. fn_m365_sent_status_claim / fn_m365_sent_status_record: resilience_ping (_shared/m365_sent_status.ts) asks Graph for
--     each M365 send in supplier@'s Sent Items by its internetMessageId. Found: provider_status 'sent' at Graph's
--     sentDateTime (Exchange took it and sent it; it does not prove the recipient's server accepted it). Not found or no answer:
--     provider_poll_failures + 1, and after 5 tries (2.5 h) 'unreadable' with the reason in provider_error_code. Never 'delivered':
--     Graph has no delivery receipt for this lane.
--  2. fn_mail_bounce_marks_its_send: a delivery report that quotes the EXACT Message-ID of an M365 send writes
--     'undelivered' and 'bounce:<enhanced code>' on that send. A delay notice writes nothing. A bounce overwrites 'sent'.
--  3. fn_supplier_mailbox_mail_gets_its_owner (live body, three edits): an exact Message-ID match counts as authenticated,
--     so a permanent bounce from our own tenant's Exchange marks the lead 'bounced' and the bounce brake counts it; it
--     calls (2).
--  4. Backfill, at apply, from what Graph already returned: every report in inbound_messages naming a qd-notif send goes
--     through (2). The Sent Items read-back fills the rest on resilience_ping's 15-minute beat, 20 sends at a time.
-- Prevented by: supabase/functions/_shared/m365_sent_status.test.ts, an_m365_invitation_says_whether_it_left_and_whether_it_bounced_probe.sql

-- 1. THE SENT ITEMS READ-BACK
create or replace function public.fn_m365_sent_status_claim(p_limit int default 20)
returns table (notification_id bigint, message_id text)
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  return query
  update public.notifications u set provider_status_checked_at = now()
   where u.id in (select c.id from public.notifications c
                   where coalesce(c.channel, 'email') = 'email' and c.provider_message_id like 'm365:<%>'
                     and c.sent_at < now() - interval '10 minutes'
                     and c.provider_status is null
                     and (c.provider_status_checked_at is null or c.provider_status_checked_at < now() - interval '30 minutes')
                   -- invitations before the 435 warm-up seeds of 5-28 Oct (measured 2 Nov), each oldest-asked first
                   order by c.type <> 'supplier_invite', coalesce(c.provider_status_checked_at, c.sent_at)
                   limit least(greatest(coalesce(p_limit, 20), 1), 50)
                   for update skip locked)
  returning u.id, substr(u.provider_message_id, 6);
end $fn$;
revoke execute on function public.fn_m365_sent_status_claim(int) from public, anon, authenticated;

create or replace function public.fn_m365_sent_status_record(p_notification_id bigint, p_found boolean, p_sent_at timestamptz default null,
                                                            p_http int default null, p_code text default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  c_give_up constant int := 5;   -- 5 x 30 minutes: 2.5 hours of asking before the answer is recorded as unknown
  n public.notifications; v_fails int;
begin
  select * into n from public.notifications where id = p_notification_id for update;
  if n.id is null or coalesce(n.provider_message_id, '') not like 'm365:%' then return jsonb_build_object('matched', false); end if;
  if n.provider_status is not null then
    return jsonb_build_object('matched', true, 'applied', false, 'reason', 'already ' || n.provider_status);
  end if;
  if p_found then
    update public.notifications
       set provider_status = 'sent', provider_status_at = coalesce(p_sent_at, now()), provider_status_checked_at = now()
     where id = n.id;
    return jsonb_build_object('matched', true, 'applied', true, 'status', 'sent');
  end if;
  v_fails := coalesce(n.provider_poll_failures, 0) + 1;
  update public.notifications
     set provider_poll_failures = v_fails,
         provider_status = case when v_fails >= c_give_up then 'unreadable' end,
         provider_status_at = case when v_fails >= c_give_up then now() end,
         provider_error_code = left(coalesce(nullif(btrim(coalesce(p_code, '')), ''), 'http:' || coalesce(p_http::text, 'none')), 120)
   where id = n.id;
  return jsonb_build_object('matched', true, 'applied', true, 'failures', v_fails, 'gave_up', v_fails >= c_give_up);
end $fn$;
revoke execute on function public.fn_m365_sent_status_record(bigint, boolean, timestamptz, int, text) from public, anon, authenticated;

-- 2. A BOUNCE IS WRITTEN ON THE SEND IT IS ABOUT
create or replace function public.fn_mail_bounce_marks_its_send(p_inbound_id bigint)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare m public.inbound_messages; n public.notifications; v_ids text; v_nid bigint; v_text text; v_code text; v_n int;
begin
  select * into m from public.inbound_messages where id = p_inbound_id;
  if m.id is null or not public.fn_inbound_is_bounce(m.from_email, m.subject, m.raw) then
    return jsonb_build_object('applied', false, 'reason', 'not a delivery report');
  end if;
  v_ids := coalesce(m.raw->>'in_reply_to', '') || ' ' || coalesce(m.raw->>'references', '');
  v_nid := nullif(substring(v_ids from 'qd-notif-([0-9]+)\.'), '')::bigint;
  if v_nid is not null then select * into n from public.notifications where id = v_nid; end if;
  if n.id is null or coalesce(n.provider_message_id, '') not like 'm365:<%>' or position(substr(n.provider_message_id, 6) in v_ids) = 0 then
    return jsonb_build_object('applied', false, 'reason', 'it does not quote the exact Message-ID of an M365 send of ours', 'notification_id', v_nid);
  end if;
  v_text := left(coalesce(m.subject, '') || ' ' || coalesce(m.body, ''), 6000);
  v_code := substring(v_text from '\m(5\.[0-9]{1,3}\.[0-9]{1,3})\M');
  if v_code is null and v_text ~* '(delay|will retry|will be retried|still trying|temporar)' then
    return jsonb_build_object('applied', false, 'reason', 'a delay notice: the message may still arrive', 'notification_id', n.id);
  end if;
  update public.notifications
     set provider_status = 'undelivered', provider_status_at = m.created_at, provider_status_checked_at = now(),
         provider_error_code = 'bounce:' || coalesce(v_code, 'unknown')
   where id = n.id and provider_status is distinct from 'undelivered';
  get diagnostics v_n = row_count;
  return jsonb_build_object('applied', v_n > 0, 'notification_id', n.id, 'code', coalesce(v_code, 'unknown'));
end $fn$;
revoke execute on function public.fn_mail_bounce_marks_its_send(bigint) from public, anon, authenticated;

-- 3. THE OWNER OF SUPPLIER-MAILBOX MAIL (live body of every_reply_and_bounce_in_the_supplier_mailbox_has_an_owning_seat.sql,
--    edits: v_exact, the authentication test, the call to fn_mail_bounce_marks_its_send)
create or replace function public.fn_supplier_mailbox_mail_gets_its_owner(p_inbound_id bigint, p_filed jsonb default null, p_reassign boolean default false)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare m public.inbound_messages; n public.notifications;
  v_from text; v_boxes text[]; v_owner text; v_why text; v_reply text; v_hid bigint; v_nid bigint; v_to text;
  v_lead bigint; v_acted boolean := false; v_body text; v_exact boolean := false;
begin
  select * into m from public.inbound_messages where id = p_inbound_id;
  if not found then return jsonb_build_object('owner', null, 'reason', 'no such inbound message'); end if;
  -- an owner set by another path (the bookkeeper) is never taken; p_reassign may correct only an unowned row or a
  -- sales_engineer stamp, and never a row already answered
  if m.replied_at is not null then return jsonb_build_object('owner', m.owner_role, 'reason', 'already answered'); end if;
  if m.owner_role is not null and not (p_reassign and m.owner_role = 'sales_engineer') then
    return jsonb_build_object('owner', m.owner_role, 'reason', 'already owned');
  end if;
  select array_agg(lower(btrim(value))) into v_boxes from public.app_secrets
   where key in ('invite_m365_mailbox', 'email_reply_supplier') and btrim(coalesce(value, '')) <> '';
  if v_boxes is null or not exists (select 1 from unnest(v_boxes) b where position(b in lower(coalesce(m.to_email, ''))) > 0) then
    return jsonb_build_object('owner', m.owner_role, 'reason', 'not addressed to the supplier mailbox');
  end if;
  v_from := lower(substring(coalesce(m.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)'));

  if public.fn_inbound_is_bounce(m.from_email, m.subject, m.raw) then
    -- the email channel's delivery result: customer_support
    v_owner := 'customer_support';
    v_nid := nullif(substring(coalesce(m.raw->>'in_reply_to', '') || ' ' || coalesce(m.raw->>'references', '') from 'qd-notif-([0-9]+)\.'), '')::bigint;
    if v_nid is not null then select * into n from public.notifications where id = v_nid and channel = 'email'; end if;
    v_to := lower(btrim(n.to_email));
    -- 2 Nov 2026: the bounce quotes the exact Message-ID our send carried (a millisecond stamp only a receiving system saw),
    -- so it cannot be a forger guessing a qd-notif id. Our own tenant's Exchange NDRs carry no authentication result.
    v_exact := coalesce(n.provider_message_id like 'm365:%' and position(substr(n.provider_message_id, 6) in
                 coalesce(m.raw->>'in_reply_to', '') || ' ' || coalesce(m.raw->>'references', '')) > 0, false);
    v_body := left(coalesce(m.body, ''), 4000);
    if v_to is null or v_to = '' then
      v_why := 'a bounce that names no send of ours';
    elsif position(v_to in lower(v_body)) = 0 then
      v_why := 'the bounce does not name the address it was sent to';
    elsif v_to ~ '@(mail\.)?quotesdone\.(com|ae)$' or public.fn_is_founder_own_inbox(v_to) then
      v_why := 'never suppressed: our own or the founder''s address';
    elsif coalesce(m.raw->>'sender_authenticated', 'false') <> 'true' and not v_exact then
      -- a forged "postmaster" naming a guessed qd-notif id must never suppress a real address (resend_webhook verifies
      -- its signature for the same reason)
      v_why := 'the bounce''s sender is not authenticated';
    elsif v_body ~* '(temporar|try again later|will retry|delayed|mailbox (is )?full|over quota|5\.7\.[0-9]+|policy|blocked|spam)'
          or v_body !~* '(address not found|does ?n[o''’]t exist|no such (user|recipient|mailbox)|user unknown|unknown (user|recipient)|mailbox not found|could ?n[o''’]t be found|could not be found|5\.1\.1\M|5\.1\.10\M)' then
      -- a policy rejection (5.7.x, "blocked") is an address that exists; only "this address does not exist" is permanent
      v_why := 'not a permanent failure';
    else
      -- exactly as resend_webhook: suppress (an earlier reason such as an unsubscribe is kept) and mark the lead
      insert into public.email_suppressions (email, reason, source) values (v_to, 'hard_bounce:permanent', 'supplier_mailbox_bounce')
      on conflict (email) do nothing;
      -- (a CTE: several leads may share an address, and RETURNING INTO raises on more than one row)
      with u as (update public.leads set invite_status = 'bounced'
                  where lower(btrim(email)) = v_to and coalesce(invite_status, '') in ('', 'queued', 'sent')
                 returning id)
      select min(id) into v_lead from u;
      v_lead := coalesce(v_lead, n.lead_id);
      v_acted := true; v_why := 'a permanent bounce: the address is suppressed and its lead marked bounced';
    end if;
    perform public.fn_mail_bounce_marks_its_send(m.id);   -- the send's own row says it did not arrive
    update public.inbound_messages set owner_role = v_owner where id = m.id;
    insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
    values ('customer_support', 'mail_bounce', case when v_acted then 'auto_done' else 'skipped' end, 'low',
            left('Bounce in the supplier mailbox: ' || coalesce(v_to, 'unknown recipient') || ' (' || v_why || ')', 200),
            jsonb_build_object('inbound_message_id', m.id, 'notification_id', v_nid, 'recipient', v_to, 'lead_id', v_lead,
                               'suppressed', v_acted, 'reason', v_why),
            'inbound_messages', m.id::text);
    return jsonb_build_object('owner', v_owner, 'reason', v_why, 'suppressed', v_acted, 'recipient', v_to, 'lead_id', v_lead);
  end if;

  if public.fn_is_founder_own_inbox(v_from) then
    -- the founder answering a seed test: the it_engineer owns those tests; a supplier seat never answers him
    update public.inbound_messages set owner_role = 'it_engineer' where id = m.id;
    insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
    values ('it_engineer', 'seed_reply', 'auto_done', 'low',
            left('The founder''s own inbox answered a test send in the supplier mailbox: ' || coalesce(v_from, '?'), 200),
            jsonb_build_object('inbound_message_id', m.id, 'from_email', v_from, 'subject', left(coalesce(m.subject, ''), 200)),
            'inbound_messages', m.id::text);
    return jsonb_build_object('owner', 'it_engineer', 'reason', 'the founder''s own inbox');
  end if;

  -- a person: the sales engineer. The invite-reply filer decides first (it is idempotent through fn_seat_handoff).
  v_owner := 'sales_engineer';
  p_filed := coalesce(p_filed, public.fn_marketing_files_invite_reply(m.id));
  update public.inbound_messages set owner_role = v_owner where id = m.id;
  if coalesce((p_filed->>'due')::boolean, false) then
    return jsonb_build_object('owner', v_owner, 'reason', 'an invited supplier''s reply (invite.reply)', 'handoff_id', p_filed->'handoff_id');
  end if;
  v_why := coalesce(p_filed->>'reason', 'no reason');
  -- the filer tests "is it a lead" before "is it a machine", so an out-of-office from a non-lead is read here too
  if v_why in ('an automatic reply', 'a stop reply (handled as an unsubscribe)', 'an empty reply')
     or public.fn_inbound_is_auto_reply(m.subject, m.body, m.raw) then
    return jsonb_build_object('owner', v_owner, 'reason', case when v_why = 'the sender is no lead' then 'an automatic reply' else v_why end);
  end if;
  v_reply := btrim(regexp_replace(replace(coalesce(m.body, ''), E'\r', ''), E'(\\n|^)\\s*(>|On [^\\n]{0,200}wrote:|-{2,}\\s*Original Message|_{8,}|From:\\s).*$', ''));
  v_hid := public.fn_seat_handoff('marketing', 'sales_engineer', 'mailbox.supplier_reply', 'inbound_messages', m.id::text,
    jsonb_build_object('inbound_message_id', m.id, 'from_email', v_from, 'subject', left(coalesce(m.subject, ''), 200),
                       'reply_text', left(coalesce(nullif(v_reply, ''), m.body, ''), 4000), 'not_an_invite_reply_because', v_why,
                       'ask', 'Read this message to the supplier mailbox and answer it in its thread.',
                       'summary', jsonb_build_object(
                         'known', 'A person wrote to the supplier mailbox; the invite-reply path did not take it: ' || v_why || '.',
                         'tried', 'fn_marketing_files_invite_reply', 'needed', 'an answer in the thread',
                         'evidence', 'inbound_messages #' || m.id, 'context', left(coalesce(m.subject, ''), 200),
                         'decision', 'sales_engineer owns supplier conversations (seat map 24 Sep 2026)',
                         'open_asks', 'answer the sender', 'deadline', to_char(now() + interval '24 hours', 'YYYY-MM-DD"T"HH24:MI"Z"'))));
  return jsonb_build_object('owner', v_owner, 'reason', v_why, 'handoff_id', v_hid);
end $fn$;
revoke execute on function public.fn_supplier_mailbox_mail_gets_its_owner(bigint, jsonb, boolean) from public, anon, authenticated;

-- 4. BACKFILL FROM WHAT GRAPH ALREADY RETURNED: the delivery reports already in inbound_messages
do $backfill$
declare r record;
begin
  for r in select i.id from public.inbound_messages i
            where (coalesce(i.raw->>'in_reply_to', '') || ' ' || coalesce(i.raw->>'references', '')) ~ 'qd-notif-[0-9]+\.'
            order by i.id
  loop
    perform public.fn_mail_bounce_marks_its_send(r.id);
  end loop;
end
$backfill$;
