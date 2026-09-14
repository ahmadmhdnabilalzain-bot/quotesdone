-- THE WHATSAPP NUMBER IS CONFIRMED, AND ONLY A CONFIRMED ONE IS USED (14 Sep 2026, agent: customer_support)
--
-- The founder, 14 Sep 2026 (founder_instruction #322): "what if the customer has whatsapp on another
-- phone number, maybe we should confirm this point through the sign up".
--
-- MEASURED BEFORE THIS FILE (production, 14 Sep 2026):
--   * WhatsApp notices went to whatever number was on the row: fn_wa_fanout sent a customer's to
--     customers.phone and a supplier's to leads.whatsapp (a SCRAPED listing number, never verified)
--     or leads.phone, and fn_originator_checks_delivery retried a failed email the same way.
--   * Inbound WhatsApp was matched against the same unverified columns by fn_wa_lead_id (and through
--     it fn_wa_answer and fn_wa_fact_pack), fn_identify_contact, fn_conversation_party and
--     fn_wa_context, on a 9-digit tail, taking the first row: a scraped number could make a stranger's
--     message read as a supplier's, and a number on two accounts silently picked one.
--
-- WHAT THIS CHANGES
--   1. customers and leads gain whatsapp_phone, whatsapp_verified_at, whatsapp_opt (same/other/none;
--      null = not answered) and whatsapp_asked_at. Written only by kyc (whatsapp_choose /
--      whatsapp_send_code / whatsapp_verify / whatsapp_later). Email stays the identity: nothing here
--      is read by sign-in, and login_otp's phone lookup is untouched (a phone may confirm, never select).
--   2. fn_verified_mobile: the mobile only if it was verified by code.
--   3. fn_whatsapp_destination: where a WhatsApp notice may go. 'other' -> whatsapp_phone only once
--      verified; 'same' -> the CURRENT verified mobile (derived, so a changed mobile cannot leave a
--      stale copy); 'none' or unanswered -> nowhere. An unverified number is never returned.
--   4. fn_whatsapp_owner: who an inbound WhatsApp number belongs to - a verified 'other' number or a
--      verified 'same' mobile, nothing else. Two different parties on one number -> nobody.
--   5. a03_notifications_whatsapp_goes_to_a_confirmed_number: every customer/supplier WhatsApp row is
--      addressed by fn_whatsapp_destination whoever wrote it; with no confirmed number it is recorded
--      as 'skipped' with the reason, never sent to the number the writer guessed.
--   6. fn_wa_fanout makes the WhatsApp twin only for a confirmed number, and records a 'skipped' twin
--      for someone who said they do not use WhatsApp (their email carries it). Unanswered accounts get
--      no twin, as before when there was no opt-in.
--   7. fn_originator_checks_delivery retries an undelivered email on the confirmed WhatsApp number,
--      else by SMS on the verified mobile (send_sms drains channel='sms'), never an unverified number.
--   8. fn_wa_lead_id, fn_identify_contact, fn_conversation_party, fn_wa_context and (PR #652)
--      fn_spec_offer_whatsapp_reply match inbound numbers only through fn_whatsapp_owner, now the ONE
--      inbound-number helper. #652's fn_customer_by_whatsapp_sender (verified mobile only, no 'other'
--      number) had one caller, fn_spec_offer_whatsapp_reply - measured 14 Sep 2026 by a search of every
--      routine body on production and of the repository; pg_depend is empty (plpgsql calls are not
--      recorded there) - and is dropped at the end of this file, recorded in scripts/sql/DROPPED.txt.
--   9. wa_optin stops being a second source of WhatsApp consent (review of #657). Its two database
--      readers are repointed: fn_support_notify_new_quotation gated its WhatsApp alert on wa_optin and
--      addressed it to customers.phone - it now sends only to fn_whatsapp_destination and records the
--      honest skip reason; fn_ws_customer_360 reported the flag and now reports the WhatsApp route.
--      (fn_wa_fanout, the third reader, is replaced above.) The edge readers (customer_api, sales_engineer,
--      dropbox_backup, supplier_api) and kyc's writes go in the same PR. After this file and that code,
--      NOTHING reads or writes customers.wa_optin / leads.wa_optin; the column is kept, not dropped here.
--  10. wa_optin_set, the edge function that let a signed-in user write wa_optin, is retired in this PR
--      (folder, config.toml, check lists). Its registry rows go here, the way the OS retirement
--      (the_os_and_the_founder_command_layer_are_removed.sql) cleared function_owner. Undeploy with
--      `npx supabase functions delete wa_optin_set --project-ref htdblwldjkcgjvmqkbeh` straight after merge.
--
-- WHAT THIS DOES NOT CHANGE
--   * fn_support_notify_new_quotation writes WhatsApp into support_notification, which is deliberately
--     not bridged to any sender (fn_support_notification_to_outbox holds it), so nothing is sent there.
--   * leads.whatsapp (the scraped number) is kept as data about the listing; it is no longer a route.
--   * Existing accounts: until they answer (the portal asks once, never blocking), WhatsApp is not used
--     for them. Pre-launch there are no real customers to lose a message.

-- ── 1. THE COLUMNS ───────────────────────────────────────────────────────────────────────────────
alter table public.customers add column if not exists whatsapp_phone text,
  add column if not exists whatsapp_verified_at timestamptz,
  add column if not exists whatsapp_opt text,
  add column if not exists whatsapp_asked_at timestamptz;
alter table public.leads add column if not exists whatsapp_phone text,
  add column if not exists whatsapp_verified_at timestamptz,
  add column if not exists whatsapp_opt text,
  add column if not exists whatsapp_asked_at timestamptz;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'customers_whatsapp_opt_known') then
    alter table public.customers add constraint customers_whatsapp_opt_known check (whatsapp_opt is null or whatsapp_opt in ('same', 'other', 'none'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'leads_whatsapp_opt_known') then
    alter table public.leads add constraint leads_whatsapp_opt_known check (whatsapp_opt is null or whatsapp_opt in ('same', 'other', 'none'));
  end if;
  -- A number is only ever stored together with the moment it was verified.
  if not exists (select 1 from pg_constraint where conname = 'customers_whatsapp_phone_is_verified') then
    alter table public.customers add constraint customers_whatsapp_phone_is_verified check (whatsapp_phone is null or whatsapp_verified_at is not null);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'leads_whatsapp_phone_is_verified') then
    alter table public.leads add constraint leads_whatsapp_phone_is_verified check (whatsapp_phone is null or whatsapp_verified_at is not null);
  end if;
end $$;
comment on column public.customers.whatsapp_opt is 'Answer to "Is this number on WhatsApp?": same (the verified mobile), other (whatsapp_phone, verified over WhatsApp), none. Null = not answered. Founder, 14 Sep 2026 (#322).';
comment on column public.leads.whatsapp_opt is 'As customers.whatsapp_opt. leads.whatsapp is the scraped listing number and is never a route.';

-- ── 2-4. THE THREE RESOLVERS ────────────────────────────────────────────────────────────────────
create or replace function public.fn_verified_mobile(p_role text, p_customer uuid default null, p_lead bigint default null, p_email text default null)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select case
    when p_role = 'customer' then (select c.phone from public.customers c
                                    where coalesce(c.phone_verified, false) and nullif(btrim(c.phone), '') is not null
                                      and (c.id = p_customer or (p_customer is null and p_email is not null and lower(c.email) = lower(btrim(p_email))))
                                    limit 1)
    when p_role = 'supplier' then (select l.phone from public.leads l
                                    where coalesce(l.owner_phone_verified, false) and nullif(btrim(l.phone), '') is not null
                                      and (l.id = p_lead or (p_lead is null and p_email is not null and (lower(l.claimed_by) = lower(btrim(p_email)))))
                                    order by l.id limit 1)
  end
$fn$;
revoke execute on function public.fn_verified_mobile(text, uuid, bigint, text) from public, anon, authenticated;
grant execute on function public.fn_verified_mobile(text, uuid, bigint, text) to service_role;

create or replace function public.fn_whatsapp_destination(p_role text, p_customer uuid default null, p_lead bigint default null, p_email text default null)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_opt text; v_wa text; v_at timestamptz;
begin
  if p_role = 'customer' then
    select c.whatsapp_opt, c.whatsapp_phone, c.whatsapp_verified_at into v_opt, v_wa, v_at from public.customers c
     where c.id = p_customer or (p_customer is null and p_email is not null and lower(c.email) = lower(btrim(p_email))) limit 1;
  elsif p_role = 'supplier' then
    select l.whatsapp_opt, l.whatsapp_phone, l.whatsapp_verified_at into v_opt, v_wa, v_at from public.leads l
     where l.id = p_lead or (p_lead is null and p_email is not null and lower(l.claimed_by) = lower(btrim(p_email))) order by l.id limit 1;
  else
    return null;
  end if;
  if v_opt = 'other' and v_at is not null and nullif(btrim(v_wa), '') is not null then return v_wa; end if;
  if v_opt = 'same' then return public.fn_verified_mobile(p_role, p_customer, p_lead, p_email); end if;
  return null;   -- 'none', unanswered, or an 'other' number not yet verified
end $fn$;
revoke execute on function public.fn_whatsapp_destination(text, uuid, bigint, text) from public, anon, authenticated;
grant execute on function public.fn_whatsapp_destination(text, uuid, bigint, text) to service_role;

-- p_all: every confirmed owner, for a caller that must REPORT a shared number rather than act on it
-- (#652's offer reply opens a support case). Every caller acts only on exactly one owner.
create or replace function public.fn_whatsapp_owner(p_phone text, p_all boolean default false)
returns table(party_kind text, customer_id uuid, lead_id bigint)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with t as (select right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9) as tail),
  hits as (
    select 'customer'::text as party_kind, c.id as customer_id, null::bigint as lead_id
      from public.customers c, t
     where length(t.tail) = 9
       and ((c.whatsapp_opt = 'other' and c.whatsapp_verified_at is not null
             and right(regexp_replace(coalesce(c.whatsapp_phone, ''), '[^0-9]', '', 'g'), 9) = t.tail)
         or (c.whatsapp_opt = 'same' and coalesce(c.phone_verified, false)
             and right(regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g'), 9) = t.tail))
    union
    select 'supplier', null, l.id
      from public.leads l, t
     where length(t.tail) = 9
       and ((l.whatsapp_opt = 'other' and l.whatsapp_verified_at is not null
             and right(regexp_replace(coalesce(l.whatsapp_phone, ''), '[^0-9]', '', 'g'), 9) = t.tail)
         or (l.whatsapp_opt = 'same' and coalesce(l.owner_phone_verified, false)
             and right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 9) = t.tail)))
  -- A PHONE MAY CONFIRM, NEVER SELECT: one party or nobody.
  select h.party_kind, h.customer_id, h.lead_id from hits h where p_all or (select count(*) from hits) = 1
$fn$;
revoke execute on function public.fn_whatsapp_owner(text, boolean) from public, anon, authenticated;
grant execute on function public.fn_whatsapp_owner(text, boolean) to service_role;

-- ── 5. EVERY WHATSAPP NOTICE GOES TO A CONFIRMED NUMBER ─────────────────────────────────────────
create or replace function public.fn_notifications_whatsapp_goes_to_a_confirmed_number()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_dest text; v_opt text;
begin
  if coalesce(new.channel, '') <> 'whatsapp' or coalesce(new.to_role, '') not in ('customer', 'supplier') then return new; end if;
  v_dest := public.fn_whatsapp_destination(new.to_role, null, new.lead_id, new.to_email);
  if v_dest is not null then new.to_phone := v_dest; return new; end if;
  if new.to_role = 'customer' then
    select c.whatsapp_opt into v_opt from public.customers c where lower(c.email) = lower(btrim(coalesce(new.to_email, ''))) limit 1;
  else
    select l.whatsapp_opt into v_opt from public.leads l where l.id = new.lead_id or (new.lead_id is null and lower(l.claimed_by) = lower(btrim(coalesce(new.to_email, '')))) order by l.id limit 1;
  end if;
  new.status := 'skipped';
  new.last_error := case when v_opt = 'none'
    then 'not sent on WhatsApp: the recipient said they do not use WhatsApp; email or SMS carries this message'
    else 'not sent on WhatsApp: no confirmed WhatsApp number on file (an unverified number is never used)' end;
  return new;
end $fn$;
revoke execute on function public.fn_notifications_whatsapp_goes_to_a_confirmed_number() from public, anon, authenticated;
drop trigger if exists a03_notifications_whatsapp_goes_to_a_confirmed_number on public.notifications;
create trigger a03_notifications_whatsapp_goes_to_a_confirmed_number before insert on public.notifications
  for each row execute function public.fn_notifications_whatsapp_goes_to_a_confirmed_number();

-- ── 6. THE WHATSAPP TWIN ────────────────────────────────────────────────────────────────────────
create or replace function public.fn_wa_fanout()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_dest text; v_opt text;
begin
  -- only fan out plain email rows; never recurse on whatsapp rows
  if coalesce(new.channel, 'email') <> 'email' or new.to_email is null or coalesce(new.to_role, '') not in ('customer', 'supplier') then return new; end if;
  v_dest := public.fn_whatsapp_destination(new.to_role, null, new.lead_id, new.to_email);
  if v_dest is null then
    if new.to_role = 'customer' then
      select c.whatsapp_opt into v_opt from public.customers c where lower(c.email) = lower(new.to_email) limit 1;
    else
      select l.whatsapp_opt into v_opt from public.leads l where l.id = new.lead_id or (new.lead_id is null and lower(l.claimed_by) = lower(new.to_email)) order by l.id limit 1;
    end if;
    -- 'none' is recorded (a03 marks the twin skipped with the reason); unanswered makes no twin.
    if v_opt is distinct from 'none' then return new; end if;
  end if;
  insert into public.notifications (type, to_email, to_role, to_phone, lead_id, inquiry_id, quote_id, subject, body, channel, status)
  values (new.type, new.to_email, new.to_role, v_dest, new.lead_id, new.inquiry_id, new.quote_id, new.subject, new.body, 'whatsapp', 'queued');
  return new;
end $fn$;

create or replace function public.fn_originator_checks_delivery(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  a public.agent_actions; req public.agent_actions; n public.notifications; v_seat text; v_result text; v_seen jsonb;
  v_verdict text; v_phone text; v_email text; v_channel text; v_retry bigint; v_rep jsonb; v_origin bigint;
begin
  select * into a from public.agent_actions where id = p_id;
  v_seat := a.agent; v_result := a.detail->>'result';
  select * into req from public.agent_actions where id = (a.detail->>'request_id')::bigint;
  if req.id is null then return jsonb_build_object('closed', false, 'reason', 'the request this result answers is gone'); end if;

  select * into n from public.notifications
   where id = coalesce((req.detail->>'retry_notification_id')::bigint, (req.evidence->>'notification_id')::bigint);
  v_seen := jsonb_build_object('notification_id', n.id, 'status', n.status, 'channel', n.channel,
                               'provider_message_id', n.provider_message_id, 'sent_at', n.sent_at, 'checked_at', now());

  if v_result in ('proof_of_response', 'no_response_confirmation') then
    v_verdict := 'handled_by_the_ladder';
  elsif v_result = 'delivered' and n.status = 'sent' and coalesce(btrim(n.provider_message_id), '') <> '' then
    v_verdict := 'confirmed';
  elsif v_result in ('routed', 'stubbed', 'digested', 'cancelled') then
    v_verdict := v_result;
  end if;

  if v_verdict is null and v_result not in ('not_queued', 'sent_unconfirmed') and req.detail->'retry_of' is null
     and coalesce(req.detail->>'recipient_role', n.to_role) in ('customer', 'supplier') then
    -- THE OTHER CHANNEL, ONCE. Email that did not arrive goes to the number on file; WhatsApp that did
    -- not arrive goes to the address. A refused request (not_queued) is a defect, not a channel
    -- problem, and a send that may have left (sent_unconfirmed) is never sent twice: both escalate.
    v_email := coalesce(n.to_email, req.detail->>'to_email');
    if coalesce(n.channel, req.detail->'prepared'->>'channel', 'email') = 'whatsapp' then
      if coalesce(v_email, '') ~ '@' then v_channel := 'email'; end if;
    else
      -- 14 Sep 2026 (#322): the CONFIRMED WhatsApp number, else SMS on the verified mobile. This used to
      -- take leads.whatsapp (a scraped listing number) or any phone on file.
      v_phone := public.fn_whatsapp_destination(coalesce(req.detail->>'recipient_role', n.to_role), null,
                   coalesce((req.detail->>'supplier_id')::bigint, n.lead_id), v_email);
      if v_phone is not null then v_channel := 'whatsapp';
      else
        v_phone := public.fn_verified_mobile(coalesce(req.detail->>'recipient_role', n.to_role), null,
                     coalesce((req.detail->>'supplier_id')::bigint, n.lead_id), v_email);
        if v_phone is not null then v_channel := 'sms'; end if;
      end if;
    end if;
    if v_channel is not null and n.id is not null then
      v_retry := public.fn_seat_handoff(v_seat, 'customer_support', 'delivery.request', 'notifications', 'retry:' || req.id,
        jsonb_build_object('retry_of', req.id, 'msg_type', n.type, 'recipient_role', coalesce(n.to_role, req.detail->>'recipient_role'),
                           'to_email', v_email, 'supplier_id', coalesce(req.detail->'supplier_id', to_jsonb(n.lead_id)),
                           'inquiry_id', n.inquiry_id, 'quote_id', n.quote_id,
                           'prepared', jsonb_build_object('type', n.type, 'kind', n.kind, 'to_role', n.to_role, 'lead_id', n.lead_id,
                                                          'inquiry_id', n.inquiry_id, 'quote_id', n.quote_id, 'subject', n.subject,
                                                          'body', n.body, 'lang', n.lang, 'channel', v_channel,
                                                          'to_email', case when v_channel = 'email' then v_email else n.to_email end,
                                                          'to_phone', case when v_channel in ('whatsapp', 'sms') then v_phone end)));
      v_verdict := 'retried_on_' || v_channel;
    end if;
  end if;

  if v_verdict is null then
    v_rep := public.fn_support_report_to_ceo(
      'delivery_undelivered:' || req.id, 'elevated',
      'A ' || coalesce(req.detail->>'msg_type', 'notice') || ' for the ' || coalesce(req.detail->>'recipient_role', n.to_role, 'recipient')
        || ' did not arrive (' || v_result || ')',
      jsonb_build_object('request_id', req.id, 'result', v_result, 'support_evidence', a.detail->'evidence', 'rechecked', v_seen,
                         'retry_of', req.detail->'retry_of'),
      jsonb_build_array(v_seat || ' asked customer_support to send it',
                        case when req.detail->'retry_of' is not null then 'it was already a retry on the other channel'
                             else 'no other channel was on file' end),
      'Decide how this reaches them: correct the address or number, reach them another way, or record that it need not go.',
      'agent_actions#' || req.id, p_source_agent => v_seat);
    v_verdict := case when coalesce((v_rep->>'ok')::boolean, false) then 'escalated' else 'escalation_refused' end;
  end if;

  update public.agent_actions
     set detail = detail || jsonb_build_object('loop', v_verdict, 'closed_by', v_seat, 'closed_at', now(), 'close_check', v_seen,
                                               'retry_request_id', v_retry, 'escalation', v_rep)
   where id = req.id;
  -- A retry's outcome is the original's outcome too: whoever reads the first request sees how it ended.
  v_origin := (req.detail->>'retry_of')::bigint;
  if v_origin is not null then
    update public.agent_actions set detail = detail || jsonb_build_object('loop', 'retry_' || v_verdict) where id = v_origin;
  end if;
  return jsonb_build_object('checked_by', v_seat, 'result', v_result, 'verdict', v_verdict, 'rechecked', v_seen,
                            'retry_request_id', v_retry, 'escalation', v_rep);
end $function$;


create or replace function public.fn_wa_lead_id(p_phone text)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- 14 Sep 2026 (#322): only a supplier's CONFIRMED WhatsApp number (fn_whatsapp_owner). fn_wa_answer
  -- and fn_wa_fact_pack identify suppliers through this function.
  select o.lead_id from public.fn_whatsapp_owner(p_phone) o where o.party_kind = 'supplier';
$function$;


create or replace function public.fn_identify_contact(p_phone text)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_d text; v_tail text; v_name text; v_sid bigint; v_cid text; v_claimed boolean; v_appr boolean; v_kind text; v_cuid uuid;
begin
  v_d := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
  if length(v_d) < 7 then return json_build_object('audience','unknown'); end if;
  v_tail := right(v_d, 9);   -- tolerate +9715..., 05..., 5... variants

  -- THE FOUNDER. Before suppliers and customers: he is neither, and a number that is both his and
  -- a lead's must still be treated as his.
  if exists (
    select 1 from unnest(string_to_array(coalesce((select value from app_secrets where key='admin_mfa_phone'),''), ',')) p
     where length(regexp_replace(p,'[^0-9]','','g')) >= 9
       and right(regexp_replace(p,'[^0-9]','','g'), 9) = v_tail)
  then
    return json_build_object('audience','founder',
      'name', split_part(coalesce((select value from app_secrets where key='admin_emails'),''), ',', 1));
  end if;

  -- 14 Sep 2026 (#322): a supplier or customer is recognised only by a CONFIRMED WhatsApp number.
  select o.party_kind, o.lead_id, o.customer_id into v_kind, v_sid, v_cuid from public.fn_whatsapp_owner(p_phone) o;
  if v_kind = 'supplier' then
    select company_name, coalesce(claimed,false), (approval_status='approved') into v_name, v_claimed, v_appr from leads where id = v_sid;
  end if;
  if v_sid is not null then
    return json_build_object('audience','supplier','name',v_name,'claimed',v_claimed,'approved',coalesce(v_appr,false));
  end if;

  if v_kind = 'customer' then select id::text, full_name into v_cid, v_name from customers where id = v_cuid; end if;
  if v_cid is not null then
    return json_build_object('audience','customer','name',v_name);
  end if;

  return json_build_object('audience','unknown');
end $function$;


create or replace function public.fn_conversation_party(p_lead bigint, p_customer uuid, p_inquiry uuid, p_email text, p_phone text)
 RETURNS TABLE(party_kind text, party_id text, inquiry_id text, demo boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_email text := lower(nullif(btrim(coalesce(p_email, '')), ''));
        v_tail text := nullif(right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9), '');
        v_c uuid; v_l bigint;
begin
  if v_tail is not null and length(v_tail) < 7 then v_tail := null; end if;
  v_c := p_customer;
  if v_c is null and p_inquiry is not null then select i.customer_id into v_c from public.inquiries i where i.id = p_inquiry; end if;
  if v_c is not null then
    return query select 'customer'::text, v_c::text, p_inquiry::text,
      coalesce((select c.is_demo or coalesce(c.email, '') ~* 'example\.invalid' from public.customers c where c.id = v_c), false);
    return;
  end if;
  v_l := p_lead;
  if v_l is null and v_email is not null then
    select c.id into v_c from public.customers c where lower(c.email) = v_email limit 1;
    if v_c is not null then
      return query select 'customer'::text, v_c::text, null::text,
        coalesce((select c.is_demo or coalesce(c.email, '') ~* 'example\.invalid' from public.customers c where c.id = v_c), false);
      return;
    end if;
    select l.id into v_l from public.leads l where lower(l.email) = v_email or lower(l.claimed_by) = v_email limit 1;
  end if;
  if v_l is null and v_tail is not null then
    -- 14 Sep 2026 (#322): only a CONFIRMED WhatsApp number names a party.
    select o.customer_id, o.lead_id into v_c, v_l from public.fn_whatsapp_owner(p_phone) o;
    if v_c is not null then
      return query select 'customer'::text, v_c::text, null::text,
        coalesce((select c.is_demo from public.customers c where c.id = v_c), false);
      return;
    end if;
  end if;
  if v_l is not null then
    return query select 'supplier'::text, v_l::text, null::text,
      coalesce((select coalesce(l.is_demo, false) or coalesce(l.email, '') ~* 'example\.invalid'
                     or coalesce(l.company_name, '') ~* 'ZZ DEMO' from public.leads l where l.id = v_l), false);
    return;
  end if;
  return query select 'company'::text, null::text, null::text, false;
end $function$;


create or replace function public.fn_wa_context(p_audience text, p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_e164 text; v_email text; v_lead record; v_cust record;
        v_dc uuid[]; v_dl bigint[]; v_di uuid[]; v_refunds jsonb;
begin
  -- ONE IDENTIFIER, TWO SHAPES. wa_from arrives as 'whatsapp:+9715...'; a browser session arrives
  -- as an email address. An '@' is the discriminator: nothing that is a phone number contains one,
  -- and an address stripped of non-digits is meaningless, which is how a mis-shaped identifier used
  -- to fall through to "known: false" instead of an answer.
  v_email := nullif(lower(btrim(coalesce(p_phone, ''))), '');
  if v_email is not null and position('@' in v_email) = 0 then v_email := null; end if;
  v_e164 := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  if v_e164 = '' and v_email is null then return jsonb_build_object('scope','none'); end if;

  -- ---------------------------------------------------------------- FOUNDER: the company itself
  if p_audience = 'founder' then
    -- DEMO: left out of every business figure below.
    select coalesce(array_agg(id), '{}') into v_dc from customers where is_demo;
    select coalesce(array_agg(id), '{}') into v_dl from leads where is_demo;
    select coalesce(array_agg(id), '{}') into v_di from inquiries where public.fn_inquiry_is_demo(id);

    -- REFUNDS ARE THE CEO'S, NOT HIS. The old decision-queue reader (dropped 9 Sep) listed refunds as
    -- waiting on him; since 14 Sep the CEO decides every refund and the founder only receives the CEO's summary
    -- when a review loop escalates. This is what the CEO holds, stated as information.
    with open_r as (
      select r.id, r.requested_at, r.amount_fils, r.reason_code, rv.cycle, rv.outcome
        from refunds r
        left join lateral (select x.cycle, x.outcome from refund_ceo_review x where x.refund_id = r.id order by x.cycle desc limit 1) rv on true
       where r.status = 'requested'
         and (r.customer_id = any (v_dc)) is not true and (r.supplier_lead_id = any (v_dl)) is not true and (r.inquiry_id = any (v_di)) is not true)
    select jsonb_build_object(
      'who_decides', 'ceo',
      'note', 'Every refund is decided by the CEO. You receive his short summary only when a review loop escalates (three cycles or a missed deadline). Nothing here waits on you.',
      'open', (select count(*) from open_r),
      'escalated', (select count(*) from open_r where outcome = 'escalated'),
      'items', coalesce((select jsonb_agg(jsonb_build_object('refund_id', z.id, 'requested_at', z.requested_at,
                          'amount_aed', round(z.amount_fils / 100.0, 2), 'reason', z.reason_code,
                          'review_cycle', z.cycle, 'review_outcome', z.outcome) order by z.requested_at)
                           from (select * from open_r order by requested_at limit 12) z), '[]'::jsonb))
      into v_refunds;

    return jsonb_build_object(
      'scope','company',
      'suppliers', jsonb_build_object(
        'leads_total',      (select count(*) from leads where (id = any (v_dl)) is not true),
        'claimed',          (select count(*) from leads where coalesce(claimed,false) and (id = any (v_dl)) is not true),
        'claimed_real',     (select count(*) from leads where coalesce(claimed,false) and (id = any (v_dl)) is not true
                              and not (coalesce(company_name,'') ilike 'ZZ DEMO%' or coalesce(email,'') ilike '%@example.invalid')),
        'approved',         (select count(*) from leads where approval_status = 'approved' and (id = any (v_dl)) is not true),
        'licence_verified', (select count(*) from leads where coalesce(verified,false) and (id = any (v_dl)) is not true),
        'with_email',       (select count(*) from leads where coalesce(btrim(email),'') <> '' and (id = any (v_dl)) is not true)),
      'invites', jsonb_build_object(
        'enabled',      (select value from app_secrets where key='invite_enabled'),
        'daily_cap',    (select value from app_secrets where key='invite_daily_cap'),
        'sent_today',   (select count(*) from leads where invited_at >= date_trunc('day', now() at time zone 'utc') and (id = any (v_dl)) is not true),
        'sent_7d',      (select count(*) from leads where invited_at > now() - interval '7 days' and (id = any (v_dl)) is not true),
        'bounced_7d',   (select count(*) from leads where invite_status='bounced' and invited_at > now() - interval '7 days' and (id = any (v_dl)) is not true),
        'uncontacted',  (select count(*) from leads where invited_at is null and coalesce(btrim(email),'') <> '' and (id = any (v_dl)) is not true)),
      'demand', jsonb_build_object(
        'customers',        (select count(*) from customers where (id = any (v_dc)) is not true),
        'inquiries_total',  (select count(*) from inquiries where (id = any (v_di)) is not true),
        'inquiries_7d',     (select count(*) from inquiries where created_at > now() - interval '7 days' and (id = any (v_di)) is not true),
        'quotes_total',     (select count(*) from quotes where (inquiry_id = any (v_di)) is not true and (supplier_id = any (v_dl)) is not true),
        'quotes_7d',        (select count(*) from quotes where created_at > now() - interval '7 days'
                               and (inquiry_id = any (v_di)) is not true and (supplier_id = any (v_dl)) is not true)),
      'money', jsonb_build_object(
        'transactions',      (select count(*) from transactions where (customer_id = any (v_dc)) is not true
                                and (supplier_id = any (v_dl)) is not true and (inquiry_id = any (v_di)) is not true),
        'revealed',          (select count(*) from transactions where revealed_at is not null and (customer_id = any (v_dc)) is not true
                                and (supplier_id = any (v_dl)) is not true and (inquiry_id = any (v_di)) is not true),
        'ai_spend_today_aed',(select round(coalesce(sum(cost_aed),0)::numeric,2) from ai_cost_log where occurred_at >= current_date),
        'ai_spend_month_aed',(select round(coalesce(sum(cost_aed),0)::numeric,2) from ai_cost_log where occurred_at >= date_trunc('month', now()))),
      'health', jsonb_build_object(
        'agent_runs_failed_24h', (select count(*) from agent_runs where status in ('error','failed') and started_at > now() - interval '24 hours'),
        'actions_pending',       (select count(*) from agent_actions where status in ('pending','needs_review')),
        'escalations_open',      (select count(*) from agent_actions where coalesce(escalated,false) and status in ('pending','needs_review'))),
      'refunds_with_the_ceo', v_refunds);
  end if;

  -- ---------------------------------------------------------------- SUPPLIER: only their own row
  if p_audience = 'supplier' then
    select * into v_lead from leads l
     where (v_e164 <> '' and l.id = (select o.lead_id from public.fn_whatsapp_owner(p_phone) o where o.party_kind = 'supplier'))
        or (v_email is not null and (lower(coalesce(l.claimed_by,'')) = v_email or lower(coalesce(l.email,'')) = v_email))
     order by coalesce(l.claimed,false) desc, l.id limit 1;
    if not found then return jsonb_build_object('scope','supplier','known', false); end if;

    return jsonb_build_object(
      'scope','supplier', 'known', true,
      'company', v_lead.company_name,
      'account', jsonb_build_object('email', v_lead.claimed_by, 'phone', coalesce(v_lead.phone_e164, v_lead.phone)),
      'profile', jsonb_build_object(
        'claimed',          coalesce(v_lead.claimed,false),
        'approval_status',  coalesce(v_lead.approval_status,'not submitted'),
        'verified',         coalesce(v_lead.verified,false),
        'email_verified',   coalesce(v_lead.owner_email_verified,false),
        'phone_verified',   coalesce(v_lead.owner_phone_verified,false),
        'trade_licence_no', v_lead.trade_license_no,
        'licence_authority',v_lead.license_authority,
        'licence_expiry',   v_lead.license_expiry,
        'licence_on_file',  (v_lead.license_doc_path is not null),
        'blocked_because',  v_lead.licence_gate_reason),
      'work', jsonb_build_object(
        'inquiries_received',  (select count(*) from inquiry_matches m where m.supplier_id = v_lead.id),
        'inquiries_quoted',    (select count(distinct q.inquiry_id) from quotes q where q.supplier_id = v_lead.id),
        'inquiries_missed',    (select count(*) from inquiry_matches m where m.supplier_id = v_lead.id
                                  and not exists (select 1 from quotes q where q.inquiry_id = m.inquiry_id and q.supplier_id = v_lead.id)),
        'quotes_submitted',    (select count(*) from quotes q where q.supplier_id = v_lead.id),
        'last_quote',          (select jsonb_build_object('amount_aed', q.quote_amount, 'status', q.status, 'when', q.created_at)
                                  from quotes q where q.supplier_id = v_lead.id order by q.created_at desc limit 1),
        'jobs_won',            (select count(*) from quotes q where q.supplier_id = v_lead.id and q.status = 'accepted')));
  end if;

  -- ---------------------------------------------------------------- CUSTOMER: only their own rows
  if p_audience = 'customer' then
    select * into v_cust from customers c
     where (v_e164 <> '' and c.id = (select o.customer_id from public.fn_whatsapp_owner(p_phone) o where o.party_kind = 'customer'))
        or (v_email is not null and lower(coalesce(c.email,'')) = v_email)
     limit 1;
    if not found then return jsonb_build_object('scope','customer','known', false); end if;

    return jsonb_build_object(
      'scope','customer', 'known', true,
      'name', v_cust.full_name,
      -- WHAT WE HOLD FOR THEM. "what is my email registered" was one of the four questions the
      -- assistant could not answer, and the answer was one column away the whole time.
      'account', jsonb_build_object(
        'email', v_cust.email, 'phone', v_cust.phone,
        'language', v_cust.locale, 'industry', v_cust.industry,
        'customer_since', v_cust.created_at),
      'profile', jsonb_build_object(
        'phone_verified', coalesce(v_cust.phone_verified,false),
        'email_verified', coalesce(v_cust.email_verified,false),
        'terms_signed',   (v_cust.signed_terms_url is not null),
        -- create_inquiry's own gate, stated as the fact it is, so the assistant answers "can I post
        -- a request" with the truth rather than an encouragement.
        'can_post_request', (coalesce(v_cust.phone_verified,false) and coalesce(v_cust.email_verified,false)
                             and v_cust.signed_terms_url is not null)),
      'inquiries', coalesce((
        select jsonb_agg(x order by x->>'created_at' desc) from (
          select jsonb_build_object(
            'id', i.id, 'category', i.category, 'emirate', i.emirate, 'status', i.status,
            'created_at', i.created_at,
            'suppliers_received', (select count(*) from inquiry_matches m where m.inquiry_id = i.id),
            'quotes_received',    (select count(*) from quotes q where q.inquiry_id = i.id and q.status='submitted'),
            -- PRE-REVEAL: a band and a count, never the individual quotes and never a supplier name.
            'revealed', exists (select 1 from transactions t where t.inquiry_id = i.id and t.revealed_at is not null),
            'price_band', case
              when exists (select 1 from transactions t where t.inquiry_id = i.id and t.revealed_at is not null)
                then (select jsonb_build_object('low', min(q.quote_amount), 'high', max(q.quote_amount), 'average', round(avg(q.quote_amount)::numeric,0))
                        from quotes q where q.inquiry_id = i.id and q.status='submitted')
              else (select case when count(*) = 0 then null
                                else jsonb_build_object('average_rounded_to_nearest_1000',
                                        round(avg(q.quote_amount)::numeric / 1000) * 1000, 'note',
                                        'rounded band only - the exact quotes and the supplier names unlock when you reveal')
                           end from quotes q where q.inquiry_id = i.id and q.status='submitted') end) as x
          from inquiries i where i.customer_id = v_cust.id order by i.created_at desc limit 10) z), '[]'::jsonb));
  end if;

  return jsonb_build_object('scope','unknown');
end $function$;


create or replace function public.fn_spec_offer_whatsapp_reply(p_phone text, p_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_digits text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  v_cust uuid;
  v_matches int;
  v_ref text;
  r public.spec_alternative_offer;
  v_t text := lower(btrim(translate(coalesce(p_text, ''), '٠١٢٣٤٥٦٧٨٩', '0123456789')));
  v_n int;
  v_choice text;
begin
  if length(v_digits) < 8 then return jsonb_build_object('handled', false, 'reason', 'no_phone'); end if;
  -- The text's SHAPE first: only something that looks like an answer (a no, an option number, a bare
  -- yes) goes any further. Otherwise a number two customers share would open a support case for
  -- every "hello" it sends.
  v_t := regexp_replace(v_t, '[[:space:][:punct:]]+$', '');
  if not (v_t ~ '^(no|no thanks|decline|لا|لأ|لا شكرا|لا شكرًا)$'
          or v_t ~ '^(option |choice |yes |نعم |الخيار )?[0-9]{1,2}$'
          or v_t ~ '^(yes|ok|نعم|موافق)$') then
    return jsonb_build_object('handled', false, 'reason', 'not_a_reply');
  end if;
  -- Who the sender is: fn_whatsapp_owner alone decides (a verified 'other' WhatsApp number or a verified
  -- 'same' mobile). p_all, so a number several customers share is still reported below, never guessed.
  select count(*), min(w.customer_id::text)::uuid into v_matches, v_cust
    from public.fn_whatsapp_owner(p_phone, true) as w
   where w.party_kind = 'customer'
     and exists (select 1 from public.spec_alternative_offer o where o.customer_id = w.customer_id and o.state = 'open');
  if v_matches = 0 then return jsonb_build_object('handled', false, 'reason', 'no_verified_customer_with_open_offer'); end if;
  if v_matches > 1 then
    v_ref := 'SE-SPECOFFER-AMBIG-' || right(v_digits, 9) || '-' || to_char(now(), 'YYYYMMDD');
    insert into public.support_case (case_ref, party_kind, party_id, subject, owner_role_id)
    values (v_ref, 'unknown', null,
            'From the sales engineer: a WhatsApp answer to a no-exact-spec offer came from a number that ' || v_matches ||
            ' verified customers with open offers share. Nothing was recorded. Confirm with the customer which request it is for, then record it from the portal.',
            'customer_support')
    on conflict (case_ref) do nothing;
    return jsonb_build_object('handled', false, 'reason', 'ambiguous_sender', 'case_ref', v_ref, 'matches', v_matches);
  end if;
  select * into r from public.spec_alternative_offer where customer_id = v_cust and state = 'open' order by opened_at, id limit 1;
  if not found then return jsonb_build_object('handled', false, 'reason', 'no_open_offer'); end if;
  v_t := regexp_replace(v_t, '[[:space:][:punct:]]+$', '');
  if v_t ~ '^(no|no thanks|decline|لا|لأ|لا شكرا|لا شكرًا)$' then v_choice := 'no';
  elsif v_t ~ '^(option |choice |yes |نعم |الخيار )?[0-9]{1,2}$' then
    v_n := (regexp_replace(v_t, '\D', '', 'g'))::int;
    if v_n < 1 or v_n > jsonb_array_length(r.alternatives) then return jsonb_build_object('handled', true, 'ok', false, 'error', 'unknown_option', 'offer_id', r.id, 'options', jsonb_array_length(r.alternatives)); end if;
    v_choice := r.alternatives -> (v_n - 1) ->> 'option_id';
  elsif v_t ~ '^(yes|ok|نعم|موافق)$' and jsonb_array_length(r.alternatives) = 1 then v_choice := r.alternatives -> 0 ->> 'option_id';
  else return jsonb_build_object('handled', false, 'reason', 'not_a_reply', 'offer_id', r.id);
  end if;
  return jsonb_build_object('handled', true) || public.fn_spec_offer_answer(r.id, v_cust, v_choice, 'whatsapp');
end;
$function$;


-- ONE INBOUND-NUMBER HELPER. Its only caller now reads fn_whatsapp_owner (above).
drop function if exists public.fn_customer_by_whatsapp_sender(text);

-- ── 9. NO SECOND SOURCE OF WHATSAPP CONSENT ─────────────────────────────────────────────────────
create or replace function public.fn_support_notify_new_quotation(p_quote_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  q record; c record; v_case bigint; v_ref text; v_portal text;
  v_body text; v_subject text; v_scan jsonb;
  v_queued jsonb := '[]'::jsonb; v_skipped jsonb := '[]'::jsonb;
  v_dedupe text; v_id bigint;
begin
  -- THE COMMITTED STATE, AND THE CURRENT ONE. Both are required: committed_at proves it was
  -- published, and the status re-read proves it has not been withdrawn since. A quotation withdrawn
  -- between publication and this call must not be announced, and only a fresh read can know that.
  select qq.id, qq.inquiry_id, qq.supplier_id, qq.committed_at, qq.committed_hash, qq.status, qq.anonymized
    into q from public.quotes qq where qq.id = p_quote_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', format('no quotation %s', p_quote_id::text));
  end if;
  if q.committed_at is null then
    return jsonb_build_object('ok', false, 'reason',
      'this quotation is not committed. A draft or a failed upload is not a publication and must never reach a customer.');
  end if;
  if coalesce(q.status,'') in ('withdrawn','cancelled','rejected','expired') then
    return jsonb_build_object('ok', false, 'reason',
      format('the quotation is %L now. It was committed once; it is not visible today, and the customer is not told about it.', q.status));
  end if;

  -- wa_dest: the CONFIRMED WhatsApp number (#322), or null. wa_optin is no longer read anywhere.
  select i.rfq_no, cu.id cust_id, cu.full_name, cu.phone, cu.email, cu.banned,
         public.fn_whatsapp_destination('customer', cu.id) as wa_dest
    into c
    from public.inquiries i
    join public.customers cu on cu.id = i.customer_id
   where i.id = q.inquiry_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason',
      'the inquiry or its owner could not be read. Nothing is sent: a notification with no verified recipient is a message to a guess.');
  end if;
  if coalesce(c.banned, false) then
    return jsonb_build_object('ok', false, 'reason', 'the inquiry owner is banned; no notification is sent.');
  end if;

  -- rfq_no is an INTEGER sequence number. The customer-facing reference is rendered from it when
  -- it exists and from the inquiry id when it does not, so the shape is stable either way.
  v_ref := case when c.rfq_no is not null then 'RFQ-' || c.rfq_no::text
                else 'INQ-' || q.inquiry_id::text end;
  v_portal := coalesce((select value from public.app_secrets where key = 'public_site_url'), 'https://quotesdone.com') || '/portal';

  -- DETERMINISTIC RENDERING. The spec requires it for notifications, and it is also the only way the
  -- anonymity scan means anything: a model could compose a different sentence next time, and the
  -- scan would be checking a message nobody will send.
  v_body := 'You have received a new quotation for inquiry ' || v_ref
         || '. Sign in to your QuotesDone portal to review it: ' || v_portal || '.';
  v_subject := 'A new quotation for inquiry ' || v_ref;

  -- THE SCAN, before anything is queued. It reads the live supplier row and the live quotation, so
  -- it is checking for THIS supplier's actual name, email, phone and amount -- not a word list.
  v_scan := public.fn_support_anonymity_scan(v_body, v_subject, null, q.supplier_id, q.id::text);
  if (v_scan->>'safe') <> 'true' then
    return jsonb_build_object('ok', false, 'blocked', true, 'reason', v_scan->>'note', 'scan', v_scan);
  end if;

  -- The case that owns this conversation.
  insert into public.support_case (case_ref, party_kind, party_id, inquiry_ref, subject)
  values ('case:quote:' || q.id::text, 'customer', c.cust_id::text, v_ref,
          'New quotation published for ' || v_ref)
  on conflict (case_ref) do update set last_activity_at = now()
  returning case_id into v_case;
  if v_case is null then
    select case_id into v_case from public.support_case where case_ref = 'case:quote:' || q.id::text;
  end if;

  -- BOTH CHANNELS, EACH JUDGED ON ITS OWN PERMISSION. The spec: "Check both-channel permissions
  -- independently and record blocked/suppressed outcomes honestly." A missing email is not a reason
  -- to skip WhatsApp, and no consent on WhatsApp is not a reason to skip email.
  --
  -- The dedupe key carries the publication version (committed_hash), so re-committing a changed
  -- quotation notifies again and the same commit arriving twice does not.
  if c.wa_dest is not null then
    v_dedupe := 'quote_published|' || q.id::text || '|' || coalesce(q.committed_hash,'nohash') || '|whatsapp|' || c.wa_dest;
    insert into public.support_notification
      (dedupe_key, case_id, purpose, channel, recipient, inquiry_ref, publication_version,
       subject, body, anonymity_checked_at, anonymity_result)
    values (v_dedupe, v_case, 'quote_published', 'whatsapp', c.wa_dest, v_ref, q.committed_hash,
            null, v_body, now(), v_scan)
    on conflict (dedupe_key) do nothing
    returning id into v_id;
    v_queued := v_queued || jsonb_build_object('channel','whatsapp','queued', v_id is not null,
                  'note', case when v_id is null then 'already queued for this publication version' else 'queued' end);
  else
    v_skipped := v_skipped || jsonb_build_object('channel','whatsapp','reason',
      'no confirmed WhatsApp number (the customer said they do not use WhatsApp, or has not confirmed one)');
  end if;

  if coalesce(btrim(c.email),'') <> '' then
    v_dedupe := 'quote_published|' || q.id::text || '|' || coalesce(q.committed_hash,'nohash') || '|email|' || c.email;
    insert into public.support_notification
      (dedupe_key, case_id, purpose, channel, recipient, inquiry_ref, publication_version,
       subject, body, anonymity_checked_at, anonymity_result)
    values (v_dedupe, v_case, 'quote_published', 'email', c.email, v_ref, q.committed_hash,
            v_subject, v_body, now(), v_scan)
    on conflict (dedupe_key) do nothing
    returning id into v_id;
    v_queued := v_queued || jsonb_build_object('channel','email','queued', v_id is not null,
                  'note', case when v_id is null then 'already queued for this publication version' else 'queued' end);
  else
    v_skipped := v_skipped || jsonb_build_object('channel','email','reason','no email on the customer record');
  end if;

  return jsonb_build_object(
    'ok', true, 'quote_id', q.id, 'inquiry_ref', v_ref, 'case_id', v_case,
    'publication_version', q.committed_hash,
    'queued', v_queued, 'skipped', v_skipped, 'anonymity', v_scan,
    'note', 'Queued only. Delivery is the sender''s job and its outcome is recorded on the row, never assumed here.');
end $function$;


create or replace function public.fn_ws_customer_360(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare c public.customers%rowtype; j jsonb;
  ltv numeric(18,2); deal_value numeric(18,2); reveals int;
  rfqs_total int; rfqs_active int; rfqs_done int; avg_budget numeric(18,2);
  last_act timestamptz; score int; cats text; docs jsonb := '[]'::jsonb; summary text;
begin
  select * into c from public.customers where id=p_id;
  if c.id is null then return jsonb_build_object('error','customer not found'); end if;

  select coalesce(sum(reveal_fee) filter (where fee_status='paid'),0), coalesce(sum(quote_amount),0), count(*)
    into ltv, deal_value, reveals from public.transactions where customer_id=p_id;
  select count(*), count(*) filter (where status not in ('completed','cancelled','closed','lost')),
         count(*) filter (where status in ('completed','closed') or outcome='completed'),
         coalesce(round(avg(nullif(expected_value,0)),2),0)
    into rfqs_total, rfqs_active, rfqs_done, avg_budget from public.inquiries where customer_id=p_id;
  select string_agg(distinct category, ', ') into cats from public.inquiries where customer_id=p_id and category is not null;

  select greatest(coalesce(max(i.created_at), c.created_at),
                  coalesce((select max(revealed_at) from public.transactions where customer_id=p_id), c.created_at),
                  c.created_at)
    into last_act from public.inquiries i where i.customer_id=p_id;
  last_act := coalesce(last_act, c.created_at);

  score := least(100, greatest(0,
      coalesce(rfqs_total,0)*12 + coalesce(reveals,0)*25 + round(coalesce(ltv,0)/20)::int
      + (case when last_act > now() - interval '30 days' then 15 else 0 end)));

  docs := coalesce((select jsonb_agg(jsonb_build_object('type','Drawing','name',coalesce(drawing_file_name,'drawing'),'path',drawing_file_path))
                    from public.inquiries where customer_id=p_id and drawing_file_path is not null),'[]'::jsonb);
  if c.signed_terms_path is not null then docs := docs || jsonb_build_object('type','Signed terms','name','terms','path',c.signed_terms_path); end if;

  summary := c.full_name||' joined '||to_char(c.created_at,'Mon YYYY')||'. '
    ||coalesce(rfqs_total,0)||' RFQ(s)'||coalesce(' across '||cats,'')||'. '
    ||coalesce(reveals,0)||' reveal(s), AED '||to_char(coalesce(ltv,0),'FM999999990.00')||' paid to date.'
    ||(case when avg_budget>0 then ' Avg project budget AED '||to_char(avg_budget,'FM999999990') else '' end)
    ||(case when c.banned then ' [BANNED]' when not coalesce(c.email_verified,false) then ' Email unverified.' else '' end);

  j := jsonb_build_object(
    'profile', jsonb_build_object('id',c.id,'full_name',c.full_name,'email',c.email,'phone',c.phone,
       'created_at',c.created_at,'phone_verified',c.phone_verified,'email_verified',c.email_verified,
       'banned',c.banned,'banned_reason',c.banned_reason,'whatsapp',jsonb_build_object('opt',c.whatsapp_opt,'confirmed',public.fn_whatsapp_destination('customer',c.id) is not null),'tos_accepted_at',c.tos_accepted_at,
       'chat_strikes',c.chat_strikes),
    'metrics', jsonb_build_object('ltv',ltv,'total_deal_value',deal_value,'reveals',reveals,
       'rfqs_total',rfqs_total,'rfqs_active',rfqs_active,'rfqs_completed',rfqs_done,
       'avg_project_budget',avg_budget,'relationship_score',score),
    'ai_summary', summary,
    'preferences', (
       with pref as (select p.preferences pj from public.customer_preference p
                       join public.customers cc on cc.id = p.customer_id
                      where p.customer_id = p_id and cc.tos_accepted_at is not null)
       select jsonb_build_object(
         'categories', coalesce((select pj->'stated'->'categories' from pref),
                                (select pj->'inferred'->'categories' from pref),
                                coalesce((select jsonb_agg(distinct category) from public.inquiries where customer_id=p_id and category is not null),'[]'::jsonb)),
         'emirates',   coalesce((select pj->'stated'->'emirates' from pref),
                                (select pj->'inferred'->'emirates' from pref),
                                coalesce((select jsonb_agg(distinct emirate) from public.inquiries where customer_id=p_id and emirate is not null),'[]'::jsonb)),
         'scope_type', (select pj->'inferred'->>'scope_type' from pref),
         'budget_aed_avg', (select pj->'inferred'->'budget_aed_avg' from pref),
         'remembered', exists(select 1 from pref))),
    'rfqs', coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'category',i.category,'emirate',i.emirate,
       'status',i.status,'pipeline_stage',i.pipeline_stage,'budget',i.expected_value,
       'outcome',i.outcome,'created_at',i.created_at) order by i.created_at desc)
       from (select * from public.inquiries where customer_id=p_id order by created_at desc limit 15) i),'[]'::jsonb),
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'amount',q.quote_amount,'status',q.status,'created_at',q.created_at) order by q.created_at desc)
       from public.quotes q join public.inquiries i on i.id=q.inquiry_id where i.customer_id=p_id),'[]'::jsonb),
    'transactions', coalesce((select jsonb_agg(jsonb_build_object('quote_amount',t.quote_amount,'reveal_fee',t.reveal_fee,'fee_status',t.fee_status,'revealed_at',t.revealed_at) order by t.revealed_at desc)
       from public.transactions t where t.customer_id=p_id),'[]'::jsonb),
    'documents', docs,
    'timeline', (select jsonb_agg(e order by e->>'at' desc) from (
        select jsonb_build_object('at',c.created_at,'event','Signed up') e
        union all select jsonb_build_object('at',i.created_at,'event','RFQ: '||coalesce(i.category,'inquiry')) from public.inquiries i where i.customer_id=p_id
        union all select jsonb_build_object('at',t.revealed_at,'event','Revealed supplier · AED '||coalesce(t.reveal_fee::text,'0')||' fee') from public.transactions t where t.customer_id=p_id and t.revealed_at is not null
      ) tl)
  );
  return j;
end $function$;


-- ── 10. THE RETIRED EDGE FUNCTION LEAVES THE REGISTRIES ─────────────────────────────────────────
-- A registry that names an absent function is how a later reader concludes it exists; both rows are
-- read by live checks. Measured 14 Sep 2026: one function_owner row, one it_watch_subject row; the
-- phase_c_* registries that also listed it no longer exist.
delete from public.function_owner where function_slug = 'wa_optin_set';
delete from public.it_watch_subject where subject = 'wa_optin_set';

-- ── PROOF, NO DATA (this file defines things, so it must not raise on success) ────────────────────
do $$
begin
  if public.fn_whatsapp_destination('customer', null, null, 'nobody-registered@example.invalid') is not null then raise exception 'destination: an unknown address must have no WhatsApp route'; end if;
  if exists (select 1 from public.fn_whatsapp_owner('')) then raise exception 'owner: an empty number must match nobody'; end if;
  if exists (select 1 from public.fn_whatsapp_owner('+971 50 000 0000')) and (select count(*) from public.fn_whatsapp_owner('+971 50 000 0000')) <> 1 then raise exception 'owner: never more than one party'; end if;
  raise notice 'the_whatsapp_number_is_confirmed_and_only_a_confirmed_one_is_used: resolvers and routing hold';
end $$;
