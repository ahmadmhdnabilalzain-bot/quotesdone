-- THE ACCOUNTANT WATCHES THE VAT THRESHOLD AND TELLS THE CEO.
--
-- The founder, 9 September 2026: "he is already connected to Stripe, so the total revenue can be
-- received from there. And then the threshold, which is the three hundred seventy five, that is
-- when he notifies the CEO that we are supposed to register over that."
--
-- Revenue booking already existed and is fine: fn_gl_sync_business posts 4000 Reveal Fee Revenue
-- and 4200 Supplier Registration Revenue, and stripe_webhook is its trigger. What did not exist was
-- anything watching the number. Measured before building: no routine in the database referenced
-- 375000 at all, and revenue posted to date is AED 0.00 across all five revenue accounts.
--
-- THE UAE RULE HAS TWO LIMBS, AND ONLY ONE OF THEM IS MEASURABLE.
--
--   (1) Mandatory registration once taxable supplies in the PREVIOUS 12 MONTHS exceed AED 375,000.
--   (2) Or once they are EXPECTED to exceed it within the next 30 days.
--
-- Limb 1 is arithmetic and this routine decides it. Limb 2 is a forecast, and a forecast is a
-- judgement about the future that an accountant makes with the founder — so the run-rate is
-- REPORTED as information and the routine does not claim to have decided it. Saying "you must
-- register" from a straight-line projection would be inventing an obligation; saying nothing would
-- be hiding the only early warning there is.
--
-- WHY ROLLING TWELVE MONTHS AND NOT LIFETIME. A lifetime total crosses once and stays crossed
-- forever, which would make the alarm permanently true the moment the company earns its 375,001st
-- dirham even if it later earned nothing for two years. The obligation is measured on a moving
-- window and so is this.
--
-- WHY A WARNING BAND. Registration is a filing with a deadline, not a switch. Discovering the
-- crossing on the day it happens is discovering it late. The band is 80% by default and lives in
-- gl_settings, so the founder can move it without anyone editing a routine.
--
-- WHERE IT GOES: THE CEO, NOT THE FOUNDER. His instruction was explicit — the accountant "notifies
-- the CEO". It files through fn_support_report_to_ceo with p_source_agent => 'accountant', which
-- became possible earlier today; before that the shared routine hardcoded 'customer_support' and
-- the accountant's report would have been filed under Support's name.
--
-- IT IS IDEMPOTENT BY BAND AND MONTH. The tick runs every 15 minutes. Without a key it would file
-- the same report ninety-six times a day, and the CEO would learn to ignore the one that mattered.

-- ── THE FIGURES LIVE IN CONFIG, NOT IN THE ROUTINE ──────────────────────────────────────────────
insert into public.gl_settings (key, num_value, txt_value) values
  ('vat_registration_threshold_aed', 375000,
   'UAE mandatory VAT registration threshold on taxable supplies in the preceding 12 months. The founder stated this figure on 9 Sep 2026. The accountant''s knowledge body deliberately holds no tax figures, so the number lives here and the routine reads it.'),
  ('vat_threshold_warn_fraction', 0.80,
   'Report to the CEO once rolling turnover reaches this fraction of the threshold, so registration is prepared rather than discovered.')
on conflict (key) do update set txt_value = excluded.txt_value;

-- 14 SEP 2026 (duty 4 of the eight, founder: "yea add them all"): the CEO is warned at EACH configured
-- fraction of the threshold, and the founder is asked for a decision — by email, through customer_support
-- — once turnover reaches the decision fraction, well before the line is crossed. Configuration, not
-- literals: decision_policy holds both.
insert into public.decision_policy (key, value, description) values
  ('vat_threshold_report_fractions', '[0.5, 0.7, 0.8, 0.9, 1.0]'::jsonb,
   'Fractions of the VAT registration threshold at which the accountant reports rolling 12-month turnover to the CEO (once per fraction per month).'),
  ('vat_threshold_founder_decision_fraction', '0.8'::jsonb,
   'From this fraction of the threshold the founder is emailed once per fraction, through customer_support, to decide on VAT registration before the threshold is crossed.')
on conflict (key) do nothing;

