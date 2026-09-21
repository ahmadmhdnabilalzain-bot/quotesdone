-- THE OPEN ACCOUNT FACTS OF 21 SEPTEMBER ARE RECORDED: THE WHATSAPP NAME, THE PROVIDER CAPS, THE .AE DATE.
--
-- Assigned: accountant (the caps, the renewal date); it_engineer (the WhatsApp sender and its templates).
-- Every figure below was read on 21 Sep 2026, read-only, from the provider named beside it. Nothing
-- was submitted to Meta, Twilio, a registrar or any provider.
--
-- MEASURED (21 Sep 2026):
--   WhatsApp   Graph API GET /994300166829007/phone_numbers: phone 1203009262891015 (+1 218-316-6814)
--              verified_name "QuotesDone", name_status APPROVED, new_name_status NONE, quality GREEN,
--              status CONNECTED, is_official_business_account false. On 18 Sep it was NON_EXISTS.
--   Templates  Twilio Content API (ContentAndApprovals): quotesdone_login_code_{en,ar} (AUTHENTICATION)
--              and quotesdone_supplier_account_notice_{en,ar} (UTILITY), created 18 Sep 03:38 UTC, all
--              four at approval status "received". None of the four is listed by Meta's GET
--              /994300166829007/message_templates (13 templates, all APPROVED), so Meta has not received
--              them yet. The three *_utility_mu1rjyv0 re-submissions of 14 Sep are in the same state.
--              This WABA refused an AUTHENTICATION template on 4 Aug ("does not have permission to create
--              message template", quotesdone_control_mode_code): the login_code pair may meet it again.
--   Resend     receipt #2771-8471 (public.expenses id 27): USD 20.00 monthly. resend.com/pricing, read the
--              same day: USD 20/mo is Pro = 50,000 emails a month, "no daily email limit", overage billed
--              at USD 0.90 per 1,000 (a billing threshold, not a hard stop). The API exposes no quota.
--   Vercel     GET /v2/teams: plan "pro", status active. GET /v1/billing/charges, 1-21 Sep: USD 38.96
--              billed usage. The only spend control the API returns is analyticsSpendLimitInDollars = 500,
--              which caps Web Analytics alone - NOT the account (apply-discipline section 8).
--   Twilio     GET /Accounts/{sid}/Balance.json: USD 11.27, account type Full, active. A balance is not a
--              floor: the floor is the lowest balance the founder will allow, a budget decision.
--   .ae        whois.aeda.ae: registrar Host Arabia (Tasjeel.ae), status ok; aeDA publishes no expiry and
--              rdap.org has no RDAP service for .ae (404), which is why the row was empty since 14 Sep.
--              Tasjeel invoice TJ420134 (public.expense_entries id 67): registration 08/06/2026-07/06/2027.
--
-- WHAT WAS WRONG: four provider caps sat at the NULL their file inserted, with basis "not recorded",
-- the .ae expiry was NULL, instruction 494 was open with "no record", and the 18 Sep templates were in no
-- register. Nothing failed when any of that stayed so.
--
-- WHAT THIS CHANGES:
--   * cap_resend_emails_month = 50000 (fn_it_cap_set, by the accountant, from the receipt and the page).
--   * cap_resend_emails_day is removed: the Pro plan has none, and a NULL row would raise "no cap recorded"
--     for ever. Its insert is removed from the_it_engineer_watches_every_bill_before_its_cap.sql too.
--   * cap_vercel_charges_month and floor_twilio_balance stay NULL - they are the founder's budgets - and
--     their basis now says what was measured and where he sets each (fn_it_cap_set with a NULL value).
--   * domain:quotesdone.ae expires 2027-06-07, from the invoice; fn_it_renewal_watch warns the accountant
--     at 60 and 30 days as it does every other item; its route says RDAP will never read it.
--   * wa_template_registry gains the seven templates waiting at Twilio, status pending.
--   * founder_instruction 494 is done, with the Graph API reading as evidence.
-- NOT CHANGED: no routine, no table, no provider setting. Prevented from recurring by
-- scripts/checks/every_provider_cap_and_renewal_date_is_recorded.test.mjs.

-- 1. The caps.
select public.fn_it_cap_set('cap_resend_emails_month', 50000, 'accountant',
  'Resend receipt #2771-8471 (expenses id 27, USD 20.00/month) = the Pro plan; resend.com/pricing read 21 Sep 2026: '
  || '50,000 emails a month, no daily limit, overage USD 0.90 per 1,000 is billed rather than refused');
delete from public.it_threshold where key = 'cap_resend_emails_day' and value is null;
select public.fn_it_cap_set('cap_vercel_charges_month', null, 'accountant',
  'needs the founder''s dashboard: vercel.com > team > Settings > Billing > Spend Management (the API does not expose it). '
  || 'Measured 21 Sep 2026: plan pro, 1-21 Sep usage billed USD 38.96, subscription USD 49.90/month in expenses; '
  || 'analyticsSpendLimitInDollars = 500 caps Web Analytics only');
select public.fn_it_cap_set('floor_twilio_balance', null, 'accountant',
  'needs the founder: the lowest prepaid balance he allows, set in console.twilio.com > Billing > Auto-recharge (the API '
  || 'does not expose it). Measured 21 Sep 2026: balance USD 11.27 (Balance.json), account Full, active');

-- 2. The .ae renewal date.
update public.it_expiry
   set expires_on = date '2027-06-07', checked_at = now(),
       source = 'Tasjeel.ae invoice TJ420134 (expense_entries id 67): registered 08/06/2026-07/06/2027; whois.aeda.ae '
                || '21 Sep 2026: registrar Host Arabia (Tasjeel.ae), status ok, no expiry published',
       route = 'renew at Tasjeel.ae (Host Arabia); aeDA publishes no expiry and rdap.org has no .ae service, so record the '
               || 'new date from the invoice with fn_it_renewal_recorded'
 where item = 'domain:quotesdone.ae' and expires_on is null;

-- 3. The templates waiting at Twilio.
insert into public.wa_template_registry (template_name, language, category, status, purpose, approved_on, rejection_cause, checked_at, source) values
  ('quotesdone_login_code_en_mu6eslpb', 'en', 'AUTHENTICATION', 'pending',
   'The sign-in one-time code. This WABA refused an AUTHENTICATION template on 4 Aug (no permission); it may again.', null, null, now(),
   'Twilio Content API: "received" since 18 Sep 2026 03:38 UTC; not in Meta message_templates on 21 Sep 2026'),
  ('quotesdone_login_code_ar_mu6esobi', 'ar', 'AUTHENTICATION', 'pending', 'Arabic of the above.', null, null, now(),
   'Twilio Content API: "received" since 18 Sep 2026 03:38 UTC; not in Meta message_templates on 21 Sep 2026'),
  ('quotesdone_supplier_account_notice_en_mu6esqkz', 'en', 'UTILITY', 'pending',
   'Tells a supplier something changed on their account.', null, null, now(),
   'Twilio Content API: "received" since 18 Sep 2026 03:38 UTC; not in Meta message_templates on 21 Sep 2026'),
  ('quotesdone_supplier_account_notice_ar_mu6est8z', 'ar', 'UTILITY', 'pending', 'Arabic of the above.', null, null, now(),
   'Twilio Content API: "received" since 18 Sep 2026 03:38 UTC; not in Meta message_templates on 21 Sep 2026'),
  ('quotesdone_supplier_new_inquiry_en_utility_mu1rjyv0', 'en', 'UTILITY', 'pending',
   'UTILITY re-submission of quotesdone_supplier_new_inquiry_en (approved as MARKETING).', null, null, now(),
   'Twilio Content API: "received" since 14 Sep 2026 21:37 UTC; not in Meta message_templates on 21 Sep 2026'),
  ('quotesdone_supplier_doc_expiry_ar_utility_mu1rjyv0', 'ar', 'UTILITY', 'pending',
   'UTILITY re-submission of quotesdone_supplier_doc_expiry_ar (approved as MARKETING).', null, null, now(),
   'Twilio Content API: "received" since 14 Sep 2026 21:37 UTC; not in Meta message_templates on 21 Sep 2026'),
  ('quotesdone_customer_new_quote_ar_utility_mu1rjyv0', 'ar', 'UTILITY', 'pending',
   'UTILITY re-submission of quotesdone_customer_new_quote_ar (approved as MARKETING).', null, null, now(),
   'Twilio Content API: "received" since 14 Sep 2026 21:37 UTC; not in Meta message_templates on 21 Sep 2026')
on conflict (template_name) do update set status = excluded.status, checked_at = excluded.checked_at, source = excluded.source
 where public.wa_template_registry.status = 'pending';

-- 4. Instruction 494.
update public.founder_instruction
   set status = 'done',
       evidence = 'Graph API GET /994300166829007/phone_numbers, 21 Sep 2026: phone 1203009262891015 verified_name '
                  || '"QuotesDone", name_status APPROVED (NON_EXISTS on 18 Sep), quality GREEN, CONNECTED; Twilio sender '
                  || 'profile name QuotesDone, ONLINE. is_official_business_account false: the green tick is Meta''s grant, not promised.',
       note = note || ' | DONE (21 Sep 2026, it_engineer): display name approved; number unchanged, as he ruled.'
 where id = 494 and status = 'open';

-- PROBE: one verdict row.
select case when
    (select value from public.it_threshold where key = 'cap_resend_emails_month') = 50000
    and not exists (select 1 from public.it_threshold where key ~ '^(cap|floor)_' and value is null and basis like 'not recorded%')
    and (select expires_on from public.it_expiry where item = 'domain:quotesdone.ae') = date '2027-06-07'
    and (select count(*) from public.wa_template_registry where status = 'pending') >= 7
    and (select status from public.founder_instruction where id = 494) = 'done'
  then 'PROBE OK' else 'PROBE FAILED' end as verdict;
