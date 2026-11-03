-- THE BILLS IN THE FOUNDER'S GMAIL THAT NEVER REACHED THE BOOKS.
-- Agent: accountant. 3 November 2026. Founder instruction 1538 (and 1545, his follow-up).
--
-- THE FOUNDER, 3 Nov 2026 (1538): "go through my emails and collect all bills and receipts and give it
-- to the accountant. all services included (ubicloud/namespace/github/godaddy/stripe/...etc. just ignore
-- suno and emastered." Then (1545): "many of those will be on my gmail account
-- (ahmadmhdnabilalzain@gmail.com) i have stopped forwarding bills to our expenses mail as i forgot".
--
-- WHAT WAS READ (3 Nov 2026)
--   * Gmail ahmadmhdnabilalzain@gmail.com, after:2026/01/01, per vendor and by catch-all receipt queries
--     (receipt / invoice / payment received / order / renewal / tax invoice / category:purchases). Every
--     candidate opened and its amount read off the body. Suno and eMastered excluded by his instruction.
--   * public.inbound_messages addressed to expenses@mail.quotesdone.com since 15 Sep 2026.
--   * NOT read: Outlook management@doratajewelries.com. The Outlook connector in this session is signed
--     in as supplier@quotesdone.com and returns ErrorInvalidUser for the Dorata mailbox. Anthropic's old
--     invoice series YXWTXUVD bills that mailbox; -0007 is booked below from its expenses@ forward.
--
-- WHAT WAS WRONG
--   1. The founder stopped forwarding in mid-September; 11 forwards that DID arrive were HELD by the
--      intake ("the model is held, so it is not booked on a guess; the accountant's queue replays it")
--      and nothing replayed them: inbound 161 (Anthropic Sep, USD 210), 163-171 (nine OpenAI API
--      fundings, 19-21 Sep), 172 (Google Play 13 Sep), 316+317 (GlockApps 5 Oct, one charge), 369
--      (GitHub 9 Oct, USD 684.68). No org_tasks row exists for any of them.
--   2. The latest receipt in expense_entries other than the OpenRouter meter was Vercel, 9 Oct.
--
-- WHAT THIS FILE DOES
--   1. Books 28 entries, 27 read off receipts and 1 month the founder states, guarded twice like
--      the_receipts_that_reached_the_inbox_and_were_never_forwarded.sql: by source_msg_id (a held forward
--      keeps its resend:<id> key, so a later replay of the same email is a no-op) AND by the economic
--      identity (vendor, charged_on, amount, currency).
--   2. Posts each through fn_expense_post_to_gl (Dr expense / VAT, Cr 1000).
--   3. Moves the ones paid on the founder's OWN card from 1000 to 2500 Due to Owner, one adjusting
--      journal each, the same 'bank_reconciliation' journal the_bank_account_holds_only_what_the_mashreq_
--      statement_shows.sql wrote. The card is read off each receipt: 5057 is the founder's Visa; 0841
--      is the company's Mashreq NEO BIZ debit card (inbound 316, a Mashreq alert naming it). A receipt
--      that prints no card follows ruling 1011: before 29 Sep the owner's card, from 29 Sep the company's.
--      Claude is NOT moved here: fn_accountant_owner_card_tick restates it at the AED 799 bank value.
--   4. ChatGPT August 2026, USD 200, booked on the founder's word (1538: "200 usd monthly for the last 3
--      months"). The three months are 29 Jul (receipt, AED 385, already booked), August (no receipt in any
--      mailbox) and 19 Sep (AED 799, already booked as his statement). The date 19 Aug is his own billing
--      day from the ruling of 24 Sep ("ChatGPT ~19th"); it is a convention, not a printed date.
--
-- WHAT IT DOES NOT DO
--   * OpenRouter top-ups from 7 Oct are NOT booked: from that day the books carry OpenRouter as metered
--     daily usage (source accountant:openrouter_daily); booking the top-ups too would count it twice.
--     The 24 Sep top-up (USD 10.80) predates the meter and is booked.
--   * Mashreq's November fee is not booked: the October statement books it (the bank route, ruling 369).
--   * Undecided items are not booked: Tripo AI/API, MVSEP, Topaz Labs, Google Cloud USD 5, DigitalOcean,
--     Postiz, Dropbox Jan-Apr 2026, Supabase invoice TLZLFZ-00002, the Tasjeel AED 52.50 refunded to
--     account credit, ADIB (password-protected). They are in docs/reports/expenses_statement_2026/.
--   * Vercel's refunds of USD 0.06 and 0.07 (22 Oct) are not booked: fn_expense_post_to_gl posts no
--     amount <= 0. Immaterial (AED 0.48).

