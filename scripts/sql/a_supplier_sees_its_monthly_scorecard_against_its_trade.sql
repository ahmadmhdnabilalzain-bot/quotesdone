-- A SUPPLIER SEES ITS MONTHLY SCORECARD AGAINST ITS TRADE, IN THE PORTAL AND BY E-MAIL, IN ENGLISH.
-- Seat: sales_engineer. 29 Sep 2026, founder_instruction 1013 item 2:
--   "A monthly supplier scorecard the supplier can see: response speed, win rate and rating against their trade's
--    average (show the average only when there are at least 3 suppliers), plus one improvement tip chosen by rule.
--    Visible in the supplier portal and sent by email, IN ENGLISH ONLY. With no data, it says 'not enough data yet'."
--
-- WHAT WAS MEASURED (29 Sep 2026, schema mirror and production, read-only):
--   * fn_sales_engineer_supplier_performance (duty sales_engineer.supplier_performance) keeps an INTERNAL score in
--     supplier_performance (reliability, rating, disputes) for matching; nothing shows a supplier his own month
--     against his trade, and no e-mail carries one. fn_supplier_tier (portal "Supplier score") is the tier ladder,
--     not a month's measurement. This file adds the supplier-facing card and leaves both untouched.
--   * The facts exist: inquiry_matches.sent_at (a supplier was sent a request), quotes.created_at (he quoted),
--     transactions (the customer revealed his quote: the customer chose him), inquiries.hired_supplier_id (hired),
--     reviews.rating. A supplier's trade: lead_trade_class.trade_code, else his first confirmed capability trade,
--     else leads.sector.
--
-- WHAT THIS ADDS
--   1. fn_supplier_scorecard_month(p_month): one row per supplier active in the month -
--        response_hours  median hours from a request being sent to him to his first quote on it;
--        win_rate        requests he quoted in the month that the customer revealed him on, or hired him for;
--        rating          his average customer rating given in the month.
--   2. fn_supplier_scorecard(p_lead, p_month): his card. Each metric carries his value and his trade's average; the
--      average is null unless AT LEAST 3 suppliers of his trade (him included) have that metric in the month. With
--      no metric at all the card says "not enough data yet". One tip, by rule (fn_supplier_scorecard_tip), first
--      match wins: invited but quoted nothing; slower than his trade (or over 48 hours with no average); winning
--      less than his trade (or 0 of 3+ quotes); rated below his trade (or under 4/5); otherwise keep going. The
--      default month is the last complete calendar month in Dubai.
--   3. public.supplier_scorecard: the card as sent, one row per supplier and month, never sent twice.
--   4. fn_sales_engineer_supplier_scorecard_tick (duty sales_engineer.supplier_scorecard, daily): for the last
--      complete month, every approved supplier with a portal account gets his card by e-mail, ENGLISH ONLY, through
--      the one delivery door (fn_customer_support_takes_delivery), only to an address fn_email_sendable accepts
--      (email_suppressions, where an unsubscribe lands). A fixture run (qd.duty_fixtures = 'on') selects ONLY demo
--      suppliers, so a probe cannot reach a real one.
--   The portal reads fn_supplier_scorecard through supplier_portal action 'scorecard' (SupplierScorecard.tsx).
--   No model is called: every number is a count and every tip a rule.
--
-- Pending: scripts/sql/pending/a_supplier_sees_its_monthly_scorecard_against_its_trade.txt
-- Proved by: scripts/eval/supplier_scorecard_proof.mjs (one aborted transaction, ZZ DEMO rows).
-- Prevented by: scripts/checks/the_supplier_scorecard_is_english_and_hides_a_thin_average.test.mjs

-- ── 1. a supplier's trade ────────────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_trade(p_lead bigint)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(
    (select nullif(lower(btrim(c.trade_code)), '') from public.lead_trade_class c where c.lead_id = p_lead),
    (select nullif(lower(btrim(sc.trades[1])), '') from public.supplier_capabilities sc where sc.supplier_id = p_lead and sc.confirmed_at is not null),
    (select nullif(lower(btrim(l.sector)), '') from public.leads l where l.id = p_lead))
$fn$;
revoke execute on function public.fn_supplier_trade(bigint) from public, anon, authenticated;

