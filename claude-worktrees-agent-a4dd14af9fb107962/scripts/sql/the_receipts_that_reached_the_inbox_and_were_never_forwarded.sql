-- THE RECEIPTS THAT REACHED THE INBOX AND WERE NEVER FORWARDED.
-- Agent: ceo. 9 September 2026.
--
-- THE FOUNDER, 9 Sep 2026: "also include chat gpt bills". He was right that vendors were missing,
-- and the cause was a THIRD gap, distinct from the two already closed on the same day.
--
-- Gap 1 was Resend's ~1-month inbound retention: closed by reading the founder's Gmail SENT folder.
-- Gap 2 was a second mailbox nobody read: closed by reading Outlook management@doratajewelries.com.
-- BOTH of those swept only FORWARDED mail. Gap 1 read what he forwarded and Resend still held;
-- Gap 2 read a mailbox he never forwarded from at all. Neither could see the case in between:
--
--   A RECEIPT THAT LANDED IN HIS GMAIL **INBOX** AND WAS NEVER FORWARDED TO THE EXPENSES ADDRESS.
--
-- The two closed gaps are both bounded by an act of forwarding - `in:sent to:expenses@...` finds
-- exactly the mail he remembered to send on, and finds nothing about the mail he did not. A vendor
-- can bill a mailbox the accountant CAN read and still be invisible, because the only query ever
-- pointed at that mailbox filtered on the forward. Replicate had billed twice and the ledger had
-- never heard the name.
--
-- WHAT WAS ACTUALLY READ
--   Gmail, `in:anywhere -in:sent`, 1 May 2026 to 9 Sep 2026, on receipt/invoice/payment/renewal/
--   subscription/billing/charged, paged to exhaustion (three pages, 201 estimated / 127 distinct
--   threads), plus targeted per-vendor searches for OpenAI, Stripe-relayed invoices, Figma, Google
--   Play, Replicate, GitHub, GoDaddy, Glide and Higgsfield. Every candidate below was opened and
--   its amount read off the receipt body. NOTHING here is derived, estimated or annualised.
--
-- WHAT THIS FILE DOES
--   1. Registers the founder's Gmail INBOX as a billing mailbox in its own right, distinct from the
--      SENT folder already registered. An unread source has to be visible as unread; a source read
--      only through a `in:sent` filter is a HALF-read source and now says so.
--   2. Books 10 charges that are demonstrably QuotesDone's, with a stable gmail:<message_id> key AND
--      an economic guard on (vendor, charged_on, amount, currency) - the same charge reaching two
--      mailboxes carries two different message ids, so the key alone cannot stop a double-booking.
--   3. Records what was SEEN but not booked: five vendor/entity questions and two Dorata orders,
--      in public.expense_vendor_billing_mailbox, with the evidence that was actually read.
--
-- ENTITY CARE. Learned an hour before this file: the Outlook mailbox belongs to Dorata Jewelries
-- FZCO, so seven vendors found there were recorded UNDECIDED rather than booked. The same rule is
-- applied here and it bites twice - two GoDaddy orders in this window name DORATAJEWELRIES.COM and
-- the management@doratajewelries.com mailbox outright. Booking another company's costs corrupts the
-- ledger exactly as much as omitting ours.
--
-- ============================================================================================
-- CHATGPT, WHICH IS WHAT THE FOUNDER ASKED FOR BY NAME
-- ============================================================================================
-- public.expense_entries holds exactly ONE OpenAI row: 29 Jul 2026, AED 385.00 (the mail printed an
-- explicit AED breakdown, 366.67 + 18.33 tax). ChatGPT Pro renews monthly, so August and September
-- renewals should exist. They were searched for four different ways:
--
--   Gmail `in:anywhere after:2026/07/29 (ChatGPT OR OpenAI OR chatgpt.com OR 385.00 OR "Pro plan")`
--        -> 19 threads, every one of them marketing, security-notice, sign-in or support. No receipt.
--   Gmail `in:anywhere after:2026/05/01 ("Your receipt from OpenAI" OR "OpenAI, LLC" OR "385.00"
--        OR from:invoice+statements@openai.com)` -> ZERO threads.
--   Gmail `from:stripe.com` across the whole period -> the only Stripe-relayed invoices are Rork's
--        (acct_1QjqBKFp8To3eoRn). OpenAI does not bill through that rail into this mailbox.
--   Outlook `from:openai.com after 1 Jul 2026` -> 7 messages, all marketing.
--
-- FINDING, stated as a measurement and not as an inference: THE AUGUST AND SEPTEMBER CHATGPT
-- RENEWAL RECEIPTS DO NOT EXIST IN EITHER MAILBOX. No row is created for them. A monthly cadence is
-- a reason to go looking, never a licence to invent an amount - and ~AED 385 x 2 would be exactly
-- that. What CAN be said is bounded: the only OpenAI billing mail either mailbox has ever held is
-- the 29 Jul 2026 one, which is already booked. Where the renewals went - a different address, a
-- different plan, a cancellation, or a receipt OpenAI never sent - is not answerable from the mail.
--
-- Two neighbouring facts, recorded because they bound the question rather than answer it:
--   - 31 Jul 2026, support@openai.com case 12359891: "You reported your subscription credits were
--     exhausted very quickly while using the coding feature." Something changed on that account two
--     days after the 29 Jul charge. That is a fact about the account, NOT evidence of a charge.
--   - The 29 Jul mail is titled "ChatGPT - Your new plan" and says the subscription "will
--     automatically renew". An intention to renew is not a receipt and is not booked as one.
--
-- FIGMA. Same treatment. Gmail holds exactly ONE Figma mail in the whole period, the 10 Jul 2026
-- receipt already booked; Outlook holds none. No August or September Figma receipt exists to read.
--
-- GOOGLE. The founder's "July missing" is CORRECT and is fixed below: the Google Play/Dropbox
-- subscription renews on the 13th and the mailbox holds four receipts - 13 May, 13 Jun, 13 Jul,
-- 13 Aug. Only June and August had been booked. May and July are booked here.
-- ============================================================================================

