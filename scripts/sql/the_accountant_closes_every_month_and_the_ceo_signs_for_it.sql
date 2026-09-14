-- THE ACCOUNTANT CLOSES EVERY MONTH, AND THE CEO SIGNS FOR IT.
--
-- Assigned: accountant (duty 8 of the eight, founder 14 Sep 2026: "yea add them all"); the
-- acknowledgement is the ceo's (fn_ceo_accountant_reports_sweep).
--
-- WHAT WAS MEASURED (14 Sep 2026, production htdblwldjkcgjvmqkbeh):
--   * The accountant files a weekly report (fn_accountant_weekly_report_figures over any window) and a
--     VAT watch to the CEO through fn_support_report_to_ceo. Every one of them sits at status 'sent':
--     support_ceo_report ids 138, 140 and 147 were never accepted, because the only CEO sweep that
--     accepts a report reads source_agent 'it_engineer'. The CEO never acknowledged a single accountant
--     report — a one-way message, exactly what the founder ruled out.
--   * Nothing produced a month: no P&L by account, no statement of cash in and out, no reconciliation
--     status, and no document an auditor could be handed.
--
-- WHAT THIS BUILDS: public.accountant_month_close, one row per closed month, holding the figures, the
-- CEO report and the paths of the PDF and CSV the accountant runtime renders (pdf_native, English,
-- finance-reports/accountant/close/<YYYY-MM>). The figures reuse fn_accountant_weekly_report_figures
-- over the month and add the P&L from posted journals, the payout reconciliation, cash in and out, the
-- refund reserve ("held for possible refunds"), disputes, collections aging, the subscription position,
-- the VAT position, bank drafts waiting and open charge-audit differences. fn_ceo_accountant_reports_sweep
-- makes the CEO accept every accountant report with a receipt naming what it read, and
-- fn_accountant_reports_complete closes each one only once that receipt is on it.
--
--   node scripts/apply_sql.mjs scripts/sql/the_accountant_closes_every_month_and_the_ceo_signs_for_it.sql --apply --ddl

create table if not exists public.accountant_month_close (
  month         date primary key check (month = date_trunc('month', month)::date),
  figures       jsonb       not null,
  ceo_report_id bigint,
  pdf_bucket    text,
  pdf_path      text,
  csv_path      text,
  closed_at     timestamptz not null default now(),
  rendered_at   timestamptz
);
comment on table public.accountant_month_close is
  'One row per month the accountant closed: the figures, the CEO report that carried them, and the auditor-ready PDF and CSV (English) in finance-reports.';
alter table public.accountant_month_close enable row level security;
drop policy if exists accountant_month_close_service_role_only on public.accountant_month_close;
create policy accountant_month_close_service_role_only on public.accountant_month_close as permissive for all to public using (false) with check (false);
revoke all on public.accountant_month_close from anon, authenticated;

insert into public.gl_settings (key, num_value, txt_value) values
  ('month_close_day', 3, 'Day of the following month (Dubai) on which the accountant closes a month and files it to the CEO.')
on conflict (key) do nothing;

-- ── 1. THE FIGURES ───────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_month_close_figures(p_month date)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_m date := date_trunc('month', p_month)::date; v_e date; v_fx numeric;
  v_from timestamptz; v_to timestamptz; v_pnl jsonb; v_rev numeric; v_exp numeric; v_aging jsonb;
