-- TEST RUNS LEAVE NO COST ROW AN AGENT READS AS REAL, AND THE SPEND STAYS BOOKED AS TEST SPEND
-- (it_engineer; 19 Nov 2026; ledger 1199 "delete all test/demo data once and for all ... logs").
--
-- THE QUESTION: 5 e2e harness runs (qd_run:565c29cb 5c8cf44b 728bc26c b5ab99ec d421248d, all 17-18 Nov, after the 17 Nov
--   purge cutoff) left tagged rows in public.ai_cost_log. The ledger note of 18 Nov 07:16Z counted 148 (one run); the
--   four runs after it make it 548. Is deleting them safe, given the spend was REAL money billed by OpenRouter?
--
-- MEASURED (SELECT only, production, 19 Nov 2026):
--   ai_cost_log 33,962 rows; e2e_run_tag is not null on 548 (565c29cb 131, 5c8cf44b 148, 728bc26c 72, b5ab99ec 87,
--   d421248d 110), every one on Dubai day 18 Nov 2026, 17 Nov 23:51Z to 18 Nov 15:43Z; cost_usd_reported 2.516 USD
--   (cost_aed 10.61 AED); 384 carry an OpenRouter generation_id. fns: drawing_redact_verify 287, sales_engineer 148,
--   inquiry_intake 99, drawing_boq 10, drawing_redact 2, supplier_api 2. Untagged rows that ZZ DEMO runs left: 0
--   (model_used 'zz-demo/%' 0; agent_key/fn like %zz%/%demo% 0). The 9 untagged `load_probe` rows (11 Nov) are a latency probe,
--   and the untagged rows inside the long `check:` rehearsal windows are real traffic that ran at the same time: neither is touched.
--   The 5 windows are in rehearsal_window (ended, models_allowed false, cap 0.60 USD each).
--
-- WHAT READS ai_cost_log (pg_proc, 19 Nov): 39 routines; the books are NOT among them for their figures:
--   * the books are openrouter_meter (OpenRouter's own lifetime counter) -> fn_accountant_openrouter_tick -> openrouter_day and
--     expense_entries. 18 Nov is closed (openrouter_day reconciled_at 18 Nov 20:30Z: authoritative 4.7726 USD from the meter,
--     attributed 4.7172, unattributed 0.0554, expense_entries 3362). Those rows are stored, not recomputed; the IT
--     alarm fn_it_engineer_openrouter_unattributed reads openrouter_day, not ai_cost_log. Deleting a cost row moves none of them.
--   * what the rows DO feed live: fn_accountant_openrouter_breakdown (via v_openrouter_call_log) when a day is first closed,
--     and ~10 agent-facing spend figures that do NOT exclude e2e_run_tag (only 8 routines do): fn_company_snapshot
--     ai_cost_30d_aed, fn_ceo_planning_pack model_aed_30d_by_seat, fn_budget_available / fn_ai_route (dept month budget),
--     fn_it_cost_watch_tick (7 d vs 14 d), fn_wa_context ai_spend_today/month, fn_what_if, fn_accountant_unit_economics (month),
--     fn_accountant_weekly_report_figures, fn_it_engineer_model_spend (24 h). So until the rows are gone, 2.5 USD of test
--     traffic is read as the company's own spend by those seats.
--   * PRECEDENT, MEASURED: fn_demo_purge_run already deletes `ai_cost_log where e2e_run_tag is not null` (ruling 1199). It has
--     done so before: live v_openrouter_call_log now sums LESS than the stored openrouter_day.attributed_usd on 7 of the last 11 days
--     (10 Nov 2.60 vs 12.51, 11 Nov 0.51 vs 2.72, 12 Nov 2.49 vs 10.30, 13 Nov 0.49 vs 0.71, 15 Nov 0.94 vs 2.25, 16 Nov 2.74 vs 5.56,
--     17 Nov 1.94 vs 4.80 USD; about 27 USD of REAL spend whose row-level record is gone and whose only record is the daily
--     snapshot). That is the gap this file closes for the 18 Nov rows, and for every later purge.
--
-- DECISION: DELETE IS SAFE ONLY IF THE SPEND STAYS BOOKED. So this file does not just delete:
--   1. public.ai_test_spend_day: one row per (Dubai day, run tag, fn, model) with calls, priced calls, unpriced calls, USD, AED,
--      tokens, generation ids, first and last call. It is test spend, kept as a TOTAL, with no prompt hash, no seat, no payload.
--   2. a BEFORE DELETE row trigger on ai_cost_log (tagged rows only) that adds the row to that table, so EVERY purge from
--      now on, this one and fn_demo_purge_run's, leaves the day's test spend booked. The tally is the books' line for what
--      the meter charged that no seat spent: authoritative = attributed + test + unattributed.
--   3. the delete of the 548 rows, guarded: a row goes only when its run window is ENDED and its Dubai day is already CLOSED in
--      openrouter_day (reconciled_at not null). A tagged row that fails either guard stays and is named in the verdict.
--   NOT done here, deliberately: the 5 rehearsal_window rows (the next fn_demo_purge pass deletes them; they hold no spend), and
--   the ~10 readers above (rewriting 10 live routine bodies from a read of them is the next file's work, not this one's; see the
--   note at the foot). Once the rows are deleted the readers see nothing to exclude.
--
-- SEAT: it_engineer. APPLY: node scripts/apply_sql.mjs scripts/sql/test_runs_leave_no_cost_row_an_agent_reads_as_real.sql --apply --ddl,
--   then append it to scripts/sql/MANIFEST.txt (Edit, last line). ROLLBACK: drop trigger trg_ai_cost_log_keeps_test_spend on
--   public.ai_cost_log; drop function public.fn_ai_cost_log_keeps_test_spend(); drop table public.ai_test_spend_day. The deleted
--   cost rows are NOT restorable (ledger 1199 asks for exactly that); their totals are in ai_test_spend_day and openrouter_day.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

create table if not exists public.ai_test_spend_day (
  day              date    not null,                       -- Dubai day of the call
  e2e_run_tag      text    not null,
  fn               text    not null,
  model_used       text    not null,
  calls            integer not null default 0,
  priced_calls     integer not null default 0,
  unpriced_calls   integer not null default 0,             -- used a model, recorded no cost: UNKNOWN, never counted as zero
  cost_usd         numeric not null default 0,             -- priced calls only, as v_openrouter_call_log prices them
  cost_aed         numeric not null default 0,
  prompt_tokens    bigint  not null default 0,
  output_tokens    bigint  not null default 0,
  generation_ids   integer not null default 0,             -- calls OpenRouter can be asked about by id
  first_call_at    timestamptz not null,
  last_call_at     timestamptz not null,
  primary key (day, e2e_run_tag, fn, model_used)
);
comment on table public.ai_test_spend_day is
  'Real OpenRouter spend caused by e2e/rehearsal test runs, kept as a total after the tagged ai_cost_log rows are deleted (ledger 1199, 19 Nov 2026). Filled only by trg_ai_cost_log_keeps_test_spend. No seat reads it as the company''s own spend.';
alter table public.ai_test_spend_day enable row level security;
drop policy if exists ai_test_spend_day_service_role_only on public.ai_test_spend_day;
create policy ai_test_spend_day_service_role_only on public.ai_test_spend_day
  as permissive for all to public using (false) with check (false);
revoke all on public.ai_test_spend_day from public, anon, authenticated;

create or replace function public.fn_ai_cost_log_keeps_test_spend()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_fx  numeric;
  v_usd numeric;
begin
  if old.e2e_run_tag is null then return old; end if;
  select coalesce(max(num_value), 3.6725) into v_fx from public.gl_settings where key = 'usd_to_aed';
  -- priced exactly as v_openrouter_call_log prices a call: free when no model or cached, the provider's figure when reported,
  -- else the rate card, else UNKNOWN (counted in unpriced_calls, not in the money)
  v_usd := case when old.model_used = 'none' or old.cached then 0
                when old.cost_usd_reported is not null then old.cost_usd_reported
                when coalesce(old.cost_aed, 0) > 0 then round(old.cost_aed / v_fx, 6)
                else null end;
  insert into public.ai_test_spend_day as t
    (day, e2e_run_tag, fn, model_used, calls, priced_calls, unpriced_calls, cost_usd, cost_aed,
     prompt_tokens, output_tokens, generation_ids, first_call_at, last_call_at)
  values ((old.occurred_at at time zone 'Asia/Dubai')::date, old.e2e_run_tag, coalesce(old.fn, '(none)'), old.model_used,
          1, case when v_usd is not null then 1 else 0 end, case when v_usd is null then 1 else 0 end,
          coalesce(v_usd, 0), coalesce(v_usd, 0) * v_fx,
          coalesce(old.prompt_tokens, 0), coalesce(old.output_tokens, 0),
          case when old.generation_id is not null then 1 else 0 end, old.occurred_at, old.occurred_at)
  on conflict (day, e2e_run_tag, fn, model_used) do update set
    calls = t.calls + 1, priced_calls = t.priced_calls + excluded.priced_calls, unpriced_calls = t.unpriced_calls + excluded.unpriced_calls,
    cost_usd = t.cost_usd + excluded.cost_usd, cost_aed = t.cost_aed + excluded.cost_aed,
    prompt_tokens = t.prompt_tokens + excluded.prompt_tokens, output_tokens = t.output_tokens + excluded.output_tokens,
    generation_ids = t.generation_ids + excluded.generation_ids,
    first_call_at = least(t.first_call_at, excluded.first_call_at), last_call_at = greatest(t.last_call_at, excluded.last_call_at);
  return old;
end $$;
revoke all on function public.fn_ai_cost_log_keeps_test_spend() from public, anon, authenticated;

drop trigger if exists trg_ai_cost_log_keeps_test_spend on public.ai_cost_log;
create trigger trg_ai_cost_log_keeps_test_spend before delete on public.ai_cost_log
  for each row when (old.e2e_run_tag is not null) execute function public.fn_ai_cost_log_keeps_test_spend();

-- ---- the delete of the 18 Nov test rows, guarded -------------------------------------------------------------------------------
create temp table _tt_before on commit drop as
  select count(*)::int n, coalesce(sum(case when model_used = 'none' or cached then 0
                                            else coalesce(cost_usd_reported, round(nullif(cost_aed, 0) / (select coalesce(max(num_value), 3.6725) from public.gl_settings where key = 'usd_to_aed'), 6)) end), 0)::numeric(14,6) usd
    from public.ai_cost_log l
   where l.e2e_run_tag is not null
     and exists (select 1 from public.rehearsal_window w where w.run_tag = 'qd_run:' || l.e2e_run_tag and w.ended_at is not null)
     and exists (select 1 from public.openrouter_day o where o.day = (l.occurred_at at time zone 'Asia/Dubai')::date and o.reconciled_at is not null);
create temp table _tt_books on commit drop as
  select (select count(*) from public.openrouter_day) days, (select coalesce(sum(authoritative_usd), 0) from public.openrouter_day) auth,
         (select count(*) from public.expense_entries) exp_n, (select coalesce(sum(amount), 0) from public.expense_entries) exp_sum;

create temp table _tt_probe (step text, ok boolean, detail text) on commit drop;
create temp table _tt_tally0 on commit drop as
  select coalesce(sum(calls), 0)::bigint calls, coalesce(sum(cost_usd), 0)::numeric usd from public.ai_test_spend_day;

-- the delete runs in its own sub-transaction: when the tally's CHANGE is not the rows and the cost deleted, it raises and the delete
-- rolls back (the rows cannot be restored, so a wrong tally must never commit); the probe then records PROBE FAILED
do $del$
declare n int;
begin
  begin
    delete from public.ai_cost_log l
     where l.e2e_run_tag is not null
       and exists (select 1 from public.rehearsal_window w where w.run_tag = 'qd_run:' || l.e2e_run_tag and w.ended_at is not null)
       and exists (select 1 from public.openrouter_day o where o.day = (l.occurred_at at time zone 'Asia/Dubai')::date and o.reconciled_at is not null);
    get diagnostics n = row_count;
    if (select coalesce(sum(calls), 0) from public.ai_test_spend_day) - (select calls from _tt_tally0) <> n
       or abs((select coalesce(sum(cost_usd), 0) from public.ai_test_spend_day) - (select usd from _tt_tally0) - (select usd from _tt_before)) >= 0.0001 then
      raise exception 'tally change differs from the % rows deleted', n;
    end if;
  exception when others then
    insert into _tt_probe values ('the delete and its tally agree (else the delete is rolled back)', false, sqlerrm);
  end;
end $del$;

-- ---- PROBE (the file holds DDL, so it cleans up after itself and ends in a verdict row; only the delete's own sub-transaction raises, to roll itself back) ---------------------
-- 1 the tally holds what the delete removed; 2 the books did not move; 3 a probe row, tagged, then deleted, lands in the tally and
-- is removed from both; 4 an UNtagged row's delete writes nothing to the tally. The probe row is fn 'zz_probe_test_spend', model
-- 'zz-demo/probe': no person, no model call and no message can be reached from it.
do $probe$
declare v_id bigint; v_id2 bigint; n0 int; n1 int; c numeric;
begin
  insert into _tt_probe select 'tally holds the deleted rows', (select coalesce(sum(calls), 0) from public.ai_test_spend_day) - (select calls from _tt_tally0) = (select n from _tt_before),
         'tally change ' || ((select coalesce(sum(calls), 0) from public.ai_test_spend_day) - (select calls from _tt_tally0)) || ' vs deleted ' || (select n from _tt_before);
  insert into _tt_probe select 'tally USD equals the deleted USD (to 0.0001)',
         abs((select coalesce(sum(cost_usd), 0) from public.ai_test_spend_day) - (select usd from _tt_tally0) - (select usd from _tt_before)) < 0.0001,
         'tally change ' || ((select coalesce(sum(cost_usd), 0) from public.ai_test_spend_day) - (select usd from _tt_tally0)) || ' vs deleted ' || (select usd from _tt_before);
  insert into _tt_probe select 'the books did not move', (select (select count(*) from public.openrouter_day) = b.days
                                                           and (select coalesce(sum(authoritative_usd), 0) from public.openrouter_day) = b.auth
                                                           and (select count(*) from public.expense_entries) = b.exp_n
                                                           and (select coalesce(sum(amount), 0) from public.expense_entries) = b.exp_sum from _tt_books b), 'openrouter_day + expense_entries';
  insert into _tt_probe select 'no tagged row is left that passes the guards',
         not exists (select 1 from public.ai_cost_log l where l.e2e_run_tag is not null
                      and exists (select 1 from public.rehearsal_window w where w.run_tag = 'qd_run:' || l.e2e_run_tag and w.ended_at is not null)
                      and exists (select 1 from public.openrouter_day o where o.day = (l.occurred_at at time zone 'Asia/Dubai')::date and o.reconciled_at is not null)),
         (select count(*) from public.ai_cost_log where e2e_run_tag is not null) || ' tagged rows remain (guard-failing ones stay on purpose)';

  select count(*) into n0 from public.ai_test_spend_day where e2e_run_tag = 'zzprobe0';
  insert into public.ai_cost_log (fn, model_used, cached, ok, cost_usd_reported, cost_aed, prompt_tokens, output_tokens, generation_id)
    values ('zz_probe_test_spend', 'zz-demo/probe', false, true, 0.25, 0.9181, 10, 5, 'zz-probe-gen') returning id into v_id;
  update public.ai_cost_log set e2e_run_tag = 'zzprobe0' where id = v_id;
  insert into public.ai_cost_log (fn, model_used, cached, ok, cost_usd_reported, cost_aed)
    values ('zz_probe_test_spend', 'zz-demo/probe', false, true, 0.5, 1.8363) returning id into v_id2;   -- untagged
  delete from public.ai_cost_log where id in (v_id, v_id2);
  select count(*), coalesce(sum(cost_usd), 0) into n1, c from public.ai_test_spend_day where e2e_run_tag = 'zzprobe0';
  insert into _tt_probe values ('a tagged delete is tallied, an untagged one is not', n0 = 0 and n1 = 1 and c = 0.25, 'tally rows ' || n1 || ', usd ' || c);
  delete from public.ai_test_spend_day where e2e_run_tag = 'zzprobe0';
  insert into _tt_probe values ('the probe left nothing behind',
    not exists (select 1 from public.ai_cost_log where fn = 'zz_probe_test_spend') and not exists (select 1 from public.ai_test_spend_day where e2e_run_tag = 'zzprobe0'), '');
  insert into _tt_probe select 'the trigger function is not callable by a client',
    not has_function_privilege('anon', 'public.fn_ai_cost_log_keeps_test_spend()', 'execute')
    and not has_function_privilege('authenticated', 'public.fn_ai_cost_log_keeps_test_spend()', 'execute'), '';
  insert into _tt_probe select 'the tally table is closed to clients',
    not has_table_privilege('anon', 'public.ai_test_spend_day', 'select') and not has_table_privilege('authenticated', 'public.ai_test_spend_day', 'select'), '';
exception when others then
  insert into _tt_probe values ('probe raised', false, sqlerrm);
end $probe$;

select case when bool_and(ok) then 'PROBE OK' else 'PROBE FAILED: ' || string_agg(step || ' (' || detail || ')', '; ') filter (where not ok) end as verdict,
       (select n from _tt_before) as rows_deleted, (select usd from _tt_before) as usd_kept_in_tally,
       (select count(*) from public.ai_cost_log where e2e_run_tag is not null) as tagged_rows_left
  from _tt_probe;

-- NOTE FOR THE NEXT FILE (not done here): the readers that sum ai_cost_log without `e2e_run_tag is null` (list in the header) should read
-- one view, public.v_ai_cost_real (= ai_cost_log where e2e_run_tag is null), so a run that has not been purged yet is invisible to
-- every seat. v_openrouter_call_log and fn_accountant_openrouter_breakdown must keep reading ALL rows: that is how a day reconciles to the meter.