-- ---------------------------------------------------------------------------------------------
-- 1. THE MAILBOX THAT WAS ONLY EVER READ THROUGH A FILTER
-- ---------------------------------------------------------------------------------------------
insert into public.expense_billing_mailbox (mailbox, description, reachable_by, is_swept, last_swept_on, note)
values
  ('founder Gmail inbox (ahmadmhdnabilalzain@gmail.com)',
   'The address most vendors actually bill. A receipt arriving here only reaches the accountant if '
   'the founder forwards it by hand, and many were never forwarded.',
   'Gmail connector, search of all mail excluding sent',
   true, date '2026-09-09',
   'Added 9 Sep 2026. The SENT folder was already registered, but sweeping `in:sent to:expenses@` '
   'can only ever find mail he REMEMBERED to forward - it is blind by construction to a receipt that '
   'arrived and stayed put. Swept 1 May - 9 Sep 2026 on receipt/invoice/payment/renewal/subscription/'
   'billing/charged, paged to exhaustion, plus per-vendor searches. Replicate was found this way: two '
   'invoices, a vendor the ledger had never seen.')
on conflict (mailbox) do update
   set is_swept = true, last_swept_on = excluded.last_swept_on,
       reachable_by = excluded.reachable_by, note = excluded.note;

-- ---------------------------------------------------------------------------------------------
-- 2. THE CHARGES. Amounts read off the receipt, never derived.
-- ---------------------------------------------------------------------------------------------
-- Every insert is guarded TWICE. `source_msg_id` stops the same message being read twice; the
-- (vendor, charged_on, amount, currency) test stops the same ECONOMIC charge being booked twice
-- when it reaches two mailboxes under two different message ids. Both guards are needed: the 40
-- rows already in the book carry resend:, gmail: and outlook: keys for overlapping mail.
with candidate(vendor, category, amount, currency, charged_on, vat_amount, source_msg_id, note) as (
  values
  -- REPLICATE. A vendor the ledger had never seen. Both invoices print "To quotesdone" and the line
  -- item "One-time credit purchase"; both print "Amount paid -$20.00" and "Amount remaining $0.00".
  -- Neither prints a "date paid" line, so the date is taken from the invoice's own "Due <date>",
  -- which on both is the same day the invoice arrived AND the same day the paired "Purchase
  -- successful - credit added to your Replicate account" mail arrived (31 Aug 14:40:48Z / 4 Sep
  -- 19:14:26Z, seconds from the invoice). Established by matching two messages, not estimated.
  ('Replicate','Usage',20.00,'USD',date '2026-08-31',null,'gmail:1a0584433eba619a',
   'Replicate, LLC invoice #Z4XJ1TTF-0001. "To quotesdone". One-time credit purchase, Qty 1 $20.00, '
   '"Amount paid -$20.00", "Amount remaining $0.00". No VAT line printed. The invoice prints no date '
   'paid; "Due August 31, 2026" is corroborated by the same-minute "Purchase successful" mail from '
   'billing@replicate.email. Arrived in the founder''s Gmail inbox and was NEVER forwarded to the '
   'accountant - this vendor had never appeared in the ledger at all.'),
  ('Replicate','Usage',20.00,'USD',date '2026-09-04',null,'gmail:1a06dd7fb896ce07',
   'Replicate, LLC invoice #Z4XJ1TTF-0002. "To quotesdone". One-time credit purchase, Qty 1 $20.00, '
   '"Amount paid -$20.00", "Amount remaining $0.00". No VAT line printed. Date basis as for -0001: '
   '"Due September 4, 2026", corroborated by the same-minute "Purchase successful" mail. Never forwarded.'),

  -- OPENROUTER. Already a booked QuotesDone vendor; these two receipts simply never got forwarded.
  -- The ledger holds nine OpenRouter charges and neither of these dates is among them.
  ('OpenRouter','Usage',10.80,'USD',date '2026-08-07',null,'gmail:19fdcff5975a9a7e',
   'OpenRouter, Inc receipt #1177-1854. "Amount paid $10.80", "Date paid Aug 7, 2026, 4:11:08 PM". '
   'OpenRouter Credits $10.80, payment method card 5057. No VAT line printed. Arrived in the '
   'founder''s Gmail inbox and was never forwarded; the 6 Aug and 10 Aug receipts either side of it were.'),
  ('OpenRouter','Usage',10.80,'USD',date '2026-06-08',null,'gmail:19ea83c25bb55707',
   'OpenRouter, Inc receipt #1512-7448. "Amount paid $10.80", "Date paid Jun 8, 2026, 5:14:54 PM". '
   'OpenRouter Credits $10.80, card 5057. No VAT line printed. This is the FIRST OpenRouter charge - '
   'the account''s welcome mail arrived four minutes earlier, 8 Jun 17:12:27Z. It was never forwarded, '
   'so the book''s OpenRouter history began a month late, on 1 Jul.'),

  -- GITHUB. A vendor the ledger had never seen. The receipt is headed "PERSONAL PURCHASE -
  -- ahmadmhdnabilalzain-bot", which is the account that OWNS the quotesdone repository and is the
  -- git identity on every commit in it, so the purchase is QuotesDone's build tooling.
  ('GitHub','Subscription',3.61,'USD',date '2026-08-12',null,'gmail:19ff71bb424e6e05',
   'GitHub, Inc. "GITHUB RECEIPT - PERSONAL PURCHASE - ahmadmhdnabilalzain-bot". Line item '
   '"GitHub Pro - month: $3.61 USD" for Aug 12 - Sep 8, 2026. "Total: $3.61 USD". Transaction '
   'ch_3U3fXUJFr6CCHwIi0n5HpKwt, charged to Visa 5057. NO VAT AMOUNT IS PRINTED - the only tax '
   'wording is the footnote "VAT/GST paid directly by GitHub, where applicable", which states no '
   'figure, so vat_amount is null rather than a split invented from a rate. Attributed to QuotesDone '
   'because ahmadmhdnabilalzain-bot is the owner of the quotesdone repository.'),

  -- GOOGLE PLAY / DROPBOX. The founder named July as missing and he was right; May was missing too.
  -- The 13 Jun and 13 Aug receipts of this same monthly series are already booked as vendor "Google",
  -- AED 26.99, VAT 1.29, so these two are the same subscription on the same card, not a new question.
  ('Google','Subscription',26.99,'AED',date '2026-05-13',1.29,'gmail:19e20d9879e17c01',
   'Google Play order GPA.3306-1807-2606-12909..9, merchant Dropbox, Inc., "Dropbox Simple" '
   'auto-renewing subscription. "Total: 26.99" in the AED symbol, "(Includes VAT of 1.29)" - the VAT '
   'is INSIDE the 26.99, read off the receipt. "Order date: 13 May 2026 14:19:42 GST", Visa 5057. '
   'Never forwarded. Same series as the already-booked 13 Jun and 13 Aug rows.'),
  ('Google','Subscription',26.99,'AED',date '2026-07-13',1.29,'gmail:19f5afd71db41bd0',
   'Google Play order GPA.3306-1807-2606-12909..11, merchant Dropbox, Inc., "Dropbox Simple". '
   '"Total: 26.99" AED, "(Includes VAT of 1.29)". "Order date: 13 Jul 2026 14:19:43 GST", Visa 5057. '
   'Never forwarded. THIS IS THE JULY GAP THE FOUNDER NAMED.'),

  -- RORK. Already a booked QuotesDone vendor - the ledger holds invoice XYGZ5CWF-0002 of 27 Jun.
  -- This is XYGZ5CWF-0001, the month before it, which was never forwarded.
  ('Rork','Subscription',20.00,'USD',date '2026-05-27',null,'gmail:19e69c0101adcffd',
   'Rork, Inc. receipt #2670-5289 (invoice XYGZ5CWF-0001), billed via Stripe. Plan "Junior" Qty 1 '
   '$20.00, "Total $20.00", "Amount paid $20.00", "Paid May 27, 2026", period May 27 - Jun 27 2026. '
   'No VAT line printed. The receipt also notes "Charged AED75.66 using 1 USD = 3.7828 AED"; the USD '
   'figure is the transacted amount and is what is booked, exactly as for XYGZ5CWF-0002. Never forwarded.'),

  -- GODADDY, 8 JUNE. The order that BOUGHT quotesdone.com and quotesdone.net. Unambiguously ours.
  ('GoDaddy','Subscription',246.18,'AED',date '2026-06-08',11.72,'gmail:19ea89ac094123d6',
   'GoDaddy order #4104080093, "Order number 4104080093 is complete". Line items: .COM Domain '
   'Registration quotesdone.com 1 Year AED 46.73; Full Domain Protection quotesdone.com 1 Year AED '
   '33.00; Microsoft 365 Email Essentials 1 Year AED 66.00; .NET Domain Registration quotesdone.net '
   '1 Year AED 55.73; Full Domain Protection quotesdone.net 1 Year AED 33.00. Subtotal AED 234.46 + '
   'tax AED 11.72 = AED 246.18. This is the founding purchase of the QuotesDone domains, so the '
   'entity is not in question. Never forwarded.'),

  -- GODADDY, 10 JUNE, order 4109275583. No domain is printed on any line, which would normally make
  -- this undecided. It is booked because the receipt itself prints the link: its Email Plus line says
  -- "Auto-renews on 10/07/2026 for 39.00 AED", and the ledger already holds GoDaddy order #4132924111
  -- of 10 Jul 2026 charging Microsoft 365 Email Plus at exactly AED 39.00 as a QuotesDone cost. The
  -- attribution is read off the two receipts together, not assumed from the vendor.
  ('GoDaddy','Subscription',103.25,'AED',date '2026-06-10',4.92,'gmail:19eb224e77524346',
   'GoDaddy order #4109275583, "Order number 4109275583 is complete". Line items 1 Month each: '
   'Microsoft 365 Email Plus AED 58.00 ("Auto-renews on 10/07/2026 for 39.00 AED"); Microsoft 365 '
   'Email Backup AED 9.00; Advanced Email Security AED 18.33; Email - Archiving AED 13.00. Subtotal '
   'AED 98.33 + tax AED 4.92 = AED 103.25. NO DOMAIN IS PRINTED on any line. Attributed to QuotesDone '
   'because the printed auto-renewal - 10/07/2026 at AED 39.00 for Email Plus - is exactly the '
   'already-booked GoDaddy order #4132924111 of 10 Jul 2026, whose Email Plus line is AED 39.00. This '
   'is the parent subscription of the monthly renewals the book already carries. Never forwarded.')
)
insert into public.expense_entries
  (vendor, category, amount, currency, charged_on, vat_amount, source, source_msg_id, note)
