-- NOTHING WATCHED THE DATABASE BACKUPS.
--
-- 9 September 2026. Fixing fn_backup_watch — which read `agent_runs where agent = 'backup'`, a name
-- nothing has ever written, and therefore reported catastrophe on every call it ever made — exposed
-- a bigger hole than the bug. That watcher was the only thing in the estate with "backup" in its
-- name, and once it was pointed at the subject it can actually see (the Dropbox document mirror),
-- the count of routines watching the DATABASE backups was zero.
--
-- The company's records live in one Postgres database. Its documents had a watcher. It did not.
--
-- WHAT THIS ADDS: an eighth detector, D8, inside fn_it_detect. It is added INSIDE rather than as a
-- standalone routine for a structural reason — fn_it_detect resolves every it_watch_finding whose
-- detector_key it did not just produce, so a separate function writing to that table would have its
-- finding closed by the very next tick. A detector that is not part of the tick is a detector that
-- silently un-fires.
--
-- WHY pg_stat_archiver AND NOT THE MANAGEMENT API. The daily physical backups are taken outside the
-- database. Their status is readable only through the Supabase management API, which needs a
-- personal access token this estate does not hold and which would hand an edge function full
-- project admin — a credential decision, and not one to make as a side effect of adding a monitor.
-- But those snapshots are built on continuous WAL archiving, and pg_stat_archiver is the archiver's
-- own counter, readable from inside with no credential whatsoever. If archiving stops, the chain
-- that feeds the snapshots stops, and D8 sees it inside the hour.
--
-- MEASURED WHILE WRITING THIS, so the thresholds are not invented:
--
--   archived_count      69,283 since stats_reset 2026-05-22 15:11 UTC — roughly one segment every
--                       two to three minutes across 110 days.
--   last_archived_time  2026-09-09 08:19:04 UTC, ninety seconds before the read.
--   failed_count        0. last_failed_time NULL.
--   management API      seven consecutive COMPLETED daily physical backups, 2 Sep - 8 Sep, WAL-G on,
--                       PITR off. The chain is healthy today; what was missing was anyone watching.
--
-- Against one segment every few minutes, sixty minutes of silence is not a quiet period. Four hours
-- escalates it from high to critical.
--
-- THE FAILURE TEST IS A TIME, NOT A COUNT. failed_count is cumulative since stats_reset, so
-- `failed_count > 0` would stay true forever after a single bad hour in May and would be exactly
-- the kind of permanently-true alarm this whole file exists because of. D8 tests last_failed_time
-- against the same one-hour window every other detector uses.
--
-- AND ZERO IS NOT A FINDING. If archived_count is 0, the instrument has never once observed
-- archiving working, and a lookup that has never seen success cannot report failure. That case goes
-- to notes as `basis: unproven` and raises nothing. That branch IS the lesson from fn_backup_watch,
-- written into the detector rather than into a comment.
--
-- WHAT D8 STILL CANNOT SEE, NAMED RATHER THAN LEFT TO BE DISCOVERED: whether a nightly snapshot
-- COMPLETED. Healthy archiving with a broken snapshot pipeline reads clean here. Every finding and
-- the healthy note both carry `not_covered` saying so. Closing that needs the management API and a
-- token the founder would have to mint, which is his call and not a monitor's.
--
-- Everything else in this definition is byte-identical to what was live; only the D8 block, its six
-- variables and the routine's own comment (seven detectors -> eight) changed.

create or replace function public.fn_it_detect(p_web jsonb default null, p_persist boolean default true)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $fn$
declare
  -- The window is one hour and the baseline is the seven days BEFORE it. The window has to be
  -- long enough that a 30-minute job appears in it and short enough that a fault is news.
  c_win       constant interval := interval '60 minutes';
  c_base      constant interval := interval '7 days';
  -- Statuses agent_runs uses for "this run did its job". Anything else, NULL included, is a
  -- failure: a run that started and never recorded an outcome is not a success.
  c_ok        constant text[] := array['ok','success','completed','skipped','warn','held','noop'];
  v_now       timestamptz := now();
  v_find      jsonb := '[]'::jsonb;
  v_notes     jsonb := '{}'::jsonb;
  v_keys      text[] := '{}';
  v_worst     text := 'none';
  r           record;
  v_rate      numeric;
  v_brate     numeric;
  v_state     text;
  v_sev       text;
  v_key       text;
  v_prev      timestamptz;
  v_gap       numeric;
  v_cnt       bigint;
  v_oldest    timestamptz;
  v_age       numeric;
  v_basis     jsonb;
  v_opened    int := 0;
  v_resolved  int := 0;
  v_watched   int;
  v_site_ms   integer;
  v_site_st   integer;
  -- D8, the backup chain. Read from pg_stat_archiver, which needs no credential.
  v_arch_n       bigint;
  v_arch_at      timestamptz;
  v_arch_fail    bigint;
  v_arch_fail_at timestamptz;
  v_arch_reset   timestamptz;
  v_arch_age     numeric;
begin

