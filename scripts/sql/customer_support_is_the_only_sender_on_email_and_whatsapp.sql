-- CUSTOMER SUPPORT IS THE ONLY SENDER ON EMAIL AND WHATSAPP, AND READS THE WHOLE CASE FIRST.
--
-- Assigned: customer_support (the seat whose wiring this is), carried out for the ceo.
--
-- The founder, 14 Sep 2026, verbatim: "the only agent who uses the whatsapp and email is the customer
-- support agent. so he should be always up to date with that is going on."
--
-- MEASURED BEFORE WRITING (14 Sep 2026, production htdblwldjkcgjvmqkbeh):
--
--   The outbox. public.notifications is the one queue both dispatchers drain: send_outbox (email,
--   Resend) and send_whatsapp (Twilio) select from it; email_cron and resilience_ping call send_outbox.
--   All four are function_owner = customer_support. The table had NO column saying who asked for a
--   message or who sent it: 41 rows, 6 types, every one silent about its seat.
--
--   Who writes to it. 26 routines insert into notifications (prosrc scan) and 11 edge functions do
--   (source scan). By the seat whose work each message is:
--     sales_engineer  invoice_ready, quote_accepted, reveal_receipt, new_inquiry, new_quote, new_message,
--                     clarification_requested, job_awarded_other, rfq_addendum, rfq_no_supplier,
--                     supplier_registered, registration_received, supplier_ack, supplier_invites,
--                     invite_paused_bounce, quote_coaching, cancel_warning, inquiry_edit_staled_quotes,
--                     licence_renewal, doc_final_notice, supplier_doc_expiry, doc_restored, doc_suspended,
--                     supplier_doc_applied, customer_success, reveal_no_response_notice,
--                     supplier_no_response_chase (the refund ladder's inner loop: sales asks support to chase)
--     accountant      refund_issued, refund_action_failed, dues_paid, registration_paid, subscription_due,
--                     subscription_billing_summary, expense_logged, accountant_weekly_report,
--                     accountant_spend_report
--     ceo             founder_brief (fn_founder_brief, fn_ceo_daily_digest_submit)
--     it_engineer     it_engineer_handover, smoke_alert, ai_quality_alert, agent_escalation, wa_templates_ready
--     customer_support rating_request, doc_received, inbound_reply, contact_message, support_notification bridge
--     founder_alert   fn_notify_founder: the seat is founder_mail_policy.owner_role for the kind
--
--   Around it. Five edge functions reach a provider without the outbox:
--     contact_submit  emailed the notify inbox straight through Resend      -> MOVED to the outbox (this PR)
--     login_otp, kyc  sign-in / email-confirmation CODES through Resend     -> platform OTP service, documented
--     send_sms        SMS sign-in codes through Twilio                      -> platform OTP service, documented
--     wa_inbound      replies inside the 24h window through Twilio          -> IS customer_support's runtime
--   No routine calls a provider directly: the 7 that reach a sender call send_outbox or send_whatsapp.
--
--   function_owner. Every channel slug was already customer_support except resend_webhook and
--   unsubscribe ('website': the email channel's delivery feedback and its RFC 8058 opt-out), and
--   email_cron carried moves_to='it' from 8 Sep. Those move now; the OTP slugs stay 'website'.
--
-- WHAT THIS FILE DOES
--   1. notifications.requested_by (the seat that asked) and notifications.sender (who sends it).
--   2. CHECK notifications_sender_is_customer_support: sender must be customer_support, or the
--      documented platform OTP service for an OTP type. Nothing else can be written.
--   3. a05_notifications_sender_of_record: fills requested_by from fn_channel_requester when a writer
--      did not name it, and refuses a requested_by that is not an active seat or 'platform'.
--      It fires BEFORE a10_notifications_founder_mail_policy and changes nothing that policy decides.
--   4. founder_mail_policy learns 'contact_message' (allowed, as the direct email always was).
--   5. fn_contact_timeline(p_contact): the per-contact case timeline customer_support reads before it
--      answers, deterministic, service-role only.
--
--   node scripts/apply_sql.mjs scripts/sql/customer_support_is_the_only_sender_on_email_and_whatsapp.sql --apply --ddl

begin;

-- 1. Who asked, and who sends. -------------------------------------------------------------------
alter table public.notifications add column if not exists requested_by text;
alter table public.notifications add column if not exists sender text not null default 'customer_support';
comment on column public.notifications.requested_by is
  'The seat whose work this message is (an active org_role, or ''platform''). Filled by a05_notifications_sender_of_record when the writer does not name it.';
comment on column public.notifications.sender is
  'The sender of record. Always customer_support (founder, 14 Sep 2026), except the documented platform OTP service. Enforced by notifications_sender_is_customer_support.';

-- 2. The guard. ----------------------------------------------------------------------------------
alter table public.notifications drop constraint if exists notifications_sender_is_customer_support;
alter table public.notifications add constraint notifications_sender_is_customer_support
  check (sender = 'customer_support'
         or (sender = 'platform_otp' and type in ('login_otp', 'mobile_otp', 'voice_otp', 'email_confirmation_code')));

-- 3. Which seat asked. ---------------------------------------------------------------------------
create or replace function public.fn_channel_requester(p_type text, p_kind text)
returns text
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $fn$
declare v text;
begin
  v := case
    when p_type in ('invoice_ready','quote_accepted','reveal_receipt','new_inquiry','new_quote','new_message',
                    'clarification_requested','job_awarded_other','rfq_addendum','rfq_no_supplier',
                    'supplier_registered','registration_received','supplier_ack','supplier_invites',
                    'invite_paused_bounce','quote_coaching','cancel_warning','inquiry_edit_staled_quotes',
                    'licence_renewal','doc_final_notice','supplier_doc_expiry','doc_restored','doc_suspended',
                    'supplier_doc_applied','customer_success','reveal_no_response_notice',
                    'supplier_no_response_chase') then 'sales_engineer'
    when p_type in ('refund_issued','refund_action_failed','dues_paid','registration_paid','subscription_due',
                    'subscription_billing_summary','expense_logged','accountant_weekly_report',
                    'accountant_spend_report') then 'accountant'
    when p_type in ('founder_brief') then 'ceo'
    when p_type in ('it_engineer_handover','smoke_alert','ai_quality_alert','agent_escalation',
                    'wa_templates_ready') then 'it_engineer'
    when p_type in ('rating_request','doc_received','inbound_reply','contact_message') then 'customer_support'
    when p_type in ('login_otp','mobile_otp','voice_otp','email_confirmation_code') then 'platform'
  end;
  -- A founder notification names its seat in founder_mail_policy, the register that already governs it.
  if v is null then
    select f.owner_role into v from public.founder_mail_policy f
     where f.kind = coalesce(nullif(btrim(p_kind), ''), p_type);
  end if;
  if v = 'platform' then return v; end if;
  -- A seat that is not active today cannot be the requester; the channel's own seat stands in.
  if v is null or not exists (select 1 from public.org_role r where r.role_id = v and r.status = 'active') then
    v := 'customer_support';
  end if;
  return v;
end $fn$;
revoke execute on function public.fn_channel_requester(text, text) from public, anon, authenticated;

create or replace function public.fn_notifications_sender_of_record()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  NEW.sender := coalesce(nullif(btrim(NEW.sender), ''), 'customer_support');
  NEW.requested_by := coalesce(nullif(btrim(NEW.requested_by), ''), public.fn_channel_requester(NEW.type, NEW.kind));
  if NEW.requested_by <> 'platform'
     and not exists (select 1 from public.org_role r where r.role_id = NEW.requested_by and r.status = 'active') then
    raise exception 'notifications.requested_by % is not an active seat: a delivery request must name the seat that asked (customer_support sends it)', NEW.requested_by
      using errcode = 'check_violation';
  end if;
  return NEW;
end $fn$;
revoke execute on function public.fn_notifications_sender_of_record() from public, anon, authenticated;

drop trigger if exists a05_notifications_sender_of_record on public.notifications;
create trigger a05_notifications_sender_of_record
  before insert or update of sender, requested_by on public.notifications
  for each row execute function public.fn_notifications_sender_of_record();

-- Backfill: fires only a05 (z51 reacts to status, which this does not touch).
update public.notifications set requested_by = public.fn_channel_requester(type, kind) where requested_by is null;

-- 4. The contact form's notify keeps reaching him, now through the outbox. ----------------------
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role, updated_at)
values ('contact_message', true,
        'A visitor wrote through the contact form. contact_submit emailed this to the notify inbox directly from July 2026; on 14 Sep 2026 it moved into the outbox so customer_support is the sender of record ("the only agent who uses the whatsapp and email is the customer support agent"). Allowed, so delivery is unchanged.',
        'customer_support', now())
on conflict (kind) do nothing;

-- 5. The channels' owners. -----------------------------------------------------------------------
update public.function_owner set owner = 'customer_support',
       note = case function_slug
         when 'resend_webhook' then 'Delivery, bounce and complaint events for the mail customer_support sends. The email channel''s feedback belongs to the only seat on the channel (founder, 14 Sep 2026).'
         when 'unsubscribe'    then 'One-click unsubscribe (RFC 8058) for the mail customer_support sends. The recipient''s opt-out belongs to the only seat on the channel (founder, 14 Sep 2026).'
       end
 where function_slug in ('resend_webhook', 'unsubscribe');
update public.function_owner
   set moves_to = null, moves_to_note = null,   -- function_owner_moves_to_ck: the two are null together
       note = 'Runs the outbox flush on a schedule and watches domain verification. The 8 Sep plan to move it to IT was superseded on 14 Sep 2026: "the only agent who uses the whatsapp and email is the customer support agent." email_cron dispatches the outbox, so it is the email channel itself and stays customer_support''s.'
 where function_slug = 'email_cron';

-- 6. The timeline customer_support reads before it composes or answers. ------------------------
create or replace function public.fn_contact_timeline(p_contact text, p_limit integer default 60)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_raw text := btrim(coalesce(p_contact, ''));
  v_email text; v_tail text;
  v_cust uuid[]; v_lead bigint[]; v_inq uuid[]; v_txn uuid[]; v_ref bigint[];
  v_events jsonb; v_counts jsonb;
begin
  v_raw := regexp_replace(v_raw, '^whatsapp:', '', 'i');
  if position('@' in v_raw) > 0 then
    v_email := lower(v_raw);
  elsif length(regexp_replace(v_raw, '[^0-9]', '', 'g')) >= 7 then
    v_tail := right(regexp_replace(v_raw, '[^0-9]', '', 'g'), 9);   -- +9715..., 05..., 5...
  else
    return jsonb_build_object('contact', v_raw, 'known', false, 'event_count', 0, 'events', '[]'::jsonb);
  end if;

  select coalesce(array_agg(c.id), '{}') into v_cust from public.customers c
   where (v_email is not null and lower(c.email) = v_email)
      or (v_tail is not null and right(regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g'), 9) = v_tail);
  select coalesce(array_agg(l.id), '{}') into v_lead from public.leads l
   where (v_email is not null and (lower(l.email) = v_email or lower(l.claimed_by) = v_email))
      or (v_tail is not null and v_tail in (right(regexp_replace(coalesce(l.phone_e164, ''), '[^0-9]', '', 'g'), 9),
                                            right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 9),
                                            right(regexp_replace(coalesce(l.whatsapp, ''), '[^0-9]', '', 'g'), 9)));
  select coalesce(array_agg(i.id), '{}') into v_inq from public.inquiries i where i.customer_id = any (v_cust);
  select coalesce(array_agg(t.id), '{}') into v_txn from public.transactions t
   where t.customer_id = any (v_cust) or t.supplier_id = any (v_lead);
  select coalesce(array_agg(r.id), '{}') into v_ref from public.refunds r
   where r.customer_id = any (v_cust) or r.supplier_lead_id = any (v_lead) or r.transaction_id = any (v_txn);

  with ev(at, kind, channel, direction, seat, ref, summary) as (
    -- what they asked for
    select i.created_at, 'request', 'portal', 'in', 'sales_engineer', i.id::text,
           coalesce(i.status, '') || ': ' || left(coalesce(i.summary_masked, i.summary, i.category, ''), 140)
      from public.inquiries i where i.id = any (v_inq)
    -- quotes on their requests: state only, never a supplier or an amount (the pre-reveal rule)
    union all
    select q.created_at, 'quote', 'portal', 'in', 'sales_engineer', q.id::text,
           case when exists (select 1 from public.transactions t where t.quote_id = q.id and t.revealed_at is not null)
                then 'released (revealed)' else 'held (' || coalesce(q.status, 'received') || ')' end
      from public.quotes q where q.inquiry_id = any (v_inq)
    -- quotes they submitted, when the contact is a supplier
    union all
    select q.created_at, 'quote_submitted', 'portal', 'out', 'sales_engineer', q.id::text, coalesce(q.status, 'submitted')
      from public.quotes q where q.supplier_id = any (v_lead)
    -- reveals and what was paid
    union all
    select t.revealed_at, 'reveal', 'portal', 'out', 'accountant', t.id::text, 'fee ' || coalesce(t.fee_status, 'unknown')
      from public.transactions t where t.id = any (v_txn) and t.revealed_at is not null
    union all
    select ri.created_at, 'invoice', 'portal', 'out', 'accountant', ri.invoice_no, 'reveal invoice issued'
      from public.reveal_invoices ri where ri.transaction_id = any (v_txn)
    -- refunds, and the CEO's decision on each (the refund loop)
    union all
    select coalesce(r.updated_at, r.created_at), 'refund', 'portal', 'out', 'accountant', r.id::text,
           coalesce(r.status, '') || coalesce(' — ' || r.reason_code, '')
      from public.refunds r where r.id = any (v_ref)
    union all
    select coalesce(rc.updated_at, rc.created_at), 'refund_case', 'internal', 'internal', 'accountant', rc.case_id::text,
           coalesce(rc.state, '') || coalesce(' — ' || rc.decision, '')
      from public.refund_case rc where rc.refund_id = any (v_ref)
    union all
    select a.decided_at, 'ceo_decision', 'internal', 'internal', 'ceo', a.decision_id::text,
           coalesce(a.subject_kind, '') || ': ' || coalesce(a.decision, '')
      from public.ceo_approval a where a.subject_kind ilike 'refund%' and a.subject_id = any (v_ref::text[])
    -- support cases
    union all
    select coalesce(s.last_activity_at, s.opened_at), 'support_case', 'internal', 'internal',
           coalesce(s.owner_role_id, 'customer_support'), s.case_ref, coalesce(s.state, '') || ': ' || left(coalesce(s.subject, ''), 120)
      from public.support_case s
     where (s.party_kind = 'customer' and s.party_id = any (v_cust::text[]))
        or (s.party_kind = 'supplier' and s.party_id = any (v_lead::text[]))
    -- every message the company sent them, and the seat that asked for it
    union all
    select n.created_at, 'message', coalesce(n.channel, 'email'), 'out', coalesce(n.requested_by, 'customer_support'),
           n.id::text, coalesce(n.status, 'queued') || ': ' || left(coalesce(n.subject, n.type, ''), 140)
      from public.notifications n
     where (v_email is not null and lower(n.to_email) = v_email)
        or (v_tail is not null and right(regexp_replace(coalesce(n.to_phone, ''), '[^0-9]', '', 'g'), 9) = v_tail)
        or n.lead_id = any (v_lead) or n.inquiry_id = any (v_inq)
    -- every message they sent the company
    union all
    select m.created_at, 'message', 'email', 'in', 'customer_support', m.id::text, left(coalesce(m.subject, ''), 140)
      from public.inbound_messages m
     where (v_email is not null and lower(m.from_email) = v_email) or m.lead_id = any (v_lead)
    union all
    select w.at, 'message', 'whatsapp', w.direction, 'customer_support', w.id::text, left(coalesce(w.transcript, w.body, ''), 140)
      from public.wa_turn w join public.wa_conversation c on c.id = w.conversation_id
     where (v_tail is not null and right(regexp_replace(coalesce(c.phone_e164, ''), '[^0-9]', '', 'g'), 9) = v_tail)
        or (c.party_kind = 'customer' and c.party_id = any (v_cust::text[]))
        or (c.party_kind = 'supplier' and c.party_id = any (v_lead::text[]))
    union all
    select pm.created_at, 'message', 'portal_chat', case when pm.customer_id = any (v_cust) and pm.sender = 'customer' then 'in' else 'out' end,
           'sales_engineer', pm.id::text, left(coalesce(pm.redacted_body, ''), 140)
      from public.messages pm where pm.customer_id = any (v_cust) or pm.supplier_id = any (v_lead)
    union all
    select cm.created_at, 'message', 'contact_form', 'in', 'customer_support', cm.id::text, left(coalesce(cm.message, ''), 140)
      from public.contact_messages cm
     where (v_email is not null and lower(cm.email) = v_email)
        or (v_tail is not null and right(regexp_replace(coalesce(cm.phone, ''), '[^0-9]', '', 'g'), 9) = v_tail)
  )
  select coalesce(jsonb_agg(jsonb_build_object('at', e.at, 'kind', e.kind, 'channel', e.channel, 'direction', e.direction,
                                               'seat', e.seat, 'ref', e.ref, 'summary', e.summary) order by e.at desc), '[]'::jsonb)
    into v_events
    from (select * from ev where at is not null order by at desc limit greatest(1, least(coalesce(p_limit, 60), 500))) e;

  select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) into v_counts
    from (select x ->> 'kind' k, count(*) n from jsonb_array_elements(v_events) x group by 1) z;

  return jsonb_build_object(
    'contact', coalesce(v_email, v_tail),
    'known', cardinality(v_cust) + cardinality(v_lead) > 0,
    'customer_ids', to_jsonb(v_cust), 'supplier_lead_ids', to_jsonb(v_lead),
    'event_count', jsonb_array_length(v_events), 'counts', v_counts,
    'events', v_events,
    'assembled_by', 'fn_contact_timeline (deterministic; no model)');
end $fn$;
revoke execute on function public.fn_contact_timeline(text, integer) from public, anon, authenticated;

-- His words, in the register the moment they are acted on.
insert into public.founder_instruction (said_at, instruction, subject, status, evidence)
select '2026-09-14T00:00:00Z',
       'the only agent who uses the whatsapp and email is the customer support agent. so he should be always up to date with that is going on.',
       'customer support is the only sender on email and whatsapp',
       'closed',
       'scripts/sql/customer_support_is_the_only_sender_on_email_and_whatsapp.sql; scripts/checks/customer_support_is_the_only_sender.test.mjs'
 where not exists (select 1 from public.founder_instruction
                    where instruction like 'the only agent who uses the whatsapp and email is the customer support agent%');

-- 7. Proof, in this transaction. The file defines things, so every probe runs in a sub-block that
--    rolls itself back and the file ends in a notice (apply discipline section 4).
do $check$
declare v_blocked boolean := false; v_req text; v_sender text; v_tl jsonb; v_before bigint; v_after bigint;
        v_unfilled bigint; v_owner text;
begin
  select count(*) into v_before from public.notifications;

  -- (a) a seat other than customer_support cannot be the sender
  begin
    insert into public.notifications (type, to_email, to_role, channel, status, subject, body, sender)
    values ('invoice_ready', 'zz-demo-guard@example.invalid', 'customer', 'email', 'held', 'ZZ DEMO', 'ZZ DEMO', 'accountant');
  exception when check_violation then v_blocked := true;
  end;
  if not v_blocked then raise exception 'GUARD FAILED: an outbox row with sender=accountant was accepted'; end if;

  -- (b) a delivery request names its seat and customer_support sends it; (c) the timeline sees it
  begin
    insert into public.notifications (type, to_email, to_role, channel, status, subject, body)
    values ('invoice_ready', 'zz-demo-timeline@example.invalid', 'customer', 'email', 'held', 'ZZ DEMO invoice', 'ZZ DEMO')
    returning requested_by, sender into v_req, v_sender;
    v_tl := public.fn_contact_timeline('zz-demo-timeline@example.invalid', 10);
    raise exception using errcode = 'P0001', message = 'probe-rollback';
  exception when others then
    if sqlerrm <> 'probe-rollback' then raise; end if;
  end;
  if v_req is distinct from 'sales_engineer' or v_sender is distinct from 'customer_support' then
    raise exception 'REQUESTED_BY/SENDER WRONG: requested_by=% sender=%', v_req, v_sender;
  end if;
  if coalesce((v_tl ->> 'event_count')::int, 0) < 1 or v_tl -> 'events' -> 0 ->> 'seat' <> 'sales_engineer' then
    raise exception 'TIMELINE DID NOT SEE THE DELIVERY REQUEST: %', v_tl;
  end if;

  select count(*) into v_after from public.notifications;
  if v_after <> v_before then raise exception 'PROBE LEFT ROWS BEHIND: % -> %', v_before, v_after; end if;

  select count(*) into v_unfilled from public.notifications where requested_by is null or sender <> 'customer_support';
  if v_unfilled > 0 then raise exception 'BACKFILL INCOMPLETE: % row(s)', v_unfilled; end if;

  select string_agg(function_slug || '=' || owner, ', ') into v_owner from public.function_owner
   where function_slug in ('send_outbox','send_whatsapp','email_cron','wa_inbound','resend_inbound','inbound_email',
                           'email_triage','site_assistant','wa_template_setup','wa_templates_watch','wa_optin_set',
                           'resend_webhook','unsubscribe')
     and owner <> 'customer_support';
  if v_owner is not null then raise exception 'A CHANNEL FUNCTION IS OWNED BY ANOTHER SEAT: %', v_owner; end if;

  raise notice 'channels: sender guard refuses other seats; requested_by=% sender=%; timeline events=%; % rows backfilled',
    v_req, v_sender, v_tl ->> 'event_count', v_before;
end
$check$;

commit;