select c.vendor, c.category, c.amount, c.currency, c.charged_on, c.vat_amount,
       'receipt', c.source_msg_id, c.note
  from candidate c
 where not exists (select 1 from public.expense_entries e where e.source_msg_id = c.source_msg_id)
   and not exists (select 1 from public.expense_entries e
                    where e.vendor = c.vendor and e.charged_on = c.charged_on
                      and e.amount = c.amount and upper(e.currency) = upper(c.currency));

-- Post every entry that carries one of this file's keys and has no journal yet. fn_expense_post_to_gl
-- is itself idempotent (it returns the existing gl_journal id rather than posting twice), so this is
-- safe to re-run; the where-clause simply keeps it quiet.
select public.fn_expense_post_to_gl(e.id)
  from public.expense_entries e
 where e.source_msg_id in (
         'gmail:1a0584433eba619a','gmail:1a06dd7fb896ce07','gmail:19fdcff5975a9a7e',
         'gmail:19ea83c25bb55707','gmail:19ff71bb424e6e05','gmail:19e20d9879e17c01',
         'gmail:19f5afd71db41bd0','gmail:19e69c0101adcffd','gmail:19ea89ac094123d6',
         'gmail:19eb224e77524346')
   and not exists (select 1 from public.gl_journal g
                    where g.source = 'expense' and g.source_ref = e.id::text);

