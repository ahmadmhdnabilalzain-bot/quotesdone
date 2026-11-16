-- THE PUBLIC ANSWERS SAY VERIFICATION IS AUTOMATIC, AND THE LICENCE NAMES THE COMPANY.
--
-- Assigned: sales_engineer (the supplier page and the site assistant). Agent: simplify_build_D, 16 Nov 2026. Founder ledgers
-- 1714/1715. Audit: scratchpad audit_simplify/STALE.md S3.
--
-- MEASURED (16 Nov 2026, SELECT on production): company_faq 39 "How long does verification take?" answers "Verification is
-- fast — up to a maximum of 3 working days once your documents are complete", its Arabic twin 619 the same, and the
-- onboarding policy (159, Arabic 786) "verification within a maximum of 3 working days". What the live flow does:
-- pricing_config.auto_approve_suppliers = true; the two real (non-ZZ) suppliers ever approved were approved by the
-- sales_engineer's automatic gate 3.7 and 5.4 minutes after their last document or acceptance (licence read to approval:
-- 2.3 and 7.6 minutes). The WhatsApp menu was corrected on 10 Nov 2026 (wa_inbound/menu.ts) with the sentence reused here.
-- RULINGS: 1681 (13 Nov) "the reader itself decides what is a trade licence ... no human hold"; 1672 (12 Nov) the name and
-- trade "extracted automatically from the company profile and the trade license". Supplier Agreement v18 clause 13 still
-- sets three working days as the outer limit; the answers keep that limit where they state a contractual term.
-- prevented by: the verdict row at the end of this file (it fails while any of the four rows still promises the old wait).
set local lock_timeout = '3s';

update public.company_faq set answer = replace(answer,
    'Verification is fast — up to a maximum of 3 working days once your documents are complete.',
    'Verification is automatic: each document is checked the moment it is saved.'), updated_at = now()
 where id = 39 and answer like 'Verification is fast — up to a maximum of 3 working days%';
update public.company_faq set answer = replace(answer,
    'التحقق سريع، وبحد أقصى 3 أيام عمل بمجرد اكتمال مستنداتك.',
    'يجري التحقق تلقائيًا فور حفظ كل مستند.'), updated_at = now()
 where id = 619 and answer like '%بحد أقصى 3 أيام عمل%';
update public.company_faq set answer = replace(answer,
    '(verification within a maximum of 3 working days; approval is automatic',
    '(verification is automatic, each document checked the moment it is saved; approval is automatic'), updated_at = now()
 where id = 159 and answer like '%verification within a maximum of 3 working days%';
update public.company_faq set answer = replace(answer,
    '(خلال 3 أيام عمل كحد أقصى؛ وتصدر الموافقة تلقائيًا',
    '(يجري التحقق تلقائيًا فور حفظ كل مستند؛ وتصدر الموافقة تلقائيًا'), updated_at = now()
 where id = 786 and answer like '%خلال 3 أيام عمل كحد أقصى%';

select case when exists (select 1 from public.company_faq where id in (39, 619, 159, 786)
                          and answer ~ '(maximum of 3 working days|3 أيام عمل)')
            then 'PROBE FAILED: a verification answer still promises up to 3 working days'
            else 'PROBE OK: the four verification answers say it is automatic' end as verdict;