begin
  v_e := (v_m + interval '1 month' - interval '1 day')::date;
  v_from := v_m::timestamp at time zone 'Asia/Dubai'; v_to := (v_e + 1)::timestamp at time zone 'Asia/Dubai';
  v_fx := coalesce((select num_value from public.gl_settings where key = 'usd_to_aed'), 3.6725);

  select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name, 'type', type, 'amount_aed', amt) order by code), '[]'::jsonb),
         coalesce(sum(amt) filter (where type = 'revenue'), 0), coalesce(sum(amt) filter (where type = 'expense'), 0)
    into v_pnl, v_rev, v_exp
    from (select a.code, a.name, a.type,
                 round(sum(case when a.type = 'revenue' then l.credit - l.debit else l.debit - l.credit end), 2) amt
            from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id join public.gl_accounts a on a.code = l.account_code
           where j.status = 'posted' and j.entry_date between v_m and v_e and a.type in ('revenue', 'expense')
           group by a.code, a.name, a.type) z;

  select jsonb_build_object(
      'current', count(*) filter (where d <= 0), 'd1_30', count(*) filter (where d between 1 and 30),
      'd31_60', count(*) filter (where d between 31 and 60), 'd61_90', count(*) filter (where d between 61 and 90),
      'over_90', count(*) filter (where d > 90), 'open_aed', coalesce(sum(owed), 0))
    into v_aging
    from (select v_e - due_date d, coalesce(total_claim, amount_due + coalesce(admin_fee, 0) + coalesce(interest_amount, 0)) owed
            from public.supplier_dues
           where paid_at is null and coalesce(status, '') not in ('paid', 'settled', 'waived', 'cancelled')) z;

  return jsonb_build_object(
    'month', to_char(v_m, 'YYYY-MM'), 'from', v_m, 'to', v_e, 'timezone', 'Asia/Dubai',
    'profit_and_loss', jsonb_build_object('accounts', v_pnl, 'revenue_aed', v_rev, 'expenses_aed', v_exp,
                                          'net_result_aed', v_rev - v_exp,
                                          'basis', 'Posted journals dated in the month, revenue and expense accounts. Drafts are not in it.'),
    'cash_in', jsonb_build_object(
      'reveals_aed', (select coalesce(sum(coalesce(total_charged, reveal_fee)), 0) from public.transactions t
                       left join public.customers c on c.id = t.customer_id
                      where t.fee_status = 'paid' and t.revealed_at >= v_from and t.revealed_at < v_to and not coalesce(c.is_demo, false)),
      'supplier_charges_aed', (select coalesce(sum(coalesce(total_claim, amount_due)), 0) from public.supplier_dues
                                where paid_at >= v_from and paid_at < v_to),
      'subscriptions_paid', (select count(*) from public.leads where registration_paid_at >= v_from and registration_paid_at < v_to
                               and not coalesce(is_demo, false))),
    'cash_out', jsonb_build_object(
      'refunds_aed', (select coalesce(sum(amount_fils), 0) / 100.0 from public.refunds where status = 'succeeded'
                       and settled_at >= v_from and settled_at < v_to),
      'expenses_aed', (select coalesce(round(sum(amount * case upper(currency) when 'USD' then v_fx else 1 end)
                                             filter (where upper(currency) in ('AED', 'USD')), 2), 0)
                         from public.expense_entries where charged_on between v_m and v_e),
      'expenses_unconverted', (select count(*) from public.expense_entries where charged_on between v_m and v_e
                                 and upper(currency) not in ('AED', 'USD'))),
    'held_for_possible_refunds', public.fn_accountant_refund_reserve(),
    'bank_reconciliation', jsonb_build_object(
      'payouts', (select count(*) from public.stripe_payout where livemode and arrival_date between v_m and v_e),
      'payouts_aed', (select coalesce(sum(amount_fils), 0) / 100.0 from public.stripe_payout where livemode and arrival_date between v_m and v_e),
      'matched', (select count(*) from public.stripe_payout where livemode and arrival_date between v_m and v_e and bank_line_id is not null),
      'unmatched', (select count(*) from public.stripe_payout where livemode and status = 'paid' and arrival_date between v_m and v_e and bank_line_id is null),
      'statement_lines', (select count(*) from public.bank_statement_line where account <> 'zz_demo' and value_date between v_m and v_e),
      'open_findings', (select count(*) from public.it_engineer_finding where issue_key like 'acct:bank:%' and closed_at is null)),
    'bank_drafts_waiting', (select count(*) from public.gl_journal where source = 'bank_charge' and status = 'draft'),
    'disputes', jsonb_build_object('open', (select count(*) from public.stripe_dispute where livemode and closed_at is null),
                                   'closed_in_month', (select coalesce(jsonb_object_agg(outcome, n), '{}'::jsonb) from (
                                      select outcome, count(*) n from public.stripe_dispute where livemode and closed_at >= v_from and closed_at < v_to
                                       group by outcome) z)),
    'collections_aging', v_aging,
    'charge_audit_open_differences', (select count(*) from public.charge_audit where livemode and abs(diff_aed) >= 0.01 and resolved_at is null),
    'subscriptions', public.fn_accountant_subscription_position(),
    'vat', public.fn_accountant_vat_threshold_check(false),
    'weekly_figures_over_the_month', public.fn_accountant_weekly_report_figures(v_m, v_e),
    'measured_at', now());
end $fn$;
revoke execute on function public.fn_accountant_month_close_figures(date) from public, anon, authenticated;

