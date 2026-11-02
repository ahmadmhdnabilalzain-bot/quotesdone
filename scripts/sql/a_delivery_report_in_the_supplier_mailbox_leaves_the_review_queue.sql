-- A DELIVERY REPORT IN THE SUPPLIER MAILBOX LEAVES THE REVIEW QUEUE ONCE ITS OWNER HAS ACTED (2 Nov 2026).
-- Assigned: customer_support (the email channel's delivery results).
--
-- MEASURED on production (htdblwldjkcgjvmqkbeh), 2 Nov 2026 ~06:40Z, ledger 1446 (every company mailbox reaches the agents):
-- inbound_messages 1611, 1612, 1613, 1614, 1617, 1618 are Exchange delivery reports (MicrosoftExchange<hex>@...onmicrosoft.com)
-- in supplier@quotesdone.com, owner_role customer_support, and all six read needs_review = true with no reply: the only six
-- needs_review rows in the table. Their addresses were suppressed (resend_inbound's mailbox_bounce path and by hand), so there
-- was nothing left to answer, but fn_supplier_mailbox_mail_gets_its_owner stamped the owner and never cleared the flag, so
-- the founder's Inbox kept six finished reports. declinedRowFields (customer_mail.ts) already does this for every other
-- Microsoft 365 mailbox; supplier@ was left out on purpose for a PERSON's reply, never for a machine's report.
--
-- The routine is the live body (md5 e15228c99cccbbb9d1abf38d6028d015, 7938 characters, read 2 Nov) with ONE change: the bounce
-- branch also sets needs_review = false. Nothing else in it moves. A person's reply and the founder's seed reply keep their flag.
-- The six rows are cleared here by id. Prevented by: scripts/checks/a_delivery_report_in_the_supplier_mailbox_leaves_the_review_queue.test.mjs.

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
    elsif v_to ~ '@(mail\.)?quotesdone\.(com|ae)$' or public.fn_is_founder_own_inbox(v_to) then
      v_why := 'never suppressed: our own or the founder''s address';
    elsif coalesce(m.raw->>'sender_authenticated', 'false') <> 'true' then
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
    -- a delivery report has nothing to answer: customer_support owns it and the agent_actions row below is the verdict, so
    -- it leaves the review queue (a needs_review row is what reaches the founder's Inbox)
    update public.inbound_messages set owner_role = v_owner, needs_review = false where id = m.id;
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

-- the six reports above: owned by customer_support, a delivery report, not answered
update public.inbound_messages set needs_review = false
 where id in (1611, 1612, 1613, 1614, 1617, 1618) and owner_role = 'customer_support' and needs_review and replied_at is null
   and public.fn_inbound_is_bounce(from_email, subject, raw);
