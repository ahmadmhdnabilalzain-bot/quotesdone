-- THE IT PLAYBOOK KNOWS ITS RECURRING FAILURE CLASSES, SO A REPEAT IS WRITTEN UP WITHOUT A MODEL.
-- Seat: it_engineer. 24 Sep 2026, seat audit GAPS.md IT gap 2 (ledger 983). Needs
-- every_new_bug_leaves_a_playbook_entry_a_check_and_an_incident_record.sql (it_playbook).
--
-- WHAT WAS MEASURED (production, 24 Sep 2026): 26 playbook classes, 1 with a remedy routine. The recurring open
--   findings were unsigned_revision (33e9f8d seen 68 times, 0a58ea6 65), WhatsApp template 401s and heartbeat steps
--   failing on an internal 401 or the edge CPU cap (546). unreviewed_revision and heartbeat_step had no typical
--   cause for the two newer shapes, and none of the duties added today had a class, so every one of their closed
--   faults would have needed a reasoned postmortem (every_serious_incident_gets_a_postmortem.sql).
--
-- WHAT THIS CHANGES: typical causes for the three recurring shapes, and one class per new duty. Nothing here is a
--   remedy routine: each of these fixes is a code or configuration change (the IT engineer is refused [deploy]),
--   so the honest entry is the cause, the remedy in words, and the check that fails if it returns.
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_playbook_knows_its_recurring_failure_classes.sql --apply --ddl

update public.it_playbook set typical_cause =
  'Routines were applied from a branch whose pull request was closed or never merged (measured 24 Sep 2026: 33e9f8d, '
  || '0a58ea6, 9826ead). Remedy when the branch is dead: re-apply main''s canonical file for each routine, then the '
  || 'change watch sees a signed revision and closes it.'
 where failure_class = 'unreviewed_revision';

update public.it_playbook set typical_cause = typical_cause
  || ' Two further shapes (24 Sep 2026): an internal hop answered HTTP 401 because internal_credential.scope does not '
  || 'name the callee or the credential was rotated under the caller (fn_it_credential_reverify); and an edge function '
  || 'ended with 546, the platform CPU cap, which a timeout cannot bound -- the batch is made smaller.'
 where failure_class = 'heartbeat_step' and position('546' in coalesce(typical_cause, '')) = 0;

insert into public.it_playbook (failure_class, issue_prefix, remedy, not_automatable_reason, regression_check, added_by, typical_cause) values
  ('provider_outage', 'duty:provider_status:', null,
   'The outage is the provider''s; nothing inside the company fixes it. The finding closes when their status page clears.',
   'supabase/functions/_shared/it_provider_readings.test.ts', 'it_engineer', 'A provider published a major or critical incident.'),
  ('latency_over_budget', 'duty:latency_slo:', 'The owning seat bounds the slow query or warms the function; the next hourly p95 closes it.', null,
   'supabase/functions/_shared/observe.test.ts', 'it_engineer', 'A portal data function''s 24-hour p95 exceeded the 2.5 s budget.'),
  ('data_quality', 'duty:data_quality:', 'Demo identities are marked by the duty itself; orphans and mismatches are corrected by the owning seat.', null,
   'scripts/checks/it_engineer_gap_duties_act.test.mjs', 'it_engineer', 'A row lost its parent, disagreed with its quote, or a demo identity was not marked.'),
  ('model_runaway', 'duty:model_spend:', 'The owning seat stops the loop or adds the consumer to it_model_consumer with its reason.', null,
   'scripts/checks/it_engineer_gap_duties_act.test.mjs', 'it_engineer', 'A model consumer was unlisted, looped, or paid for the same call again.'),
  ('postmortem_incomplete', 'duty:postmortem:', 'Write the cause and add the regression check to the repository.', null,
   'scripts/checks/it_engineer_gap_duties_act.test.mjs', 'it_engineer', 'A new failure class closed without its cause or its check.')
on conflict (failure_class) do update set issue_prefix = excluded.issue_prefix, remedy = excluded.remedy,
  not_automatable_reason = excluded.not_automatable_reason, regression_check = excluded.regression_check, typical_cause = excluded.typical_cause;

select case when (select count(*) from public.it_playbook where failure_class in
                   ('provider_outage', 'latency_over_budget', 'data_quality', 'model_runaway', 'postmortem_incomplete')) = 5
            then 'PROBE OK' else 'PROBE FAILED: a playbook class is missing' end as verdict;
