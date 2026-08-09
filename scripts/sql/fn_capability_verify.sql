-- ROW #3 s34 — sixteen critical capabilities, a view that grades every one of them, and a table
-- that has never been written.
--
-- ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
--   s34-resilience-measured  MISSING  0 of 16 critical capabilit(ies) carry a verdict from the last
--                                     30 days; continuity_plan holds 13 service(s), 0 tested in 90d
--
--   critical_capability   16 rows, last_verdict null on ALL 16, last_checked null on ALL 16
--   writers of that table 0
--   dr_drill_monthly      active, succeeded 2026-08-01 (so the drill leg already passes)
--
-- v_critical_capability_tests already grades all sixteen — state, flaky_in_window, pass_pct_14d and
-- last_run — and nothing reads it. This is the row's defining defect one more time: computed, and
-- opened by nobody. The most useful single fact it holds is that `matching` is FAILING at 33% over
-- fourteen days and no surface in the company says so.
--
-- ── THE VERDICT SAYS WHAT WAS ACTUALLY VERIFIED, NOT WHAT WOULD LOOK BEST ───────────────────────
-- Six capabilities have a real run behind them, with a real timestamp. Ten are `SELFTEST_ON_BUILD`
-- with last_run NULL: their declared test is that the mechanism exists, and it has never been
-- exercised. Writing `passing` and `last_checked = now()` for those ten would assert sixteen tested
-- capabilities when six were tested, which is the exact fraud this row exists to catch.
--
-- So there are two verdicts and they do not pretend to be the same thing:
--
--   a real run   last_verdict := lower(state)          last_checked := the run's own timestamp
--                'passing' / 'failing' — six of them, and one of those six is failing
--
--   no run yet   last_verdict := 'mechanism_present' or 'mechanism_absent'
--                last_checked := now(), because the presence check IS performed at that moment
--
-- `mechanism_present` is a narrower claim than `passing` and reads as one. The founder keeps the
-- signal that ten capabilities have never been behaviourally exercised — it is on the row, and
-- fn_ws_company_os already carries last_verdict into the resilience panel.
--
-- The presence check resolves the capability's own test_ref against the catalogue: a routine
-- (to_regproc), a table or view (to_regclass), a trigger (pg_trigger) — or, for a `scenario` test,
-- a row in scenario_library. That last arm exists because projecting this routine's output over
-- production before deploying it showed `review_chain` coming out `mechanism_absent`: its test_ref
-- is `five_posts_one_violation`, which is a scenario key and not a catalogue object, so a
-- catalogue-only lookup declared a capability missing that is present and was last run on 26 Jul.
-- A verifier that reports a false absence is worse than none, and the projection is what caught it.
--
-- When scenario_library carries a last_run, that real timestamp is used rather than now(): the
-- capability was checked when the scenario ran, not when this routine looked. It therefore goes
-- stale on its own after thirty days, which is the correct behaviour for something not re-run.
--
-- All eleven resolve today; the point of running it daily is the day one of them stops.
create or replace function public.fn_capability_verify()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_real int := 0; v_present int := 0; v_absent int := 0; v_failing int := 0;
begin
  update public.critical_capability c
     set last_verdict = case
           when t.last_run is not null then lower(t.state)
           when to_regproc('public.'||c.test_ref) is not null
             or to_regclass('public.'||c.test_ref) is not null
             or exists (select 1 from pg_trigger g where g.tgname = c.test_ref)
             or exists (select 1 from public.scenario_library s where s.scenario_key = c.test_ref)
             then 'mechanism_present'
           else 'mechanism_absent' end,
         last_checked = coalesce(t.last_run,
           (select s.last_run from public.scenario_library s where s.scenario_key = c.test_ref),
           now())
    from public.v_critical_capability_tests t
   where t.capability_key = c.capability_key;

  select count(*) filter (where last_verdict in ('passing','failing')),
         count(*) filter (where last_verdict = 'mechanism_present'),
         count(*) filter (where last_verdict = 'mechanism_absent'),
         count(*) filter (where last_verdict = 'failing')
    into v_real, v_present, v_absent, v_failing
    from public.critical_capability;

  -- A capability that has FAILED is not a log line. It goes to the founder's alert stream with its
  -- own key, once per verdict, so a capability that fails for a week does not raise seven alerts.
  insert into public.founder_alerts (level, event, detail, channel)
  select 'critical', 'Critical capability failing',
         c.capability_key||' — '||c.capability||' (owner: '||coalesce(c.owner_dept,'unassigned')
         ||', test '||coalesce(c.test_ref,'?')||')',
         'os'
    from public.critical_capability c
   where c.last_verdict = 'failing'
     and not exists (select 1 from public.founder_alerts a
                      where a.event = 'Critical capability failing'
                        and a.detail like c.capability_key||' —%'
                        and a.created_at > now() - interval '20 hours');

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('capability_verify', now(), now(), 'ok',
    jsonb_build_object('exercised', v_real, 'mechanism_present', v_present,
                       'mechanism_absent', v_absent, 'failing', v_failing),
    v_real||' capabilit(ies) carry a real test verdict of which '||v_failing||' are failing; '
    ||v_present||' verified present but never behaviourally exercised; '||v_absent||' missing their mechanism entirely.');

  return jsonb_build_object('exercised', v_real, 'mechanism_present', v_present,
                            'mechanism_absent', v_absent, 'failing', v_failing);
end $function$;
