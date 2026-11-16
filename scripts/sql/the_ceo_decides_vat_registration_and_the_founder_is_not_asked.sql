-- THE CEO DECIDES VAT REGISTRATION; THE FOUNDER IS NOT ASKED. Seat: accountant (built by it_engineer, agent L3_IT, 16 Nov 2026,
-- founder ledger 1557).
-- THE RULINGS: 9 (9 Sep 2026) "the threshold ... that is when he [the accountant] notifies the CEO that we are supposed to
-- register"; 1696 (15 Nov) "CEO is having full authority ... He doesnt rely on me in anything"; 1710 "don't rely on me".
-- 1687 (13 Nov) is about the reveal fee being computed WITHOUT VAT ("VAT is for the suppliers ... we're not collecting
-- VAT"); it routes no VAT decision to him, and no ruling in the ledger does: the line "THE FOUNDER DECIDES REGISTRATION"
-- (14 Sep) was this routine's own comment, not his word.
-- BEFORE: at the configured fraction (decision_policy vat_threshold_founder_decision_fraction) fn_accountant_vat_threshold_check
-- asked customer_support to deliver "VAT registration: your decision is needed" to the founder (kind finance_alert) as well as
-- reporting to the CEO. NOW: no founder delivery request is made at all, so none can be left unconfirmed; the CEO's report
-- carries the decision instead (severity 'elevated' from that fraction, as before, and the requested action asks the CEO to
-- decide whether QuotesDone registers now or at the threshold). Production's body otherwise (md5 before the edit
-- a0cd056a4af6a54d1c7999c24645fd87).
-- founder_mail_policy is NOT changed: kind finance_alert is also how fn_accountant_escalates_payment_exception tells him a reveal
-- payment did not reconcile, the money-mismatch summary his ruling 183 keeps with him.

CREATE OR REPLACE FUNCTION public.fn_accountant_vat_threshold_check(p_notify boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_turn numeric; v_pos jsonb; v_band text; v_key text; v_rpt jsonb;
  v_m3 numeric; v_runrate numeric; v_since date; v_frac numeric; v_dec numeric;
begin
  v_since := (current_date - interval '12 months')::date;

  -- Taxable supplies = what the revenue accounts actually carry, posted only. Draft and reversed
  -- journals are not turnover.
  -- 28 Sep 2026: through gl_revenue_lines_measured, so a posted reversal of a VOID original (journal 821 of 690)
  -- no longer reads as AED -250 of turnover.
  select coalesce(sum(revenue_aed), 0) into v_turn
    from public.gl_revenue_lines_measured
   where entry_date >= v_since;

  v_pos  := public.fn_vat_threshold_position(v_turn);
  v_band := v_pos->>'band';

  -- The forecast limb, reported and never decided: the last 3 months annualised.
  select coalesce(sum(revenue_aed), 0) into v_m3
    from public.gl_revenue_lines_measured
   where entry_date >= (current_date - interval '3 months')::date;
  v_runrate := round(v_m3 * 4, 2);

  v_frac := public.fn_vat_threshold_fraction_reached(v_turn);
  v_pos := v_pos || jsonb_build_object('fraction_reached', v_frac);

  if v_frac is null or not p_notify then
    return v_pos || jsonb_build_object('reported_to_ceo', false,
      'window_from', v_since, 'run_rate_annualised_aed', v_runrate,
      'run_rate_note', 'The preceding-12-months test is decided above. This annualised figure is the forward-looking limb of the UAE rule and is INFORMATION for the CEO and the founder, not a determination — a projection is a judgement about the future, not a measurement.');
  end if;

  -- One report per configured fraction per month. The tick runs every 15 minutes; without this the
  -- CEO would receive the same finding ninety-six times a day and would stop reading it.
  v_key := 'vat_threshold:' || v_frac || ':' || to_char(current_date, 'YYYY-MM');

  -- 16 Nov 2026 (ledger 1557): THE CEO DECIDES REGISTRATION (rulings 9, 1696, 1710). The founder delivery request that stood
  -- here ("VAT registration: your decision is needed", kind finance_alert) is gone; the fraction still raises the CEO's report.
  select (value #>> '{}')::numeric into v_dec from public.decision_policy where key = 'vat_threshold_founder_decision_fraction';

  v_rpt := public.fn_support_report_to_ceo(
    p_idempotency_key => v_key,
    p_severity        => case when v_band = 'crossed' then 'serious' when v_frac >= coalesce(v_dec, 1) then 'elevated' else 'routine' end,
    p_subject         => case when v_band = 'crossed'
                              then 'VAT registration is now required: rolling 12-month turnover AED '
                                   || (v_pos->>'turnover_aed') || ' has passed AED ' || (v_pos->>'threshold_aed')
                              else 'VAT registration threshold approaching: AED ' || (v_pos->>'turnover_aed')
                                   || ' of AED ' || (v_pos->>'threshold_aed') || ' (' || (v_pos->>'pct_of_threshold') || '%)' end,
    p_evidence        => v_pos || jsonb_build_object(
                           'window_from', v_since, 'window_to', current_date,
                           'run_rate_annualised_aed', v_runrate,
                           'basis', 'Sum of posted journal lines on accounts 4xxx over the preceding 12 months. Draft and reversed journals excluded.'),
    p_attempted       => '[]'::jsonb,
    p_requested       => case when v_band = 'crossed'
      then 'Registration for UAE VAT is required on the preceding-12-months test. Decide who files and by when, and instruct the accountant. Note the accountant holds no filing deadline or penalty figure by design — those come from the FTA, not from this system.'
      when v_frac >= coalesce(v_dec, 1)
      then 'Decide whether QuotesDone registers for UAE VAT now or at the threshold, give the reason, and instruct the accountant. Taxable turnover over the last 12 months is AED '
           || (v_pos->>'turnover_aed') || ' (' || (v_pos->>'pct_of_threshold') || '% of the threshold); the annualised run rate of the last three months is AED ' || v_runrate || '.'
      else 'No action is required yet. Prepare for registration so that crossing the threshold is a scheduled filing rather than a discovery. The accountant will report again if the band changes.' end,
    p_review_in       => interval '30 days',
    p_source_agent    => 'accountant');

  return v_pos || jsonb_build_object(
    'window_from', v_since, 'run_rate_annualised_aed', v_runrate,
    'reported_to_ceo', coalesce((v_rpt->>'ok')::boolean, false),
    'ceo_report', v_rpt);
end $function$
;
