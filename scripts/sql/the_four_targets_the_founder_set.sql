-- THE FOUR TARGETS THE FOUNDER SET, AND THE ONE DEADLINE THEY ALL SHARE
--
-- Founder, 7 September 2026, in his words:
--
--   "now the targets for the CEO:
--    1 million AED revenue
--    1000 suppliers to be registered
--    1000 customer to be registered.
--    2000 followers on social media platforms in total (IG, FB)
--    deadline is 1 oct 2027"
--
-- Four contracts, one deadline. The revenue contract already existed with a 31 August 2027 deadline;
-- his is 1 October 2027, so that one is corrected rather than duplicated.
--
-- EVERY BASELINE HERE IS MEASURED, NOT ESTIMATED, and three of the four read zero. A measured zero
-- and an unknown are different things: there is an instrument, it works, and the answer is none yet.
-- The fourth -- social followers -- has no instrument at all and says so; inventing a follower count
-- would be worse than admitting the gap, because the first weekly verdict would then measure
-- progress against a number nobody ever counted.

-- ---------------------------------------------------------------------------------------------
-- 1. THE DEADLINE HE SET
-- ---------------------------------------------------------------------------------------------
update public.target_contract
   set deadline = date '2027-10-01'
 where contract_key = 'AED_1M_BY_2027_08_31'
   and deadline is distinct from date '2027-10-01';

-- ---------------------------------------------------------------------------------------------
-- 2. THE THREE THAT DID NOT EXIST YET
-- ---------------------------------------------------------------------------------------------
insert into public.target_contract (
  contract_key, version, status, objective, business_reason, priority, accountable_owner,
  metric_definition, metric_unit, metric_population, authoritative_source, measure_sql,
  baseline_value, baseline_state, baseline_at, baseline_note,
  desired_value, desired_basis, deadline, measurement_cadence,
  guardrails, assumptions, confidence_note, escalation_threshold,
  success_definition, evidence_required, created_by)
values

-- SUPPLIERS -----------------------------------------------------------------------------------
-- "Registered" is the founder's word and it means a supplier who completed registration, not a
-- name on the invitation list. leads holds 22,264 rows and 0 of them are registered, which is why
-- the two must never be counted as one number.
('SUPPLIERS_1000_BY_2027_10_01', 1, 'active',
 'Reach 1,000 registered suppliers by 1 October 2027.',
 'The founder set it. A category opens to buyers only at 10 verified suppliers, so registered supply is what unlocks demand at all.',
 2, 'ceo',
 'Count of leads that have completed registration, measured by leads.claimed.',
 'suppliers', 'Every row in public.leads.',
 'public.leads -- the row a supplier fills in on the website.',
 $q$select count(*) from public.leads where claimed$q$,
 0, 'measured', now(),
 'Measured 7 Sep 2026: 22,264 leads on the list and 0 registered. The list is not the target; registration is.',
 1000, 'cumulative', date '2027-10-01', 'daily',
 jsonb_build_array(
   'Registration is always on the website first. Documents may follow on WhatsApp or email, the first registration may not.',
   'The mandatory six and nothing more: company name, UAE mobile, email, trade licence, company profile, signed terms.',
   'Invitation volume stays inside the founder''s ceilings: 10 a day in month one, +5 a day each month after.'),
 jsonb_build_array(
   'The first 1,000 registrants never pay the annual fee, so this target and the revenue target do not compete for the same money.'),
 'Confidence is LOW. 110 invitations have been delivered and produced 0 registrations, so the conversion rate is measured and it is zero.',
 'Any month that ends with zero net new registrations while invitations were sent.',
 'public.leads shows 1,000 or more rows with claimed = true on or before 1 October 2027.',
 'The count, the invitation volume that produced it, and the bounce rate over the same period.',
 'founder'),

-- CUSTOMERS -----------------------------------------------------------------------------------
('CUSTOMERS_1000_BY_2027_10_01', 1, 'active',
 'Reach 1,000 registered customers by 1 October 2027.',
 'The founder set it. Suppliers stay only if requests arrive, so registered demand is what keeps supply.',
 2, 'ceo',
 'Count of rows in public.customers.',
 'customers', 'Every row in public.customers.',
 'public.customers -- the row a buyer creates when they register on the website.',
 $q$select count(*) from public.customers$q$,
 0, 'measured', now(),
 'Measured 7 Sep 2026: 0 registered customers.',
 1000, 'cumulative', date '2027-10-01', 'daily',
 jsonb_build_array(
   'A customer''s mandatory set is four, not six: name, mobile, email, signed terms.',
   'The buyer pays the 3 per cent reveal fee and nothing else. There is no charge to post a request.',
   'Anonymity holds until the buyer chooses to reveal.'),
 jsonb_build_array(
   'Buyers arrive once a category is open, so this target lags the supplier target rather than running beside it.'),
 'Confidence is LOW. No buyer has ever registered, so there is no conversion rate to reason from.',
 'Any month that ends with zero net new registrations while a category was open.',
 'public.customers shows 1,000 or more rows on or before 1 October 2027.',
 'The count, the categories open over the same period, and the requests those customers posted.',
 'founder'),

