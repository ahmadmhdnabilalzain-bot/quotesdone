-- A PAID REVEAL WITH NO SALE IS FOUND AND RECORDED WITHIN THE HOUR.
--
-- Seat: accountant (every payment path is the accountant's, founder 14 Sep 2026). 3 Nov 2026.
--
-- THE GAP (read from the repository, 3 Nov 2026): a Payment Element reveal is recorded in public.transactions from three
-- places, all through recordRevealSale (supabase/functions/_shared/reveal_sale.ts): stripe_checkout element_pay,
-- element_settle after 3-D Secure, and stripe_webhook invoice.paid. Since #1835 the webhook answers Stripe 500 rather
-- than record an invoice id when it cannot read the PaymentIntent, so Stripe delivers the event again; Stripe stops
-- after about three days. If all three fail, the customer has paid, has no supplier revealed, and the books hold
-- nothing. No routine compared Stripe's paid reveals with the books (the hourly accountant duties read payouts, fees,
-- disputes and the charge audit of sales ALREADY recorded). The reviewer of #1835 named it.
--
-- WHAT THIS BUILDS
--   1. The sweep, in the accountant runtime (supabase/functions/accountant, action 'reveal_reconcile', pure logic in
--      supabase/functions/_shared/reveal_reconcile.ts): Stripe's paid invoices and succeeded PaymentIntents of the last
--      gl_settings.reveal_reconcile_window_days (30) days that carry metadata.quote_id, live and test keys, are matched
--      against transactions by stripe_invoice_id, then payment_ref; each one unmatched is recorded through
--      recordRevealSale with its PaymentIntent (never the invoice id). Bounded: 5 pages of 100 per list per mode, 25
--      recordings per run, nothing paid in the last 15 minutes. Idempotent: a match writes nothing, and recordRevealSale
--      is idempotent on quote_id (transactions.quote_id is unique).
--   2. public.accountant_reveal_reconcile_item: one row per Stripe payment the sweep could NOT simply match (recovered,
--      second payment, refunded, failed, deferred), keyed on the invoice id (pi_ when there is none). The audit record
--      of every sale the sweep wrote and every one it could not.
--   3. public.accountant_reveal_reconcile_run: one row per dispatch, the pg_net request and what the runtime reported.
--   4. fn_accountant_reveal_reconcile_record(run, readings): what the runtime calls with its outcomes. Upserts the items,
--      resolves any the books now hold by another path, then files the findings.
--   5. fn_accountant_reveal_reconcile_findings(): ONE accountant finding per payment still unresolved, computed from the
--      tables (never from one run, so a run that could not read Stripe closes nothing), through fn_accountant_duty_settle
--      ('reveal_reconcile'): a payment that could not be recorded, a partial refund of an unrecorded payment, a second
--      payment of a sold quote (for a CEO refund; not filed twice when recordRevealSale already raised
--      reveal:second_payment:<pi>, #1835), a backlog over the per-run bound for 3 hours, a sweep that has not reported
--      for 3 hours, a live Stripe that could not be read, a listing cut by its bound. DEMO PAYMENTS FILE NOTHING: a
--      test-mode payment (stripe_checkout serves demo accounts the test keys only), an email fn_is_demo_email names, or
--      a customer whose is_demo is true. They are still recorded, as every other path records them.
--   6. fn_accountant_reveal_reconcile_tick(): seat duty accountant.reveal_reconcile, every hour. Reads back the last
--      dispatch's HTTP status, sends the next one (none while one is in flight, under 30 minutes), keeps 60 days of runs,
--      and settles the findings. It never reads Stripe or the books itself.
-- SECURITY DEFINER, search_path pinned, EXECUTE revoked from public, anon and authenticated (CREATE grants PUBLIC);
-- the record routine is granted to service_role, which the runtime calls it as. Both tables RLS on, deny-all policy,
-- revoked from anon and authenticated, and registered in table_export_registry.
-- No begin/commit: the applier runs the file as one transaction. Ends with a verdict row (PROBE OK or PROBE FAILED).
-- NOT CHANGED: recordRevealSale, stripe_checkout, stripe_webhook, fn_accountant_duty_settle (called, not redefined).
--   node scripts/apply_sql.mjs scripts/sql/a_paid_reveal_with_no_sale_is_found_and_recorded_within_the_hour.sql --apply --ddl --seat accountant
-- prevented by: supabase/functions/_shared/reveal_reconcile.test.ts,
--               scripts/checks/a_paid_reveal_with_no_sale_is_found_and_recorded_within_the_hour.test.mjs,
--               scripts/sql/a_paid_reveal_with_no_sale_is_found_and_recorded_within_the_hour_probe.sql

insert into public.gl_settings (key, num_value, txt_value) values ('reveal_reconcile_window_days', 30,
  'Days of Stripe paid reveals the accountant''s hourly reveal sweep compares with the books (1 to 90; fn_accountant_reveal_reconcile_tick).')
on conflict (key) do nothing;

-- ── 2 and 3. The tables ───────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.accountant_reveal_reconcile_run (
  id            bigint generated always as identity primary key,
  requested_at  timestamptz not null default now(),
  window_days   integer not null check (window_days between 1 and 90),
  request_id    bigint,
  http_status   integer,
  http_error    text,
  reported_at   timestamptz,
  result        jsonb
);
comment on table public.accountant_reveal_reconcile_run is
  'One row per dispatch of the accountant''s hourly reveal sweep: the pg_net request, its HTTP status, and the readings the runtime reported (no outcomes; those are accountant_reveal_reconcile_item).';
create index if not exists accountant_reveal_reconcile_run_reported_idx on public.accountant_reveal_reconcile_run (reported_at desc);

create table if not exists public.accountant_reveal_reconcile_item (
  key             text primary key check (key ~ '^(in|pi)_[A-Za-z0-9_]+$'),
  livemode        boolean not null,
  source          text not null check (source in ('invoice', 'payment_intent')),
  quote_id        text not null check (btrim(quote_id) <> ''),
  invoice_id      text,
  payment_intent  text,
  customer_id     text,
  customer_email  text,
  amount_fils     bigint,
  currency        text,
  paid_at         timestamptz,
  demo            boolean not null default false,
  outcome         text not null check (outcome in ('recovered', 'second_payment', 'refunded', 'refunded_unrecorded',
                                                   'failed', 'deferred', 'recorded_elsewhere')),
  transaction_id  uuid,
  error           text,
  attempts        integer not null default 1,
  first_seen_at   timestamptz not null default now(),
  last_seen_at    timestamptz not null default now(),
  last_run_id     bigint,
  resolved_at     timestamptz
);
comment on table public.accountant_reveal_reconcile_item is
  'Every Stripe-paid reveal the accountant''s hourly sweep found with no sale in the books: recovered through recordRevealSale, a second payment, refunded, or not recordable (a finding until resolved).';
create index if not exists accountant_reveal_reconcile_item_open_idx on public.accountant_reveal_reconcile_item (outcome) where resolved_at is null;

alter table public.accountant_reveal_reconcile_run enable row level security;
drop policy if exists accountant_reveal_reconcile_run_service_role_only on public.accountant_reveal_reconcile_run;
create policy accountant_reveal_reconcile_run_service_role_only on public.accountant_reveal_reconcile_run
  as permissive for all to public using (false) with check (false);
revoke all on public.accountant_reveal_reconcile_run from anon, authenticated;

alter table public.accountant_reveal_reconcile_item enable row level security;
drop policy if exists accountant_reveal_reconcile_item_service_role_only on public.accountant_reveal_reconcile_item;
create policy accountant_reveal_reconcile_item_service_role_only on public.accountant_reveal_reconcile_item
  as permissive for all to public using (false) with check (false);
revoke all on public.accountant_reveal_reconcile_item from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('accountant_reveal_reconcile_item', true, 'accountant',
   'Every Stripe-paid reveal the accountant''s sweep found with no sale: what it recorded and what it could not (the audit trail of recovered sales).', 'accountant'),
  ('accountant_reveal_reconcile_run', false, 'log',
   'One row per hourly dispatch of the reveal sweep (request id, HTTP status, readings); kept 60 days. The outcomes are in accountant_reveal_reconcile_item, which is exported.', 'accountant')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- ── 5. The findings, from the tables ──────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_reveal_reconcile_findings()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_items jsonb; v_last public.accountant_reveal_reconcile_run; v_live jsonb; v_req timestamptz;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
      'item', i.outcome || ':' || i.key,
      'owner_seat', case when i.outcome = 'second_payment' then 'ceo' else 'accountant' end,
      'subject', 'transactions',
      'title', case i.outcome
        when 'failed' then 'A paid reveal has no sale: Stripe ' || i.key || ' (AED ' || round(coalesce(i.amount_fils, 0) / 100.0, 2)
                           || ', quote ' || i.quote_id || ') could not be recorded: ' || coalesce(left(i.error, 160), 'no reason given')
        when 'refunded_unrecorded' then 'A paid reveal with no sale was partly refunded: Stripe ' || i.key || ' (quote ' || i.quote_id
                           || '); decide whether the sale is recorded or the rest refunded'
        when 'second_payment' then 'A revealed quote was paid a second time: ' || coalesce(i.payment_intent, i.key)
                           || ' (AED ' || round(coalesce(i.amount_fils, 0) / 100.0, 2) || ', quote ' || i.quote_id || ') must be refunded'
        else 'A paid reveal has waited over 3 hours to be recorded: Stripe ' || i.key || ' is past the sweep''s per-run bound' end,
      'blast', 'customer_facing', 'affected', 1, 'demo', false,
      'evidence', jsonb_build_object('stripe', i.key, 'livemode', i.livemode, 'quote_id', i.quote_id, 'invoice_id', i.invoice_id,
        'payment_intent', i.payment_intent, 'amount_fils', i.amount_fils, 'currency', i.currency, 'paid_at', i.paid_at,
        'outcome', i.outcome, 'error', i.error, 'attempts', i.attempts, 'first_seen_at', i.first_seen_at,
        'transaction_id', i.transaction_id,
        'remedy', case i.outcome
          when 'failed' then 'the hourly sweep retries it; read the error (a quote that no longer exists, or a PaymentIntent Stripe would not return)'
          when 'second_payment' then 'a CEO-approved refund of the second payment; the first payment is the sale'
          when 'refunded_unrecorded' then 'the accountant decides: record the sale, or refund the remainder through the CEO'
          else 'more than 25 unrecorded payments an hour: read the failed items first' end))
    order by i.first_seen_at), '[]'::jsonb)
    into v_items
    from public.accountant_reveal_reconcile_item i
   where i.resolved_at is null and not i.demo
     and (i.outcome in ('failed', 'refunded_unrecorded', 'second_payment')
          or (i.outcome = 'deferred' and i.first_seen_at < now() - interval '3 hours'))
     -- #1835: recordRevealSale raises reveal:second_payment:<pi> itself; the same payment is not filed twice.
     and not (i.outcome = 'second_payment' and exists (select 1 from public.it_engineer_finding f
                where f.issue_key = 'reveal:second_payment:' || i.payment_intent and f.closed_at is null));

  -- The sweep's own health, from its last report.
  select r.* into v_last from public.accountant_reveal_reconcile_run r where r.reported_at is not null order by r.reported_at desc, r.id desc limit 1;
  select min(r.requested_at) into v_req from public.accountant_reveal_reconcile_run r
   where r.requested_at > coalesce(v_last.reported_at, '-infinity') and r.requested_at < now() - interval '2 hours';
  if v_req is not null and (v_last.id is null or v_last.reported_at < now() - interval '3 hours') then
    v_items := v_items || jsonb_build_array(jsonb_build_object('item', 'sweep_silent', 'owner_seat', 'accountant', 'subject', 'accountant_reveal_reconcile_run',
      'title', 'The reveal sweep has not reported since ' || coalesce(to_char(v_last.reported_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai', 'it was registered')
               || ': a paid reveal with no sale would go unseen',
      'blast', 'agent_facing', 'affected', 1,
      'evidence', jsonb_build_object('last_reported_at', v_last.reported_at, 'unanswered_since', v_req,
        'last_dispatches', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'requested_at', r.requested_at, 'http_status', r.http_status,
                              'http_error', left(r.http_error, 200)) order by r.id desc), '[]'::jsonb)
                              from (select * from public.accountant_reveal_reconcile_run order by id desc limit 3) r),
        'remedy', 'read the accountant function''s logs for action reveal_reconcile; cred_fn_accountant and project_ref must be in app_secrets')));
  end if;
  if v_last.id is not null then
    v_live := v_last.result->'modes'->'live';
    if v_last.result ? 'error' then
      v_items := v_items || jsonb_build_array(jsonb_build_object('item', 'sweep_error', 'owner_seat', 'accountant', 'subject', 'accountant_reveal_reconcile_run',
        'title', 'The reveal sweep stopped before it compared anything: ' || left(v_last.result->>'error', 200),
        'blast', 'agent_facing', 'affected', 1, 'evidence', jsonb_build_object('run', v_last.id, 'reported_at', v_last.reported_at, 'error', v_last.result->>'error')));
    elsif coalesce(v_live->>'basis', 'not_read') <> 'measured' then
      v_items := v_items || jsonb_build_array(jsonb_build_object('item', 'stripe_live_unread', 'owner_seat', 'accountant', 'subject', 'accountant_reveal_reconcile_run',
        'title', 'The reveal sweep could not read live Stripe (' || coalesce(v_live->>'basis', 'not_read') || '): live reveals are not being compared with the books',
        'blast', 'agent_facing', 'affected', 1, 'evidence', jsonb_build_object('run', v_last.id, 'reported_at', v_last.reported_at, 'live', v_live)));
    elsif coalesce((v_live->>'truncated')::boolean, false) then
      v_items := v_items || jsonb_build_array(jsonb_build_object('item', 'listing_truncated', 'owner_seat', 'accountant', 'subject', 'accountant_reveal_reconcile_run',
        'title', 'Live Stripe holds more paid payments in the reveal sweep''s window than it reads (5 pages of 100): shorten gl_settings.reveal_reconcile_window_days or raise the bound',
        'blast', 'agent_facing', 'affected', 1, 'evidence', jsonb_build_object('run', v_last.id, 'window_days', v_last.window_days, 'live', v_live)));
    end if;
  end if;
  return public.fn_accountant_duty_settle('reveal_reconcile', v_items);
