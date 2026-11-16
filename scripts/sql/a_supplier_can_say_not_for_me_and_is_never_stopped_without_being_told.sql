-- A SUPPLIER CAN SAY "NOT FOR ME", AND IS NEVER STOPPED WITHOUT BEING TOLD.
-- Seat: sales_engineer (matching, the supplier's standing, the quote hold desk). Agent: NOT_FOR_ME (sales_engineer seat's
-- builder, wave 2 of the real-company holes, founder ledgers 1711-1713, 16 Nov 2026).
--
-- THE HOLES (scratchpad holes files of 16 Nov 2026; READ on origin/main and the batch-B branch this builds on):
--   SUPPLIER 2 / OPERATIONS H8. "No penalty for ignoring" was false. an_unanswered_request_is_a_strike_and_a_quote_clears_the_run.sql
--     gives one strike per ended request he did not quote (:15-23), fn_is_matchable stops him at 3, "no message is sent on a
--     strike" (:23), and he had no way to say "not my trade": inquiry_matches had no declined or reason column, supplier_api no
--     decline action, and the FAQ and knowledge/brief/company.md:89 said "ignoring an invitation carries no penalty".
--   FAILURES 2. The strike clock is inquiry_matches.sent_at, which defaults to now() at MATCH time, not delivery: a bounced,
--     spam-foldered or undelivered request still counted, only a quote reset the run, and an unmatchable supplier never gets a
--     request to quote on, so he was removed for good, silently.
--   SUPPLIER 7. "Stop sending me painting jobs" by e-mail or WhatsApp changed nothing (services editable in the portal only).
--   SUPPLIER 3. A customer could pay 3% to reveal a supplier who is away, whose licence lapsed or who left
--     (_shared/reveal_guard.ts canReveal checked none of these).
--   CUSTOMER 8. A quote far from the others on the same request went out unflagged: only market ranges exist
--     (fn_price_benchmarks, 5+ quotes by 3+ suppliers on other requests; today none). A 450,000 typo among 45,000s is a
--     13,500 reveal fee.
--   FAILURES 8. quotes.masked_terms (what the scrubbers removed) was read by nothing.
--
-- WHAT THIS ADDS (code decides only facts: delivery statuses, dates, sums, who owns a row; what a supplier MEANT is read by a
-- model in _shared/supplier_instruction.ts, and the weekly trade correction is the model's decision, applied below):
--   1. inquiry_matches.declined_at / decline_reason / decline_channel: "Not for me", with his reason in his words.
--   2. fn_supplier_declines_request: records it against the match, withdraws a strike that request already gave him (event
--      'withdrawn'), and answers which trade the request was in and whether removing it from his profile is possible.
--   3. THE STRIKE IS DECIDED ON WHETHER THE REQUEST REACHED HIM. fn_supplier_request_reached_him reads the delivery facts the
--      estate already holds for that request's notices (provider_status delivered/read/undelivered, notifications status,
--      email_open_event other than a machine prefetch, a portal sign-in after the request was sent). A request he never
--      received, or received but never opened, is recorded 'not_counted' with those facts and is NOT a strike; two in a row
--      file a sales engineer action to reach him another way. A declined request is never a strike.
--   4. TOLD BEFORE AND AT THE STOP. One strike short of the limit he is told in plain words, with the requests named and what
--      to do ("Not for me", busy until a date, or "I'm available"); at the limit he is told requests are paused and how to
--      resume. fn_supplier_says_available clears the run (and sets him available) when he says so.
--   5. public.supplier_trade_correction: a proposed removal of a trade or service from his profile (from his "Not for me",
--      from an e-mail or WhatsApp instruction, or from the weekly review), applied only when he confirms. The removal itself
--      is the portal's own writer (servicesSaveRewrite -> capabilityConfirm), called by supplier_api / the readers.
--   6. sales_engineer.decline_review (weekly): each supplier's declined requests of the week, with his reasons, what matched
--      him and his services, are put to the sales engineer's model (surface sales_engineer.trade_correction, one option per
--      trade or implied service those requests reached him through, plus "keep"); fn_reason_apply_sales_engineer__trade_correction
--      turns a removal into a proposal and asks the supplier to confirm it.
--   7. fn_supplier_live_standing: approved, closed, banned, licence in date, availability and the date he is back, strikes,
--      contact details removed from his quotations. Every supplier-facing reader and the reveal door read this one answer.
--   8. fn_reveal_standing(quote): proceed / away ("back on <date>") / not_revealable / figure_unconfirmed, read by
--      reveal_guard.canReveal before any charge. A supplier going on leave is offered to keep or withdraw his live quotes
--      (supplier_api); fn_supplier_live_quotes lists them.
--   9. A QUOTE FAR FROM ITS PEERS IS CHECKED. fn_quote_peer_price_flag: with no market range for its lines, a quote whose
--      ex-VAT total is at least decision_policy 'quote_peer_price_factor' (3) times the median of the same request's other
--      live quotes from at least two other suppliers, or at most a third of it, carries flag price_far_from_peers. It joins
--      fn_quote_quality_flags, so it takes the EXISTING quote-quality hold path (held as a draft, the fixes sent to the
--      supplier in English, released when corrected or after the hold hours). The supplier's fix line names only his own
--      total, never a rival figure or a direction. fn_supplier_confirms_quote_figure records "this figure is right"
--      (public.quote_figure_confirmation), which clears the flag for that amount; the reveal door refuses a flagged,
--      unconfirmed figure and asks the supplier once.
--  10. CONTACT DETAILS REMOVED ARE A FACT ON HIS RECORD. fn_supplier_contact_removals counts the e-mail addresses, web
--      addresses and phone numbers among his quotations' masked_terms (exact forms, not words); trigger
--      z33_quote_contact_removal_is_told tells him once, citing clause 10 of the Supplier Agreement, without accusing him
--      (a letterhead carries them).
--  11. THE FAQ AND THE KNOWLEDGE ROWS say what is true (company_faq 42 and 730, the compiled FAQ, two kb_chunks), with the site's
--      src/content/marketing.json and knowledge/brief/company.md:89 in the same change.
-- NOT CHANGED: fn_is_matchable and fn_matching_strike_limit (the founder's 3 of 3 Aug 2026 stands); a quote still clears the
--   run; the accountant's circumvention reasoning (its tick is the accountant's file: fn_supplier_live_standing carries the
--   count for it to read).
-- prevented by: this file's _probe.sql; supabase/functions/_shared/supplier_instruction.test.ts;
--   supabase/functions/_shared/reveal_standing.test.ts; supabase/functions/supplier_api/not_for_me.test.ts.
-- Pending until the release applies it: scripts/sql/pending/a_supplier_can_say_not_for_me_and_is_never_stopped_without_being_told.txt

-- ── 1. the answer on the match ─────────────────────────────────────────────────────────────────────────────────────────
alter table public.inquiry_matches add column if not exists declined_at timestamptz;
alter table public.inquiry_matches add column if not exists decline_reason text;
alter table public.inquiry_matches add column if not exists decline_channel text;
comment on column public.inquiry_matches.decline_reason is
  'The supplier''s own words when he answered "Not for me" (portal, e-mail or WhatsApp). Read by the weekly decline review''s model; never shown to the customer.';

-- the strike record learns three more kinds: not counted (never reached him), withdrawn (he declined after the strike)
alter table public.supplier_strike_event drop constraint if exists supplier_strike_event_kind_check;
alter table public.supplier_strike_event add constraint supplier_strike_event_kind_check
  check (kind in ('strike', 'cleared', 'not_counted', 'withdrawn'));
create unique index if not exists supplier_strike_event_one_not_counted_per_request
  on public.supplier_strike_event (lead_id, inquiry_id) where kind = 'not_counted';
create unique index if not exists supplier_strike_event_one_withdrawal_per_request
  on public.supplier_strike_event (lead_id, inquiry_id) where kind = 'withdrawn';

insert into public.decision_policy (key, value, description) values
  ('quote_peer_price_factor', '3'::jsonb,
   'A quote whose ex-VAT total is this many times the median of the same request''s other live quotes (or this fraction of it) is held for the supplier to confirm, when no market range exists for its lines. Sales engineer, 16 Nov 2026.')
