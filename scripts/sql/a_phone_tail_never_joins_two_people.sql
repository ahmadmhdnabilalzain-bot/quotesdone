-- a_phone_tail_never_joins_two_people.sql — customer_support seat (built by agent PROFILE_SPLIT, 16 Nov 2026).
--
-- THE HOLE (review of b5d137290, item 2, proved on a local Postgres 16): fn_support_profile_resolve joined two different people
-- into ONE support profile when the last nine digits of their phones agreed, although each carried a different e-mail and
-- customer id (+971 5x xxx xxxx and +999 5x xxx xxxx have the same tail). The second person's replies then read the first
-- person's cases, summaries and promises (fn_support_open_cases: up to 5 cases). A privacy breach (UAE PDPL) and, before a
-- reveal, an anonymity breach. The estate's own rule says why: email is the identity, and a phone deliberately repeats, so A
-- PHONE MAY CONFIRM AN IDENTITY AND NEVER SELECT ONE (.claude/memory/a-phone-may-confirm-never-select.md, 13 Aug 2026).
--
-- WHAT IS NOW TRUE.
--   1. fn_support_profile_resolve. A profile is found by the account (customer id, lead id), then by the mailbox, unless that
--      profile is a different account. A number joins a profile only when the number confirms (the handset the message came
--      from, or a customer's or supplier's VERIFIED number) and only a profile that carries no e-mail, customer or lead of its
--      own (a WhatsApp handset nobody has named yet), with the same country prefix. A handset with no other name first asks
--      who the number's confirmed owner is (fn_whatsapp_owner: one party or nobody), so a confirmed customer writing on
--      WhatsApp still reads the same profile his portal and e-mail cases are on. When two different strong identities meet
--      on one number or one mailbox a SEPARATE profile is opened and the IT engineer is told (finding
--      customer_support:profile_identity_collision:<new profile>); nothing is ever merged silently. The same person writing
--      on WhatsApp and then by e-mail (no conflicting identity, verified number) is still one profile.
--   2. support_customer_profile.phone_prefix: the digits before the tail (country code), so two handsets that share a tail
--      across countries stay two profiles. Only the prefix is kept, never the whole number.
--   3. fn_whatsapp_owner (reply path: fn_identify_contact, fn_wa_context, fn_conversation_party, the support wiring): a
--      verified number names its owner only when the country prefixes agree too. Otherwise identical (sanctions clause kept).
--   4. fn_support_case_summaries_owed: the catch-up rebuilds a summary from the WhatsApp turns read BY TAIL
--      (support_case_memory.ts catchUpOwedSummaries); a tail that two profiles share is no longer owed there, so one person's
--      words never enter another's summary. The in-turn retries and the finding still cover it.
--   5. fn_contact_timeline_for_sender (new; wa_inbound/identify.ts reads it): fn_contact_timeline matched every customer and
--      supplier whose UNVERIFIED phone shares the sender's tail and put their requests, cases and messages into the reply's
--      prompt as "THIS SENDER'S CASE TIMELINE ... theirs only". The wrapper reads the timeline of the number's confirmed owner
--      (by their e-mail), or, with no confirmed owner, only what this very number exchanged with us. fn_contact_timeline is
--      left untouched (sales_engineer-every-door-reads-the-same-case redefines it).
--   6. The repair, never run by this file: fn_support_profile_collisions() lists profiles joined before today (ids and counts
--      only) and fn_support_profile_split(...) moves the cases a reviewer names to their own profile, dry run by default.
--
-- MEASURED ON PRODUCTION 16 Nov 2026 (SELECT counts only): 29 profiles, 30 cases; 0 tails and 0 e-mails shared by two profiles;
-- 0 profiles whose WhatsApp numbers carry two country prefixes; 0 profiles holding a second registered identity; 1 latent pair
-- (a customer profile whose tail one supplier lead with a different e-mail shares; the lead has written twice, neither message
-- reached support, so they were never joined). The three redefined bodies equal production (pg_get_functiondef md5
-- fn_support_profile_resolve 52219a85..., fn_whatsapp_owner 534bb745..., fn_support_case_summaries_owed 29f45135...).
-- Probe: a_phone_tail_never_joins_two_people_probe.sql (local Postgres 16, twice).

