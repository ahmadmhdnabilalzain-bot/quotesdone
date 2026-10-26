-- SUPPORT ASKS FOR A RATING THREE WEEKS AFTER THE REVEAL
-- Agent: customer_support.
--
-- The founder, 9 Sep 2026: "supplier reputation should be zero cause no supplier is verified.
-- supplier rating should be from customers after they tried them. support should send an email
-- after 3 weeks from the reveal date."
--
-- This SUPERSEDES the earlier rule that a rating was solicited at the reveal moment. At the reveal
-- the customer has paid for a phone number and nothing else; they have no opinion worth recording.
-- Three weeks later they have either worked with the supplier or been ignored by them, and both of
-- those are ratings.
--
-- WHAT WAS ALREADY TRUE AND IS NOT "FIXED" HERE. public.supplier_reputation is a VIEW over
-- public.reviews. Measured 9 Sep 2026: 22,264 suppliers, 0 with review_count > 0, 0 with a
-- non-null overall — because reviews holds 0 rows. The founder's "reputation should be zero" is
-- already the case; nothing in this file changes the view, and nothing in it makes a Google Maps
-- rating look earned. customer_api's ratingOf() keeps labelling those source: 'Google'.
--
-- WHAT THIS ADDS. One routine that finds every reveal at or past the configured age, has not been
-- rated, has not already been asked, and was not refunded — and enqueues ONE customer-facing email
-- per transaction into public.notifications, which is the pipe Support already owns and
-- send_outbox already drains. It does not send anything itself; it does not open a second channel.
--
-- WHERE IT POINTS. customer_api already accepts the rating: action 'rate_supplier', keyed by
-- quote_id, upserting into reviews on transaction_id and calling recompute_supplier_rating. The
-- email points at that existing flow in the customer portal. No second submission path is invented.

-- ---------------------------------------------------------------------------------------------
-- 1. THE ONE KNOB
-- ---------------------------------------------------------------------------------------------
-- Three weeks is the founder's number today, not a law of nature. It lives in app_secrets and is
-- read at run time, so changing it is an UPDATE and not a deploy.
insert into public.app_secrets (key, value)
values ('rating_request_days_after_reveal', '21')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 2. THE IDEMPOTENCY KEY — A UNIQUE INDEX ON THE BUSINESS EVENT
-- ---------------------------------------------------------------------------------------------
-- The business event is "this transaction's customer has been asked to rate this supplier".
-- transactions_quote_id_uidx makes quote_id <-> transaction one-to-one, so the ask's key is the
-- quote_id of the notification row itself. No side table, no second bookkeeping surface to drift.
--
-- WHY THE INDEX IS SCOPED TO THE EMAIL ROW. fn_wa_fanout fires AFTER INSERT and copies type and
-- quote_id onto a second row with channel='whatsapp' for an opted-in customer. An index that did
-- not exclude that row would make the fanout raise a unique violation inside a trigger and take the
-- whole insert down with it.
--
-- WHY THE GUARD BELOW IS UNFILTERED. fn_agent_action_work_sweep filters its `not exists` by status,
-- so a row that FAILED still occupies the unique key without satisfying the guard: the sweep retries
-- forever into a unique violation, and its '#2' suffix workaround caps attempts at two. Here, a row
-- in ANY state — queued, sent, failed, held, suppressed, skipped, digest — means "already asked",
-- which is the truth: the ask was made and the outbox owns what happened to it afterwards.
create unique index if not exists notifications_rating_request_uidx
  on public.notifications (quote_id)
  where type = 'rating_request' and coalesce(channel, 'email') = 'email';

comment on index public.notifications_rating_request_uidx is
  'One rating request per revealed quote, ever. Scoped to the email row because fn_wa_fanout inserts a whatsapp twin carrying the same type and quote_id.';

-- ---------------------------------------------------------------------------------------------
-- 3. THE SWEEP
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_support_request_ratings_due(p_limit integer default 500)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_days     integer;
  v_site     text;
  v_founder  text;
  v_asked    integer := 0;
