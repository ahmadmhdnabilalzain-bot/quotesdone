-- THE LICENCE WE NAME IS THE LICENCE WE HOLD (22 Sep 2026, audit DL-06).
--
-- SEAT: customer_support. One stored email template and two published FAQ answers. No routine, no
-- table, no grant. (Renamed from the_supplier_mail_... during review, before it was ever applied: the
-- subject is the licence class every surface prints, and the supplier footer was only the first one
-- found. One subject, one file.)
--
-- WHAT WAS WRONG. Every supplier email footer read:
--     QuotesDone · Dubai, UAE · Dubai DET E-Trader Licence 1633275
-- and its Arabic twin said «رخصة تاجر إلكتروني». The company's licence is a DET TRADER licence,
-- number 1633275 — supabase/functions/_shared/doc_template.ts has carried that correction since the
-- documents were fixed ("There is no 'E-Trader' licence"), the supplier agreement was reissued
-- without the words, and the PDFs print the TDRA permit NOL-26-100000665 beside it. The email footer,
-- which is what an unregistered supplier actually receives, was never corrected: it named a licence
-- class the DET does not issue to this company and omitted the TDRA permit entirely.
--
-- THE CORRECT LINE, the same one every PDF letterhead prints:
--     EN  QuotesDone Technologies · Dubai, UAE · DET Trader Licence No. 1633275 · TDRA NOL-26-100000665
--     AR  رخصة تاجر رقم 1633275 – دائرة الاقتصاد والسياحة في دبي
-- The Arabic is produced at send time by send_outbox/arabic_frame.ts, which translates the English
-- footer words of this template; that file and send_outbox/supplier_mail.ts (the text/plain part) are
-- corrected in the same change, and their tests were updated to pin the corrected string.
--
-- AND THE PUBLISHED FAQ SAID IT TOO (found by the independent review of this PR). company_faq ids 1
-- and 10 — English, public, approved — read "(E-Trader Licence No. 1633275)" and "DET E-Trader
-- Licence No. 1633275". Left alone, this change would have put the Arabic twin of id 10 (which says
-- رخصة تاجر) beside an English original naming a different licence class: one question, two answers.
-- Their embedding_gte is set to NULL so the re-embed rebuilds the vector from the corrected text: a
-- stale vector would keep answering from the old wording. AFTER APPLY, with the Arabic FAQ file:
--   node scripts/kb/embed_sales_knowledge.mjs --table=company_faq
-- one run covers these two English rows and the 128 new Arabic ones (it takes every row whose
-- embedding_gte is null, in any language).
--
-- NOT CHANGED: templates.email_customer, whose footer carries no licence claim at all
-- ('QuotesDone · Dubai, UAE'), and every other word of this template or those two answers.
--
-- A REPLACE, NOT A REPASTE: the template is one 600px HTML document and only the footer line is
-- wrong. Re-pasting it here would make this file the owner of every other line of it too.
--
--   node scripts/apply_sql.mjs scripts/sql/the_licence_we_name_is_the_licence_we_hold.sql --apply

update public.templates
   set content = replace(content,
        'QuotesDone &middot; Dubai, UAE &middot; Dubai DET E-Trader Licence 1633275',
        'QuotesDone Technologies &middot; Dubai, UAE &middot; DET Trader Licence No. 1633275 &middot; TDRA NOL-26-100000665')
 where name = 'email_supplier'
   and content like '%Dubai DET E-Trader Licence 1633275%';

update public.company_faq
   set answer = replace(answer, '(E-Trader Licence No. 1633275)', '(Trader Licence No. 1633275)'),
       embedding_gte = null, updated_at = now()
 where id = 1 and language = 'en' and answer like '%(E-Trader Licence No. 1633275)%';

update public.company_faq
   set answer = replace(answer, 'DET E-Trader Licence No. 1633275', 'DET Trader Licence No. 1633275'),
       embedding_gte = null, updated_at = now()
 where id = 10 and language = 'en' and answer like '%DET E-Trader Licence No. 1633275%';

-- The verdict as a ROW: the supplier wrapper names the trader licence and the TDRA permit, the
-- retired class appears in no template, and no published FAQ answer names it either.
select case when (select count(*) from public.templates
                   where name = 'email_supplier'
                     and content like '%DET Trader Licence No. 1633275 &middot; TDRA NOL-26-100000665%') = 1
             and (select count(*) from public.templates where content like '%E-Trader%') = 0
             and (select count(*) from public.company_faq where answer ilike '%E-Trader%' or question ilike '%E-Trader%') = 0
            then 'PROBE OK — the supplier footer names DET Trader Licence No. 1633275 and TDRA NOL-26-100000665; no template and no FAQ answer says E-Trader'
            else 'PROBE FAILED — supplier footer not corrected, or E-Trader survives in template(s) '
                 || coalesce((select string_agg(name, ', ') from public.templates where content like '%E-Trader%'), 'none')
                 || ' / company_faq id(s) '
                 || coalesce((select string_agg(id::text, ', ' order by id) from public.company_faq
                               where answer ilike '%E-Trader%' or question ilike '%E-Trader%'), 'none')
       end as probe_verdict;
