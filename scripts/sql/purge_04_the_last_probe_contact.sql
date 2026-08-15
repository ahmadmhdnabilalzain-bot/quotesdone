-- PURGE 04 — the last of our own test data on a real company's row.
--
-- A broad demo/test scan over the 20,465 surviving leads returned 28 hits. TWENTY-SIX OF THEM ARE
-- REAL UAE COMPANIES, and deleting on that pattern would have destroyed real leads:
--
--   '%test%'  matched soil TESTing laboratories, INTERTEK TESTING, DUTEST INDUSTRIAL,
--             MATCON TESTING, "The LaTEST Technology", and "BRIGHTEST TRADING"
--   '%demo%'  matched six DEMOLITION contractors
--             (Liberty Building Demolition, Al Zelzal, JBR Tower Wrecking, Richmount, Marshal,
--              Al Ghaf Digging & Building Demolition)
--   also      "Amazon ATTESTation And Documents Clearing"
--
-- Testing/inspection is one of the company's own 66 knowledge packs
-- (QD-KB-065-testing-inspection-certification-and-technical-services) and demolition is a real
-- construction trade, so a keyword sweep over a supplier list will always hit them. The lesson is
-- the one this repo keeps relearning: check what an instrument actually matched before acting on
-- its count.
--
-- TWO rows carry data that is not the company's:
--
--   30466  MERIDIAN MEP CONTRACTING LLC — a real company, but the contact on it is OUR probe:
--          email ahmadmhdnabilalzain+qdprobe1@gmail.com, source 'qd_live_path_probe'. It is also
--          the row that still read registration_status='not_due' after the purge.
--   4128   TAME FLAME FIRE FIGHTING LLC DUBAI — a real company whose scraped email is the literal
--          placeholder info@yourcompany.example.com. Not our test data, but it is not a contact
--          either, and it will register as a false positive on every future demo scan.
--
-- The COMPANIES stay. Only the contact that is not theirs is removed. Deleting either row would
-- throw away a real UAE business because of what happened to be written in one column.

begin;

update leads
   set email  = null,
       source = 'qd_probe_contact_removed_15aug2026',
       registration_status = null
 where id = 30466
   and email = 'ahmadmhdnabilalzain+qdprobe1@gmail.com';

update leads
   set email = null
 where id = 4128
   and email ilike '%@yourcompany.example.com';

do $$
begin
  raise notice 'leads=% our_test_contacts_left=%',
    (select count(*) from leads),
    (select count(*) from leads
      where email ilike '%+qdprobe%' or email ilike '%@example.invalid'
         or email ilike '%@example.com' or source in ('demo_factory','qd_row4_verify','qd_live_path_probe')
         or tags && array['qd_demo']);
end $$;

commit;