with candidate(vendor, category, amount, currency, charged_on, vat_amount, source, doc_kind, doc_note, source_msg_id, owner_card, note) as (
  values
  -- ANTHROPIC. Sep: the old series on the owner's card (forward held as inbound 161). Oct: a new account
  -- (invoice series IRGYVYFE) on the company card, billed in AED.
  ('Anthropic','Subscription',210.00,'USD',date '2026-09-23',10.00,'receipt',null::text,null::text,'resend:0fdcd5b9-4a46-4d7d-9c51-a790af8b2115',false,
   'Anthropic, PBC receipt 2830-8951-2948 (invoice YXWTXUVD-0007), "Paid September 23, 2026", Max plan 20x Sep 23 - Oct 23 2026, $200.00 + VAT UAE 5% $10.00 = $210.00, Visa 5057 (owner). Forwarded to expenses@ 23 Sep (inbound 161) and HELD by the intake. fn_accountant_owner_card_tick restates it at AED 799 to 2500.'),
  ('Anthropic','Subscription',775.01,'AED',date '2026-10-19',36.91,'receipt',null,null,'gmail:1a157233244c6a4a',false,
   'Anthropic, PBC receipt 2901-3918-5415 (invoice IRGYVYFE-0001), Max plan 20x Oct 19 - Nov 19 2026, AED 738.10 + VAT 36.91 = AED 775.01, card 0841 (company Mashreq). In Gmail, never forwarded.'),

  -- OPENAI API. Ten fundings of the API credit balance, all "credit card ending in 5057" (owner).
  ('OpenAI','Usage',10.50,'USD',date '2026-09-19',null,'receipt',null,null,'resend:6817002c-ce8f-4373-a605-1a6a6c34db99',true,'OpenAI "Your OpenAI API account has been funded", Sep 19 2026 11:28: "We charged $10.50 to your credit card ending in 5057". Forward held as inbound 163.'),
  ('OpenAI','Usage',6.41,'USD',date '2026-09-19',null,'receipt',null,null,'resend:5c485805-8ef2-499f-9e5d-9b45dbfa106d',true,'OpenAI API funded, Sep 19 2026 12:51: $6.41, card 5057. Forward held as inbound 164.'),
  ('OpenAI','Usage',5.27,'USD',date '2026-09-19',null,'receipt',null,null,'resend:2aed15a7-c867-4bec-b3fe-0b30710a5713',true,'OpenAI API funded, Sep 19 2026 13:09: $5.27, card 5057. Forward held as inbound 165.'),
  ('OpenAI','Usage',5.82,'USD',date '2026-09-20',null,'receipt',null,null,'resend:e694d394-c918-49cd-b100-6be139d7d826',true,'OpenAI API funded, Sep 20 2026 00:38: $5.82, card 5057. Forward held as inbound 166.'),
  ('OpenAI','Usage',5.49,'USD',date '2026-09-20',null,'receipt',null,null,'resend:b84a6468-f28e-44ba-8bc4-867e4be87dd5',true,'OpenAI API funded, Sep 20 2026 01:36: $5.49, card 5057. Forward held as inbound 167 (original gmail:1a0bc74c49383100).'),
  ('OpenAI','Usage',5.84,'USD',date '2026-09-20',null,'receipt',null,null,'resend:b8b7d17b-6e89-4635-aa88-3a8840f8650d',true,'OpenAI API funded, Sep 20 2026 19:40: $5.84, card 5057. Forward held as inbound 168.'),
  ('OpenAI','Usage',5.78,'USD',date '2026-09-20',null,'receipt',null,null,'resend:c7731ece-06ca-4d64-830e-62e38ab90d89',true,'OpenAI API funded, Sep 20 2026 21:49: $5.78, card 5057. Forward held as inbound 169.'),
  ('OpenAI','Usage',6.04,'USD',date '2026-09-20',null,'receipt',null,null,'resend:ed3b6452-2011-425c-a173-cf8b2e3c5ee6',true,'OpenAI API funded, Sep 20 2026 22:16: $6.04, card 5057. Forward held as inbound 170.'),
  ('OpenAI','Usage',10.50,'USD',date '2026-09-21',null,'receipt',null,null,'resend:e0efca20-4f8c-494f-9968-b6d1cd85960e',true,'OpenAI API funded, Sep 21 2026 08:24: $10.50, card 5057. Forward held as inbound 171 (original gmail:1a0c31168ca1c609).'),
  ('OpenAI','Usage',10.50,'USD',date '2026-09-26',null,'receipt',null,null,'gmail:1a0db2fe04b6e6f4',true,'OpenAI API funded, Sep 26 2026: $10.50, card 5057. In Gmail, never forwarded.'),

  -- CHATGPT AUGUST, on the founder's word.
  ('OpenAI','Subscription',200.00,'USD',date '2026-08-19',null,'founder_reported','founder_statement',
   'receipt not in any mailbox; founder 3 Nov 2026 (instruction 1538): "chatgpt subscription (200 usd monthly for the last 3 months, won''t happen anymore as i stopped it)". Date is his billing day from the 24 Sep ruling (~19th).',
   'founder:1538:chatgpt:2026-08',true,
   'ChatGPT Pro, August 2026, USD 200 as stated by the founder (1538). The other two of his three months are booked: 29 Jul AED 385 (receipt, preferred over the stated figure) and 19 Sep AED 799 (his statement of 24 Sep). Owner''s card (before 29 Sep): moved to 2500.'),

  -- OPENROUTER, the one top-up before the daily meter began on 7 Oct. Company card 0841.
  ('OpenRouter','Usage',10.80,'USD',date '2026-09-24',null,'receipt',null,null,'gmail:1a0d2e81229becc1',false,
   'OpenRouter, Inc receipt 1382-2095, Sep 24 2026, credits $10.80, card 0841 (company). Booked because it predates the metered daily ledger of 7 Oct; later top-ups are not booked (the meter books the usage).'),

  -- SUPABASE. No card printed. 00007 before the 29 Sep switch (owner); 00009 and 00010 after (company).
  ('Supabase','Usage',72.36,'USD',date '2026-09-27',null,'receipt',null,null,'gmail:1a0e3495f2df81af',true,'Supabase Pte. Ltd. "Payment received" invoice TLZLFZ-00007, paid Sep 27 2026, $72.36. No card printed; before 29 Sep, so the owner''s card (ruling 1011).'),
  ('Supabase','Usage',21.44,'USD',date '2026-10-12',null,'receipt',null,null,'gmail:1a1311e4f8203d12',false,'Supabase Pte. Ltd. "Payment received" invoice TLZLFZ-00009, paid Oct 12 2026, $21.44 (mid-cycle; -00008 is in no mailbox). No card printed; after 29 Sep, so the company account (ruling 1011).'),
  ('Supabase','Usage',131.16,'USD',date '2026-10-27',null,'receipt',null,null,'gmail:1a17c8dbca648b40',false,'Supabase Pte. Ltd. "Payment received" invoice TLZLFZ-00010, paid Oct 27 2026, $131.16. No card printed; company account (ruling 1011).'),

  -- GITHUB, 9 Oct. Forward held as inbound 369. Mostly Actions minutes for September.
  ('GitHub','Usage',684.68,'USD',date '2026-10-09',null,'receipt',null,null,'resend:83a048cb-6bbe-48ec-9c41-c7030215c233',true,
   'GitHub, Inc. receipt, transaction ch_3UOlShJFr6CCHwIi1svlgu9H, Oct 9 2026, $684.68: GitHub Actions usage Sep 1 - Sep 30 2026 $670.68, plus plan lines. Visa 5057 (owner). A "problem billing your account" mail came 5 minutes before. Forward held as inbound 369.'),

  -- GODADDY, 10 Oct renewal of the supplier@quotesdone.com mailbox services. Card ending 41 (company).
  ('GoDaddy','Subscription',93.80,'AED',date '2026-10-10',4.47,'receipt',null,null,'gmail:1a12783d752a511f',false,
   'GoDaddy renewal order #7038032441, Oct 10 2026, 1 month: Microsoft 365 Email Plus, Advanced Email Security, Email Archiving; tax 4.47; total AED 93.80. "Visa card ending with the last two digits: 41" (company 0841). Same series as the booked 10 Jul / 10 Aug / 10 Sep renewals.'),

  -- GOOGLE PLAY / DROPBOX, owner's card 5057. Same series as the booked May-Aug rows.
  ('Google','Subscription',26.99,'AED',date '2026-09-13',1.29,'receipt',null,null,'resend:4973c87e-a028-4128-b0bd-ffd8a0a375cc',true,'Google Play order GPA.3306-1807-2606-12909..13, Dropbox Simple, 13 Sep 2026, AED 26.99 incl VAT 1.29, Visa 5057. Forward held as inbound 172.'),
  ('Google','Subscription',26.99,'AED',date '2026-10-13',1.29,'receipt',null,null,'gmail:1a134c67dde065d6',true,'Google Play order GPA.3306-1807-2606-12909..14, Dropbox Simple, 13 Oct 2026, AED 26.99 incl VAT 1.29, Visa 5057 (owner). In Gmail, never forwarded.'),

  -- RESEND, TWILIO, UBICLOUD, NAMESPACE.
  ('Resend','Subscription',20.00,'USD',date '2026-10-15',null,'receipt',null,null,'gmail:1a14195dcc2da029',false,'Resend receipt 2417-9707 (invoice QOGH46KN-0005), Transactional Pro Oct 15 - Nov 15 2026, $20.00 (charged AED 76.40), card 0841 (company).'),
  ('Twilio','Usage',10.01,'USD',date '2026-10-05',null,'receipt',null,null,'gmail:1a10be90ab9e253c',false,'Twilio auto-recharge, transaction CXa9e1670b1190b2b120102147bfbbd1c4, Oct 5 2026, $10.01, card 0841 (company).'),
  ('Ubicloud','Usage',40.33,'USD',date '2026-10-02',null,'receipt',null,null,'gmail:1a0fc537de84b385',false,'Ubicloud September 2026 invoice #2609-3ae8a0e0a3-0001, $40.33 (managed CI runners), charged to the card on file; dated by the invoice email (2 Oct). Card not printed; company account (ruling 1011).'),
  ('Namespace','Subscription',100.00,'USD',date '2026-10-21',null,'receipt',null,null,'gmail:1a15f60fe9d64e6a',false,'Namespace receipt 2821-8040 (invoice AQTRGJBS-0001), Team plan Oct 21 - Nov 21 2026, $100.00 (charged AED 381.95), card 0841 (company).'),

  -- GLOCKAPPS (inbox-placement tests). Two orders, billed to "quotesdone technologies".
  ('GlockApps','Subscription',65.74,'AED',date '2026-10-05',null,'receipt',null,null,'resend:eb6f6fd4-ee92-48ac-bfa6-95981f8f8899',false,'2Checkout / GLOCKSOFT LLC order 279756930 (invoice BV106977362), 5 Oct 2026, grand total AED 65.74, Visa/MasterCard 0841 (company); the Mashreq alert (inbound 316) shows the same AED 65.74. Forward held as inbound 317.'),
  ('GlockApps','Subscription',65.50,'AED',date '2026-11-01',3.12,'receipt',null,null,'gmail:1a1988ac33bc052b',true,'2Checkout / GLOCKSOFT LLC order 280768225 (invoice BV107675817), 1 Nov 2026, Glock Apps Credits Pack 1 AED 62.38 + VAT 3.12 = AED 65.50, Visa/MasterCard 5057 (owner). Billed to quotesdone technologies.'),

  -- TASJEEL: mail hosting for ahmad@666realestate.ae, the founder's deliverability-test address (1544).
  ('Tasjeel.ae','Subscription',31.50,'AED',date '2026-10-27',1.50,'receipt',null,null,'gmail:1a17dcdab7167a2c',false,'Tasjeel.ae receipt TJ468022 (invoice 523590), Personal Email hosting 666realestate.ae, 27 Oct 2026, AED 30.00 + VAT 1.50 = AED 31.50. QuotesDone: founder instruction 1544 says that address is his and was used for deliverability scoring. Card not printed; company account (ruling 1011).')
),
ins as (
  insert into public.expense_entries
    (vendor, category, amount, currency, charged_on, vat_amount, source, doc_kind, doc_note, source_msg_id, note)
  select c.vendor, c.category, c.amount, c.currency, c.charged_on, c.vat_amount, c.source, c.doc_kind, c.doc_note, c.source_msg_id, c.note
    from candidate c
   where not exists (select 1 from public.expense_entries e where e.source_msg_id = c.source_msg_id)
     and not exists (select 1 from public.expense_entries e
                      where lower(e.vendor) like lower(c.vendor) || '%' and e.charged_on = c.charged_on
                        and e.amount = c.amount and upper(e.currency) = upper(c.currency))
  returning id
)
select count(*) as inserted from ins;

