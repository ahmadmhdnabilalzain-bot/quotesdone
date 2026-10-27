-- THE FOUR DUTY FAMILIES RAISED SINCE 6 OCT EACH HAVE A PLAYBOOK CLASS.
--
-- Agent: it_engineer. 13 Oct 2026. scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class
-- failed on the full npm test against production.
--
-- MEASURED (read-only, production htdblwldjkcgjvmqkbeh, 13 Oct 2026 06:50 UTC): 17 cleared it.finding handoffs
-- sat at awaiting_learning because no it_playbook prefix covers their key at all -- four key families:
--   93625                       acct:books:books_stale                              (accountant, parked 7 Oct)
--   126356, 126869, 134400      duty:marketing_media_below_recommended:<post>        (marketing, parked 7-12 Oct)
--   148364, 149825, 152386, 159735  watch:run_failure:llm_gateway_auth             (ceo, parked 8-11 Oct)
--   150241 .. 150249 (9)        duty:backup_prune:storage:2026-08-15 .. 08-23        (ceo, parked 10 Oct)
-- ROOT CAUSE: the same as the_five_duty_families_raised_since_28_sep_each_have_a_playbook_class.sql -- a duty or
-- detector family is added without its it_playbook row, so when its first finding clears fn_it_loop_reverify has
-- no class to record the learning against and parks the handoff with no clock.
--
-- WHAT THIS DOES: one class per family, naming what the owning seat does. None is given a typical_cause: none has
-- been measured, and a cause is recorded only when one is (fn_it_attach_learning) -- so the handoffs stay at
-- awaiting_learning, now covered, and the handoff_sla duty keeps reporting them until a cause is attached.
-- WHAT THIS DOES NOT DO: close any handoff, or write any finding.
--
-- Prevented by: scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs and the
-- verdict row at the end of this file.
--   node scripts/apply_sql.mjs scripts/sql/the_four_duty_families_raised_since_6_oct_each_have_a_playbook_class.sql --apply --ddl --seat it_engineer

insert into public.it_playbook (failure_class, issue_prefix, remedy, remedy_routine, not_automatable_reason, regression_check, typical_cause, added_by) values
  ('books_stale', 'acct:books:', null, null,
   'Books that go stale (no posted journal within gl_settings.books_stale_after_days) are brought current by the accountant posting the missing period; the accountant books duty clears the finding when a fresh journal posts.',
   'the accountant books duty (fn_accountant_books_duty); scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   null, 'it_engineer'),
  ('marketing_media_below_recommended', 'duty:marketing_media_below_recommended:', null, null,
   'A post published below a platform''s recommended media target is information for the marketing seat, answered in the next month''s plan; the marketing_channels settle clears it when no post of the last 7 days is below target.',
   'marketing_channels (fn_it_duty_settle marketing_media_below_recommended); scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   null, 'it_engineer'),
  ('run_failure', 'watch:run_failure:', null, null,
   'A run that fails (an expired or refused provider credential, a provider outage) is fixed at the credential or the caller by the owning seat; the run_failure detector clears the finding when the subject''s runs succeed again.',
   'the run_failure watch detector; scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   null, 'it_engineer'),
  ('backup_prune_blocked', 'duty:backup_prune:', null, null,
   'An export day that cannot be pruned because its Dropbox copy is not verified is retried by the Dropbox picker; fn_backup_prune_tick clears the finding when the copy verifies and the day prunes.',
   'fn_backup_prune_tick (fn_it_duty_settle backup_prune); scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   null, 'it_engineer')
on conflict (failure_class) do update set issue_prefix = excluded.issue_prefix,
  not_automatable_reason = excluded.not_automatable_reason, regression_check = excluded.regression_check;

select case
  when exists (select 1 from public.agent_actions a
                where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status in ('pending', 'failed')
                  and a.detail ? 'awaiting_learning'
                  and not exists (select 1 from public.it_playbook b
                                   where left(a.detail->>'issue_key', length(b.issue_prefix)) = b.issue_prefix))
    then 'PROBE FAILED: a parked it.finding handoff still has no playbook class'
  when exists (select 1 from public.it_playbook
                where failure_class in ('books_stale', 'marketing_media_below_recommended', 'run_failure', 'backup_prune_blocked')
                  and typical_cause is not null)
    then 'PROBE FAILED: a new class carries a cause nobody measured'
  else 'PROBE OK' end as verdict;