-- ── 2. every supplier's month ────────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_scorecard_month(p_month date)
returns table (lead_id bigint, trade text, invited integer, quoted integer, won integer, response_hours numeric,
               win_rate numeric, rating numeric, ratings integer)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with b as (   -- the month in Dubai, as timestamps
    select (date_trunc('month', p_month)::timestamp at time zone 'Asia/Dubai') as t0,
           ((date_trunc('month', p_month) + interval '1 month')::timestamp at time zone 'Asia/Dubai') as t1
  ), inv as (   -- sent a request in the month, and how long his first quote on it took
    select m.supplier_id, m.inquiry_id, min(m.sent_at) as sent_at,
           (select min(q.created_at) from public.quotes q where q.inquiry_id = m.inquiry_id and q.supplier_id = m.supplier_id) as quoted_at
      from public.inquiry_matches m, b
     where m.sent_at >= b.t0 and m.sent_at < b.t1 and m.supplier_id is not null
     group by m.supplier_id, m.inquiry_id
  ), quo as (   -- quoted in the month, and whether the customer chose him
    select q.supplier_id, q.inquiry_id,
           bool_or(exists (select 1 from public.transactions t where t.inquiry_id = q.inquiry_id and t.supplier_id = q.supplier_id and t.revealed_at is not null)
                   or exists (select 1 from public.inquiries i where i.id = q.inquiry_id and i.hired_supplier_id = q.supplier_id)) as won
      from public.quotes q, b
     where q.created_at >= b.t0 and q.created_at < b.t1 and q.supplier_id is not null
     group by q.supplier_id, q.inquiry_id
  ), rat as (
    select r.supplier_id, avg(r.rating)::numeric as rating, count(*)::int as n
      from public.reviews r, b where r.created_at >= b.t0 and r.created_at < b.t1 and r.supplier_id is not null
     group by r.supplier_id
  ), ids as (select supplier_id from inv union select supplier_id from quo union select supplier_id from rat)
  select s.supplier_id, public.fn_supplier_trade(s.supplier_id),
         (select count(*)::int from inv where inv.supplier_id = s.supplier_id),
         (select count(*)::int from quo where quo.supplier_id = s.supplier_id),
         (select count(*)::int from quo where quo.supplier_id = s.supplier_id and quo.won),
         (select round((percentile_cont(0.5) within group (order by extract(epoch from (inv.quoted_at - inv.sent_at)) / 3600.0))::numeric, 1)
            from inv where inv.supplier_id = s.supplier_id and inv.quoted_at >= inv.sent_at),
         (select round(avg(case when quo.won then 1.0 else 0.0 end), 3) from quo where quo.supplier_id = s.supplier_id),
         (select round(rat.rating, 2) from rat where rat.supplier_id = s.supplier_id),
         coalesce((select rat.n from rat where rat.supplier_id = s.supplier_id), 0)
    from ids s
    join public.leads l on l.id = s.supplier_id
   where not coalesce(l.banned, false)
$fn$;
revoke execute on function public.fn_supplier_scorecard_month(date) from public, anon, authenticated;

-- ── 3. the one tip, by rule ──────────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_scorecard_tip(p_invited integer, p_quoted integer, p_resp numeric, p_resp_avg numeric,
  p_win numeric, p_win_avg numeric, p_rating numeric, p_rating_avg numeric)
returns jsonb language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case
    when coalesce(p_invited, 0) = 0 and coalesce(p_quoted, 0) = 0 and p_rating is null then jsonb_build_object('code', 'complete_profile',
      'text', 'Keep your services, the emirates you cover and your documents complete, so you are matched to more requests.')
    when coalesce(p_invited, 0) > 0 and coalesce(p_quoted, 0) = 0 then jsonb_build_object('code', 'answer_invitations',
      'text', 'You were sent ' || p_invited || ' request' || case when p_invited = 1 then '' else 's' end
        || ' and quoted none. Quoting even a few of them is the fastest way to win work.')
    when p_resp is not null and ((p_resp_avg is not null and p_resp > p_resp_avg) or (p_resp_avg is null and p_resp > 48)) then
      jsonb_build_object('code', 'respond_faster',
      'text', 'Your first quote took ' || p_resp || ' hours' || coalesce(' against your trade''s ' || p_resp_avg, '')
        || '. Customers compare the quotes that arrive first; aim to quote within 24 hours of a request.')
    when p_win is not null and ((p_win_avg is not null and p_win < p_win_avg) or (p_win_avg is null and p_win = 0 and p_quoted >= 3)) then
      jsonb_build_object('code', 'sharpen_quotes',
      'text', 'Customers chose ' || round(p_win * 100) || '% of your quotes' || coalesce(' against your trade''s ' || round(p_win_avg * 100) || '%', '')
        || '. Price every line, and state lead time, validity and warranty: the comparison reads them line by line.')
    when p_rating is not null and ((p_rating_avg is not null and p_rating < p_rating_avg) or (p_rating_avg is null and p_rating < 4)) then
      jsonb_build_object('code', 'lift_rating',
      'text', 'Your customers rated you ' || p_rating || '/5' || coalesce(' against your trade''s ' || p_rating_avg || '/5', '')
        || '. Call the customer within a day of a reveal and confirm the scope and dates in writing.')
    else jsonb_build_object('code', 'keep_going',
      'text', 'You are at or above your trade on every measure we have. Keep your services and documents current so you keep being matched.')
  end