-- ── the country prefix of a number ────────────────────────────────────────────────────────────────
alter table public.support_customer_profile add column if not exists phone_prefix text;
do $$ begin
  alter table public.support_customer_profile add constraint support_customer_profile_phone_prefix_check
    check (phone_prefix is null or phone_prefix ~ '^[0-9]{1,6}$');
exception when duplicate_object then null; end $$;
comment on column public.support_customer_profile.phone_prefix is
  'The digits before phone_tail (country code, 00 and a trunk 0 removed), or null when the number was written in a local form. '
  'Two handsets with the same tail and different prefixes are two people (a_phone_tail_never_joins_two_people.sql).';

-- The digits before the last nine, as a country code: 00 (international prefix) and one trunk 0 before the tail removed
-- (+971 0 5x... is +971 5x...). Null for a local form (05x..., 5x...), which names no country and therefore agrees with any.
create or replace function public.fn_phone_prefix(p_phone text)
returns text
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select case when length(d) >= 10
              then nullif(regexp_replace(regexp_replace(left(d, length(d) - 9), '^00', ''), '0$', ''), '') end
    from (select regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g') as d) x
$fn$;
revoke execute on function public.fn_phone_prefix(text) from public, anon, authenticated;
grant execute on function public.fn_phone_prefix(text) to service_role;

-- ── 1. the profile a message belongs to ──────────────────────────────────────────────────────────
create or replace function public.fn_support_profile_resolve(p_kind text, p_party_id text, p_email text, p_phone text)
returns bigint
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_cust uuid; v_lead bigint; v_email text; v_tail text; v_prefix text; v_name text; v_id bigint;
  v_kind text := case when p_kind in ('customer', 'supplier') then p_kind else 'unknown' end;
  v_confirms boolean := false;    -- the number may confirm: the sending handset itself, or the record's verified number
  v_okind text; v_ocust uuid; v_olead bigint;
  v_clash bigint[] := '{}'; v_clash_on text;
begin
  -- A HANDSET WITH NO OTHER NAME is first asked who its confirmed owner is (one party or nobody), so the WhatsApp case read
  -- (case_memory.ts startWaCase: phone only) lands on the profile the wiring recorded the message on.
  if v_kind = 'unknown' and nullif(btrim(coalesce(p_email, '')), '') is null and nullif(btrim(coalesce(p_phone, '')), '') is not null then
    select o.party_kind, o.customer_id, o.lead_id into v_okind, v_ocust, v_olead from public.fn_whatsapp_owner(p_phone) o limit 1;
    if v_okind = 'customer' then v_kind := 'customer'; p_party_id := v_ocust::text;
    elsif v_okind = 'supplier' then v_kind := 'supplier'; p_party_id := v_olead::text; end if;
  end if;

  if v_kind = 'customer' and p_party_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_cust := p_party_id::uuid;
    select lower(btrim(c.email)), c.phone, c.full_name, coalesce(c.phone_verified, false) into v_email, p_phone, v_name, v_confirms
      from public.customers c where c.id = v_cust;
    v_email := coalesce(v_email, lower(btrim(p_email)));
  elsif v_kind = 'supplier' and p_party_id ~ '^[0-9]+$' then
    v_lead := p_party_id::bigint;
    select lower(btrim(l.email)), coalesce(l.phone_e164, l.phone), l.company_name, coalesce(l.owner_phone_verified, false)
      into v_email, p_phone, v_name, v_confirms
      from public.leads l where l.id = v_lead;
    v_email := coalesce(v_email, lower(btrim(p_email)));
  else
    v_email := lower(btrim(p_email));
    -- a number with no other name is the handset the message came from; a number typed beside an address is a claim
    v_confirms := nullif(v_email, '') is null;
  end if;
  v_confirms := coalesce(v_confirms, false);
  if v_email !~ '^[^@\s]+@[^@\s]+$' then v_email := null; end if;
  v_tail := right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9);
  if length(v_tail) < 9 then v_tail := null; end if;
  v_prefix := case when v_tail is not null then public.fn_phone_prefix(p_phone) end;
  if v_cust is null and v_lead is null and v_email is null and v_tail is null then return null; end if;

  -- 1. the account itself
  select p.id into v_id from public.support_customer_profile p
   where (v_cust is not null and p.customer_id = v_cust)
      or (v_lead is not null and p.lead_id = v_lead)
   order by (p.customer_id = v_cust) desc nulls last, p.id
   limit 1;

  -- 2. the mailbox (e-mail is the identity), unless that profile is a different account
  if v_id is null and v_email is not null then
    select p.id into v_id from public.support_customer_profile p
     where p.email = v_email
       and not (v_cust is not null and p.customer_id is not null and p.customer_id <> v_cust)
       and not (v_lead is not null and p.lead_id is not null and p.lead_id <> v_lead)
     order by p.id
     limit 1;
    if v_id is null then
      select coalesce(array_agg(p.id order by p.id), '{}') into v_clash from public.support_customer_profile p where p.email = v_email;
      if cardinality(v_clash) > 0 then v_clash_on := 'email'; end if;
    end if;
  end if;

  -- 3. the number: it may confirm, never select. Only a confirming number, only a profile nobody has named (no e-mail, customer
  --    or lead), only with the same country prefix where both are known.
  if v_id is null and v_tail is not null and v_confirms then
    select p.id into v_id from public.support_customer_profile p
     where p.phone_tail = v_tail
       and p.customer_id is null and p.lead_id is null and p.email is null
       and (p.phone_prefix is null or v_prefix is null or p.phone_prefix = v_prefix)
     order by (p.phone_prefix = v_prefix) desc nulls last, p.id
     limit 1;
  end if;
  -- the hole this file closes: a different named person on the same tail is a collision, not a match
  if v_id is null and v_clash_on is null and v_tail is not null
     and (v_cust is not null or v_lead is not null or v_email is not null) then
    select coalesce(array_agg(p.id order by p.id), '{}') into v_clash from public.support_customer_profile p
     where p.phone_tail = v_tail and (p.customer_id is not null or p.lead_id is not null or p.email is not null);
    if cardinality(v_clash) > 0 then v_clash_on := 'phone_tail'; end if;
  end if;

  if v_id is null then
    insert into public.support_customer_profile (party_kind, customer_id, lead_id, email, phone_tail, phone_prefix, display_name)
    values (v_kind, v_cust, v_lead, v_email, v_tail, v_prefix, v_name) returning id into v_id;
    if v_clash_on is not null then
      begin
        perform public.fn_it_engineer_finding_upsert('customer_support:profile_identity_collision:' || v_id,
          'Two named people met on one ' || case v_clash_on when 'email' then 'e-mail address' else 'phone number (last nine digits)' end
            || '; support profile ' || v_id || ' was opened apart, nothing was joined',
          'public.fn_support_profile_resolve', 'internal', cardinality(v_clash) + 1,
          jsonb_build_object('profile_id', v_id, 'kept_apart_from', to_jsonb(v_clash), 'key', v_clash_on, 'party_kind', v_kind,
                             'owner_seat', 'customer_support',
                             'fixture', coalesce(v_email like '%@example.invalid', false) or public.fn_is_demo_phone(p_phone)),
          '{}'::text[],
          array['whether the two are in fact one person: then read both records and join them by hand; never on the number alone'],
          'customer_support');
      exception when others then
        raise warning 'fn_support_profile_resolve: collision of profile % not recorded: %', v_id, sqlerrm;
      end;
    end if;
  else
    update public.support_customer_profile p
       set party_kind   = case when p.party_kind = 'unknown' then v_kind else p.party_kind end,
           customer_id  = coalesce(p.customer_id, case when not exists (select 1 from public.support_customer_profile x where x.customer_id = v_cust) then v_cust end),
           lead_id      = coalesce(p.lead_id, case when not exists (select 1 from public.support_customer_profile x where x.lead_id = v_lead) then v_lead end),
           email        = coalesce(p.email, v_email),
           phone_tail   = coalesce(p.phone_tail, v_tail),
           phone_prefix = case when p.phone_tail is null or p.phone_tail = v_tail then coalesce(p.phone_prefix, v_prefix) else p.phone_prefix end,
           display_name = coalesce(p.display_name, v_name),
           last_seen_at = now()
     where p.id = v_id;
  end if;
  return v_id;
