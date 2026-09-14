-- no_supplier_quoted_the_exact_spec_so_the_customer_is_offered_what_was.sql
--
-- FOUNDER, 14 Sep 2026 (founder_instruction #321, verbatim): "if no supplier was able to quote what
-- customer requested, then the customer support agent need to communicate with the customer and
-- mention that no supplier was able to quote your exact spec. However, there were similar options
-- such as xxxx which they can, are you willing to proceed with such option? if yes then we proceed in
-- the normal workflow and accordingly dont consider the new spec as a deviation. if not then we just
-- apologize to the customer in a professional way".
--
-- MEASURED BEFORE THIS FILE: nothing modelled it. There was no quote window, no "all invited
-- suppliers answered", no record of a customer accepting another spec, and no close reason on
-- inquiries (status and lost_reason exist, unconstrained and unused). A deviation was only ever shown.
--
-- WHO DOES WHAT
--   sales_engineer   detects (deterministically, over quote_compare's technical comparison, in
--                    _shared/line_specs/no_exact_spec.ts), builds the alternatives, decides.
--   customer_support sends every message (WhatsApp and email, the customer's registered language)
--                    through _shared/deliver.ts; the portal shows the same question with quick replies.
--
-- THE LOOP (public.spec_alternative_offer, one row per line and mandatory attribute)
--   open      -> the question went out; reply_by = opened_at + spec_offer_reply_window_hours
--   accepted  -> recorded on the inquiry (inquiries.accepted_alternatives: which option, when, which
--                channel) and the comparison treats the chosen value as the customer's own request
--   declined  -> apology; inquiry closed, lost_reason 'no_exact_spec_declined'; nothing is charged
--   no_reply  -> after the final reminder and past reply_by: apology; lost_reason 'no_exact_spec_no_reply'
--   superseded-> another offer on the same inquiry was declined or lapsed, which closed the inquiry
--
-- THE CLOCK is resilience_ping (GitHub Actions, scheduled), the loop every seat's ticks already ride;
-- no pg_cron job is added (cron.job holds only wa_flush). Reminders fire on the first tick after
-- opened_at + each spec_offer_reminder_after_hours; the offer lapses on the first tick past reply_by.
--
-- WHO MAY ANSWER ON WHATSAPP: only a customer with a VERIFIED number and an open offer; a number two
-- such customers share records nothing and opens a support_case for customer_support instead. Which
-- customer a sender is, is decided in ONE place, fn_customer_by_whatsapp_sender (verified mobile
-- today; the WhatsApp-number build extends it to a verified whatsapp_phone).
-- WHEN AN INQUIRY IS CHECKED: not before it has at least one non-draft quote (stated in the query).
--
-- WHAT THIS DOES NOT DO: it does not message anyone (the edge sweep does, through customer_support),
-- it does not trigger when any eligible quote matches the requested value (then a differing quote is
-- only shown as "This is what the supplier quoted in writing"), and it never stores which supplier
-- offered an alternative: the alternatives column can hold option_id, value and a supplier COUNT only,
-- enforced by a CHECK below.
--
-- Applied with: node scripts/apply_sql.mjs scripts/sql/no_supplier_quoted_the_exact_spec_so_the_customer_is_offered_what_was.sql --apply --ddl
-- Proved by:    scripts/checks/no_exact_spec_offer_yes_no_silence.test.mjs (demo data, rolled back)

-- ── POLICY ────────────────────────────────────────────────────────────────────────────────────────
insert into public.decision_policy (key, value, description, updated_at) values
  ('spec_offer_quote_window_days', '7'::jsonb, 'Days after the first supplier invitation before the no-exact-spec check runs, if not every invited supplier has quoted sooner (founder_instruction #321).', now()),
  ('spec_offer_reply_window_hours', '72'::jsonb, 'Hours the customer has to answer the no-exact-spec offer before it lapses as no reply (founder_instruction #321).', now()),
  ('spec_offer_reminder_after_hours', '[24, 48]'::jsonb, 'Hours after the offer at which customer_support reminds the customer; the last one is the final reminder (founder_instruction #321).', now())
on conflict (key) do nothing;

-- ── THE INQUIRY CARRIES WHAT THE CUSTOMER ACCEPTED ───────────────────────────────────────────────
alter table public.inquiries add column if not exists accepted_alternatives jsonb not null default '[]'::jsonb;
alter table public.inquiries add column if not exists spec_offer_checked_at timestamptz;
comment on column public.inquiries.accepted_alternatives is
  'No-exact-spec offers the customer accepted: [{offer_id, line_no, attr, requested, accepted, option_id, at, channel}]. compare.ts treats accepted as the customer''s own value for that line and attribute (founder_instruction #321).';
comment on column public.inquiries.spec_offer_checked_at is
  'When sales_engineer ran the no-exact-spec check on this inquiry. Checked once, when the quote window closed or every invited supplier had quoted.';

-- ── THE OFFER ─────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.spec_alternative_offer (
  id               bigserial primary key,
  inquiry_id       uuid not null references public.inquiries(id) on delete cascade,
  customer_id      uuid references public.customers(id) on delete set null,
  line_no          integer not null,
  item             text,
  attr             text not null,
  label_en         text not null,
  label_ar         text not null,
  requested        text not null,
  alternatives     jsonb not null,
  state            text not null default 'open',
  reminders_sent   integer not null default 0,
  last_sent_at     timestamptz,
  reply_by         timestamptz not null,
  accepted_option  text,
  accepted_value   text,
  answered_at      timestamptz,
  answer_channel   text,
  closed_reason    text,
  notification_ids jsonb not null default '[]'::jsonb,
  owner_seat       text not null default 'sales_engineer',
  messenger_seat   text not null default 'customer_support',
  opened_at        timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint spec_alternative_offer_state_check check (state in ('open', 'accepted', 'declined', 'no_reply', 'superseded')),
  constraint spec_alternative_offer_channel_check check (answer_channel is null or answer_channel in ('portal', 'whatsapp', 'email')),
  constraint spec_alternative_offer_reason_check check (closed_reason is null or closed_reason in ('no_exact_spec_declined', 'no_exact_spec_no_reply')),
  constraint spec_alternative_offer_seats_check check (owner_seat = 'sales_engineer' and messenger_seat = 'customer_support'),
  -- NO SUPPLIER IDENTITY, structurally: an array of objects whose only keys are option_id, value and
  -- suppliers (a count). A quote id, a lead id, a label or a name has nowhere to go.
  constraint spec_alternative_offer_alternatives_shape check (
    jsonb_typeof(alternatives) = 'array' and jsonb_array_length(alternatives) >= 1
    and not jsonb_path_exists(alternatives, '$[*] ? (@.type() != "object")')
    and not jsonb_path_exists(alternatives, '$[*].keyvalue() ? (@.key != "option_id" && @.key != "value" && @.key != "suppliers")')
    and not jsonb_path_exists(alternatives, '$[*].suppliers ? (@.type() != "number")'))
);
create unique index if not exists spec_alternative_offer_one_live_per_attr
  on public.spec_alternative_offer (inquiry_id, line_no, attr) where state in ('open', 'accepted');
create index if not exists spec_alternative_offer_open_idx on public.spec_alternative_offer (state, reply_by) where state = 'open';
alter table public.spec_alternative_offer enable row level security;
drop policy if exists spec_alternative_offer_service_role_only on public.spec_alternative_offer;
create policy spec_alternative_offer_service_role_only on public.spec_alternative_offer
  as permissive for all to public using (false) with check (false);
revoke all on public.spec_alternative_offer from anon, authenticated;
revoke all on sequence public.spec_alternative_offer_id_seq from anon, authenticated;

-- ── CREDENTIAL SCOPES: exactly the two new hops ───────────────────────────────────────────────────
-- resilience_ping -> sales_engineer (the daily sweep); sales_engineer -> quote_compare (the technical
-- comparison the detection reads, the same one the customer sees).
update public.internal_credential set scope = (select array_agg(distinct s order by s) from unnest(scope || array['sales_engineer']) s)
 where context = 'fn.resilience_ping' and active and not ('sales_engineer' = any(scope));
update public.internal_credential set scope = (select array_agg(distinct s order by s) from unnest(scope || array['quote_compare']) s)
 where context = 'fn.sales_engineer' and active and not ('quote_compare' = any(scope));

-- ── WHICH INQUIRIES ARE READY TO BE CHECKED ───────────────────────────────────────────────────────
-- Not yet checked, not closed, nothing revealed, at least one live quote, and either every invited
-- supplier has quoted or the quote window has closed.
create or replace function public.fn_spec_offer_candidates(p_limit integer default 20)
returns table (inquiry_id uuid, customer_id uuid, why text)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with pol as (select coalesce((select (value #>> '{}')::numeric from public.decision_policy where key = 'spec_offer_quote_window_days'), 7) as days),
  inv as (
    select m.inquiry_id, count(distinct m.supplier_id) as invited, min(m.sent_at) as first_sent
      from public.inquiry_matches m group by m.inquiry_id),
  quoted as (
    select q.inquiry_id, count(distinct q.supplier_id) as quoted
      from public.quotes q where coalesce(q.status, '') <> 'draft' group by q.inquiry_id)
  select i.id, i.customer_id,
         case when coalesce(qd.quoted, 0) >= inv.invited then 'every_invited_supplier_quoted' else 'quote_window_closed' end
    from public.inquiries i
    join inv on inv.inquiry_id = i.id
    left join quoted qd on qd.inquiry_id = i.id
   where i.spec_offer_checked_at is null
     and coalesce(i.status, '') not in ('closed', 'completed', 'cancelled')
     and i.parent_inquiry_id is null
     -- THE TIMING GUARD, stated rather than implied by a join (review of #652): at least one live
     -- (non-draft) quote. An inquiry whose window closed with no quote at all is not a case of "no
     -- supplier quoted your exact spec": there is nothing to offer, and checking it would mark it
     -- checked before any quote could arrive.
     and exists (select 1 from public.quotes q1 where q1.inquiry_id = i.id and coalesce(q1.status, '') <> 'draft')
     and not exists (select 1 from public.transactions t join public.quotes q2 on q2.id = t.quote_id where q2.inquiry_id = i.id)
     and (coalesce(qd.quoted, 0) >= inv.invited or now() >= inv.first_sent + make_interval(days => (select days from pol)::int))
   order by i.created_at
   limit greatest(1, least(p_limit, 100));
$fn$;
revoke execute on function public.fn_spec_offer_candidates(integer) from public, anon, authenticated;

-- ── OPEN THE OFFERS (and mark the inquiry checked, offers or none) ────────────────────────────────
create or replace function public.fn_spec_offer_open(p_inquiry uuid, p_offers jsonb)
returns setof public.spec_alternative_offer
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_hours numeric := coalesce((select (value #>> '{}')::numeric from public.decision_policy where key = 'spec_offer_reply_window_hours'), 72);
  v_cust uuid;
  o jsonb;
begin
  select customer_id into v_cust from public.inquiries where id = p_inquiry for update;
  if not found then raise exception 'spec offer: no inquiry %', p_inquiry; end if;
  update public.inquiries set spec_offer_checked_at = coalesce(spec_offer_checked_at, now()) where id = p_inquiry;
  for o in select * from jsonb_array_elements(coalesce(p_offers, '[]'::jsonb)) loop
    insert into public.spec_alternative_offer (inquiry_id, customer_id, line_no, item, attr, label_en, label_ar, requested, alternatives, reply_by)
    values (p_inquiry, v_cust, (o->>'line_no')::int, o->>'item', o->>'attr', o->>'label_en', o->>'label_ar', o->>'requested', o->'alternatives',
            now() + make_interval(secs => (v_hours * 3600)::int))
    on conflict (inquiry_id, line_no, attr) where state in ('open', 'accepted') do nothing;
  end loop;
  return query select * from public.spec_alternative_offer where inquiry_id = p_inquiry and state = 'open' order by line_no, attr;
end;
$fn$;
revoke execute on function public.fn_spec_offer_open(uuid, jsonb) from public, anon, authenticated;

-- ── CLOSING AN INQUIRY THE CUSTOMER WILL NOT PROCEED WITH ────────────────────────────────────────
create or replace function public.fn_spec_offer_close_inquiry(p_inquiry uuid, p_reason text, p_except bigint)
returns void
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if p_reason not in ('no_exact_spec_declined', 'no_exact_spec_no_reply') then raise exception 'spec offer: bad close reason %', p_reason; end if;
  update public.spec_alternative_offer set state = 'superseded', updated_at = now()
   where inquiry_id = p_inquiry and state = 'open' and id <> p_except;
  -- Nothing was revealed (a candidate never has a transaction), so nothing is charged.
  update public.inquiries set status = 'closed', lost_reason = p_reason, stage_changed_at = now() where id = p_inquiry;
end;
$fn$;
revoke execute on function public.fn_spec_offer_close_inquiry(uuid, text, bigint) from public, anon, authenticated;

-- ── THE CUSTOMER ANSWERS (portal, WhatsApp or email) ─────────────────────────────────────────────
create or replace function public.fn_spec_offer_answer(p_offer bigint, p_customer uuid, p_choice text, p_channel text)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  r public.spec_alternative_offer;
  v_alt jsonb;
  v_choice text := lower(btrim(coalesce(p_choice, '')));
begin
  if p_channel not in ('portal', 'whatsapp', 'email') then return jsonb_build_object('ok', false, 'error', 'bad_channel'); end if;
  select * into r from public.spec_alternative_offer where id = p_offer for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.customer_id is distinct from p_customer then return jsonb_build_object('ok', false, 'error', 'not_your_offer'); end if;
  if r.state <> 'open' then return jsonb_build_object('ok', false, 'error', 'not_open', 'state', r.state); end if;

  if v_choice in ('no', 'decline', 'declined') then
    update public.spec_alternative_offer set state = 'declined', closed_reason = 'no_exact_spec_declined', answered_at = now(),
           answer_channel = p_channel, updated_at = now() where id = r.id;
    perform public.fn_spec_offer_close_inquiry(r.inquiry_id, 'no_exact_spec_declined', r.id);
    return jsonb_build_object('ok', true, 'state', 'declined', 'offer_id', r.id, 'inquiry_id', r.inquiry_id, 'customer_id', r.customer_id, 'inquiry_closed', true);
  end if;

  select a into v_alt from jsonb_array_elements(r.alternatives) a where a->>'option_id' = v_choice limit 1;
  if v_alt is null then return jsonb_build_object('ok', false, 'error', 'unknown_option'); end if;
  update public.spec_alternative_offer set state = 'accepted', accepted_option = v_alt->>'option_id', accepted_value = v_alt->>'value',
         answered_at = now(), answer_channel = p_channel, updated_at = now() where id = r.id;
  update public.inquiries
     set accepted_alternatives = coalesce(accepted_alternatives, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
           'offer_id', r.id, 'line_no', r.line_no, 'attr', r.attr, 'requested', r.requested,
           'accepted', v_alt->>'value', 'option_id', v_alt->>'option_id', 'at', now(), 'channel', p_channel))
   where id = r.inquiry_id;
  return jsonb_build_object('ok', true, 'state', 'accepted', 'offer_id', r.id, 'inquiry_id', r.inquiry_id, 'customer_id', r.customer_id,
    'accepted_value', v_alt->>'value', 'still_open', (select count(*) from public.spec_alternative_offer where inquiry_id = r.inquiry_id and state = 'open'));
end;
$fn$;
revoke execute on function public.fn_spec_offer_answer(bigint, uuid, text, text) from public, anon, authenticated;

-- ── WHICH CUSTOMER A WHATSAPP SENDER IS ─────────────────────────────────────────────────────────
-- THE ONE PLACE THAT DECIDES IT. Today: a customer whose MOBILE is verified (customers.phone_verified)
-- and equals the sender's number, digits only. The founder wants customers able to use WhatsApp on a
-- number other than their mobile (coordinator, 14 Sep 2026); that build adds customers.whatsapp_phone,
-- whatsapp_verified_at and whatsapp_opt and EXTENDS THIS FUNCTION, and no caller changes: prefer a
-- verified whatsapp_phone when present, else the verified mobile when whatsapp_opt = 'same'. Callers
-- must never match a sender to a customer any other way. Returns every customer the number identifies;
-- more than one is the caller's to treat as ambiguous.
create or replace function public.fn_customer_by_whatsapp_sender(p_phone text)
returns setof uuid
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select c.id from public.customers c
   where length(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g')) >= 8
     and c.phone_verified is true
     and regexp_replace(coalesce(c.phone, ''), '\D', '', 'g') = regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
$fn$;
revoke execute on function public.fn_customer_by_whatsapp_sender(text) from public, anon, authenticated;

-- ── A WHATSAPP REPLY: "2", "٢", "option 2", "yes" (one option), "no", "لا" ─────────────────────
-- WHO MAY ANSWER (review of #652, 14 Sep 2026): only a customer whose phone is VERIFIED
-- (customers.phone_verified) and who HAS an open offer. A number is not an identity (a phone may
-- confirm, never select), so: none such -> not a reply, the normal WhatsApp route continues; exactly
-- one -> their oldest open offer; two or more -> NOTHING is recorded, and a support_case is opened for
-- customer_support to resolve by hand (one per number per day), because answering for the wrong
-- customer would accept or close their request. Anything that is not an answer is left to the
-- normal route (handled=false).
create or replace function public.fn_spec_offer_whatsapp_reply(p_phone text, p_text text)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
  -- Who the sender is: fn_customer_by_whatsapp_sender alone decides (verified numbers only).
  select count(*), min(s.id::text)::uuid into v_matches, v_cust
    from public.fn_customer_by_whatsapp_sender(p_phone) as s(id)
   where exists (select 1 from public.spec_alternative_offer o where o.customer_id = s.id and o.state = 'open');
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
$fn$;
revoke execute on function public.fn_spec_offer_whatsapp_reply(text, text) from public, anon, authenticated;

-- ── WHAT THE DAILY TICK HAS TO DO ─────────────────────────────────────────────────────────────────
create or replace function public.fn_spec_offer_due()
returns table (offer_id bigint, action text, reminder_no integer, final boolean)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with pol as (select coalesce((select value from public.decision_policy where key = 'spec_offer_reminder_after_hours'), '[24,48]'::jsonb) as hrs)
  select o.id,
         case when now() >= o.reply_by and o.reminders_sent >= jsonb_array_length((select hrs from pol)) then 'close_no_reply' else 'remind' end,
         o.reminders_sent + 1,
         o.reminders_sent + 1 = jsonb_array_length((select hrs from pol))
    from public.spec_alternative_offer o
   where o.state = 'open' and o.last_sent_at is not null
     and (
       (o.reminders_sent < jsonb_array_length((select hrs from pol))
        and now() >= o.opened_at + make_interval(secs => ((select hrs from pol) ->> o.reminders_sent)::numeric::int * 3600))
       or (now() >= o.reply_by and o.reminders_sent >= jsonb_array_length((select hrs from pol))))
   order by o.opened_at;
$fn$;
revoke execute on function public.fn_spec_offer_due() from public, anon, authenticated;

-- ── RECORD WHAT WAS SENT, OR LAPSE THE OFFER ──────────────────────────────────────────────────────
create or replace function public.fn_spec_offer_mark(p_offer bigint, p_action text, p_notification_ids jsonb default '[]'::jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.spec_alternative_offer;
begin
  select * into r from public.spec_alternative_offer where id = p_offer for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_action = 'sent' then
    update public.spec_alternative_offer set last_sent_at = now(), notification_ids = notification_ids || coalesce(p_notification_ids, '[]'::jsonb), updated_at = now() where id = r.id;
  elsif p_action = 'remind' then
    if r.state <> 'open' then return jsonb_build_object('ok', false, 'error', 'not_open', 'state', r.state); end if;
    update public.spec_alternative_offer set reminders_sent = reminders_sent + 1, last_sent_at = now(),
           notification_ids = notification_ids || coalesce(p_notification_ids, '[]'::jsonb), updated_at = now() where id = r.id;
  elsif p_action = 'close_no_reply' then
    if r.state <> 'open' then return jsonb_build_object('ok', false, 'error', 'not_open', 'state', r.state); end if;
    update public.spec_alternative_offer set state = 'no_reply', closed_reason = 'no_exact_spec_no_reply',
           notification_ids = notification_ids || coalesce(p_notification_ids, '[]'::jsonb), updated_at = now() where id = r.id;
    perform public.fn_spec_offer_close_inquiry(r.inquiry_id, 'no_exact_spec_no_reply', r.id);
  elsif p_action = 'answered' then
    update public.spec_alternative_offer set notification_ids = notification_ids || coalesce(p_notification_ids, '[]'::jsonb), updated_at = now() where id = r.id;
  else
    return jsonb_build_object('ok', false, 'error', 'bad_action');
  end if;
  return jsonb_build_object('ok', true, 'offer_id', r.id, 'action', p_action);
end;
$fn$;
revoke execute on function public.fn_spec_offer_mark(bigint, text, jsonb) from public, anon, authenticated;
