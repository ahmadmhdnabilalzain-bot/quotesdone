-- TABLES NOTHING READS OR WRITES MOVE TO THE RETIRED SCHEMA, DATA KEPT.
--
-- Seat: it_engineer. Founder ledgers 1714 and 1715 (16 Nov 2026): remove what is unnecessary and prove each removal with
-- evidence, and prove everything is still fine. Ruling 1551 asks for Supabase cost cuts; these hold 197 MB.
--
-- WHAT WAS WRONG. Each table below is named by no live routine body (any schema, comments stripped), cron command, view,
-- RLS policy on another table, column default, dispatch table or *_sql column, by no edge function or app code, and by no
-- statement from service_role, authenticated or anon since 2 Nov (pg_stat_statements). pg_stat_user_tables shows 0 inserts,
-- updates and deletes since the 9 Nov restart for every one. Their scans are not readers: 19 to 76 seq scans each are the
-- schema export and audits; the few index scans on the four exported ones are the daily export paging by primary key; and
-- the larger counts are foreign-key checks run when a referenced row is deleted - inquiry_requirement 628 index scans
-- (inquiries), supplier_opportunity_score 1,111 seq and 2,591 index scans (leads, inquiries), handoff_contract 5,726 seq
-- scans (agent_actions, whose purge deletes rows it could reference). Those checks keep working after the move.
-- No table outside this list has a foreign key INTO one of them, and no view depends on them (pg_depend). Row counts are
-- count(*) on production, 16 Nov 2026 (n_live_tup is wrong after the restart). 26 of the 37 are empty.
--   kb_chunk_quarantine                  70629 rows  128776 KB  registry: excluded (no_writer)
--   kb_trim_hash                        148326 rows   38240 KB  registry: excluded (cache)
--   kb_trim_plan                             0 rows    2624 KB  registry: excluded (cache)
--   knowledge_ingestion_undo                 0 rows   11960 KB  registry: excluded (no_writer)
--   knowledge_ingestion_run                  0 rows      48 KB  registry: excluded (log)
--   yello_staging                        13123 rows   12680 KB  registry: excluded (fixture)
--   kb_operational_route_test              344 rows    1824 KB  registry: excluded (no_writer)
--   qd_deploy_src                           70 rows    1264 KB  registry: excluded (log)
--   marketing_library                      317 rows    1200 KB  registry: excluded (no_writer)
--   category_keyword                      1839 rows     560 KB  registry: excluded (no_writer)
--   qd_i18n                                 30 rows     272 KB  registry: excluded (no_writer)
--   qd_i18n_chunks                          68 rows     288 KB  registry: excluded (no_writer)
--   taxonomy_trade_code                    385 rows     192 KB  registry: excluded (no_writer)
--   subcategory_agent_map                  434 rows     160 KB  registry: excluded (no_writer)
--   inquiry_scope_disposition                0 rows     248 KB  registry: exported (inquiry)
--   inquiry_trade_candidate_evidence         0 rows     120 KB  registry: excluded (no_writer)
--   inquiry_requirement                      0 rows      56 KB  registry: exported (inquiry)
--   inquiry_answer_conflict_value            0 rows      64 KB  registry: excluded (no_writer)
--   inquiry_answer_corroboration             0 rows      40 KB  registry: excluded (no_writer)
--   inquiry_answer_document                  0 rows      16 KB  registry: exported (inquiry)
--   quote_requirements                       0 rows      32 KB  registry: exported (quote)
--   agent_context_retrieval                  0 rows     208 KB  registry: excluded (no_writer)
--   agent_command_log                        0 rows     160 KB  registry: excluded (log)
--   canon_eval_runs                          0 rows      88 KB  registry: excluded (log)
--   match_eval_runs                          0 rows      64 KB  registry: excluded (log)
--   boq_fixture_run                          0 rows      64 KB  registry: excluded (fixture)
--   vt_results                               0 rows      56 KB  registry: excluded (log)
--   ai_usage                                 0 rows      56 KB  registry: excluded (log)
--   chat_violations                          0 rows      32 KB  registry: excluded (no_writer)
--   agent_pending_actions                    0 rows      32 KB  registry: excluded (no_writer)
--   supplier_opportunity_score               0 rows      16 KB  registry: excluded (no_writer)
--   customer_score                           0 rows      48 KB  registry: excluded (no_writer)
--   org_objectives                           0 rows      32 KB  registry: excluded (no_writer)
--   handoff_contract                         0 rows     112 KB  registry: excluded (no_writer)
--   org_workflow_step                        0 rows      64 KB  registry: excluded (no_writer)
--   org_workflow_ownership                   0 rows      88 KB  registry: excluded (no_writer)
--   employee_workflow                        0 rows      40 KB  registry: excluded (no_writer)
-- Foreign keys FROM them into live tables (leads, inquiries, inquiry_answer, org_agents, agent_actions, org_role, ...) move
-- with them and keep working; their triggers move too (the trigger functions stay in public, still used elsewhere).
-- The three fn_kb_trim_* routines move with kb_trim_hash and kb_trim_plan, their only tables: the one-off trim tool
-- (scripts/kb/trim_kb_chunks.mjs) is the only thing that ran them, and it would fail loudly until the one-line reversal.
-- KEPT although quiet: org_departments (25 live bodies and two views read it), dept_knowledge_alias (fn_dept_scope reads it),
-- catalog_subcategories (lead_subcategory has a foreign key into it), inv_items (po_lines), inquiry_workstream_group (four
-- live inquiry tables point at it), inquiry_trade_candidate and inquiry_trade_clarification (holdout_v2.fn_run_pending),
-- agent_context_head (decision_policy prompt_cache_enabled), qa_results (a metric's measure_sql), kb_purge_ledger and
-- kb_revisions (records of a deletion and of edits), and every audit, books and PDPL table.
--
-- THE DAILY EXPORT. Each table's table_export_registry row is deleted in the same file (the form
-- scripts/lib/table_export_registry.mjs replays), because the export and every_table_is_exported_or_explicitly_excluded
-- treat a row whose table is gone as a fault. Four of them were exported every day although empty; the copies already in the
-- backups bucket stay.
--
-- REVERSIBLE (phase 1 of 2): data kept; phase 2 (archive to the evidence bucket with counts and checksums, then DROP) is owed
-- after 7 clean days - scripts/sql/pending/the_retired_schema_is_dropped_only_after_seven_clean_days_probe.txt.
--
-- REVERSAL, one line per table (back to public with its registry row exactly as it was on 16 Nov):
--   alter table retired.kb_chunk_quarantine set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('kb_chunk_quarantine', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.kb_trim_hash set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('kb_trim_hash', false, 'cache', 'Working hashes of kb_chunks for the night trim, rebuilt from kb_chunks on every run.', 'it_engineer');
--   alter table retired.kb_trim_plan set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('kb_trim_plan', false, 'cache', 'The night trim''s work list, rebuilt from kb_trim_hash on every run and emptied as it goes.', 'it_engineer');
--   alter table retired.knowledge_ingestion_undo set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('knowledge_ingestion_undo', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.knowledge_ingestion_run set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('knowledge_ingestion_run', false, 'log', 'An operational log of runs, calls, probes, evals or errors: that machinery ran, not a business record.', 'it_engineer');
--   alter table retired.yello_staging set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('yello_staging', false, 'fixture', 'Import staging or a test fixture: its rows are promoted into an exported table, or are synthetic.', 'it_engineer');
--   alter table retired.kb_operational_route_test set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('kb_operational_route_test', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.qd_deploy_src set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('qd_deploy_src', false, 'log', 'An operational log of runs, calls, probes, evals or errors: that machinery ran, not a business record.', 'it_engineer');
--   alter table retired.marketing_library set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('marketing_library', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.category_keyword set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('category_keyword', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.qd_i18n set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('qd_i18n', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.qd_i18n_chunks set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('qd_i18n_chunks', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.taxonomy_trade_code set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('taxonomy_trade_code', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.subcategory_agent_map set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('subcategory_agent_map', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.inquiry_scope_disposition set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('inquiry_scope_disposition', true, 'inquiry', 'exported before the registry (the 174-row list of 29 Sep 2026): a inquiry record', 'it_engineer');
--   alter table retired.inquiry_trade_candidate_evidence set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('inquiry_trade_candidate_evidence', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.inquiry_requirement set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('inquiry_requirement', true, 'inquiry', 'exported before the registry (the 174-row list of 29 Sep 2026): a inquiry record', 'it_engineer');
--   alter table retired.inquiry_answer_conflict_value set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('inquiry_answer_conflict_value', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.inquiry_answer_corroboration set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('inquiry_answer_corroboration', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.inquiry_answer_document set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('inquiry_answer_document', true, 'inquiry', 'exported before the registry (the 174-row list of 29 Sep 2026): a inquiry record', 'it_engineer');
--   alter table retired.quote_requirements set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('quote_requirements', true, 'quote', 'exported before the registry (the 174-row list of 29 Sep 2026): a quote record', 'it_engineer');
--   alter table retired.agent_context_retrieval set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('agent_context_retrieval', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.agent_command_log set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('agent_command_log', false, 'log', 'An operational log of runs, calls, probes, evals or errors: that machinery ran, not a business record.', 'it_engineer');
--   alter table retired.canon_eval_runs set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('canon_eval_runs', false, 'log', 'An operational log of runs, calls, probes, evals or errors: that machinery ran, not a business record.', 'it_engineer');
--   alter table retired.match_eval_runs set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('match_eval_runs', false, 'log', 'An operational log of runs, calls, probes, evals or errors: that machinery ran, not a business record.', 'it_engineer');
--   alter table retired.boq_fixture_run set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('boq_fixture_run', false, 'fixture', 'Import staging or a test fixture: its rows are promoted into an exported table, or are synthetic.', 'it_engineer');
--   alter table retired.vt_results set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('vt_results', false, 'log', 'An operational log of runs, calls, probes, evals or errors: that machinery ran, not a business record.', 'it_engineer');
--   alter table retired.ai_usage set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('ai_usage', false, 'log', 'An operational log of runs, calls, probes, evals or errors: that machinery ran, not a business record.', 'it_engineer');
--   alter table retired.chat_violations set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('chat_violations', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.agent_pending_actions set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('agent_pending_actions', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.supplier_opportunity_score set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('supplier_opportunity_score', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.customer_score set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('customer_score', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.org_objectives set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('org_objectives', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.handoff_contract set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('handoff_contract', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.org_workflow_step set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('org_workflow_step', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.org_workflow_ownership set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('org_workflow_ownership', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
--   alter table retired.employee_workflow set schema public; insert into public.table_export_registry (table_name, exported, category, reason, added_by) values ('employee_workflow', false, 'no_writer', 'FROZEN: no routine, edge function or app code writes it (re-measured on every CI run), so its content cannot drift.', 'it_engineer');
-- and per routine:
--   alter function retired.fn_kb_trim_batch(integer) set schema public; grant execute on function public.fn_kb_trim_batch(integer) to service_role;
--   alter function retired.fn_kb_trim_hash_page(bigint,integer) set schema public; grant execute on function public.fn_kb_trim_hash_page(bigint,integer) to service_role;
--   alter function retired.fn_kb_trim_plan_build(bigint) set schema public; grant execute on function public.fn_kb_trim_plan_build(bigint) to service_role;

-- The schema that holds what is retired: owned by postgres, no USAGE for anyone else (PUBLIC, anon, authenticated and
-- service_role cannot even name an object in it), so a retired routine cannot be called and a retired table cannot be read
-- from the API. postgres keeps full access for the phase-2 archive. Idempotent: every cluster file repeats these lines.
create schema if not exists retired;
revoke all on schema retired from public, anon, authenticated, service_role;

-- The tables (data kept; their indexes, constraints, owned sequences, policies and triggers move with them).
alter table if exists public.kb_chunk_quarantine set schema retired;
alter table if exists public.kb_trim_hash set schema retired;
alter table if exists public.kb_trim_plan set schema retired;
alter table if exists public.knowledge_ingestion_undo set schema retired;
alter table if exists public.knowledge_ingestion_run set schema retired;
alter table if exists public.yello_staging set schema retired;
alter table if exists public.kb_operational_route_test set schema retired;
alter table if exists public.qd_deploy_src set schema retired;
alter table if exists public.marketing_library set schema retired;
alter table if exists public.category_keyword set schema retired;
alter table if exists public.qd_i18n set schema retired;
alter table if exists public.qd_i18n_chunks set schema retired;
alter table if exists public.taxonomy_trade_code set schema retired;
alter table if exists public.subcategory_agent_map set schema retired;
alter table if exists public.inquiry_scope_disposition set schema retired;
alter table if exists public.inquiry_trade_candidate_evidence set schema retired;
alter table if exists public.inquiry_requirement set schema retired;
alter table if exists public.inquiry_answer_conflict_value set schema retired;
alter table if exists public.inquiry_answer_corroboration set schema retired;
alter table if exists public.inquiry_answer_document set schema retired;
alter table if exists public.quote_requirements set schema retired;
alter table if exists public.agent_context_retrieval set schema retired;
alter table if exists public.agent_command_log set schema retired;
alter table if exists public.canon_eval_runs set schema retired;
alter table if exists public.match_eval_runs set schema retired;
alter table if exists public.boq_fixture_run set schema retired;
alter table if exists public.vt_results set schema retired;
alter table if exists public.ai_usage set schema retired;
alter table if exists public.chat_violations set schema retired;
alter table if exists public.agent_pending_actions set schema retired;
alter table if exists public.supplier_opportunity_score set schema retired;
alter table if exists public.customer_score set schema retired;
alter table if exists public.org_objectives set schema retired;
alter table if exists public.handoff_contract set schema retired;
alter table if exists public.org_workflow_step set schema retired;
alter table if exists public.org_workflow_ownership set schema retired;
alter table if exists public.employee_workflow set schema retired;

-- No API role keeps a grant on a retired table (they could not reach the schema anyway).
revoke all on table retired.kb_chunk_quarantine from anon, authenticated, service_role;
revoke all on table retired.kb_trim_hash from anon, authenticated, service_role;
revoke all on table retired.kb_trim_plan from anon, authenticated, service_role;
revoke all on table retired.knowledge_ingestion_undo from anon, authenticated, service_role;
revoke all on table retired.knowledge_ingestion_run from anon, authenticated, service_role;
revoke all on table retired.yello_staging from anon, authenticated, service_role;
revoke all on table retired.kb_operational_route_test from anon, authenticated, service_role;
revoke all on table retired.qd_deploy_src from anon, authenticated, service_role;
revoke all on table retired.marketing_library from anon, authenticated, service_role;
revoke all on table retired.category_keyword from anon, authenticated, service_role;
revoke all on table retired.qd_i18n from anon, authenticated, service_role;
revoke all on table retired.qd_i18n_chunks from anon, authenticated, service_role;
revoke all on table retired.taxonomy_trade_code from anon, authenticated, service_role;
revoke all on table retired.subcategory_agent_map from anon, authenticated, service_role;
revoke all on table retired.inquiry_scope_disposition from anon, authenticated, service_role;
revoke all on table retired.inquiry_trade_candidate_evidence from anon, authenticated, service_role;
revoke all on table retired.inquiry_requirement from anon, authenticated, service_role;
revoke all on table retired.inquiry_answer_conflict_value from anon, authenticated, service_role;
revoke all on table retired.inquiry_answer_corroboration from anon, authenticated, service_role;
revoke all on table retired.inquiry_answer_document from anon, authenticated, service_role;
revoke all on table retired.quote_requirements from anon, authenticated, service_role;
revoke all on table retired.agent_context_retrieval from anon, authenticated, service_role;
revoke all on table retired.agent_command_log from anon, authenticated, service_role;
revoke all on table retired.canon_eval_runs from anon, authenticated, service_role;
revoke all on table retired.match_eval_runs from anon, authenticated, service_role;
revoke all on table retired.boq_fixture_run from anon, authenticated, service_role;
revoke all on table retired.vt_results from anon, authenticated, service_role;
revoke all on table retired.ai_usage from anon, authenticated, service_role;
revoke all on table retired.chat_violations from anon, authenticated, service_role;
revoke all on table retired.agent_pending_actions from anon, authenticated, service_role;
revoke all on table retired.supplier_opportunity_score from anon, authenticated, service_role;
revoke all on table retired.customer_score from anon, authenticated, service_role;
revoke all on table retired.org_objectives from anon, authenticated, service_role;
revoke all on table retired.handoff_contract from anon, authenticated, service_role;
revoke all on table retired.org_workflow_step from anon, authenticated, service_role;
revoke all on table retired.org_workflow_ownership from anon, authenticated, service_role;
revoke all on table retired.employee_workflow from anon, authenticated, service_role;

-- Their rows leave the daily export's registry.
delete from public.table_export_registry where table_name = 'kb_chunk_quarantine';
delete from public.table_export_registry where table_name = 'kb_trim_hash';
delete from public.table_export_registry where table_name = 'kb_trim_plan';
delete from public.table_export_registry where table_name = 'knowledge_ingestion_undo';
delete from public.table_export_registry where table_name = 'knowledge_ingestion_run';
delete from public.table_export_registry where table_name = 'yello_staging';
delete from public.table_export_registry where table_name = 'kb_operational_route_test';
delete from public.table_export_registry where table_name = 'qd_deploy_src';
delete from public.table_export_registry where table_name = 'marketing_library';
delete from public.table_export_registry where table_name = 'category_keyword';
delete from public.table_export_registry where table_name = 'qd_i18n';
delete from public.table_export_registry where table_name = 'qd_i18n_chunks';
delete from public.table_export_registry where table_name = 'taxonomy_trade_code';
delete from public.table_export_registry where table_name = 'subcategory_agent_map';
delete from public.table_export_registry where table_name = 'inquiry_scope_disposition';
delete from public.table_export_registry where table_name = 'inquiry_trade_candidate_evidence';
delete from public.table_export_registry where table_name = 'inquiry_requirement';
delete from public.table_export_registry where table_name = 'inquiry_answer_conflict_value';
delete from public.table_export_registry where table_name = 'inquiry_answer_corroboration';
delete from public.table_export_registry where table_name = 'inquiry_answer_document';
delete from public.table_export_registry where table_name = 'quote_requirements';
delete from public.table_export_registry where table_name = 'agent_context_retrieval';
delete from public.table_export_registry where table_name = 'agent_command_log';
delete from public.table_export_registry where table_name = 'canon_eval_runs';
delete from public.table_export_registry where table_name = 'match_eval_runs';
delete from public.table_export_registry where table_name = 'boq_fixture_run';
delete from public.table_export_registry where table_name = 'vt_results';
delete from public.table_export_registry where table_name = 'ai_usage';
delete from public.table_export_registry where table_name = 'chat_violations';
delete from public.table_export_registry where table_name = 'agent_pending_actions';
delete from public.table_export_registry where table_name = 'supplier_opportunity_score';
delete from public.table_export_registry where table_name = 'customer_score';
delete from public.table_export_registry where table_name = 'org_objectives';
delete from public.table_export_registry where table_name = 'handoff_contract';
delete from public.table_export_registry where table_name = 'org_workflow_step';
delete from public.table_export_registry where table_name = 'org_workflow_ownership';
delete from public.table_export_registry where table_name = 'employee_workflow';

-- The trim routines that only these tables served.
do $retire_kb_trim$
begin
  if to_regprocedure('public.fn_kb_trim_batch(integer)') is not null then
    revoke all on function public.fn_kb_trim_batch(integer) from public, anon, authenticated, service_role;
    alter function public.fn_kb_trim_batch(integer) set schema retired;
  end if;
  if to_regprocedure('public.fn_kb_trim_hash_page(bigint,integer)') is not null then
    revoke all on function public.fn_kb_trim_hash_page(bigint,integer) from public, anon, authenticated, service_role;
    alter function public.fn_kb_trim_hash_page(bigint,integer) set schema retired;
  end if;
  if to_regprocedure('public.fn_kb_trim_plan_build(bigint)') is not null then
    revoke all on function public.fn_kb_trim_plan_build(bigint) from public, anon, authenticated, service_role;
    alter function public.fn_kb_trim_plan_build(bigint) set schema retired;
  end if;
end
$retire_kb_trim$;

-- PROBE (tables): a verdict row. Every table is in retired and not in public, nothing outside retired names one (routine
-- bodies with comments stripped, cron commands, views, policies, defaults), no foreign key from outside retired points into
-- one, no registry row is left for one, and no API role can use the schema.
with t(n) as (values
         ('kb_chunk_quarantine'),
         ('kb_trim_hash'),
         ('kb_trim_plan'),
         ('knowledge_ingestion_undo'),
         ('knowledge_ingestion_run'),
         ('yello_staging'),
         ('kb_operational_route_test'),
         ('qd_deploy_src'),
         ('marketing_library'),
         ('category_keyword'),
         ('qd_i18n'),
         ('qd_i18n_chunks'),
         ('taxonomy_trade_code'),
         ('subcategory_agent_map'),
         ('inquiry_scope_disposition'),
         ('inquiry_trade_candidate_evidence'),
         ('inquiry_requirement'),
         ('inquiry_answer_conflict_value'),
         ('inquiry_answer_corroboration'),
         ('inquiry_answer_document'),
         ('quote_requirements'),
         ('agent_context_retrieval'),
         ('agent_command_log'),
         ('canon_eval_runs'),
         ('match_eval_runs'),
         ('boq_fixture_run'),
         ('vt_results'),
         ('ai_usage'),
         ('chat_violations'),
         ('agent_pending_actions'),
         ('supplier_opportunity_score'),
         ('customer_score'),
         ('org_objectives'),
         ('handoff_contract'),
         ('org_workflow_step'),
         ('org_workflow_ownership'),
         ('employee_workflow')),
body as (select regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') src, ns.nspname || '.' || p.proname who
           from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
          where ns.nspname not in ('retired', 'pg_catalog', 'information_schema')
            and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')),
v as (select
  (select count(*) from t where to_regclass('retired.' || n) is not null) moved,
  (select count(*) from t) wanted,
  (select count(*) from t where to_regclass('public.' || n) is not null) left_in_public,
  (select string_agg(who || ' names ' || substring(src from '\m(agent_command_log|agent_context_retrieval|agent_pending_actions|ai_usage|boq_fixture_run|canon_eval_runs|category_keyword|chat_violations|customer_score|employee_workflow|handoff_contract|inquiry_answer_conflict_value|inquiry_answer_corroboration|inquiry_answer_document|inquiry_requirement|inquiry_scope_disposition|inquiry_trade_candidate_evidence|kb_chunk_quarantine|kb_operational_route_test|kb_trim_hash|kb_trim_plan|knowledge_ingestion_run|knowledge_ingestion_undo|marketing_library|match_eval_runs|org_objectives|org_workflow_ownership|org_workflow_step|qd_deploy_src|qd_i18n|qd_i18n_chunks|quote_requirements|subcategory_agent_map|supplier_opportunity_score|taxonomy_trade_code|vt_results|yello_staging)\M'), '; ') from body where src ~ '\m(agent_command_log|agent_context_retrieval|agent_pending_actions|ai_usage|boq_fixture_run|canon_eval_runs|category_keyword|chat_violations|customer_score|employee_workflow|handoff_contract|inquiry_answer_conflict_value|inquiry_answer_corroboration|inquiry_answer_document|inquiry_requirement|inquiry_scope_disposition|inquiry_trade_candidate_evidence|kb_chunk_quarantine|kb_operational_route_test|kb_trim_hash|kb_trim_plan|knowledge_ingestion_run|knowledge_ingestion_undo|marketing_library|match_eval_runs|org_objectives|org_workflow_ownership|org_workflow_step|qd_deploy_src|qd_i18n|qd_i18n_chunks|quote_requirements|subcategory_agent_map|supplier_opportunity_score|taxonomy_trade_code|vt_results|yello_staging)\M') body_callers,
  (select string_agg(jobname, ', ') from cron.job where command ~ '\m(agent_command_log|agent_context_retrieval|agent_pending_actions|ai_usage|boq_fixture_run|canon_eval_runs|category_keyword|chat_violations|customer_score|employee_workflow|handoff_contract|inquiry_answer_conflict_value|inquiry_answer_corroboration|inquiry_answer_document|inquiry_requirement|inquiry_scope_disposition|inquiry_trade_candidate_evidence|kb_chunk_quarantine|kb_operational_route_test|kb_trim_hash|kb_trim_plan|knowledge_ingestion_run|knowledge_ingestion_undo|marketing_library|match_eval_runs|org_objectives|org_workflow_ownership|org_workflow_step|qd_deploy_src|qd_i18n|qd_i18n_chunks|quote_requirements|subcategory_agent_map|supplier_opportunity_score|taxonomy_trade_code|vt_results|yello_staging)\M') cron_callers,
  (select string_agg(schemaname || '.' || viewname, ', ') from pg_views where schemaname not in ('retired', 'pg_catalog', 'information_schema') and definition ~ '\m(agent_command_log|agent_context_retrieval|agent_pending_actions|ai_usage|boq_fixture_run|canon_eval_runs|category_keyword|chat_violations|customer_score|employee_workflow|handoff_contract|inquiry_answer_conflict_value|inquiry_answer_corroboration|inquiry_answer_document|inquiry_requirement|inquiry_scope_disposition|inquiry_trade_candidate_evidence|kb_chunk_quarantine|kb_operational_route_test|kb_trim_hash|kb_trim_plan|knowledge_ingestion_run|knowledge_ingestion_undo|marketing_library|match_eval_runs|org_objectives|org_workflow_ownership|org_workflow_step|qd_deploy_src|qd_i18n|qd_i18n_chunks|quote_requirements|subcategory_agent_map|supplier_opportunity_score|taxonomy_trade_code|vt_results|yello_staging)\M') view_callers,
  (select string_agg(schemaname || '.' || tablename || '.' || policyname, ', ') from pg_policies where schemaname <> 'retired' and coalesce(qual, '') || ' ' || coalesce(with_check, '') ~ '\m(agent_command_log|agent_context_retrieval|agent_pending_actions|ai_usage|boq_fixture_run|canon_eval_runs|category_keyword|chat_violations|customer_score|employee_workflow|handoff_contract|inquiry_answer_conflict_value|inquiry_answer_corroboration|inquiry_answer_document|inquiry_requirement|inquiry_scope_disposition|inquiry_trade_candidate_evidence|kb_chunk_quarantine|kb_operational_route_test|kb_trim_hash|kb_trim_plan|knowledge_ingestion_run|knowledge_ingestion_undo|marketing_library|match_eval_runs|org_objectives|org_workflow_ownership|org_workflow_step|qd_deploy_src|qd_i18n|qd_i18n_chunks|quote_requirements|subcategory_agent_map|supplier_opportunity_score|taxonomy_trade_code|vt_results|yello_staging)\M') policy_callers,
  (select string_agg(k.conrelid::regclass::text || '.' || k.conname, ', ') from pg_constraint k join pg_class c on c.oid = k.confrelid join pg_namespace cn on cn.oid = c.relnamespace
     join pg_class s on s.oid = k.conrelid join pg_namespace sn on sn.oid = s.relnamespace where k.contype = 'f' and cn.nspname = 'retired' and sn.nspname <> 'retired') fk_into,
  (select count(*) from public.table_export_registry r join t on t.n = r.table_name) registry_rows,
  (select count(*) from unnest(array['anon', 'authenticated', 'service_role']) r(role) where has_schema_privilege(r.role, 'retired', 'usage')) api_usage)
select case when moved = wanted and left_in_public = 0 and body_callers is null and cron_callers is null and view_callers is null
             and policy_callers is null and fk_into is null and registry_rows = 0 and api_usage = 0
            then 'PROBE OK: tables: ' || moved || ' of ' || wanted || ' tables in schema retired with their data, none left in public, nothing outside retired names one, no registry row, no API role can reach the schema'
            else 'PROBE FAILED: tables: moved ' || moved || '/' || wanted || ', left in public ' || left_in_public
                 || ', bodies [' || coalesce(body_callers, '') || '], cron [' || coalesce(cron_callers, '') || '], views [' || coalesce(view_callers, '')
                 || '], policies [' || coalesce(policy_callers, '') || '], foreign keys into retired [' || coalesce(fk_into, '')
                 || '], registry rows ' || registry_rows || ', API roles with usage ' || api_usage end as verdict
  from v;

-- PROBE (kb_trim): a verdict row, never a raise (a raise would roll back the moves above). It reads, live, at apply time:
--   moved      every signature is now in schema retired;  gone  no routine of these names is left in public;
--   callers    no routine outside schema retired names one of them in its body (comments stripped), no cron command,
--              no view, no policy, no column default, and no trigger outside retired runs a retired routine;
--   closed     no role but postgres may execute a retired routine.
with sig(s) as (values
         ('fn_kb_trim_batch(integer)'),
         ('fn_kb_trim_hash_page(bigint,integer)'),
         ('fn_kb_trim_plan_build(bigint)')),
nm(n) as (select unnest(array['fn_kb_trim_batch','fn_kb_trim_hash_page','fn_kb_trim_plan_build'])),
body as (select regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') src, ns.nspname || '.' || p.proname who
           from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
          where ns.nspname not in ('retired', 'pg_catalog', 'information_schema')
            and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')),
v as (select
  (select count(*) from sig where to_regprocedure('retired.' || s) is not null) moved,
  (select count(*) from sig) wanted,
  (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace join nm on nm.n = p.proname where ns.nspname = 'public') left_in_public,
  (select string_agg(who || ' names ' || substring(src from '\m(fn_kb_trim_batch|fn_kb_trim_hash_page|fn_kb_trim_plan_build)\M'), '; ') from body where src ~ '\m(fn_kb_trim_batch|fn_kb_trim_hash_page|fn_kb_trim_plan_build)\M') body_callers,
  (select string_agg(jobname, ', ') from cron.job where command ~ '\m(fn_kb_trim_batch|fn_kb_trim_hash_page|fn_kb_trim_plan_build)\M') cron_callers,
  (select string_agg(schemaname || '.' || viewname, ', ') from pg_views where schemaname not in ('retired', 'pg_catalog', 'information_schema') and definition ~ '\m(fn_kb_trim_batch|fn_kb_trim_hash_page|fn_kb_trim_plan_build)\M') view_callers,
  (select string_agg(tablename || '.' || policyname, ', ') from pg_policies where coalesce(qual, '') || ' ' || coalesce(with_check, '') ~ '\m(fn_kb_trim_batch|fn_kb_trim_hash_page|fn_kb_trim_plan_build)\M') policy_callers,
  (select string_agg(c.relname, ', ') from pg_attrdef ad join pg_class c on c.oid = ad.adrelid where pg_get_expr(ad.adbin, ad.adrelid) ~ '\m(fn_kb_trim_batch|fn_kb_trim_hash_page|fn_kb_trim_plan_build)\M') default_callers,
  (select string_agg(c.relname || '.' || t.tgname, ', ') from pg_trigger t join pg_proc p on p.oid = t.tgfoid join pg_namespace pn on pn.oid = p.pronamespace
     join pg_class c on c.oid = t.tgrelid join pg_namespace cn on cn.oid = c.relnamespace where pn.nspname = 'retired' and cn.nspname <> 'retired') trigger_callers,
  (select count(*) from sig, unnest(array['anon', 'authenticated', 'service_role']) r(role)
     where to_regprocedure('retired.' || s) is not null and has_function_privilege(r.role, to_regprocedure('retired.' || s), 'execute')) still_executable)
select case when moved = wanted and left_in_public = 0 and body_callers is null and cron_callers is null and view_callers is null
             and policy_callers is null and default_callers is null and trigger_callers is null and still_executable = 0
            then 'PROBE OK: kb_trim: ' || moved || ' of ' || wanted || ' routines in schema retired, none left in public, no caller outside retired, executable by no API role'
            else 'PROBE FAILED: kb_trim: moved ' || moved || '/' || wanted || ', left in public ' || left_in_public
                 || ', bodies [' || coalesce(body_callers, '') || '], cron [' || coalesce(cron_callers, '') || '], views [' || coalesce(view_callers, '')
                 || '], policies [' || coalesce(policy_callers, '') || '], defaults [' || coalesce(default_callers, '') || '], triggers [' || coalesce(trigger_callers, '')
                 || '], executable by an API role ' || still_executable end as verdict
  from v;