-- ══ D1. EDGE FUNCTIONS / AGENTS FAILING, OR FAILING MORE THAN USUAL ═════════════════════════
-- Reads: public.agent_runs (window vs the 7 days before it), public.it_watch_subject.
-- Fires when every attempt in the window failed ('stopped'), or when the window's failure rate is
-- at least 20 percentage points above this subject's own baseline rate ('degraded').
-- ON AN IDLE ESTATE: an agent with no runs in the window is not evaluated at all, and an agent
-- whose runs all succeeded produces nothing. Silence here means "nothing failed", and D2 below is
-- what stops that being confused with "nothing ran".
-- The `fn:<name>` telemetry rows and the bare `<name>` semantic rows are two logs of the SAME
-- subject, so the prefix is stripped before grouping: otherwise one function appears as two, and
-- neither half can be looked up in it_watch_subject to find out whether it is customer-facing.
for r in
  with runs as (
    select regexp_replace(agent, '^fn:', '')                       subject,
           agent, started_at,
           coalesce(status,'error') <> all (c_ok)                  bad,
           public.fn_it_run_is_refusal(agent, started_at, counts)  refused
    from public.agent_runs
    where started_at > v_now - c_base),
  w as (
    select subject,
           count(*) filter (where not refused)::int              n,
           count(*) filter (where bad and not refused)::int      f,
           count(*) filter (where refused)::int                  refused
    from runs where started_at > v_now - c_win group by subject),
  b as (
    select subject,
           count(*) filter (where not refused)::int              n,
           count(*) filter (where bad and not refused)::int      f
    from runs where started_at <= v_now - c_win group by subject)
  select w.subject agent, w.n, w.f, w.refused, coalesce(b.n,0) bn, coalesce(b.f,0) bf,
         coalesce(s.public_surface,false) pub, (s.subject is not null) known
  from w
  left join b on b.subject = w.subject
  left join public.it_watch_subject s on s.subject = w.subject
  where w.f > 0 and w.n > 0
loop
  v_rate  := r.f::numeric / r.n;
  v_brate := case when r.bn >= 10 then r.bf::numeric / r.bn else null end;
  v_state := case
               when r.f = r.n then 'stopped'
               when r.n >= 3 and (v_rate - coalesce(v_brate, 0)) >= 0.20 then 'degraded'
               else null end;
  continue when v_state is null;
  v_sev := public.fn_it_severity(v_state, r.pub);
  v_key := 'run_failure:' || r.agent;
  v_keys := v_keys || v_key;
  v_find := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'run_failure', 'subject', r.agent,
    'state', v_state, 'severity', v_sev,
    'title', case when v_state = 'stopped'
                  then r.agent || ' failed every one of its ' || r.n || ' attempts in the last hour'
                  else r.agent || ' is failing ' || round(v_rate*100) || '% of attempts, against a baseline of '
                       || coalesce(round(coalesce(v_brate,0)*100)::text,'?') || '%' end,
    'evidence', jsonb_build_object(
      'window_runs', r.n, 'window_failed', r.f, 'window_rate', round(v_rate,4),
      -- Counted, reported, and excluded from the rate above. A caller turned away is not a fault
      -- of this subject; a SURGE of them is a signal the security build owns, not this one.
      'window_refused', r.refused,
      'baseline_runs', r.bn, 'baseline_failed', r.bf,
      'baseline_rate', case when v_brate is null then null else round(v_brate,4) end,
      'baseline_basis', case when r.bn >= 10 then 'measured' else 'insufficient_history' end,
      'public_surface', r.pub,
      'surface_basis', case when r.known then 'supabase/config.toml verify_jwt'
                            else 'subject not in it_watch_subject; treated as internal' end));
end loop;

-- ══ D2. A SUBJECT THAT HAS STOPPED RUNNING WHEN IT SHOULD BE RUNNING ═══════════════════════
-- Reads: public.agent_runs, seven days of it.
-- The hard part is telling a SCHEDULED subject from an EVENT-DRIVEN one, because a subject that
-- only runs when a customer does something is supposed to be silent on a quiet day, and a
-- detector that cannot tell the difference is the "guard that fires when the system works" this
-- estate keeps paying for. Measured 9 Sep 2026, sales_engineer had 105 runs about a minute apart
-- inside a single two-hour burst and had then been silent for four hours — legitimately, because
-- it is event-driven. So a subject qualifies for silence monitoring only when its own history
-- shows a RHYTHM, on all three counts:
--   >= 10 gaps      — enough samples for a median to mean anything
--   >= 12 distinct hours with a run over 7 days — it recurs across time, it is not one burst
--   p90 gap <= 3x p50 gap — the gaps are TIGHT; a bursty subject has p90 far above p50
-- Then it is silent when it has been quiet for more than 4x its own median gap (floor 30 min).
-- ON AN IDLE ESTATE, measured on the live data: exactly ONE of the eight subjects in agent_runs
-- qualifies today — send_outbox (37 distinct hours, p50 30.1 min, p90 45.0 min, ratio 1.5).
-- login_otp (ratio 187), sales_engineer and accountant (2 and 4 distinct hours) are correctly
-- excluded as event-driven. The count of qualifying subjects is reported in notes.cadence, so
-- "no silence findings" can never be mistaken for "nothing is being watched".
v_watched := 0;
for r in
  with s0 as (
    select regexp_replace(agent, '^fn:', '') agent, started_at
    from public.agent_runs where started_at > v_now - c_base),
  g as (
    select agent, started_at,
           extract(epoch from (started_at - lag(started_at) over (partition by agent order by started_at)))/60 gap
    from s0),
  c as (
    select agent,
           count(*) filter (where gap > 0)::int                                   samples,
           count(distinct date_trunc('hour', started_at))::int                    hours,
           (percentile_cont(0.5) within group (order by gap) filter (where gap > 0))::numeric p50,
           (percentile_cont(0.9) within group (order by gap) filter (where gap > 0))::numeric p90,
           max(started_at)                                                        last_run
    from g group by agent)
  select c.*, coalesce(s.public_surface,false) pub,
         extract(epoch from (v_now - c.last_run))/60 silent_min
  from c left join public.it_watch_subject s on s.subject = c.agent
  where c.samples >= 10 and c.hours >= 12 and c.p50 > 0 and c.p90 <= c.p50 * 3