on conflict (key) do nothing;

-- ── 3. did the request reach him? ──────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_request_reached_him(p_supplier bigint, p_inquiry uuid, p_sent_at timestamptz)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_claimed text; v_notices int; v_delivered int; v_undelivered int; v_read int; v_opened int; v_login timestamptz;
begin
  select lower(btrim(coalesce(l.claimed_by, ''))) into v_claimed from public.leads l where l.id = p_supplier;
  select count(*),
         count(*) filter (where n.provider_status in ('delivered', 'read')),
         count(*) filter (where n.provider_status in ('undelivered', 'failed') or n.status in ('failed', 'suppressed', 'bounced')),
         count(*) filter (where n.provider_status = 'read')
    into v_notices, v_delivered, v_undelivered, v_read
    from public.notifications n
   where n.lead_id = p_supplier and n.inquiry_id = p_inquiry and coalesce(n.to_role, 'supplier') = 'supplier';
  select count(*) into v_opened
    from public.email_open_event e join public.notifications n on n.id = e.notification_id
   where n.lead_id = p_supplier and n.inquiry_id = p_inquiry and coalesce(e.classification, 'unknown') <> 'machine_prefetch';
  if v_claimed <> '' then
    select max(u.last_sign_in_at) into v_login from auth.users u where lower(u.email) = v_claimed;
  end if;
  return jsonb_build_object(
    'seen', v_read > 0 or v_opened > 0 or (v_login is not null and v_login >= p_sent_at),
    'delivered', v_delivered > 0,
    'undelivered', v_notices > 0 and v_undelivered = v_notices,
    'notices', v_notices, 'opened', v_opened, 'read_on_whatsapp', v_read,
    'portal_sign_in_after_send', v_login is not null and v_login >= p_sent_at,
    'why', case when v_read > 0 or v_opened > 0 or (v_login is not null and v_login >= p_sent_at) then 'seen'
                when v_notices = 0 then 'never_sent'
                when v_undelivered = v_notices then 'not_delivered'
                else 'delivered_not_seen' end);
end $fn$;
revoke execute on function public.fn_supplier_request_reached_him(bigint, uuid, timestamptz) from public, anon, authenticated;

-- ── 4. what he is told ─────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_strike_notice(p_supplier bigint, p_kind text)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare l public.leads; v_refs text; v_n int; v_limit int := public.fn_matching_strike_limit(); v_subject text; v_body text;
begin
  select * into l from public.leads where id = p_supplier;
  if not found or coalesce(nullif(btrim(l.claimed_by), ''), nullif(btrim(l.email), '')) is null then return null; end if;
  select count(*) into v_n from public.supplier_strike_event where lead_id = p_supplier and kind = 'strike';
  select string_agg(coalesce('RFQ-' || i.rfq_no, 'a request in ' || coalesce(i.category, 'your trade')), ', ' order by e.created_at)
    into v_refs
    from (select * from public.supplier_strike_event
           where lead_id = p_supplier and kind = 'strike'
             and created_at > coalesce((select max(c.created_at) from public.supplier_strike_event c
                                         where c.lead_id = p_supplier and c.kind = 'cleared'), '-infinity'::timestamptz)) e
    left join public.inquiries i on i.id = e.inquiry_id;
  if p_kind = 'warning' then
    v_subject := 'Please answer your QuotesDone job requests';
    v_body := 'You did not answer ' || (v_limit - 1) || ' job requests we sent you'
      || coalesce(' (' || v_refs || ')', '') || '. If one more request goes unanswered, we will stop sending you new requests.'
      || E'\n\nWhat to do:'
      || E'\n- If a request is not your kind of work, press "Not for me" on it in your portal, or reply "not for me" to its e-mail or on WhatsApp. That never counts against you, and you can tell us why.'
      || E'\n- If you no longer do a trade, tell us and we will stop sending you those jobs.'
      || E'\n- If you are away, set yourself busy until the date you are back (portal, Settings, Availability).'
      || E'\n- If you are available, reply "I''m available" and this count goes back to zero.';
  elsif p_kind = 'stopped' then
    v_subject := 'We have paused new job requests to you';
    v_body := 'You did not answer ' || v_limit || ' job requests in a row' || coalesce(' (' || v_refs || ')', '')
      || ', so we have paused new requests to you. Requests you already have stay open.'
      || E'\n\nTo receive requests again, reply "I''m available" here or on WhatsApp, or send a quotation on any open request. '
      || 'If those requests were not your kind of work, press "Not for me" on them and tell us why: we will correct the trades we send you.';
  else
    raise exception 'unknown strike notice kind %', p_kind;
  end if;
  return public.fn_sales_engineer_writes('supplier_strike_' || p_kind, 'supplier',
    coalesce(nullif(btrim(l.claimed_by), ''), l.email), p_supplier, null, null, null, v_subject, v_body, null, null, '{}'::text[],
    'supplier_strike_' || p_kind || ':' || p_supplier || ':' || v_n);
end $fn$;
revoke execute on function public.fn_supplier_strike_notice(bigint, text) from public, anon, authenticated;

-- The strikes of one ended request, now decided on the delivery facts (replaces the body of
-- an_unanswered_request_is_a_strike_and_a_quote_clears_the_run.sql; same signature, same caller, same 21-day window).
create or replace function public.fn_sales_engineer_counts_unanswered_request(p_inquiry uuid, p_ended_at timestamptz default now())
 returns int
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_window int := public.fn_seat_clock_policy('request_no_quote_expiry_days', 21)::int;
  v_limit int := public.fn_matching_strike_limit();
  r record; v_n int := 0; v_after int; v_reach jsonb; v_unseen int;
begin
  for r in
    select m.supplier_id, min(m.sent_at) as sent_at
      from public.inquiry_matches m
     where m.inquiry_id = p_inquiry and m.supplier_id is not null
     group by m.supplier_id
    having min(m.sent_at) <= p_ended_at - make_interval(days => v_window)
       and bool_and(m.declined_at is null)                    -- "Not for me" is an answer
       and not exists (select 1 from public.quotes q where q.inquiry_id = p_inquiry and q.supplier_id = m.supplier_id)
  loop
    v_reach := public.fn_supplier_request_reached_him(r.supplier_id, p_inquiry, r.sent_at);
    if coalesce((v_reach->>'seen')::boolean, false) is not true then
      -- it never reached him, or reached him unopened: not his silence. Recorded with the facts, never a strike.
      insert into public.supplier_strike_event (lead_id, inquiry_id, kind, strikes_after, detail)
      select r.supplier_id, p_inquiry, 'not_counted', coalesce(l.chat_strikes, 0),
             jsonb_build_object('sent_at', r.sent_at, 'ended_at', p_ended_at, 'delivery', v_reach)
        from public.leads l where l.id = r.supplier_id
      on conflict do nothing;
      if found then
        -- two in a row with nothing seen since: the sales engineer reaches him another way
        select count(*) into v_unseen from public.supplier_strike_event e
         where e.lead_id = r.supplier_id and e.kind = 'not_counted'
           and e.created_at > coalesce((select max(x.created_at) from public.supplier_strike_event x
                                         where x.lead_id = r.supplier_id and x.kind in ('strike', 'cleared')), '-infinity'::timestamptz);
        if v_unseen >= 2 and not coalesce((select is_demo from public.leads where id = r.supplier_id), false) then
          insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
          select 'sales_engineer', 'supplier_unreachable', 'pending', 'low',
                 left('Job requests are not reaching supplier #' || r.supplier_id, 200),
                 'The last ' || v_unseen || ' requests sent to this supplier were not delivered or not opened, so none counted against him. Check his e-mail and WhatsApp number, and reach him on the other channel.',
                 jsonb_build_object('supplier_id', r.supplier_id, 'unseen_requests', v_unseen, 'last_delivery', v_reach),
                 'leads', 'supplier_unreachable:' || r.supplier_id
           where not exists (select 1 from public.agent_actions a where a.kind = 'supplier_unreachable'
                              and a.target_id = 'supplier_unreachable:' || r.supplier_id and a.status = 'pending');
        end if;
      end if;
      continue;
    end if;
    insert into public.supplier_strike_event (lead_id, inquiry_id, kind, strikes_after, detail)
    select r.supplier_id, p_inquiry, 'strike', coalesce(l.chat_strikes, 0) + 1,
           jsonb_build_object('sent_at', r.sent_at, 'ended_at', p_ended_at, 'window_days', v_window, 'delivery', v_reach,
                              'rule', 'matching_strike_limit (founder, 3 Aug 2026)')
      from public.leads l where l.id = r.supplier_id
    on conflict do nothing;
    if found then
      update public.leads set chat_strikes = coalesce(chat_strikes, 0) + 1 where id = r.supplier_id returning chat_strikes into v_after;
      v_n := v_n + 1;
      -- told one short of the stop, and at the stop: never stopped silently
      if v_after = v_limit - 1 then perform public.fn_supplier_strike_notice(r.supplier_id, 'warning');
      elsif v_after = v_limit then perform public.fn_supplier_strike_notice(r.supplier_id, 'stopped');
      end if;
    end if;
  end loop;
  return v_n;
