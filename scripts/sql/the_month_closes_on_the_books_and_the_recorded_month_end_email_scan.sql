-- THE MONTH CLOSES ON THE BOOKS AND THE RECORDED MONTH-END EMAIL SCAN, NEVER ON A BANK STATEMENT.
-- Seat: accountant (the close, the close pack and the receipts are the accountant's). 10 Nov 2026.
-- Founder rulings: 1559 (10 Nov 2026, standing) "No bank statement reconciliation. Near each month end the founder will tell
-- the session to scan his email and check the receipts there."; 1574 "the accountant keeps every finance record (invoices
-- out, expenses from the month-end email scan)". Runs after the_founders_rulings_of_10_november_settle_four_open_problems.sql,
-- which records the decision no_bank_statement_reconciliation and retires accountant.receipt_bank_match; this file takes the
-- statement out of the close itself.
--
-- MEASURED BEFORE WRITING (production htdblwldjkcgjvmqkbeh, read-only, 10 Nov 2026):
--   * accountant_month_close has no row for 2026-10. fn_accountant_month_close_status('2026-10-01') answers
--     'waiting_for_statement' ("no readable Mashreq statement for 2026-10 has been received"), so
--     fn_accountant_month_close_tick never closes October and fn_accountant_founder_close_pack_tick never builds its pack:
--     the status has blocked the close since the 3rd. fn_accountant_close_by_day_5 files "the close is waiting for the
--     Mashreq statement" instead of closing.
--   * The close pack's first section is "Bank against the Mashreq statement" (statement closing balance, unbooked
--     statement lines, unexplained difference), and an unbooked statement line is one of its unusual-item rules.
--   * Nothing records the month-end email scan: when the founder asks, a session scans the mailboxes and books receipts
--     (expense_entries), and the books cannot see that the scan happened, what it found, or what it could not book.
--
-- WHAT THIS CHANGES:
--   1. public.accountant_month_scan: the founder-triggered month-end email scan, one row per month: when he asked, when
--      it ran, which mailboxes, receipts found / booked / not booked (each with its reason). Written only through
--      fn_accountant_month_scan_record, which refuses a "booked" count the books do not hold (no figure without a
--      source row: expense_entries created in the scan's window for the month).
--   2. fn_accountant_month_close_status: 'waiting_for_statement' is gone. A month is due on day 3 (gl_settings
--      month_close_day) and closes by day 5 on the books alone; when a scan was recorded for it, by two days after the
--      scan if that is later. The status carries the scan (or "not asked") instead of the statement.
--   3. fn_accountant_month_close_tick and fn_accountant_close_by_day_5 lose their statement branch; a missed day 5 is
--      reported as late, as before.
--   4. fn_accountant_month_close: the close's severity and its line to the CEO no longer count payouts against the bank;
--      the figures carry the book cash (GL 1000, "book balance, not confirmed by a statement") and the month's scan.
--   5. The founder's close pack goes out on the receipts: fn_accountant_founder_close_pack_figures replaces the bank
--      section with the book cash and a receipts section (the scan, and the month's expenses with no receipt document,
--      v_expense_receipt_gap), and drops the unbooked-statement-line rule; fn_accountant_founder_close_pack_document
--      prints them; fn_accountant_founder_close_pack_tick no longer waits for a statement.
--   CREATE OR REPLACE keeps every rewritten routine's ACL; the new routine is revoked; the new table has RLS, a
--   service-role-only policy and its export registry row. Each rewritten body is the live body (pg_get_functiondef,
--   10 Nov 2026) with only the statement parts changed.
--
-- Prevented by: scripts/checks/the_month_closes_on_the_books_and_the_recorded_month_end_email_scan.test.mjs (no close
-- routine reads a bank statement as a gate; rolled-back replay: October closes, its pack builds, a scan is recorded and
-- a booked count the books do not hold is refused).
--   node scripts/apply_sql.mjs scripts/sql/the_month_closes_on_the_books_and_the_recorded_month_end_email_scan.sql --apply --ddl --seat accountant

create table if not exists public.accountant_month_scan (
  month date primary key check (month = date_trunc('month', month)::date),
  requested_by text not null default 'founder' check (requested_by = 'founder'),
  requested_at timestamptz not null,
  scanned_at timestamptz not null,
  mailboxes text[] not null check (cardinality(mailboxes) > 0),
  receipts_found integer not null check (receipts_found >= 0),
  receipts_booked integer not null check (receipts_booked >= 0 and receipts_booked <= receipts_found),
  receipts_unbooked jsonb not null default '[]'::jsonb check (jsonb_typeof(receipts_unbooked) = 'array'),
  booked_measured integer not null,
  recorded_by text not null references public.org_role(role_id),
  note text,
  recorded_at timestamptz not null default now(),
  check (scanned_at >= requested_at),
  check (jsonb_array_length(receipts_unbooked) = receipts_found - receipts_booked)
);
alter table public.accountant_month_scan enable row level security;
drop policy if exists accountant_month_scan_service_role_only on public.accountant_month_scan;
create policy accountant_month_scan_service_role_only on public.accountant_month_scan
  as permissive for all to public using (false) with check (false);
revoke all on public.accountant_month_scan from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('accountant_month_scan', true, 'payment',
   'the founder-triggered month-end email scan per month: mailboxes, receipts found, booked and not booked (ruling 1559)', 'accountant')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason;

-- ── 1. THE SCAN IS RECORDED (the session calls this when the founder says "scan") ──────────────────────────────
create or replace function public.fn_accountant_month_scan_record(p_month date, p_requested_at timestamptz, p_mailboxes text[],
  p_receipts_found integer, p_receipts_booked integer, p_receipts_unbooked jsonb default '[]'::jsonb, p_note text default null,
  p_scanned_at timestamptz default now(), p_recorded_by text default 'accountant')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_m date := date_trunc('month', p_month)::date; v_measured int; v_bad text;
begin
  if p_month is null or p_requested_at is null then raise exception 'a scan names its month and when the founder asked for it'; end if;
  if v_m > date_trunc('month', now() at time zone 'Asia/Dubai')::date then raise exception 'month % has not begun', to_char(v_m, 'YYYY-MM'); end if;
  if jsonb_typeof(coalesce(p_receipts_unbooked, '[]'::jsonb)) <> 'array' then raise exception 'the receipts not booked are an array'; end if;
  select string_agg(coalesce(x->>'what', '?'), ', ') into v_bad from jsonb_array_elements(coalesce(p_receipts_unbooked, '[]'::jsonb)) x
   where coalesce(btrim(x->>'what'), '') = '' or length(btrim(coalesce(x->>'why', ''))) < 10;
  if v_bad is not null then raise exception 'every receipt not booked names what it is and why (>= 10 characters): %', v_bad; end if;
  -- NO FIGURE WITHOUT A SOURCE ROW: what the scan says it booked must be in the books, dated in the month,
  -- entered between the founder's ask and a day after the scan
  select count(*) into v_measured from public.expense_entries e
   where e.charged_on >= v_m and e.charged_on < (v_m + interval '1 month')::date
     and e.created_at >= p_requested_at and e.created_at < coalesce(p_scanned_at, now()) + interval '1 day';
  if p_receipts_booked > v_measured then
    raise exception 'the scan says % receipt(s) were booked for %, and the books hold % entered in its window: no figure without a source row',
      p_receipts_booked, to_char(v_m, 'YYYY-MM'), v_measured;
  end if;
  insert into public.accountant_month_scan (month, requested_at, scanned_at, mailboxes, receipts_found, receipts_booked,
                                            receipts_unbooked, booked_measured, recorded_by, note)
  values (v_m, p_requested_at, coalesce(p_scanned_at, now()), p_mailboxes, p_receipts_found, p_receipts_booked,
          coalesce(p_receipts_unbooked, '[]'::jsonb), v_measured, p_recorded_by, p_note)
  on conflict (month) do update set requested_at = excluded.requested_at, scanned_at = excluded.scanned_at, mailboxes = excluded.mailboxes,
    receipts_found = excluded.receipts_found, receipts_booked = excluded.receipts_booked, receipts_unbooked = excluded.receipts_unbooked,
    booked_measured = excluded.booked_measured, recorded_by = excluded.recorded_by, note = excluded.note, recorded_at = now();
  return jsonb_build_object('ok', true, 'month', to_char(v_m, 'YYYY-MM'), 'booked', p_receipts_booked, 'booked_measured', v_measured,
                            'not_booked', jsonb_array_length(coalesce(p_receipts_unbooked, '[]'::jsonb)));
end $fn$;
revoke execute on function public.fn_accountant_month_scan_record(date, timestamptz, text[], integer, integer, jsonb, text, timestamptz, text) from public, anon, authenticated;

-- ── 2. THE CLOSE IS DUE ON THE BOOKS ──────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_month_close_status(p_month date, p_today date default null::date)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_m date := date_trunc('month', p_month)::date;
  v_today date := coalesce(p_today, (now() at time zone 'Asia/Dubai')::date);
  v_day int := coalesce((select num_value::int from public.gl_settings where key = 'month_close_day'), 3);
  s public.accountant_month_scan; v_due_by date; v_closed timestamptz; v_status text;
begin
  -- 10 Nov 2026 (ruling 1559): no bank statement gates the close. Due by the 5th on the books alone, or two days after
  -- the founder's month-end email scan when it was recorded later than that.
  select * into s from public.accountant_month_scan where month = v_m;
  v_due_by := greatest((v_m + interval '1 month' + interval '4 days')::date,
                       coalesce(((s.scanned_at at time zone 'Asia/Dubai')::date + 2), (v_m + interval '1 month' + interval '4 days')::date));
  select closed_at into v_closed from public.accountant_month_close where month = v_m;
  v_status := case when v_closed is not null then 'closed'
                   when v_today < (v_m + interval '1 month')::date + (v_day - 1) then 'not_due'
                   else 'due' end;
  return jsonb_build_object('month', to_char(v_m, 'YYYY-MM'), 'status', v_status, 'due_by', v_due_by,
    'closed_at', v_closed,
    'scan', case when s.month is null then jsonb_build_object('asked', false, 'note', 'no month-end email scan was recorded: the month closes on the books alone')
                 else jsonb_build_object('asked', true, 'requested_at', s.requested_at, 'scanned_at', s.scanned_at, 'mailboxes', to_jsonb(s.mailboxes),
                        'receipts_found', s.receipts_found, 'receipts_booked', s.receipts_booked,
                        'receipts_not_booked', jsonb_array_length(s.receipts_unbooked)) end,
    'statement', 'not required: founder ruling 1559, no bank statement reconciliation',
    'late', case when v_status = 'closed' then (v_closed at time zone 'Asia/Dubai')::date > v_due_by
                 when v_status = 'due' then v_today > v_due_by
                 else false end);
end $fn$;

create or replace function public.fn_accountant_month_close_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_prev date := (date_trunc('month', (now() at time zone 'Asia/Dubai')::date) - interval '1 month')::date; v_s jsonb;
begin
  v_s := public.fn_accountant_month_close_status(v_prev);
  if v_s->>'status' <> 'due' then
    return jsonb_build_object('closed', false, 'month', v_s->>'month', 'status', v_s->>'status', 'scan', v_s->'scan',
      'pending_render', (select count(*) from public.accountant_month_close where rendered_at is null));
  end if;
  return public.fn_accountant_month_close(v_prev) || jsonb_build_object('closed', true, 'status', 'closed');
end $fn$;

create or replace function public.fn_accountant_close_by_day_5()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_local date := (now() at time zone 'Asia/Dubai')::date; v_prev date; v_tick jsonb; v_s jsonb; v_rep jsonb;
begin
  v_prev := (date_trunc('month', v_local) - interval '1 month')::date;
  v_tick := public.fn_accountant_month_close_tick();       -- the close itself runs here too, not only inside the runtime
  v_s := public.fn_accountant_month_close_status(v_prev, v_local);
  -- 10 Nov 2026 (ruling 1559): there is no "waiting for the statement" any more; a close past its day is late.
  if (v_s->>'late')::boolean then
    v_rep := public.fn_support_report_to_ceo(
      p_idempotency_key => 'accountant_close_day5:' || to_char(v_prev, 'YYYY-MM'), p_severity => 'elevated',
      p_subject => 'The ' || to_char(v_prev, 'Mon YYYY') || ' close ' || case when v_s->>'status' = 'closed' then 'was late' else 'is not done' end
                   || ' (due by ' || (v_s->>'due_by') || ')',
      p_evidence => jsonb_build_object('month', to_char(v_prev, 'YYYY-MM'), 'status', v_s, 'tick', v_tick),
      p_attempted => '[]'::jsonb, p_requested => 'None: the accountant closes it on this tick; this records the missed target.',
      p_review_in => interval '30 days', p_source_agent => 'accountant');
  end if;
  return jsonb_build_object('month', to_char(v_prev, 'YYYY-MM'), 'status', v_s->>'status', 'due_by', v_s->'due_by',
    'closed_at', v_s->'closed_at', 'closed_by_day_5', v_s->>'status' = 'closed' and not (v_s->>'late')::boolean,
    'late', (v_s->>'late')::boolean, 'tick', v_tick);
end $fn$;

-- ── 4. THE CLOSE ITSELF ───────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_month_close(p_month date)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_m date := date_trunc('month', p_month)::date; f jsonb; v_rep jsonb; v_sev text; v_gl numeric; s public.accountant_month_scan;
begin
  if v_m >= date_trunc('month', now() at time zone 'Asia/Dubai')::date then
    raise exception 'month % has not ended; a month is closed only after it ends', to_char(v_m, 'YYYY-MM');
  end if;
  if exists (select 1 from public.accountant_month_close where month = v_m) then
    return jsonb_build_object('ok', true, 'month', to_char(v_m, 'YYYY-MM'), 'already_closed', true);
  end if;
  f := public.fn_accountant_month_close_figures(v_m);
  -- 10 Nov 2026 (ruling 1559): the books' cash is the book balance, never reconciled to a statement; the month's scan rides
  -- on the close so the CEO and the founder read what the receipts covered.
  select coalesce(sum(l.debit - l.credit), 0) into v_gl
    from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
   where l.account_code = '1000' and j.entry_date <= (v_m + interval '1 month' - interval '1 day')::date;
  select * into s from public.accountant_month_scan where month = v_m;
  f := f || jsonb_build_object(
    'book_cash', jsonb_build_object('gl_1000_aed', round(v_gl, 2), 'basis', 'book balance, not confirmed by a bank statement (founder ruling 1559)'),
    'month_end_email_scan', case when s.month is null then jsonb_build_object('asked', false)
                                 else jsonb_build_object('asked', true, 'requested_at', s.requested_at, 'scanned_at', s.scanned_at,
                                        'mailboxes', to_jsonb(s.mailboxes), 'receipts_found', s.receipts_found, 'receipts_booked', s.receipts_booked,
                                        'receipts_not_booked', s.receipts_unbooked) end);
  v_sev := case when (f->>'charge_audit_open_differences')::int > 0 or (f#>>'{disputes,open}')::int > 0
                -- 29 Sep 2026, instruction 1013: no runway target, the founder funds the company. Runway and the
                -- cash forecast are information and no longer raise the close's severity.
                then 'elevated' else 'routine' end;
  v_rep := public.fn_support_report_to_ceo('accountant_close:' || to_char(v_m, 'YYYY-MM'), v_sev,
    'Monthly close ' || to_char(v_m, 'Mon YYYY') || ': net result AED ' || (f#>>'{profit_and_loss,net_result_aed}')
      || ', book cash AED ' || round(v_gl, 2) || ' (not confirmed by a statement)'
      || ', AED ' || (f#>>'{held_for_possible_refunds,held_for_possible_refunds_aed}') || ' held for possible refunds, '
      || case when s.month is null then 'no month-end email scan was asked'
              else 'the month-end email scan found ' || s.receipts_found || ' receipt(s) and booked ' || s.receipts_booked end,
    f, '[]'::jsonb,
    'Acknowledge the close. The PDF and CSV are filed in finance-reports/accountant/close/' || to_char(v_m, 'YYYY-MM') || '.',
    p_review_in => interval '3 days', p_source_agent => 'accountant');
  insert into public.accountant_month_close (month, figures, ceo_report_id)
  values (v_m, f, (v_rep->>'report_id')::bigint);
  return jsonb_build_object('ok', true, 'month', to_char(v_m, 'YYYY-MM'), 'ceo_report', v_rep);
end $fn$;

-- ── 5. THE FOUNDER'S CLOSE PACK GOES OUT ON THE RECEIPTS ──────────────────────────────────────────────────────
create or replace function public.fn_accountant_founder_close_pack_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_local date := (now() at time zone 'Asia/Dubai')::date; v_prev date; v_b jsonb; v_s jsonb; p public.accountant_founder_close_pack; v_rep jsonb;
        v_close jsonb;
begin
  v_prev := (date_trunc('month', v_local) - interval '1 month')::date;
  -- the pack follows the close, due by the close's own day (fn_accountant_month_close_status; ruling 1559: no statement)
  v_close := public.fn_accountant_month_close_status(v_prev, v_local);
  if exists (select 1 from public.accountant_month_close where month = v_prev) then
    v_b := public.fn_accountant_founder_close_pack_build(v_prev);
  end if;
  select * into p from public.accountant_founder_close_pack where month = v_prev;
  if p.month is not null and p.sent_at is null and p.pdf_path is not null then
    v_s := public.fn_accountant_founder_close_pack_send(v_prev);
    select * into p from public.accountant_founder_close_pack where month = v_prev;
  end if;
  if p.sent_at is null
     and v_local > coalesce((v_close->>'due_by')::date, (v_prev + interval '1 month' + interval '4 days')::date) then
    v_rep := public.fn_support_report_to_ceo(
      p_idempotency_key => 'accountant_close_pack_day5:' || to_char(v_prev, 'YYYY-MM'), p_severity => 'elevated',
      p_subject => 'The founder''s ' || to_char(v_prev, 'Mon YYYY') || ' close pack was not sent by ' || coalesce(v_close->>'due_by', 'day 5'),
      p_evidence => jsonb_build_object('month', to_char(v_prev, 'YYYY-MM'), 'close', v_close,
                                       'built_at', p.built_at, 'rendered_at', p.rendered_at, 'render_error', p.render_error, 'send_result', p.send_result),
      p_attempted => '[]'::jsonb,
      p_requested => 'None from you: the accountant builds, renders and sends it on its next tick; this records the missed day.',
      p_review_in => interval '30 days', p_source_agent => 'accountant');
  end if;
  return jsonb_build_object('month', to_char(v_prev, 'YYYY-MM'), 'close_status', v_close->>'status', 'due_by', v_close->'due_by',
                            'build', v_b, 'send', v_s, 'sent_at', p.sent_at,
                            'late_reported', v_rep is not null);
end $fn$;

create or replace function public.fn_accountant_founder_close_pack_figures(p_month date)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_m date := date_trunc('month', p_month)::date;
  v_end date := (date_trunc('month', p_month) + interval '1 month' - interval '1 day')::date;
  v_close jsonb; v_gl numeric; v_pnl jsonb; v_unusual jsonb := '[]'::jsonb; v_pct numeric; v_min numeric; v_large numeric;
  r record; v_bank jsonb; v_ppa jsonb; v_receipts jsonb; s public.accountant_month_scan;
begin
  select figures into v_close from public.accountant_month_close where month = v_m;
  if v_close is null then
    raise exception 'month % is not closed: a close pack is built only for a closed, locked month', to_char(v_m, 'YYYY-MM');
  end if;
  select coalesce(max(num_value) filter (where key = 'close_pack_variance_pct'), 25),
         coalesce(max(num_value) filter (where key = 'close_pack_variance_min_aed'), 200),
         coalesce(max(num_value) filter (where key = 'close_pack_large_line_aed'), 1000)
    into v_pct, v_min, v_large from public.gl_settings
   where key in ('close_pack_variance_pct', 'close_pack_variance_min_aed', 'close_pack_large_line_aed');

  -- CASH: the books' bank account at month end, a book balance (10 Nov 2026, ruling 1559: no bank statement reconciliation)
  select coalesce(sum(l.debit - l.credit), 0) into v_gl
    from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
   where l.account_code = '1000' and j.entry_date <= v_end;
  v_bank := jsonb_build_object('gl_1000_aed', round(v_gl, 2), 'status', 'book balance',
    'basis', 'the books'' bank account (GL 1000) at month end; not confirmed by a bank statement (founder ruling 1559)');

  -- RECEIPTS: the founder's month-end email scan, and the month's expenses still without their receipt document
  select * into s from public.accountant_month_scan where month = v_m;
  v_receipts := jsonb_build_object(
    'scan', case when s.month is null then jsonb_build_object('asked', false, 'note', 'no month-end email scan was asked for this month')
                 else jsonb_build_object('asked', true, 'requested_at', s.requested_at, 'scanned_at', s.scanned_at, 'mailboxes', to_jsonb(s.mailboxes),
                        'found', s.receipts_found, 'booked', s.receipts_booked, 'not_booked', s.receipts_unbooked) end,
    'expenses_in_month', (select count(*) from public.expense_entries e where e.charged_on between v_m and v_end),
    'expenses_aed', (select coalesce(round(sum(e.amount) filter (where upper(e.currency) = 'AED'), 2), 0) from public.expense_entries e where e.charged_on between v_m and v_end),
    'without_receipt_document', (select coalesce(jsonb_agg(jsonb_build_object('expense_id', g.id, 'vendor', g.vendor, 'amount', g.amount,
                                   'currency', g.currency, 'charged_on', g.charged_on, 'remedy', g.remedy) order by g.charged_on, g.id), '[]'::jsonb)
                                   from public.v_expense_receipt_gap g where g.charged_on between v_m and v_end));

  -- P&L AGAINST BUDGET, per account that has either an actual or a budget line.
  with act as (
    select account_code as code, sum(revenue_aed) as actual from public.gl_revenue_lines_measured
     where entry_date between v_m and v_end group by 1
    union all
    select l.account_code, sum(l.debit - l.credit)
      from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
      join public.gl_accounts a on a.code = l.account_code and a.type = 'expense'
     where j.entry_date between v_m and v_end group by 1),
  bud as (
    select l.account_code as code, sum(l.amount) as budget
      from public.budget_lines l join public.budgets b on b.id = l.budget_id and b.status = 'active'
     where l.period_month = v_m group by 1),
  x as (
    select a.code, a.name, a.type, round(coalesce(act.actual, 0), 2) as actual, bud.budget
      from public.gl_accounts a left join act on act.code = a.code left join bud on bud.code = a.code
     where a.type in ('revenue', 'expense') and (act.code is not null or bud.code is not null))
  select jsonb_build_object(
           'accounts', coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name, 'type', type, 'actual_aed', actual,
                         'budget_aed', budget, 'variance_aed', case when budget is not null then round(actual - budget, 2) end,
                         'variance_pct', case when coalesce(budget, 0) <> 0 then round((actual - budget) / abs(budget) * 100, 1) end)
                       order by code), '[]'::jsonb),
           'revenue_actual_aed', coalesce(sum(actual) filter (where type = 'revenue'), 0),
           'revenue_budget_aed', coalesce(sum(budget) filter (where type = 'revenue'), 0),
           'expense_actual_aed', coalesce(sum(actual) filter (where type = 'expense'), 0),
           'expense_budget_aed', coalesce(sum(budget) filter (where type = 'expense'), 0),
           'net_actual_aed', coalesce(sum(actual) filter (where type = 'revenue'), 0) - coalesce(sum(actual) filter (where type = 'expense'), 0),
           'net_budget_aed', coalesce(sum(budget) filter (where type = 'revenue'), 0) - coalesce(sum(budget) filter (where type = 'expense'), 0),
           'budget_lines', count(budget))
    into v_pnl from x;

  -- UNUSUAL ITEMS, by rule. The explanation is the memo on the journals that make the item.
  for r in select e from jsonb_array_elements(v_pnl->'accounts') e
            where abs(coalesce((e->>'actual_aed')::numeric, 0) - coalesce((e->>'budget_aed')::numeric, 0)) >= v_min
              and (coalesce((e->>'budget_aed')::numeric, 0) = 0 or abs((e->>'variance_pct')::numeric) >= v_pct) loop
    v_unusual := v_unusual || jsonb_build_object('rule', 'budget_variance', 'account', r.e->>'code', 'name', r.e->>'name',
      'amount_aed', coalesce((r.e->>'actual_aed')::numeric, 0) - coalesce((r.e->>'budget_aed')::numeric, 0),
      'journals', (select coalesce(jsonb_agg(jsonb_build_object('journal', j.entry_no, 'amount_aed', l.debit - l.credit,
                          'memo', coalesce(nullif(btrim(l.memo), ''), nullif(btrim(j.memo), ''))) order by j.entry_date, l.id), '[]'::jsonb)
                     from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
                    where l.account_code = r.e->>'code' and j.entry_date between v_m and v_end));
  end loop;
  for r in select j.entry_no, l.account_code, l.debit, l.credit, coalesce(nullif(btrim(l.memo), ''), nullif(btrim(j.memo), '')) as memo
             from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
             join public.gl_accounts a on a.code = l.account_code and a.type in ('revenue', 'expense')
            where j.entry_date between v_m and v_end and greatest(l.debit, l.credit) >= v_large
            order by j.entry_date, l.id loop
    v_unusual := v_unusual || jsonb_build_object('rule', 'large_line', 'account', r.account_code, 'amount_aed', greatest(r.debit, r.credit),
      'journals', jsonb_build_array(jsonb_build_object('journal', r.entry_no, 'amount_aed', r.debit - r.credit, 'memo', r.memo)));
  end loop;
  -- A reversal is the journal fn_gl_reverse writes (source 'reversal', source_ref = the original's id), dated in the
  -- month, in ANY status: fn_gl_reverse voids both sides, so a posted-only rule never fired (re-review of #1063).
  for r in select coalesce(j.entry_no, 'journal ' || j.id) as entry_no, j.memo, j.status,
                  coalesce(o.entry_no, 'journal ' || o.id) as original,
                  (select sum(l.debit) from public.gl_journal_lines l where l.journal_id = j.id) as amount
             from public.gl_journal j
             left join public.gl_journal o on o.id = coalesce(j.reverses, case when j.source_ref ~ '^[0-9]+$' then j.source_ref::bigint end)
            where j.source = 'reversal' and j.entry_date between v_m and v_end order by j.entry_date, j.id loop
    v_unusual := v_unusual || jsonb_build_object('rule', 'reversal', 'reverses', r.original, 'status', r.status, 'amount_aed', r.amount,
      'journals', jsonb_build_array(jsonb_build_object('journal', r.entry_no, 'memo', nullif(btrim(r.memo), ''))));
  end loop;
  -- a late item for a month already closed, booked in this month (fn_gl_post, gl_prior_period_adjustment)
  select coalesce(jsonb_agg(jsonb_build_object('journal', j.entry_no, 'posted_on', a.posted_on, 'original_date', a.original_date,
                            'closed_month', to_char(a.closed_month, 'YYYY-MM'), 'statement_line_id', a.statement_line_id,
                            'source', a.source, 'amount_aed', a.amount_aed, 'memo', nullif(btrim(j.memo), ''))
                            order by a.posted_on, a.journal_id), '[]'::jsonb)
    into v_ppa
    from public.gl_prior_period_adjustment a join public.gl_journal j on j.id = a.journal_id and j.status = 'posted'
   where a.posted_on between v_m and v_end;
  for r in select e from jsonb_array_elements(v_ppa) e loop
    v_unusual := v_unusual || jsonb_build_object('rule', 'prior_period_adjustment', 'amount_aed', (r.e->>'amount_aed')::numeric,
      'journals', jsonb_build_array(jsonb_build_object('journal', r.e->>'journal', 'memo', r.e->>'memo')),
      'explanation', (r.e->>'journal') || ': dated ' || (r.e->>'original_date') || ' in ' || (r.e->>'closed_month') || ', which was already closed'
                     || '; booked in this month as a prior-period adjustment (IFRS for SMEs Section 10: an immaterial prior-period item is corrected in the current period)');
  end loop;
  -- a receipt the month-end scan found and could not book is an unusual item with its own reason
  for r in select e from jsonb_array_elements(coalesce(s.receipts_unbooked, '[]'::jsonb)) e loop
    v_unusual := v_unusual || jsonb_build_object('rule', 'receipt_not_booked', 'amount_aed', nullif(r.e->>'amount_aed', '')::numeric,
      'journals', '[]'::jsonb, 'explanation', (r.e->>'what') || ': not booked by the month-end email scan, because ' || (r.e->>'why'));
  end loop;
  -- an item is explained when it names its cause: every journal it lists carries a memo, or it states its own
  select coalesce(jsonb_agg(u || jsonb_build_object('explained',
           coalesce(u ? 'explanation', false)
           or (jsonb_array_length(u->'journals') > 0 and not exists (select 1 from jsonb_array_elements(u->'journals') jj where jj->>'memo' is null)))), '[]'::jsonb)
    into v_unusual from jsonb_array_elements(v_unusual) u;

  return jsonb_build_object(
    'month', to_char(v_m, 'YYYY-MM'), 'from', v_m, 'to', v_end, 'built_from', 'the closed month (period locked)',
    'bank', v_bank,
    'receipts', v_receipts,
    'vat', coalesce(v_close->'vat', '{}'::jsonb) || jsonb_build_object('registered', false,
             'note', 'QuotesDone is not VAT-registered; registration is required only past the threshold (fn_vat_threshold_position).'),
    'pnl_vs_budget', v_pnl,
    'runway', public.fn_accountant_runway_figures(v_m) - 'cash_13_weeks',
    'prior_period_adjustments', v_ppa,
    'unusual', v_unusual,
    'unusual_items', jsonb_array_length(v_unusual),
    'unexplained_items', (select count(*) from jsonb_array_elements(v_unusual) u where not (u->>'explained')::boolean),
    'rules', jsonb_build_object('variance_pct', v_pct, 'variance_min_aed', v_min, 'large_line_aed', v_large));
end $fn$;

create or replace function public.fn_accountant_founder_close_pack_document(p_month date)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare f jsonb; v_title text; v_pnl jsonb; v_unu jsonb; v_n numeric;
begin
  select figures into f from public.accountant_founder_close_pack where month = date_trunc('month', p_month)::date;
  if f is null then raise exception 'no close pack is built for %', to_char(p_month, 'YYYY-MM'); end if;
  v_title := 'QuotesDone close pack ' || (f->>'month');
  select coalesce(jsonb_agg(jsonb_build_array(e->>'code' || ' ' || (e->>'name'), e->>'actual_aed', coalesce(e->>'budget_aed', '-'),
                            coalesce(e->>'variance_aed', '-') || coalesce(' (' || (e->>'variance_pct') || '%)', '')) order by e->>'code'), '[]'::jsonb)
    into v_pnl from jsonb_array_elements(f#>'{pnl_vs_budget,accounts}') e;
  select coalesce(jsonb_agg(jsonb_build_array(
           u->>'rule' || coalesce(' ' || (u->>'account'), ''), coalesce(u->>'amount_aed', '-'),
           case when (u->>'explained')::boolean
                then coalesce(u->>'explanation', (select string_agg(coalesce(jj->>'journal', '') || ': ' || (jj->>'memo'), '; ') from jsonb_array_elements(u->'journals') jj))
                else 'UNEXPLAINED: ' || coalesce((select string_agg(jj->>'journal', ', ') from jsonb_array_elements(u->'journals') jj where jj->>'memo' is null), 'no journal') || ' has no memo' end)), '[]'::jsonb)
    into v_unu from jsonb_array_elements(f->'unusual') u;
  v_n := jsonb_array_length(v_unu);
  return jsonb_build_object('month', f->>'month', 'title', v_title, 'name', 'QuotesDone_Close_Pack_' || (f->>'month'),
    'blocks', jsonb_build_array(
      jsonb_build_object('t', 'h2', 'text', v_title),
      jsonb_build_object('t', 'p', 'text', 'Period ' || (f->>'from') || ' to ' || (f->>'to') || ', read from the closed and locked month. Nothing is estimated; a figure the books do not hold prints as missing.'),
      jsonb_build_object('t', 'h3', 'text', '1. Cash and receipts'),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Item', 'Value'), 'widths', jsonb_build_array(0.65, 0.35), 'rows', jsonb_build_array(
        jsonb_build_array('Books, account 1000 (AED; a book balance, not confirmed by a bank statement)', coalesce(f#>>'{bank,gl_1000_aed}', 'missing')),
        jsonb_build_array('Month-end email scan', case when (f#>>'{receipts,scan,asked}')::boolean
                            then 'run ' || left(f#>>'{receipts,scan,scanned_at}', 10) || ' over ' || coalesce((select string_agg(x #>> '{}', ', ') from jsonb_array_elements(f#>'{receipts,scan,mailboxes}') x), '-')
                            else 'not asked for this month' end),
        jsonb_build_array('Receipts found / booked by the scan', coalesce((f#>>'{receipts,scan,found}') || ' / ' || (f#>>'{receipts,scan,booked}'), '-')),
        jsonb_build_array('Expenses booked in the month', coalesce(f#>>'{receipts,expenses_in_month}', 'missing')),
        jsonb_build_array('Expenses still without their receipt document', coalesce(jsonb_array_length(f#>'{receipts,without_receipt_document}')::text, 'missing')))),
      jsonb_build_object('t', 'h3', 'text', '2. VAT position'),
      jsonb_build_object('t', 'p', 'text', 'Not VAT-registered. Rolling 12-month turnover AED ' || coalesce(f#>>'{vat,turnover_aed}', 'missing')
        || coalesce(' of the AED ' || (f#>>'{vat,threshold_aed}') || ' threshold', '') || coalesce(' (' || (f#>>'{vat,band}') || ')', '') || '.'),
      jsonb_build_object('t', 'h3', 'text', '3. Profit and loss against budget'),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Account', 'Actual', 'Budget', 'Variance'),
                         'widths', jsonb_build_array(0.43, 0.17, 0.17, 0.23), 'rows', v_pnl || jsonb_build_array(
        jsonb_build_array('Net result', f#>>'{pnl_vs_budget,net_actual_aed}', f#>>'{pnl_vs_budget,net_budget_aed}',
          ((f#>>'{pnl_vs_budget,net_actual_aed}')::numeric - (f#>>'{pnl_vs_budget,net_budget_aed}')::numeric)::text))),
      jsonb_build_object('t', 'h3', 'text', '4. Cash runway'),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Item', 'Value'), 'widths', jsonb_build_array(0.65, 0.35), 'rows', jsonb_build_array(
        jsonb_build_array('Available cash (AED)', coalesce(f#>>'{runway,available_aed}', 'missing')),
        jsonb_build_array('Runway at actual spend (months)', coalesce(f#>>'{runway,runway_months_at_actual_spend}', 'missing')),
        jsonb_build_array('Runway at budget (months)', coalesce(f#>>'{runway,runway_months_at_budget}', 'missing')))),
      jsonb_build_object('t', 'h3', 'text', '5. Unusual items (' || v_n || ', ' || (f->>'unexplained_items') || ' unexplained)'),
      case when v_n = 0 then jsonb_build_object('t', 'p', 'text', 'None under the rules: variance past ' || (f#>>'{rules,variance_pct}') || '% and AED '
                                                || (f#>>'{rules,variance_min_aed}') || ', a line of AED ' || (f#>>'{rules,large_line_aed}') || ' or more, a reversal, a prior-period adjustment, a receipt the month-end scan could not book.')
           else jsonb_build_object('t', 'table', 'head', jsonb_build_array('Item', 'AED', 'Explanation'), 'widths', jsonb_build_array(0.25, 0.15, 0.6), 'rows', v_unu) end,
      jsonb_build_object('t', 'note', 'text', 'Prepared by the QuotesDone accountant from gl_journal, expense_entries, the month-end email scan, budget_lines and the month close. Informational; nothing here needs your approval.')));
end $fn$;

-- already closed to clients on production (10 Nov 2026); restated so the file says so itself
revoke execute on function public.fn_accountant_month_close_status(date, date) from public, anon, authenticated;
revoke execute on function public.fn_accountant_month_close_tick() from public, anon, authenticated;
revoke execute on function public.fn_accountant_close_by_day_5() from public, anon, authenticated;
revoke execute on function public.fn_accountant_month_close(date) from public, anon, authenticated;
revoke execute on function public.fn_accountant_founder_close_pack_tick() from public, anon, authenticated;
revoke execute on function public.fn_accountant_founder_close_pack_figures(date) from public, anon, authenticated;
revoke execute on function public.fn_accountant_founder_close_pack_document(date) from public, anon, authenticated;

-- ── VERDICT (read-only) ─────────────────────────────────────────────────────────────────────────────────────────
select case when problems is null then 'PROBE OK' else 'PROBE FAILED: ' || problems end as verdict from (
  select string_agg(p, '; ') problems from (
    select 'a routine is open or unpinned: ' || p.oid::regprocedure::text p from pg_proc p
     where p.oid in ('public.fn_accountant_month_scan_record(date,timestamptz,text[],integer,integer,jsonb,text,timestamptz,text)'::regprocedure,
                     'public.fn_accountant_month_close_status(date,date)'::regprocedure, 'public.fn_accountant_month_close_tick()'::regprocedure,
                     'public.fn_accountant_close_by_day_5()'::regprocedure, 'public.fn_accountant_month_close(date)'::regprocedure,
                     'public.fn_accountant_founder_close_pack_tick()'::regprocedure, 'public.fn_accountant_founder_close_pack_figures(date)'::regprocedure,
                     'public.fn_accountant_founder_close_pack_document(date)'::regprocedure)
       and (not p.prosecdef or not coalesce(p.proconfig @> array['search_path=public, pg_temp'], false)
            or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
    union all select 'a close routine still waits for a statement: ' || p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname in ('fn_accountant_month_close_status', 'fn_accountant_month_close_tick', 'fn_accountant_close_by_day_5',
                                                   'fn_accountant_founder_close_pack_tick', 'fn_accountant_founder_close_pack_figures')
       and (position('waiting_for_' || 'statement' in p.prosrc) > 0 or position('bank_statement_' || 'intake' in p.prosrc) > 0)
    union all select 'the scan table is readable by a client'
     where has_table_privilege('anon', 'public.accountant_month_scan', 'select') or has_table_privilege('authenticated', 'public.accountant_month_scan', 'select')
    union all select 'the scan table has no policy' where not exists (select 1 from pg_policy where polrelid = 'public.accountant_month_scan'::regclass)
  ) z) y;
