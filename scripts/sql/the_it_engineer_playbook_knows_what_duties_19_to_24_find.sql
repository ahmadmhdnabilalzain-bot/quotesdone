-- THE IT ENGINEER'S PLAYBOOK KNOWS WHAT DUTIES 19-24 FIND.
--
-- Assigned: it_engineer. 14 Sep 2026.
--
-- Founder, 14 Sep 2026, approving IT duties 19-24 ("add all for accountant and IT"). Duty 21 says the mail
-- findings "go to the playbook"; the others are recorded there for the same reason: a failure class with
-- no playbook row is a finding nobody has decided how to answer.
--
-- THE PLAYBOOK IS public.it_playbook (every_new_bug_leaves_a_playbook_entry_a_check_and_an_incident_record.sql):
-- per failure class, the issue keys it covers, its remedy - and the zero-argument routine that applies it,
-- if one exists - or why it cannot be automated, and the check that fails if it comes back. This file only
-- adds rows. None names a remedy_routine: no remedy here is a routine the IT engineer can run on its own,
-- and a playbook that names one it cannot run would be worse than a plain sentence.
--
-- WHICH KEYS. The sender rows cover the issue keys duty 10 raises (fn_it_duties_scheduled, 'duty:sender:');
-- duty 21's weekly mail check IS duty 10's daily one, so it adds no second check, only these rows. The rest
-- cover the files of duties 19, 20, 22, 23 and 24.
--
-- DNS. On 14 Sep 2026 app_secrets held no credential for the domain's DNS host (the keys were read by name),
-- so no seat can change a DNS record: those classes say so, and go round the IT loop to the founder.

insert into public.it_playbook (failure_class, issue_prefix, remedy, remedy_routine, not_automatable_reason, regression_check, added_by) values
  ('sender_spf', 'duty:sender:spf:', null, null,
   'The SPF record is changed at the domain''s DNS host, and no seat holds that account. Resend re-checks the domain itself once it is fixed.',
   'scripts/checks/it_engineer_duties_9_to_18.test.mjs', 'it_engineer'),
  ('sender_dmarc', 'duty:sender:dmarc:', null, null,
   'The DMARC record is changed at the domain''s DNS host, and no seat holds that account.',
   'scripts/checks/it_engineer_duties_9_to_18.test.mjs', 'it_engineer'),
  ('sender_dkim', 'duty:sender:dkim:', null, null,
   'The DKIM key Resend issues is published at the domain''s DNS host, and no seat holds that account.',
   'scripts/checks/it_engineer_duties_9_to_18.test.mjs', 'it_engineer'),
  ('sender_resend_domain', 'duty:sender:resend_domain', null, null,
   'Resend verifies the domain from its DNS records; the records are changed at the DNS host, which no seat holds.',
   'scripts/checks/it_engineer_duties_9_to_18.test.mjs', 'it_engineer'),
  ('sender_blocklist', 'duty:sender:blocklist:', null, null,
   'A listing is removed at the list''s own site after its cause is fixed; no list offers a delisting API a seat can call.',
   'scripts/checks/it_engineer_duties_19_to_24.test.mjs', 'it_engineer'),
  ('sender_bounce_rate', 'duty:sender:bounce_rate',
   'resend_webhook already suppresses every hard-bounced address, so no bounced address is mailed again and the rate falls as the week rolls on; customer_support reviews the list those sends went to.',
   null, null, 'scripts/checks/it_engineer_duties_9_to_18.test.mjs', 'it_engineer'),
  ('sender_complaint_rate', 'duty:sender:complaint_rate',
   'resend_webhook already suppresses every address that complained; customer_support reviews what was sent to them and why.',
   null, null, 'scripts/checks/it_engineer_duties_9_to_18.test.mjs', 'it_engineer'),
  ('whatsapp_quality', 'duty:sender:whatsapp_quality', null, null,
   'Meta sets the WhatsApp number''s quality rating from how recipients respond; no API raises it.',
   'scripts/checks/it_engineer_duties_9_to_18.test.mjs', 'it_engineer'),
  ('whatsapp_template', 'duty:sender:template:', null, null,
   'Meta approves or rejects a WhatsApp template; a rejected one is rewritten and resubmitted.',
   'scripts/checks/it_engineer_duties_9_to_18.test.mjs', 'it_engineer'),
  ('dependency_advisory', 'duty:dependency:',
   'Every Monday the weekly readings open a lockfile-only npm audit fix as a pull request when it lowers the advisory count and the TypeScript build still passes (scripts/it/open_dependency_patch_pr.mjs). It is never merged without an independent review.',
   null, null, 'scripts/checks/it_engineer_duties_19_to_24.test.mjs', 'it_engineer'),
  ('restore_table', 'duty:restore_table:', null, null,
   'A table export that is stale or does not restore needs its writer rebuilt; nothing in the repository has written one since 7 Sep 2026.',
   'scripts/checks/it_engineer_duties_19_to_24.test.mjs', 'it_engineer'),
  ('renewal', 'duty:renewal:',
   'The accountant is warned at 60 and 30 days by a renewal.due handoff, arranges the renewal, and records the new date with fn_it_renewal_recorded; the IT engineer closes it when it reads the new date back.',
   null, null, 'scripts/checks/it_engineer_duties_19_to_24.test.mjs', 'it_engineer'),
  ('provider_cap', 'duty:usage_',
   'The accountant raises the plan or tops the account up, and records the new cap or floor with fn_it_cap_set.',
   null, null, 'scripts/checks/it_engineer_duties_19_to_24.test.mjs', 'it_engineer'),
  ('unsigned_routine_change', 'duty:unsigned_change:', null, null,
   'Only the ceo or the founder can accept a change made outside the reviewed path (fn_it_change_accept); re-applying each routine with scripts/apply_sql.mjs from a reviewed revision also closes it.',
   'scripts/checks/it_engineer_duties_19_to_24.test.mjs', 'it_engineer'),
  ('unreviewed_revision', 'duty:unsigned_revision:',
   'Merge the pull request the revision belongs to; the next GitHub check closes the finding.',
   null, null, 'scripts/checks/it_engineer_duties_19_to_24.test.mjs', 'it_engineer')
on conflict (failure_class) do update set issue_prefix = excluded.issue_prefix, remedy = excluded.remedy,
  remedy_routine = excluded.remedy_routine, not_automatable_reason = excluded.not_automatable_reason,
  regression_check = excluded.regression_check;