begin
  select nullif(regexp_replace(coalesce(value, ''), '[^0-9]', '', 'g'), '')::int
    into v_days from public.app_secrets where key = 'rating_request_days_after_reveal';
  v_days := coalesce(v_days, 21);

  select coalesce(value, 'https://quotesdone.com') into v_site
    from public.app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');

  -- The founder's own address, so a customer record that happens to carry it is never asked.
  -- fn_notifications_founder_mail_policy intercepts founder-directed mail whose kind is not
  -- allowed_to_email and returns NULL: the row is silently not inserted, the unique key stays free,
  -- and this sweep would re-ask that one transaction every 15 minutes forever.
  select lower(nullif(split_part(coalesce(value, ''), ',', 1), '')) into v_founder
    from public.app_secrets where key = 'admin_emails';

  with due as (
    select t.id as tx_id, t.quote_id, t.inquiry_id, t.supplier_id,
           c.email as cemail, l.company_name, i.summary
      from public.transactions t
      join public.customers c on c.id = t.customer_id
      left join public.leads l on l.id = t.supplier_id
      left join public.inquiries i on i.id = t.inquiry_id
     where t.revealed_at is not null
       and t.revealed_at <= now() - make_interval(days => v_days)
       and t.quote_id is not null
       -- 4. NEVER ASK ABOUT A REFUNDED OR REVERSED REVEAL.
       -- MEASURED, NOT ASSUMED: trg_reveal_window sets refund_status := 'window_open' on EVERY
       -- reveal, so "refund_status is null" describes no real transaction at all — a guard written
       -- as `coalesce(refund_status,'none') = 'none'` asks nobody, ever, and its zero would have
       -- looked exactly like "nothing was due". The live vocabulary is
       -- none / window_open / requested / approved / refunded / declined.
       -- This is an ALLOWLIST of the states where the money is still ours and undisputed, plus
       -- 'declined' (the customer complained and the complaint was refused — their opinion is then
       -- the most informative rating on the platform). An unrecognised future state falls out of the
       -- list and is simply not asked, which is the safe direction to fail.
       and coalesce(t.refund_status, 'none') in ('none', 'window_open', 'declined')
       and coalesce(c.email, '') like '%@%'
       and lower(coalesce(c.email, '')) is distinct from coalesce(v_founder, '~none~')
       -- 3. STOP ASKING WHEN IT IS ANSWERED. A review closes the ask permanently.
       and not exists (select 1 from public.reviews r where r.transaction_id = t.id)
       -- 2. ASKED ONCE, EVER — looked up in ANY state.
       and not exists (select 1 from public.notifications n
                        where n.type = 'rating_request' and n.quote_id = t.quote_id)
     -- A deterministic order shared by every session, so two concurrent runs take the same key in
     -- the same sequence. With one target table, one lock per key and ON CONFLICT DO NOTHING, there
     -- is no second resource to hold and therefore no cycle: this cannot deadlock.
     order by t.revealed_at, t.quote_id
     limit greatest(coalesce(p_limit, 500), 1)
  ), ins as (
    -- 1. SUPPORT SENDS IT. public.notifications is the estate's one channel queue; kind
    -- 'support_agent' is already registered in founder_mail_policy as customer_support's own
    -- customer-facing mail. The Sales Engineer is not involved and no new send path exists.
    insert into public.notifications
      (type, kind, to_email, to_role, lead_id, inquiry_id, quote_id, subject, body, channel, status)
    select 'rating_request', 'support_agent', d.cemail, 'customer',
           d.supplier_id, d.inquiry_id, d.quote_id,
           'How did ' || coalesce(d.company_name, 'your supplier') || ' do?',
           'It has been about ' || v_days || ' days since you unlocked '
             || coalesce(d.company_name, 'this supplier')
             || coalesce(' for: ' || left(d.summary, 80), '')
             || '. Now that you have had the chance to actually work with them, please rate them out '
             || 'of 5 — communication, quality, punctuality, documentation and after-sales. Open the '
             || 'job in your portal and choose Rate supplier: ' || v_site || '/portal'
             || '. Ratings on QuotesDone come only from customers who have paid to reveal a supplier '
             || 'and dealt with them, so yours is what gives this company a score at all.',
           'email', 'queued'
      from due d
    on conflict (quote_id) where type = 'rating_request' and coalesce(channel, 'email') = 'email'
    do nothing
    returning 1
  )
  select count(*)::int into v_asked from ins;

  return jsonb_build_object('ok', true, 'asked', v_asked, 'days_after_reveal', v_days,
    'note', 'Enqueued into public.notifications as customer_support. send_outbox delivers; a row in any state means the ask was already made.');
end $function$;

comment on function public.fn_support_request_ratings_due(integer) is
  'Support asks the customer to rate the supplier N days after the reveal (app_secrets.rating_request_days_after_reveal, default 21). Skips reveals already rated, already asked in any state, and any transaction whose refund_status is not one of none/window_open/declined. Idempotent on notifications_rating_request_uidx.';

revoke execute on function public.fn_support_request_ratings_due(integer) from public;
revoke execute on function public.fn_support_request_ratings_due(integer) from anon;
revoke execute on function public.fn_support_request_ratings_due(integer) from authenticated;
