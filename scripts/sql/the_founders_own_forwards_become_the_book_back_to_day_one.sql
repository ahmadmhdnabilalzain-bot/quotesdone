-- THE FOUNDER'S OWN FORWARDS BECOME THE BOOK, BACK TO DAY ONE.
--
-- The founder, 9 September 2026, verbatim: "from 29th of june i have been sending emails to
-- expenses mail. so i need the accountant to email me the whole thing and keep it in his record
-- as well".
--
-- fn_accountant_spend_report already exists and is correct. It was reporting a TRUE total over an
-- INCOMPLETE book: only 9 rows had ever been booked, because the only path into expense_entries
-- was Resend's inbound history, and Resend keeps inbound mail for roughly one month. Everything the
-- founder forwarded before 12 August 2026 had aged out of the provider before the sweep existed.
-- Nothing was misaddressed and nothing was lost by us -- the provider simply does not keep it.
--
-- WHAT WAS MEASURED BEFORE A LINE OF THIS WAS WRITTEN (9 Sep 2026, all from production and from
-- the founder's own Gmail SENT folder, which is the surviving record):
--   * `in:sent to:expenses@mail.quotesdone.com` returns exactly 36 threads, 29 Jun -> 3 Sep 2026.
--     That is the complete history of what he forwarded. All 36 were opened and read.
--   * 35 of the 36 print an amount that can be read directly off the forwarded receipt body.
--   * 8 of the 36 are ALREADY booked, under their `resend:<email_id>` keys (ids 49-55, 57). They
--     are excluded here by the unique index on source_msg_id AND by matching vendor+date+amount,
--     so neither key can produce a second copy of the same charge.
--   * The 9th already-booked row -- id 56, GoDaddy AED 40.95 incl VAT 1.95, charged 12 Aug 2026 --
--     corresponds to NO thread in the 36. Its net of 39.00 is the single "Microsoft 365 Email Plus"
--     line; both GoDaddy orders the founder forwarded total 93.80 (89.33 + 4.47 VAT) across four
--     line items. Different amounts, different dates, different baskets: they are distinct charges
--     and booking these two does not duplicate that one.
--   * A full-mailbox search for GoDaddy receipts between 5 and 20 Aug 2026 returns exactly one
--     receipt -- order #4159524806 of 10 Aug. There is no second 10 Aug GoDaddy charge for the
--     12 Aug row to be a mis-parse of.
--
-- SO 36 = 8 already booked + 28 booked here. The 28 below are every charge the founder forwarded
-- that the ledger had never seen.
--
-- HOW THE AMOUNTS WERE OBTAINED. Every figure is READ off the receipt the founder forwarded --
-- never derived, never estimated, never inferred from a vendor's list price. The one receipt whose
-- amount could not have been read (OpenAI's "your new plan" mail) turned out to print an explicit
-- charged breakdown in AED, so the AED figure is used and the USD list price was NOT substituted.
--
-- THE ONE ENTRY WHOSE DATE WAS NOT PRINTED. The Twilio funding notice reached expenses@ inside the
-- 29 Jun batch as an .eml ATTACHMENT rather than quoted inline, so the forward's own text carries
-- the amount ("$20.00 to bring the balance to $20.00") but no date. It is booked at 25 Jun 2026,
-- established by MEASUREMENT, not by guess: a search of the entire mailbox for Twilio funding
-- notices returns exactly two threads -- the original from noreply@twilio.com on 25 Jun 2026 for
-- $20.00 on card 5057, and the founder's forward of it. There is exactly one Twilio funding event
-- in the mailbox and this is it. The basis is recorded in the row's own note so a later auditor
-- sees how the date was reached, and fn_accountant_spend_report names it on the face of the report.
-- Dropping a real $20 charge to look rigorous would understate the total; guessing at it would be
-- worse. Booking it with its basis written down is neither.
--
-- VAT IS STORED THE WAY fn_expense_post_to_gl READS IT: `amount` is the gross the card was charged
-- and `vat_amount` is the tax contained WITHIN it (the routine computes net = amount - vat). So a
-- receipt that adds tax on top is stored at its TOTAL, not its subtotal. This matches the two
-- already-booked rows that carry VAT -- Google 26.99/1.29 and GoDaddy 40.95/1.95 -- so the old rows
-- and the new ones mean the same thing.
--
-- CURRENCY. Only AED and USD appear. USD converts at gl_settings.usd_to_aed (3.6725) inside
-- fn_expense_post_to_gl, per entry, rounded to two places. No other currency is present, so nothing
-- here is at risk of the 1:1 refusal -- and if one ever were, that routine refuses it rather than
-- booking it wrong.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. THE 28 CHARGES. Keyed `gmail:<message_id>` on the founder's own forward -- the artifact that
--    would have arrived at expenses@ had the provider still held it. That key is stable, it is
--    unique per forward, and it cannot collide with a `resend:<email_id>` key, so the live webhook,
--    the Resend sweep and this backfill can never book the same receipt twice.
--
--    The `where not exists` is belt as well as braces: the unique index already stops a second run
--    of THIS file, and the vendor+date+amount clause additionally stops a charge already booked
--    under its resend key from arriving a second time under a gmail key.
-- ---------------------------------------------------------------------------------------------
with forwarded(source_msg_id, vendor, category, amount, currency, charged_on, vat_amount, note) as (
  values
  ('gmail:19f14948f978ceb3','Anthropic','Subscription',105.00,'USD','2026-05-26'::date, 5.00,
   'Anthropic, PBC receipt 2838-8118-2419 (invoice YXWTXUVD-0001). VAT - United Arab Emirates (5%) $5.00 stated on the receipt. Forwarded from management@doratajewelries.com, then to expenses@mail.quotesdone.com in the 29 Jun 2026 batch.'),
  ('gmail:19f14963d1cdc6cf','Apify','Usage',29.00,'USD','2026-06-03'::date, null,
   'Apify invoice #202606032609. No VAT line printed. Forwarded to expenses@ on 29 Jun 2026.'),
  ('gmail:19f1495fe16818a4','Tasjeel.ae','Subscription',135.45,'AED','2026-06-08'::date, 6.45,
   'Tasjeel.ae invoice TJ420134 - domain registration quotesdone.ae, 1 year (08/06/2026-07/06/2027). Sub total AED 129.00 + 5.00% VAT AED 6.45 = AED 135.45. Forwarded to expenses@ on 29 Jun 2026.'),
  ('gmail:19f1495c0b496923','Vercel','Subscription',20.00,'USD','2026-06-09'::date, null,
   'Vercel Inc. receipt 2779-4954 (invoice OOJ7APIU-0001), Pro $20.00. No VAT line printed. Forwarded to expenses@ on 29 Jun 2026.'),
  ('gmail:19f149476497e2bf','Anthropic','Subscription',47.25,'USD','2026-06-09'::date, 2.25,
   'Anthropic, PBC receipt 2058-0862-9389 (invoice YXWTXUVD-0002). VAT - United Arab Emirates (5%) $2.25 stated on the receipt. Forwarded from management@doratajewelries.com, then to expenses@ on 29 Jun 2026.'),
  ('gmail:19f149b0c7968090','Google','Subscription',26.99,'AED','2026-06-13'::date, 1.29,
   'Google Play order GPA.3306-1807-2606-12909..10, merchant Dropbox, Inc. Receipt prints "(Includes VAT of 1.29)" - VAT is inside the 26.99. Forwarded to expenses@ on 29 Jun 2026.'),
  ('gmail:19f1494fef717462','Resend','Subscription',20.00,'USD','2026-06-15'::date, null,
   'Resend receipt 2335-5477 (invoice QOGH46KN-0001). No VAT line printed. Receipt also notes a settlement of AED 76.39 at 3.8196; the USD figure is the transacted amount and is what is booked. Forwarded to expenses@ on 29 Jun 2026.'),
  ('gmail:19f149133fad4849','Twilio','Usage',20.00,'USD','2026-06-25'::date, null,
   'Twilio, Inc. account funding - "We charged the My first Twilio account Credit Card (**** 5057) $20.00 to bring the balance to $20.00". Transaction CX4a1ac023e1038f53e09d8f78f4043636. No receipt number and NO DATE is printed in the forwarded text: the original reached expenses@ on 29 Jun 2026 as an .eml attachment rather than quoted inline. DATE BASIS: a search of the entire mailbox for Twilio funding notices returns exactly two threads - the original from noreply@twilio.com dated 25 Jun 2026 for $20.00 on card 5057, and the founder''s forward of it. There is exactly one Twilio funding event in the mailbox, so the charge date is 25 Jun 2026. Established by matching to the unique source message, NOT read off the forward and NOT estimated.'),
  ('gmail:19f1494518c9ead7','Anthropic','Subscription',105.00,'USD','2026-06-26'::date, 5.00,
   'Anthropic, PBC receipt 2082-1679-3052 (invoice YXWTXUVD-0003). VAT - United Arab Emirates (5%) $5.00 stated on the receipt. Forwarded from management@doratajewelries.com, then to expenses@ on 29 Jun 2026.'),
  ('gmail:19f14919a39f678d','Supabase','Usage',50.55,'USD','2026-06-27'::date, null,
   'Supabase Pte. Ltd. invoice TLZLFZ-00004, paid Jun 27 2026. No VAT line printed. Forwarded to expenses@ on 29 Jun 2026.'),
  ('gmail:19f14903677204bb','Rork','Subscription',20.00,'USD','2026-06-27'::date, null,
   'Rork, Inc. receipt 2324-8607 (invoice XYGZ5CWF-0002), billed via Stripe. No VAT line printed. Receipt also notes AED 75.66 at 1 USD = 3.7829; the USD figure is the transacted amount and is what is booked. Forwarded to expenses@ on 29 Jun 2026.'),
  ('gmail:19f1d3a66f4e96cf','OpenRouter','Usage',21.10,'USD','2026-07-01'::date, null,
   'OpenRouter, Inc receipt 1554-8228, paid Jul 1 2026. No VAT line printed.'),
  ('gmail:19f25855086777dd','Apify','Usage',54.75,'USD','2026-07-03'::date, null,
   'Apify invoice #202607031706. No VAT line printed.'),
  ('gmail:19f48c0451e1e372','Vercel','Subscription',20.00,'USD','2026-07-09'::date, null,
   'Vercel Inc. receipt 2965-2105 (invoice OOJ7APIU-0003), Observability Plus $0.00 + Pro $20.00. No VAT line printed.'),
  ('gmail:19f4bf30dcd5624e','GoDaddy','Subscription',93.80,'AED','2026-07-10'::date, 4.47,
   'GoDaddy renewal order #4132924111. Line items 1 month each: Microsoft 365 Email Plus AED 39.00, Advanced Email Security AED 18.33, Email Archiving AED 16.00, Microsoft 365 Email Backup AED 16.00. Subtotal AED 89.33 + tax AED 4.47 = AED 93.80.'),
  ('gmail:19f4eb4987daa092','Figma','Subscription',20.00,'USD','2026-07-10'::date, null,
   'Figma subscription receipt in_1TrpJ2IvcqWR3dFDTyaOAH4A, period Jul 10 - Aug 10 2026. No VAT line printed.'),
  ('gmail:19f67bcd2ff7a4c0','OpenRouter','Usage',31.65,'USD','2026-07-15'::date, null,
   'OpenRouter, Inc receipt 1123-1576, paid Jul 15 2026. No VAT line printed.'),
  ('gmail:19f67cda874adb97','Resend','Subscription',20.00,'USD','2026-07-15'::date, null,
   'Resend receipt 2614-7681 (invoice QOGH46KN-0002). No VAT line printed.'),
  ('gmail:19f9f626bd30290c','OpenRouter','Usage',31.65,'USD','2026-07-26'::date, null,
   'OpenRouter, Inc receipt 1550-9316, paid Jul 26 2026. No VAT line printed.'),
  ('gmail:19fa327d24ef8d34','Supabase','Usage',53.71,'USD','2026-07-27'::date, null,
   'Supabase Pte. Ltd. invoice TLZLFZ-00005, paid Jul 27 2026. No VAT line printed.'),
  ('gmail:19fad8f00a5749b4','OpenRouter','Usage',21.10,'USD','2026-07-29'::date, null,
   'OpenRouter, Inc receipt 1018-2222, paid Jul 29 2026. No VAT line printed.'),
  ('gmail:19faf0638e1ad499','OpenAI','Subscription',385.00,'AED','2026-07-29'::date, 18.33,
   'OpenAI ChatGPT Pro subscription sub_1TyZKqC6h1nxGoI3n9P94ftd, Jul 29 2026. The mail prints an explicit charged breakdown in AED: 366.67 + tax 18.33 = 385.00, paid on Visa 5057. Booked in AED as printed; the USD list price was NOT substituted.'),
  ('gmail:19faf44e0cd07e7e','Vercel','Subscription',30.00,'USD','2026-07-29'::date, null,
   'Vercel Inc. receipt 2020-7436 (invoice OOJ7APIU-0004), v0 Seats $30.00, paid by Link. No VAT line printed.'),
  ('gmail:19fc51e6a072b304','Apify','Usage',29.00,'USD','2026-08-03'::date, null,
   'Apify invoice #202608031760. No VAT line printed.'),
  ('gmail:19fd4efbdadfe414','OpenRouter','Usage',21.10,'USD','2026-08-06'::date, null,
   'OpenRouter, Inc receipt 1557-8238, paid Aug 6 2026. No VAT line printed.'),
  ('gmail:19fe8a6d1a755deb','Vercel','Subscription',20.00,'USD','2026-08-09'::date, null,
   'Vercel Inc. receipt 2290-0745-3622 (invoice OOJ7APIU-0005), Observability Plus $0.00 + Pro $20.00. No VAT line printed.'),
  ('gmail:19feb3c03a3d77a8','OpenRouter','Usage',10.80,'USD','2026-08-10'::date, null,
   'OpenRouter, Inc receipt 1251-4850, paid Aug 10 2026. No VAT line printed.'),
  ('gmail:19febff5f375babd','GoDaddy','Subscription',93.80,'AED','2026-08-10'::date, 4.47,
   'GoDaddy renewal order #4159524806. Line items 1 month each: Microsoft 365 Email Plus AED 39.00, Advanced Email Security AED 18.33, Email Archiving AED 16.00, Microsoft 365 Email Backup AED 16.00. Subtotal AED 89.33 + tax AED 4.47 = AED 93.80. Distinct from the already-booked AED 40.95 of 12 Aug 2026, which is the Email Plus line alone.')
)
insert into public.expense_entries
  (source_msg_id, vendor, category, amount, currency, charged_on, vat_amount, note, source)
select f.source_msg_id, f.vendor, f.category, f.amount, f.currency, f.charged_on, f.vat_amount,
       f.note, 'receipt'
  from forwarded f
 where not exists (
       select 1 from public.expense_entries e
        where e.source_msg_id = f.source_msg_id)
   and not exists (
       -- the same charge already booked under a resend key: same vendor, same day, same money
       select 1 from public.expense_entries e
        where e.vendor = f.vendor
          and e.charged_on = f.charged_on
          and e.amount = f.amount
          and upper(e.currency) = upper(f.currency));

commit;

-- ---------------------------------------------------------------------------------------------
-- 2. POST EVERY UNPOSTED ENTRY TO THE LEDGER, through the routine that already owns that decision.
--    fn_expense_post_to_gl returns the existing journal id when one exists, so this is safe to run
--    over the whole table and cannot double-post. gl_expense_map picks the account, 6300 is the
--    fallback, and a currency with no rate is refused rather than booked at 1:1.
-- ---------------------------------------------------------------------------------------------
select e.id, public.fn_expense_post_to_gl(e.id) as journal_id
  from public.expense_entries e
 order by e.charged_on, e.id;