end $fn$;
revoke execute on function public.fn_support_profile_resolve(text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_support_profile_resolve(text, text, text, text) to service_role;

-- ── 3. a verified number names its owner only in its own country ─────────────────────────────────
create or replace function public.fn_whatsapp_owner(p_phone text, p_all boolean DEFAULT false)
returns table(party_kind text, customer_id uuid, lead_id bigint)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with t as (select right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9) as tail, public.fn_phone_prefix(p_phone) as prefix),
  hits as (
    select 'customer'::text as party_kind, c.id as customer_id, null::bigint as lead_id
      from public.customers c, t
     where length(t.tail) = 9
       and ((c.whatsapp_opt = 'other' and c.whatsapp_verified_at is not null
             and right(regexp_replace(coalesce(c.whatsapp_phone, ''), '[^0-9]', '', 'g'), 9) = t.tail
             and coalesce(public.fn_phone_prefix(c.whatsapp_phone) = t.prefix, true))
         or (c.whatsapp_opt = 'same' and coalesce(c.phone_verified, false)
             and right(regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g'), 9) = t.tail
             and coalesce(public.fn_phone_prefix(c.phone) = t.prefix, true)))
    union
    select 'supplier', null, l.id
      from public.leads l, t
     where length(t.tail) = 9
       -- 18 Sep 2026, founder instruction 516: a confirmed sanctions ban means the handset names
       -- nobody. WhatsApp is the one channel with no session to refuse.
       and not exists (select 1 from public.sanctions_ban b where b.lead_id = l.id)
       and ((l.whatsapp_opt = 'other' and l.whatsapp_verified_at is not null
             and right(regexp_replace(coalesce(l.whatsapp_phone, ''), '[^0-9]', '', 'g'), 9) = t.tail
             and coalesce(public.fn_phone_prefix(l.whatsapp_phone) = t.prefix, true))
         or (l.whatsapp_opt = 'same' and coalesce(l.owner_phone_verified, false)
             and right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 9) = t.tail
             and coalesce(public.fn_phone_prefix(l.phone) = t.prefix, true))))
  -- A PHONE MAY CONFIRM, NEVER SELECT: one party or nobody. The country prefix must agree as well as the last nine digits
  -- (a_phone_tail_never_joins_two_people.sql); a number written in a local form names no country and agrees with any.
  select h.party_kind, h.customer_id, h.lead_id from hits h where p_all or (select count(*) from hits) = 1
