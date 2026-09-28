-- THE ACCOUNTANT SENDS THE FOUNDER ONE CLOSE PACK BY THE FIFTH — accountant, 29 Sep 2026.
-- Founder instruction 1009, upgrade 8: a monthly close pack by the 5th of each month — the bank reconciled to the
-- Mashreq statement, the VAT position, P&L against budget, cash runway and unusual items explained — to the founder
-- as ONE short PDF through fn_notify_founder with the correct p_kind, respecting the period lock.
--
-- STACKED ON #1013 (scripts/sql/the_accountant_keeps_one_cash_truth_and_closes_the_open_audit_gaps.sql): that file
-- seeds the active budget (budgets / budget_lines), the period lock (a05_gl_period_lock on gl_journal, which refuses a
-- posting dated in a month that has an accountant_month_close row), fn_accountant_runway_figures and the close by day 5.
--
-- WHAT WAS THERE (measured 29 Sep 2026 on htdblwldjkcgjvmqkbeh): accountant_month_close holds one month (2026-08) and
-- its PDF goes to the CEO only (fn_support_report_to_ceo). Nothing reached the founder for a month. The close figures
-- carry Stripe payouts matched to the bank, not the GL bank account against the Mashreq statement; P&L had no budget
-- column (0 budgets before #1013); nothing named an unusual item or asked for its explanation.
--
-- WHAT THIS BUILDS
--   1. public.accountant_founder_close_pack — one row per month: the figures, the PDF, and what the send did.
--   2. fn_accountant_founder_close_pack_figures(month) — pure reads, no posting:
--        bank      GL 1000 at month end against the Mashreq statement closing balance of that month
--                  (bank_statement_intake), with the reconciling items: statement lines with no posted journal
--                  (source bank_charge / bank_interest / owner_capital, source_ref = the line id) and GL 1000
--                  postings no statement line carries. 'reconciled' only when the rest is within AED 0.01.
--        vat       the VAT position the close stored (accountant_month_close.figures->vat): not registered,
--                  rolling 12-month turnover, band, headroom.
--        pnl       per account: actual (posted, revenue through gl_revenue_lines_measured) against the active
--                  budget's line for the month, variance AED and %.
--        runway    fn_accountant_runway_figures(month): at actual spend and at budget.
--        unusual   by rule, never by reading words: a budget variance past gl_settings close_pack_variance_pct
--                  (default 25) AND close_pack_variance_min_aed (default 200); a single P&L line of at least
--                  close_pack_large_line_aed (default 1000); a reversal posted in the month; an unbooked statement
--                  line. Each carries its journals and their memos as the explanation; a journal with no memo
--                  prints UNEXPLAINED and counts in unexplained_items.
--   3. THE PERIOD LOCK IS RESPECTED: a pack is built only for a month that is closed (it has its
--      accountant_month_close row, so a05_gl_period_lock already refuses postings dated in it), and it is built
--      once — the stored figures are the locked month's, never re-read after a reopen.
--   4. fn_accountant_founder_close_pack_document(month) — the pdf_native blocks: one short PDF.
--      The accountant runtime renders it (supabase/functions/accountant/index.ts) and calls
--      fn_accountant_founder_close_pack_attach, which sends.
--   5. fn_accountant_founder_close_pack_send(month) — fn_notify_founder(p_kind => 'accountant_close_pack',
--      p_level => 'info', p_owner_agent => 'accountant', p_dedupe_key => 'accountant_close_pack:YYYY-MM'), then
--      the PDF is attached to the email row fn_notify_founder queued (the notification's own attachments column,
--      which send_outbox v43 delivers). A kind the policy does not allow is recorded as not sent, never forced.
--   6. seat_duty accountant.founder_close_pack (daily): builds the previous month once it is closed, re-sends a
--      rendered pack that did not go, and past day 5 (Asia/Dubai) with nothing sent reports the miss to the CEO.
--
-- Proved by scripts/sql/the_accountant_sends_the_founder_one_close_pack_by_the_fifth_probe.sql (aborted
-- transaction, ZZ DEMO month 2020-01, must print PROBE OK).

-- ── 1. the pack record ──────────────────────────────────────────────────────────────────────────
create table if not exists public.accountant_founder_close_pack (
  month           date primary key check (month = date_trunc('month', month)::date),
  figures         jsonb not null,
  built_at        timestamptz not null default now(),
  pdf_bucket      text,
  pdf_path        text,
  rendered_at     timestamptz,
  render_error    text,
  sent_at         timestamptz,
  notification_id bigint,
  send_result     jsonb
);
alter table public.accountant_founder_close_pack enable row level security;
drop policy if exists accountant_founder_close_pack_service_role_only on public.accountant_founder_close_pack;
create policy accountant_founder_close_pack_service_role_only on public.accountant_founder_close_pack
  as permissive for all to public using (false) with check (false);
revoke all on public.accountant_founder_close_pack from anon, authenticated;
comment on table public.accountant_founder_close_pack is
  'The founder''s monthly close pack (instruction 1009 upgrade 8): bank to Mashreq statement, VAT position, P&L against budget, runway, unusual items explained. Built once per closed (locked) month; sent as one PDF through fn_notify_founder kind accountant_close_pack.';

insert into public.founder_mail_policy (kind, allowed_to_email, owner_role, reason) values
  ('accountant_close_pack', true, 'accountant',
   'Founder instruction 1009, upgrade 8 (29 Sep 2026): the accountant''s monthly close pack reaches the founder as one short PDF by the 5th. Informational; it asks him for nothing.')
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, owner_role = excluded.owner_role, reason = excluded.reason;

-- ── 2. the figures ──────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_founder_close_pack_figures(p_month date)
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_m date := date_trunc('month', p_month)::date;
  v_end date := (date_trunc('month', p_month) + interval '1 month' - interval '1 day')::date;
  v_close jsonb; v_stmt record; v_gl numeric; v_unbooked numeric; v_bookonly numeric; v_rest numeric;
  v_unb jsonb; v_bo jsonb; v_pnl jsonb; v_unusual jsonb := '[]'::jsonb; v_pct numeric; v_min numeric; v_large numeric;
  r record; v_bank jsonb;
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

  -- BANK: the books' bank account at month end against the Mashreq statement of that month.
  select * into v_stmt from public.bank_statement_intake
   where account = 'mashreq' and statement_month = v_m and closing_balance_aed is not null
   order by received_at desc limit 1;
  select coalesce(sum(l.debit - l.credit), 0) into v_gl
    from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
   where l.account_code = '1000' and j.entry_date <= v_end;
  -- statement lines to month end that no posted journal books
  select coalesce(sum(b.amount_aed), 0),
         coalesce(jsonb_agg(jsonb_build_object('line_id', b.id, 'date', b.value_date, 'amount_aed', b.amount_aed, 'kind', b.kind,
                                               'description', b.description) order by b.value_date, b.id), '[]'::jsonb)
    into v_unbooked, v_unb
    from public.bank_statement_line b
   where b.account = 'mashreq' and b.value_date <= v_end
     and not exists (select 1 from public.gl_journal g
                      where g.status = 'posted' and g.source in ('bank_charge', 'bank_interest', 'owner_capital')
                        and g.source_ref = b.id::text);
  -- GL 1000 postings to month end that came from no statement line
  select coalesce(sum(l.debit - l.credit), 0),
         coalesce(jsonb_agg(jsonb_build_object('journal', j.entry_no, 'date', j.entry_date, 'amount_aed', l.debit - l.credit,
                                               'source', j.source, 'memo', coalesce(nullif(btrim(l.memo), ''), j.memo))
                            order by j.entry_date, j.id), '[]'::jsonb)
    into v_bookonly, v_bo
    from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
   where l.account_code = '1000' and j.entry_date <= v_end
     and not (j.source in ('bank_charge', 'bank_interest', 'owner_capital')
              and exists (select 1 from public.bank_statement_line b where b.account = 'mashreq' and b.id::text = j.source_ref));
  v_rest := case when v_stmt.closing_balance_aed is not null
                 then round(v_stmt.closing_balance_aed - (v_gl + v_unbooked - v_bookonly), 2) end;
  v_bank := jsonb_build_object(
    'statement_closing_aed', v_stmt.closing_balance_aed, 'statement_balance_on', v_stmt.balance_on,
    'statement_source', v_stmt.source_ref, 'gl_1000_aed', round(v_gl, 2),
    'difference_aed', case when v_stmt.closing_balance_aed is not null then round(v_stmt.closing_balance_aed - v_gl, 2) end,
    'unbooked_statement_lines', v_unb, 'unbooked_aed', round(v_unbooked, 2),
    'book_only_postings', v_bo, 'book_only_aed', round(v_bookonly, 2),
    'unexplained_aed', v_rest,
    'status', case when v_stmt.closing_balance_aed is null then 'missing: no Mashreq statement with a closing balance for ' || to_char(v_m, 'YYYY-MM')
                   when abs(v_rest) <= 0.01 then 'reconciled' else 'not reconciled' end);

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
  for r in select j.entry_no, j.memo, o.entry_no as original from public.gl_journal j left join public.gl_journal o on o.id = j.reverses
            where j.status = 'posted' and j.reverses is not null and j.entry_date between v_m and v_end order by j.entry_date, j.id loop
    v_unusual := v_unusual || jsonb_build_object('rule', 'reversal', 'reverses', r.original,
      'journals', jsonb_build_array(jsonb_build_object('journal', r.entry_no, 'memo', nullif(btrim(r.memo), ''))));
  end loop;
  for r in select e from jsonb_array_elements(v_unb) e where (e->>'date')::date between v_m and v_end loop
    v_unusual := v_unusual || jsonb_build_object('rule', 'unbooked_statement_line', 'amount_aed', (r.e->>'amount_aed')::numeric,
      'journals', '[]'::jsonb, 'explanation', 'statement line ' || (r.e->>'line_id') || ' (' || coalesce(r.e->>'description', '') || ') has no posted journal');
  end loop;
  -- an item is explained when it names its cause: every journal it lists carries a memo, or it states its own
  select coalesce(jsonb_agg(u || jsonb_build_object('explained',
           coalesce(u ? 'explanation', false)
           or (jsonb_array_length(u->'journals') > 0 and not exists (select 1 from jsonb_array_elements(u->'journals') jj where jj->>'memo' is null)))), '[]'::jsonb)
    into v_unusual from jsonb_array_elements(v_unusual) u;

  return jsonb_build_object(
    'month', to_char(v_m, 'YYYY-MM'), 'from', v_m, 'to', v_end, 'built_from', 'the closed month (period locked)',
    'bank', v_bank,
    'vat', coalesce(v_close->'vat', '{}'::jsonb) || jsonb_build_object('registered', false,
             'note', 'QuotesDone is not VAT-registered; registration is required only past the threshold (fn_vat_threshold_position).'),
    'pnl_vs_budget', v_pnl,
    'runway', public.fn_accountant_runway_figures(v_m) - 'cash_13_weeks',
    'unusual', v_unusual,
    'unusual_items', jsonb_array_length(v_unusual),
    'unexplained_items', (select count(*) from jsonb_array_elements(v_unusual) u where not (u->>'explained')::boolean),
    'rules', jsonb_build_object('variance_pct', v_pct, 'variance_min_aed', v_min, 'large_line_aed', v_large));
end $fn$;
revoke execute on function public.fn_accountant_founder_close_pack_figures(date) from public, anon, authenticated;

-- ── 3. build once, from the locked month ────────────────────────────────────────────────────────
create or replace function public.fn_accountant_founder_close_pack_build(p_month date)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_m date := date_trunc('month', p_month)::date; v_f jsonb;
begin
  if exists (select 1 from public.accountant_founder_close_pack where month = v_m) then
    return jsonb_build_object('ok', true, 'month', to_char(v_m, 'YYYY-MM'), 'already_built', true);
  end if;
  v_f := public.fn_accountant_founder_close_pack_figures(v_m);   -- refuses an open month
  insert into public.accountant_founder_close_pack (month, figures) values (v_m, v_f);
  return jsonb_build_object('ok', true, 'month', to_char(v_m, 'YYYY-MM'), 'built', true,
                            'bank', v_f#>>'{bank,status}', 'unusual_items', v_f->'unusual_items', 'unexplained_items', v_f->'unexplained_items');
end $fn$;
revoke execute on function public.fn_accountant_founder_close_pack_build(date) from public, anon, authenticated;

-- ── 4. one short PDF ────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_founder_close_pack_document(p_month date)
returns jsonb language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
      jsonb_build_object('t', 'h3', 'text', '1. Bank against the Mashreq statement'),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Item', 'AED'), 'widths', jsonb_build_array(0.65, 0.35), 'rows', jsonb_build_array(
        jsonb_build_array('Statement closing balance (' || coalesce(f#>>'{bank,statement_balance_on}', 'missing') || ')', coalesce(f#>>'{bank,statement_closing_aed}', 'missing')),
        jsonb_build_array('Books, account 1000', f#>>'{bank,gl_1000_aed}'),
        jsonb_build_array('Statement lines not yet booked', f#>>'{bank,unbooked_aed}'),
        jsonb_build_array('Booked, not on the statement', f#>>'{bank,book_only_aed}'),
        jsonb_build_array('Unexplained', coalesce(f#>>'{bank,unexplained_aed}', 'missing')),
        jsonb_build_array('Status', f#>>'{bank,status}'))),
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
                                                || (f#>>'{rules,variance_min_aed}') || ', a line of AED ' || (f#>>'{rules,large_line_aed}') || ' or more, a reversal, an unbooked statement line.')
           else jsonb_build_object('t', 'table', 'head', jsonb_build_array('Item', 'AED', 'Explanation'), 'widths', jsonb_build_array(0.25, 0.15, 0.6), 'rows', v_unu) end,
      jsonb_build_object('t', 'note', 'text', 'Prepared by the QuotesDone accountant from gl_journal, bank_statement_line/intake, budget_lines and the month close. Informational; nothing here needs your approval.')));
end $fn$;
revoke execute on function public.fn_accountant_founder_close_pack_document(date) from public, anon, authenticated;

-- ── 5. send through fn_notify_founder, PDF attached ─────────────────────────────────────────────
create or replace function public.fn_accountant_founder_close_pack_send(p_month date)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare p public.accountant_founder_close_pack; v_before bigint; v_res jsonb; v_nid bigint; f jsonb;
begin
  select * into p from public.accountant_founder_close_pack where month = date_trunc('month', p_month)::date for update;
  if p.month is null then raise exception 'no close pack is built for %', to_char(p_month, 'YYYY-MM'); end if;
  if p.sent_at is not null then return jsonb_build_object('ok', true, 'already_sent', p.sent_at, 'notification_id', p.notification_id); end if;
  if p.pdf_path is null then return jsonb_build_object('ok', false, 'reason', 'the PDF is not rendered yet'); end if;
  f := p.figures;
  select coalesce(max(id), 0) into v_before from public.notifications;
  v_res := public.fn_notify_founder(
    p_event => 'Close pack ' || (f->>'month') || ': net AED ' || (f#>>'{pnl_vs_budget,net_actual_aed}') || ' against budget AED ' || (f#>>'{pnl_vs_budget,net_budget_aed}'),
    p_detail => 'Your close pack for ' || (f->>'month') || ' is attached (one PDF).' || E'\n'
      || 'Bank against the Mashreq statement: ' || (f#>>'{bank,status}') || '.' || E'\n'
      || 'Runway: ' || coalesce((f#>>'{runway,runway_months_at_actual_spend}') || ' months at actual spend', 'missing') || '.' || E'\n'
      || 'Unusual items: ' || (f->>'unusual_items') || ' (' || (f->>'unexplained_items') || ' unexplained).' || E'\n'
      || 'Nothing here needs your approval.',
    p_level => 'info', p_kind => 'accountant_close_pack',
    p_dedupe_key => 'accountant_close_pack:' || (f->>'month'), p_owner_agent => 'accountant');
  select id into v_nid from public.notifications
   where id > v_before and type = 'founder_alert' and kind = 'accountant_close_pack' and channel = 'email'
   order by id limit 1;
  if v_nid is null then
    update public.accountant_founder_close_pack set send_result = v_res where month = p.month;
    return jsonb_build_object('ok', false, 'reason', 'fn_notify_founder queued no email', 'notify', v_res);
  end if;
  update public.notifications
     set attachments = jsonb_build_array(jsonb_build_object('bucket', p.pdf_bucket, 'path', p.pdf_path,
                                                            'filename', 'QuotesDone_Close_Pack_' || (f->>'month') || '.pdf'))
   where id = v_nid;
  update public.accountant_founder_close_pack set sent_at = now(), notification_id = v_nid, send_result = v_res where month = p.month;
  return jsonb_build_object('ok', true, 'month', f->>'month', 'notification_id', v_nid, 'notify', v_res);
end $fn$;
revoke execute on function public.fn_accountant_founder_close_pack_send(date) from public, anon, authenticated;

create or replace function public.fn_accountant_founder_close_pack_attach(p_month date, p_bucket text, p_pdf_path text, p_error text default null)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if coalesce(btrim(p_pdf_path), '') = '' then
    update public.accountant_founder_close_pack set render_error = coalesce(p_error, 'no PDF path') where month = date_trunc('month', p_month)::date;
    return jsonb_build_object('ok', false, 'month', to_char(p_month, 'YYYY-MM'), 'error', coalesce(p_error, 'no PDF path'));
  end if;
  update public.accountant_founder_close_pack
     set pdf_bucket = p_bucket, pdf_path = p_pdf_path, rendered_at = now(), render_error = null
   where month = date_trunc('month', p_month)::date;
  if not found then raise exception 'no close pack is built for %', to_char(p_month, 'YYYY-MM'); end if;
  return public.fn_accountant_founder_close_pack_send(p_month);
end $fn$;
revoke execute on function public.fn_accountant_founder_close_pack_attach(date, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_accountant_founder_close_pack_document(date) to service_role;
grant execute on function public.fn_accountant_founder_close_pack_attach(date, text, text, text) to service_role;

-- ── 6. the daily duty: built when closed, sent by the 5th ───────────────────────────────────────
create or replace function public.fn_accountant_founder_close_pack_tick()
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_local date := (now() at time zone 'Asia/Dubai')::date; v_prev date; v_b jsonb; v_s jsonb; p public.accountant_founder_close_pack; v_rep jsonb;
begin
  v_prev := (date_trunc('month', v_local) - interval '1 month')::date;
  if exists (select 1 from public.accountant_month_close where month = v_prev) then
    v_b := public.fn_accountant_founder_close_pack_build(v_prev);
  end if;
  select * into p from public.accountant_founder_close_pack where month = v_prev;
  if p.month is not null and p.sent_at is null and p.pdf_path is not null then
    v_s := public.fn_accountant_founder_close_pack_send(v_prev);
    select * into p from public.accountant_founder_close_pack where month = v_prev;
  end if;
  if p.sent_at is null and extract(day from v_local) > 5 then
    v_rep := public.fn_support_report_to_ceo(
      p_idempotency_key => 'accountant_close_pack_day5:' || to_char(v_prev, 'YYYY-MM'), p_severity => 'elevated',
      p_subject => 'The founder''s ' || to_char(v_prev, 'Mon YYYY') || ' close pack was not sent by day 5',
      p_evidence => jsonb_build_object('month', to_char(v_prev, 'YYYY-MM'), 'month_closed', exists (select 1 from public.accountant_month_close where month = v_prev),
                                       'built_at', p.built_at, 'rendered_at', p.rendered_at, 'render_error', p.render_error, 'send_result', p.send_result),
      p_attempted => '[]'::jsonb,
      p_requested => 'None from you: the accountant builds, renders and sends it on its next tick; this records the missed day.',
      p_review_in => interval '30 days', p_source_agent => 'accountant');
  end if;
  return jsonb_build_object('month', to_char(v_prev, 'YYYY-MM'), 'build', v_b, 'send', v_s, 'sent_at', p.sent_at,
                            'late_reported', v_rep is not null);
end $fn$;
revoke execute on function public.fn_accountant_founder_close_pack_tick() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('accountant.founder_close_pack', 'accountant', interval '1 day', 'fn_accountant_founder_close_pack_tick',
   'the founder''s monthly close pack (bank to Mashreq, VAT, P&L against budget, runway, unusual items explained) built from the locked month and sent as one PDF by the 5th',
   'scripts/sql/the_accountant_sends_the_founder_one_close_pack_by_the_fifth.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
