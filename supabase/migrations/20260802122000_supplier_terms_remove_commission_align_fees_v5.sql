-- LEGAL CONSISTENCY (2 Aug 2026, external code review + founder correction).
-- WHY: the signed Supplier Agreement in app_secrets.supplier_terms_html still ran a 2% COMMISSION
-- model. Clause 7 had already been rewritten to say no commission is charged, but the definitions,
-- the payment-terms clause, the late-payment clause, the non-circumvention clause, the privacy
-- clause, the termination clause and the general-fees clause were all left behind, so the document
-- contradicted itself, contradicted the public website ("no commission, ever") and contradicted
-- app_secrets.supplier_subscription_term. It also stated the CUSTOMER reveal fee as 2% when
-- pricing_config has held 3% (standard and promo) throughout. This is the document suppliers
-- electronically sign and that compliance_archive renders into a PDF certificate, so an internal
-- contradiction here is a live legal exposure, not a typo. Version bumped 4 -> 5 because the
-- commercial terms have materially changed.
-- Safe to apply: zero suppliers had signed at the time of writing (leads.accepted_terms_at null
-- everywhere), so no existing acceptance is retro-changed.
-- NOTE: the full text of each replacement clause lives in the applied migration; this file is the
-- committed record of it. Re-running is idempotent - the regexes no longer match once applied.

update app_secrets set value = regexp_replace(value,
  '<li><b>Commission</b>[^<]*</li>',
  '<li><b>Subscription Fee</b> &mdash; the annual supplier subscription fee described in clause 6.</li>')
where key = 'supplier_terms_html';

update app_secrets set value = regexp_replace(value,
  '<h2>6\. Registration fees</h2>.*?</p>',
  '<h2>6. Registration &amp; subscription fees</h2><p>Supplier registration is <b>free of charge until 31 July 2027</b>. From <b>1 August 2027</b> a subscription fee of <b>AED 1,000 per year</b> applies, payable annually in advance. The <b>first 1,000 businesses to register</b> on the Platform are permanently exempt from that fee. QuotesDone will give at least 30 days&#39; notice and seek re-confirmation of acceptance before introducing or varying the fee, as set out in the Amendments section; continued use of the Platform after the effective date constitutes acceptance. The subscription fee, once paid, is non-refundable except as expressly stated at the time.</p>')
where key = 'supplier_terms_html';

update app_secrets set value = regexp_replace(value,
  '<h2>7\. Platform commission</h2>.*?</p>',
  '<h2>7. No supplier commission</h2><p><b>QuotesDone charges the Supplier no commission on any job won through the Platform</b> &mdash; not on the Quotation Value, not on the amount finally invoiced, and not on repeat work with the same Customer. The Platform is funded by the subscription fee in clause 6 and by a fee payable by the Customer at Reveal. QuotesDone reserves the right to introduce a supplier commission in future only on at least 30 days&#39; notice and re-confirmation of acceptance as set out in the Amendments section; no commission is or becomes payable under this version of the Agreement.</p>')
where key = 'supplier_terms_html';

update app_secrets set value = regexp_replace(value,
  '<h2>8\. Payment terms</h2>.*?</p>',
  '<h2>8. Payment terms</h2><p>Where a Subscription Fee is payable under clause 6, it is payable annually in advance, by card or by bank transfer, on the renewal date of the Supplier&#39;s account. QuotesDone may issue an invoice or statement for amounts due; payment is not conditional on receipt of an invoice. All amounts are in AED unless stated. Separately, the Customer &mdash; not the Supplier &mdash; pays QuotesDone a reveal fee of <b>3% of the Quotation Value</b> at the moment of Reveal. Nothing is deducted from, or charged on, the amount the Customer pays the Supplier for the work.</p>')
where key = 'supplier_terms_html';

update app_secrets set value = regexp_replace(value,
  '<h2>9\. Late payment</h2>.*?</p>',
  '<h2>9. Late payment</h2><p>If a Subscription Fee is not received by its due date, QuotesDone may, after giving the Supplier notice and a further <b>7 Working Days</b> to pay, suspend the Supplier&#39;s account until payment is made. Unpaid Subscription Fees are debts due and payable and may be recovered through the competent UAE courts. QuotesDone may set off amounts owed against any sums it holds for the Supplier.</p>')
where key = 'supplier_terms_html';

update app_secrets set value = replace(value,
  'lost platform value and lost commissions',
  'lost platform value and lost subscription revenue')
where key = 'supplier_terms_html';

update app_secrets set value = regexp_replace(value,
  'in that event the Supplier.{0,12}s Commission for that job is treated as forfeited \(it remains due if unpaid and is not refundable if already paid\), and',
  'and')
where key = 'supplier_terms_html';

update app_secrets set value = replace(value,
  'Commission invoicing and collection',
  'subscription invoicing and collection')
where key = 'supplier_terms_html';

update app_secrets set value = replace(value,
  'Outstanding Commissions and charges survive termination',
  'Outstanding Subscription Fees and charges survive termination')
where key = 'supplier_terms_html';

update app_secrets set value = replace(value,
  'Registration and commission are addressed in sections 6 and 7',
  'Registration and subscription fees are addressed in sections 6 and 7, and no supplier commission is charged')
where key = 'supplier_terms_html';

update app_secrets set value = replace(value,
  'Version 4 &middot; governed by',
  'Version 5 &middot; governed by')
where key = 'supplier_terms_html';

-- SINGLE SOURCE OF TRUTH for the version string. supplier_api read app_secrets('terms_version')
-- and fell back to 'v2' because the key had never been created, while kyc hard-coded 'v4' and
-- compliance_archive printed "Version 4" on the certificate. Three answers for one question.
insert into app_secrets (key, value) values
  ('terms_version', 'v5'),
  ('supplier_terms_version', 'v5'),
  ('supplier_terms_label', 'Supplier Agreement - Version 5'),
  ('customer_terms_version', 'v3'),
  ('customer_terms_label', 'Customer Terms & Conditions - Version 3')
on conflict (key) do update set value = excluded.value;
