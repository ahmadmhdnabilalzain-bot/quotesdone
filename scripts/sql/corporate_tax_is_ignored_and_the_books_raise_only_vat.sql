-- CORPORATE TAX IS IGNORED; THE BOOKS RAISE ONLY VAT.
--
-- Assigned: accountant. Founder_instruction 344, verbatim: "just ignore the corporate tax matter for
-- companies". Ledger 983 (24 Sep 2026): Accountant gap 6 -- "make sure no duty raises it. VAT only."
--
-- WHAT WAS MEASURED (24 Sep 2026, production, read-only):
--   * No seat_duty's 'what' mentions corporate tax, and the only routines whose body does are fn_company_context
--     and fn_company_self_knowledge_sync, which print company_registration.corporate_tax_note into every seat's
--     company knowledge.
--   * That note still said: "...when revenue approaches the threshold the CFO opens a registration task." That
--     sentence instructs a seat to raise corporate tax, which instruction 344 rules out -- and there is no CFO.
--
-- WHAT THIS CHANGES: the note, so the knowledge every seat reads states the ruling. No routine changes.
--
-- prevented by: scripts/checks/accountant_duties_are_wired.test.mjs (no seat_duty and no fn_accountant_*
-- routine in the schema mirror raises corporate tax).

update public.company_registration
   set corporate_tax_note = 'Corporate Tax is ignored (founder ruling, instruction 344: "just ignore the corporate tax matter for companies"). '
                         || 'No seat raises, tracks, computes or asks about Corporate Tax. The accountant''s tax duty is VAT only: '
                         || 'registration is due at AED 375,000 of revenue and the VAT watch tells the CEO.'
 where corporate_tax_note is distinct from
       'Corporate Tax is ignored (founder ruling, instruction 344: "just ignore the corporate tax matter for companies"). '
    || 'No seat raises, tracks, computes or asks about Corporate Tax. The accountant''s tax duty is VAT only: '
    || 'registration is due at AED 375,000 of revenue and the VAT watch tells the CEO.';

select case when exists (select 1 from public.company_registration where corporate_tax_note ilike '%opens a registration task%')
            then 'PROBE FAILED: a registration note still tells a seat to raise corporate tax'
            else 'PROBE OK' end as verdict;
