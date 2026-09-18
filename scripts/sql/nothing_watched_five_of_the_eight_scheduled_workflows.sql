-- NOTHING WATCHED FIVE OF THE EIGHT SCHEDULED WORKFLOWS.
--
-- MEASURED 17-18 Sep 2026 (it_engineer, wiring audit). The estate runs eight scheduled GitHub
-- workflows. fn_it_workflow_heartbeats() covered exactly two of them -- `dependency` and `platform`,
-- both from it-weekly-readings.yml -- and fn_it_duties adds `journey_heartbeat` for the nightly
-- journey. Nothing watched resilience-ping.yml, kb-embed-backfill.yml, project-parity.yml,
-- dropbox-backup-second-scheduler.yml or it-post-deploy-smoke.yml, and
-- scripts/checks/a_failed_scheduled_run_has_a_reader.RETIRED.mjs was retired with the phase
-- programme. That is why two outages ran their course in silence:
--   * the external resilience watchdog was red 4/4 days (14-17 Sep), and
--   * kb-embed-backfill failed six consecutive scheduled runs (10-15 Sep).
--
-- WHAT THIS CHANGES. The heartbeat list goes from two subjects to five, each keyed off a row the
-- workflow ALREADY writes, because a heartbeat watching a name nothing writes is this estate's own
-- recurring defect. Every key below was read out of production before it was added:
--
--   subject       every   key                                                       measured 18 Sep 04:0x
--   smoke         7 days  agent_runs it_engineer counts->>'job' = 'duty:smoke'       41 rows/30d, newest 02:52
--   dropbox_kick  12 h    agent_runs agent='backup_kick' counts->>'reason'
--                           = 'github_actions'                                       13 rows/30d, newest 17 Sep 21:44
--   parity        36 h    max(security_advisor_baseline.last_seen_at)                563 rows, newest 04:09
--   kb_embed      36 h    agent_runs it_engineer counts->>'job' = 'duty:kb_embed'    NO ROWS -- see below
--
-- kb_embed HAD NO KEY AT ALL. scripts/kb/run_embed_backfill.mjs wrote nothing to agent_runs, so
-- nothing could tell a night it ran from a night it did not; kb_chunks.embed_claimed_at is NOT a
-- freshness key either, because fn_kb_embed_harvest sets it back to null on success (it only ever
-- shows what is in flight -- the 7 Sep value standing in production today is a stuck claim, not a
-- stale corpus). That script now ends with fn_it_duty_ran('kb_embed', ...), which is the same key
-- shape as the three duties above. Until its next scheduled run at 02:20 UTC this subject has never
-- beaten, so it raises the `never` finding below ONCE and closes itself on that run. That finding is
-- true, not noise: today nothing can prove the backfill ran.
--
-- WHAT THIS DELIBERATELY DOES NOT ADD: a heartbeat for resilience-ping.yml.
-- fn_it_workflow_heartbeats is reached only from fn_it_duties_scheduled, which is called only from
-- resilience_ping's own `itscheduled` step. A heartbeat for resilience_ping evaluated by
-- resilience_ping is guarded by a condition that cannot occur -- if the tick stops, so does the thing
-- that would notice. resilience_ping's liveness is watched from OUTSIDE the cluster on purpose, by
-- .github/workflows/resilience-ping.yml and the Vercel cron, and both were repaired in the same
-- change (their timeouts were below the function's own 110 s deadline, so neither could ever see a
-- success). Adding an in-cluster copy would have looked like coverage and asserted nothing.
--
-- NOT CHANGED: the `dependency` and `platform` subjects, their 8-day interval, and the rule that
-- nothing is reported until the scheduled duties have themselves been running longer than the
-- interval -- so a workflow merged today is not called missing before its first schedule comes round.
-- Note in passing, not fixed here: duty:dependency and duty:platform have NO rows in the last 30
-- days, so it-weekly-readings.yml has not reported since before 19 Aug and the existing heartbeat
-- should already be raising both.

