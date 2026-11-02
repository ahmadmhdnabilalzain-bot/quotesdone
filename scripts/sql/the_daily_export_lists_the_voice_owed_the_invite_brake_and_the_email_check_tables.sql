-- THE DAILY EXPORT LISTS THE VOICE-OWED, INVITE-BRAKE AND EMAIL-CHECK TABLES (2 Nov 2026; seat: it_engineer).
--
-- Three public tables were created without the registry row public.table_export_registry asks every table-creating
-- PR to carry, so main's `checks` job failed "every public table is exported every day or excluded with a reason"
-- (scripts/checks/every_table_is_exported_or_explicitly_excluded.test.mjs, run 41355966206 on main):
--   customer_support_voice_owed  (scripts/sql/customer_support_writes_its_duty_updates_through_the_model.sql)
--   invite_brake                 (scripts/sql/an_invitation_goes_only_to_a_checked_mailbox_and_a_bounce_brake_restarts_itself.sql)
--   lead_email_check             (the same file)
-- All three hold records the company acts on (a message owed to a person, the reason supplier invitations stopped,
-- the verdict on a lead's mailbox), so they are exported, not excluded.

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('customer_support_voice_owed', true, 'customer_support', 'a message customer_support still owes a customer or supplier: its draft, situation and the attempts made to write it in the seat''s voice', 'it_engineer'),
  ('invite_brake', true, 'deliverability', 'each stop of the supplier invitations and the reason it stopped, with when and how it was restarted (ledger 1449)', 'it_engineer'),
  ('lead_email_check', true, 'deliverability', 'the verdict on each lead''s mailbox (verified, rejected, retry) that decides whether an invitation may be sent to it', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

select case when (select count(*) from public.fn_table_export_list() t
                   where t::text ~ '(customer_support_voice_owed|invite_brake|lead_email_check)') = 3
            then 'PROBE OK all three tables are in fn_table_export_list(), ' || (select count(*) from public.table_export_registry where exported) || ' exported'
            else 'PROBE FAILED: not all of customer_support_voice_owed, invite_brake, lead_email_check are in fn_table_export_list()' end as verdict;
