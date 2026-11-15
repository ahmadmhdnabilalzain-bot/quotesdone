-- PROBE: A QUOTATION'S EXPIRY IS THE VALIDITY THE SUPPLIER STATES, READ FROM HIS OWN WORDS, AND NOTHING FILLS A PERIOD HE DID NOT.
-- Seat: sales_engineer. 15 Nov 2026 (ledger 1697). Pure probe: no DDL, never applied. Run in the same rolled-back transaction as
-- a_quotation_is_valid_for_the_period_the_supplier_states_and_for_no_period_we_choose.sql (or after it is applied); it must
-- print PROBE OK. It always raises, so every row it writes is rolled back. Every party is a ZZ DEMO fixture on @example.invalid,
-- and no real row is read or written: the fixtures are found only by the ids this probe generated.
-- PROBE OK only if
--   R. every wording below (English, Arabic, digits and words, periods, dates, ranges, working days, a period from a named date,
--      a last day beside a period) gives exactly the last valid day written beside it, counted from the quotation's date when
--      one is given and else from the day received; and every wording that states no readable validity gives NULL;
--   I. a quote inserted with no validity has NO expiry; with "valid 15 days" and a quotation date, the end of that day + 15 in
--      Dubai; a writer that sets expires_at itself keeps it;
--   U. a validity stated later (an update) sets the expiry; a quotation date added later moves it; a validity cleared clears
--      it; an update that sets expires_at itself keeps it; an update that touches neither leaves it;
--   P. the reveal period: a live quotation with no stated validity is counted live and leaves the period at the request's cap;
--      a quotation whose stated validity ended is not live; with only dated quotations the period is their latest end;
--      the "still live" test in fn_sales_engineer_tells_unchosen_suppliers carries no period of its own;
--   S. no routine of this file fills an expiry with a period of its own (the source of every one is read).
do $probe$
declare
  fails text := ''; r record; got date; v_rcv constant timestamptz := '2026-11-15 10:00:00+04'; c uuid := gen_random_uuid();
  s1 bigint; s2 bigint; i1 uuid := gen_random_uuid(); i2 uuid := gen_random_uuid();
  q1 uuid := gen_random_uuid(); q2 uuid := gen_random_uuid(); q3 uuid := gen_random_uuid(); q4 uuid := gen_random_uuid();
  q5 uuid := gen_random_uuid(); q6 uuid := gen_random_uuid(); e timestamptz; v_cap timestamptz := now() + interval '30 days';
  n int; src text;