loop
  v_watched := v_watched + 1;
  continue when r.silent_min <= greatest(r.p50 * 4, 30);
  v_sev := public.fn_it_severity('stopped', r.pub);
  v_key := 'run_silent:' || r.agent;
  v_keys := v_keys || v_key;
  v_find := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'run_silent', 'subject', r.agent,
    'state', 'stopped', 'severity', v_sev,
    'title', r.agent || ' has not run for ' || round(r.silent_min) || ' minutes; it normally runs every '
             || round(r.p50) || ' minutes',
    'evidence', jsonb_build_object(
      'silent_minutes', round(r.silent_min,1), 'last_run', r.last_run,
      'cadence_p50_min', round(r.p50,2), 'cadence_p90_min', round(r.p90,2),
      'cadence_samples', r.samples, 'distinct_hours_7d', r.hours,
      'threshold_min', round(greatest(r.p50 * 4, 30),1),
      'basis', 'measured from this subject''s own inter-run gaps over 7 days',
      'public_surface', r.pub));
end loop;
v_notes := v_notes || jsonb_build_object('cadence', jsonb_build_object(
  'subjects_with_a_measurable_rhythm', v_watched,
  'basis', case when v_watched = 0
                then 'no subject in agent_runs yet recurs regularly enough to have a cadence; silence cannot be detected for any subject'
                else 'measured' end));

-- ══ D3. THE SCHEDULER ITSELF ════════════════════════════════════════════════════════════════
-- Reads: public.it_watch_tick — its own previous row.
-- The live scheduler is Vercel cron -> /api/resilience-ping -> resilience_ping, every 15 minutes.
-- pg_cron is dead by founder instruction (one inactive job; 234 deleted on 7 Sep), so any check
-- that reads cron.job_run_details to judge scheduler health is now reading a table nothing writes
-- — a guard that cannot fire. The gap between two rows of this table cannot be fooled that way:
-- if the tick did not happen, there is no row, and the next tick reports the hole it fell into.
-- ON AN IDLE ESTATE: silent, because the tick still runs on an idle estate. On the very first
-- tick there is no previous row, and it reports basis 'first_tick' rather than a clean bill.
select max(ran_at) into v_prev from public.it_watch_tick;
if v_prev is null then
  v_notes := v_notes || jsonb_build_object('scheduler', jsonb_build_object(
    'basis','first_tick','detail','no previous tick recorded; the gap detector arms from the next tick onward'));
else
  v_gap := extract(epoch from (v_now - v_prev))/60;
  v_notes := v_notes || jsonb_build_object('scheduler', jsonb_build_object(
    'basis','measured','gap_minutes', round(v_gap,1), 'expected_minutes', 15, 'threshold_minutes', 45));
  if v_gap > 45 then
    v_sev := public.fn_it_severity('stopped', false);
    v_key := 'scheduler_gap';
    v_keys := v_keys || v_key;
    v_find := v_find || jsonb_build_object(
      'detector_key', v_key, 'detector', 'scheduler_gap', 'subject', 'scheduler',
      'state', 'stopped', 'severity', v_sev,
      'title', 'the 15-minute scheduler went ' || round(v_gap) || ' minutes without a tick — at least three were missed',
      'evidence', jsonb_build_object(
        'gap_minutes', round(v_gap,1), 'previous_tick', v_prev, 'expected_every_minutes', 15,
        'path','Vercel cron -> /api/resilience-ping -> resilience_ping',
        'basis','measured from the interval between this tick and the previous one'));
  end if;
end if;

-- ══ D4. DATABASE AND FUNCTION ERRORS ════════════════════════════════════════════════════════
-- Reads: public.error_events (the capture a sibling build is filling right now).
-- THIS IS THE DETECTOR MOST AT RISK OF THE "zero cannot tell a dead guard from an idle system"
-- failure, because error_events has held 0 rows for its entire existence. So it never reports a
-- clean bill from emptiness: capture_alive is computed from whether ANY row landed in seven days,
-- and while that is false the engine says 'no_capture_yet' out loud.
select count(*) into v_cnt from public.error_events where created_at > v_now - c_base;
v_notes := v_notes || jsonb_build_object('error_capture', jsonb_build_object(
  'capture_alive', v_cnt > 0, 'rows_7d', v_cnt,
  'basis', case when v_cnt > 0 then 'measured'
                else 'no_capture_yet — error_events is empty, so an absence of findings here proves nothing' end));
for r in
  select e.source, e.kind,
         count(*)::int n,
         count(*) filter (where lower(coalesce(e.severity,'error')) in ('critical','fatal'))::int crit,
         coalesce(s.public_surface,false) pub
  from public.error_events e
  left join public.it_watch_subject s on s.subject = e.source
  where e.created_at > v_now - c_win
    and lower(coalesce(e.severity,'error')) <> all (array['info','debug','notice','warn','warning'])
  group by e.source, e.kind, s.public_surface
