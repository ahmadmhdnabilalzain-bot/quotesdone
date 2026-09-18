-- THE 15-MINUTE TICK RAN OUT OF BUDGET AND THE END OF ITS LIST STOPPED RUNNING (18 Sep 2026, it_engineer).
--
-- MEASURED, on production, before anything here was written:
--   * fn:resilience_ping, 96 ticks/day, last 24 h: mean 80.4 s, max 140.9 s. The 06:45:21Z tick took
--     110,384 ms and observe recorded "slow run: 110383ms" — it hit DEADLINE_MS = 110,000 exactly.
--   * Consequence: `orphans` is 22nd of 25 steps, so the sanctions screen did not fire even though
--     fn_resilience_orphan_steps_due() returned sanctions:true and app_secrets.sanctions_screen_enabled
--     was 'true'. It had to be kicked by hand with fn_sanctions_screen_tick().
--   * Where the time goes (agent_runs rows of the sub-functions each tick calls, contained in the tick's
--     own started_at..finished_at window, 12 h to 18 Sep 07:00Z, ms per tick):
--         dropbox_backup 23,533   send_outbox 9,434   accountant 8,308   send_whatsapp 6,262
--         conversation_archive 5,387   sales_engineer 3,343   quote_compare 2,960
--         compliance_archive 1,073   pdf_native 1,021
--     ~61 s of the mean 86 s tick is those serial sub-calls; the rest is the RPC steps.
--
-- THE DEFECT IS NOT THE TOTAL, IT IS THE ORDER. 25 steps share one wall clock and run in a hard-coded
-- list order, so the SAME tail loses every time the front of the list runs long. Raising the deadline
-- moves the cliff; it does not remove it, and a compliance obligation that stops running because a
-- backup ran long is precisely the failure that has now happened once.
--
-- WHAT THIS CHANGES. Postgres already owns the cadence decision for eleven of these steps
-- (fn_dropbox_backup_due, fn_it_duties_due, fn_table_export_due, fn_resilience_orphan_steps_due, …).
-- This extends that pattern rather than inventing another: Postgres now also owns the ORDER, and the
-- order is STALENESS, not position. A step deferred this tick is more overdue next tick, so it moves
-- to the front. Nothing can starve by being last, because "last" is no longer a property of a step.
--
-- WHY NOT THE ALTERNATIVES:
--   * Split the list across several scheduled entry points by cadence — a second fixed list on a second
--     fixed clock. The fast list grows back (it grew by two steps this week) and starves its own tail.
--   * Give the long jobs their own trigger — the three biggest (dropbox_backup, send_outbox, accountant)
--     are queue drainers that genuinely need every tick; moving them changes which queue is starved.
--   * Run independent steps concurrently — real, but it shrinks the total without bounding any step, and
--     these steps contend on the same Postgres and the same edge-function CPU cap (an edge function has a
--     CPU cap a deadline does not bound: #686). Concurrency can be added later INSIDE a plan; it is not
--     what makes starvation impossible.
--   * Raise DEADLINE_MS — the founder's own rule against a check that passes while the thing it checks is
--     broken applies to a deadline too: a fuller list on a longer deadline is this same defect later.

-- ONE ROW PER STEP THE TICK CAN RUN. Shaped like public.it_duty_schedule (key, `every`, note), which is
-- the estate's existing home for "how often does this duty need to run", so an auditor reads one shape.
-- The declared columns (every, budget_ms, place, note) are the decision; the measured columns
-- (last_*, ewma_ms, deferrals) are what the tick writes back.
create table if not exists public.resilience_step (
  step            text primary key,
  -- The check is not decoration: the plan divides by extract(epoch from every), and a zero or negative
  -- cadence would make the step permanently due and permanently stalest — it would win rn = 1 for ever
  -- and starve everything else. The `greatest(…, 1)` floor in the plan stops the division error; this
  -- stops the row existing (independent review, ecc:database-reviewer, 18 Sep 2026).
  every           interval not null check (every > interval '0'),
  -- The step's own worst case in ms, used to decide whether it fits in what is left of the budget.
  -- Seeded from the per-tick attribution above; fn_resilience_step_record replaces it with ewma_ms
  -- once the step has run, so a wrong seed self-corrects within a few ticks.
  -- The step's EXPECTED cost in ms when it runs — not its worst case. It is what the plan adds up to
  -- decide what fits, and fn_resilience_step_record replaces it with ewma_ms from the first tick, so
  -- seeding a worst case would make the plan behave one way on day one and another way for ever after.
  -- Worst cases are the DEADLINE's job, not the budget's.
  --
  -- WHAT THE SEED IS AND IS NOT (said plainly, because it is an estimate and the estimate is visible).
  -- PER-STEP COST HAS NEVER BEEN MEASURED IN THIS ESTATE — the only number recorded today is the tick's
  -- total, which is the whole reason this defect was found late. The seeds are bounded from two things
  -- that WERE measured: each step's own AbortSignal timeout (a hard ceiling, read off the source) and
  -- the average duration of the sub-function it calls (agent_runs). The second is an UPPER bound, not
  -- an attribution: dropbox_backup ran 255 times in 6 hours against 24 ticks, so most of those rows
  -- belong to other callers and only some fall to this tick. Per-step cost stops being an estimate with
  -- the first tick after this is deployed — `tick.ms` in the response, ewma_ms in this column.
  budget_ms       integer not null check (budget_ms > 0),
  -- 'plan' = scheduled by staleness. 'last' = a drain that runs every tick after everything that
  -- writes to it, and is never subject to the budget cut (these are today's `always` steps plus the
  -- conversation archive, which must put a PDF behind every message within one beat).
  place           text not null default 'plan' check (place in ('plan', 'last')),
  -- The order WITHIN place='last', where the dependency is real: itEngineerAlertTick must raise what
  -- the detector just wrote, and the outbox must drain after everything that writes mail. It is a
  -- column and not the alphabet because the alphabet happening to give the right answer today is how a
  -- dependency gets broken by a rename.
  rank            integer not null default 0,
  note            text not null,
  last_started_at timestamptz,
  last_ok_at      timestamptz,
  last_ms         integer,
  ewma_ms         integer,
  deferrals       integer not null default 0,
  deferred_since  timestamptz
);
alter table public.resilience_step enable row level security;
-- Deliberately service-role only: the seats bypass RLS, nothing else may read or write the schedule.
drop policy if exists resilience_step_service_role_only on public.resilience_step;
create policy resilience_step_service_role_only on public.resilience_step
  as permissive for all to public using (false) with check (false);
revoke all on public.resilience_step from anon, authenticated;

-- THE SEED. `every` is a FLOOR ON HOW OFTEN THE TICK BOTHERS ASKING, never a second copy of the
-- routine's own due rule: every one of these steps still runs its own gate (fn_*_due) and still decides
-- for itself whether there is work. Where a step's real cadence is daily or weekly, asking every 15
-- minutes bought nothing and cost a round trip; where a step drains a queue a person is waiting on, the
-- floor is one tick. On conflict the DECLARED columns are refreshed and the measured ones are left
-- alone, so re-applying this file re-seeds the schedule without losing the measurements.
insert into public.resilience_step (step, every, budget_ms, place, rank, note) values
  ('digest',           interval '1 hour',    1000,  'plan', 0, 'fn_ceo_daily_digest_tick is a once-a-day gate; hourly is enough to catch its window'),
  ('ratings',          interval '15 min',    1500,  'plan', 0, 'fn_support_request_ratings_due is itself a 15-minute sweep'),
  ('backup',           interval '15 min',    1000,  'plan', 0, 'queue-driven (2,006 documents queued, measured 18 Sep), so it keeps a one-tick floor — but it only STARTS the drain now: dropbox_backup chains its own passes, so the tick kicks it and leaves, and this step costs one RPC instead of the 25 s it used to spend awaiting a worker that did not need awaiting'),
  ('backupVerify',     interval '6 hours',  25000,  'plan', 0, 'reconcile pass over what is already in Dropbox; nobody waits on it, but when it fires it is another dropbox_backup call, not a cheap gate'),
  ('dropboxHealth',    interval '2 hours',  10000,  'plan', 0, 'fn_it_dropbox_health_due is once a Dubai day, or 2 hours after an error'),
  ('tableExport',      interval '30 min',    1000,  'plan', 0, 'fn_table_export_due claims the Dubai day once after 03:00; the export itself runs in its own invocations, so this step only starts it'),
  ('backupPrune',      interval '6 hours',  15000,  'plan', 0, 'fn_backup_prune_tick runs one pass per Dubai day after that day''s export, then up to two 55 s prune workers'),
  ('weekly',           interval '2 hours',  20000,  'plan', 0, 'fn_accountant_weekly_report_tick is weekly; on the week boundary it also renders a PDF through pdf_native'),
  ('vat',              interval '1 hour',    1000,  'plan', 0, 'the VAT threshold moves over months, not minutes'),
  ('ceoWeekly',        interval '2 hours',   1000,  'plan', 0, 'fn_ceo_weekly_report_tick is weekly'),
  ('openrouter',       interval '1 hour',    4000,  'plan', 0, 'two calls to openrouter.ai for a daily meter reading; 15 s timeouts each'),
  ('ladder',           interval '15 min',     800,  'plan', 0, 'refund chases must be written before the outbox drain on the same tick'),
  ('refunds',          interval '15 min',    4500,  'plan', 0, 'money already approved: never make an approved refund wait a cadence. One of the accountant''s two calls, which averaged 4.2 s each'),
  ('accountantDuties', interval '30 min',    4500,  'plan', 0, 'the accountant''s other call; its own gates hold the daily duties'),
  ('whatsapp',         interval '15 min',    8800,  'plan', 0, 'drains the founder''s command channel; send_whatsapp averaged 8.8 s a call'),
  ('itdetect',         interval '15 min',    8000,  'plan', 0, 'the detector; three missed ticks produced a false SCHEDULER DOWN page on 17 Sep, so it keeps a one-tick floor'),
  ('itduties',         interval '30 min',    3000,  'plan', 0, 'fn_it_duties_due is a 55-minute gate'),
  ('itscheduled',      interval '30 min',    4000,  'plan', 0, 'fn_it_scheduled_due reads it_duty_schedule, whose shortest `every` is 1 hour'),
  ('itlater',          interval '30 min',    3000,  'plan', 0, 'IT duties 19-24, each gated in its own routine'),
  ('specoffer',        interval '15 min',    4000,  'plan', 0, 'a supplier is waiting on the spec offer; sales_engineer averaged 3.8 s a call'),
  ('orphans',          interval '15 min',   12000,  'plan', 0, 'send_sms, email_cron, wa_templates, doc_extract, email_triage and the weekly SANCTIONS SCREEN — the step that was starved. Its own ORPHAN_BUDGET_MS caps it at 60 s; 12 s is what it costs when most of its jobs are not due'),
  ('orgtasks',         interval '15 min',    1500,  'plan', 0, 'fn_org_task_consume_tick is a 15-minute consumer'),
  -- The three drains, in the order their dependencies require, appended after every planned step and
  -- outside the budget because they DELIVER. `archive` is here and not in the plan because the founder
  -- asked for the PDF within one beat, and because it is the step the 110 s deadline actually skipped:
  -- duty:heartbeat:archive, "not run: the tick passed its 110s deadline", seen 27 times by 18 Sep 07:17Z.
  ('it',               interval '15 min',    1000,  'last', 1, 'raises the findings the detector wrote this tick; must run AFTER itdetect'),
  ('outbox',           interval '15 min',    9500,  'last', 2, 'drains the mail AFTER everything that writes mail; send_outbox averaged 8.5 s a call'),
  ('archive',          interval '15 min',    6200,  'last', 3, 'every conversation message gets its PDF within one beat (founder, 14 Sep 2026); conversation_archive averaged 6.2 s a call')
on conflict (step) do update
   set every = excluded.every, budget_ms = excluded.budget_ms,
       place = excluded.place, rank = excluded.rank, note = excluded.note;

-- THE PLAN. Returns the steps to run, in order, and the due steps that did not fit.
--
-- HOW STARVATION BECOMES STRUCTURALLY IMPOSSIBLE — the whole point of this file:
--   1. The sort key is STALENESS RATIO: (now - last attempt) / every. It is not position in a list, and
--      no step owns a position any more.
--   2. Running a step resets its ratio to ~0 (fn_resilience_step_record stamps last_started_at).
--      Deferring a step does NOT touch last_started_at, so its ratio keeps rising.
--   3. The stalest due step is admitted UNCONDITIONALLY (`rn = 1`), whatever it costs. Without this a
--      step whose budget_ms exceeds the whole tick budget could never fit and would starve for ever —
--      the same defect one level down, which is how `orphans` deferring its own sanctions job was
--      already written (#691 rebuilt inside orphanTick).
--   Together: for any step S, every tick S is not run raises S's ratio while every step that ran drops
--   to ~0. After at most (number of due steps) ticks S has the maximum ratio, is rn = 1, and runs. The
--   bound is a number of ticks, not a hope.
--
-- THE RATIO IS TAKEN ON THE LAST ATTEMPT, NOT THE LAST SUCCESS. A step that fails every time would
-- otherwise never reset, sit at rn = 1 for ever and starve everything else — a fix that creates the
-- defect it fixes. Failure is reported the way it already is: the tick raises it through
-- fn_it_duty_settle as a heartbeat finding.
create or replace function public.fn_resilience_tick_plan(p_budget_ms integer default 70000)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with due as (
    select step, coalesce(ewma_ms, budget_ms) as cost, deferrals,
           extract(epoch from (now() - coalesce(last_started_at, now() - every - interval '365 days')))
             / greatest(extract(epoch from every), 1) as ratio
      from public.resilience_step
     where place = 'plan'
       and (last_started_at is null or now() - last_started_at >= every)
  ), ranked as (
    select *, row_number() over (order by ratio desc, step) as rn from due
  ), filled as (
    -- ponytail: prefix cut, not a knapsack. A large step near the front can leave budget unused; the
    -- staleness order still admits it next tick, so the cost is a beat, never a starved step. Swap in a
    -- fitting pass only if the measured deferral rate says the waste matters.
    select *, sum(cost) over (order by rn rows between unbounded preceding and current row) as cum
      from ranked
  ), decided as (
    select *, (rn = 1 or cum <= p_budget_ms) as admitted from filled
  )
  select jsonb_build_object(
    'budget_ms',  p_budget_ms,
    'planned_ms', coalesce((select sum(cost) from decided where admitted), 0),
    'run',        coalesce((select jsonb_agg(step order by rn) from decided where admitted), '[]'::jsonb)
                  || coalesce((select jsonb_agg(step order by rank, step) from public.resilience_step where place = 'last'), '[]'::jsonb),
    'deferred',   coalesce((select jsonb_agg(step order by rn) from decided where not admitted), '[]'::jsonb),
    -- A step that has been passed over four ticks running (an hour) is no longer "a beat late". It is
    -- returned so the tick raises it as an IT engineer finding, which is the alarm on the guarantee
    -- above: if the bound is ever not holding, this says so instead of the silence that cost the
    -- sanctions screen its run.
    'starved',    coalesce((select jsonb_agg(step order by deferrals desc, step)
                              from decided where not admitted and deferrals >= 4), '[]'::jsonb)
  );
$fn$;
revoke execute on function public.fn_resilience_tick_plan(integer) from public, anon, authenticated;

-- WHAT THE TICK WRITES BACK, IN ONE CALL. Per-step round trips would cost 25 of them a tick, which is
-- the budget this file exists to protect. p_rows is
--     [{"step":"backup","ms":33210,"ok":true}, {"step":"orphans","deferred":true}, …]
-- ok       -> the step ran and passed: attempt and success both stamped, ewma folded, deferrals cleared.
-- not ok   -> the step ran and failed: the ATTEMPT is stamped (so it cannot monopolise rn = 1) and
--             last_ok_at is left where it was, which is what an auditor reads to see how long a step has
--             been failing. The failure itself is raised as a finding by the caller, not here.
-- deferred -> nothing is stamped. That is the mechanism: an untouched last_started_at is what makes the
--             step stalest next tick.
-- A step name with no row is ignored rather than inserted: the schedule is a declaration, and a step
-- appearing in the code without a row here is caught by scripts/checks/every_tick_step_is_scheduled.mjs.
create or replace function public.fn_resilience_step_record(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_seen integer := 0;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'p_rows must be a jsonb array');
  end if;

  -- EVERY FIELD IS READ DEFENSIVELY, AND THE ARRAY IS DE-DUPLICATED (independent review,
  -- ecc:database-reviewer, 18 Sep 2026). Two findings, both about one bad element taking the whole call
  -- down or silently winning:
  --   * a malformed `ms` or `ok` ("12.5", 2) would raise a cast error, and because this is ONE
  --     `update … from` that aborts the whole batch — so no step gets its attempt stamped, every
  --     staleness ratio keeps rising, and the next plan is computed from a lie. A bad field now degrades
  --     to its default instead of taking the tick's whole record with it.
  --   * `update … from` with the same step twice picks an arbitrary source row, with no error and a
  --     row_count that still looks complete. `distinct on` makes the winner a decision: a step that RAN
  --     beats the same step reported deferred, because a stamped attempt is the truthful one.
  with parsed as (
    select e->>'step'                                                           as step,
           coalesce(e->>'deferred' = 'true', false)                             as deferred,
           coalesce(e->>'ok' = 'true', false)                                   as ok,
           case when e->>'ms' ~ '^[0-9]{1,9}$' then (e->>'ms')::integer end      as ms
      from jsonb_array_elements(p_rows) e
     where jsonb_typeof(e) = 'object' and e->>'step' is not null
  ), rows as (
    select distinct on (step) * from parsed order by step, deferred asc, ok desc, ms desc nulls last
  )
  update public.resilience_step s
     set last_started_at = case when r.deferred then s.last_started_at else now() end,
         last_ok_at      = case when not r.deferred and r.ok then now() else s.last_ok_at end,
         last_ms         = case when r.deferred then s.last_ms else coalesce(r.ms, s.last_ms) end,
         -- 0.7 old + 0.3 new: a single slow pass moves the estimate without owning it.
         ewma_ms         = case
                             when r.deferred or r.ms is null then s.ewma_ms
                             when s.ewma_ms is null then r.ms
                             else round(0.7 * s.ewma_ms + 0.3 * r.ms)::integer
                           end,
         deferrals       = case when r.deferred then s.deferrals + 1 else 0 end,
         deferred_since  = case when r.deferred then coalesce(s.deferred_since, now()) else null end
    from rows r
   where r.step = s.step;
  get diagnostics v_seen = row_count;

  return jsonb_build_object('ok', true, 'updated', v_seen);
end;
$fn$;
revoke execute on function public.fn_resilience_step_record(jsonb) from public, anon, authenticated;

-- THE BOARD an auditor (or the IT engineer's own duty pass) reads to see the guarantee holding: how
-- overdue each step is against its own cadence, and how long anything has been waiting.
create or replace function public.fn_resilience_step_board()
returns table (step text, every interval, overdue_ratio numeric, last_started_at timestamptz,
               last_ok_at timestamptz, ewma_ms integer, deferrals integer, deferred_since timestamptz)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select s.step, s.every,
         round((extract(epoch from (now() - coalesce(s.last_started_at, now() - s.every - interval '365 days')))
                / greatest(extract(epoch from s.every), 1))::numeric, 2),
         s.last_started_at, s.last_ok_at, s.ewma_ms, s.deferrals, s.deferred_since
    from public.resilience_step s
   order by 3 desc, s.step;
$fn$;
revoke execute on function public.fn_resilience_step_board() from public, anon, authenticated;
