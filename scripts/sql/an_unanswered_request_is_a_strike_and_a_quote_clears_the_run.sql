-- Seat: sales_engineer (matching), delivered by customer_support. Assigned: customer_support (supplier follow-up of #1909,
-- item 6; founder ruling 1608).
--
-- THE RULE IS THE FOUNDER'S, 3 Aug 2026: a supplier with THREE CONSECUTIVE UNANSWERED RFQs stops receiving them
-- (docs/archive/brain/marketplace.md JP7; decision_policy.matching_strike_limit = 3, written 3 Aug 2026 18:17 UTC, "How
-- many times a supplier may ignore an RFQ before the matcher stops offering them work"). fn_is_matchable enforces it
-- (chat_strikes < fn_matching_strike_limit()) and the supplier portal's eligibility panel explains it ("Requests sent to
-- you went unanswered N times, which pauses new requests").
--
-- MEASURED on origin/main (production, 10 Nov 2026): NOTHING writes leads.chat_strikes. No routine body and no edge
-- function assigns it (the schema mirror and supabase/functions searched); 0 leads have a strike. The gate could never
-- close and the panel's sentence could never be true.
--
-- WHAT THIS CHANGES (no new number: the window is the platform's own "no quote in time" window):
--   * A STRIKE: when a request ends as expired, lost or completed (the request-outcome duty of #1906, a hire, a
--     completion), every supplier it was sent to at least request_no_quote_expiry_days (21) before that end and who put
--     NO quote on it (any status: a draft, a held or a withdrawn quote is an answer) gets one strike. A request the
--     customer CANCELLED is not the supplier's silence and counts nothing; nor does one that ended before he had the
--     full window to answer, or one still waiting for the customer's details (rfq_ready not true: it could not be priced).
--   * CONSECUTIVE: any quote the supplier writes clears his run to 0 (a quote is an answer).
--   * Each strike and each clearing is recorded in public.supplier_strike_event (append-only), so the count on the lead
--     can always be explained, and so a request is counted once per supplier however often its status moves.
-- NOT CHANGED: fn_is_matchable, fn_matching_strike_limit, the portal's copy; no message is sent on a strike (the
-- eligibility panel already names it); nothing lifts a strike but a quote.
-- prevented by: scripts/checks/an_unanswered_request_is_a_strike_and_a_quote_clears_the_run.test.mjs and this file's _probe.sql.
-- Pending until the release applies it: scripts/sql/pending/an_unanswered_request_is_a_strike_and_a_quote_clears_the_run.txt

create table if not exists public.supplier_strike_event (
  id bigint generated always as identity primary key,
  lead_id bigint not null references public.leads(id) on delete cascade,
  inquiry_id uuid,
  kind text not null check (kind in ('strike', 'cleared')),
  strikes_after int not null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
-- one strike per supplier per request, however often the request's status moves
create unique index if not exists supplier_strike_event_one_per_request on public.supplier_strike_event (lead_id, inquiry_id) where kind = 'strike';
alter table public.supplier_strike_event enable row level security;
drop policy if exists supplier_strike_event_service_role_only on public.supplier_strike_event;
create policy supplier_strike_event_service_role_only on public.supplier_strike_event as permissive for all to public using (false) with check (false);
revoke all on public.supplier_strike_event from anon, authenticated;

create or replace function public.fn_supplier_strike_event_append_only()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
begin
  raise exception 'supplier_strike_event is append-only' using errcode = '42501';
end $fn$;
revoke execute on function public.fn_supplier_strike_event_append_only() from public, anon, authenticated;
drop trigger if exists a10_supplier_strike_event_append_only on public.supplier_strike_event;
create trigger a10_supplier_strike_event_append_only before update or delete on public.supplier_strike_event
  for each row execute function public.fn_supplier_strike_event_append_only();

-- The strikes of one ended request: its matched suppliers who had the full window and wrote no quote.
create or replace function public.fn_sales_engineer_counts_unanswered_request(p_inquiry uuid, p_ended_at timestamptz default now())
 returns int
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_window int := public.fn_seat_clock_policy('request_no_quote_expiry_days', 21)::int; r record; v_n int := 0; v_after int;
begin
  for r in
    select m.supplier_id, min(m.sent_at) as sent_at
      from public.inquiry_matches m
     where m.inquiry_id = p_inquiry and m.supplier_id is not null
     group by m.supplier_id
    having min(m.sent_at) <= p_ended_at - make_interval(days => v_window)
       and not exists (select 1 from public.quotes q where q.inquiry_id = p_inquiry and q.supplier_id = m.supplier_id)
  loop
    insert into public.supplier_strike_event (lead_id, inquiry_id, kind, strikes_after, detail)
    select r.supplier_id, p_inquiry, 'strike', coalesce(l.chat_strikes, 0) + 1,
           jsonb_build_object('sent_at', r.sent_at, 'ended_at', p_ended_at, 'window_days', v_window, 'rule', 'matching_strike_limit (founder, 3 Aug 2026)')
      from public.leads l where l.id = r.supplier_id
    on conflict do nothing;
    if found then
      update public.leads set chat_strikes = coalesce(chat_strikes, 0) + 1 where id = r.supplier_id returning chat_strikes into v_after;
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end $fn$;
revoke execute on function public.fn_sales_engineer_counts_unanswered_request(uuid, timestamptz) from public, anon, authenticated;

create or replace function public.trg_request_end_counts_unanswered_suppliers()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
begin
  -- expired, lost or completed: the supplier had the request and the window. cancelled is the customer's choice; closed
  -- is a split parent, whose parts are counted as they end.
  -- A request still waiting for the customer's details (rfq_ready not true) could not be priced: nobody's silence.
  if coalesce(NEW.status, '') in ('expired', 'lost', 'completed') and NEW.rfq_ready is true
     and coalesce(OLD.status, '') not in ('completed', 'closed', 'cancelled', 'expired', 'lost') then
    perform public.fn_sales_engineer_counts_unanswered_request(NEW.id, now());
  end if;
  return NEW;
end $fn$;
revoke execute on function public.trg_request_end_counts_unanswered_suppliers() from public, anon, authenticated;
drop trigger if exists z32_request_end_counts_unanswered_suppliers on public.inquiries;
create trigger z32_request_end_counts_unanswered_suppliers after update of status on public.inquiries
  for each row execute function public.trg_request_end_counts_unanswered_suppliers();

create or replace function public.trg_a_quote_clears_the_strike_run()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare v_prev int;
begin
  select chat_strikes into v_prev from public.leads where id = NEW.supplier_id;
  if coalesce(v_prev, 0) > 0 then
    update public.leads set chat_strikes = 0 where id = NEW.supplier_id;
    insert into public.supplier_strike_event (lead_id, inquiry_id, kind, strikes_after, detail)
    values (NEW.supplier_id, NEW.inquiry_id, 'cleared', 0, jsonb_build_object('cleared_from', v_prev, 'quote_id', NEW.id));
  end if;
  return NEW;
end $fn$;
revoke execute on function public.trg_a_quote_clears_the_strike_run() from public, anon, authenticated;
drop trigger if exists z32_a_quote_clears_the_strike_run on public.quotes;
create trigger z32_a_quote_clears_the_strike_run after insert on public.quotes
  for each row when (NEW.supplier_id is not null) execute function public.trg_a_quote_clears_the_strike_run();

select case
  when not exists (select 1 from pg_trigger where tgname = 'z32_request_end_counts_unanswered_suppliers' and tgrelid = 'public.inquiries'::regclass)
    or not exists (select 1 from pg_trigger where tgname = 'z32_a_quote_clears_the_strike_run' and tgrelid = 'public.quotes'::regclass)
    then 'PROBE FAILED: a strike trigger is missing'
  when has_function_privilege('anon', 'public.fn_sales_engineer_counts_unanswered_request(uuid, timestamptz)', 'execute')
    or has_table_privilege('anon', 'public.supplier_strike_event', 'select')
    then 'PROBE FAILED: anon can reach the strike record'
  else 'PROBE OK' end as verdict;