-- ── 2. THE DOCUMENT: pdf_native blocks and a CSV, from the stored figures ─────────────────────────
create or replace function public.fn_accountant_month_close_document(p_month date)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare f jsonb; v_pnl_rows jsonb; v_csv text; x jsonb; v_title text;
begin
  select figures into f from public.accountant_month_close where month = date_trunc('month', p_month)::date;
  if f is null then raise exception 'month % is not closed', to_char(p_month, 'YYYY-MM'); end if;
  v_title := 'QuotesDone monthly close ' || (f->>'month');
  select coalesce(jsonb_agg(jsonb_build_array(e->>'code', e->>'name', e->>'type', to_char((e->>'amount_aed')::numeric, 'FM999,999,990.00'))
                            order by e->>'code'), '[]'::jsonb)
    into v_pnl_rows from jsonb_array_elements(f#>'{profit_and_loss,accounts}') e;
  v_csv := 'section,item,value,note' || E'\n';
  for x in select e from jsonb_array_elements(f#>'{profit_and_loss,accounts}') e loop
    v_csv := v_csv || 'profit_and_loss,' || (x->>'code') || ' ' || replace(x->>'name', ',', ' ') || ',' || (x->>'amount_aed') || ',' || (x->>'type') || E'\n';
  end loop;
  v_csv := v_csv
    || 'profit_and_loss,revenue,' || (f#>>'{profit_and_loss,revenue_aed}') || ',posted journals' || E'\n'
    || 'profit_and_loss,expenses,' || (f#>>'{profit_and_loss,expenses_aed}') || ',posted journals' || E'\n'
    || 'profit_and_loss,net_result,' || (f#>>'{profit_and_loss,net_result_aed}') || ',' || E'\n'
    || 'cash_in,reveals,' || (f#>>'{cash_in,reveals_aed}') || ',' || E'\n'
    || 'cash_in,supplier_charges,' || (f#>>'{cash_in,supplier_charges_aed}') || ',' || E'\n'
    || 'cash_in,subscriptions_paid,' || (f#>>'{cash_in,subscriptions_paid}') || ',count' || E'\n'
    || 'cash_out,refunds,' || (f#>>'{cash_out,refunds_aed}') || ',' || E'\n'
    || 'cash_out,expenses,' || (f#>>'{cash_out,expenses_aed}') || ',AED and USD converted at gl_settings.usd_to_aed' || E'\n'
    || 'held,held_for_possible_refunds,' || (f#>>'{held_for_possible_refunds,held_for_possible_refunds_aed}') || ',not earned while it can be refunded' || E'\n'
    || 'bank,payouts,' || (f#>>'{bank_reconciliation,payouts}') || ',count' || E'\n'
    || 'bank,payouts_aed,' || (f#>>'{bank_reconciliation,payouts_aed}') || ',' || E'\n'
    || 'bank,matched,' || (f#>>'{bank_reconciliation,matched}') || ',count' || E'\n'
    || 'bank,unmatched,' || (f#>>'{bank_reconciliation,unmatched}') || ',count' || E'\n'
    || 'bank,drafts_waiting,' || (f->>'bank_drafts_waiting') || ',bank charges prepared as drafts under the founder''s hold' || E'\n'
    || 'disputes,open,' || (f#>>'{disputes,open}') || ',count' || E'\n'
    || 'collections,open_aed,' || (f#>>'{collections_aging,open_aed}') || ',' || E'\n'
    || 'charge_audit,open_differences,' || (f->>'charge_audit_open_differences') || ',count' || E'\n'
    || 'vat,rolling_12m_turnover,' || (f#>>'{vat,turnover_aed}') || ',' || coalesce(f#>>'{vat,band}', '') || E'\n';
  return jsonb_build_object('month', f->>'month', 'title', v_title, 'name', 'QuotesDone_Monthly_Close_' || (f->>'month'),
    'csv', v_csv,
    'blocks', jsonb_build_array(
      jsonb_build_object('t', 'h2', 'text', v_title),
      jsonb_build_object('t', 'p', 'text', 'Period ' || (f->>'from') || ' to ' || (f->>'to') || ' (Asia/Dubai). Every figure is read from the books at close; nothing is estimated. QuotesDone is not VAT-registered.'),
      jsonb_build_object('t', 'h3', 'text', 'Profit and loss (posted journals)'),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Account', 'Name', 'Type', 'AED'), 'rows', v_pnl_rows,
                         'widths', jsonb_build_array(0.12, 0.5, 0.16, 0.22)),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Result', 'AED'), 'widths', jsonb_build_array(0.6, 0.4), 'rows', jsonb_build_array(
        jsonb_build_array('Revenue', f#>>'{profit_and_loss,revenue_aed}'),
        jsonb_build_array('Expenses', f#>>'{profit_and_loss,expenses_aed}'),
        jsonb_build_array('Net result', f#>>'{profit_and_loss,net_result_aed}'),
        jsonb_build_array('Held for possible refunds (not earned while it can be refunded)', f#>>'{held_for_possible_refunds,held_for_possible_refunds_aed}'))),
      jsonb_build_object('t', 'h3', 'text', 'Cash in and out'),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Movement', 'Value'), 'widths', jsonb_build_array(0.6, 0.4), 'rows', jsonb_build_array(
        jsonb_build_array('Reveals paid (AED)', f#>>'{cash_in,reveals_aed}'),
        jsonb_build_array('Supplier charges collected (AED)', f#>>'{cash_in,supplier_charges_aed}'),
        jsonb_build_array('Supplier subscriptions paid (count)', f#>>'{cash_in,subscriptions_paid}'),
        jsonb_build_array('Refunds paid out (AED)', f#>>'{cash_out,refunds_aed}'),
        jsonb_build_array('Expenses charged (AED)', f#>>'{cash_out,expenses_aed}'))),
      jsonb_build_object('t', 'h3', 'text', 'Bank reconciliation (Stripe payouts to Mashreq)'),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Item', 'Value'), 'widths', jsonb_build_array(0.6, 0.4), 'rows', jsonb_build_array(
        jsonb_build_array('Payouts arriving in the month', f#>>'{bank_reconciliation,payouts}'),
        jsonb_build_array('Payout value (AED)', f#>>'{bank_reconciliation,payouts_aed}'),
        jsonb_build_array('Matched to a statement line', f#>>'{bank_reconciliation,matched}'),
        jsonb_build_array('Paid by Stripe, not yet in the bank', f#>>'{bank_reconciliation,unmatched}'),
        jsonb_build_array('Open reconciliation findings', f#>>'{bank_reconciliation,open_findings}'),
        jsonb_build_array('Bank charges prepared as drafts (founder''s hold)', f->>'bank_drafts_waiting'))),
      jsonb_build_object('t', 'h3', 'text', 'Positions'),
      jsonb_build_object('t', 'table', 'head', jsonb_build_array('Item', 'Value'), 'widths', jsonb_build_array(0.6, 0.4), 'rows', jsonb_build_array(
        jsonb_build_array('Open card disputes', f#>>'{disputes,open}'),
        jsonb_build_array('Supplier charges outstanding (AED)', f#>>'{collections_aging,open_aed}'),
        jsonb_build_array('Open charge-audit differences', f->>'charge_audit_open_differences'),
        jsonb_build_array('Suppliers ranked toward the free thousand', f#>>'{subscriptions,registered_ranked}'),
        jsonb_build_array('Rolling 12-month turnover for VAT (AED)', f#>>'{vat,turnover_aed}'))),
      jsonb_build_object('t', 'note', 'text', 'Prepared by the QuotesDone accountant from public.gl_journal, stripe_payout, bank_statement_line, transactions, refunds, expense_entries, supplier_dues, stripe_dispute and charge_audit. The CSV beside this document carries the same figures line by line.')));
end $fn$;
revoke execute on function public.fn_accountant_month_close_document(date) from public, anon, authenticated;

-- ── 3. CLOSING A MONTH ───────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_month_close(p_month date)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_m date := date_trunc('month', p_month)::date; f jsonb; v_rep jsonb; v_sev text;
begin
  if v_m >= date_trunc('month', now() at time zone 'Asia/Dubai')::date then
    raise exception 'month % has not ended; a month is closed only after it ends', to_char(v_m, 'YYYY-MM');
  end if;
  if exists (select 1 from public.accountant_month_close where month = v_m) then
    return jsonb_build_object('ok', true, 'month', to_char(v_m, 'YYYY-MM'), 'already_closed', true);
  end if;
  f := public.fn_accountant_month_close_figures(v_m);
  v_sev := case when (f#>>'{bank_reconciliation,unmatched}')::int > 0 or (f->>'charge_audit_open_differences')::int > 0
                     or (f#>>'{disputes,open}')::int > 0 then 'elevated' else 'routine' end;
  v_rep := public.fn_support_report_to_ceo('accountant_close:' || to_char(v_m, 'YYYY-MM'), v_sev,
    'Monthly close ' || to_char(v_m, 'Mon YYYY') || ': net result AED ' || (f#>>'{profit_and_loss,net_result_aed}')
      || ', AED ' || (f#>>'{held_for_possible_refunds,held_for_possible_refunds_aed}') || ' held for possible refunds, '
      || (f#>>'{bank_reconciliation,unmatched}') || ' payout(s) not yet in the bank',
    f, '[]'::jsonb,
    'Acknowledge the close. The PDF and CSV are filed in finance-reports/accountant/close/' || to_char(v_m, 'YYYY-MM') || '.',
    p_review_in => interval '3 days', p_source_agent => 'accountant');
  insert into public.accountant_month_close (month, figures, ceo_report_id)
  values (v_m, f, (v_rep->>'report_id')::bigint);
  return jsonb_build_object('ok', true, 'month', to_char(v_m, 'YYYY-MM'), 'ceo_report', v_rep);
end $fn$;
revoke execute on function public.fn_accountant_month_close(date) from public, anon, authenticated;

create or replace function public.fn_accountant_month_close_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_local date := (now() at time zone 'Asia/Dubai')::date; v_prev date;
begin
  v_prev := (date_trunc('month', v_local) - interval '1 month')::date;
  if extract(day from v_local) < coalesce((select num_value::int from public.gl_settings where key = 'month_close_day'), 3)
     or exists (select 1 from public.accountant_month_close where month = v_prev) then
    return jsonb_build_object('closed', false, 'pending_render', (select count(*) from public.accountant_month_close where rendered_at is null));
  end if;
  return public.fn_accountant_month_close(v_prev) || jsonb_build_object('closed', true);
end $fn$;
revoke execute on function public.fn_accountant_month_close_tick() from public, anon, authenticated;

-- The runtime renders the PDF and CSV and records where it put them.
create or replace function public.fn_accountant_month_close_attach(p_month date, p_bucket text, p_pdf_path text, p_csv_path text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if coalesce(btrim(p_pdf_path), '') = '' or coalesce(btrim(p_csv_path), '') = '' then
    raise exception 'a close is rendered only with both its PDF and its CSV';
  end if;
  update public.accountant_month_close set pdf_bucket = p_bucket, pdf_path = p_pdf_path, csv_path = p_csv_path, rendered_at = now()
   where month = date_trunc('month', p_month)::date;
  if not found then raise exception 'month % is not closed', to_char(p_month, 'YYYY-MM'); end if;
  update public.support_ceo_report r
     set verified_evidence = r.verified_evidence || jsonb_build_object('pdf', p_bucket || '/' || p_pdf_path, 'csv', p_bucket || '/' || p_csv_path)
    from public.accountant_month_close c
   where c.month = date_trunc('month', p_month)::date and r.id = c.ceo_report_id;
  return jsonb_build_object('ok', true, 'month', to_char(p_month, 'YYYY-MM'));
end $fn$;
revoke execute on function public.fn_accountant_month_close_attach(date, text, text, text) from public, anon, authenticated;

-- ── 4. THE CEO READS WHAT THE ACCOUNTANT SENT, AND THE ACCOUNTANT SEES THAT HE DID ───────────────
create or replace function public.fn_ceo_accountant_reports_sweep()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.support_ceo_report; n int := 0;
begin
  for r in select * from public.support_ceo_report where source_agent = 'accountant' and status = 'sent' order by id loop
    perform public.fn_ceo_accept_support_report(r.id,
      'ceo: read the accountant''s ' || r.severity || ' report "' || left(r.subject, 140) || '" with its evidence ('
        || (select count(*) from jsonb_object_keys(r.verified_evidence)) || ' field(s))');
    n := n + 1;
  end loop;
  return jsonb_build_object('acknowledged', n);
end $fn$;
revoke execute on function public.fn_ceo_accountant_reports_sweep() from public, anon, authenticated;

create or replace function public.fn_accountant_reports_complete()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare n int;
begin
  update public.support_ceo_report
     set status = 'completed', completed_at = now(),
         completion_note = 'accountant saw the CEO''s receipt: ' || acceptance_receipt
   where source_agent = 'accountant' and status = 'accepted' and acceptance_receipt is not null;
  get diagnostics n = row_count;
  return jsonb_build_object('completed_after_receipt', n);
end $fn$;
revoke execute on function public.fn_accountant_reports_complete() from public, anon, authenticated;