-- ── THE HEARTBEATS FOR EVERY SCHEDULED READING THAT ARRIVES FROM GITHUB ───────────────────────────
create or replace function public.fn_it_workflow_heartbeats()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_items jsonb := '[]'::jsonb; x record; v_running interval;
begin
  -- How long the scheduled duties have been running at all. The original guard asked this as an
  -- EXISTS per subject over the same set, so asking it once is the same test, and it now reads as
  -- what it is. Note what it is NOT: it is global, not per subject. A subject added today borrows
  -- its grace period from the oldest duty row of any kind — months — so it is judged from the first
  -- tick rather than after its own interval. That is why every key above was read out of production
  -- before it was added, and why kb_embed's "never beaten" is documented as expected rather than
  -- discovered in the finding ledger.
  select now() - min(started_at) into v_running
    from public.agent_runs where agent = 'it_engineer' and counts->>'job' like 'duty:%';
  if v_running is null then return public.fn_it_duty_settle('workflow_heartbeat', '[]'::jsonb); end if;

  for x in
    select 'dependency'::text job, interval '8 days' every,
           '.github/workflows/it-weekly-readings.yml'::text wf,
           (select max(started_at) from public.agent_runs
             where agent = 'it_engineer' and counts->>'job' = 'duty:dependency') last
    union all
    select 'platform', interval '8 days', '.github/workflows/it-weekly-readings.yml',
           (select max(started_at) from public.agent_runs
             where agent = 'it_engineer' and counts->>'job' = 'duty:platform')
    union all
    select 'smoke', interval '7 days', '.github/workflows/it-post-deploy-smoke.yml',
           (select max(started_at) from public.agent_runs
             where agent = 'it_engineer' and counts->>'job' = 'duty:smoke')
    union all
    select 'kb_embed', interval '36 hours', '.github/workflows/kb-embed-backfill.yml',
           (select max(started_at) from public.agent_runs
             where agent = 'it_engineer' and counts->>'job' = 'duty:kb_embed')
    union all
    -- The second scheduler kicks every 6 hours; 12 h is two missed kicks, not one late one.
    select 'dropbox_kick', interval '12 hours', '.github/workflows/dropbox-backup-second-scheduler.yml',
           (select max(started_at) from public.agent_runs
             where agent = 'backup_kick' and counts->>'reason' = 'github_actions')
    union all
    -- project-parity.yml runs daily AND on every pull request, and the advisor refresh step stamps
    -- last_seen_at on each of the 563 baseline rows.
    -- SAY WHAT THIS DOES NOT CATCH. The key cannot tell a scheduled run from a pull-request run, and
    -- this repository merges most days, so a permanently broken `schedule:` trigger — a cron run has
    -- no PR context and a different token scope, so it can fail on its own — would stay hidden behind
    -- the PR runs indefinitely. What this subject DOES catch is the whole workflow going quiet: no
    -- parity run of any kind for 36 hours, which is the weekend, the quiet day, and a deleted or
    -- disabled workflow. It is deliberately not claimed as coverage of the schedule itself; closing
    -- that would need the refresh step to record which trigger it ran under, and it does not.
    select 'parity', interval '36 hours', '.github/workflows/project-parity.yml',
           (select max(last_seen_at) from public.security_advisor_baseline)
  loop
    continue when v_running <= x.every;   -- the schedule has not had time to come round yet
    if x.last is null then
      -- NEVER BEAT. Zero cannot tell a dead guard from an idle system, so this is said in its own
      -- words rather than reported as "late": nothing has ever written the row this reads.
      v_items := v_items || jsonb_build_object('item', x.job, 'owner_seat', 'ceo', 'subject', 'github',
        'title', 'Nothing has ever reported a ' || x.job || ' run, so its workflow cannot be seen to fail',
        'blast', 'agent_facing', 'affected', 1,
        'evidence', jsonb_build_object('workflow', x.wf, 'every', x.every::text, 'last', null,
          'look_at', 'the workflow''s runs in GitHub Actions, then whether the step that reports back is present and reached'));
    elsif x.last < now() - x.every then
      v_items := v_items || jsonb_build_object('item', x.job, 'owner_seat', 'ceo', 'subject', 'github',
        'title', 'The ' || x.job || ' readings from GitHub have not arrived for ' || x.every,
        'blast', 'agent_facing', 'affected', 1,
        'evidence', jsonb_build_object('workflow', x.wf, 'every', x.every::text, 'last', x.last,
          'look_at', 'the workflow''s runs in GitHub Actions: not triggered, failed, or failed to report'));
    end if;
  end loop;
  return public.fn_it_duty_settle('workflow_heartbeat', v_items);
end $fn$;
revoke execute on function public.fn_it_workflow_heartbeats() from public, anon, authenticated;

-- ── WHAT EACH KEY READS, RIGHT NOW, BEFORE ANY OF IT IS BELIEVED ─────────────────────────────────
-- A read-only probe. It writes nothing, so it ends in `raise notice`: this file defines a routine,
-- and a `raise exception` here would take the create with it.
do $probe$
declare r record; v_missing text := '';
begin
  for r in
    select 'smoke' job, (select max(started_at) from public.agent_runs
                          where agent = 'it_engineer' and counts->>'job' = 'duty:smoke') last
    union all select 'kb_embed', (select max(started_at) from public.agent_runs
                          where agent = 'it_engineer' and counts->>'job' = 'duty:kb_embed')
    union all select 'dropbox_kick', (select max(started_at) from public.agent_runs
                          where agent = 'backup_kick' and counts->>'reason' = 'github_actions')
    union all select 'parity', (select max(last_seen_at) from public.security_advisor_baseline)
  loop
    raise notice 'heartbeat key %: last beat %', r.job, coalesce(r.last::text, 'NEVER');
    if r.last is null then v_missing := v_missing || r.job || ' '; end if;
  end loop;
  raise notice 'keys with no row yet: %', coalesce(nullif(v_missing, ''), '(none)');
end $probe$;