-- ---------------------------------------------------------------------------------------------
-- 3. WHAT WAS SEEN AND NOT BOOKED
-- ---------------------------------------------------------------------------------------------
-- in_ledger_scope: true = QuotesDone's. false = another entity's. NULL = UNDECIDED, which
-- fn_accountant_spend_report_coverage() names out loud so the total declares what it is missing.
insert into public.expense_vendor_billing_mailbox
  (vendor, mailbox, in_ledger_scope, first_seen, last_seen, evidence, note)
values
  -- Booked above; recorded so the register shows where these vendors actually bill.
  ('Replicate','founder Gmail inbox (ahmadmhdnabilalzain@gmail.com)', true,
   date '2026-08-31', date '2026-09-04',
   'Two invoices read: Replicate, LLC #Z4XJ1TTF-0001 $20.00 (31 Aug 2026) and #Z4XJ1TTF-0002 $20.00 '
   '(4 Sep 2026). Both print "To quotesdone" and "Amount paid -$20.00".',
   'QuotesDone: the invoices name the account "quotesdone". Booked 9 Sep 2026. Neither was ever '
   'forwarded to the accountant, which is why this vendor had never appeared in the ledger.'),
  ('GitHub','founder Gmail inbox (ahmadmhdnabilalzain@gmail.com)', true,
   date '2026-08-12', date '2026-08-12',
   'One receipt read: "GITHUB RECEIPT - PERSONAL PURCHASE - ahmadmhdnabilalzain-bot", GitHub Pro '
   'month $3.61 USD, 12 Aug 2026, transaction ch_3U3fXUJFr6CCHwIi0n5HpKwt.',
   'QuotesDone: ahmadmhdnabilalzain-bot owns the quotesdone repository and is the git identity on '
   'its commits. Booked 9 Sep 2026. Never forwarded.'),

  -- UNDECIDED. Seen, amount read, entity not establishable from the receipt.
  ('Suno','founder Gmail inbox (ahmadmhdnabilalzain@gmail.com)', null,
   date '2026-05-11', date '2026-06-11',
   'Two paid receipts read: #2779-8959-3255 (invoice NJCDQMWP-0001) $30.00 "Paid May 11, 2026", '
   'period May 11 - Jun 11; and #2855-6239-8138 (invoice NJCDQMWP-0002) $30.00 "Paid June 11, 2026", '
   'period Jun 11 - Jul 11. Both "Suno Premier" Qty 1, card 5057, no VAT line printed.',
   'UNDECIDED. A music generation subscription. Nothing on either receipt names a company, project '
   'or product line that ties it to QuotesDone, a procurement marketplace. Both went to the personal '
   'Gmail. Not booked; recorded so the spend report says it is missing rather than pretending it is zero.'),
  ('GoDaddy (order 4109276253)','founder Gmail inbox (ahmadmhdnabilalzain@gmail.com)', null,
   date '2026-06-10', date '2026-06-10',
   'One order read: #4109276253, 10 Jun 2026, "Order number 4109276253 is complete". Advanced Email '
   'Security AED 218.73 for 11.933 Months; Email - Archiving AED 155.13 for 11.933 Months. Subtotal '
   'AED 373.86 + tax AED 18.69 = AED 392.55. NO DOMAIN PRINTED on either line.',
   'UNDECIDED and HELD. Unlike its sibling order #4109275583 booked the same day, nothing in this '
   'order links it to a QuotesDone renewal: it prepays ~12 months of the SAME two products - Advanced '
   'Email Security and Email Archiving - that the already-booked GoDaddy monthly renewals of 10 Jul '
   'and 10 Aug charge MONTHLY at AED 18.33 and AED 16.00. A 12-month prepay and a monthly charge for '
   'the same product cannot both be this company''s, and the receipt does not say which mailbox or '
   'domain it covers. Booking it could double-count a cost the ledger already carries monthly.'),
  ('ADIB','founder Gmail inbox (ahmadmhdnabilalzain@gmail.com)', null,
   date '2026-07-11', date '2026-07-11',
   'One "ADIB Monthly VAT Invoice" read, 11 Jul 2026. NO AMOUNT, no invoice number and no date appear '
   'anywhere in the mail body. The mail states: "For additional security, your VAT Invoice is password '
   'protected... enter your first 4 letter of customer name followed by date of birth in MMYY format." '
   'Attachment CONSOLIDATED_TAX_INVOICE_ADIB_TAXINVOICE_34591033.pdf. AMOUNT NOT READ.',
   'UNDECIDED and HELD, for the same reason as the Outlook ADIB rows: the figures exist only inside a '
   'password-protected PDF whose password this seat does not hold. The mail is addressed "Dear '
   'Customer, AHMAD ALZAIN" - a named individual, no company. No amount is recorded here because none '
   'was read.'),

  -- NOT OURS. Read, attributed, and deliberately excluded.
  ('GoDaddy (order 4132040165, DORATAJEWELRIES.COM)','founder Gmail inbox (ahmadmhdnabilalzain@gmail.com)', false,
   date '2026-07-09', date '2026-07-09',
   'One renewal receipt read: #4132040165, 9 Jul 2026. .COM Domain Renewal DORATAJEWELRIES.COM 1 Year '
   'AED 85.73; Full Domain Protection DORATAJEWELRIES.COM 1 Year AED 55.00. Subtotal AED 140.73 + tax '
   'AED 7.04 = AED 147.77. "We have billed your Visa card ending with the last two digits: 57 for the '
   'amount of 147.77 AED."',
   'NOT QuotesDone. Every line item names DORATAJEWELRIES.COM, the jewellery business. Deliberately '
   'NOT booked - the same rule that held seven vendors in the Outlook mailbox on 9 Sep 2026.'),
  ('GoDaddy (order 4131262686, doratajewelries mailbox)','founder Gmail inbox (ahmadmhdnabilalzain@gmail.com)', false,
   date '2026-07-08', date '2026-07-08',
   'One renewal receipt read: #4131262686, 8 Jul 2026. Microsoft 365 Secure Business Professional - '
   'Renewal, 1 Year, AED 780.00, the item identified as management@doratajewelries.com. Subtotal AED '
   '780.00 + tax AED 39.00 = AED 819.00. "We have billed your Visa card ending with the last two '
   'digits: 57 for the amount of 819.00 AED."',
   'NOT QuotesDone. The line item names the management@doratajewelries.com mailbox - Dorata Jewelries '
   'FZCO''s own Microsoft 365 licence. Deliberately NOT booked. At AED 819.00 this is the single '
   'largest charge in the swept window, and booking it would have been the biggest single error '
   'available in this sweep.')