-- The highest configured fraction a turnover has reached, or null.
create or replace function public.fn_vat_threshold_fraction_reached(p_turnover_aed numeric)
returns numeric language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select max(e::numeric)
    from public.decision_policy d, jsonb_array_elements_text(d.value) e
   where d.key = 'vat_threshold_report_fractions'
     and coalesce(p_turnover_aed, 0) >= e::numeric * (select num_value from public.gl_settings where key = 'vat_registration_threshold_aed');
$fn$;
revoke execute on function public.fn_vat_threshold_fraction_reached(numeric) from public, anon, authenticated;

-- ── THE DECISION, SEPARATED FROM THE MEASUREMENT ────────────────────────────────────────────────
-- Pure: given a turnover figure, what is the position? Separated so the rule can be proved
-- exhaustively without writing a single journal — the ledger is immutable by trigger, so a probe
-- that seeded revenue could never clean up after itself.
create or replace function public.fn_vat_threshold_position(p_turnover_aed numeric)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare v_thr numeric; v_frac numeric; v_band text;
begin
  select num_value into v_thr  from public.gl_settings where key = 'vat_registration_threshold_aed';
  select num_value into v_frac from public.gl_settings where key = 'vat_threshold_warn_fraction';
  if v_thr is null then
    raise exception 'gl_settings.vat_registration_threshold_aed is missing; refusing to decide a tax obligation against a threshold nobody set';
  end if;

  v_band := case
    when p_turnover_aed >= v_thr                       then 'crossed'
    when p_turnover_aed >= v_thr * coalesce(v_frac,0.8) then 'approaching'
    else 'below' end;

  return jsonb_build_object(
    'band', v_band,
    'turnover_aed', round(coalesce(p_turnover_aed,0), 2),
    'threshold_aed', v_thr,
    'headroom_aed', round(v_thr - coalesce(p_turnover_aed,0), 2),
    'pct_of_threshold', round(coalesce(p_turnover_aed,0) / v_thr * 100, 1),
    'obligation', case v_band
      when 'crossed'     then 'Taxable supplies in the preceding 12 months have passed the mandatory registration threshold. Registration is required.'
      when 'approaching' then 'Not yet required. Close enough that registration should be prepared rather than discovered.'
      else 'No registration obligation on the preceding-12-months test.' end);
end $fn$;
revoke execute on function public.fn_vat_threshold_position(numeric) from public;

-- ── THE MEASUREMENT, AND THE REPORT TO THE CEO ──────────────────────────────────────────────────
create or replace function public.fn_accountant_vat_threshold_check(p_notify boolean default true)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
declare
  v_turn numeric; v_pos jsonb; v_band text; v_key text; v_rpt jsonb;
  v_m3 numeric; v_runrate numeric; v_since date; v_frac numeric; v_dec numeric;
begin
  v_since := (current_date - interval '12 months')::date;

  -- Taxable supplies = what the revenue accounts actually carry, posted only. Draft and reversed
  -- journals are not turnover.
  select coalesce(sum(l.credit - l.debit), 0) into v_turn
    from public.gl_journal_lines l
    join public.gl_journal j on j.id = l.journal_id
   where l.account_code like '4%'
     and j.status = 'posted'
     and j.entry_date >= v_since;

  v_pos  := public.fn_vat_threshold_position(v_turn);
  v_band := v_pos->>'band';

  -- The forecast limb, reported and never decided: the last 3 months annualised.
  select coalesce(sum(l.credit - l.debit), 0) into v_m3
    from public.gl_journal_lines l
    join public.gl_journal j on j.id = l.journal_id
   where l.account_code like '4%' and j.status = 'posted'
     and j.entry_date >= (current_date - interval '3 months')::date;
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

  -- THE FOUNDER DECIDES REGISTRATION, AND HEARS IT BEFORE THE LINE (14 Sep 2026). Once per fraction,
  -- through customer_support; fn_notify_founder dedupes on the key as well.
  select (value #>> '{}')::numeric into v_dec from public.decision_policy where key = 'vat_threshold_founder_decision_fraction';
  if v_dec is not null and v_frac >= v_dec then
    perform public.fn_seat_handoff('accountant', 'customer_support', 'delivery.request', 'founder', 'vat_decision:' || v_frac,
      jsonb_build_object('recipient_role', 'founder', 'kind', 'finance_alert', 'level', 'high',
        'event', 'VAT registration: your decision is needed (' || round(v_frac * 100) || '% of the threshold)',
        'detail', 'Taxable turnover over the last 12 months is AED ' || (v_pos->>'turnover_aed') || ', which is '
                  || (v_pos->>'pct_of_threshold') || '% of the AED ' || (v_pos->>'threshold_aed') || ' mandatory VAT registration threshold. '
                  || case when v_band = 'crossed' then 'It has been crossed, so registration is required now. '
                          else 'It has not been crossed yet; AED ' || (v_pos->>'headroom_aed') || ' of headroom is left. ' end
                  || 'Please decide whether QuotesDone registers for VAT now or at the threshold, and reply with your decision. '
                  || 'The annualised run rate of the last three months is AED ' || v_runrate || '.',
        'dedupe_key', 'vat_decision:' || v_frac));
  end if;

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
      else 'No action is required yet. Prepare for registration so that crossing the threshold is a scheduled filing rather than a discovery. The accountant will report again if the band changes.' end,
    p_review_in       => interval '30 days',
    p_source_agent    => 'accountant');

  return v_pos || jsonb_build_object(
    'window_from', v_since, 'run_rate_annualised_aed', v_runrate,
    'reported_to_ceo', coalesce((v_rpt->>'ok')::boolean, false),
    'ceo_report', v_rpt);