loop
  v_state := case when r.crit > 0 then 'stopped' else 'degraded' end;
  v_sev   := public.fn_it_severity(v_state, r.pub);
  v_key   := 'error_events:' || coalesce(r.source,'?') || ':' || coalesce(r.kind,'?');
  v_keys  := v_keys || v_key;
  v_find  := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'error_events', 'subject', coalesce(r.source,'unknown'),
    'state', v_state, 'severity', v_sev,
    'title', r.n || ' ' || coalesce(r.kind,'error') || ' error(s) from ' || coalesce(r.source,'an unnamed source')
             || ' in the last hour' || case when r.crit > 0 then ', ' || r.crit || ' of them critical' else '' end,
    'evidence', jsonb_build_object(
      'window_errors', r.n, 'critical', r.crit, 'kind', r.kind,
      'public_surface', r.pub, 'basis','measured from error_events rows in the window'));
end loop;

-- ══ D5. A QUEUE NOBODY IS DRAINING ══════════════════════════════════════════════════════════
-- Reads: public.it_watch_queue, and each registered table by its own predicate.
-- The test is the AGE of the oldest pending row against that queue's own threshold — never the
-- depth. A backlog of 400 rows that is one minute old is a busy queue; one row that is nine weeks
-- old is a dead consumer.
-- ON AN IDLE ESTATE: a queue with nothing pending is skipped before any threshold is consulted,
-- so an empty estate produces nothing. The two queues that are genuinely stalled today
-- (exec_reports at status='new' since 6 July, doc_backups at status='error' since 11 July) do
-- fire, correctly — they are real, and neither is a business volume.
for r in select * from public.it_watch_queue where enabled order by queue_key loop
  begin
    execute format('select count(*), min(%I) from public.%I where %s', r.ts_column, r.table_name, r.pending_predicate)
      into v_cnt, v_oldest;
  exception when others then
    v_notes := v_notes || jsonb_build_object('queue_' || r.queue_key,
      jsonb_build_object('basis','unreadable','error', sqlerrm));
    continue;
  end;
  continue when coalesce(v_cnt,0) = 0 or v_oldest is null;
  v_age := extract(epoch from (v_now - v_oldest))/60;
  continue when v_age <= r.stall_minutes;
  v_state := case when v_age > r.stall_minutes * 4 then 'stopped' else 'degraded' end;
  v_sev   := public.fn_it_severity(v_state, r.surface = 'customer');
  v_key   := 'queue_stalled:' || r.queue_key;
  v_keys  := v_keys || v_key;
  v_find  := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'queue_stalled', 'subject', r.queue_key,
    'state', v_state, 'severity', v_sev,
    'title', r.table_name || ': ' || v_cnt || ' undrained row(s), the oldest waiting '
             || round(v_age/60) || ' hours against a ' || round(r.stall_minutes/60.0) || '-hour threshold',
    'evidence', jsonb_build_object(
      'pending_rows', v_cnt, 'oldest_pending', v_oldest, 'oldest_age_minutes', round(v_age,1),
      'threshold_minutes', r.stall_minutes, 'predicate', r.pending_predicate,
      'public_surface', r.surface = 'customer',
      'basis','measured from the age of the oldest row matching the predicate'));
end loop;

-- ══ D6. LATENCY — THE FOUNDER'S OWN EXAMPLE ═════════════════════════════════════════════════
-- Reads: public.agent_runs, finished_at - started_at.
-- "Lagging" is meaningless without a baseline, so the baseline is each subject's own trailing
-- seven days ENDING at the start of the window (the window cannot pollute its own reference).
-- A departure has to clear three bars at once, and the three exist to stop three different false
-- positives: above the subject's own p95 (not just above typical), at least double its median
-- (not a 5% drift), and at least one second in absolute terms (so a 2ms -> 5ms move on a subject
-- that does nothing is not an incident).
--
-- WHAT IT DOES ON DAY ONE, said plainly rather than implied. Measured on the live data, 9 Sep:
--   send_outbox   65 samples, p50 9,956ms, p95 21,320ms -> 'measured'. Armed. Fires above ~21.3s.
--   sales_engineer / accountant / compliance_archive — every duration is exactly 0ms, because
--       their writer sets finished_at = started_at. Zero spread is not a fast subject, it is NO
--       SIGNAL, and it is reported as 'no_latency_signal' rather than as a healthy baseline.
--   login_otp / dropbox_backup / quote_extract / doc_extract — under 20 samples ->
--       'insufficient_history'.
-- So exactly ONE subject has a real latency baseline today. Every subject the sibling build
-- instruments with timing will arm itself here automatically once it has 20 runs; nothing needs
-- editing. The per-subject basis is returned in notes.latency every tick, so the founder's
-- "the comparison report is lagging" can be answered with either a departure or an honest "there
-- is not enough history of that report yet to know", and never with a false all-clear.
v_basis := '{}'::jsonb;
for r in
  -- A 403 returned in four milliseconds is not a measurement of how long this subject's work
  -- takes, so refusals are excluded from the baseline as well as from the failure rate. Left in,
  -- they would drag the baseline down and make ordinary work look like a departure.
  with d as (
    select regexp_replace(agent, '^fn:', '') agent, started_at,
           extract(epoch from (finished_at - started_at)) * 1000 ms
    from public.agent_runs
    where finished_at is not null and finished_at >= started_at and started_at > v_now - c_base
      and not public.fn_it_run_is_refusal(agent, started_at, counts)),
  b as (
    select agent, count(*)::int n,
           (percentile_cont(0.50) within group (order by ms))::numeric p50,
           (percentile_cont(0.95) within group (order by ms))::numeric p95,
           min(ms)::numeric mn, max(ms)::numeric mx
    from d where started_at <= v_now - c_win group by agent),
  w as (
    select agent, count(*)::int n,
           (percentile_cont(0.50) within group (order by ms))::numeric p50
    from d where started_at > v_now - c_win group by agent)
  select b.agent, b.n bn, b.p50 bp50, b.p95 bp95, b.mn bmn, b.mx bmx,
         w.n wn, w.p50 wp50, coalesce(s.public_surface,false) pub
  from b
  left join w on w.agent = b.agent
  left join public.it_watch_subject s on s.subject = b.agent