-- Post every entry this file owns that has no journal yet (fn_expense_post_to_gl is itself idempotent).
select public.fn_expense_post_to_gl(e.id)
  from public.expense_entries e
 where e.source_msg_id in (
   'resend:0fdcd5b9-4a46-4d7d-9c51-a790af8b2115','gmail:1a157233244c6a4a',
   'resend:6817002c-ce8f-4373-a605-1a6a6c34db99','resend:5c485805-8ef2-499f-9e5d-9b45dbfa106d','resend:2aed15a7-c867-4bec-b3fe-0b30710a5713',
   'resend:e694d394-c918-49cd-b100-6be139d7d826','resend:b84a6468-f28e-44ba-8bc4-867e4be87dd5','resend:b8b7d17b-6e89-4635-aa88-3a8840f8650d',
   'resend:c7731ece-06ca-4d64-830e-62e38ab90d89','resend:ed3b6452-2011-425c-a173-cf8b2e3c5ee6','resend:e0efca20-4f8c-494f-9968-b6d1cd85960e',
   'gmail:1a0db2fe04b6e6f4','founder:1538:chatgpt:2026-08','gmail:1a0d2e81229becc1',
   'gmail:1a0e3495f2df81af','gmail:1a1311e4f8203d12','gmail:1a17c8dbca648b40',
   'resend:83a048cb-6bbe-48ec-9c41-c7030215c233','gmail:1a12783d752a511f',
   'resend:4973c87e-a028-4128-b0bd-ffd8a0a375cc','gmail:1a134c67dde065d6',
   'gmail:1a14195dcc2da029','gmail:1a10be90ab9e253c','gmail:1a0fc537de84b385','gmail:1a15f60fe9d64e6a',
   'resend:eb6f6fd4-ee92-48ac-bfa6-95981f8f8899','gmail:1a1988ac33bc052b','gmail:1a17dcdab7167a2c')
   and not exists (select 1 from public.gl_journal g where g.source = 'expense' and g.source_ref = e.id::text);

