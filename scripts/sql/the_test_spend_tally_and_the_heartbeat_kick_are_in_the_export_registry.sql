-- THE TEST-SPEND TALLY AND THE HEARTBEAT KICK ARE IN THE EXPORT REGISTRY (it_engineer, 19 Nov 2026).
--
-- #2063 created public.ai_test_spend_day and #2069 created public.resilience_detached_kick, both applied 19 Nov, and
-- neither inserted its public.table_export_registry row. scripts/checks/every_table_is_exported_or_explicitly_excluded
-- .test.mjs failed on main for both (found by the review of #2084). The tally is the accountant's record of what test
-- runs cost once their ai_cost_log rows were removed, so it is exported; the kick row is the last pg_net request id per
-- detached run, overwritten every tick, so it is a log.
set local statement_timeout = '30s';

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('ai_test_spend_day', true, 'accountant', 'per Dubai day, run tag, function and model: what test runs cost after their ai_cost_log rows were removed (#2063, ledger 1199); the books read it', 'it_engineer'),
  ('resilience_detached_kick', false, 'log', 'one row per detached resilience_ping run holding the last pg_net request id, overwritten every tick (#2069); nothing is lost if it is not exported', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

do $probe$
begin
  if (select count(*) from public.table_export_registry where table_name in ('ai_test_spend_day','resilience_detached_kick')) <> 2 then
    raise exception 'PROBE FAILED: both registry rows must exist';
  end if;
  raise notice 'PROBE OK: ai_test_spend_day exported (accountant), resilience_detached_kick excluded (log)';
end
$probe$;
