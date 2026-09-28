-- EVERY SUPPORT CONVERSATION IS ONE CASE, MEASURED, RATED AND RECOVERED — customer_support, 28 Sep 2026.
-- Assigned: customer_support. The founder's standard is "better than Amazon".
--
-- WHAT WAS THERE (measured 28 Sep 2026 on htdblwldjkcgjvmqkbeh): public.support_case and public.feedback
-- existed with 0 rows each. Only fn_wa_problem_report (the WhatsApp "report a problem" menu) ever opened a
-- case; an email, a widget chat or any other WhatsApp message opened nothing, so first-reply time,
-- resolution, reopen, satisfaction and first-contact resolution were unmeasurable on every channel.
--
-- WHAT THIS BUILDS
--   1. public.support_customer_profile — ONE profile per person, keyed by customer id, supplier (lead) id,
--      email and the last nine phone digits, so a customer who writes by email and then by WhatsApp lands
--      on the same profile and the same open case.
--   2. support_case gains channel(s), first-reply time, contact/message counts, resolution, reopen count,
--      a generated first-contact-resolution flag, a CSAT request stamp and a service-recovery link.
--   3. fn_support_touch — the ONE door every inbound path goes through. Wired by triggers on the stores the
--      paths already write, so no writer can skip it:
--        wa_inbound      -> public.wa_messages      (inbound = customer message, sent reply = our reply)
--        resend_inbound  -> public.inbound_messages (a support mail becomes a case once email_triage
--        email_triage       triages it; replied_at is our reply)
--        site_assistant  -> public.assistant_logs   (signed-in widget chats; an anonymous visitor has no
--                                                    identity to hold a case against)
--        portals         -> the portal chat IS the assistant: sales_engineer 'assist' (customer portal) and
--                           the ChatWidget's site_assistant on portal pages (supplier portal) both write
--                           assistant_logs with the verified 'customer:<uuid>' / 'supplier:<lead id>' and a
--                           portal path, so those rows open channel 'portal'. A portal rating goes through
--                           action 'support_rating' on either function -> fn_support_portal_rate.
--   4. Feedback after resolution: closing a case queues ONE CSAT + CES question on the channel the customer
--      last used; a reply "4" or "4 6" (Arabic digits too) on WhatsApp or email is recorded into
--      public.feedback against the case. fn_support_feedback_record takes it from a portal.
--   5. Reopen: a message naming a closed case's reference within the reopen window reopens that case.
--   6. Complaint follow-up: a CSAT of 1 or 2 opens a service_recovery case linked to the original.
--   7. customer_support.case_idle_close duty: a case waiting on the customer with no reply for
--      support_case_append_days (default 7) closes as resolved, which asks for the rating.
--
-- A trigger here must never refuse the message it watches: every wire catches its own error and raises a
-- WARNING, so a defect in case keeping cannot lose a customer's WhatsApp or email.
--
-- Proved by scripts/sql/every_support_conversation_is_one_case_measured_rated_and_recovered_probe.sql
-- (aborted transaction on ZZ DEMO @example.invalid data; must print PROBE OK).

