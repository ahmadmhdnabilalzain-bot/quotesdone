-- T6 LEGAL AND COMPLIANCE CALENDAR. Seat: accountant. Deterministic, no LLM, no lawyer (founder).
--
-- Measured live on 4 Oct 2026 before writing this:
--   * public.it_expiry already watches trade_licence_det_1633275 (2027-06-24) and tdra_nol_26_100000665
--     (2027-09-14) with warn_days {60,30}; fn_it_renewal_watch hands each stage to the accountant and escalates.
--   * fn_accountant_vat_threshold_check already sums gl_revenue_lines_measured over the preceding 12 months
--     against gl_settings.vat_registration_threshold_aed = 375000 and reports at decision_policy
--     vat_threshold_report_fractions [0.5,0.7,0.8,0.9,1] (the founder decides from 0.8). Nothing added there.
--   * Terms versions live in public.legal_documents (customer-terms v9, supplier-agreement v14 on 4 Oct).
--   * company_calendar had none of the four as rows of its own.
-- So this file only adds the 90-day stage to the two expiries and writes the four calendar rows.
-- Idempotent: a second run changes nothing.

update public.it_expiry
   set warn_days = array[90, 60, 30]
 where item in ('trade_licence_det_1633275', 'tdra_nol_26_100000665')
   and warn_days is distinct from array[90, 60, 30];

with r(event_name, starts_on, recurrence, affects, action, source_url) as (values
  ('Trade licence DET 1633275 expires', date '2027-06-24', 'annual',
   'QuotesDone''s own licence to trade (DET Trader licence, activities 722901 and 724003)',
   'Renew with DET before 24 Jun 2027. Reminders at 90/60/30 days from public.it_expiry through fn_it_renewal_watch to the accountant; the fee is the accountant''s, the filing the ceo''s.',
   'https://invest.dubai.ae'),
  ('TDRA NOL NOL-26-100000665 expires', date '2027-09-14', 'annual',
   'The e-activity approval for www.quotesdone.ae',
   'Renew with TDRA before 14 Sep 2027. Reminders at 90/60/30 days from public.it_expiry through fn_it_renewal_watch to the accountant.',
   'https://tdra.gov.ae'),
  ('VAT registration threshold watch (AED 375,000, rolling 12 months)', null::date, 'continuous',
   'Whether QuotesDone must register for VAT; invoices carry no VAT until then',
   'fn_accountant_vat_threshold_check sums posted revenue (gl_revenue_lines_measured) over the preceding 12 months against gl_settings vat_registration_threshold_aed and reports at decision_policy vat_threshold_report_fractions; the founder decides registration from 80%.',
   'https://tax.gov.ae'),
  ('Terms versions in force', null::date, 'on change',
   'Customer terms and supplier agreement accepted at sign-up',
   'The version in force is public.legal_documents.version (customer-terms, supplier-agreement); acceptance is recorded per party (leads.accepted_terms_version). Review on any change of law or of the product.',
   null)
), upd as (
  update public.company_calendar c
     set starts_on = r.starts_on, ends_on = r.starts_on, recurrence = r.recurrence, affects = r.affects,
         action = r.action, source_url = r.source_url, kind = 'compliance', owner_dept = 'accountant',
         verified_at = current_date
    from r
   where c.event_name = r.event_name
     and (c.kind, c.starts_on, c.ends_on, c.recurrence, c.affects, c.action, c.source_url, c.owner_dept)
         is distinct from ('compliance', r.starts_on, r.starts_on, r.recurrence, r.affects, r.action, r.source_url, 'accountant')
  returning c.id)
insert into public.company_calendar (event_name, kind, starts_on, ends_on, recurrence, affects, action, owner_dept, source_url)
select r.event_name, 'compliance', r.starts_on, r.starts_on, r.recurrence, r.affects, r.action, 'accountant', r.source_url
  from r
 where not exists (select 1 from public.company_calendar c where c.event_name = r.event_name);