begin
  -- ── R. the readings (received 15 Nov 2026 10:00 Dubai, a Sunday) ──────────────────────────────────────────────────────────
  for r in select * from (values
      ('valid 15 days', null::date, '2026-11-30'::date), ('Validity: 30 days from date', '2026-11-01', '2026-12-01'),
      ('valid until 30 Nov 2026', null, '2026-11-30'), ('valid till 15/12/2026', null, '2026-12-15'),
      ('VALID UNTIL 30-11-2026', null, '2026-11-30'), ('valid up to 30th November, 2026', null, '2026-11-30'),
      ('Nov 30, 2026', null, '2026-11-30'), ('2026-12-15', null, '2026-12-15'), ('valid till 31.12.26', null, '2026-12-31'),
      ('30 Nov', null, '2026-11-30'), ('until 10 Jan', null, '2027-01-10'), ('valid until 15th of December', null, '2026-12-15'),
      ('end of November 2026', null, '2026-11-30'), ('end of month', null, '2026-11-30'), ('expiry date: 20/12/2026', null, '2026-12-20'),
      ('expires on 5 Dec 2026', null, '2026-12-05'), ('valid from 1 Nov until 30 Nov 2026', null, '2026-11-30'),
      ('valid 30 days (until 20 Dec 2026)', null, '2026-12-20'), ('30 days from 1 Nov 2026', null, '2026-12-01'),
      ('thirty (30) days', null, '2026-12-15'), ('Two (2) weeks', null, '2026-11-29'), ('2 weeks', null, '2026-11-29'),
      ('one month', null, '2026-12-15'), ('3 months', '2026-11-30', '2027-02-28'), ('1.5 months', null, '2026-12-30'),
      ('valid for 1 year', null, '2027-11-15'), ('valid for one year from the date of quotation', null, '2027-11-15'),
      ('10 working days', null, '2026-11-27'), ('7 business days', null, '2026-11-24'), ('valid 30 calendar days', null, '2026-12-15'),
      ('15-30 days', null, '2026-11-30'), ('Validity : 30 days', null, '2026-12-15'), ('price validity 30days', null, '2026-12-15'),
      ('7d', null, '2026-11-22'), ('valid for a week', null, '2026-11-22'), ('forty five days', null, '2026-12-30'),
      ('valid 7 days only, prices subject to change', null, '2026-11-22'),
      ('صالح لمدة 15 يوما', null, '2026-11-30'), ('صلاحية العرض: ثلاثين يوماً من تاريخه', null, '2026-12-15'),
      ('سارٍ حتى 30 نوفمبر 2026', null, '2026-11-30'), ('أسبوعين', null, '2026-11-29'), ('شهر واحد', null, '2026-12-15'),
      ('٣٠ يوم', null, '2026-12-15'), ('نهاية الشهر', null, '2026-11-30'), ('صالح حتى نهاية شهر ديسمبر 2026', null, '2026-12-31'),
      ('صالح لغاية 2026/11/30', null, '2026-11-30'), ('يسري العرض لمدة شهرين', null, '2027-01-15'),
      ('العرض ساري لمدة 7 أيام', null, '2026-11-22'), ('صالح 10 أيام عمل', null, '2026-11-27'), ('لمدة سنة', null, '2027-11-15'),
      ('خمسة عشر يوما', null, '2026-11-30'),
      -- states no validity we can read: no expiry
      ('', null, null), ('   ', null, null), ('subject to stock', null, null), ('TBA', null, null), ('Rates are firm', null, null),
      ('Offer valid until further notice', null, null), ('as per stock availability', null, null), ('0 days', null, null),
      ('from 1 Nov 2026', null, null), ('31/02/2026', null, null), ('12/15/2026', null, null), ('valid 2026 days', null, null)
    ) t(w, qd, want) loop
    got := (public.fn_quote_validity_until(r.w, r.qd, v_rcv) at time zone 'Asia/Dubai')::date - 1;
    if got is distinct from r.want then fails := fails || format(' R:%s=>%s(want %s)', r.w, coalesce(got::text, 'null'), coalesce(r.want::text, 'null')); end if;
  end loop;
  if public.fn_quote_validity_until(null, null, v_rcv) is not null then fails := fails || ' R:null_text'; end if;
  -- the end is the close of the last day in Dubai, not a moment inside it
  if public.fn_quote_validity_until('valid 15 days', null, v_rcv) <> '2026-12-01 00:00:00+04'::timestamptz then fails := fails || ' R:end_of_day'; end if;

  -- ── fixtures ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
  perform set_config('qd.duty_fixtures', 'on', true);
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, signed_terms_url, locale, created_at)
  values (c, 'ZZ DEMO Validity Customer', 'zz-demo-validity@example.invalid', '+971500000197', true, true, 'demo://terms', 'en', now() - interval '20 days');
  insert into public.leads (company_name, email) values ('ZZ DEMO Validity Supplier One', 'zz-demo-validity-s1@example.invalid') returning id into s1;
  insert into public.leads (company_name, email) values ('ZZ DEMO Validity Supplier Two', 'zz-demo-validity-s2@example.invalid') returning id into s2;
  insert into public.inquiries (id, customer_id, category, emirate, summary, status, lang, created_at, scope_type)
  select x, c, 'plumbing', 'Dubai', 'ZZ DEMO validity probe', 'quoted', 'en', now() - interval '10 days', 'single' from unnest(array[i1, i2]) x;

  -- ── I. insert ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at, validity)
  values (q1, i1, s1, 1000, 'draft', now(), null);
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at, validity, quotation_date)
  values (q2, i1, s2, 1100, 'draft', now(), 'valid 15 days', current_date - 3);
  insert into public.quotes (id, inquiry_id, supplier_id, option_no, quote_amount, status, created_at, validity, expires_at)
  values (q3, i1, s1, 2, 1200, 'draft', now(), 'valid 15 days', '2030-01-01 00:00+04');
  select expires_at into e from public.quotes where id = q1;
  if e is not null then fails := fails || ' I:no_validity_has_expiry(' || e || ')'; end if;
  select expires_at into e from public.quotes where id = q2;
  if e is distinct from ((current_date - 3 + 16)::timestamp at time zone 'Asia/Dubai') then fails := fails || ' I:dated(' || coalesce(e::text, 'null') || ')'; end if;
  select expires_at into e from public.quotes where id = q3;
  if e is distinct from '2030-01-01 00:00+04'::timestamptz then fails := fails || ' I:writer_expiry_kept'; end if;

  -- ── U. update ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
  update public.quotes set validity = '30 days' where id = q1;            -- stated later (the hold desk, a resubmission)
  select expires_at into e from public.quotes where id = q1;
  if e is distinct from public.fn_quote_validity_until('30 days', null, (select created_at from public.quotes where id = q1)) or e is null then
    fails := fails || ' U:stated_later(' || coalesce(e::text, 'null') || ')'; end if;
  update public.quotes set quotation_date = current_date - 10 where id = q1;
  select expires_at into e from public.quotes where id = q1;
  if e is distinct from ((current_date - 10 + 31)::timestamp at time zone 'Asia/Dubai') then fails := fails || ' U:date_moves(' || coalesce(e::text, 'null') || ')'; end if;
  update public.quotes set notes = 'ZZ DEMO a note' where id = q1;           -- touches neither: unchanged
  if (select expires_at from public.quotes where id = q1) is distinct from e then fails := fails || ' U:unrelated_update_moved'; end if;
  update public.quotes set validity = null where id = q1;                   -- cleared: no expiry
  if (select expires_at from public.quotes where id = q1) is not null then fails := fails || ' U:cleared_kept_expiry'; end if;
  update public.quotes set validity = 'valid 5 days', expires_at = '2031-01-01 00:00+04' where id = q3;   -- the writer's own
  if (select expires_at from public.quotes where id = q3) is distinct from '2031-01-01 00:00+04'::timestamptz then fails := fails || ' U:writer_expiry_kept'; end if;

  -- ── P. the reveal period ──────────────────────────────────────────────────────────────────────────────────────────────────
  -- i1: q1 (no validity) and q2 (dated) submitted and released; q3 withdrawn
  update public.quotes set status = 'withdrawn' where id = q3;
  update public.quotes set status = 'submitted' where id in (q1, q2);
  update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id in (q1, q2) and released_at is null;
  update public.quotes set status = 'submitted' where id in (q1, q2) and status <> 'submitted';
  if public.fn_sales_engineer_live_quotes_left(i1) <> 2 then fails := fails || ' P:live(' || public.fn_sales_engineer_live_quotes_left(i1) || ' of 2)'; end if;
  if public.fn_sales_engineer_reveal_period_until(i1, v_cap) is distinct from v_cap then
    fails := fails || ' P:undated_keeps_cap(' || coalesce(public.fn_sales_engineer_reveal_period_until(i1, v_cap)::text, 'null') || ')'; end if;
  -- i2: one dated quotation still valid, one whose stated validity ended yesterday
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, created_at, validity, quotation_date)
  values (q4, i2, s1, 900, 'draft', now(), 'valid 5 days', current_date),
         (q5, i2, s2, 950, 'draft', now(), 'valid until ' || to_char(current_date - 1, 'DD Mon YYYY'), null);
  update public.quotes set status = 'submitted' where id in (q4, q5);
  update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id in (q4, q5) and released_at is null;
  update public.quotes set status = 'submitted' where id in (q4, q5) and status <> 'submitted';
  if public.fn_sales_engineer_live_quotes_left(i2) <> 1 then fails := fails || ' P:ended_counted(' || public.fn_sales_engineer_live_quotes_left(i2) || ')'; end if;
  if public.fn_sales_engineer_reveal_period_until(i2, v_cap) is distinct from ((current_date + 6)::timestamp at time zone 'Asia/Dubai') then
    fails := fails || ' P:dated_period(' || coalesce(public.fn_sales_engineer_reveal_period_until(i2, v_cap)::text, 'null') || ')'; end if;
  -- an undated quotation joins: the period is the cap again
  insert into public.quotes (id, inquiry_id, supplier_id, option_no, quote_amount, status, created_at) values (q6, i2, s1, 2, 990, 'draft', now());
  update public.quotes set status = 'submitted' where id = q6;
  update public.quote_quality_hold set released_at = now(), release_reason = 'waited_24h' where quote_id = q6 and released_at is null;
  update public.quotes set status = 'submitted' where id = q6 and status <> 'submitted';
  if public.fn_sales_engineer_reveal_period_until(i2, v_cap) is distinct from v_cap then fails := fails || ' P:undated_joins'; end if;

  -- ── S. no routine of the file carries a period of its own ─────────────────────────────────────────────────────────────────
  for r in select p.proname, pg_get_functiondef(p.oid) d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
            where ns.nspname = 'public' and p.proname in ('trg_quote_expiry', 'fn_quote_validity_until', 'fn_quote_validity_date',
              'fn_sales_engineer_reveal_period_until', 'fn_sales_engineer_live_quotes_left', 'fn_sales_engineer_tells_unchosen_suppliers') loop
    if r.d ~ 'created_at \+ interval|days int := \d|days => days|interval ''14 days''' then fails := fails || ' S:' || r.proname; end if;
  end loop;
  select count(*) into n from pg_trigger t where t.tgrelid = 'public.quotes'::regclass and t.tgname = 'trg_quote_expiry_b'
     and pg_get_triggerdef(t.oid) ~ 'BEFORE INSERT OR UPDATE OF validity, quotation_date';
  if n <> 1 then fails := fails || ' S:trigger_not_on_update'; end if;
  select count(*) into n from information_schema.routine_privileges where routine_schema = 'public'
     and routine_name in ('trg_quote_expiry', 'fn_quote_validity_until', 'fn_quote_validity_date', 'fn_quote_validity_month')
     and grantee in ('PUBLIC', 'anon', 'authenticated');
  if n <> 0 then fails := fails || ' S:executable_by_' || n || '_public_grants'; end if;

  raise exception 'CHK<<%>>', case when fails = '' then 'PROBE OK' else 'PROBE FAILED:' || fails end;
end $probe$;