loop
  v_state := null;
  if r.bn < 20 then
    v_basis := v_basis || jsonb_build_object(r.agent, jsonb_build_object(
      'basis','insufficient_history','baseline_samples', r.bn, 'samples_needed', 20));
  elsif r.bmx = r.bmn then
    v_basis := v_basis || jsonb_build_object(r.agent, jsonb_build_object(
      'basis','no_latency_signal','constant_ms', round(r.bmn),
      'detail','every recorded duration is identical, so this subject reports no timing to depart from'));
  elsif coalesce(r.wn,0) < 3 then
    v_basis := v_basis || jsonb_build_object(r.agent, jsonb_build_object(
      'basis','insufficient_window','window_samples', coalesce(r.wn,0), 'samples_needed', 3,
      'baseline_p50_ms', round(r.bp50), 'baseline_p95_ms', round(r.bp95)));
  else
    v_basis := v_basis || jsonb_build_object(r.agent, jsonb_build_object(
      'basis','measured','baseline_p50_ms', round(r.bp50), 'baseline_p95_ms', round(r.bp95),
      'window_p50_ms', round(r.wp50), 'window_samples', r.wn,
      'fires_above_ms', round(greatest(r.bp95, r.bp50 * 2, 1000))));
    if r.wp50 > r.bp95 and r.wp50 >= r.bp50 * 2 and r.wp50 >= 1000 then
      v_state := 'delayed';
    end if;
  end if;
  continue when v_state is null;
  v_sev  := public.fn_it_severity(v_state, r.pub);
  v_key  := 'latency:' || r.agent;
  v_keys := v_keys || v_key;
  v_find := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'latency', 'subject', r.agent,
    'state', v_state, 'severity', v_sev,
    'title', r.agent || ' is taking ' || round(r.wp50) || 'ms, against its own baseline of '
             || round(r.bp50) || 'ms (p95 ' || round(r.bp95) || 'ms)',
    'evidence', jsonb_build_object(
      'window_p50_ms', round(r.wp50), 'window_samples', r.wn,
      'baseline_p50_ms', round(r.bp50), 'baseline_p95_ms', round(r.bp95), 'baseline_samples', r.bn,
      'rule','window p50 > baseline p95 AND >= 2x baseline p50 AND >= 1000ms',
      'public_surface', r.pub, 'basis','measured against this subject''s own trailing 7 days'));
end loop;
v_notes := v_notes || jsonb_build_object('latency', v_basis);

-- ══ D7. THE WEBSITE ═════════════════════════════════════════════════════════════════════════
-- Reads: p_web, the reading the caller took this tick. Postgres cannot fetch, so the tick fetches
-- and Postgres judges — the same division this estate already uses for the OpenRouter meter.
-- Four separate questions, because they fail separately:
--   is it up            home.status outside 2xx/3xx, or a fetch that threw   -> stopped -> CRITICAL
--   did a deploy fail   latest production deployment state ERROR/CANCELED    -> degraded -> HIGH
--   runtime errors      Vercel's runtime error count in the window           -> degraded -> HIGH
--   is it slow          home.ms against the site's own history in it_watch_tick -> delayed
-- The website is public_surface = true by definition, which is why a site that does not answer
-- outranks everything else the engine can find.
-- ON AN IDLE ESTATE: an idle site still answers, so silence here means the site answered. When no
-- reading was taken it reports 'not_probed_this_tick' and NEVER reads as a clean bill.
if p_web is null then
  v_notes := v_notes || jsonb_build_object('website', jsonb_build_object(
    'basis','not_probed_this_tick',
    'detail','no reading was passed to fn_it_detect; the site was not checked and is NOT being reported as healthy'));