end $fn$;
revoke execute on function public.fn_accountant_reveal_reconcile_findings() from public, anon, authenticated;

-- ── 4. What the runtime reports ───────────────────────────────────────────────────────────────────────────────────
-- p_r: {days, modes: {live|test: {basis, invoices, payment_intents, truncated, reason?}}, checked, too_recent,
--       outcomes: [{key, mode, livemode, source, quote_id, invoice_id, payment_intent, customer_id, customer_email,
--                   amount_fils, currency, paid_at (unix s), outcome, transaction_id, error}], error?}
create or replace function public.fn_accountant_reveal_reconcile_record(p_run_id bigint, p_r jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_run bigint; x jsonb; n_kept int := 0; n_refused int := 0; n_resolved int := 0; v_demo boolean; v_qid uuid;
  c_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  if jsonb_typeof(p_r) is distinct from 'object' or jsonb_typeof(coalesce(p_r->'outcomes', '[]'::jsonb)) is distinct from 'array' then
    raise exception 'fn_accountant_reveal_reconcile_record(run, readings): readings must be an object with an outcomes array';
  end if;
  select id into v_run from public.accountant_reveal_reconcile_run where id = p_run_id;
  if v_run is null then   -- a call the duty did not dispatch (the founder, by hand): it is a run of its own
    insert into public.accountant_reveal_reconcile_run (window_days)
    values (greatest(1, least(90, coalesce(nullif(p_r->>'days', '')::int, 30)))) returning id into v_run;
  end if;
  update public.accountant_reveal_reconcile_run
     set reported_at = now(),
         result = (p_r - 'outcomes') || jsonb_build_object('reported', jsonb_array_length(coalesce(p_r->'outcomes', '[]'::jsonb)))
   where id = v_run;

  for x in select e from jsonb_array_elements(coalesce(p_r->'outcomes', '[]'::jsonb)) e loop
    if coalesce(x->>'key', '') !~ '^(in|pi)_[A-Za-z0-9_]+$' or coalesce(btrim(x->>'quote_id'), '') = ''
       or coalesce(x->>'outcome', '') not in ('recovered', 'second_payment', 'refunded', 'refunded_unrecorded', 'failed', 'deferred')
       or coalesce(x->>'source', '') not in ('invoice', 'payment_intent') then
      n_refused := n_refused + 1;   -- 'recorded' (a plain match) never needs a row; anything malformed is refused, not guessed
      continue;
    end if;
    v_qid := case when x->>'quote_id' ~ c_uuid then (x->>'quote_id')::uuid end;
    -- DEMO: a test-mode payment, an email the one demo rule names, or a customer the database marks is_demo.
    v_demo := not coalesce((x->>'livemode')::boolean, false)
           or public.fn_is_demo_email(x->>'customer_email')
           or exists (select 1 from public.customers c where c.is_demo and c.id::text = x->>'customer_id')
           or exists (select 1 from public.quotes q join public.inquiries iq on iq.id = q.inquiry_id
                        join public.customers c on c.id = iq.customer_id where q.id = v_qid and c.is_demo);
    insert into public.accountant_reveal_reconcile_item as it (key, livemode, source, quote_id, invoice_id, payment_intent,
        customer_id, customer_email, amount_fils, currency, paid_at, demo, outcome, transaction_id, error, last_run_id, resolved_at)
    values (x->>'key', coalesce((x->>'livemode')::boolean, false), x->>'source', x->>'quote_id', nullif(x->>'invoice_id', ''),
        nullif(x->>'payment_intent', ''), nullif(x->>'customer_id', ''), lower(nullif(x->>'customer_email', '')),
        nullif(x->>'amount_fils', '')::bigint, nullif(x->>'currency', ''),
        case when x->>'paid_at' ~ '^[0-9]+$' then to_timestamp((x->>'paid_at')::bigint) end,
        v_demo, x->>'outcome', case when x->>'transaction_id' ~ c_uuid then (x->>'transaction_id')::uuid end,
        left(nullif(x->>'error', ''), 1000), v_run,
        case when x->>'outcome' in ('recovered', 'refunded') then now() end)
    on conflict (key) do update set
        outcome = excluded.outcome, error = excluded.error, demo = excluded.demo,
        payment_intent = coalesce(excluded.payment_intent, it.payment_intent),
        customer_email = coalesce(excluded.customer_email, it.customer_email),
        transaction_id = coalesce(excluded.transaction_id, it.transaction_id),
        attempts = it.attempts + 1, last_seen_at = now(), last_run_id = excluded.last_run_id,
        resolved_at = case when excluded.outcome in ('recovered', 'refunded') then coalesce(it.resolved_at, now()) end;
    n_kept := n_kept + 1;
  end loop;

  -- A payment the books now hold by another path (the webhook, a by-hand recording) is resolved, whatever this run saw.
  update public.accountant_reveal_reconcile_item i
     set outcome = 'recorded_elsewhere', resolved_at = now(), transaction_id = t.id
    from public.transactions t
   where i.resolved_at is null and i.outcome in ('failed', 'refunded_unrecorded', 'deferred')
     and ((i.invoice_id is not null and t.stripe_invoice_id = i.invoice_id) or (i.payment_intent is not null and t.payment_ref = i.payment_intent));
  get diagnostics n_resolved = row_count;

  return jsonb_build_object('run', v_run, 'kept', n_kept, 'refused', n_refused, 'resolved_elsewhere', n_resolved,
    'findings', public.fn_accountant_reveal_reconcile_findings());
end $fn$;
revoke execute on function public.fn_accountant_reveal_reconcile_record(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_accountant_reveal_reconcile_record(bigint, jsonb) to service_role;

-- ── 6. The duty ───────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_reveal_reconcile_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'extensions', 'pg_temp' as $fn$
declare v_days int; v_ref text; v_key text; v_cred text; v_run bigint; v_req bigint; v_harvested int := 0; v_pruned int := 0;
begin
  -- The last dispatches' HTTP answers (pg_net keeps responses 6 hours; this runs every hour).
  update public.accountant_reveal_reconcile_run r
     set http_status = coalesce(h.status_code, 0),
         http_error = case when h.status_code = 200 then null else left(coalesce(h.error_msg, h.content::text, 'no answer'), 500) end
    from net._http_response h
   where h.id = r.request_id and r.http_status is null;
  get diagnostics v_harvested = row_count;
  delete from public.accountant_reveal_reconcile_run where requested_at < now() - interval '60 days';
  get diagnostics v_pruned = row_count;

  -- One sweep at a time: none is sent while the last is unanswered and under 30 minutes old.
  if exists (select 1 from public.accountant_reveal_reconcile_run
              where reported_at is null and http_status is null and requested_at > now() - interval '30 minutes') then
    return jsonb_build_object('dispatched', false, 'why', 'a sweep is in flight', 'harvested', v_harvested,
                              'findings', public.fn_accountant_reveal_reconcile_findings());
  end if;

  v_days := greatest(1, least(90, coalesce((select num_value::int from public.gl_settings where key = 'reveal_reconcile_window_days'), 30)));
  select value into v_ref from public.app_secrets where key = 'project_ref';
  v_key := public.fn_gateway_client_key();
  select value into v_cred from public.app_secrets where key = 'cred_fn_accountant';
  if coalesce(v_ref, '') = '' or coalesce(v_key, '') = '' or coalesce(v_cred, '') = '' then
    -- A duty that cannot send has failed: the seat shows red (fn_seat_duty_health), it does not report green.
    raise exception 'fn_accountant_reveal_reconcile_tick: project_ref, the gateway key or cred_fn_accountant is missing from app_secrets';
  end if;
  insert into public.accountant_reveal_reconcile_run (window_days) values (v_days) returning id into v_run;
  v_req := net.http_post(url := 'https://' || v_ref || '.supabase.co/functions/v1/accountant',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key, 'apikey', v_key),
    body := jsonb_build_object('__secret', v_cred, 'action', 'reveal_reconcile', 'run_id', v_run, 'days', v_days),
    timeout_milliseconds := 140000);
  update public.accountant_reveal_reconcile_run set request_id = v_req where id = v_run;
  return jsonb_build_object('dispatched', true, 'run', v_run, 'request', v_req, 'window_days', v_days, 'harvested', v_harvested,
                            'pruned', v_pruned, 'findings', public.fn_accountant_reveal_reconcile_findings());
end $fn$;
revoke execute on function public.fn_accountant_reveal_reconcile_tick() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('accountant.reveal_reconcile', 'accountant', interval '1 hour', 'fn_accountant_reveal_reconcile_tick',
   'Every hour: Stripe''s paid reveals of the last 30 days are compared with transactions; each one with no sale is recorded through recordRevealSale, and each one that cannot be is a finding (demo payments file none).',
   'scripts/sql/a_paid_reveal_with_no_sale_is_found_and_recorded_within_the_hour.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- verdict
select case when
       (select count(*) from public.seat_duty where duty = 'accountant.reveal_reconcile' and owner_seat = 'accountant' and enabled
          and every = interval '1 hour' and routine = 'fn_accountant_reveal_reconcile_tick') = 1
   and (select count(*) from public.table_export_registry where table_name in ('accountant_reveal_reconcile_item', 'accountant_reveal_reconcile_run')) = 2
   and (select bool_and(relrowsecurity) from pg_class where oid in ('public.accountant_reveal_reconcile_item'::regclass, 'public.accountant_reveal_reconcile_run'::regclass))
   and not has_table_privilege('anon', 'public.accountant_reveal_reconcile_item', 'select')
   and not has_table_privilege('authenticated', 'public.accountant_reveal_reconcile_item', 'select')
   and not has_table_privilege('anon', 'public.accountant_reveal_reconcile_run', 'select')
   and not has_table_privilege('authenticated', 'public.accountant_reveal_reconcile_run', 'select')
   and not has_function_privilege('anon', 'public.fn_accountant_reveal_reconcile_tick()', 'execute')
   and not has_function_privilege('authenticated', 'public.fn_accountant_reveal_reconcile_tick()', 'execute')
   and not has_function_privilege('anon', 'public.fn_accountant_reveal_reconcile_record(bigint, jsonb)', 'execute')
   and not has_function_privilege('authenticated', 'public.fn_accountant_reveal_reconcile_record(bigint, jsonb)', 'execute')
   and has_function_privilege('service_role', 'public.fn_accountant_reveal_reconcile_record(bigint, jsonb)', 'execute')
   and not has_function_privilege('anon', 'public.fn_accountant_reveal_reconcile_findings()', 'execute')
   and not has_function_privilege('authenticated', 'public.fn_accountant_reveal_reconcile_findings()', 'execute')
   and (select count(*) from pg_proc where oid in ('public.fn_accountant_reveal_reconcile_tick()'::regprocedure,
          'public.fn_accountant_reveal_reconcile_record(bigint, jsonb)'::regprocedure, 'public.fn_accountant_reveal_reconcile_findings()'::regprocedure)
          and prosecdef and array_to_string(proconfig, ',') like '%search_path=public%pg_temp%') = 3
  then 'PROBE OK' else 'PROBE FAILED: the duty, the export registry rows, RLS, the grants or a pinned search_path' end as verdict;
