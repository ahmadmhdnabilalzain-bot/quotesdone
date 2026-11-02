-- PROBE (pure, no DDL, aborted transaction) for every_reply_and_bounce_in_the_supplier_mailbox_has_an_owning_seat.sql.
-- Run after the definition, in the same rolled-back transaction while it is pending (scripts/lib/safe_replay.mjs
-- replaySql, as the check does) or alone once it is applied. It always ends in raise exception 'CHK<<json>>', so every
-- row it writes rolls back. Its leads are ZZ DEMO at @example.invalid, created here. One sender is the founder's own
-- Gmail, because fn_is_founder_own_inbox can only be satisfied by his real addresses: that row is an inbound message
-- that exists only inside this transaction, and nothing is sent. The count of real unowned rows is taken before and
-- after and must not move. On the definition BEFORE the fix it answers PROBE FAILED.
--
-- It replays the real order: resend_inbound INSERTS the message (z52 runs), then email_triage either answers it or
-- marks it triaged with ai_category 'no_auto_reply'. Step 1 asserts that NO message has an owner at insert, because
-- email_triage reads only unowned rows: an owner written then would silence its answer (g, h). Step 2 plays triage's
-- decline on a..f and i, as email_triage writes it, and asserts each owner:
--   a  a person who is no lead, to the supplier mailbox          -> sales_engineer + a live mailbox.supplier_reply handoff
--   b  an authenticated permanent bounce of our send to lead b   -> customer_support; suppressed; lead bounced; off the nudge list
--   c  an authenticated TEMPORARY bounce of our send to lead c   -> customer_support; NOT suppressed; lead still 'sent'
--   d  the founder's own inbox                                    -> it_engineer, no handoff
--   e  an out-of-office from a person who is no lead              -> sales_engineer, no handoff
--   f  a person writing to info@ (not the supplier mailbox)       -> untouched (owner stays null)
--   g  an INVITED lead's reply (triage answers it; not declined) -> no owner, so email_triage still answers it
--   h  a supplier's reply to suppliers@mail (triage answers it)  -> no owner, so email_triage still answers it
--   i  an UNAUTHENTICATED "postmaster" naming our send to lead i -> customer_support; NOT suppressed; lead still 'sent'
do $$
declare
  v_box text := (select value from public.app_secrets where key = 'invite_m365_mailbox');
  v_mail_box text := (select value from public.app_secrets where key = 'email_reply_supplier');
  b bigint; c bigint; g bigint; i_ bigint; nb bigint; nc bigint; ng bigint; ni bigint;
  ia bigint; ib bigint; ic bigint; id_ bigint; ie bigint; if_ bigint; ig bigint; ih bigint; ii bigint;
  v_real_before int; v_real_after int; fail text := ''; o jsonb; v_at_insert int;
  -- an invitation body the notifications guard accepts (the reply-"stop" line), as the outbox writes it
  v_body text := 'Hi ZZ DEMO team,' || chr(10) || chr(10) || 'Would your company like to receive requests when they come in?'
                 || chr(10) || chr(10) || 'If this isn''t relevant, reply "stop" and we won''t contact you again.';
  v_auth jsonb := '{"content_type": "multipart/report; report-type=delivery-status; boundary=x", "auto_submitted": "auto-replied", "sender_authenticated": true}';
begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  if coalesce(v_box, '') = '' or coalesce(v_mail_box, '') = '' then
    raise exception 'CHK<<%>>', jsonb_build_object('verdict', 'PROBE FAILED: a supplier mailbox secret is missing'); end if;
  select count(*) into v_real_before from public.inbound_messages
   where needs_review and replied_at is null and owner_role is null and created_at < now() - interval '24 hours';

  insert into public.leads (company_name, email, invited_at, invite_status) values
    ('ZZ DEMO - mailbox owner probe b (bounced)', 'zz-demo-mbx-b@example.invalid', now() - interval '4 days', 'sent') returning id into b;
  insert into public.leads (company_name, email, invited_at, invite_status) values
    ('ZZ DEMO - mailbox owner probe c (soft)',    'zz-demo-mbx-c@example.invalid', now() - interval '4 days', 'sent') returning id into c;
  insert into public.leads (company_name, email, invited_at, invite_status) values
    ('ZZ DEMO - mailbox owner probe g (answers)', 'zz-demo-mbx-g@example.invalid', now() - interval '4 days', 'sent') returning id into g;
  insert into public.leads (company_name, email, invited_at, invite_status) values
    ('ZZ DEMO - mailbox owner probe i (forged)',  'zz-demo-mbx-i@example.invalid', now() - interval '4 days', 'sent') returning id into i_;
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, status, created_at, sent_at, channel, lang)
  values ('supplier_invite', 'zz-demo-mbx-b@example.invalid', 'supplier', b, 'Quote requests for QuotesDone', v_body, 'sent',
          now() - interval '4 days', now() - interval '4 days', 'email', 'en') returning id into nb;
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, status, created_at, sent_at, channel, lang)
  values ('supplier_invite', 'zz-demo-mbx-c@example.invalid', 'supplier', c, 'Quote requests for QuotesDone', v_body, 'sent',
          now() - interval '4 days', now() - interval '4 days', 'email', 'en') returning id into nc;
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, status, created_at, sent_at, channel, lang)
  values ('supplier_invite', 'zz-demo-mbx-g@example.invalid', 'supplier', g, 'Quote requests for QuotesDone', v_body, 'sent',
          now() - interval '4 days', now() - interval '4 days', 'email', 'en') returning id into ng;
  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, status, created_at, sent_at, channel, lang)
  values ('supplier_invite', 'zz-demo-mbx-i@example.invalid', 'supplier', i_, 'Quote requests for QuotesDone', v_body, 'sent',
          now() - interval '4 days', now() - interval '4 days', 'email', 'en') returning id into ni;

  -- STEP 1: the messages arrive (resend_inbound's insert; z52 runs)
  insert into public.inbound_messages (from_email, to_email, subject, body, needs_review, matched_existing, raw)
  values ('ZZ DEMO Person <zz-demo-mbx-a@example.invalid>', v_box, 'Re: Registration',
          E'Definitely but later\r\n\r\n________________________________\r\nFrom: Ahmad\r\nWould you like to register',
          true, false, '{}'::jsonb) returning id into ia;
  insert into public.inbound_messages (from_email, to_email, subject, body, needs_review, matched_existing, raw)
  values ('mailer-daemon@googlemail.com', v_box, 'Undeliverable: Delivery Status Notification (Failure)',
          E'Address not found\r\nYour message wasn''t delivered to zz-demo-mbx-b@example.invalid because the address couldn''t be found. The email account that you tried to reach does not exist.',
          true, false, v_auth || jsonb_build_object('in_reply_to', '<qd-notif-' || nb || '.1793272615684@quotesdone.com>')) returning id into ib;
  insert into public.inbound_messages (from_email, to_email, subject, body, needs_review, matched_existing, raw)
  values ('mailer-daemon@googlemail.com', v_box, 'Delivery Status Notification (Delay)',
          E'Delivery incomplete\r\nThere was a temporary problem delivering your message to zz-demo-mbx-c@example.invalid. Gmail will retry for 47 more hours.',
          true, false, v_auth || jsonb_build_object('in_reply_to', '<qd-notif-' || nc || '.1793272615684@quotesdone.com>')) returning id into ic;
  insert into public.inbound_messages (from_email, to_email, subject, body, needs_review, matched_existing, raw)
  values ('ahmadmhdnabilalzain@gmail.com', v_box, 'Re: Quote requests for QuotesDone', 'All good', true, false, '{}'::jsonb)
  returning id into id_;
  insert into public.inbound_messages (from_email, to_email, subject, body, needs_review, matched_existing, raw)
  values ('zz-demo-mbx-e@example.invalid', v_box, 'Automatic reply: Quote requests for QuotesDone',
          'I am currently out of the office.', true, false, '{"auto_submitted": "auto-replied"}'::jsonb) returning id into ie;
  insert into public.inbound_messages (from_email, to_email, subject, body, needs_review, matched_existing, raw)
  values ('zz-demo-mbx-f@example.invalid', 'info@quotesdone.com', 'A question', 'Do you sell tiles?', true, false, '{}'::jsonb)
  returning id into if_;
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, needs_review, matched_existing, raw)
  values (g, 'zz-demo-mbx-g@example.invalid', v_box, 'Re: Quote requests for QuotesDone', 'Yes, we do tiling.', true, true, '{}'::jsonb)
  returning id into ig;
  insert into public.inbound_messages (from_email, to_email, subject, body, needs_review, matched_existing, raw)
  values ('zz-demo-mbx-h@example.invalid', v_mail_box, 'Re: Your quote request', 'Can I send the drawing by email?', true, false, '{}'::jsonb)
  returning id into ih;
  insert into public.inbound_messages (from_email, to_email, subject, body, needs_review, matched_existing, raw)
  values ('postmaster@zz-demo-forged.example.invalid', v_box, 'Undeliverable: Quote requests for QuotesDone',
          E'Address not found\r\nYour message to zz-demo-mbx-i@example.invalid could not be delivered: the account does not exist (5.1.1).',
          true, false, jsonb_build_object('content_type', 'multipart/report', 'sender_authenticated', false,
                                          'in_reply_to', '<qd-notif-' || ni || '.1793272615684@quotesdone.com>')) returning id into ii;

  select count(*) into v_at_insert from public.inbound_messages where id in (ia, ib, ic, id_, ie, if_, ig, ih, ii) and owner_role is not null;
  if v_at_insert > 0 then fail := fail || v_at_insert || ' message(s) owned at insert: email_triage would never read them; '; end if;

  -- STEP 2: email_triage declines a..f and i exactly as it writes it; g and h it answers, so they are not declined
  update public.inbound_messages set ai_category = 'no_auto_reply', ai_summary = 'Not answered automatically: probe',
         triaged_at = now() where id in (ia, ib, ic, id_, ie, if_, ii);

  select jsonb_object_agg(x.k, x.o) into o from (
    select 'a' k, owner_role o from public.inbound_messages where id = ia union all
    select 'b', owner_role from public.inbound_messages where id = ib union all
    select 'c', owner_role from public.inbound_messages where id = ic union all
    select 'd', owner_role from public.inbound_messages where id = id_ union all
    select 'e', owner_role from public.inbound_messages where id = ie union all
    select 'f', owner_role from public.inbound_messages where id = if_ union all
    select 'g', owner_role from public.inbound_messages where id = ig union all
    select 'h', owner_role from public.inbound_messages where id = ih union all
    select 'i', owner_role from public.inbound_messages where id = ii) x;

  if o->>'a' is distinct from 'sales_engineer' then fail := fail || 'a (a person, no lead) is not the sales engineer''s; '; end if;
  if not exists (select 1 from public.agent_actions where kind = 'handoff' and agent = 'sales_engineer'
                  and target_id = 'mailbox.supplier_reply:' || ia and status <> 'failed'
                  and detail->>'reply_text' = 'Definitely but later') then
    fail := fail || 'a has no live mailbox.supplier_reply handoff carrying the words above the quote; '; end if;
  if o->>'b' is distinct from 'customer_support' then fail := fail || 'b (a permanent bounce) is not customer_support''s; '; end if;
  if not exists (select 1 from public.email_suppressions where email = 'zz-demo-mbx-b@example.invalid') then fail := fail || 'b''s address is not suppressed; '; end if;
  if (select invite_status from public.leads where id = b) is distinct from 'bounced' then fail := fail || 'lead b is not marked bounced; '; end if;
  if exists (select 1 from public.fn_supplier_invite_nudges_due(now(), true) x where x.lead_id = b) then fail := fail || 'lead b is still due a nudge; '; end if;
  if o->>'c' is distinct from 'customer_support' then fail := fail || 'c (a temporary bounce) is not customer_support''s; '; end if;
  if exists (select 1 from public.email_suppressions where email = 'zz-demo-mbx-c@example.invalid') then fail := fail || 'a temporary bounce suppressed c; '; end if;
  if (select invite_status from public.leads where id = c) is distinct from 'sent' then fail := fail || 'a temporary bounce marked lead c; '; end if;
  if o->>'d' is distinct from 'it_engineer' then fail := fail || 'd (the founder''s own inbox) is not the it_engineer''s; '; end if;
  if exists (select 1 from public.agent_actions where kind = 'handoff' and target_id = 'mailbox.supplier_reply:' || id_) then fail := fail || 'd was handed to a supplier seat; '; end if;
  if o->>'e' is distinct from 'sales_engineer' then fail := fail || 'e (an out-of-office) is not the sales engineer''s; '; end if;
  if exists (select 1 from public.agent_actions where kind = 'handoff' and target_id = 'mailbox.supplier_reply:' || ie) then fail := fail || 'an out-of-office filed a handoff; '; end if;
  if o->>'f' is not null then fail := fail || 'f (not the supplier mailbox) was taken: ' || (o->>'f') || '; '; end if;
  if o->>'g' is not null then fail := fail || 'g (an invited lead''s reply) got an owner: email_triage would not answer it; '; end if;
  if o->>'h' is not null then fail := fail || 'h (a reply to suppliers@mail) got an owner: email_triage would not answer it; '; end if;
  if o->>'i' is distinct from 'customer_support' then fail := fail || 'i (an unauthenticated bounce) is not customer_support''s; '; end if;
  if exists (select 1 from public.email_suppressions where email = 'zz-demo-mbx-i@example.invalid') then fail := fail || 'a forged bounce suppressed a real-looking address; '; end if;
  if (select invite_status from public.leads where id = i_) is distinct from 'sent' then fail := fail || 'a forged bounce marked lead i; '; end if;
  if exists (select 1 from public.inbound_messages where id in (ia, ib, ic, id_, ie, ig, ih, ii) and (replied_at is not null or not needs_review)) then
    fail := fail || 'a message was closed; '; end if;

  select count(*) into v_real_after from public.inbound_messages
   where needs_review and replied_at is null and owner_role is null and created_at < now() - interval '24 hours';
  if v_real_after <> v_real_before then fail := fail || 'real rows moved (' || v_real_before || ' -> ' || v_real_after || '); '; end if;

  raise exception 'CHK<<%>>', jsonb_build_object(
    'verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end, 'owners', o, 'owned_at_insert', v_at_insert);
end $$;