-- ── 1. the single profile ────────────────────────────────────────────────────────────────────────
create table if not exists public.support_customer_profile (
  id           bigint generated always as identity primary key,
  party_kind   text not null default 'unknown' check (party_kind in ('customer', 'supplier', 'unknown')),
  customer_id  uuid unique references public.customers(id) on delete set null,
  lead_id      bigint unique references public.leads(id) on delete set null,
  email        text check (email is null or email = lower(btrim(email))),
  phone_tail   text check (phone_tail is null or phone_tail ~ '^[0-9]{9}$'),
  display_name text,
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index if not exists support_customer_profile_email_idx on public.support_customer_profile (email);
create index if not exists support_customer_profile_phone_idx on public.support_customer_profile (phone_tail);
alter table public.support_customer_profile enable row level security;
drop policy if exists support_customer_profile_service_role_only on public.support_customer_profile;
create policy support_customer_profile_service_role_only on public.support_customer_profile
  as permissive for all to public using (false) with check (false);
revoke all on public.support_customer_profile from anon, authenticated;

-- ── 2. the case record ───────────────────────────────────────────────────────────────────────────
alter table public.support_case
  add column if not exists case_kind            text not null default 'support',
  add column if not exists customer_profile_id  bigint references public.support_customer_profile(id),
  add column if not exists channel              text,
  add column if not exists channels             text[] not null default '{}',
  add column if not exists last_channel         text,
  add column if not exists lang                 text,
  add column if not exists first_customer_msg_at timestamptz,
  add column if not exists last_inbound_at      timestamptz,
  add column if not exists first_reply_at       timestamptz,
  add column if not exists inbound_count        integer not null default 0,
  add column if not exists outbound_count       integer not null default 0,
  add column if not exists contact_count        integer not null default 0,
  add column if not exists resolution           text,
  add column if not exists resolved_at          timestamptz,
  add column if not exists reopen_count         integer not null default 0,
  add column if not exists reopened_at          timestamptz,
  add column if not exists csat_requested_at    timestamptz,
  add column if not exists csat_request_error   text,
  add column if not exists recovery_of_case_id  bigint references public.support_case(case_id);

alter table public.support_case
  add column if not exists first_reply_seconds numeric generated always as
    (extract(epoch from (first_reply_at - coalesce(first_customer_msg_at, opened_at)))) stored,
  -- First-contact resolution: closed, never reopened, and the customer needed ONE contact (a contact is a
  -- burst of messages; a gap of support_contact_gap_hours starts a new one). null while the case is open.
  add column if not exists fcr boolean generated always as
    (case when state = 'closed' then reopen_count = 0 and contact_count <= 1 end) stored;

do $$ begin
  alter table public.support_case add constraint support_case_kind_ck check (case_kind in ('support', 'service_recovery'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.support_case add constraint support_case_channel_ck
    check (channel is null or channel in ('whatsapp', 'email', 'widget', 'portal', 'phone', 'internal'));
exception when duplicate_object then null; end $$;
create index if not exists support_case_profile_open_idx on public.support_case (customer_profile_id) where state <> 'closed';

-- ── feedback is tied to its case ─────────────────────────────────────────────────────────────────
alter table public.feedback
  add column if not exists case_id    bigint references public.support_case(case_id),
  add column if not exists kind       text,
  add column if not exists channel    text,
  add column if not exists profile_id bigint references public.support_customer_profile(id);
do $$ begin
  -- CSAT 1-5 (5 = very satisfied); CES 1-7 (7 = very easy). Low is bad on both, which is what
  -- t_emit_customer_complaint (rating <= 2) already assumes.
  alter table public.feedback add constraint feedback_kind_scale_ck check (
    kind is null
    or (kind = 'csat' and rating between 1 and 5)
    or (kind = 'ces'  and rating between 1 and 7));
exception when duplicate_object then null; end $$;
create unique index if not exists feedback_one_per_case_kind on public.feedback (case_id, kind) where case_id is not null and kind is not null;

-- ── helpers ──────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_support_profile_resolve(p_kind text, p_party_id text, p_email text, p_phone text)
returns bigint
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_cust uuid; v_lead bigint; v_email text; v_tail text; v_name text; v_id bigint;
  v_kind text := case when p_kind in ('customer', 'supplier') then p_kind else 'unknown' end;
begin
  if v_kind = 'customer' and p_party_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_cust := p_party_id::uuid;
    select lower(btrim(c.email)), c.phone, c.full_name into v_email, p_phone, v_name
      from public.customers c where c.id = v_cust;
    v_email := coalesce(v_email, lower(btrim(p_email)));
  elsif v_kind = 'supplier' and p_party_id ~ '^[0-9]+$' then
    v_lead := p_party_id::bigint;
    select lower(btrim(l.email)), coalesce(l.phone_e164, l.phone), l.company_name into v_email, p_phone, v_name
      from public.leads l where l.id = v_lead;
    v_email := coalesce(v_email, lower(btrim(p_email)));
  else
    v_email := lower(btrim(p_email));
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+$' then v_email := null; end if;
  v_tail := right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9);
  if length(v_tail) < 9 then v_tail := null; end if;
  if v_cust is null and v_lead is null and v_email is null and v_tail is null then return null; end if;

  select p.id into v_id from public.support_customer_profile p
   where (v_cust is not null and p.customer_id = v_cust)
      or (v_lead is not null and p.lead_id = v_lead)
      or (v_email is not null and p.email = v_email)
      or (v_tail is not null and p.phone_tail = v_tail)
   order by (p.customer_id = v_cust) desc nulls last, (p.lead_id = v_lead) desc nulls last,
            (p.email = v_email) desc nulls last, p.id
   limit 1;

  if v_id is null then
    insert into public.support_customer_profile (party_kind, customer_id, lead_id, email, phone_tail, display_name)
    values (v_kind, v_cust, v_lead, v_email, v_tail, v_name) returning id into v_id;
  else
    update public.support_customer_profile p
       set party_kind   = case when p.party_kind = 'unknown' then v_kind else p.party_kind end,
           customer_id  = coalesce(p.customer_id, case when not exists (select 1 from public.support_customer_profile x where x.customer_id = v_cust) then v_cust end),
           lead_id      = coalesce(p.lead_id, case when not exists (select 1 from public.support_customer_profile x where x.lead_id = v_lead) then v_lead end),
           email        = coalesce(p.email, v_email),
           phone_tail   = coalesce(p.phone_tail, v_tail),
           display_name = coalesce(p.display_name, v_name),
           last_seen_at = now()
     where p.id = v_id;
  end if;
  return v_id;
end $fn$;
revoke execute on function public.fn_support_profile_resolve(text, text, text, text) from public, anon, authenticated;

-- A case opened by any other routine (fn_wa_problem_report, the refund and quote builds) joins its
-- profile and gets the lifecycle stamps; closing and reopening keep the resolution and reopen record.
create or replace function public.fn_support_case_lifecycle()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if tg_op = 'INSERT' then
    if new.customer_profile_id is null then
      new.customer_profile_id := public.fn_support_profile_resolve(new.party_kind, new.party_id,
        case when new.party_id ~ '@' then new.party_id end,
        case when new.party_id ~ '^\+?[0-9]{9,}$' then new.party_id end);
    end if;
    if new.channel is null and new.subject ilike 'WhatsApp%' then new.channel := 'whatsapp'; end if;
    if new.channel is not null then
      new.last_channel := coalesce(new.last_channel, new.channel);
      if not new.channel = any(new.channels) then new.channels := new.channels || new.channel; end if;
    end if;
    return new;
  end if;
  if new.state = 'closed' and old.state <> 'closed' then
    new.resolved_at := coalesce(new.closed_at, now());
    new.resolution  := coalesce(new.resolution, new.close_reason);
  elsif old.state = 'closed' and new.state <> 'closed' then
    new.reopen_count := old.reopen_count + 1;
    new.reopened_at  := now();
    new.closed_at := null; new.close_reason := null; new.resolved_at := null; new.resolution := null;
    new.csat_requested_at := null; new.csat_request_error := null;
    new.last_activity_at := now();
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_support_case_lifecycle() from public, anon, authenticated;
drop trigger if exists a10_support_case_lifecycle on public.support_case;
create trigger a10_support_case_lifecycle before insert or update of state on public.support_case
  for each row execute function public.fn_support_case_lifecycle();

create or replace function public.fn_support_case_new_ref()
returns text
language plpgsql volatile
set search_path to 'public', 'pg_temp'
as $fn$
declare
  alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';   -- the QD-S- alphabet fn_wa_problem_report uses
  v_bytes bytea := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
  v_ref text := 'QD-S-'; i int;
begin
  for i in 0..5 loop v_ref := v_ref || substr(alphabet, (get_byte(v_bytes, i) % 32) + 1, 1); end loop;
  return v_ref;
end $fn$;
revoke execute on function public.fn_support_case_new_ref() from public, anon, authenticated;

-- ── 4. feedback ──────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_support_feedback_record(p_case_ref text, p_csat numeric, p_ces numeric default null,
                                                             p_comment text default null, p_channel text default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_case public.support_case; n int := 0;
begin
  select * into v_case from public.support_case where case_ref = upper(btrim(p_case_ref));
  if not found then return jsonb_build_object('ok', false, 'reason', 'no case ' || coalesce(p_case_ref, '')); end if;
  if p_csat is not null then
    insert into public.feedback (source, subject_type, subject_id, rating, comment, case_id, kind, channel, profile_id)
    values ('support_case', 'support_case', v_case.case_ref, p_csat, left(p_comment, 2000), v_case.case_id, 'csat',
            coalesce(p_channel, v_case.last_channel), v_case.customer_profile_id)
    on conflict (case_id, kind) where case_id is not null and kind is not null do nothing;
    get diagnostics n = row_count;
  end if;
  if p_ces is not null then
    insert into public.feedback (source, subject_type, subject_id, rating, case_id, kind, channel, profile_id)
    values ('support_case', 'support_case', v_case.case_ref, p_ces, v_case.case_id, 'ces',
            coalesce(p_channel, v_case.last_channel), v_case.customer_profile_id)
    on conflict (case_id, kind) where case_id is not null and kind is not null do nothing;
  end if;
  return jsonb_build_object('ok', true, 'case_ref', v_case.case_ref, 'csat_recorded', n = 1);
end $fn$;
revoke execute on function public.fn_support_feedback_record(text, numeric, numeric, text, text) from public, anon, authenticated;

-- The portal door for a rating: the party is the VERIFIED session (site_assistant / sales_engineer
-- action 'support_rating'), and the case must belong to that party's profile.
create or replace function public.fn_support_portal_rate(p_party_kind text, p_party_id text, p_case_ref text,
                                                         p_csat numeric, p_ces numeric default null, p_comment text default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_prof bigint := public.fn_support_profile_resolve(p_party_kind, p_party_id, null, null);
begin
  if p_csat is not null and p_csat not between 1 and 5 then return jsonb_build_object('ok', false, 'reason', 'csat is 1 to 5'); end if;
  if p_ces is not null and p_ces not between 1 and 7 then return jsonb_build_object('ok', false, 'reason', 'ces is 1 to 7'); end if;
  if v_prof is null or not exists (select 1 from public.support_case c where c.case_ref = upper(btrim(p_case_ref))
                                      and c.customer_profile_id = v_prof and c.state = 'closed') then
    return jsonb_build_object('ok', false, 'reason', 'no closed case ' || coalesce(p_case_ref, '') || ' for this account');
  end if;
  return public.fn_support_feedback_record(p_case_ref, p_csat, p_ces, p_comment, 'portal');
end $fn$;
revoke execute on function public.fn_support_portal_rate(text, text, text, numeric, numeric, text) from public, anon, authenticated;

-- What the portal shows: this party's closed cases that asked for a rating in the last 14 days and have none.
create or replace function public.fn_support_rating_due(p_party_kind text, p_party_id text)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_prof bigint;
begin
  select p.id into v_prof from public.support_customer_profile p
   where (p_party_kind = 'customer' and p.customer_id::text = p_party_id)
      or (p_party_kind = 'supplier' and p.lead_id::text = p_party_id)
   limit 1;
  if v_prof is null then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('case_ref', c.case_ref, 'subject', left(c.subject, 140), 'closed_at', c.closed_at)
                                    order by c.closed_at desc)
                     from public.support_case c
                    where c.customer_profile_id = v_prof and c.state = 'closed'
                      and c.csat_requested_at > now() - interval '14 days'
                      and not exists (select 1 from public.feedback f where f.case_id = c.case_id and f.kind = 'csat')), '[]'::jsonb);
end $fn$;
revoke execute on function public.fn_support_rating_due(text, text) from public, anon, authenticated;

-- 6. A low CSAT opens a service-recovery case against the same person, linked to the case it recovers.
create or replace function public.fn_support_low_csat_opens_recovery()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_case public.support_case; v_ref text; attempt int := 0;
begin
  select * into v_case from public.support_case where case_id = new.case_id;
  -- a recovery case that is itself rated low is not recovered again in a loop; the complaint event
  -- (t_emit_customer_complaint) still records it for the CEO.
  if not found or v_case.case_kind = 'service_recovery' then return null; end if;
  if exists (select 1 from public.support_case r where r.recovery_of_case_id = v_case.case_id) then return null; end if;
  loop
    attempt := attempt + 1;
    begin
      v_ref := public.fn_support_case_new_ref();
      insert into public.support_case (case_ref, party_kind, party_id, inquiry_ref, subject, state, identity_verified,
                                       verified_how, owner_role_id, case_kind, customer_profile_id, channel, channels,
                                       last_channel, lang, recovery_of_case_id)
      values (v_ref, v_case.party_kind, v_case.party_id, v_case.inquiry_ref,
              'Service recovery: rated ' || new.rating::int || '/5 on ' || v_case.case_ref
                || coalesce(' — "' || left(new.comment, 500) || '"', ''),
              'open', v_case.identity_verified, v_case.verified_how, 'customer_support', 'service_recovery',
              v_case.customer_profile_id, v_case.last_channel,
              case when v_case.last_channel is null then '{}'::text[] else array[v_case.last_channel] end,
              v_case.last_channel, v_case.lang, v_case.case_id);
      exit;
    exception when unique_violation then
      if attempt >= 5 then raise; end if;
    end;
  end loop;
  return null;
end $fn$;
revoke execute on function public.fn_support_low_csat_opens_recovery() from public, anon, authenticated;
drop trigger if exists t_support_low_csat_opens_recovery on public.feedback;
create trigger t_support_low_csat_opens_recovery after insert on public.feedback
  for each row when (new.kind = 'csat' and new.rating <= 2 and new.case_id is not null)
  execute function public.fn_support_low_csat_opens_recovery();

-- ── 3. the one door ──────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_support_touch(
  p_channel text, p_direction text, p_party_kind text, p_party_id text,
  p_email text default null, p_phone text default null, p_text text default null,
  p_rating_text text default null, p_lang text default null)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_days int := greatest(1, public.fn_seat_clock_policy('support_case_append_days', 7)::int);
  v_reopen_days int := greatest(1, public.fn_seat_clock_policy('support_case_reopen_days', 14)::int);
  v_gap interval := make_interval(hours => greatest(1, public.fn_seat_clock_policy('support_contact_gap_hours', 4)::int));
  v_prof bigint; v_case public.support_case; v_closed public.support_case; v_id bigint; v_ref text;
  v_digits text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  v_party_kind text := case when p_party_kind in ('customer', 'supplier') then p_party_kind else 'unknown' end;
  v_party_id text; v_rt text; m text[]; attempt int := 0;
begin
  if p_direction not in ('in', 'out') then raise exception 'fn_support_touch: direction must be in or out'; end if;
  v_prof := public.fn_support_profile_resolve(v_party_kind, p_party_id, p_email, p_phone);
  if v_prof is null then return jsonb_build_object('ok', false, 'reason', 'no identity'); end if;

  select * into v_case from public.support_case
   where customer_profile_id = v_prof and state <> 'closed' order by last_activity_at desc limit 1;

  if p_direction = 'out' then
    if v_case.case_id is null then return jsonb_build_object('ok', true, 'case', null, 'reason', 'no open case'); end if;
    update public.support_case
       set first_reply_at = coalesce(first_reply_at, now()), outbound_count = outbound_count + 1,
           state = case when state in ('open', 'waiting_service') then 'waiting_customer' else state end,
           last_activity_at = now()
     where case_id = v_case.case_id;
    return jsonb_build_object('ok', true, 'case_ref', v_case.case_ref, 'direction', 'out');
  end if;

  -- A rating answering the CSAT question of a recently closed case.
  v_rt := btrim(translate(coalesce(p_rating_text, p_text, ''), '٠١٢٣٤٥٦٧٨٩', '0123456789'));
  m := regexp_match(v_rt, '^([1-5])(?:\s*[,/ -]\s*([1-7]))?$');
  if m is not null then
    select * into v_closed from public.support_case c
     where c.customer_profile_id = v_prof and c.state = 'closed' and c.csat_requested_at > now() - make_interval(days => v_days)
       and not exists (select 1 from public.feedback f where f.case_id = c.case_id and f.kind = 'csat')
     order by c.csat_requested_at desc limit 1;
    if v_closed.case_id is not null then
      perform public.fn_support_feedback_record(v_closed.case_ref, m[1]::numeric, m[2]::numeric, null, p_channel);
      return jsonb_build_object('ok', true, 'case_ref', v_closed.case_ref, 'rated', m[1]::int, 'ces', m[2]::int);
    end if;
  end if;

  -- 5. A message naming a recently closed case of this person reopens it.
  if v_case.case_id is null then
    select * into v_closed from public.support_case c
     where c.customer_profile_id = v_prof and c.state = 'closed' and c.closed_at > now() - make_interval(days => v_reopen_days)
       and position(c.case_ref in upper(coalesce(p_text, ''))) > 0
     order by c.closed_at desc limit 1;
    if v_closed.case_id is not null then
      update public.support_case set state = 'open' where case_id = v_closed.case_id;
      select * into v_case from public.support_case where case_id = v_closed.case_id;
    end if;
  end if;

  -- An open case idle past the append window is closed and a new one starts.
  if v_case.case_id is not null and v_case.last_activity_at < now() - make_interval(days => v_days) then
    update public.support_case set state = 'closed', closed_at = now(),
           close_reason = 'resolved — no further contact in ' || v_days || ' days (closed by customer_support)'
     where case_id = v_case.case_id;
    v_case := null;
  end if;

  if v_case.case_id is null then
    select case when p.customer_id is not null then 'customer' when p.lead_id is not null then 'supplier' else 'unknown' end,
           coalesce(p.customer_id::text, p.lead_id::text, case when v_digits <> '' then '+' || v_digits end, p.email)
      into v_party_kind, v_party_id
      from public.support_customer_profile p where p.id = v_prof;
    loop
      attempt := attempt + 1;
      begin
        v_ref := public.fn_support_case_new_ref();
        insert into public.support_case (case_ref, party_kind, party_id, subject, state, identity_verified, verified_how,
                                         owner_role_id, customer_profile_id, channel, lang)
        values (v_ref, v_party_kind, v_party_id,
                initcap(p_channel) || ': ' || left(coalesce(nullif(btrim(p_text), ''), '(no text)'), 4000),
                'open', v_party_kind <> 'unknown',
                case when v_party_kind <> 'unknown' then 'matched on the ' || p_channel || ' identity' end,
                'customer_support', v_prof, p_channel,
                case when p_lang in ('en', 'ar') then p_lang end)
        returning * into v_case;
        exit;
      exception when unique_violation then
        if attempt >= 5 then raise; end if;
      end;
    end loop;
  end if;

  update public.support_case
     set inbound_count = inbound_count + 1,
         contact_count = contact_count + case when last_inbound_at is null or last_inbound_at < now() - v_gap then 1 else 0 end,
         first_customer_msg_at = coalesce(first_customer_msg_at, now()),
         last_inbound_at = now(), last_activity_at = now(),
         last_channel = p_channel,
         channels = case when p_channel = any(channels) then channels else channels || p_channel end,
         lang = coalesce(lang, case when p_lang in ('en', 'ar') then p_lang end),
         state = case when state = 'waiting_customer' then 'open' else state end
   where case_id = v_case.case_id;
  return jsonb_build_object('ok', true, 'case_ref', v_case.case_ref, 'case_id', v_case.case_id, 'direction', 'in');
end $fn$;
revoke execute on function public.fn_support_touch(text, text, text, text, text, text, text, text, text) from public, anon, authenticated;

-- ── 4. closing asks for the rating ──────────────────────────────────────────────────────────────
create or replace function public.fn_support_case_closed_asks_for_the_rating()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_p public.support_customer_profile; v_lang text := coalesce(new.lang, 'en'); v_body text; v_err text; v_phone text;
begin
  if new.state <> 'closed' or old.state = 'closed' or new.csat_requested_at is not null then return null; end if;
  if exists (select 1 from public.feedback f where f.case_id = new.case_id and f.kind = 'csat') then return null; end if;
  select * into v_p from public.support_customer_profile where id = new.customer_profile_id;
  v_body := case when v_lang = 'ar'
    then 'كيف كانت خدمتنا في البلاغ ' || new.case_ref || E'؟\nأرسلوا رقماً من ١ (غير راضٍ) إلى ٥ (راضٍ جداً)، '
         || 'ويمكنكم إضافة رقم ثانٍ من ١ (صعب جداً) إلى ٧ (سهل جداً) لمدى سهولة حل المشكلة. مثال: ٥ ٧'
    else 'How did we do on case ' || new.case_ref || E'?\nReply with a number from 1 (unhappy) to 5 (very happy). '
         || 'You can add a second number from 1 (very hard) to 7 (very easy) for how easy it was to get it solved, e.g. "5 7".' end;
  if new.last_channel = 'whatsapp' then
    v_phone := coalesce(case when new.party_id ~ '^\+?[0-9]{9,}$' then new.party_id end,
                        (select coalesce(c.whatsapp_phone, c.phone) from public.customers c where c.id = v_p.customer_id),
                        (select coalesce(l.whatsapp_phone, l.phone_e164, l.phone) from public.leads l where l.id = v_p.lead_id));
  end if;
  begin
    if v_phone is not null then
      insert into public.notifications (type, kind, to_phone, to_role, channel, lang, subject, body, requested_by, sender)
      values ('support_csat_request', 'support_csat_request', v_phone, new.party_kind, 'whatsapp', v_lang, 'Case ' || new.case_ref || ' rating', v_body, 'customer_support', 'customer_support');
    elsif v_p.email is not null then
      insert into public.notifications (type, kind, to_email, to_role, channel, lang, subject, body, requested_by, sender)
      values ('support_csat_request', 'support_csat_request', v_p.email, new.party_kind, 'email', v_lang,
              case when v_lang = 'ar' then 'قيّموا خدمتنا في البلاغ ' || new.case_ref else 'How did we do? Case ' || new.case_ref end,
              v_body, 'customer_support', 'customer_support');
    else
      v_err := 'no channel to ask on';
    end if;
  exception when others then
    v_err := left(sqlerrm, 500);   -- a refused notice never undoes the close
  end;
  update public.support_case set csat_requested_at = case when v_err is null then now() end, csat_request_error = v_err
   where case_id = new.case_id;
  return null;
end $fn$;
revoke execute on function public.fn_support_case_closed_asks_for_the_rating() from public, anon, authenticated;
drop trigger if exists trg_support_case_closed_asks_for_the_rating on public.support_case;
create trigger trg_support_case_closed_asks_for_the_rating after update of state on public.support_case
  for each row execute function public.fn_support_case_closed_asks_for_the_rating();

-- ── the wires ───────────────────────────────────────────────────────────────────────────────────
-- wa_inbound -> wa_messages. The founder's own command channel is not a support conversation.
create or replace function public.fn_support_wire_whatsapp()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_kind text; v_cust uuid; v_lead bigint;
begin
  if coalesce(new.meta ->> 'audience', '') = 'founder' or coalesce(new.wa_from, '') = '' then return null; end if;
  begin
    select o.party_kind, o.customer_id, o.lead_id into v_kind, v_cust, v_lead from public.fn_whatsapp_owner(new.wa_from) o limit 1;
    if tg_op = 'INSERT' and nullif(btrim(new.inbound), '') is not null then
      perform public.fn_support_touch('whatsapp', 'in', v_kind, coalesce(v_cust::text, v_lead::text), null, new.wa_from,
                                      new.inbound, null, new.lang);
    end if;
    if new.reply is not null and new.sent and (tg_op = 'INSERT' or not coalesce(old.sent, false)) then
      perform public.fn_support_touch('whatsapp', 'out', v_kind, coalesce(v_cust::text, v_lead::text), null, new.wa_from);
    end if;
  exception when others then
    raise warning 'fn_support_wire_whatsapp: wa_messages % not recorded on a case: %', new.id, sqlerrm;
  end;
  return null;
end $fn$;
revoke execute on function public.fn_support_wire_whatsapp() from public, anon, authenticated;
drop trigger if exists z50_support_wire_whatsapp on public.wa_messages;
create trigger z50_support_wire_whatsapp after insert or update of sent on public.wa_messages
  for each row execute function public.fn_support_wire_whatsapp();

-- resend_inbound + email_triage -> inbound_messages. A mail becomes a case when email_triage has read it
-- and left it with support (no other owner, not spam, not a no-auto-reply sender); replied_at is our reply.
create or replace function public.fn_support_wire_email()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_from text := lower(substring(coalesce(new.from_email, '') from '([^<>\s"]+@[^<>\s"]+)'));
        v_kind text := 'unknown'; v_id text; v_first text;
begin
  if v_from is null or v_from ~ '@(mail\.)?quotesdone\.(com|ae)$' then return null; end if;
  if coalesce(new.owner_role, 'customer_support') <> 'customer_support' then return null; end if;
  begin
    select 'customer', c.id::text into v_kind, v_id from public.customers c where lower(btrim(c.email)) = v_from limit 1;
    if v_id is null then
      select 'supplier', l.id::text into v_kind, v_id from public.leads l where lower(btrim(l.email)) = v_from order by l.id limit 1;
    end if;
    v_kind := coalesce(v_kind, 'unknown');
    if new.triaged_at is not null and old.triaged_at is null
       and coalesce(new.ai_category, '') not in ('spam', 'no_auto_reply', 'glm_queued') then
      v_first := substring(coalesce(new.body, '') from '^\s*([^\r\n]*)');
      perform public.fn_support_touch('email', 'in', v_kind, v_id, v_from, null,
                                      coalesce(new.subject, '') || E'\n' || coalesce(new.body, ''), v_first, null);
    end if;
    if new.replied_at is not null and old.replied_at is null then
      perform public.fn_support_touch('email', 'out', v_kind, v_id, v_from);
    end if;
  exception when others then
    raise warning 'fn_support_wire_email: inbound_messages % not recorded on a case: %', new.id, sqlerrm;
  end;
  return null;
end $fn$;
revoke execute on function public.fn_support_wire_email() from public, anon, authenticated;
drop trigger if exists z50_support_wire_email on public.inbound_messages;
create trigger z50_support_wire_email after update of triaged_at, replied_at on public.inbound_messages
  for each row execute function public.fn_support_wire_email();

-- site_assistant (the ChatWidget on every page, both portals included) and sales_engineer 'assist' (the
-- customer portal assistant) -> assistant_logs. audience is 'customer:<uuid>' or 'supplier:<lead id>' for a
-- verified session (site_assistant wrote 'customer:session' until this change and now writes the id).
-- The channel is 'portal' when the chat happened inside a portal: sales_engineer logs path 'portal', the
-- widget logs the page path (/me, /portal, /supplier, with or without the locale).
create or replace function public.fn_support_wire_widget()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_kind text := split_part(coalesce(new.audience, ''), ':', 1); v_id text := split_part(coalesce(new.audience, ''), ':', 2);
        v_ch text := case when coalesce(new.path, '') = 'portal'
                            or coalesce(new.path, '') ~ '^(/(en|ar))?/(me|portal|supplier)(/|$|\?)' then 'portal' else 'widget' end;
begin
  if not ((v_kind = 'customer' and v_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
          or (v_kind = 'supplier' and v_id ~ '^[0-9]+$')) then
    return null;
  end if;
  begin
    if nullif(btrim(new.message), '') is not null then
      perform public.fn_support_touch(v_ch, 'in', v_kind, v_id, null, null, new.message);
    end if;
    if new.reply is not null and new.answered is distinct from false then
      perform public.fn_support_touch(v_ch, 'out', v_kind, v_id);
    end if;
  exception when others then
    raise warning 'fn_support_wire_widget: assistant_logs % not recorded on a case: %', new.id, sqlerrm;
  end;
  return null;
end $fn$;
revoke execute on function public.fn_support_wire_widget() from public, anon, authenticated;
drop trigger if exists z50_support_wire_widget on public.assistant_logs;
create trigger z50_support_wire_widget after insert on public.assistant_logs
  for each row execute function public.fn_support_wire_widget();

-- ── 7. the idle-close duty ──────────────────────────────────────────────────────────────────────
create or replace function public.fn_support_case_idle_close()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_days int := greatest(1, public.fn_seat_clock_policy('support_case_append_days', 7)::int); n int;
begin
  update public.support_case
     set state = 'closed', closed_at = now(),
         close_reason = 'resolved — answered, and no reply from the customer in ' || v_days || ' days (closed by customer_support)'
   where state = 'waiting_customer' and last_activity_at < now() - make_interval(days => v_days);
  get diagnostics n = row_count;
  return jsonb_build_object('closed', n);
end $fn$;
revoke execute on function public.fn_support_case_idle_close() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.case_idle_close', 'customer_support', interval '1 hour', 'fn_support_case_idle_close',
   'close a case we answered that the customer has not replied to in support_case_append_days, which asks for the CSAT rating',
   'scripts/sql/every_support_conversation_is_one_case_measured_rated_and_recovered.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- ── what the seat and the CEO read ──────────────────────────────────────────────────────────────
create or replace view public.v_support_customer_profile with (security_invoker = true) as
select p.id as profile_id, p.party_kind, p.customer_id, p.lead_id, p.email, p.phone_tail, p.display_name,
       count(c.case_id) as cases, count(c.case_id) filter (where c.state <> 'closed') as open_cases,
       array_agg(c.case_ref order by c.opened_at desc) filter (where c.case_id is not null) as case_refs,
       (select array_agg(distinct ch) from public.support_case c2, unnest(c2.channels) ch where c2.customer_profile_id = p.id) as channels,
       round(avg(r.csat), 2) as csat_avg, round(avg(r.ces), 2) as ces_avg,
       max(c.last_activity_at) as last_activity_at
  from public.support_customer_profile p
  left join public.support_case c on c.customer_profile_id = p.id
  left join lateral (select max(f.rating) filter (where f.kind = 'csat') as csat, max(f.rating) filter (where f.kind = 'ces') as ces
                       from public.feedback f where f.case_id = c.case_id) r on true
 group by p.id;
revoke all on public.v_support_customer_profile from anon, authenticated;

create or replace view public.v_support_case_metrics with (security_invoker = true) as
select date_trunc('day', c.opened_at) as day, c.channel,
       count(*) as opened,
       count(*) filter (where c.state = 'closed') as closed,
       round((percentile_cont(0.5) within group (order by c.first_reply_seconds) / 60)::numeric, 1) as median_first_reply_minutes,
       round(avg(c.fcr::int) * 100, 1) as fcr_pct,
       round(avg((c.reopen_count > 0)::int) filter (where c.state = 'closed') * 100, 1) as reopen_pct,
       round(avg(r.csat), 2) as csat_avg, count(r.csat) as csat_responses,
       round(avg(r.ces), 2) as ces_avg,
       count(*) filter (where c.case_kind = 'service_recovery') as service_recovery_cases
  from public.support_case c   -- feedback folded per case, so a CSAT and a CES never count a case twice
  left join lateral (select max(f.rating) filter (where f.kind = 'csat') as csat, max(f.rating) filter (where f.kind = 'ces') as ces
                       from public.feedback f where f.case_id = c.case_id) r on true
 group by 1, 2;
revoke all on public.v_support_case_metrics from anon, authenticated;