$fn$;
revoke execute on function public.fn_supplier_scorecard_tip(integer, integer, numeric, numeric, numeric, numeric, numeric, numeric) from public, anon, authenticated;

-- ── 4. his card ──────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_supplier_scorecard(p_lead bigint, p_month date default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_month date := coalesce(date_trunc('month', p_month)::date,
                                 (date_trunc('month', (now() at time zone 'Asia/Dubai')) - interval '1 month')::date);
  v_trade text := public.fn_supplier_trade(p_lead); me record; a record; v_any boolean;
begin
  select * into me from public.fn_supplier_scorecard_month(v_month) s where s.lead_id = p_lead;
  -- the trade's average of each metric, only over suppliers who HAVE it, and only when there are at least three
  select case when count(s.response_hours) >= 3 then round(avg(s.response_hours), 1) end as resp,
         count(s.response_hours)::int as resp_n,
         case when count(s.win_rate) >= 3 then round(avg(s.win_rate), 3) end as win,
         count(s.win_rate)::int as win_n,
         case when count(s.rating) >= 3 then round(avg(s.rating), 2) end as rating,
         count(s.rating)::int as rating_n
    into a from public.fn_supplier_scorecard_month(v_month) s where v_trade is not null and s.trade = v_trade;
  v_any := me.response_hours is not null or me.win_rate is not null or me.rating is not null;
  return jsonb_build_object(
    'lead_id', p_lead, 'month', to_char(v_month, 'YYYY-MM'), 'month_label', to_char(v_month, 'FMMonth YYYY'),
    'trade', v_trade, 'trade_label', (select t.label from public.taxonomy_trade t where t.code = v_trade),
    'enough_data', v_any,
    'message', case when v_any then null else 'not enough data yet' end,
    'activity', jsonb_build_object('requests_sent', coalesce(me.invited, 0), 'quoted', coalesce(me.quoted, 0), 'won', coalesce(me.won, 0),
                                   'ratings', coalesce(me.ratings, 0)),
    'metrics', jsonb_build_object(
      'response_hours', jsonb_build_object('you', me.response_hours, 'trade_average', a.resp, 'trade_suppliers', coalesce(a.resp_n, 0), 'better', 'lower'),
      'win_rate',       jsonb_build_object('you', me.win_rate, 'trade_average', a.win, 'trade_suppliers', coalesce(a.win_n, 0), 'better', 'higher'),
      'rating',         jsonb_build_object('you', me.rating, 'trade_average', a.rating, 'trade_suppliers', coalesce(a.rating_n, 0), 'better', 'higher')),
    'min_suppliers_for_average', 3,
    'tip', public.fn_supplier_scorecard_tip(me.invited, me.quoted, me.response_hours, a.resp, me.win_rate, a.win, me.rating, a.rating));
end $fn$;
revoke execute on function public.fn_supplier_scorecard(bigint, date) from public, anon, authenticated;
grant execute on function public.fn_supplier_scorecard(bigint, date) to service_role;

-- ── 5. the card as e-mail text: English only (founder, 28 Sep 2026: a supplier is always written in English) ──
create or replace function public.fn_supplier_scorecard_text(p_card jsonb, p_company text)
returns jsonb language plpgsql immutable set search_path to 'public', 'pg_temp' as $fn$
declare m jsonb := p_card->'metrics'; v_lines text := ''; k text; v jsonb; v_name text;
begin
  if coalesce((p_card->>'enough_data')::boolean, false) then
    foreach k in array array['response_hours', 'win_rate', 'rating'] loop
      v := m->k;
      v_name := case k when 'response_hours' then 'Response speed (median hours to your first quote)'
                       when 'win_rate' then 'Win rate (quotes the customer chose you on)' else 'Customer rating (out of 5)' end;
      v_lines := v_lines || '- ' || v_name || ': '
        || case when v->>'you' is null then 'not enough data yet'
                when k = 'win_rate' then round((v->>'you')::numeric * 100) || '%' else v->>'you' end
        || case when v->>'trade_average' is null then ' (trade average shown once 3 suppliers of your trade have this measure)'
                when k = 'win_rate' then ' (your trade: ' || round((v->>'trade_average')::numeric * 100) || '%)'
                else ' (your trade: ' || (v->>'trade_average') || ')' end || chr(10);
    end loop;
  else
    v_lines := 'There is not enough data yet for a scorecard: no request, quote or rating of yours in ' || (p_card->>'month_label') || '.' || chr(10);
  end if;
  return jsonb_build_object('lang', 'en',
    'subject', 'Your QuotesDone scorecard for ' || (p_card->>'month_label'),
    'body', 'Dear ' || coalesce(nullif(btrim(p_company), ''), 'partner') || ',' || chr(10) || chr(10)
      || 'Here is how you did in ' || (p_card->>'month_label')
      || coalesce(' against other ' || coalesce(p_card->>'trade_label', p_card->>'trade') || ' suppliers', '') || ':' || chr(10) || chr(10)
      || v_lines || chr(10)
      || 'One thing to improve: ' || (p_card->'tip'->>'text') || chr(10) || chr(10)
      || 'Your scorecard is always in your portal under Insights: https://quotesdone.com/supplier' || chr(10) || chr(10)
      || 'QuotesDone Sales Engineering');
end $fn$;
revoke execute on function public.fn_supplier_scorecard_text(jsonb, text) from public, anon, authenticated;

-- ── 6. the card as sent: one per supplier and month ──────────────────────────────────────────────
create table if not exists public.supplier_scorecard (
  lead_id     bigint not null references public.leads (id) on delete cascade,
  month       date not null check (month = date_trunc('month', month)::date),
  card        jsonb not null,
  to_email    text,
  outcome     text not null,
  handoff_id  bigint,
  created_at  timestamptz not null default now(),
  primary key (lead_id, month)
);
comment on table public.supplier_scorecard is
  'The monthly scorecard each supplier was e-mailed (English only), one row per supplier and month. sales_engineer, founder_instruction 1013.';
alter table public.supplier_scorecard enable row level security;
drop policy if exists supplier_scorecard_service_role_only on public.supplier_scorecard;
create policy supplier_scorecard_service_role_only on public.supplier_scorecard
  as permissive for all to public using (false) with check (false);
revoke all on public.supplier_scorecard from anon, authenticated;

-- ── 7. the clock ─────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_sales_engineer_supplier_scorecard_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_month date := (date_trunc('month', (now() at time zone 'Asia/Dubai')) - interval '1 month')::date;
  r record; v_card jsonb; m jsonb; v_ok jsonb; v jsonb; v_sent int := 0; v_held int := 0;
begin
  for r in select l.id, l.company_name, lower(btrim(l.claimed_by)) as mail from public.leads l
            where l.approval_status = 'approved' and nullif(btrim(l.claimed_by), '') is not null
              and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)
              and (coalesce(l.is_demo, false) or public.fn_is_demo_email(l.claimed_by)) = v_fx
              and not exists (select 1 from public.supplier_scorecard s where s.lead_id = l.id and s.month = v_month)
            order by l.id limit 500 loop
    v_card := public.fn_supplier_scorecard(r.id, v_month);
    m := public.fn_supplier_scorecard_text(v_card, r.company_name);
    v_ok := public.fn_email_sendable(r.mail);
    if not coalesce((v_ok->>'ok')::boolean, false) then
      insert into public.supplier_scorecard (lead_id, month, card, to_email, outcome)
      values (r.id, v_month, v_card, r.mail, 'not_sendable: ' || (v_ok->>'reason'));
      v_held := v_held + 1;
      continue;
    end if;
    v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_scorecard', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', r.mail, 'to_role', 'supplier', 'lead_id', r.id, 'lang', 'en',
      'dedupe_key', 'supplier_scorecard:' || r.id || ':' || to_char(v_month, 'YYYY-MM'),
      'subject', m->>'subject', 'body', m->>'body')));
    insert into public.supplier_scorecard (lead_id, month, card, to_email, outcome, handoff_id)
    values (r.id, v_month, v_card, r.mail, 'queued', (v->0->>'handoff_id')::bigint);
    v_sent := v_sent + 1;
  end loop;
  return jsonb_build_object('month', to_char(v_month, 'YYYY-MM'), 'sent', v_sent, 'not_sendable', v_held);
end $fn$;
revoke execute on function public.fn_sales_engineer_supplier_scorecard_tick() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_supplier_scorecard_tick() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.supplier_scorecard', 'sales_engineer', interval '1 day', 'fn_sales_engineer_supplier_scorecard_tick',
   'e-mail every approved supplier his last month''s scorecard against his trade, in English, once a month',
   'scripts/sql/a_supplier_sees_its_monthly_scorecard_against_its_trade.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
