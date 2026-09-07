-- THE CEO HOLDS A TARGET, A DECISION REGISTER AND AN AUTHORITY
--
-- Founder, 7 September 2026: "the CEO we built today remains", and then: build it fully.
--
-- What existed after this morning was the CEO's MACHINERY -- company_charter, target_contract,
-- target_driver, target_verdict, fn_target_baseline, fn_target_feasibility -- and a position
-- document. What did NOT exist was the content: not one target contract, no decision register, no
-- authority tiers, no budget, no evidence requirement and no way to ask the seat where it stands.
-- Machinery with no content is the pattern this estate keeps producing, and it is what this file
-- closes.
--
-- IT IS BUILT FOR THE COMPANY THAT EXISTS, not the one that was deleted this afternoon. There are
-- two seats and no departments, so nothing here cascades to a department, opens a task, or travels
-- a manager chain. The CEO decides, records the decision with its evidence, and reports.

-- ---------------------------------------------------------------------------------------------
-- 1. THE TARGET, WITH A BASELINE THAT IS MEASURED AND A DRIVER MODEL THAT ADMITS WHAT IT GUESSES
-- ---------------------------------------------------------------------------------------------
-- The baseline is not an estimate. Measured 7 Sep 2026: public.transactions holds 0 rows,
-- reveal_invoices 0, inquiries 0. Revenue to date is AED 0 and the state is 'measured', not
-- 'unknown' -- there is an instrument, it reads zero, and that is a fact rather than a gap.
insert into public.target_contract (
  contract_key, version, status, objective, business_reason, priority, accountable_owner,
  metric_definition, metric_unit, metric_population, authoritative_source, measure_sql,
  baseline_value, baseline_state, baseline_at, baseline_note,
  desired_value, desired_basis, deadline, measurement_cadence,
  guardrails, assumptions, confidence_note, escalation_threshold,
  success_definition, evidence_required, created_by)
values (
  'AED_1M_BY_2027_08_31', 1, 'active',
  'Reach AED 1,000,000 of cumulative reveal-fee revenue by 31 August 2027.',
  'It is the founder''s stated target for the company and the only number the whole build is aimed at.',
  1, 'ceo',
  'Cumulative sum of transactions.reveal_fee for transactions whose fee_status records the fee as collected, in AED.',
  'AED', 'Every reveal transaction in public.transactions since the platform opened.',
  'public.transactions -- the row Stripe writes when a buyer pays to reveal a supplier.',
  $q$select coalesce(sum(reveal_fee), 0) from public.transactions where fee_status in ('paid','collected','succeeded')$q$,
  0, 'measured', now(),
  'Measured 7 Sep 2026: transactions 0 rows, reveal_invoices 0 rows, inquiries 0. The instrument exists and reads zero. This is a measured zero, not an unknown.',
  1000000, 'cumulative', date '2027-08-31', 'weekly',
  jsonb_build_array(
    'The reveal fee is 3% and is paid by the buyer. It does not move to hit this number.',
    'Suppliers pay no commission, ever.',
    'No supplier is invited beyond the channel volumes the founder set: 10 supplier invitations a day in month one, +5 a day each month after.',
    'Every refund is the founder''s decision alone.'),
  jsonb_build_array(
    'A category opens to buyers only once 10 verified suppliers sit in it.',
    'The first 1,000 suppliers never pay the annual fee, so supplier revenue contributes nothing to this target before 1 Aug 2027.'),
  'Confidence is LOW and stated as such: every conversion rate below this line is not_instrumented, because the funnel has never carried a real transaction.',
  'Any week in which the required run rate rises above twice the highest run rate ever measured.',
  'Cumulative collected reveal fees reach AED 1,000,000 on or before 31 August 2027, read from public.transactions and reconciled against Stripe.',
  'The measure_sql result, the Stripe payout reconciliation for the same period, and the reveal-invoice count. All three must agree.',
  'ceo')
on conflict (contract_key, version) do nothing;

-- THE DRIVER MODEL. Every rate carries where it came from. Not one of them is measured, because no
-- inquiry has ever been posted and no reveal has ever been paid -- so fn_target_feasibility must
-- return a verdict that says the model rests on assumptions, not on evidence. A driver model that
-- launders an assumption as a rate is how a target becomes a wish.
insert into public.target_driver (contract_id, stage_order, stage_key, stage_label, from_stage_key,
                                  rate, rate_source, rate_evidence, lag_days, note)
select c.id, v.ord, v.k, v.lbl, v.from_k, v.rate, v.src, v.ev, v.lag, v.note
  from public.target_contract c
  cross join (values
    (1, 'supplier_invited',   'Suppliers invited',                 null,                 1.00, 'not_instrumented',
        'The channel policy sets the volume; it is not a conversion rate.', 0,
        'Top of funnel. Capped by the founder''s own volumes, not by demand.'),
    (2, 'supplier_registered','Suppliers who register',            'supplier_invited',   0.00, 'not_instrumented',
        'Measured 7 Sep 2026: 110 invitations delivered, 0 registrations. A zero here is a real reading and it is the binding stage.', 7,
        'This is where the funnel currently stops dead.'),
    (3, 'category_open',      'Categories reaching 10 verified suppliers', 'supplier_registered', 0.00, 'not_instrumented',
        'No category has ever opened.', 14,
        'A category opens to buyers at 10 verified suppliers. None has reached it.'),
    (4, 'inquiry_posted',     'Buyer requests posted',             'category_open',      0.00, 'not_instrumented',
        'inquiries holds 0 rows.', 0,
        'No buyer demand has ever been measured, only assumed.'),
    (5, 'quotes_returned',    'Requests that receive quotes',      'inquiry_posted',     0.00, 'not_instrumented',
        'No request has ever been quoted.', 3, null),
    (6, 'reveal_paid',        'Quoted requests where the buyer pays to reveal', 'quotes_returned', 0.00, 'not_instrumented',
        'transactions holds 0 rows.', 1,
        'The only stage that produces revenue.')
  ) as v(ord, k, lbl, from_k, rate, src, ev, lag, note)
 where c.contract_key = 'AED_1M_BY_2027_08_31' and c.version = 1
   and not exists (select 1 from public.target_driver d where d.contract_id = c.id);
