-- EVERY REPLY AND BOUNCE IN THE SUPPLIER MAILBOX HAS AN OWNING SEAT (1 Nov 2026).
-- Assigned: sales_engineer (a person's reply to the supplier mailbox), customer_support (a bounce: the email channel's
-- delivery result), it_engineer (the founder's own seed-test inboxes answering a seed).
--
-- MEASURED on production (htdblwldjkcgjvmqkbeh), 1 Nov 2026 18:05Z: scripts/checks/receipts_never_wait_on_the_founder.test.mjs
-- failed "inbound_messages: no needs_review row older than 24h without an owner role" on five rows, all addressed to
-- supplier@quotesdone.com (app_secrets.invite_m365_mailbox), all lead_id null:
--   653 bookings@djzaino.com, 654 ahmadmhdnabilalzain@gmail.com, 655 fati.labib@icloud.com - "Re: Quote requests for
--       QuotesDone", 27 Oct 15:31-15:46Z, each "All good". In-Reply-To names notifications 112176/112174/112182, type
--       supplier_invite_seed (the warm-up seed of 27 Oct). All three are in fn_is_founder_own_inbox: the founder
--       answering his own seed. None is a lead.
--   1483 ahmad@666realestate.ae - "Re: Registration", 28 Oct 13:46Z, "Definitely but later": a reply to a mail sent by
--       hand from Outlook. Not a lead.
--   1484 mailer-daemon@googlemail.com - "Undeliverable: Delivery Status Notification (Failure)", 29 Oct 11:31Z,
--       multipart/report, auto_submitted auto-replied: "Address not found ... sales@mayyashomes.com". In-Reply-To names
--       notification 117557, the supplier_invite to lead 1887 (Mayyas Interio Trading LLC).
-- At 18:37Z the five read owner_role 'sales_engineer', written by hand outside any routine (no routine in the database
-- writes that value to inbound_messages; read 1 Nov), and nothing reads owner_role 'sales_engineer' on inbound mail, so
-- the rows had left the founder's inbox without reaching any seat's queue.
--
-- WHY THEY HAD NO OWNER. The only path that takes a reply to the supplier mailbox is z52 ->
-- fn_marketing_files_invite_reply, and it hands over only a reply from an INVITED LEAD. Every other exit returned a
-- reason and left the row as it came: 'the sender is no lead' (653, 654, 655, 1483), 'an automatic reply' (1484, rightly
-- not an invite.reply), 'a stop reply', 'an empty reply', 'the lead already has its company page', 'the lead was never
-- invited'. And no path read a bounce that arrives as MAIL: resend_webhook suppresses an address and marks its lead
-- 'bounced' for a Resend send, but an invitation sent from the Microsoft 365 lane (send_outbox m365_lane) bounces back
-- into the mailbox. So lead 1887 still read invite_status 'queued', had no email_suppressions row, and was on
-- fn_supplier_invite_nudges_due for its day-3 nudge (read 1 Nov 18:5xZ: step 1), due to leave on the next open window,
-- Monday 2 Nov 09:00 Dubai, to an address Gmail says does not exist.
--
-- WHAT THIS CHANGES
--   1. fn_inbound_is_bounce(from, subject, raw): a delivery failure (mailer-daemon/postmaster, a multipart/report, or a
--      machine sender with an "Undeliverable"/"Delivery Status Notification" subject).
--   2. fn_supplier_mailbox_mail_gets_its_owner(id, filed, reassign): every message to the supplier mailbox leaves with
--      an owning seat, and the seat acts:
--        - a bounce -> customer_support. When its In-Reply-To names our notification and the body says the address
--          does not exist (a permanent failure that names that recipient), the address is suppressed (hard_bounce) and
--          its lead marked 'bounced' exactly as resend_webhook does, so no nudge goes to it again; the record is an
--          agent_actions row. A bounce it cannot tie to a send, or a temporary one, is owned and recorded, not acted on.
--        - the founder's own inbox (fn_is_founder_own_inbox) -> it_engineer, which owns the seed tests (ledger 1312/
--          1344); recorded, no handoff: a supplier seat must never answer the founder as a supplier.
--        - an invited lead's reply that fn_marketing_files_invite_reply handed over -> sales_engineer (its invite.reply).
--        - an automatic reply, a stop, an empty reply -> sales_engineer, nothing to answer.
--        - any other person -> sales_engineer, with a mailbox.supplier_reply handoff carrying the words above the quote.
--   3. trg_invite_reply_reaches_sales_engineer (z52) calls it after the invite-reply filer, each in its own guard so a
--      failure never costs the mail it rides on.
--   4. The five rows above are handed to those owners by id. None is closed: needs_review and replied_at are untouched.
--
-- CREATE OR REPLACE of trg_invite_reply_reaches_sales_engineer keeps its ACL; the new routines are created here and
-- revoked here (CREATE grants EXECUTE to PUBLIC).
-- Prevented by: scripts/checks/every_reply_and_bounce_in_the_supplier_mailbox_has_an_owning_seat.test.mjs (offline, and
-- production aborted through the _probe file, which answers PROBE FAILED on the definition before this file).

create or replace function public.fn_inbound_is_bounce(p_from text, p_subject text, p_raw jsonb)
returns boolean
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(
       lower(coalesce(p_from, '')) ~ '(^|[<"[:space:]])(mailer[-_]?daemon|postmaster)@'
    or lower(coalesce(p_raw->>'content_type', '')) = 'multipart/report'
    or (public.fn_is_machine_sender(p_from)
        and coalesce(p_subject, '') ~* '(undeliverable|delivery status notification|mail delivery (failed|subsystem)|returned mail|failure notice|undelivered mail|delivery has failed)'),
    false)