$fn$;
revoke execute on function public.fn_whatsapp_owner(text, boolean) from public, anon, authenticated;
grant execute on function public.fn_whatsapp_owner(text, boolean) to service_role;

-- ── 4. the catch-up never summarises a tail two people share ─────────────────────────────────────
create or replace function public.fn_support_case_summaries_owed(p_limit integer DEFAULT 5)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.last_inbound_at), '[]'::jsonb)
    from (
      select c.case_ref, c.summary_text, c.summary_version, c.last_inbound_at, c.summary_updated_at, p.phone_tail, p.id as profile
        from public.support_case c
        join public.support_customer_profile p on p.id = c.customer_profile_id
       where c.state <> 'closed' and c.last_channel = 'whatsapp' and p.phone_tail is not null
         and c.last_inbound_at between now() - interval '24 hours' and now() - interval '5 minutes'
         -- not owed when ANY case of the person was summarised since the message (review round 2): the arrival attaches a message
         -- to the newest open case, the step after the reply may record it on another one, and the exchange is then recorded
         and not exists (select 1 from public.support_case c2
                          where c2.customer_profile_id = c.customer_profile_id and c2.summary_updated_at >= c.last_inbound_at)
         -- the catch-up reads the turns BY TAIL: a tail another profile shares would mix two people (a_phone_tail_never_joins_two_people.sql)
         and not exists (select 1 from public.support_customer_profile p2 where p2.phone_tail = p.phone_tail and p2.id <> p.id)
         and exists (select 1 from public.wa_messages m
                      where m.created_at >= c.last_inbound_at - interval '2 minutes'
                        and right(regexp_replace(coalesce(m.wa_from, ''), '[^0-9]', '', 'g'), 9) = p.phone_tail
                        and coalesce(btrim(m.inbound), '') <> '' and coalesce(btrim(m.reply), '') <> ''
                        -- the reply reached them: sent, or captured on a reserved fixture number
                        and (m.sent or coalesce(m.meta ->> 'send_error', '') like 'captured:%')
                        -- each catch-up is a paid model call: a ZZ DEMO number only while a rehearsal window is open
                        and (not public.fn_is_demo_phone(m.wa_from)
                             or coalesce((select (d.value #>> '{}')::boolean from public.decision_policy d where d.key = 'demo_rehearsal_active'), false)))
       order by c.last_inbound_at
       limit greatest(1, least(coalesce(p_limit, 5), 20))
    ) x;
$fn$;
revoke execute on function public.fn_support_case_summaries_owed(integer) from public, anon, authenticated;
grant execute on function public.fn_support_case_summaries_owed(integer) to service_role;

-- ── 5. the timeline a WhatsApp reply reads is the sender's own ───────────────────────────────────
create or replace function public.fn_contact_timeline_for_sender(p_contact text, p_limit integer DEFAULT 60)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_raw text := regexp_replace(btrim(coalesce(p_contact, '')), '^whatsapp:', '', 'i');
  v_digits text; v_tail text; v_prefix text;
  v_kind text; v_cust uuid; v_lead bigint; v_email text; v_tl jsonb; v_events jsonb;
begin
  -- an e-mail address is the identity: the timeline as it is
  if position('@' in v_raw) > 0 then return public.fn_contact_timeline(p_contact, p_limit); end if;
  v_digits := regexp_replace(v_raw, '[^0-9]', '', 'g');
  if length(v_digits) < 9 then return public.fn_contact_timeline(p_contact, p_limit); end if;
  v_tail := right(v_digits, 9);
  v_prefix := public.fn_phone_prefix(v_raw);

  -- a number: its confirmed owner (one party or nobody), read by the owner's e-mail
  select o.party_kind, o.customer_id, o.lead_id into v_kind, v_cust, v_lead from public.fn_whatsapp_owner(v_raw) o limit 1;
  if v_kind = 'customer' then
    select lower(btrim(c.email)) into v_email from public.customers c where c.id = v_cust;
  elsif v_kind = 'supplier' then
    select lower(btrim(coalesce(l.claimed_by, l.email))) into v_email from public.leads l where l.id = v_lead;
  end if;
  if v_email ~ '^[^@\s]+@[^@\s]+$' then
    return public.fn_contact_timeline(v_email, p_limit)
           || jsonb_build_object('contact', v_tail, 'read_as', 'the number''s confirmed owner, by their e-mail');
  end if;
  if v_kind is not null then
    -- an owner with no address: the number's own timeline, kept only if it names that owner and nobody else
    v_tl := public.fn_contact_timeline(v_raw, p_limit);
    if (v_kind = 'customer' and coalesce(v_tl -> 'customer_ids', '[]') = jsonb_build_array(v_cust) and coalesce(v_tl -> 'supplier_lead_ids', '[]') = '[]'::jsonb)
       or (v_kind = 'supplier' and coalesce(v_tl -> 'supplier_lead_ids', '[]') = jsonb_build_array(v_lead) and coalesce(v_tl -> 'customer_ids', '[]') = '[]'::jsonb) then
      return v_tl || jsonb_build_object('read_as', 'the number''s confirmed owner, by the number');
    end if;
  end if;

  -- no confirmed owner (or one the number cannot isolate): only what THIS number exchanged with us, the country prefix agreeing
  select coalesce(jsonb_agg(e order by e ->> 'at' desc), '[]'::jsonb) into v_events
    from (select jsonb_build_object('at', z.at, 'kind', 'message', 'channel', z.channel, 'direction', z.direction, 'seat', z.seat,
                                    'ref', z.ref, 'summary', z.summary) e
            from (select w.at, 'whatsapp' channel, w.direction, 'customer_support' seat, w.id::text ref,
                         left(coalesce(w.transcript, w.body, ''), 140) summary
                    from public.wa_turn w join public.wa_conversation c on c.id = w.conversation_id
                   where right(regexp_replace(coalesce(c.phone_e164, ''), '[^0-9]', '', 'g'), 9) = v_tail
                     and coalesce(public.fn_phone_prefix(c.phone_e164) = v_prefix, true)
                  union all
                  select n.created_at, coalesce(n.channel, 'whatsapp'), 'out', coalesce(n.requested_by, 'customer_support'), n.id::text,
                         coalesce(n.status, 'queued') || ': ' || left(coalesce(n.subject, n.type, ''), 140)
                    from public.notifications n
                   where right(regexp_replace(coalesce(n.to_phone, ''), '[^0-9]', '', 'g'), 9) = v_tail
                     and coalesce(public.fn_phone_prefix(n.to_phone) = v_prefix, true)) z
           where z.at is not null
           order by z.at desc
           limit greatest(1, least(coalesce(p_limit, 60), 500))) q;
  return jsonb_build_object('contact', v_tail, 'known', false, 'customer_ids', '[]'::jsonb, 'supplier_lead_ids', '[]'::jsonb,
    'event_count', jsonb_array_length(v_events),
    'counts', case when jsonb_array_length(v_events) > 0 then jsonb_build_object('message', jsonb_array_length(v_events)) else '{}'::jsonb end,
    'events', v_events,
    'read_as', 'this number only: it has no confirmed owner, and a phone may confirm an identity, never select one',
    'assembled_by', 'fn_contact_timeline_for_sender (deterministic; no model)');
end $fn$;
revoke execute on function public.fn_contact_timeline_for_sender(text, integer) from public, anon, authenticated;
grant execute on function public.fn_contact_timeline_for_sender(text, integer) to service_role;

-- ── 6. the repair: find the profiles joined before today, split what a reviewer names ────────────
-- Ids and counts only. Three signs that a profile holds two people: (a) its WhatsApp turns came from handsets of two country
-- prefixes; (b) a named profile's WhatsApp messages came from a handset that is not its confirmed number; (c) another registered
-- customer or supplier on the same tail wrote to support after the profile existed and has no profile of their own.
create or replace function public.fn_support_profile_collisions()
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with p as (select * from public.support_customer_profile where phone_tail is not null),
  wa as (
    select m.wa_from, m.created_at, right(regexp_replace(coalesce(m.wa_from, ''), '[^0-9]', '', 'g'), 9) as tail
      from public.wa_messages m
     where coalesce(btrim(m.inbound), '') <> '' and coalesce(m.meta ->> 'audience', '') <> 'founder'),
  handsets as (
    select p.id, count(distinct public.fn_phone_prefix(w.wa_from)) as n
      from p join wa w on w.tail = p.phone_tail and w.created_at >= p.created_at - interval '1 minute'
     group by p.id having count(distinct public.fn_phone_prefix(w.wa_from)) > 1),
  unconfirmed as (
    select p.id from p
     where (p.customer_id is not null or p.lead_id is not null or p.email is not null)
       and exists (select 1 from wa w
                    where w.tail = p.phone_tail and w.created_at >= p.created_at - interval '1 minute'
                      and not exists (select 1 from public.fn_whatsapp_owner(w.wa_from) o
                                       where o.customer_id = p.customer_id or o.lead_id = p.lead_id))),
  other_c as (
    select p.id, array_agg(distinct c.id::text) as ids from p
      join public.customers c on right(regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g'), 9) = p.phone_tail
                             and c.id is distinct from p.customer_id
     where not exists (select 1 from public.support_customer_profile x where x.customer_id = c.id)
       and (exists (select 1 from public.inbound_messages m
                     where lower(substring(coalesce(m.from_email, '') from '([^<>\s"]+@[^<>\s"]+)')) = lower(btrim(c.email))
                       and m.created_at >= p.created_at and m.triaged_at is not null)
            or exists (select 1 from public.assistant_logs a where a.audience = 'customer:' || c.id::text and a.created_at >= p.created_at))
     group by p.id),
  other_l as (
    select p.id, array_agg(distinct l.id::text) as ids from p
      join public.leads l on right(regexp_replace(coalesce(l.phone_e164, l.phone, ''), '[^0-9]', '', 'g'), 9) = p.phone_tail
                         and l.id is distinct from p.lead_id
     where not exists (select 1 from public.support_customer_profile x where x.lead_id = l.id)
       and (exists (select 1 from public.inbound_messages m
                     where lower(substring(coalesce(m.from_email, '') from '([^<>\s"]+@[^<>\s"]+)')) = lower(btrim(l.email))
                       and m.created_at >= p.created_at and m.triaged_at is not null)
            or exists (select 1 from public.assistant_logs a where a.audience = 'supplier:' || l.id::text and a.created_at >= p.created_at))
     group by p.id),
  flagged as (
    select p.id,
           array_remove(array[case when h.id is not null then 'two_country_prefixes_on_one_tail' end,
                              case when u.id is not null then 'whatsapp_from_a_number_that_is_not_theirs' end,
                              case when oc.id is not null or ol.id is not null then 'another_registered_person_on_the_tail_wrote_in' end], null) as reasons,
           coalesce(oc.ids, '{}') as other_customer_ids, coalesce(ol.ids, '{}') as other_lead_ids
      from p
      left join handsets h on h.id = p.id left join unconfirmed u on u.id = p.id
      left join other_c oc on oc.id = p.id left join other_l ol on ol.id = p.id
     where h.id is not null or u.id is not null or oc.id is not null or ol.id is not null)
  select jsonb_build_object(
    'profiles_to_review', (select count(*) from flagged),
    'how', 'read both people''s records, then fn_support_profile_split(profile, the case refs that are the other person''s, '
           || 'their kind and id, e-mail, phone, reviewed_by, reason) with p_dry_run => true first',
    'items', coalesce((select jsonb_agg(jsonb_build_object(
               'profile_id', f.id, 'reasons', to_jsonb(f.reasons),
               'other_customer_ids', to_jsonb(f.other_customer_ids), 'other_lead_ids', to_jsonb(f.other_lead_ids),
               'cases', coalesce((select jsonb_agg(jsonb_build_object('case_ref', c.case_ref, 'channels', c.channels, 'opened_at', c.opened_at,
                                                                      'state', c.state) order by c.opened_at)
                                    from public.support_case c where c.customer_profile_id = f.id), '[]'::jsonb)) order by f.id)
                         from flagged f), '[]'::jsonb));
$fn$;
revoke execute on function public.fn_support_profile_collisions() from public, anon, authenticated;
grant execute on function public.fn_support_profile_collisions() to service_role;

-- Moves the cases a reviewer names off a profile onto the other person's own profile (found by their account or e-mail, or
-- opened), with their ratings; the source keeps everything else. Dry run by default: it then only says what it would change.
-- The identity moved off the source (its customer, lead or e-mail, when the reviewer says they are the other person's) is
-- cleared there first. Never run by this file; never on the number alone.
create or replace function public.fn_support_profile_split(p_profile bigint, p_case_refs text[], p_kind text, p_party_id text,
  p_email text, p_phone text, p_reviewed_by text, p_reason text, p_dry_run boolean DEFAULT true)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  s public.support_customer_profile; t public.support_customer_profile;
  v_kind text := case when p_kind in ('customer', 'supplier') then p_kind else 'unknown' end;
  v_cust uuid; v_lead bigint; v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_tail text := nullif(right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9), '');
  v_cases bigint[]; v_unknown text[]; v_clear text[] := '{}'; v_target bigint; v_feedback int; v_action bigint;
begin
  if coalesce(btrim(p_reviewed_by), '') = '' or coalesce(btrim(p_reason), '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'a split is a reviewed decision: name who read both records and why');
  end if;
  select * into s from public.support_customer_profile where id = p_profile for update;
  if s.id is null then return jsonb_build_object('ok', false, 'reason', 'no such profile'); end if;
  if coalesce(cardinality(p_case_refs), 0) = 0 then return jsonb_build_object('ok', false, 'reason', 'name the cases that are the other person''s'); end if;
  select coalesce(array_agg(c.case_id), '{}') into v_cases from public.support_case c
   where c.case_ref = any (p_case_refs) and c.customer_profile_id = p_profile;
  select coalesce(array_agg(r), '{}') into v_unknown from unnest(p_case_refs) r
   where not exists (select 1 from public.support_case c where c.case_ref = r and c.customer_profile_id = p_profile);
  if cardinality(v_unknown) > 0 then
    return jsonb_build_object('ok', false, 'reason', 'these cases are not on the profile', 'cases', to_jsonb(v_unknown));
  end if;
  if v_kind = 'customer' then
    if coalesce(p_party_id, '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return jsonb_build_object('ok', false, 'reason', 'a customer is named by their customer id');
    end if;
    v_cust := p_party_id::uuid;
    if not exists (select 1 from public.customers c where c.id = v_cust) then return jsonb_build_object('ok', false, 'reason', 'no such customer'); end if;
  elsif v_kind = 'supplier' then
    if coalesce(p_party_id, '') !~ '^[0-9]+$' then return jsonb_build_object('ok', false, 'reason', 'a supplier is named by their lead id'); end if;
    v_lead := p_party_id::bigint;
    if not exists (select 1 from public.leads l where l.id = v_lead) then return jsonb_build_object('ok', false, 'reason', 'no such supplier'); end if;
  elsif v_email is null and v_tail is null then
    return jsonb_build_object('ok', false, 'reason', 'name the other person: an account, an e-mail or the number');
  end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+$' then return jsonb_build_object('ok', false, 'reason', 'not an e-mail address'); end if;
  if v_tail is not null and length(v_tail) < 9 then v_tail := null; end if;

  -- what moves off the source with the person
  if v_cust is not null and s.customer_id = v_cust then v_clear := v_clear || 'customer_id'::text; end if;
  if v_lead is not null and s.lead_id = v_lead then v_clear := v_clear || 'lead_id'::text; end if;
  if v_email is not null and s.email = v_email then v_clear := v_clear || 'email'::text; end if;
  -- the other person's own profile, when one exists already (their account, else their mailbox)
  select * into t from public.support_customer_profile x
   where x.id <> p_profile
     and ((v_cust is not null and x.customer_id = v_cust) or (v_lead is not null and x.lead_id = v_lead)
          or (v_email is not null and x.email = v_email
              and not (v_cust is not null and x.customer_id is not null and x.customer_id <> v_cust)
              and not (v_lead is not null and x.lead_id is not null and x.lead_id <> v_lead)))
   order by (x.customer_id = v_cust) desc nulls last, (x.lead_id = v_lead) desc nulls last, x.id
   limit 1;
  select count(*) into v_feedback from public.feedback f where f.case_id = any (v_cases);

  if p_dry_run then
    return jsonb_build_object('ok', true, 'dry_run', true, 'profile', p_profile,
      'would', jsonb_build_object(
        'target', case when t.id is not null then jsonb_build_object('use_profile', t.id) else jsonb_build_object('open_profile', v_kind) end,
        'move_cases', to_jsonb(p_case_refs), 'move_ratings', v_feedback,
        'clear_on_source', to_jsonb(v_clear),
        'cases_left_on_source', (select count(*) from public.support_case c where c.customer_profile_id = p_profile) - cardinality(v_cases)));
  end if;

  if cardinality(v_clear) > 0 then
    update public.support_customer_profile
       set customer_id = case when 'customer_id' = any (v_clear) then null else customer_id end,
           lead_id     = case when 'lead_id' = any (v_clear) then null else lead_id end,
           email       = case when 'email' = any (v_clear) then null else email end,
           party_kind  = case when ('customer_id' = any (v_clear) and lead_id is null) or ('lead_id' = any (v_clear) and customer_id is null)
                              then 'unknown' else party_kind end
     where id = p_profile;
  end if;
  if t.id is not null then
    v_target := t.id;
  else
    insert into public.support_customer_profile (party_kind, customer_id, lead_id, email, phone_tail, phone_prefix, display_name)
    values (v_kind, v_cust, v_lead, v_email, v_tail, case when v_tail is not null then public.fn_phone_prefix(p_phone) end,
            case when v_cust is not null then (select c.full_name from public.customers c where c.id = v_cust)
                 when v_lead is not null then (select l.company_name from public.leads l where l.id = v_lead) end)
    returning id into v_target;
  end if;
  update public.support_case c
     set customer_profile_id = v_target,
         party_kind = case when v_cust is not null then 'customer' when v_lead is not null then 'supplier' else c.party_kind end,
         party_id   = coalesce(v_cust::text, v_lead::text, case when v_tail is not null then '+' || regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g') end, v_email)
   where c.case_id = any (v_cases);
  update public.feedback set profile_id = v_target where case_id = any (v_cases);
  -- the case summary file follows the case into its owner's Dropbox folder
  perform public.fn_support_case_summary_backup_enqueue(x) from unnest(v_cases) x;
  insert into public.agent_actions (agent, kind, status, title, detail, target_table, target_id, decided_at, decided_by)
  values ('customer_support', 'support_profile_split', 'executed',
          'Support profile ' || p_profile || ' split: ' || cardinality(v_cases) || ' case(s) moved to profile ' || v_target,
          jsonb_build_object('source_profile', p_profile, 'target_profile', v_target, 'cases', to_jsonb(p_case_refs),
                             'ratings_moved', v_feedback, 'cleared_on_source', to_jsonb(v_clear), 'reason', left(p_reason, 500)),
          'support_customer_profile', p_profile::text, now(), left(p_reviewed_by, 120))
  returning id into v_action;
  return jsonb_build_object('ok', true, 'dry_run', false, 'profile', p_profile, 'target_profile', v_target,
    'moved_cases', to_jsonb(p_case_refs), 'moved_ratings', v_feedback, 'cleared_on_source', to_jsonb(v_clear), 'action_id', v_action);
end $fn$;
revoke execute on function public.fn_support_profile_split(bigint, text[], text, text, text, text, text, text, boolean) from public, anon, authenticated;
grant execute on function public.fn_support_profile_split(bigint, text[], text, text, text, text, text, text, boolean) to service_role;