end $fn$;
revoke execute on function public.fn_sales_engineer_counts_unanswered_request(uuid, timestamptz) from public, anon, authenticated;

-- ── 2. "Not for me" ────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_declines_request(p_supplier bigint, p_inquiry uuid, p_reason text default null, p_channel text default 'portal')
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare
  i public.inquiries; v_reason text := nullif(left(btrim(coalesce(p_reason, '')), 1000), '');
  v_channel text := coalesce(nullif(btrim(p_channel), ''), 'portal'); v_after int; v_withdrew boolean := false;
  v_trades text[]; v_label text;
begin
  if v_channel not in ('portal', 'email', 'whatsapp') then
    return jsonb_build_object('ok', false, 'code', 'bad_channel');
  end if;
  if not exists (select 1 from public.inquiry_matches m where m.inquiry_id = p_inquiry and m.supplier_id = p_supplier) then
    return jsonb_build_object('ok', false, 'code', 'not_found', 'error', 'This request was not sent to you.');
  end if;
  if exists (select 1 from public.quotes q where q.inquiry_id = p_inquiry and q.supplier_id = p_supplier
              and coalesce(q.status, '') not in ('withdrawn', 'rejected', 'expired', 'cancelled')) then
    return jsonb_build_object('ok', false, 'code', 'already_quoted',
      'error', 'You already sent a quotation on this request. To take it back, withdraw the quotation instead.');
  end if;
  select * into i from public.inquiries where id = p_inquiry;
  update public.inquiry_matches
     set declined_at = coalesce(declined_at, now()),
         decline_reason = coalesce(v_reason, decline_reason),
         decline_channel = coalesce(decline_channel, v_channel)
   where inquiry_id = p_inquiry and supplier_id = p_supplier;
  -- a strike this request already gave him is withdrawn: he answered
  if exists (select 1 from public.supplier_strike_event e where e.lead_id = p_supplier and e.inquiry_id = p_inquiry and e.kind = 'strike') then
    insert into public.supplier_strike_event (lead_id, inquiry_id, kind, strikes_after, detail)
    select p_supplier, p_inquiry, 'withdrawn', greatest(coalesce(l.chat_strikes, 0) - 1, 0),
           jsonb_build_object('channel', v_channel, 'reason', v_reason)
      from public.leads l where l.id = p_supplier
    on conflict do nothing;
    if found then
      update public.leads set chat_strikes = greatest(coalesce(chat_strikes, 0) - 1, 0) where id = p_supplier returning chat_strikes into v_after;
      v_withdrew := true;
    end if;
  end if;
  select c.trades into v_trades from public.supplier_capabilities c where c.supplier_id = p_supplier;
  select t.label into v_label from public.taxonomy_trade t where t.code = i.category;
  return jsonb_build_object('ok', true, 'inquiry_id', p_inquiry, 'rfq_no', 'RFQ-' || i.rfq_no, 'trade', i.category,
    'trade_label', coalesce(v_label, replace(coalesce(i.category, ''), '_', ' ')),
    'trade_is_his', i.category = any(coalesce(v_trades, '{}'::text[])),
    'can_remove_trade', i.category = any(coalesce(v_trades, '{}'::text[])) and cardinality(coalesce(v_trades, '{}'::text[])) > 1,
    'strike_withdrawn', v_withdrew,
    'strikes', coalesce(v_after, (select chat_strikes from public.leads where id = p_supplier), 0),
    'strike_limit', public.fn_matching_strike_limit(), 'reason_recorded', v_reason is not null);
end $fn$;
revoke execute on function public.fn_supplier_declines_request(bigint, uuid, text, text) from public, anon, authenticated;

create or replace function public.fn_supplier_says_available(p_supplier bigint, p_channel text default 'portal')
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_prev int; v_avail jsonb;
begin
  select coalesce(chat_strikes, 0) into v_prev from public.leads where id = p_supplier;
  if not found then return jsonb_build_object('ok', false, 'code', 'no_company'); end if;
  if v_prev > 0 then
    update public.leads set chat_strikes = 0 where id = p_supplier;
    insert into public.supplier_strike_event (lead_id, inquiry_id, kind, strikes_after, detail)
    values (p_supplier, null, 'cleared', 0, jsonb_build_object('cleared_from', v_prev, 'said_available', true, 'channel', p_channel));
  end if;
  if not public.fn_supplier_available((select a.state from public.supplier_availability a where a.supplier_id = p_supplier),
                                      (select a.busy_until from public.supplier_availability a where a.supplier_id = p_supplier)) then
    perform public.fn_supplier_set_availability(p_supplier, 'available', null, 'supplier (' || coalesce(p_channel, 'portal') || ')');
  end if;
  v_avail := public.fn_supplier_availability_of(p_supplier);
  return jsonb_build_object('ok', true, 'cleared_from', v_prev, 'strikes', 0, 'availability', v_avail);
end $fn$;
revoke execute on function public.fn_supplier_says_available(bigint, text) from public, anon, authenticated;

-- ── 5. a correction he confirms ────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.supplier_trade_correction (
  id bigint generated always as identity primary key,
  supplier_id bigint not null references public.leads(id) on delete cascade,
  source text not null check (source in ('not_for_me', 'email', 'whatsapp', 'portal', 'weekly_review')),
  inquiry_id uuid,
  remove_trades text[] not null default '{}',
  remove_services text[] not null default '{}',
  why text,
  status text not null default 'proposed' check (status in ('proposed', 'applied', 'declined', 'expired', 'failed')),
  proposed_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_channel text,
  result jsonb,
  check (cardinality(remove_trades) + cardinality(remove_services) > 0)
);
create unique index if not exists supplier_trade_correction_one_open on public.supplier_trade_correction (supplier_id) where status = 'proposed';
alter table public.supplier_trade_correction enable row level security;
drop policy if exists supplier_trade_correction_service_role_only on public.supplier_trade_correction;
create policy supplier_trade_correction_service_role_only on public.supplier_trade_correction as permissive for all to public using (false) with check (false);
revoke all on public.supplier_trade_correction from anon, authenticated;