$fn$;
revoke execute on function public.fn_inbound_is_bounce(text, text, jsonb) from public, anon, authenticated;

create or replace function public.fn_sales_engineer_takes_supplier_mailbox_reply(p_id bigint)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  -- The sales engineer reads the message and answers it in its thread; the handoff waits in its queue with the words.
  return jsonb_build_object(
    'waiting', 'sales_engineer: answer ' || coalesce(a.detail->>'from_email', '?') || ' in the thread of inbound message #'
               || coalesce(a.detail->>'inbound_message_id', '?'),
    'inbound_message_id', a.detail->'inbound_message_id', 'reply_text', a.detail->'reply_text');
end $fn$;
revoke execute on function public.fn_sales_engineer_takes_supplier_mailbox_reply(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file) values
  ('mailbox.supplier_reply', 'marketing', 'sales_engineer',
   'a person who is not an invited lead wrote to the supplier mailbox (a reply to a mail sent by hand, a forwarded invitation, a lead whose page is already claimed): read it and answer it in its thread',
   'fn_sales_engineer_takes_supplier_mailbox_reply', interval '24 hours', false,
   'scripts/sql/every_reply_and_bounce_in_the_supplier_mailbox_has_an_owning_seat.sql')
on conflict do nothing;

create or replace function public.fn_supplier_mailbox_mail_gets_its_owner(p_inbound_id bigint, p_filed jsonb default null, p_reassign boolean default false)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare m public.inbound_messages; n public.notifications;
  v_from text; v_boxes text[]; v_owner text; v_why text; v_reply text; v_hid bigint; v_nid bigint; v_to text;
  v_lead bigint; v_acted boolean := false; v_body text;
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
    v_body := left(coalesce(m.body, ''), 4000);
    if v_to is null or v_to = '' then
      v_why := 'a bounce that names no send of ours';
    elsif position(v_to in lower(v_body)) = 0 then
      v_why := 'the bounce does not name the address it was sent to';
    elsif v_body ~* '(temporar|try again later|will retry|delayed|mailbox (is )?full|over quota)'
          or v_body !~* '(address not found|does ?n[o''’]t exist|no such (user|recipient|mailbox)|user unknown|unknown (user|recipient)|recipient address rejected|mailbox (unavailable|not found)|invalid (recipient|address|mailbox)|could ?n[o''’]t be found|could not be found|5\.1\.[0-9]+)' then
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

create or replace function public.trg_invite_reply_reaches_sales_engineer()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_filed jsonb;
begin
  -- never costs the mail it rides on: a failure is a warning, the inbound row is kept
  begin
    v_filed := public.fn_marketing_files_invite_reply(new.id);
  exception when others then
    raise warning 'trg_invite_reply_reaches_sales_engineer: inbound_messages % not handed to the sales engineer: %', new.id, sqlerrm;
  end;
  -- 1 Nov 2026: and whatever the filer decided, the message leaves with an owning seat
  begin
    perform public.fn_supplier_mailbox_mail_gets_its_owner(new.id, coalesce(v_filed, '{"due": false, "reason": "the filer failed"}'::jsonb));
  exception when others then
    raise warning 'trg_invite_reply_reaches_sales_engineer: inbound_messages % got no owning seat: %', new.id, sqlerrm;
  end;
  return null;
end $fn$;

-- the five rows of 1 Nov 2026, handed to their owners by id (653-655 it_engineer, 1483 sales_engineer, 1484
-- customer_support). Nothing is closed.
select public.fn_supplier_mailbox_mail_gets_its_owner(x.id, null, true)
  from (values (653::bigint), (654), (655), (1483), (1484)) x(id) order by x.id;

-- verdict
select case
  when not exists (select 1 from pg_trigger where tgname = 'z52_invite_reply_reaches_sales_engineer')
    then 'PROBE FAILED: the z52 trigger is missing'
  when not exists (select 1 from public.seat_handoff_kind where type = 'mailbox.supplier_reply' and to_seat = 'sales_engineer')
    then 'PROBE FAILED: mailbox.supplier_reply is not registered'
  when (select string_agg(id || '=' || coalesce(owner_role, 'null'), ',' order by id) from public.inbound_messages where id in (653, 654, 655, 1483, 1484))
       is distinct from '653=it_engineer,654=it_engineer,655=it_engineer,1483=sales_engineer,1484=customer_support'
    then 'PROBE FAILED: the five rows are not with their owners: ' || (select string_agg(id || '=' || coalesce(owner_role, 'null'), ',' order by id) from public.inbound_messages where id in (653, 654, 655, 1483, 1484))
  when exists (select 1 from public.inbound_messages where id in (653, 654, 655, 1483, 1484) and (replied_at is not null or not needs_review))
    then 'PROBE FAILED: a row was closed'
  when not exists (select 1 from public.agent_actions where kind = 'handoff' and agent = 'sales_engineer' and target_id = 'mailbox.supplier_reply:1483' and status <> 'failed')
    then 'PROBE FAILED: 1483 has no live handoff to the sales engineer'
  when not exists (select 1 from public.email_suppressions where email = 'sales@mayyashomes.com')
    then 'PROBE FAILED: the bounced address of lead 1887 is not suppressed'
  when exists (select 1 from public.fn_supplier_invite_nudges_due(now() + interval '1 day', false) where lead_id = 1887)
    then 'PROBE FAILED: lead 1887 is still due a nudge to the address that bounced'
  else 'PROBE OK' end as verdict;
