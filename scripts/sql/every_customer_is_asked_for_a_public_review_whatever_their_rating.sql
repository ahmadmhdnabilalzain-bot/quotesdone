-- EVERY CUSTOMER IS ASKED FOR A PUBLIC REVIEW, WHATEVER THEIR RATING.
-- Seat: marketing. 28 Sep 2026. Supersedes the reputation routine of
-- marketing_recruits_where_supply_is_short_and_keeps_the_companys_reputation.sql.
--
-- WHAT WAS WRONG (read from supabase/schema/full_schema.sql, equal to production)
--   fn_marketing_reputation chose who to ask from public.reviews, keeping only the ratings of 4 and 5,
--   and its email thanked the customer "for rating your experience so well". Choosing who is asked by
--   the rating they gave is review gating, which Google's review policy forbids.
--
-- WHAT THIS DOES
--   * Who is asked is decided by the JOB, never by a review: one ask per revealed transaction, once the
--     same wait as customer_support's rating request has passed (app_secrets
--     rating_request_days_after_reveal, default 21 days = 3 weeks), not refunded or reversed, the
--     customer reachable by email, not banned, not a fixture (is_demo), and the address on no
--     email_suppressions row of ANY reason (an unsubscribe is the customer's opt-out, a bounce or complaint
--     is suppression; either stops the ask).
--   * company_review_ask no longer carries a rating or a review id, so no later edit can filter on
--     them. It is keyed per job (transaction_id unique); old per-customer rows keep their id and are
--     read as before.
--   * The wording is the same for every customer.
--   * A low rating stays visible where it was: the daily snapshot's low_ratings_30d. It is a reading
--     for customer_support's service recovery and plays no part in whether the ask goes out.
--
-- Prevented by: scripts/checks/a_review_ask_never_filters_on_rating.test.mjs (fails if the ask's chooser
-- or the ask table ever names a rating). Probe: every_customer_is_asked_for_a_public_review_whatever_their_rating_probe.sql.

alter table public.company_review_ask add column if not exists id bigint generated always as identity;
alter table public.company_review_ask add column if not exists transaction_id uuid references public.transactions (id) on delete cascade;
alter table public.company_review_ask drop constraint if exists company_review_ask_pkey;
alter table public.company_review_ask add constraint company_review_ask_pkey primary key (id);
create unique index if not exists company_review_ask_one_per_job on public.company_review_ask (transaction_id);
create index if not exists company_review_ask_by_customer on public.company_review_ask (customer_id);
alter table public.company_review_ask drop column if exists rating;
alter table public.company_review_ask drop column if exists review_id;

