-- PROBE (accountant, 23 Sep 2026): fn_accountant_books_duty names the RIGHT cause for a stale ledger.
-- Pure probe, no DDL: it always raises CHK<<...>>, so every row it writes is rolled back.
--   node scripts/qsql.mjs scripts/sql/the_books_say_why_they_are_stale_probe.sql   -> expects CHK<<PROBE OK ...>>
do $$
declare r1 jsonb; r2 jsonb; r3 jsonb; t1 text; t2 text; t3 text; v_e bigint; n_open_before int;
begin
  n_open_before := (select count(*) from public.it_engineer_finding where issue_key = 'acct:books:books_stale' and closed_at is null);
  -- 1. As of a day inside the window: not stale, so no finding (and an open one closes).
  r1 := public.fn_accountant_books_duty((select max(entry_date) from public.gl_journal where status = 'posted') + 1);
  -- 2. Far ahead, nothing arrived and nothing unposted: the cause is "nothing forwarded".
  r2 := public.fn_accountant_books_duty(current_date + 30);
  t2 := (select title from public.it_engineer_finding where issue_key = 'acct:books:books_stale' and closed_at is null);
  -- 3. A booked expense with no journal: the cause is posting. (Journal posting is by fn_gl_sync_business,
  --    never by insert, so the row stays unposted inside this transaction.)
  insert into public.expense_entries (vendor, category, amount, currency, charged_on, note, source)
  values ('Probe Vendor', 'Subscription', 1, 'AED', current_date, 'books stale probe', 'receipt') returning id into v_e;
  r3 := public.fn_accountant_books_duty(current_date + 30);
  t3 := (select title from public.it_engineer_finding where issue_key = 'acct:books:books_stale' and closed_at is null);
  if (r1->'findings'->>'failing')::int <> 0 then raise exception 'CHK<<PROBE FAILED: a fresh ledger raised a finding %>>', r1; end if;
  if t2 !~ 'nothing has reached the expenses mailbox' then raise exception 'CHK<<PROBE FAILED: idle cause not named: %>>', t2; end if;
  if t3 !~ 'posting is failing' or (r3->>'entries_not_posted')::int < 1 then raise exception 'CHK<<PROBE FAILED: posting cause not named: % %>>', t3, r3; end if;
  raise exception 'CHK<<PROBE OK fresh=% idle="%" posting="%" open_before=%>>', r1->'findings'->>'failing', t2, t3, n_open_before;
end $$;