on conflict do nothing;

-- ---------------------------------------------------------------------------------------------
-- 4. WHAT WAS REFUSED AS "NOT A CHARGE", recorded here rather than in a table because a notice that
--    charges nothing has no amount, no date and no vendor relationship to register.
-- ---------------------------------------------------------------------------------------------
--   - Supabase billing-support "Monthly bill increased for your Supabase Organization", 11 Aug and
--     31 Aug 2026. Both read. They say a project "has just been opted in for" an add-on and quote a
--     RATE ("$15/month", "$60/month"), with "To get a full breakdown of your UPCOMING invoice...".
--     No total, no amount paid, no invoice number, no date. An upcoming invoice is not a charge.
--   - Supabase invoice #TLZLFZ-00002, 27 May 2026, $25.00: "Payment due May 27, 2026", button "View
--     invoice". No "Paid", no "Amount paid", no payment method, no receipt number. This is an UNPAID
--     invoice and is NOT booked. NOTE FOR THE NEXT SWEEP: no "Payment received" mail exists in any
--     read mailbox for TLZLFZ-00002 or for TLZLFZ-00003; the book's Supabase history starts at
--     TLZLFZ-00004 (27 Jun). Whether -00002 and -00003 were ever paid cannot be answered from mail.
--   - Resend upcoming-invoice@ "Your Resend subscription will renew soon", 8 Aug 2026. A reminder.
--   - GoDaddy "Congrats on your GoDaddy Microsoft 365 renewal!", 11 Aug 2026, from the MARKETING
--     sender donotreply@e.godaddy.com (not the transactional donotreply@godaddy.com). No order
--     number, no line items, no total - an add-on upsell carrying campaign tag Promotion_General.
--   - GoDaddy "Billing Failure: Save DORATAJEWELRY.COM", 6 Aug 2026. A FAILED payment, and for a
--     Dorata domain. Neither a charge nor ours.
--   - GoDaddy domain cancellation and expiry notices (12 Jul, 15 Jul, and the recurring "your
--     domains will expire" mails). No money moved.
--   - Apify "Your Apify subscription will renew automatically" and "Prepaid usage exceeded". Both
--     forward-looking; the actual Apify invoices are all booked already.
--   - Vercel weekly usage summaries and "$15 of $20 in monthly Pro plan credit". Usage against an
--     allowance already paid for, not a new charge.
--   - GitHub Actions "you have used 90%/100% of the included minutes". An allowance notice, no charge.
--   - Dubai Customs registration renewal notifications (19 Jul, 4 Aug, 18 Aug). No amount printed,
--     and customs registration is Dorata's; the Outlook sweep already holds this vendor UNDECIDED.
