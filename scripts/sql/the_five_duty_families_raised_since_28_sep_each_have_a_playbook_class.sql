-- THE FIVE DUTY FAMILIES RAISED SINCE 28 SEP EACH HAVE A PLAYBOOK CLASS.
--
-- Agent: it_engineer. 6 Oct 2026. scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class
-- failed on every run against production.
--
-- MEASURED (read-only, production htdblwldjkcgjvmqkbeh, 6 Oct 2026): eight cleared it.finding handoffs sat at
-- awaiting_learning because no it_playbook prefix covers their key at all -- five key families, all raised by
-- duties or detectors added after every_parked_it_finding_has_a_playbook_class_and_whatsapp_rates_keep_their_own.sql
-- (29 Sep) gave the then-uncovered families their classes:
--   98498          duty:marketing_duties:geo_audit                         (marketing, since 24 Sep)
--   100467, 127563 duty:db_health:growth:os_audit_log / :knowledge_vector_ml (ceo)
--   110256, 110257 duty:backup_objectives:drill_stale / :rto_unproven     (ceo)
--   120562, 130872 duty:workflow_heartbeat:kb_embed / :dropbox_kick        (ceo)
--   132371         knowledge_recall:no_ml_vectors                          (ceo)
-- ROOT CAUSE: a duty family is added without its it_playbook row, so the moment its first finding clears,
-- fn_it_loop_reverify has no class to record the learning against and parks the handoff with no clock.
--
-- WHAT THIS DOES: one class per family, naming what the owning seat actually does and why it is not a routine a
-- seat can run. None is given a typical_cause: no cause has been measured for these families, and a cause is
-- recorded only when one is (fn_it_attach_learning), never invented to close a loop -- so the handoffs stay at
-- awaiting_learning, now covered, and the handoff_sla duty keeps reporting them until a cause is attached.
-- WHAT THIS DOES NOT DO: close any handoff, or write any finding.
--
-- Prevented by: scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs and the
-- verdict row at the end of this file.
--   node scripts/apply_sql.mjs scripts/sql/the_five_duty_families_raised_since_28_sep_each_have_a_playbook_class.sql --apply --ddl --seat it_engineer

insert into public.it_playbook (failure_class, issue_prefix, remedy, remedy_routine, not_automatable_reason, regression_check, typical_cause, added_by) values
  ('marketing_duty_failing', 'duty:marketing_duties:', null, null,
   'A marketing duty that fails (a web search that returns nothing, a source page that changed) is fixed in that duty''s own reader by the marketing seat; the next run of the duty clears the finding.',
   'the IT duty marketing_duties; scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   null, 'it_engineer'),
  ('table_growth', 'duty:db_health:growth:', null, null,
   'A table that grows faster than its weekly budget is either real volume or a writer that should not keep what it writes; the owning seat decides which and changes the writer or its retention. The db_health duty clears the finding when the growth falls back under the budget.',
   'the IT duty db_health (growth); scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   null, 'it_engineer'),
  ('backup_objective_unproven', 'duty:backup_objectives:', null, null,
   'A restore drill that has not run, or a recovery time it has not proved, is answered by running the drill (its scheduled workflow); the backup_objectives duty clears the finding when a fresh drill reading arrives.',
   'the IT duty backup_objectives; scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   null, 'it_engineer'),
  ('workflow_heartbeat_missing', 'duty:workflow_heartbeat:', null, null,
   'A GitHub workflow whose readings stopped arriving is restarted or fixed in .github/workflows (or its runner quota restored); the workflow_heartbeat duty clears the finding when the next reading lands.',
   'the IT duty workflow_heartbeat; scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
   null, 'it_engineer'),
  ('knowledge_recall_gap', 'knowledge_recall:', null, null,
   'Knowledge rows without the vector the recall examination reads are filled by the embedding backfill workflow (ml-embed-backfill); the recall fault clears when the examination finds them embedded.',
   'the knowledge recall examination; scripts/checks/a_cleared_it_finding_never_parks_for_want_of_a_playbook_class.test.mjs',
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
                where failure_class in ('marketing_duty_failing', 'table_growth', 'backup_objective_unproven',
                                        'workflow_heartbeat_missing', 'knowledge_recall_gap')
                  and typical_cause is not null)
    then 'PROBE FAILED: a new class carries a cause nobody measured'
  else 'PROBE OK' end as verdict;
