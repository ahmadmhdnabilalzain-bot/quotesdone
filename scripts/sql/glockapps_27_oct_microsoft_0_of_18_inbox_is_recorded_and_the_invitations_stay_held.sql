-- GLOCKAPPS 27 OCT 2026: MICROSOFT 0 OF 18 INBOX IS RECORDED, AND THE INVITATIONS STAY HELD (it_engineer, 27 Oct 2026).
--
-- Assigned: it_engineer. Founder instruction 1312: invitations resume only when a GlockApps test of the invitation sent
-- from supplier@quotesdone.com shows Outlook at 80% inbox or more. The result below was supplied by the founder for test
-- id:2026-10-27-09:33:53:634t. Its 112 seeds left through the Microsoft 365 lane between 09:46:19 and 11:02:02Z
-- (notifications kind 'invite_m365_seed', 112 rows, all status 'sent', measured).
--
-- WHERE IT IS RECORDED, AND WHY NOT AS NEW ROWS. public.invite_placement_check is the DAILY two-mailbox seed: primary key
-- dubai_day, and CHECK constraints pin gmail_to to the founder's Gmail and outlook_to to management@quotesdone.com. It
-- cannot hold one row per GlockApps provider without a schema change, and the automated GlockApps loop being built by
-- another agent (edge function deliverability_test) owns that change. So the result goes on the 27 Oct row's free-text
-- note column. The row's verdict ('inbox', from the in-tenant seed) is NOT touched: fn_invite_placement_gate reads it,
-- and it never decided the 1312 gate anyway (an unsigned in-tenant copy says nothing about external Outlook).
-- invite_enabled is not touched either: it reads 'false' and stays 'false'.
--
-- Data only, no DDL. Idempotent: each note is appended once, keyed on the GlockApps test id.

update public.invite_placement_check
   set note = concat_ws(E'\n', nullif(note, ''),
     'GlockApps id:2026-10-27-09:33:53:634t (founder-supplied, recorded by it_engineer 27 Oct 2026): 112 seeds via the M365 lane, 09:46-11:02Z. '
     || 'Per provider inbox/spam: Outlook US 0/8, Outlook.fr 0/1, Outlook.de 0/1, Hotmail 0/6, Exchange/Office365 0/2; '
     || 'ALL MICROSOFT 0/18 inbox, 18/18 spam (EOP verdict Spam, not phish). Gmail: all Promotions. Yahoo and AOL: all spam. '
     || 'Overall 39.6% inbox, 18.9% tabs, 36.9% spam, 4.6% missing. SPF, DKIM (selector1, d=quotesdone.com) and DMARC pass; sending IP on no blocklist. '
     || 'Ledger 1312 bar (Outlook >= 80% inbox): FAIL, invitations stay held. This row''s verdict is the in-tenant daily seed, not this test.')
 where dubai_day = date '2026-10-27'
   and coalesce(note, '') not like '%id:2026-10-27-09:33:53:634t%';

update public.founder_instruction
   set note = concat_ws(E'\n', nullif(note, ''), '27 Oct 2026 (it_engineer): GlockApps 27 Oct: Microsoft 0/18 inbox — FAIL; invitations stay held'),
       evidence = concat_ws(E'\n', nullif(evidence, ''),
         'it_engineer 27 Oct: GlockApps id:2026-10-27-09:33:53:634t, Outlook US 0/8, Outlook.fr 0/1, Outlook.de 0/1, Hotmail 0/6, Exchange/O365 0/2 inbox; '
         || 'Gmail all Promotions; Yahoo/AOL all spam; overall 39.6% inbox. invite_enabled=false. '
         || 'Diagnosis and fix plan: docs/reports/QuotesDone Campaign/GLOCKAPPS_27_OCT_RESULT_AND_FIX_PLAN.md'),
       updated_at = now()
 where id = 1312
   and coalesce(note, '') not like '%GlockApps 27 Oct: Microsoft 0/18 inbox%';

-- verdict row: both notes are present, the gate inputs are unchanged, and both invitation switches still read false
select case
  when (select note from public.invite_placement_check where dubai_day = date '2026-10-27') not like '%ALL MICROSOFT 0/18 inbox%'
    then 'PROBE FAILED: the 27 Oct invite_placement_check row does not carry the GlockApps result'
  when (select verdict from public.invite_placement_check where dubai_day = date '2026-10-27') <> 'inbox'
    then 'PROBE FAILED: the 27 Oct daily-seed verdict changed; this file must not touch it'
  when (select note from public.founder_instruction where id = 1312) not like '%GlockApps 27 Oct: Microsoft 0/18 inbox — FAIL; invitations stay held%'
    then 'PROBE FAILED: ledger 1312 does not carry the dated note'
  when (select status from public.founder_instruction where id = 1312) <> 'open'
    then 'PROBE FAILED: ledger 1312 is no longer open; the bar is not met'
  when (select value from public.app_secrets where key = 'invite_enabled') is distinct from 'false'
    then 'PROBE FAILED: invite_enabled is not false'
  when (select value from public.app_secrets where key = 'wa_supplier_invite_golive') is distinct from 'false'
    then 'PROBE FAILED: wa_supplier_invite_golive is not false'
  else 'PROBE OK' end as verdict;
