-- THE TRACE BOARD TIMED OUT ON EVERY BRANCH TODAY (3 Sep 2026).
--
-- fn_kernel_system_trace_state joins every cron.job_run_details row of every wrapped job (235,916
-- rows) and asks, per run, whether phase_c_system_execution holds a trace for the same component
-- and job within five seconds. phase_c_system_execution had no index on component_id, so that
-- correlated EXISTS was a sequential scan of 17,823 trace rows per run. It fitted inside the
-- management API's statement timeout until today; with 3,852 traces written since midnight (the
-- crons re-enabled on 2 Sep tick every minute) it stopped fitting, and three branches' kernel-gate
-- jobs went red on `57014 statement timeout, CONTEXT: SQL function "fn_kernel_system_trace_state"
-- statement 1` — the same error locally, three times, and standalone.
--
-- Measured in an aborted transaction: with this index the board returns in 72 s under the same
-- concurrent load (seven 24–116 s scorer queries in pg_stat_activity), against a timeout without it.
-- The board itself is not changed; the `runs` CTE is still unbounded and that is the next thing to
-- fix if 72 s ever becomes a timeout again.
--
--   node scripts/apply_sql.mjs scripts/sql/the_trace_board_needed_an_index_before_it_needed_a_bigger_timeout.sql --apply --ddl

create index if not exists phase_c_system_execution_component_started_idx
  on public.phase_c_system_execution (component_id, started_at);