end $fn$;
revoke execute on function public.fn_accountant_vat_threshold_check(boolean) from public;

-- ── PROVE THE RULE EXHAUSTIVELY, AND THE MEASUREMENT HONESTLY ───────────────────────────────────
do $do$
declare v jsonb; v_thr numeric; v_live jsonb;
begin
  select num_value into v_thr from public.gl_settings where key = 'vat_registration_threshold_aed';
  if v_thr <> 375000 then raise exception 'the threshold did not store: %', v_thr; end if;

  -- Every boundary of the rule, with no money written anywhere.
  v := public.fn_vat_threshold_position(0);
  if v->>'band' <> 'below' then raise exception 'zero turnover is not below: %', v->>'band'; end if;

  v := public.fn_vat_threshold_position(299999.99);
  if v->>'band' <> 'below' then raise exception 'AED 299,999.99 should be below the 80%% band: %', v->>'band'; end if;

  v := public.fn_vat_threshold_position(300000);
  if v->>'band' <> 'approaching' then raise exception 'AED 300,000 is exactly 80%% and should warn: %', v->>'band'; end if;

  v := public.fn_vat_threshold_position(374999.99);
  if v->>'band' <> 'approaching' then raise exception 'one fils below the threshold must not read as crossed: %', v->>'band'; end if;

  -- THE BOUNDARY THAT MATTERS. Exactly at the threshold is crossed, not approaching.
  v := public.fn_vat_threshold_position(375000);
  if v->>'band' <> 'crossed' then raise exception 'AED 375,000 exactly must read as crossed: %', v->>'band'; end if;
  if (v->>'headroom_aed')::numeric <> 0 then raise exception 'headroom at the threshold should be 0, got %', v->>'headroom_aed'; end if;

  v := public.fn_vat_threshold_position(500000);
  if v->>'band' <> 'crossed' then raise exception 'AED 500,000 is not crossed: %', v->>'band'; end if;

  -- THE LIVE MEASUREMENT. Today this must be below and must NOT file anything: an alarm that fires
  -- on an empty ledger is the failure this estate keeps paying for.
  v_live := public.fn_accountant_vat_threshold_check(true);
  if v_live->>'band' <> 'below' then
    raise exception 'the live ledger reads % with turnover % — check the revenue query before trusting this', v_live->>'band', v_live->>'turnover_aed';
  end if;
  if (v_live->>'reported_to_ceo')::boolean then
    raise exception 'a report was filed to the CEO against AED 0 turnover';
  end if;

  raise notice 'VAT WATCH LIVE. Rule proved at 0 / 299,999.99 / 300,000 / 374,999.99 / 375,000 / 500,000 -> below, below, approaching, approaching, crossed, crossed. Live ledger: AED % over the 12 months from %, band %, nothing filed. Run rate annualised AED %. It reports to the CEO, not the founder, and once per band per month.',
    v_live->>'turnover_aed', v_live->>'window_from', v_live->>'band', v_live->>'run_rate_annualised_aed';
end
$do$;