-- The jobs owed an ask. Nothing here reads public.reviews: what a customer thought decides nothing.
-- p_include_fixtures exists only so a probe can run the chooser on ZZ DEMO rows (every ZZ DEMO customer is
-- is_demo by its generated column). The duty calls it with no argument; it is service_role only.
create or replace function public.fn_marketing_review_ask_candidates(p_include_fixtures boolean default false)
returns table (transaction_id uuid, customer_id uuid)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select t.id, t.customer_id
    from public.transactions t
    join public.customers c on c.id = t.customer_id
   where t.revealed_at is not null
     and t.revealed_at <= now() - make_interval(days => coalesce((select nullif(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g'), '')::int
                                                                   from public.app_secrets where key = 'rating_request_days_after_reveal'), 21))
     and coalesce(t.refund_status, 'none') in ('none', 'window_open', 'declined')
     and coalesce(c.banned, false) = false
     and (p_include_fixtures or coalesce(c.is_demo, false) = false)
     and coalesce(btrim(c.email), '') like '%@%'
     and not exists (select 1 from public.email_suppressions s where lower(btrim(s.email)) = lower(btrim(c.email)))
     and not exists (select 1 from public.company_review_ask a where a.transaction_id = t.id)
   order by t.revealed_at, t.id
$fn$;
revoke execute on function public.fn_marketing_review_ask_candidates(boolean) from public, anon, authenticated;
grant execute on function public.fn_marketing_review_ask_candidates(boolean) to service_role;

create or replace function public.fn_marketing_reputation()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_link text := nullif(btrim((select value from public.app_secrets where key = 'public_review_url')), '');
  r record; v_asked int := 0; v_waiting int := 0; v_ar boolean;
begin
  insert into public.company_review_ask (customer_id, transaction_id, status)
  select k.customer_id, k.transaction_id, 'waiting_link' from public.fn_marketing_review_ask_candidates() k
  on conflict (transaction_id) do nothing;

  if v_link is null then
    select count(*) into v_waiting from public.company_review_ask where status = 'waiting_link';
    if v_waiting > 0 then
      perform public.fn_it_engineer_finding_upsert('reputation:no_public_review_link',
        v_waiting || ' customer job(s) are waiting to be asked for a public review, and no review link is configured',
        'app_secrets public_review_url', 'monitor', v_waiting, jsonb_build_object('owner_seat', 'marketing'),
        '{}'::text[], array['the Google Business Profile or directory review link to use'], 'marketing');
    end if;
  else
    update public.it_engineer_finding set closed_at = now(), close_note = 'a public review link is configured'
     where issue_key = 'reputation:no_public_review_link' and closed_at is null;
    for r in select a.id, a.customer_id, coalesce(a.transaction_id::text, a.customer_id::text) as job,
                    c.full_name, lower(btrim(c.email)) as email, c.locale
               from public.company_review_ask a join public.customers c on c.id = a.customer_id
              where a.status = 'waiting_link' and a.created_at > now() - interval '60 days'
                and not exists (select 1 from public.email_suppressions s where lower(btrim(s.email)) = lower(btrim(c.email)))
              order by a.id limit 50 loop
      v_ar := r.locale = 'ar';
      -- customer_support is the only seat that addresses a customer; the ask is marketing's, the send is support's.
      perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'public_review_ask', 'requested_by', 'customer_support', 'channel', 'email', 'to_email', r.email,
        'to_role', 'customer', 'lang', case when v_ar then 'ar' else 'en' end, 'dedupe_key', 'public_review_ask:' || r.job,
        'subject', case when v_ar then 'هل تشاركون تجربتكم مع QuotesDone؟' else 'Would you share your experience of QuotesDone?' end,
        'body', case when v_ar then
            'عزيزنا ' || coalesce(nullif(btrim(r.full_name), ''), 'العميل') || '،' || chr(10) || chr(10)
            || 'شكرًا لاستخدامكم QuotesDone. نرحب برأيكم الصريح علنًا، أيًّا كان، فذلك يساعد غيركم على اختيار موردين موثوقين: '
            || v_link || chr(10) || chr(10) || 'مع خالص الشكر والتقدير،'
          else
            'Dear ' || coalesce(nullif(btrim(r.full_name), ''), 'customer') || ',' || chr(10) || chr(10)
            || 'Thank you for using QuotesDone. If you have a minute, we would welcome your honest public review, '
            || 'whatever your experience; it helps other companies find reliable suppliers: ' || v_link
            || chr(10) || chr(10) || 'QuotesDone' end)));
      update public.company_review_ask set status = 'asked', asked_at = now() where id = r.id;
      v_asked := v_asked + 1;
    end loop;
  end if;

  -- The snapshot measures reputation; it is written after the asks and decides none of them.
  insert into public.company_reputation_snapshot as s (day, reviews, avg_rating, low_ratings_30d, asks_sent, asks_waiting)
  select (now() at time zone 'Asia/Dubai')::date, count(*), round(avg(rating)::numeric, 2),
         count(*) filter (where rating <= 2 and created_at > now() - interval '30 days'),
         (select count(*) from public.company_review_ask where status = 'asked'),
         (select count(*) from public.company_review_ask where status = 'waiting_link')
    from public.reviews
  on conflict (day) do update set reviews = excluded.reviews, avg_rating = excluded.avg_rating, low_ratings_30d = excluded.low_ratings_30d,
    asks_sent = excluded.asks_sent, asks_waiting = excluded.asks_waiting;
  return jsonb_build_object('asked', v_asked, 'waiting_for_link', v_link is null,
    'snapshot', (select to_jsonb(s) from public.company_reputation_snapshot s where day = (now() at time zone 'Asia/Dubai')::date));
end $fn$;
revoke execute on function public.fn_marketing_reputation() from public, anon, authenticated;
grant execute on function public.fn_marketing_reputation() to service_role;

update public.seat_duty
   set what = 'Every customer with a revealed, unrefunded job is asked once per job, 3 weeks after the reveal, through customer_support, for a public review, whatever their rating; a daily reputation snapshot.',
       owner_file = 'scripts/sql/every_customer_is_asked_for_a_public_review_whatever_their_rating.sql'
 where duty = 'marketing.reputation';
