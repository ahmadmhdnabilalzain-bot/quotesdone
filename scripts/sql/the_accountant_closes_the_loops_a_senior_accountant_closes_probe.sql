-- PROBE for the_accountant_closes_the_loops_a_senior_accountant_closes.sql (accountant, ledger 1003 stage 2).
-- Never applied: it always raises CHK<<...>>, so every row the seven duties write is rolled back. Run after the file is
-- applied, or concatenated after it in one transaction: node scripts/qsql.mjs <file + this probe>.
-- It runs every duty against production as it stands and reads what each wrote; then it proves the VAT duty's
-- thresholds on a ZZ DEMO posted revenue journal of AED 400,000 (rolled back with everything else): status 'mandatory'
-- with an FTA date. It asserts nothing reached the founder (notifications to admin/founder, founder_alerts).
do $probe$
declare n0 bigint := (select count(*) from public.notifications where to_role in ('admin', 'founder'));
  fa0 bigint := (select count(*) from public.founder_alerts);
  c0 bigint := (select coalesce(max(id), 0) from public.support_ceo_report);
  r jsonb := '{}'::jsonb; v_fail text := ''; v_j bigint; v_rev text;
begin
  begin r := r || jsonb_build_object('C11', public.fn_accountant_receipt_intake_duty()); exception when others then r := r || jsonb_build_object('C11', jsonb_build_object('raised', sqlerrm)); end;
  r := r || jsonb_build_object('C12', public.fn_accountant_charge_recovery_duty());
  r := r || jsonb_build_object('C13_forecast', public.fn_accountant_cash_forecast_week());
  r := r || jsonb_build_object('C13_variance', public.fn_accountant_budget_variance());
  r := r || jsonb_build_object('C14', public.fn_accountant_vat_threshold());
  r := r || jsonb_build_object('C15', public.fn_accountant_finance_week());
  r := r || jsonb_build_object('C16', public.fn_accountant_year_end_duty());

  -- the VAT duty on AED 400,000 of ZZ DEMO revenue posted today
  select code into v_rev from public.gl_accounts where type = 'revenue' and is_active order by code limit 1;
  insert into public.gl_journal (entry_date, memo, source, source_ref, status, created_by)
  values ((now() at time zone 'Asia/Dubai')::date, 'ZZ DEMO VAT threshold probe', 'manual', 'zz_demo_vat_probe', 'draft', 'probe') returning id into v_j;
  insert into public.gl_journal_lines (journal_id, line_no, account_code, debit, credit, memo) values
    (v_j, 1, (select code from public.gl_accounts where type = 'asset' and is_active order by code limit 1), 400000, 0, 'ZZ DEMO'),
    (v_j, 2, v_rev, 0, 400000, 'ZZ DEMO');
  update public.gl_journal set status = 'posted', posted_at = now() where id = v_j;
  r := r || jsonb_build_object('C14_at_400k', public.fn_accountant_vat_threshold(((now() at time zone 'Asia/Dubai')::date + 1)));

  r := r || jsonb_build_object(
    'ceo_reports_added', (select coalesce(jsonb_agg(idempotency_key order by id), '[]') from public.support_ceo_report where id > c0),
    'forecast_rows', (select count(*) from public.accountant_cash_forecast_week),
    'vat_rows', (select count(*) from public.accountant_vat_threshold_check),
    'duties_registered', (select count(*) from public.seat_duty where owner_seat = 'accountant' and routine in ('fn_accountant_receipt_intake_duty',
       'fn_accountant_charge_recovery_duty', 'fn_accountant_cash_forecast_week', 'fn_accountant_budget_variance', 'fn_accountant_vat_threshold',
       'fn_accountant_finance_week', 'fn_accountant_year_end_duty')),
    'founder_notifications_added', (select count(*) from public.notifications where to_role in ('admin', 'founder')) - n0,
    'founder_alerts_added', (select count(*) from public.founder_alerts) - fa0);
  if (r->>'founder_notifications_added')::int <> 0 or (r->>'founder_alerts_added')::int <> 0 then v_fail := v_fail || 'reached the founder; '; end if;
  if (r->>'duties_registered')::int <> 7 then v_fail := v_fail || 'a duty is not registered; '; end if;
  if (r->>'forecast_rows')::int = 0 or (r->>'vat_rows')::int = 0 then v_fail := v_fail || 'a row is missing; '; end if;
  if r->'C14_at_400k'->>'status' <> 'mandatory' or r->'C14_at_400k'->>'register_by' is null then v_fail := v_fail || 'the VAT threshold did not trip at 400k; '; end if;
  if not (r->'ceo_reports_added') ? ('accountant.finance_week:' || to_char(date_trunc('week', now() at time zone 'Asia/Dubai'), 'IYYY-"W"IW')) then
    v_fail := v_fail || 'no finance week report; '; end if;
  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK ' else 'PROBE FAILED: ' || v_fail end || r::text;
end $probe$;
