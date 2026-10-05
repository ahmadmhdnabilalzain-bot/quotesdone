-- THE QUOTE AND DRAWING FILES ARE KEPT FIVE YEARS, AS THE TAX RECORD RULE REQUIRES.
--
-- Assigned: accountant. 6 Oct 2026. Founder ledger 1122, 1126, 1127 ("BOQs, drawings, photos, inquiry details, quotes,
-- comparison reports ... NEVER purged by the conversation retention job").
--
-- MEASURED (production, read-only, 6 Oct 2026): public.retention_policy says quote-files 1095 days ("Quotes - 3y") and
-- drawing-files 1095 days ("Customer drawings - 3y"). Cabinet Decision No. 74 of 2023 Art. 3(1)(b) (FTA text, read
-- 6 Oct 2026) requires records to be kept 5 years from the end of the calendar year of creation; a quote is the record
-- the reveal fee is computed on. Privacy policy 1.6 states "at least five years". A schedule that says 3 years is a
-- schedule that, once anything enforces it, deletes evidence the law requires. 1825 days + the calendar-year tail:
-- 2190 days (6 years) is the smallest whole-day number that always covers "5 years from the end of the year".
-- No routine that deletes by retention_policy.retention_days was found in this audit (grep of scripts/sql); this
-- corrects the schedule before one exists.
--   node scripts/apply_sql.mjs scripts/sql/the_quote_and_drawing_files_are_kept_five_years_as_the_tax_record_rule_requires.sql --apply --seat accountant

update public.retention_policy
   set retention_days = 2190,
       class = 'tax',
       notes = case bucket when 'quote-files' then 'Quotes - 5 years from the end of the year of creation (Cabinet Decision 74/2023 Art. 3), held as 2190 days'
                           else 'Customer drawings and BOQs - 5 years from the end of the year of creation (Cabinet Decision 74/2023 Art. 3), held as 2190 days' end
 where bucket in ('quote-files', 'drawing-files') and coalesce(retention_days, 0) < 2190;

select case when (select count(*) from public.retention_policy where bucket in ('quote-files', 'drawing-files') and retention_days >= 2190) = 2
            then 'PROBE OK: quote and drawing files are scheduled for at least 5 years after the year of creation'
            else 'PROBE FAILED: a quote or drawing schedule is under 2190 days' end as verdict;
