-- PROBE: A BANK LINE IS CLASSIFIED BY ITS STRUCTURED REFERENCE CODE (5 Oct 2026; seat: accountant).
--
-- A pure probe: it always ends in raise exception 'CHK<<...>>', so every row it writes rolls back. Run it after
-- a_bank_line_is_classified_by_its_structured_reference_code.sql is applied, or after it in the same rolled-back
-- transaction. It runs the real fn_accountant_cost_booking_tick() against the real September Mashreq lines and
-- proves: the fee (2268) and its VAT (2267) are booked to 6300, the interest (2269) to 7000, the two card
-- purchases (2265, 2266) stay unclassified and unbooked, and the GL-minus-bank gap falls to exactly their sum,
-- 316.06. Nothing it writes survives; nobody is contacted (the tick sends nothing; duty findings roll back).
--
--   node scripts/apply_sql.mjs scripts/sql/a_bank_line_is_classified_by_its_structured_reference_code_probe.sql --apply

do $probe$
declare
  v_bad text[] := '{}'; v_gap0 numeric; v_gap1 numeric; v_tick jsonb; n int;
begin
  v_gap0 := (public.fn_finance_forecast()->>'gl_minus_bank_aed')::numeric;
  v_tick := public.fn_accountant_cost_booking_tick();
  v_gap1 := (public.fn_finance_forecast()->>'gl_minus_bank_aed')::numeric;

  select count(*) into n from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id
   where g.source = 'bank_charge' and g.source_ref in ('2267', '2268') and g.status = 'posted'
     and jl.account_code = '6300' and jl.debit in (9.95, 199.00);
  if n <> 2 then v_bad := v_bad || ('fee and VAT not both posted to 6300: ' || n); end if;

  select count(*) into n from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id
   where g.source = 'bank_interest' and g.source_ref = '2269' and g.status = 'posted'
     and jl.account_code = '7000' and jl.credit = 1.30;
  if n <> 1 then v_bad := v_bad || ('interest not posted to 7000: ' || n); end if;

  select count(*) into n from public.bank_statement_line where id in (2265, 2266) and kind is null;
  if n <> 2 then v_bad := v_bad || ('a card purchase was classified: ' || (2 - n)); end if;
  select count(*) into n from public.gl_journal where source_ref in ('2265', '2266') and source like 'bank%';
  if n <> 0 then v_bad := v_bad || ('a card purchase was booked: ' || n); end if;

  if v_gap1 is distinct from 316.06 then v_bad := v_bad || ('gap after is ' || coalesce(v_gap1::text, 'null') || ', not 316.06'); end if;

  raise exception 'CHK<<%>>', jsonb_build_object(
    'verdict', case when cardinality(v_bad) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(v_bad, '; ') end,
    'gap_before', v_gap0, 'gap_after', v_gap1,
    'classified', v_tick->'classified_by_reference_code', 'bank_charges', v_tick->'bank_charges'->'posted',
    'bank_credits', v_tick->'bank_credits'->'posted');
end $probe$;