-- The owner's card paid these: move each posted credit from 1000 Cash & Bank to 2500 Due to Owner, once.
select public.fn_gl_entry(j.entry_date,
         'Bank reconciliation: journal ' || j.id || ' was paid on the founder''s personal card, not the Mashreq account; moved from Cash & Bank to Due to Owner',
         'bank_reconciliation', j.id::text,
         jsonb_build_array(jsonb_build_object('account','1000','debit',l.credit),
                           jsonb_build_object('account','2500','credit',l.credit)), 'accountant')
  from public.expense_entries e
  join public.gl_journal j on j.source = 'expense' and j.source_ref = e.id::text and j.status = 'posted'
  join public.gl_journal_lines l on l.journal_id = j.id and l.account_code = '1000' and l.credit > 0
 where e.source_msg_id in (
   'resend:6817002c-ce8f-4373-a605-1a6a6c34db99','resend:5c485805-8ef2-499f-9e5d-9b45dbfa106d','resend:2aed15a7-c867-4bec-b3fe-0b30710a5713',
   'resend:e694d394-c918-49cd-b100-6be139d7d826','resend:b84a6468-f28e-44ba-8bc4-867e4be87dd5','resend:b8b7d17b-6e89-4635-aa88-3a8840f8650d',
   'resend:c7731ece-06ca-4d64-830e-62e38ab90d89','resend:ed3b6452-2011-425c-a173-cf8b2e3c5ee6','resend:e0efca20-4f8c-494f-9968-b6d1cd85960e',
   'gmail:1a0db2fe04b6e6f4','founder:1538:chatgpt:2026-08','gmail:1a0e3495f2df81af',
   'resend:83a048cb-6bbe-48ec-9c41-c7030215c233','resend:4973c87e-a028-4128-b0bd-ffd8a0a375cc','gmail:1a134c67dde065d6',
   'gmail:1a1988ac33bc052b')
   and not exists (select 1 from public.gl_journal x where x.source = 'bank_reconciliation' and x.source_ref = j.id::text);