else
  v_site_st := nullif(p_web #>> '{home,status}','')::int;
  v_site_ms := nullif(p_web #>> '{home,ms}','')::numeric::int;

  if v_site_st is null or v_site_st < 200 or v_site_st >= 400 then
    v_sev  := public.fn_it_severity('stopped', true);
    v_key  := 'website_down';
    v_keys := v_keys || v_key;
    v_find := v_find || jsonb_build_object(
      'detector_key', v_key, 'detector', 'website_down', 'subject', 'website',
      'state','stopped','severity', v_sev,
      'title', case when v_site_st is null
                    then 'the website did not answer at all: ' || coalesce(p_web #>> '{home,error}','no status and no error was reported')
                    else 'the website answered HTTP ' || v_site_st end,
      'evidence', jsonb_build_object(
        'status', v_site_st, 'url', p_web #>> '{home,url}', 'error', p_web #>> '{home,error}',
        'ms', v_site_ms, 'public_surface', true, 'basis','measured by HTTP request this tick'));
  end if;

  if upper(coalesce(p_web #>> '{deployment,state}','')) in ('ERROR','CANCELED') then
    v_sev  := public.fn_it_severity('degraded', true);
    v_key  := 'website_deploy_failed';
    v_keys := v_keys || v_key;
    v_find := v_find || jsonb_build_object(
      'detector_key', v_key, 'detector', 'website_deploy_failed', 'subject', 'website',
      'state','degraded','severity', v_sev,
      'title', 'the latest production deployment is ' || (p_web #>> '{deployment,state}')
               || ' — the site is still serving the previous build, so new work is not live',
      'evidence', jsonb_build_object(
        'deployment', p_web -> 'deployment', 'public_surface', true,
        'basis','measured from the Vercel deployments API this tick'));
  end if;

  -- Runtime errors. Probed 9 Sep 2026 with the stored app_secrets.vercel_token: there is no
  -- runtime-log endpoint this token can read — /v1/projects/<id>/runtime-logs,
  -- /v1/deployments/<uid>/runtime-logs and /v1/observability/runtime-logs all return 404, and the
  -- deployment `events` endpoints return BUILD output only. So the caller may legitimately be
  -- unable to supply a count, and when it cannot, THIS IS SAID rather than counted as zero: a
  -- monitor that reports "no runtime errors" because it could not look is the exact failure this
  -- whole file is built to avoid.
  if (p_web -> 'runtime_errors') ? 'count' then
    v_notes := v_notes || jsonb_build_object('website_runtime_errors', jsonb_build_object(
      'basis','measured', 'count', (p_web #>> '{runtime_errors,count}')::int,
      'window_minutes', coalesce(p_web #>> '{runtime_errors,window_minutes}','60')));
    if (p_web #>> '{runtime_errors,count}')::int > 0 then
      v_sev  := public.fn_it_severity('degraded', true);
      v_key  := 'website_runtime_errors';
      v_keys := v_keys || v_key;
      v_find := v_find || jsonb_build_object(
        'detector_key', v_key, 'detector', 'website_runtime_errors', 'subject', 'website',
        'state','degraded','severity', v_sev,
        'title', (p_web #>> '{runtime_errors,count}') || ' runtime error(s) on the website in the last '
                 || coalesce(p_web #>> '{runtime_errors,window_minutes}','60') || ' minutes',
        'evidence', jsonb_build_object(
          'runtime_errors', p_web -> 'runtime_errors', 'public_surface', true,
          'basis','measured from the Vercel runtime error API this tick'));
    end if;
  else
    v_notes := v_notes || jsonb_build_object('website_runtime_errors', jsonb_build_object(
      'basis', coalesce(p_web #>> '{runtime_errors,basis}', 'not_reported'),
      'reason', coalesce(p_web #>> '{runtime_errors,reason}',
                'the caller supplied no runtime error count; the website''s runtime errors were NOT checked and are NOT being reported as absent')));
  end if;

  -- Site latency, on the same terms as D6: the site's own history, or an honest refusal.
  -- The samples are the site_ms column of this very table, which is why the tick stores it.
  if v_site_ms is null then
    v_notes := v_notes || jsonb_build_object('website_latency', jsonb_build_object(
      'basis','not_timed','detail','the reading carried no home.ms'));
  else
    declare
      s_n int; s_p50 numeric; s_p95 numeric;
    begin
      select count(*)::int,
             (percentile_cont(0.50) within group (order by site_ms))::numeric,
             (percentile_cont(0.95) within group (order by site_ms))::numeric
        into s_n, s_p50, s_p95
      from public.it_watch_tick
      where ran_at > v_now - c_base and ran_at <= v_now - c_win and site_ms is not null and site_status between 200 and 399;
      if coalesce(s_n,0) < 20 then
        v_notes := v_notes || jsonb_build_object('website_latency', jsonb_build_object(
          'basis','insufficient_history','samples', coalesce(s_n,0), 'samples_needed', 20,
          'current_ms', v_site_ms,
          'detail','the site has no baseline yet; it needs 20 timed ticks, which is about five hours at one tick every fifteen minutes'));
      else
        v_notes := v_notes || jsonb_build_object('website_latency', jsonb_build_object(
          'basis','measured','baseline_p50_ms', round(s_p50), 'baseline_p95_ms', round(s_p95),
          'current_ms', v_site_ms, 'samples', s_n,
          'fires_above_ms', round(greatest(s_p95, s_p50 * 2, 1000))));
        if v_site_ms > s_p95 and v_site_ms >= s_p50 * 2 and v_site_ms >= 1000 then
          v_sev  := public.fn_it_severity('delayed', true);
          v_key  := 'website_slow';
          v_keys := v_keys || v_key;
          v_find := v_find || jsonb_build_object(
            'detector_key', v_key, 'detector', 'website_slow', 'subject', 'website',
            'state','delayed','severity', v_sev,
            'title','the website answered in ' || v_site_ms || 'ms, against its own baseline of '
                    || round(s_p50) || 'ms (p95 ' || round(s_p95) || 'ms)',
            'evidence', jsonb_build_object(
              'current_ms', v_site_ms, 'baseline_p50_ms', round(s_p50), 'baseline_p95_ms', round(s_p95),
              'baseline_samples', s_n, 'public_surface', true,
              'rule','current > baseline p95 AND >= 2x baseline p50 AND >= 1000ms',
              'basis','measured against the site''s own timed ticks over 7 days'));
        end if;
      end if;
    end;
  end if;
end if;

-- ══ D8. THE DATABASE BACKUP CHAIN ═══════════════════════════════════════════════════════════
-- Reads: pg_stat_archiver. Added 9 September 2026.
--
-- WHY THIS DETECTOR EXISTS. fn_backup_watch spent its whole life reading `agent_runs where
-- agent = 'backup'` — a name nothing has ever written — so it reported "no successful backup for
-- as long as there are records" on every single call, at severity critical. That was fixed the
-- same day, and fixing it exposed the real hole underneath: NOTHING watched the Postgres backups
-- at all. The document mirror had a watcher. The database that holds the company did not.
--
-- WHY pg_stat_archiver AND NOT THE MANAGEMENT API. The daily physical backups are taken outside
-- this database and their status is only readable through the Supabase management API, which needs
-- a personal access token this estate does not hold and which would give an edge function full
-- project admin. But those backups are built on continuous WAL archiving, and pg_stat_archiver is
-- the archiver's own counter, readable from inside with no credential at all. If archiving stops,
-- the backup chain stops, and this sees it within the hour. It is the mechanism rather than the
-- report, which makes it earlier and cheaper — and it is honest about being a proxy.
--
-- WHAT IT CANNOT SEE, SAID OUT LOUD: whether a nightly snapshot COMPLETED. Healthy archiving with
-- a broken snapshot pipeline would read clean here. That gap is real and is named in the note
-- rather than left for someone to discover the way I discovered the last one.
--
-- ON AN IDLE ESTATE. archived_count is cumulative since stats_reset, so a database that has never
-- archived a segment reports 0 — and 0 means "this instrument has never seen the thing work",
-- which is exactly the shape that produced today's false critical. So zero is NOT a finding here.
-- It goes to notes as unproven, and the detector declines to conclude.
begin
  select archived_count, last_archived_time, failed_count, last_failed_time, stats_reset
    into v_arch_n, v_arch_at, v_arch_fail, v_arch_fail_at, v_arch_reset
    from pg_stat_archiver;

  if v_arch_n is null or v_arch_n = 0 then
    -- POSITIVE CONTROL, and the whole lesson of the backup watcher in one branch: an instrument
    -- that has never once seen success cannot tell you about failure.
    v_notes := v_notes || jsonb_build_object('wal_archiving', jsonb_build_object(
      'basis','unproven',
      'detail','pg_stat_archiver reports no archived segment since ' || coalesce(v_arch_reset::text,'(no reset recorded)')
            || '. That means this instrument has never observed archiving working, so it declines to '
            || 'report a fault it could not distinguish from its own blindness.'));
  else
    v_arch_age := extract(epoch from (v_now - v_arch_at))/60;

    -- FAILING NOW: the archiver recorded a failure inside the window. failed_count is cumulative
    -- and would be true forever after one bad hour in May, so the test is the TIME of the last
    -- failure, not the count.
    if v_arch_fail_at is not null and v_arch_fail_at > v_now - c_win then
      v_key  := 'backup_chain:wal_archiving_failing';
      v_keys := v_keys || v_key;
      v_find := v_find || jsonb_build_object(
        'detector_key', v_key, 'detector', 'backup_chain', 'subject', 'wal_archiving',
        'state', 'stopped', 'severity', 'critical',
        'title', 'WAL archiving failed at ' || v_arch_fail_at::text
                 || ' — the database backup chain is breaking, and every daily snapshot is built on it',
        'evidence', jsonb_build_object(
          'archived_count', v_arch_n, 'last_archived_time', v_arch_at,
          'failed_count', v_arch_fail, 'last_failed_time', v_arch_fail_at,
          'stats_reset', v_arch_reset, 'public_surface', false,
          'basis','measured from pg_stat_archiver; the test is the TIME of the last failure inside the window, never the cumulative count',
          'not_covered','whether a nightly physical snapshot COMPLETED — that is only readable through the management API'));

    -- STALLED: nothing archived for an hour. Over the recorded life of this instrument the estate
    -- archives roughly one segment every few minutes, so an hour of silence is not quiet traffic.
    elsif v_arch_age > 60 then
      v_key  := 'backup_chain:wal_archiving_stalled';
      v_keys := v_keys || v_key;
      v_find := v_find || jsonb_build_object(
        'detector_key', v_key, 'detector', 'backup_chain', 'subject', 'wal_archiving',
        'state', case when v_arch_age > 240 then 'stopped' else 'degraded' end,
        'severity', case when v_arch_age > 240 then 'critical' else 'high' end,
        'title', 'No WAL segment archived for ' || round(v_arch_age/60) || ' hour(s) — the backup chain may have stopped',
        'evidence', jsonb_build_object(
          'archived_count', v_arch_n, 'last_archived_time', v_arch_at,
          'age_minutes', round(v_arch_age,1), 'threshold_minutes', 60,
          'failed_count', v_arch_fail, 'stats_reset', v_arch_reset, 'public_surface', false,
          'basis','measured from pg_stat_archiver.last_archived_time',
          'not_covered','whether a nightly physical snapshot COMPLETED — that is only readable through the management API'));
    else
      v_notes := v_notes || jsonb_build_object('wal_archiving', jsonb_build_object(
        'basis','measured','archived_count', v_arch_n,
        'last_archived_minutes_ago', round(v_arch_age,1),
        'failures_ever', v_arch_fail,
        'not_covered','whether a nightly physical snapshot COMPLETED — only the management API can say'));
    end if;
  end if;
exception when others then
  -- pg_stat_archiver is a system view; if it ever becomes unreadable that is worth SEEING rather
  -- than swallowing, but it must not take the other seven detectors down with it.
  v_notes := v_notes || jsonb_build_object('wal_archiving',
    jsonb_build_object('basis','unreadable','error', sqlerrm));
end;

-- ══ THE VERDICT ═════════════════════════════════════════════════════════════════════════════
select coalesce(
  (select f ->> 'severity' from jsonb_array_elements(v_find) f
    order by case f ->> 'severity' when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end
    limit 1), 'none')
into v_worst;

-- ══ THE LEDGER — open while true, resolved the tick after it stops being true ═══════════════
if p_persist then
  insert into public.it_watch_finding
    (detector_key, detector, subject, state, severity, title, evidence, opened_at, last_seen_at, seen_count, status, resolved_at)
  select f ->> 'detector_key', f ->> 'detector', f ->> 'subject', f ->> 'state', f ->> 'severity',
         f ->> 'title', f -> 'evidence', v_now, v_now, 1, 'open', null
  from jsonb_array_elements(v_find) f
  on conflict (detector_key) do update set
    -- A finding that reappears after being resolved is a NEW occurrence, so opened_at restarts.
    -- One that never closed keeps its original opened_at, which is what makes "how long has this
    -- been broken" answerable.
    opened_at    = case when public.it_watch_finding.status = 'resolved' then excluded.opened_at
                        else public.it_watch_finding.opened_at end,
    seen_count   = case when public.it_watch_finding.status = 'resolved' then 1
                        else public.it_watch_finding.seen_count + 1 end,
    detector     = excluded.detector,
    subject      = excluded.subject,
    state        = excluded.state,
    severity     = excluded.severity,
    title        = excluded.title,
    evidence     = excluded.evidence,
    last_seen_at = excluded.last_seen_at,
    status       = 'open',
    resolved_at  = null;
  get diagnostics v_opened = row_count;

  update public.it_watch_finding
     set status = 'resolved', resolved_at = v_now
   where status = 'open' and not (detector_key = any (v_keys));
  get diagnostics v_resolved = row_count;

  insert into public.it_watch_tick (ran_at, findings, worst, site_ms, site_status, detail)
  values (v_now, jsonb_array_length(v_find), v_worst, v_site_ms, v_site_st,
          jsonb_build_object('findings', v_find, 'notes', v_notes, 'web', p_web));
end if;

return jsonb_build_object(
  'ok', true,
  'at', v_now,
  'window_minutes', 60,
  'baseline_days', 7,
  'worst', v_worst,
  'finding_count', jsonb_array_length(v_find),
  'findings', v_find,
  'notes', v_notes,
  'persisted', p_persist,
  'ledger_upserted', v_opened,
  'ledger_resolved', v_resolved);
end
$fn$;

comment on function public.fn_it_detect(jsonb, boolean) is
  'The IT engineer''s detection engine. EIGHT detectors over the app, the scheduler, the queues, latency, the website and the database backup chain, all deterministic, all delta- or state-based, each reporting its own basis so an idle estate is never mistaken for a healthy one. p_web carries the website reading the caller measured; p_persist=false decides identically and writes nothing.';

-- A newly CREATED SECURITY DEFINER routine is granted EXECUTE to PUBLIC. It reads every failing
-- internal in the estate and executes registry-supplied predicates; nobody on the public surface
-- gets it.
revoke execute on function public.fn_it_detect(jsonb, boolean) from public;
revoke execute on function public.fn_it_severity(text, boolean) from public;
revoke execute on function public.fn_it_run_is_refusal(text, timestamptz, jsonb) from public;

revoke all on public.it_watch_subject from anon, authenticated;
revoke all on public.it_watch_queue   from anon, authenticated;
revoke all on public.it_watch_tick    from anon, authenticated;
revoke all on public.it_watch_finding from anon, authenticated;

-- ══ PROVE IT ON THE LIVE ESTATE ═════════════════════════════════════════════════════════════
--
-- WHAT IS PROVED HERE AND WHAT IS NOT, because a verification block that implies more than it ran
-- is the same defect as a detector that implies more than it saw.
--
--   PROVED: D8 reads pg_stat_archiver, reports basis 'measured', carries the real counters, and
--           produces NO finding while archiving is healthy. A detector that fires on a working
--           system is the failure mode this whole file was written after.
--   NOT PROVED HERE: the two alerting branches. Making them fire on production would mean breaking
--           WAL archiving or resetting the archiver's statistics, and pg_stat_reset_shared is not
--           transactional — it would destroy the real counter rather than roll back. So they are
--           unexercised, and that is stated rather than implied away.
do $do$
declare v jsonb; w jsonb; v_open int;
begin
  v := public.fn_it_detect(null, false);          -- decides identically, writes nothing
  if coalesce(v->>'ok','') <> 'true' then
    raise exception 'fn_it_detect did not return ok after D8 was added: %', v::text;
  end if;

  w := v -> 'notes' -> 'wal_archiving';
  if w is null then
    raise exception 'D8 produced no note at all — the detector is not running';
  end if;
  if (w->>'basis') <> 'measured' then
    raise exception 'D8 reports basis %, so it is not reading the archiver: %', (w->>'basis'), w::text;
  end if;
  if (w->>'archived_count') is null or (w->>'archived_count')::bigint <= 0 then
    raise exception 'D8 read an archived_count of % — the positive control for this instrument is absent', w->>'archived_count';
  end if;
  if (w->>'not_covered') is null then
    raise exception 'D8 dropped the statement of what it does not cover; that sentence is load-bearing';
  end if;

  select count(*) into v_open
    from jsonb_array_elements(v -> 'findings') f
   where f->>'detector' = 'backup_chain';
  if v_open <> 0 then
    raise exception 'D8 raised % backup_chain finding(s) against an estate whose archiver last ran % minute(s) ago — it fires when the system works',
      v_open, w->>'last_archived_minutes_ago';
  end if;

  raise notice 'D8 live: % segment(s) archived, last % minute(s) ago, % failure(s) ever, 0 findings raised. Alerting branches unexercised (see the block comment).',
    w->>'archived_count', w->>'last_archived_minutes_ago', w->>'failures_ever';
end
$do$;