create or replace function public.fn_supplier_trade_correction_propose(p_supplier bigint, p_source text, p_trades text[], p_services text[], p_why text default null, p_inquiry uuid default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare c public.supplier_trade_correction; v_held text[]; v_trades text[]; v_services text[];
begin
  select coalesce(trades, '{}') into v_held from public.supplier_capabilities where supplier_id = p_supplier;
  -- only what he holds can be removed; a trade that is his last is not removed (pausing is the way to stop everything)
  v_trades := array(select distinct t from unnest(coalesce(p_trades, '{}'::text[])) t where t = any(coalesce(v_held, '{}')));
  v_services := array(select distinct s from unnest(coalesce(p_services, '{}'::text[])) s where s ~ '^[a-z0-9_]+\.[a-z0-9_]+$');
  if cardinality(v_trades) + cardinality(v_services) = 0 then
    return jsonb_build_object('ok', false, 'code', 'nothing_to_remove');
  end if;
  if cardinality(v_trades) >= cardinality(coalesce(v_held, '{}')) then
    return jsonb_build_object('ok', false, 'code', 'last_trade',
      'error', 'That is the only trade on your profile. To stop all requests for a while, set yourself paused or busy instead.');
  end if;
  update public.supplier_trade_correction set status = 'expired', decided_at = now()
   where supplier_id = p_supplier and status = 'proposed';
  insert into public.supplier_trade_correction (supplier_id, source, inquiry_id, remove_trades, remove_services, why)
  values (p_supplier, p_source, p_inquiry, v_trades, v_services, nullif(left(btrim(coalesce(p_why, '')), 1000), ''))
  returning * into c;
  return jsonb_build_object('ok', true, 'correction', public.fn_supplier_trade_correction_view(c.id));
end $fn$;

create or replace function public.fn_supplier_trade_correction_view(p_id bigint)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object('id', c.id, 'status', c.status, 'source', c.source, 'proposed_at', c.proposed_at,
    'remove_trades', to_jsonb(c.remove_trades), 'remove_services', to_jsonb(c.remove_services), 'why', c.why,
    'labels', to_jsonb(array(
      select coalesce(t.label, replace(x, '_', ' ')) from unnest(c.remove_trades) x left join public.taxonomy_trade t on t.code = x
      union all
      select coalesce(s.label_en, replace(split_part(y, '.', 2), '_', ' '))
        from unnest(c.remove_services) y left join public.taxonomy_trade_service s on s.trade_code || '.' || s.code = y)))
    from public.supplier_trade_correction c where c.id = p_id;
$fn$;

create or replace function public.fn_supplier_trade_correction_decide(p_id bigint, p_supplier bigint, p_decision text, p_channel text, p_result jsonb default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_n int;
begin
  if p_decision not in ('applied', 'declined', 'failed') then return jsonb_build_object('ok', false, 'code', 'bad_decision'); end if;
  update public.supplier_trade_correction
     set status = p_decision, decided_at = now(), decided_channel = p_channel, result = p_result
   where id = p_id and supplier_id = p_supplier and status = 'proposed';
  get diagnostics v_n = row_count;
  return case when v_n = 1 then jsonb_build_object('ok', true, 'status', p_decision)
              else jsonb_build_object('ok', false, 'code', 'not_open') end;
end $fn$;
revoke execute on function public.fn_supplier_trade_correction_propose(bigint, text, text[], text[], text, uuid) from public, anon, authenticated;
revoke execute on function public.fn_supplier_trade_correction_view(bigint) from public, anon, authenticated;
revoke execute on function public.fn_supplier_trade_correction_decide(bigint, bigint, text, text, jsonb) from public, anon, authenticated;

-- ── 10. contact details removed from his quotations ────────────────────────────────────────────────────────────────────
-- An exact form, not a word: an e-mail address, a web address, or seven or more digits (a phone number).
create or replace function public.fn_is_contact_term(p_term text)
 returns boolean
 language sql
 immutable
 set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(p_term, '') ~* '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}'
      or coalesce(p_term, '') ~* '(https?://|www\.)'
      or coalesce(p_term, '') ~* '[a-z0-9-]+\.(com|ae|net|org|co|info|biz)(\M|/)'
      or length(regexp_replace(coalesce(p_term, ''), '\D', '', 'g')) >= 7;
$fn$;
revoke execute on function public.fn_is_contact_term(text) from public, anon, authenticated;

create or replace function public.fn_supplier_contact_removals(p_supplier bigint)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object(
    'terms', count(*),
    'quotes', count(distinct q.id))
    from public.quotes q
    cross join lateral jsonb_array_elements_text(case when jsonb_typeof(q.masked_terms) = 'array' then q.masked_terms else '[]'::jsonb end) t(term)
   where q.supplier_id = p_supplier and public.fn_is_contact_term(t.term);
$fn$;
revoke execute on function public.fn_supplier_contact_removals(bigint) from public, anon, authenticated;

create table if not exists public.supplier_contact_removal_notice (
  lead_id bigint primary key references public.leads(id) on delete cascade,
  quote_id uuid,
  terms_at_notice int not null,
  told_at timestamptz not null default now(),
  handoff_id bigint
);
alter table public.supplier_contact_removal_notice enable row level security;
drop policy if exists supplier_contact_removal_notice_service_role_only on public.supplier_contact_removal_notice;
create policy supplier_contact_removal_notice_service_role_only on public.supplier_contact_removal_notice as permissive for all to public using (false) with check (false);
revoke all on public.supplier_contact_removal_notice from anon, authenticated;

create or replace function public.trg_quote_contact_removal_is_told()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_n int; l public.leads; v_rfq text; v_h bigint;
begin
  select count(*) into v_n
    from jsonb_array_elements_text(case when jsonb_typeof(new.masked_terms) = 'array' then new.masked_terms else '[]'::jsonb end) t(term)
   where public.fn_is_contact_term(t.term);
  if v_n = 0 or exists (select 1 from public.supplier_contact_removal_notice where lead_id = new.supplier_id) then return new; end if;
  select * into l from public.leads where id = new.supplier_id;
  if not found then return new; end if;
  select 'RFQ-' || rfq_no into v_rfq from public.inquiries where id = new.inquiry_id;
  insert into public.supplier_contact_removal_notice (lead_id, quote_id, terms_at_notice) values (new.supplier_id, new.id, v_n)
  on conflict do nothing;
  if not found then return new; end if;
  v_h := public.fn_sales_engineer_writes('supplier_contact_removed', 'supplier',
    coalesce(nullif(btrim(l.claimed_by), ''), l.email), new.supplier_id, null, new.inquiry_id, new.id,
    'Contact details were removed from your quotation',
    'Before the customer saw your quotation' || coalesce(' for ' || v_rfq, '') || ', we removed ' || v_n
      || case when v_n = 1 then ' contact detail' else ' contact details' end || ' (a phone number, e-mail or web address) from it.'
      || ' This is normal when they sit on a letterhead, and nothing more is needed from you.'
      || E'\n\nPlease do not write contact details into a quotation''s text, lines or notes. The customer receives your full name and contact details the moment they pay to reveal you, and clause 10 of the Supplier Agreement does not allow sharing them before that (AED 10,000 per incident).',
    null, null, '{}'::text[], 'supplier_contact_removed:' || new.supplier_id);
  update public.supplier_contact_removal_notice set handoff_id = v_h where lead_id = new.supplier_id;
  return new;
end $fn$;
revoke execute on function public.trg_quote_contact_removal_is_told() from public, anon, authenticated;
drop trigger if exists z33_quote_contact_removal_is_told on public.quotes;
create trigger z33_quote_contact_removal_is_told after insert or update of masked_terms on public.quotes
  for each row when (new.supplier_id is not null and new.masked_terms is not null)
  execute function public.trg_quote_contact_removal_is_told();

-- ── 7. his live standing, one answer for every reader ──────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_live_standing(p_supplier bigint)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare l public.leads; a public.supplier_availability; v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_away boolean; v_trades text[]; v_services text[]; v_open jsonb;
begin
  select * into l from public.leads where id = p_supplier;
  if not found then return null; end if;
  select * into a from public.supplier_availability where supplier_id = p_supplier;
  v_away := a.supplier_id is not null and not public.fn_supplier_available(a.state, a.busy_until);
  select c.trades, c.services into v_trades, v_services from public.supplier_capabilities c where c.supplier_id = p_supplier;
  select public.fn_supplier_trade_correction_view(c.id) into v_open
    from public.supplier_trade_correction c where c.supplier_id = p_supplier and c.status = 'proposed';
  return jsonb_build_object(
    'supplier_id', p_supplier,
    'approved', coalesce(l.approval_status, '') = 'approved',
    'closed', coalesce(l.permanently_closed, false),
    'banned', coalesce(l.banned, false),
    'licence_expiry', l.license_expiry,
    'licence_in_date', l.license_expiry is null or l.license_expiry >= v_today,
    'availability', case when v_away then a.state else 'available' end,
    'away', v_away,
    'back_on', case when v_away and a.state = 'busy' then a.busy_until end,
    'strikes', coalesce(l.chat_strikes, 0),
    'strike_limit', public.fn_matching_strike_limit(),
    'paused_for_unanswered', coalesce(l.chat_strikes, 0) >= public.fn_matching_strike_limit(),
    'matchable', public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes) and not v_away,
    'trades', to_jsonb(coalesce(v_trades, '{}'::text[])),
    'services', to_jsonb(coalesce(v_services, '{}'::text[])),
    'open_correction', v_open,
    'contact_details_removed', public.fn_supplier_contact_removals(p_supplier));
end $fn$;
revoke execute on function public.fn_supplier_live_standing(bigint) from public, anon, authenticated;

-- his quotations still in front of a customer and not revealed: what a supplier going on leave is offered to keep or withdraw
create or replace function public.fn_supplier_live_quotes(p_supplier bigint)
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('quote_id', q.id, 'inquiry_id', q.inquiry_id, 'rfq_no', 'RFQ-' || i.rfq_no, 'status', q.status)
                            order by q.created_at), '[]'::jsonb)
    from public.quotes q join public.inquiries i on i.id = q.inquiry_id
   where q.supplier_id = p_supplier and q.status in ('draft', 'submitted')
     and coalesce(i.status, '') not in ('cancelled', 'closed', 'completed', 'expired', 'lost')
     and not exists (select 1 from public.transactions t where t.quote_id = q.id);