-- Claude: the hourly duty restates the month at the AED 799 bank value (owner's card for September).
select public.fn_accountant_owner_card_tick();

-- The verdict. Writes nothing; reads what the file booked.
with mine as (
  select e.id, e.source_msg_id from public.expense_entries e
   where e.source_msg_id in (
   'resend:0fdcd5b9-4a46-4d7d-9c51-a790af8b2115','gmail:1a157233244c6a4a',
   'resend:6817002c-ce8f-4373-a605-1a6a6c34db99','resend:5c485805-8ef2-499f-9e5d-9b45dbfa106d','resend:2aed15a7-c867-4bec-b3fe-0b30710a5713',
   'resend:e694d394-c918-49cd-b100-6be139d7d826','resend:b84a6468-f28e-44ba-8bc4-867e4be87dd5','resend:b8b7d17b-6e89-4635-aa88-3a8840f8650d',
   'resend:c7731ece-06ca-4d64-830e-62e38ab90d89','resend:ed3b6452-2011-425c-a173-cf8b2e3c5ee6','resend:e0efca20-4f8c-494f-9968-b6d1cd85960e',
   'gmail:1a0db2fe04b6e6f4','founder:1538:chatgpt:2026-08','gmail:1a0d2e81229becc1',
   'gmail:1a0e3495f2df81af','gmail:1a1311e4f8203d12','gmail:1a17c8dbca648b40',
   'resend:83a048cb-6bbe-48ec-9c41-c7030215c233','gmail:1a12783d752a511f',
   'resend:4973c87e-a028-4128-b0bd-ffd8a0a375cc','gmail:1a134c67dde065d6',
   'gmail:1a14195dcc2da029','gmail:1a10be90ab9e253c','gmail:1a0fc537de84b385','gmail:1a15f60fe9d64e6a',
   'resend:eb6f6fd4-ee92-48ac-bfa6-95981f8f8899','gmail:1a1988ac33bc052b','gmail:1a17dcdab7167a2c'))
select case
  when (select count(*) from mine) <> 28 then 'PROBE FAILED: expected 28 entries, found ' || (select count(*) from mine)
  when exists (select 1 from mine m where not exists (select 1 from public.gl_journal g where g.source = 'expense' and g.source_ref = m.id::text and g.status = 'posted'))
       then 'PROBE FAILED: an entry has no posted expense journal'
  when (select count(*) from mine m join public.gl_journal g on g.source = 'expense' and g.source_ref = m.id::text
         join public.gl_journal x on x.source = 'bank_reconciliation' and x.source_ref = g.id::text) <> 16
       then 'PROBE FAILED: expected 16 owner-card moves to 2500'
  else 'PROBE OK: 28 entries posted, 16 moved to Due to Owner'
end as verdict;
