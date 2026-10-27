-- THE INTERNAL TEST EMAIL IS DROPPED, AND THE WARM-UP IS COMPRESSED (it_engineer, 27 Oct 2026).
--
-- Assigned: it_engineer. Two dated notes, relayed by the coordinator on 27 Oct 2026:
--   ledger 1314: the internal management@ -> supplier@ test email is DROPPED. It cannot be sent from this estate (no path
--     sends as management@), and the GlockApps test of 27 Oct already measured the same mail at 111 external seeds.
--     It is no longer a warm-up prerequisite.
--   ledger 1313: the founder, 27 Oct: "do the warm up immediately after the fix. we cant wait for a week". Day 0 ran at
--     15:16Z (supplier@ -> 5 of the founder's own mailboxes, he is replying). Days 1-3 are Wed 28 to Fri 30 Oct; the
--     GlockApps re-test (last credit) is Fri 30 Oct. Plan: docs/reports/QuotesDone Campaign/SUPPLIER_WARMUP_PLAN_27_OCT.md
-- Statuses are not changed (notes only). Data only, no DDL. Idempotent: each note is appended once.
-- invite_enabled and wa_supplier_invite_golive are not touched and read 'false'.

update public.founder_instruction
   set note = concat_ws(E'\n', nullif(note, ''),
         '27 Oct 2026 (it_engineer, relayed by the coordinator): the internal test email is DROPPED. It cannot be sent from this estate, and GlockApps id:2026-10-27-09:33:53:634t already covered it. No longer a warm-up prerequisite.'),
       updated_at = now()
 where id = 1314
   and coalesce(note, '') not like '%internal test email is DROPPED%';

update public.founder_instruction
   set note = concat_ws(E'\n', nullif(note, ''),
         '27 Oct 2026 (it_engineer): COMPRESSED on the founder''s word ("we cant wait for a week"). Day 0 ran 27 Oct 15:16Z (supplier@ -> his 5 mailboxes; he replies). Ramp Wed 28 (~10), Thu 29 (~15), Fri 30 Oct (~20) person-to-person; GlockApps re-test with the last credit Fri 30 Oct. The 1314 test email is dropped.'),
       updated_at = now()
 where id = 1313
   and coalesce(note, '') not like '%COMPRESSED on the founder%';

select case
  when (select note from public.founder_instruction where id = 1314) not like '%internal test email is DROPPED%'
    then 'PROBE FAILED: ledger 1314 does not carry the note'
  when (select note from public.founder_instruction where id = 1313) not like '%COMPRESSED on the founder%'
    then 'PROBE FAILED: ledger 1313 does not carry the note'
  when (select value from public.app_secrets where key = 'invite_enabled') is distinct from 'false'
    then 'PROBE FAILED: invite_enabled is not false'
  when (select value from public.app_secrets where key = 'wa_supplier_invite_golive') is distinct from 'false'
    then 'PROBE FAILED: wa_supplier_invite_golive is not false'
  else 'PROBE OK' end as verdict;
