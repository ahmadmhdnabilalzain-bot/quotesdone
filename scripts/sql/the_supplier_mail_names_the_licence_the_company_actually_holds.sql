-- THE SUPPLIER MAIL NAMES THE LICENCE THE COMPANY ACTUALLY HOLDS (22 Sep 2026, audit DL-06).
--
-- SEAT: customer_support. One stored template, one line of it. No routine, no table, no grant.
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
-- NOT CHANGED: templates.email_customer, whose footer carries no licence claim at all
-- ('QuotesDone · Dubai, UAE'), and every other word of this template.
--
-- A REPLACE, NOT A REPASTE: the template is one 600px HTML document and only the footer line is
-- wrong. Re-pasting it here would make this file the owner of every other line of it too.
--
--   node scripts/apply_sql.mjs scripts/sql/the_supplier_mail_names_the_licence_the_company_actually_holds.sql --apply

update public.templates
   set content = replace(content,
        'QuotesDone &middot; Dubai, UAE &middot; Dubai DET E-Trader Licence 1633275',
        'QuotesDone Technologies &middot; Dubai, UAE &middot; DET Trader Licence No. 1633275 &middot; TDRA NOL-26-100000665')
 where name = 'email_supplier'
   and content like '%Dubai DET E-Trader Licence 1633275%';

-- The verdict as a ROW: the supplier wrapper names the trader licence and the TDRA permit, and the
-- retired class appears in no template.
select case when (select count(*) from public.templates
                   where name = 'email_supplier'
                     and content like '%DET Trader Licence No. 1633275 &middot; TDRA NOL-26-100000665%') = 1
             and (select count(*) from public.templates where content like '%E-Trader%') = 0
            then 'PROBE OK — the supplier footer names DET Trader Licence No. 1633275 and TDRA NOL-26-100000665; no template says E-Trader'
            else 'PROBE FAILED — supplier footer not corrected, or a template still says E-Trader: '
                 || (select string_agg(name, ', ') from public.templates where content like '%E-Trader%')
       end as probe_verdict;