$fn$;
revoke execute on function public.fn_supplier_live_quotes(bigint) from public, anon, authenticated;

-- ── 9. a quote far from its peers ──────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.quote_figure_confirmation (
  quote_id uuid primary key,
  supplier_id bigint not null references public.leads(id) on delete cascade,
  amount numeric not null,
  channel text not null,
  confirmed_at timestamptz not null default now()
);
alter table public.quote_figure_confirmation enable row level security;
drop policy if exists quote_figure_confirmation_service_role_only on public.quote_figure_confirmation;
create policy quote_figure_confirmation_service_role_only on public.quote_figure_confirmation as permissive for all to public using (false) with check (false);
revoke all on public.quote_figure_confirmation from anon, authenticated;

create or replace function public.fn_quote_peer_price_flag(p_quote public.quotes)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_total numeric := coalesce(p_quote.price_ex_vat, p_quote.quote_amount); v_median numeric; v_peers int; v_factor numeric;
begin
  if v_total is null or v_total <= 0 then return null; end if;
  if exists (select 1 from public.quote_figure_confirmation c where c.quote_id = p_quote.id and c.amount = v_total) then return null; end if;
  -- the median of the request's quotes INCLUDING this one: with one outlier among three, the median of the other two would
  -- sit halfway to the outlier and flag the honest quote as well; with this one counted, only the outlier is far from it
  with peers as (
    select q.supplier_id, coalesce(q.price_ex_vat, q.quote_amount) as total
      from public.quotes q
     where q.inquiry_id = p_quote.inquiry_id and q.id <> p_quote.id
       and q.supplier_id is distinct from p_quote.supplier_id
       and coalesce(q.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'cancelled', 'held')
       and coalesce(q.price_ex_vat, q.quote_amount) > 0)
  select (select count(distinct supplier_id) from peers),
         (select percentile_cont(0.5) within group (order by t) from (select total as t from peers union all select v_total) a)
    into v_peers, v_median;
  if coalesce(v_peers, 0) < 2 or v_median is null or v_median <= 0 then return null; end if;
  v_factor := greatest(public.fn_seat_clock_policy('quote_peer_price_factor', 3), 1.5);
  if v_total >= v_median * v_factor or v_total <= v_median / v_factor then
    return jsonb_build_object('code', 'price_far_from_peers', 'total', round(v_total, 2), 'peers', v_peers,
                              'ratio_to_median', round(v_total / v_median, 2), 'factor', v_factor);
  end if;
  return null;
end $fn$;
revoke execute on function public.fn_quote_peer_price_flag(public.quotes) from public, anon, authenticated;