-- SOCIAL --------------------------------------------------------------------------------------
-- The only one of the four with NO instrument. baseline_state is 'not_instrumented', not zero:
-- nothing in this database has ever read a follower count from Instagram or Facebook, and a zero
-- here would be a claim rather than a reading.
('SOCIAL_2000_BY_2027_10_01', 1, 'active',
 'Reach 2,000 followers across Instagram and Facebook combined by 1 October 2027.',
 'The founder set it. It is the only target of the four that measures reach rather than transactions.',
 3, 'ceo',
 'Sum of follower counts on the QuotesDone Instagram and Facebook accounts, counted once per platform.',
 'followers', 'The two accounts, combined. Not per platform, and not other platforms.',
 'The Instagram and Facebook Graph APIs. NOTHING IN THIS DATABASE READS THEM YET.',
 null,
 null, 'not_instrumented', now(),
 'No instrument exists on 7 Sep 2026. No table records a follower count and no scheduled job reads one, so there is no baseline to state. The first thing this target needs is a reader, not a campaign.',
 2000, 'cumulative', date '2027-10-01', 'weekly',
 jsonb_build_array(
   'Followers are counted once across the two platforms combined, so the same person following both counts twice and that is stated rather than hidden.',
   'No paid promotion runs while the Meta token is missing.'),
 jsonb_build_array(
   'Both accounts exist and are reachable through the Graph API once a token is present.'),
 'Confidence CANNOT BE STATED. A target with no instrument has no confidence, only an intention, and calling it anything else would be a guess wearing a number.',
 'Any week that passes with the instrument still unbuilt.',
 'A recorded follower total of 2,000 or more across the two accounts on or before 1 October 2027, read from the platforms rather than typed in.',
 'The reading from each platform with its timestamp, and the reader that produced it.',
 'founder')

on conflict (contract_key, version) do nothing;

-- ---------------------------------------------------------------------------------------------
-- 3. THE DRIVER MODELS
-- ---------------------------------------------------------------------------------------------
-- Supplier registration has exactly one measured rate in the whole estate and it is zero: 110
-- invitations delivered, 0 registrations. That single measured zero is worth more than five
-- plausible assumptions, because it is the reason nothing downstream has ever moved.
insert into public.target_driver (contract_id, stage_order, stage_key, stage_label, from_stage_key,
                                  rate, rate_source, rate_evidence, lag_days, note)
select c.id, v.ord, v.k, v.lbl, v.from_k, v.rate, v.src, v.ev, v.lag, v.note
  from public.target_contract c
  cross join (values
    (1, 'invited',    'Suppliers invited',            null,        1.00, 'not_instrumented',
        'Volume is set by the founder''s channel ceilings, not by a conversion rate.', 0, null),
    (2, 'delivered',  'Invitations delivered',        'invited',   0.90, 'measured',
        'Measured: 110 of 122 delivered, 10 per cent bounced.', 0, null),
    (3, 'registered', 'Suppliers who register',       'delivered', 0.00, 'measured',
        'Measured: 110 delivered, 0 registrations. This is the binding stage of the entire company.', 7,
        'Everything else in the business waits behind this number.')
  ) as v(ord, k, lbl, from_k, rate, src, ev, lag, note)
 where c.contract_key = 'SUPPLIERS_1000_BY_2027_10_01'
   and not exists (select 1 from public.target_driver d where d.contract_id = c.id);

insert into public.target_driver (contract_id, stage_order, stage_key, stage_label, from_stage_key,
                                  rate, rate_source, rate_evidence, lag_days, note)
select c.id, v.ord, v.k, v.lbl, v.from_k, v.rate, v.src, v.ev, v.lag, v.note
  from public.target_contract c
  cross join (values
    (1, 'category_open', 'Categories open to buyers', null,            0.00, 'measured',
        'Measured: 0 categories have reached 10 verified suppliers.', 0,
        'A buyer cannot register into a marketplace with nothing in it.'),
    (2, 'registered',    'Customers who register',    'category_open', 0.00, 'not_instrumented',
        'No buyer has ever registered, so no rate has ever been observed.', 0, null)
  ) as v(ord, k, lbl, from_k, rate, src, ev, lag, note)
 where c.contract_key = 'CUSTOMERS_1000_BY_2027_10_01'
   and not exists (select 1 from public.target_driver d where d.contract_id = c.id);

-- The social target gets NO driver rows. A driver model is a chain of rates, and there is not one
-- rate here to state -- not even a zero, because nothing has ever been counted. An empty model is
-- the honest representation of that, and fn_target_feasibility will refuse to produce a verdict
-- from it rather than manufacture one.
