-- Pure probe (no DDL of its own): run AFTER the file it proves, in the same transaction, or after apply.
-- Ends with raise exception, so nothing it writes survives (the CEO reports, the July close, the demo journal).
do $probe$
declare
  f jsonb; cp jsonb; vat jsonb; ct0 jsonb; ct1 jsonb; ue jsonb; rw jsonb; c13 jsonb; mc jsonb; d5 jsonb;
  g2 jsonb; g5 jsonb; g6 jsonb; g7 jsonb; tr jsonb; v_lock text := 'not refused'; v_j bigint; v_bud int; v_duties int; v_g4 boolean;
  v_aug_before int; v_aug_after int;
begin
  select count(*) into v_aug_before from public.accountant_month_close;
  f := public.fn_finance_forecast();
  cp := public.fn_accountant_cash_position(current_date, null);
  tr := public.fn_accountant_cash_truth_check();
  vat := public.fn_accountant_vat_threshold_check(false);
  ct0 := public.fn_accountant_ct_threshold_check(false);

  -- ZZ DEMO revenue of AED 850,000 dated today: the CT watch must report the 80% fraction.
  insert into public.gl_journal (entry_date, memo, source, status) values (current_date, 'ZZ DEMO probe revenue', 'probe', 'draft') returning id into v_j;
  insert into public.gl_journal_lines (journal_id, account_code, debit, credit) values (v_j, '1000', 850000, 0), (v_j, '4000', 0, 850000);
  update public.gl_journal set status = 'posted' where id = v_j;
  ct1 := public.fn_accountant_ct_threshold_check(true);

  ue := public.fn_accountant_unit_economics(date '2026-09-01');
  select count(*) into v_bud from public.budget_lines l join public.budgets b on b.id = l.budget_id where b.status = 'active';
  rw := public.fn_accountant_runway_figures(date '2026-09-01');
  c13 := public.fn_accountant_cash_13_weeks();

  -- the close for a past month with no close row, then a posting into it must be refused
  mc := public.fn_accountant_month_close(date '2026-07-01');
  begin
    insert into public.gl_journal (entry_date, memo, source, status) values (date '2026-07-15', 'ZZ DEMO late posting', 'probe', 'posted');
  exception when others then v_lock := sqlerrm; end;
  d5 := public.fn_accountant_close_by_day_5();

  g2 := public.fn_accountant_stripe_reconcile_duty();
  g5 := public.fn_accountant_reveal_invoice_filing_check();
  g6 := public.fn_accountant_refund_correctness_check();
  g7 := public.fn_accountant_stripe_email_setting_watch();
  select count(*) into v_duties from public.seat_duty where duty in ('accountant.cash_truth', 'accountant.ct_threshold', 'accountant.stripe_reconcile',
    'accountant.close_by_day_five', 'accountant.reveal_invoice_filing', 'accountant.refund_correctness', 'accountant.stripe_email_setting');
  v_g4 := pg_get_functiondef('public.fn_accountant_duties(jsonb)'::regprocedure) not like '%held'', ''for the marketing seat%';
  select count(*) into v_aug_after from public.accountant_month_close;

  raise exception 'PROBE forecast_cash=% cash_position=% truth_agree=% gl_minus_bank=% rev30=% reversals30=% | vat_turnover=% | ct_before=% ct_after_850k=% reported=% | ue_reveals=% ue_llm=% ue_missing=% | budget_lines=% runway_at_budget=% budget_spend=% weeks13=% c13_missing=% | july_close_ok=% lock="%" day5=% closes %->% | g2=% g5_incomplete=% g6=% g7_on=% g7_stale=% duties=% g4_stub_gone=%',
    f->'cash_now', cp#>'{cash_in_bank,aed}', tr->'agree', f->'gl_minus_bank_aed', f#>'{assumptions,revenue_run_rate_30d}', f#>'{assumptions,reversals_30d_not_carried_forward}',
    vat->'turnover_aed', ct0->'fraction', ct1->'fraction', ct1->'reported_to_ceo',
    ue->'reveals', ue->'llm_cost_aed', jsonb_array_length(ue->'missing'),
    v_bud, rw->'runway_months_at_budget', rw->'budgeted_spend_aed', jsonb_array_length(c13->'weeks'), c13->'missing',
    mc->'ok', left(v_lock, 60), d5->'closed_by_day_5', v_aug_before, v_aug_after,
    g2->'payouts_unmatched', g5->'incomplete', g6#>'{this_month,refunds}', g7->'on', g7->'stale', v_duties, v_g4;
end $probe$;