-- fn_quote_quality_flags: a_quote_is_checked_for_specs_prices_and_terms_before_the_customer_sees_it.sql's body unchanged, plus
-- (2b): with no market range for any line, the same request's peers.
create or replace function public.fn_quote_quality_flags(p_quote quotes)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_cat text; v_demo boolean; v_reader boolean; v_spec jsonb; v_price jsonb; v_terms jsonb := '[]'::jsonb; v_peer jsonb;
begin
  select i.category into v_cat from public.inquiries i where i.id = p_quote.inquiry_id;
  v_demo := public.fn_inquiry_is_demo(p_quote.inquiry_id);

  -- (1) the pack checklist, unless a line reader already read these lines
  select exists (select 1 from public.quote_items qi, jsonb_object_keys(coalesce(qi.spec, '{}'::jsonb)) k
                  where qi.quote_id = p_quote.id::text and k !~ '^spec_') into v_reader;
  if not v_reader then
    with lists as (
      select c.topic_id, c.topic, c.specs from public.trade_spec_checklist c
       where c.trade_code = v_cat or c.trade_code = any(coalesce(public.fn_taxonomy_trades_for(array[v_cat]), '{}'::text[]))
    ), specs as (
      select l.topic_id, l.topic, s.x->>'code' as code, s.x->>'label_en' as label, s.ord
        from lists l, jsonb_array_elements(l.specs) with ordinality s(x, ord)
    ), judged as (
      select sp.*, exists (select 1 from public.quote_items qi
                            where qi.quote_id = p_quote.id::text and nullif(btrim(qi.spec->>sp.code), '') is not null) as stated
        from specs sp
    ), per_list as (
      select j.topic_id, j.topic, count(*) filter (where j.stated) as n_stated, count(*) filter (where not j.stated) as n_missing,
             jsonb_agg(jsonb_build_object('code', j.code, 'label', j.label) order by j.ord) filter (where not j.stated) as missing
        from judged j group by j.topic_id, j.topic
    ), chosen as (
      select * from per_list order by (n_missing = 0) desc, n_stated desc, n_missing, topic_id limit 1
    )
    select case
             when not exists (select 1 from per_list) then null                        -- no checklist for this trade
             when (select n_missing from chosen) = 0 then null                         -- one list fully stated
             when (select n_stated from chosen) > 0 or (select count(*) from per_list) = 1
               then jsonb_build_object('code', 'missing_spec', 'topic', (select topic from chosen), 'specs', (select missing from chosen))
             else jsonb_build_object('code', 'missing_spec', 'topic', null, 'specs',
                    (select jsonb_agg(jsonb_build_object('code', u.code, 'label', u.label) order by u.first_topic, u.ord)
                       from (select distinct on (j.code) j.code, j.label, j.topic_id as first_topic, j.ord
                               from judged j order by j.code, j.topic_id, j.ord) u))
           end
      into v_spec;
  end if;

  -- (2) each priced line against the UAE range for the same item; no benchmark, no flag
  with b as (select * from public.fn_price_benchmarks(v_demo, p_quote.inquiry_id)),
  lines as (
    select qi.line_no, qi.description,
           public.fn_price_benchmark_key(qi.description, qi.specification) as item_key,
           public.fn_price_benchmark_unit(qi.unit) as unit,
           round(coalesce(qi.unit_price, qi.amount / nullif(qi.qty, 0)), 2) as price
      from public.quote_items qi where qi.quote_id = p_quote.id::text
  ), judged as (
    select l.*, b.median, b.p25, b.p75, b.quote_count, b.supplier_count,
           public.fn_price_benchmark_judge(l.price, b.median, b.p25, b.p75, b.quote_count, b.supplier_count, l.unit) as j
      from lines l join b on b.trade = lower(v_cat) and b.item_key = l.item_key and b.unit = l.unit
     where l.price > 0
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'code', case when j->>'status' = 'well_above' then 'price_above' else 'price_below' end,
           'line_no', line_no, 'description', description, 'unit', unit, 'price', price,
           'pct_vs_median', (j->>'pct_vs_median')::numeric, 'median', median, 'p25', p25, 'p75', p75,
           'quotes', quote_count, 'suppliers', supplier_count) order by line_no), '[]'::jsonb)
    into v_price
    from judged where j->>'status' in ('well_above', 'well_below');

  -- (2b) no market range flagged a line: the same request's other quotes (a_supplier_can_say_not_for_me_..., 16 Nov 2026)
  if jsonb_array_length(coalesce(v_price, '[]'::jsonb)) = 0 then
    v_peer := public.fn_quote_peer_price_flag(p_quote);
    if v_peer is not null then v_price := jsonb_build_array(v_peer); end if;
  end if;

  -- (3) the terms a customer cannot compare without
  if nullif(btrim(coalesce(p_quote.validity, '')), '') is null then
    v_terms := v_terms || jsonb_build_array(jsonb_build_object('code', 'no_validity')); end if;
  if nullif(btrim(coalesce(p_quote.lead_time, '')), '') is null
     and nullif(btrim(coalesce(p_quote.terms_spec #>> '{delivery,value}', '')), '') is null then
    v_terms := v_terms || jsonb_build_array(jsonb_build_object('code', 'no_delivery_time')); end if;
  if coalesce(p_quote.vat_treatment, 'not_stated') = 'not_stated' then
    v_terms := v_terms || jsonb_build_array(jsonb_build_object('code', 'no_vat_treatment')); end if;

  return (case when v_spec is null then '[]'::jsonb else jsonb_build_array(v_spec) end) || coalesce(v_price, '[]'::jsonb) || v_terms;
end
$function$;

-- fn_quote_quality_fixes_en: the same lines, plus the peer line, which names only his own total (never a rival figure or a
-- direction: telling him "too high" would be the implied comparison the founder removed with the best-and-final round).
create or replace function public.fn_quote_quality_fixes_en(p_flags jsonb)
 returns text
 language sql
 immutable
 set search_path to 'public', 'pg_temp'
as $function$
  select string_agg(n || '. ' || line, E'\n' order by n)
    from (select row_number() over (order by o) as n,
                 case f->>'code'
                   when 'missing_spec' then
                     'State these specifications on the lines you quote'
                     || coalesce(' (' || nullif(regexp_replace(f->>'topic', '^[Ss]pec checklist:\s*', ''), '') || ')', '') || ': '
                     || (select string_agg(s->>'label', '; ' order by k) from jsonb_array_elements(f->'specs') with ordinality e(s, k))
                     || '. If one does not apply to what you quote, write "not applicable" and why.'
                   when 'price_above' then
                     'Line ' || (f->>'line_no') || ' "' || left(coalesce(f->>'description', ''), 80) || '": AED '
                     || to_char((f->>'price')::numeric, 'FM999,999,990.00') || ' per ' || (f->>'unit') || ' is '
                     || (f->>'pct_vs_median') || '% above the usual UAE price for this item (AED '
                     || to_char((f->>'p25')::numeric, 'FM999,999,990.00') || ' to ' || to_char((f->>'p75')::numeric, 'FM999,999,990.00')
                     || ' per ' || (f->>'unit') || ', from ' || (f->>'quotes') || ' quotations by ' || (f->>'suppliers')
                     || ' suppliers). Correct the price, or state on the line what justifies it (brand, grade, scope or delivery).'
                   when 'price_below' then
                     'Line ' || (f->>'line_no') || ' "' || left(coalesce(f->>'description', ''), 80) || '": AED '
                     || to_char((f->>'price')::numeric, 'FM999,999,990.00') || ' per ' || (f->>'unit') || ' is '
                     || abs((f->>'pct_vs_median')::numeric) || '% below the usual UAE price for this item (AED '
                     || to_char((f->>'p25')::numeric, 'FM999,999,990.00') || ' to ' || to_char((f->>'p75')::numeric, 'FM999,999,990.00')
                     || ' per ' || (f->>'unit') || ', from ' || (f->>'quotes') || ' quotations by ' || (f->>'suppliers')
                     || ' suppliers). Check the quantity, the specification and what is excluded, then correct the line or state what it covers.'
                   when 'price_far_from_peers' then
                     'Please check your total of AED ' || to_char((f->>'total')::numeric, 'FM999,999,990.00')
                     || ' (before VAT) for a typing error, and that it covers the whole scope of the request and nothing more. '
                     || 'If it is right, press "Confirm this figure" on the quotation (or reply "the figure is correct"); otherwise correct it.'
                   when 'no_validity' then 'State how long the quotation is valid (for example, 30 days).'
                   when 'no_delivery_time' then 'State the delivery or lead time (a date, or a number of days from the order).'
                   when 'no_vat_treatment' then 'State whether your price includes or excludes VAT, or that you are not registered for VAT.'
                 end as line
            from jsonb_array_elements(coalesce(p_flags, '[]'::jsonb)) with ordinality a(f, o)) x
   where line is not null
$function$;

create or replace function public.fn_supplier_confirms_quote_figure(p_supplier bigint, p_quote uuid, p_channel text default 'portal')
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare q public.quotes; v_total numeric; v_flag jsonb;
begin
  select * into q from public.quotes where id = p_quote and supplier_id = p_supplier;
  if not found then return jsonb_build_object('ok', false, 'code', 'not_found'); end if;
  v_total := coalesce(q.price_ex_vat, q.quote_amount);
  if v_total is null or v_total <= 0 then return jsonb_build_object('ok', false, 'code', 'no_total'); end if;
  insert into public.quote_figure_confirmation (quote_id, supplier_id, amount, channel)
  values (q.id, p_supplier, v_total, coalesce(nullif(btrim(p_channel), ''), 'portal'))
  on conflict (quote_id) do update set amount = excluded.amount, channel = excluded.channel, confirmed_at = now();
  -- the hold desk's flags are refreshed now; its 15-minute tick releases a hold whose flags are gone
  update public.quote_quality_hold h
     set flags = public.fn_quote_quality_flags(q), fixes_en = public.fn_quote_quality_fixes_en(public.fn_quote_quality_flags(q)), updated_at = now()
   where h.quote_id = q.id and h.released_at is null and h.superseded_at is null;
  v_flag := public.fn_quote_peer_price_flag(q);
  return jsonb_build_object('ok', true, 'quote_id', q.id, 'confirmed_total', v_total, 'still_flagged', v_flag is not null);
end $fn$;
revoke execute on function public.fn_supplier_confirms_quote_figure(bigint, uuid, text) from public, anon, authenticated;

-- ── 8. the reveal door reads his standing before any charge ────────────────────────────────────────────────────────────
create or replace function public.fn_reveal_standing(p_quote uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare q public.quotes; s jsonb; v_flag jsonb; l public.leads; v_rfq text;
begin
  select * into q from public.quotes where id = p_quote;
  if not found then return jsonb_build_object('outcome', 'not_revealable', 'why', 'no_quote'); end if;
  s := public.fn_supplier_live_standing(q.supplier_id);
  if s is null then return jsonb_build_object('outcome', 'not_revealable', 'why', 'no_supplier'); end if;
  if (s->>'closed')::boolean or (s->>'banned')::boolean then
    return jsonb_build_object('outcome', 'not_revealable', 'why', 'closed');
  end if;
  if not (s->>'approved')::boolean then
    return jsonb_build_object('outcome', 'not_revealable', 'why', 'not_approved');
  end if;
  if not (s->>'licence_in_date')::boolean then
    return jsonb_build_object('outcome', 'not_revealable', 'why', 'licence_expired', 'licence_expiry', s->'licence_expiry');
  end if;
  if (s->>'away')::boolean then
    return jsonb_build_object('outcome', 'away', 'why', s->>'availability', 'back_on', s->'back_on');
  end if;
  v_flag := public.fn_quote_peer_price_flag(q);
  if v_flag is not null then
    -- the supplier is asked once to confirm or correct; the customer is told before paying anything
    select * into l from public.leads where id = q.supplier_id;
    select 'RFQ-' || rfq_no into v_rfq from public.inquiries where id = q.inquiry_id;
    -- once: the handoff is idempotent on its subject, and a demo write (no handoff, ruling 1199) is looked for here
    if not exists (select 1 from public.notifications n where n.type = 'quote_figure_confirm' and n.quote_id = q.id)
       and not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.target_id = 'delivery.request:quote_figure_confirm:' || q.id) then
    perform public.fn_sales_engineer_writes('quote_figure_confirm', 'supplier',
      coalesce(nullif(btrim(l.claimed_by), ''), l.email), q.supplier_id, null, q.inquiry_id, q.id,
      'Please confirm the total of your quotation' || coalesce(' for ' || v_rfq, ''),
      'A customer wants to go ahead with your quotation' || coalesce(' for ' || v_rfq, '') || '. Before they pay, please check your total of AED '
        || to_char((v_flag->>'total')::numeric, 'FM999,999,990.00') || ' (before VAT) for a typing error, and that it covers the whole scope of the request.'
        || E'\n\nIf it is right, press "Confirm this figure" on the quotation in your portal, or reply "the figure is correct". If it is not, correct the quotation.',
      null, null, '{}'::text[], 'quote_figure_confirm:' || q.id);
    end if;
    return jsonb_build_object('outcome', 'figure_unconfirmed', 'why', 'price_far_from_peers');
  end if;
  return jsonb_build_object('outcome', 'proceed');
end $fn$;
revoke execute on function public.fn_reveal_standing(uuid) from public, anon, authenticated;

-- the edge functions call these as service_role (supabase-js with the service key)
grant execute on function public.fn_supplier_declines_request(bigint, uuid, text, text) to service_role;
grant execute on function public.fn_supplier_says_available(bigint, text) to service_role;
grant execute on function public.fn_supplier_trade_correction_propose(bigint, text, text[], text[], text, uuid) to service_role;
grant execute on function public.fn_supplier_trade_correction_view(bigint) to service_role;
grant execute on function public.fn_supplier_trade_correction_decide(bigint, bigint, text, text, jsonb) to service_role;
grant execute on function public.fn_supplier_live_standing(bigint) to service_role;
grant execute on function public.fn_supplier_live_quotes(bigint) to service_role;
grant execute on function public.fn_supplier_confirms_quote_figure(bigint, uuid, text) to service_role;
grant execute on function public.fn_reveal_standing(uuid) to service_role;
grant execute on function public.fn_supplier_contact_removals(bigint) to service_role;

-- ── 6. the weekly decline review: the model decides, the supplier confirms ────────────────────────────────────────────
create or replace function public.fn_sales_engineer_decline_review()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_week text := to_char(now() at time zone 'Asia/Dubai', 'IYYY-"W"IW');
  r record; v_options jsonb; v_filed int := 0; v_suppliers int := 0;
begin
  for r in
    select m.supplier_id,
           jsonb_agg(jsonb_build_object('rfq_no', 'RFQ-' || i.rfq_no, 'trade', i.category, 'summary', i.summary_masked,
                                        'matched_because', m.match_reason, 'his_reason', m.decline_reason,
                                        'channel', m.decline_channel, 'declined_at', m.declined_at) order by m.declined_at) as declines,
           array_agg(distinct i.category) filter (where i.category is not null) as trades,
           array_agg(distinct x.implied) filter (where x.implied is not null) as implied
      from public.inquiry_matches m
      join public.inquiries i on i.id = m.inquiry_id
      join public.leads l on l.id = m.supplier_id
      left join lateral (select (regexp_matches(coalesce(m.match_reason, ''), '-> ([a-z0-9_]+\.[a-z0-9_]+)', 'g'))[1] as implied) x on true
     where m.declined_at >= now() - interval '7 days'
       and coalesce(l.is_demo, false) = v_fx
     group by m.supplier_id
  loop
    v_suppliers := v_suppliers + 1;
    select jsonb_agg(o) into v_options from (
      select jsonb_build_object('id', 'keep', 'meaning', 'these requests were right for him (the reasons are about timing, size or the job itself); change nothing') o
      union all
      select jsonb_build_object('id', 'remove_trade:' || t,
               'meaning', 'he does not do ' || coalesce(tt.label, t) || ' work: propose removing that trade from his profile, for him to confirm')
        from unnest(coalesce(r.trades, '{}'::text[])) t
        left join public.taxonomy_trade tt on tt.code = t
        join public.supplier_capabilities c on c.supplier_id = r.supplier_id and t = any(coalesce(c.trades, '{}'::text[]))
       where cardinality(coalesce(c.trades, '{}'::text[])) > 1
      union all
      select jsonb_build_object('id', 'remove_service:' || s,
               'meaning', 'a curated implication gave him ' || s || ', which his reasons say he does not do: propose removing it, for him to confirm')
        from unnest(coalesce(r.implied, '{}'::text[])) s) z;
    if jsonb_array_length(v_options) < 2 then continue; end if;
    perform public.fn_seat_duty_reason('sales_engineer', 'sales_engineer.trade_correction',
      case when v_fx then 'ZZ DEMO ' else '' end
      || 'A supplier answered "Not for me" on these requests this week, with his reasons. Read his reasons with what matched him and the services on his profile. Should the trades we send him be corrected?',
      v_options,
      jsonb_build_object('supplier_id', r.supplier_id, 'declines', r.declines,
                         'his_profile', public.fn_supplier_live_standing(r.supplier_id) - 'contact_details_removed'),
      jsonb_build_object('supplier_id', r.supplier_id, 'week', v_week),
      'trade_correction:' || r.supplier_id || ':' || v_week);
    v_filed := v_filed + 1;
  end loop;
  return jsonb_build_object('week', v_week, 'suppliers_with_declines', v_suppliers, 'reasoning_filed', v_filed);
end $fn$;
revoke execute on function public.fn_sales_engineer_decline_review() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_decline_review() to service_role;

create or replace function public.fn_reason_apply_sales_engineer__trade_correction(p_id bigint, p_result jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare h public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_sup bigint; v_prop jsonb; l public.leads;
  v_kind text; v_code text; v_labels text;
begin
  select * into h from public.reasoning_held_question where id = p_id;
  v_sup := nullif(h.subject->>'supplier_id', '')::bigint;
  if v_choice is null or not (v_choice = 'keep' or v_choice ~ '^remove_(trade|service):[a-z0-9_.]+$') then
    raise exception 'CHOICE_NOT_AN_OPTION: % (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  if v_choice = 'keep' or v_sup is null then return jsonb_build_object('applied', true, 'changed', false, 'choice', v_choice); end if;
  v_kind := split_part(v_choice, ':', 1); v_code := split_part(v_choice, ':', 2);
  v_prop := public.fn_supplier_trade_correction_propose(v_sup, 'weekly_review',
    case when v_kind = 'remove_trade' then array[v_code] else '{}'::text[] end,
    case when v_kind = 'remove_service' then array[v_code] else '{}'::text[] end,
    left(coalesce(p_result->>'answer', ''), 1000), null);
  if not coalesce((v_prop->>'ok')::boolean, false) then
    return jsonb_build_object('applied', true, 'changed', false, 'choice', v_choice, 'refused', v_prop->>'code');
  end if;
  select * into l from public.leads where id = v_sup;
  select string_agg(x, ', ') into v_labels from jsonb_array_elements_text(v_prop->'correction'->'labels') x;
  perform public.fn_sales_engineer_writes('supplier_trade_correction', 'supplier',
    coalesce(nullif(btrim(l.claimed_by), ''), l.email), v_sup, null, null, null,
    'Shall we stop sending you ' || coalesce(v_labels, 'these') || ' requests?',
    'You told us some recent requests were not for you. From your reasons, we suggest removing ' || coalesce(v_labels, 'this work')
      || ' from the work we match you to, so you stop receiving those requests.'
      || E'\n\nNothing changes until you confirm. Reply "yes" to remove it, or "no" to keep it; you can also do it in your portal under Services.',
    null, null, '{}'::text[], 'supplier_trade_correction:' || ((v_prop->'correction'->>'id')));
  return jsonb_build_object('applied', true, 'changed', true, 'choice', v_choice, 'correction_id', (v_prop->'correction'->>'id')::bigint);
end $fn$;
revoke execute on function public.fn_reason_apply_sales_engineer__trade_correction(bigint, jsonb) from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.decline_review', 'sales_engineer', interval '7 days', 'fn_sales_engineer_decline_review',
   'Each supplier''s "Not for me" answers of the week, with his reasons and what matched him, put to the model: keep, or propose removing a trade or an implied service for him to confirm.',
   'scripts/sql/a_supplier_can_say_not_for_me_and_is_never_stopped_without_being_told.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- ── 11. the FAQ and the knowledge rows say what is true ────────────────────────────────────────────────────────────────
-- "there is no penalty for not quoting" was false once the strike rule went live (an_unanswered_request_is_a_strike_..., 10 Nov).
-- The same answer is corrected in src/content/marketing.json (the site), knowledge/brief/company.md (the brief), and here in the
-- rows the agents read: company_faq 42 and 730 (each guarded by the md5 of the row as read on production, 16 Nov 2026, SELECT; the
-- embedding cleared so it is re-embedded), the compiled FAQ in agent_knowledge (_global) and the two kb_chunks that carry it
-- (a replace of the old answer inside each: a row that no longer holds it is left as it is).
update public.company_faq set answer = $qd$Yes. If a request is not right for you, press “Not for me” on it in your portal (or reply “not for me” to its e-mail or on WhatsApp) and, if you like, tell us why: it never counts against you, and your reason helps us correct the trades we send you. A request you simply leave unanswered is different: after 3 unanswered requests in a row that reached you, we pause new requests to you. We warn you after the second, and you can resume at any time by replying “I’m available” or sending a quotation. (The only charge is if a customer pays to reveal you and you then ignore them.)$qd$, embedding_gte = null, updated_at = now()
 where id = 42 and md5(answer) = '272d9c437031d3dadc6b71040fec59c3';
update public.company_faq set answer = $qd$نعم. إذا لم يكن الطلب مناسبًا لكم، فاضغطوا زر «Not for me» عليه في بوابتكم (أو ردّوا بعبارة «ليس لنا» على رسالته الإلكترونية أو عبر واتساب)، ويمكنكم ذكر السبب إن شئتم: لا يُحتسب ذلك عليكم أبدًا، ويساعدنا سببكم على تصحيح التخصصات التي نرسلها إليكم. أما الطلب الذي يُترك دون رد فأمره مختلف: بعد 3 طلبات متتالية وصلتكم دون رد، نوقف إرسال الطلبات الجديدة إليكم مؤقتًا. ننبّهكم بعد الطلب الثاني، ويمكنكم الاستئناف في أي وقت بالرد بعبارة «نحن متاحون» أو بإرسال عرض سعر. (الرسم الوحيد يترتّب إذا سدّد عميل رسوم الاطلاع على بياناتكم ثم تجاهلتموه.)$qd$, embedding_gte = null, updated_at = now()
 where id = 730 and md5(answer) = '817c3e630d3e1368a202650749c131c6';
update public.agent_knowledge
   set content = replace(replace(content, $qd$Yes — you are free to ignore any invitation that is not right for you; there is no penalty for not quoting. (The only charge is if a customer pays to reveal you and you then ignore them.)$qd$, $qd$Yes. If a request is not right for you, press “Not for me” on it in your portal (or reply “not for me” to its e-mail or on WhatsApp) and, if you like, tell us why: it never counts against you, and your reason helps us correct the trades we send you. A request you simply leave unanswered is different: after 3 unanswered requests in a row that reached you, we pause new requests to you. We warn you after the second, and you can resume at any time by replying “I’m available” or sending a quotation. (The only charge is if a customer pays to reveal you and you then ignore them.)$qd$), $qd$نعم، لكم أن تتجاهلوا أي دعوة لا تناسبكم، ولا غرامة على عدم تقديم عرض سعر. (الرسم الوحيد يترتّب إذا سدّد عميل رسوم الاطلاع على بياناتكم ثم تجاهلتموه.)$qd$, $qd$نعم. إذا لم يكن الطلب مناسبًا لكم، فاضغطوا زر «Not for me» عليه في بوابتكم (أو ردّوا بعبارة «ليس لنا» على رسالته الإلكترونية أو عبر واتساب)، ويمكنكم ذكر السبب إن شئتم: لا يُحتسب ذلك عليكم أبدًا، ويساعدنا سببكم على تصحيح التخصصات التي نرسلها إليكم. أما الطلب الذي يُترك دون رد فأمره مختلف: بعد 3 طلبات متتالية وصلتكم دون رد، نوقف إرسال الطلبات الجديدة إليكم مؤقتًا. ننبّهكم بعد الطلب الثاني، ويمكنكم الاستئناف في أي وقت بالرد بعبارة «نحن متاحون» أو بإرسال عرض سعر. (الرسم الوحيد يترتّب إذا سدّد عميل رسوم الاطلاع على بياناتكم ثم تجاهلتموه.)$qd$)
 where agent_key = '_global' and (content like $qd$%there is no penalty for not quoting%$qd$ or content like $qd$%ولا غرامة على عدم تقديم عرض سعر%$qd$);
update public.kb_chunks
   set content = replace(replace(content, $qd$Yes — you are free to ignore any invitation that is not right for you; there is no penalty for not quoting. (The only charge is if a customer pays to reveal you and you then ignore them.)$qd$, $qd$Yes. If a request is not right for you, press “Not for me” on it in your portal (or reply “not for me” to its e-mail or on WhatsApp) and, if you like, tell us why: it never counts against you, and your reason helps us correct the trades we send you. A request you simply leave unanswered is different: after 3 unanswered requests in a row that reached you, we pause new requests to you. We warn you after the second, and you can resume at any time by replying “I’m available” or sending a quotation. (The only charge is if a customer pays to reveal you and you then ignore them.)$qd$), $qd$نعم، لكم أن تتجاهلوا أي دعوة لا تناسبكم، ولا غرامة على عدم تقديم عرض سعر. (الرسم الوحيد يترتّب إذا سدّد عميل رسوم الاطلاع على بياناتكم ثم تجاهلتموه.)$qd$, $qd$نعم. إذا لم يكن الطلب مناسبًا لكم، فاضغطوا زر «Not for me» عليه في بوابتكم (أو ردّوا بعبارة «ليس لنا» على رسالته الإلكترونية أو عبر واتساب)، ويمكنكم ذكر السبب إن شئتم: لا يُحتسب ذلك عليكم أبدًا، ويساعدنا سببكم على تصحيح التخصصات التي نرسلها إليكم. أما الطلب الذي يُترك دون رد فأمره مختلف: بعد 3 طلبات متتالية وصلتكم دون رد، نوقف إرسال الطلبات الجديدة إليكم مؤقتًا. ننبّهكم بعد الطلب الثاني، ويمكنكم الاستئناف في أي وقت بالرد بعبارة «نحن متاحون» أو بإرسال عرض سعر. (الرسم الوحيد يترتّب إذا سدّد عميل رسوم الاطلاع على بياناتكم ثم تجاهلتموه.)$qd$), embedding_gte = null
 where id in (174666, 177559) and (content like $qd$%there is no penalty for not quoting%$qd$ or content like $qd$%ولا غرامة على عدم تقديم عرض سعر%$qd$);

select case
  when not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'inquiry_matches' and column_name = 'decline_reason')
    then 'PROBE FAILED: inquiry_matches has no decline_reason'
  when not exists (select 1 from pg_trigger where tgname = 'z33_quote_contact_removal_is_told' and tgrelid = 'public.quotes'::regclass)
    then 'PROBE FAILED: the contact-removal trigger is missing'
  when has_function_privilege('anon', 'public.fn_supplier_declines_request(bigint, uuid, text, text)', 'execute')
    or has_function_privilege('anon', 'public.fn_reveal_standing(uuid)', 'execute')
    or has_function_privilege('anon', 'public.fn_supplier_live_standing(bigint)', 'execute')
    or has_table_privilege('anon', 'public.supplier_trade_correction', 'select')
    then 'PROBE FAILED: anon can reach a supplier''s standing or answer'
  when public.fn_quote_quality_fixes_en(jsonb_build_array(jsonb_build_object('code', 'price_far_from_peers', 'total', 450000))) !~ 'AED 450,000.00'
    then 'PROBE FAILED: the peer fix line does not name his total'
  else 'PROBE OK' end as verdict;
