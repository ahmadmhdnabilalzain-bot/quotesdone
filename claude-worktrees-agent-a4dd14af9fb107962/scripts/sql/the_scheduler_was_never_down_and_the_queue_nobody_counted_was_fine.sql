-- THE SCHEDULER WAS NEVER DOWN, AND THE QUEUE NOBODY COUNTED WAS FINE.
--
-- Assigned: it_engineer. 18 Sep 2026.
--
-- The founder was paged at 03:47Z with "SCHEDULER DOWN — automation stalled". The scheduler was
-- running. It had not missed a tick all night. What had stopped was the detector that sent the
-- mail, and it could not tell the difference between the two, because it was reading its OWN
-- heartbeat and calling it the scheduler's.
--
-- ══ WHAT WAS MEASURED, 18 Sep 2026 06:25–06:35Z, against htdblwldjkcgjvmqkbeh ════════════════
--
-- 1. THE SCHEDULER NEVER MISSED A TICK.
--      select max(g) from (select extract(epoch from (started_at
--        - lag(started_at) over (order by started_at)))/60 g
--        from public.agent_runs where agent = 'fn:resilience_ping'
--         and started_at > now() - interval '6 hours') z;
--      -> 15.009566666666666 minutes. Fifteen point zero. Every slot, every quarter hour.
--    691 runs under that name in seven days; it is the only name matching '%resilience%'.
--
-- 2. THE DETECTOR MISSED THREE OF ITS OWN.
--      it_watch_tick ran_at: … 03:00:42, 03:15:38, 04:15:48, 04:30:39 …   -> a 60.2-minute hole
--      (also 30.8 min at 02:32, and 30.0 min at 06:15 — it is still happening as this is written)
--    it_watch_tick has ONE writer:
--      select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname='public' and p.prokind='f'
--         and pg_get_functiondef(p.oid) like '%insert into public.it_watch' || '_tick%';
--      -> fn_it_detect. Only fn_it_detect.
--    So the gap it read was its own. resilience_ping wall times over the same hours: 51 s, 65 s,
--    107 s, 141 s, 133 s, 78 s, 63 s, 82 s — against its own 110 s deadline and a 150 s edge cap,
--    while the daily export copied a 9.1 GB table. The detector's statements were cancelled; it
--    never reached its last line; and the next run that did reach it read the hole as the death of
--    the company's automation and sent that to the founder at the top severity.
--
--    This is the instrument-measuring-the-wrong-subject lens, in its most expensive form: the
--    instrument was measuring ITSELF and reporting the answer as the estate.
--
-- 3. THE 4,273-ROW DROPBOX QUEUE WAS LEGITIMATE, AND NOTHING WAS WATCHING IT ANYWAY.
--      rows created in doc_backups in the last 2 hours .......... 4,442
--      DISTINCT paths among them ................................ 4,442   (not a loop)
--      of which 2026-09-18/kb_chunks/page_NNNN.json ............. 4,177
--      kb_chunks .................. 2,615,397 rows, 9,113 MB, exported in full every day
--      rows that reached done in the 17 minutes measured ........ 204  -> 720/hour
--      hours to clear 4,273 at that rate ........................ 5.9
--    A busy queue, not a broken one. But it_watch_queue registers doc_backups only at
--    status = 'error'; the 4,273 PENDING rows were watched by nothing at all, and the one shape
--    that would matter — a queue filling faster than it drains — is invisible to the age test,
--    because every row in such a queue is young.
--
-- ══ WHAT THIS FILE CHANGES ══════════════════════════════════════════════════════════════════
--
-- A. D3 reads the scheduler from the scheduler. max(started_at) of fn:resilience_ping in
--    agent_runs, not max(ran_at) of it_watch_tick. An empty read is NOT a clean bill: 691 runs
--    landed under that name in seven days, so zero rows means this detector lost its subject, and
--    it raises 'scheduler_unreadable' rather than falling silent.
-- B. D3b keeps the old reading under its own name and at 'degraded'. A hole in it_watch_tick is a
--    real fault — it is just this function's fault. It now says so: 'it_detector_ticks_missed',
--    "it ran and did not finish, so nothing was being detected", pointing the reader at
--    agent_runs to confirm the scheduler is fine.
-- C. D5 gains a drain arm. it_watch_queue.drain_column (new, nullable) names the column that
--    records completion; the detector divides the depth by the rows completed in the last hour and
--    raises when the queue cannot clear inside 24 hours — the interval at which every registered
--    queue is refilled. Not a guessed row count. A drain of zero with rows pending raises at
--    'stopped', because zero cannot tell a dead consumer from an idle one and the pending rows
--    settle it. drain_column NULL leaves the arm off and the note says 'not_measured' rather than
--    reporting a clean bill it did not take.
-- D. doc_backups is registered at status = 'pending' with drain_column = 'backed_up_at'.
--    Against tonight's numbers this arm is SILENT (4,273 / 720 = 5.9 hours), which is the correct
--    answer and the reason it is not a depth threshold.
--
-- WHAT THIS FILE DOES NOT DO. It does not touch the export, the page size, or the backup
-- retention. The export is doing what it was built to do; what it costs is a separate question
-- with the founder's money in it (12.2 GB written to the backups bucket today alone, 39.1 GB in
-- the bucket, 27.3 GB already in Dropbox), and it is reported rather than quietly changed here.
--
-- Nothing is revoked below: fn_it_detect already exists and CREATE OR REPLACE preserves its ACL.
-- it_watch_queue gains a column, not a table, so its existing policy and grants still apply.

-- ══ 1. THE REGISTRY LEARNS WHAT "DRAINED" LOOKS LIKE ════════════════════════════════════════
alter table public.it_watch_queue
  add column if not exists drain_column text;

comment on column public.it_watch_queue.drain_column is
  'The timestamp column a row gets when this queue FINISHES with it (doc_backups.backed_up_at). '
  'fn_it_detect divides the pending depth by the rows stamped in the last hour to get the hours to '
  'clear, and raises when that passes 24 — the interval at which every queue here is refilled. '
  'NULL switches the arm off for that queue and the tick notes say ''not_measured'': a queue whose '
  'drain has never been measured must not be reported as one that is draining.';

-- ══ 1b. AND THE DRAIN COUNT GETS AN INDEX BEFORE IT NEEDS ONE ═══════════════════════════════
-- Raised by independent review (ecc:database-reviewer) and then MEASURED, 18 Sep 2026:
--   explain (analyze, buffers)
--     select count(*) from public.doc_backups where backed_up_at > now() - interval '1 hour';
--   -> Seq Scan on doc_backups, 811 buffers, 14,708 rows removed by filter, 5.9 ms.
-- 5.9 ms is affordable. It is also proportional to the table, and the table grows by about 4,400
-- rows on an export day (measured: 4,442 in the two hours to 06:25Z, against 15,033 rows in total).
-- At 90 days of retention that is the same scan over roughly half a million rows, inside the same
-- 8-second budget as everything else this detector does — which is precisely the failure this file
-- exists to stop. A detector that fixes its own timeout by adding an unindexed full-table count
-- every fifteen minutes has moved the fault, not removed it.
-- Partial, because the predicate `backed_up_at > <ts>` implies `backed_up_at is not null` and the
-- planner uses that implication: 4,833 of the 15,033 rows have never been backed up and do not
-- belong in the index. That implication is not assumed — it was measured, with the index built
-- inside a transaction that was then rolled back:
--   Aggregate (actual time=0.260..0.261)
--     -> Index Only Scan using ix_doc_backups_backed_up_at  (actual time=0.012..0.234 rows=342)
--          Index Cond: (backed_up_at > (now() - '01:00:00'::interval))
--   Buffers: shared hit=190      Execution Time: 0.285 ms
-- 5.906 ms -> 0.285 ms, 811 buffers -> 190, on today's 15,033 rows. The point is not the 5.6 ms
-- saved today; it is that the scan stops growing with the table.
create index if not exists ix_doc_backups_backed_up_at
  on public.doc_backups (backed_up_at)
  where backed_up_at is not null;

comment on index public.ix_doc_backups_backed_up_at is
  'Serves fn_it_detect''s drain arm: count(*) where backed_up_at > now() - interval ''1 hour''. '
  'Measured 18 Sep 2026 before it existed: seq scan, 811 buffers, 5.9 ms over 15,033 rows, growing '
  'by ~4,400 rows per export day.';

-- ══ 2. THE PENDING HALF OF THE DROPBOX QUEUE, WHICH NOTHING WATCHED ═════════════════════════
-- The existing doc_backups_failed row watches status = 'error'. It is untouched. This one watches
-- the rows that are simply waiting, which is where a stalled uploader actually shows up first.
-- stall_minutes is 1440 because a legitimate export day takes about six hours to clear (measured),
-- so a pending row older than a DAY is the honest age signal; the drain arm above catches the
-- faster-filling-than-draining case that age cannot see.
insert into public.it_watch_queue
  (queue_key, table_name, pending_predicate, ts_column, stall_minutes, surface, enabled, drain_column, note)
values
  ('doc_backups_pending', 'doc_backups',
   'status = ''pending'' and entity is distinct from ''zz_demo''',
   'created_at', 1440, 'internal', true, 'backed_up_at',
   'The Dropbox upload queue. 18 Sep 2026: 4,273 pending, 720 cleared an hour, 5.9 hours to clear '
   '- a busy queue, correctly silent. Registered because nothing watched the pending half at all: '
   'doc_backups_failed only sees status = ''error'', and an uploader that stops leaves rows at '
   'pending, not at error. The ZZ DEMO fixtures are excluded: 697 of them were abandoned on '
   '14 Sep and would sit in the depth forever.')
on conflict (queue_key) do update set
  table_name = excluded.table_name, pending_predicate = excluded.pending_predicate,
  ts_column = excluded.ts_column, stall_minutes = excluded.stall_minutes,
  surface = excluded.surface, enabled = excluded.enabled,
  drain_column = excluded.drain_column, note = excluded.note;

-- ══ 3. THE DETECTOR ═════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_it_detect(p_web jsonb DEFAULT NULL::jsonb, p_persist boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  -- The window is one hour and the baseline is the seven days BEFORE it. The window has to be
  -- long enough that a 30-minute job appears in it and short enough that a fault is news.
  c_win       constant interval := interval '60 minutes';
  c_base      constant interval := interval '7 days';
  -- Statuses agent_runs uses for "this run did its job". Anything else, NULL included, is a
  -- failure: a run that started and never recorded an outcome is not a success.
  c_ok        constant text[] := array['ok','success','completed','skipped','warn','held','noop'];
  v_now       timestamptz := now();
  -- Whatever lock_timeout the caller arrived with, so D5 can put it back exactly (see D5).
  v_lock_prev text;
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
  -- D5's drain arm: rows this queue completed in the last hour, and the depth divided by it.
  v_drain     bigint;
  v_hours     numeric;
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
  -- D9, polite refusals. It carries its own window and floor; the reasons are written at D9.
  c_ref_win   constant interval := interval '24 hours';
  c_ref_min   constant int := 20;
  v_share     numeric;
  v_bshare    numeric;
  v_ref_eval  int := 0;
  v_ref_thin  int := 0;
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
           -- A run the founder's hold refused is neither the caller turned away nor the subject's
           -- fault: it leaves both sides of the rate and is reported apart as window_held.
           public.fn_it_run_is_refusal(agent, started_at, counts) or held  refused,
           held
    from (select *, public.fn_it_run_is_held(agent, started_at, counts, note) held
            from public.agent_runs where started_at > v_now - c_base) ar0),
  w as (
    select subject,
           count(*) filter (where not refused)::int              n,
           count(*) filter (where bad and not refused)::int      f,
           count(*) filter (where refused and not held)::int     refused,
           count(*) filter (where held)::int                     held
    from runs where started_at > v_now - c_win group by subject),
  b as (
    select subject,
           count(*) filter (where not refused)::int              n,
           count(*) filter (where bad and not refused)::int      f
    from runs where started_at <= v_now - c_win group by subject)
  select w.subject agent, w.n, w.f, w.refused, w.held, coalesce(b.n,0) bn, coalesce(b.f,0) bf,
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
      'window_held', r.held,
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
-- Reads: public.agent_runs, the scheduler's own rows.  (Was: public.it_watch_tick. See below.)
-- The live scheduler is Vercel cron -> /api/resilience-ping -> resilience_ping, every 15 minutes.
-- pg_cron is dead by founder instruction (one inactive job; 234 deleted on 7 Sep), so any check
-- that reads cron.job_run_details to judge scheduler health is reading a table nothing writes.
--
-- 18 SEP 2026 — THE SCHEDULER WAS NEVER DOWN. THIS DETECTOR WAS, AND IT PUT ITS OWN NAME ON THE
-- FOUNDER'S 03:47Z "SCHEDULER DOWN — automation stalled" MAIL.
--   it_watch_tick has exactly ONE writer, and it is this function. Measured:
--     select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public' and p.prokind = 'f'
--        and pg_get_functiondef(p.oid) like '%insert into public.' || 'it_watch_tick%';
--     -> fn_it_detect, and nothing else.
--   So a hole in it_watch_tick never meant "the scheduler missed a tick". It meant "this function
--   did not reach its own last line" — a statement timeout, or a wait behind somebody's lock.
--   Measured over the exact hour the page covers, 18 Sep 2026:
--     it_watch_tick   03:15:38 -> 04:15:48         ONE row, a 60.2-minute hole
--     agent_runs      03:15:21, 03:30:21, 03:45:21, 04:00:22, 04:15:22  (fn:resilience_ping)
--     worst gap between two consecutive scheduler runs in the six hours around it: 15.01 minutes
--   Five consecutive ticks, none missed, none late by a second. Every one of them ran this
--   function; three of them did not get to the end of it, because the same six hours hold
--   resilience_ping wall times of 107 s, 141 s and 133 s against a 110 s deadline while the daily
--   export copied a 9.1 GB table. The detector reported its own three failures as the death of the
--   whole scheduler, at the top severity, to the founder.
--   The subject of a measurement is the thing measured. The scheduler is now read from the
--   scheduler's runs, and this function's own missed ticks keep a separate, lower-severity key, so
--   a detector that cannot finish says THAT, and never again says the company's automation stopped.
--
-- ON AN IDLE ESTATE: silent, because the scheduler ticks on an idle estate. On an estate with no
-- scheduler run recorded at all this does NOT go quiet: the scheduler demonstrably runs, so an
-- empty read means this detector has lost its subject (a renamed agent), and it says so.
select max(started_at) into v_prev from public.agent_runs
 where agent = 'fn:resilience_ping' and started_at > v_now - c_base;
if v_prev is null then
  -- Not a clean bill. 691 runs landed under this name in the seven days to 18 Sep 2026, so zero
  -- rows means the name moved, not that the scheduler is fine. Raised, not noted away.
  v_sev := public.fn_it_severity('degraded', false);
  v_key := 'scheduler_unreadable';
  v_keys := v_keys || v_key;
  v_find := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'scheduler_gap', 'subject', 'scheduler',
    'state', 'degraded', 'severity', v_sev,
    'title', 'the scheduler cannot be read: no fn:resilience_ping run in 7 days, so its health is unknown',
    'evidence', jsonb_build_object(
      'agent_read', 'fn:resilience_ping', 'window_days', 7, 'rows_found', 0,
      'path','Vercel cron -> /api/resilience-ping -> resilience_ping',
      'basis','measured: agent_runs holds no row under the name this detector reads'));
  v_notes := v_notes || jsonb_build_object('scheduler', jsonb_build_object(
    'basis','unreadable','detail','no fn:resilience_ping run in agent_runs in 7 days'));
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
        'basis','measured from the last fn:resilience_ping run in agent_runs — the scheduler''s own record, not this detector''s'));
  end if;
end if;

-- ── D3b. AND THIS DETECTOR'S OWN MISSED TICKS, UNDER THEIR OWN NAME ──────────────────────────
-- The old reading was not worthless, it was mislabelled: a hole in it_watch_tick is a real fault,
-- it is just this function's fault and not the scheduler's. It keeps its own key and 'degraded',
-- because the estate is still ticking and every other duty still ran; what is lost is detection.
select max(ran_at) into v_prev from public.it_watch_tick;
if v_prev is not null then
  v_gap := extract(epoch from (v_now - v_prev))/60;
  v_notes := v_notes || jsonb_build_object('detector_self', jsonb_build_object(
    'basis','measured','gap_minutes', round(v_gap,1), 'expected_minutes', 15, 'threshold_minutes', 45));
  if v_gap > 45 then
    v_sev := public.fn_it_severity('degraded', false);
    v_key := 'it_detector_ticks_missed';
    v_keys := v_keys || v_key;
    v_find := v_find || jsonb_build_object(
      'detector_key', v_key, 'detector', 'it_detector_ticks_missed', 'subject', 'fn_it_detect',
      'state', 'degraded', 'severity', v_sev,
      'title', 'the IT detector recorded no tick for ' || round(v_gap) || ' minutes: it ran and did not finish, so nothing was being detected',
      'evidence', jsonb_build_object(
        'gap_minutes', round(v_gap,1), 'previous_tick', v_prev, 'expected_every_minutes', 15,
        'look_at','agent_runs for fn:resilience_ping over the same window: if the ticks are there, the scheduler is fine and this function timed out or waited on a lock',
        'basis','measured from the interval between the last two it_watch_tick rows — this function''s own record'));
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
-- 18 SEP 2026 — A LOCK HELD BY SOMEBODY ELSE MUST NOT TAKE THE DETECTOR DOWN. Each read below is
-- a dynamic count over a watched table; measured 18 Sep, the doc_backups one costs 2–4 ms. Twice
-- that day the SAME read sat for 118,425 ms and 45,497 ms and the whole of fn_it_detect with it,
-- behind a writer on public.doc_backups (the Dropbox enqueue was split into a fast path and
-- fn_enqueue_doc_backups_backfill that morning). PostgREST cancels at 8 s, so the detector persisted
-- NOTHING — the 14 Sep outage this routine's own check names, arriving by a different road. The
-- handler below already turns an unreadable queue into a note and carries on; it never got the
-- chance, because waiting is not an error. 250 ms is the same bound fn_it_duties_scheduled's table
-- drill took on 14 Sep for the same reason.
--   RESTORED, NOT ZEROED (database review, 18 Sep): `set local lock_timeout = 0` would mean
--   "wait forever", and PostgREST's `authenticator` role carries `lock_timeout=8s` as a role
--   default (measured: rolconfig = statement_timeout=8s,lock_timeout=8s). Zeroing it would have
--   left D6-D8, which have no handler of their own, LESS protected than before this change. So the
--   caller's own value is captured and put back verbatim.
v_lock_prev := current_setting('lock_timeout');
perform set_config('lock_timeout', '250ms', true);
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

  -- DEPTH, DIVIDED BY THE QUEUE'S OWN MEASURED DRAIN. (18 Sep 2026, it_engineer.)
  -- The age arm below is deliberately not a depth test and that is right: on 18 Sep 2026 the
  -- Dropbox queue held 4,273 rows whose oldest was under two hours old, and it was a busy queue,
  -- not a broken one — 204 of them completed in the 17 minutes that were measured, 720 an hour,
  -- clearing the whole backlog in under six. A fixed row count would have paged the founder about
  -- a queue that was working, which is what an earlier depth rule did to notifications_whatsapp
  -- 226 times on 17 Sep.
  -- But age alone cannot see the one shape that matters: a queue filling faster than it empties.
  -- Every row in such a queue is young, and it still never clears. So where a queue records WHEN a
  -- row completed (it_watch_queue.drain_column), this arm divides the depth by the rows that
  -- actually completed in the last hour and reports the HOURS TO CLEAR.
  -- The threshold is not a row count somebody guessed. It is 24 hours, because every queue
  -- registered here is refilled at least daily, so a queue that cannot clear inside a day is a
  -- queue that never clears.
  -- A drain of ZERO with rows pending is the same statement with the division removed, and it is
  -- RAISED, not skipped: zero cannot tell a dead consumer from an idle one, so the pending rows
  -- decide — there is work, and in a whole hour nothing did any of it.
  -- drain_column NULL leaves this arm off for that queue, and the note says so rather than
  -- reporting a clean bill it did not measure.
  if r.drain_column is null then
    v_notes := v_notes || jsonb_build_object('queue_' || r.queue_key || '_drain',
      jsonb_build_object('basis','not_measured',
        'detail','no drain_column registered for this queue, so its rate of clearing is unknown; only the age of its oldest row is checked'));
  else
    begin
      execute format('select count(*) from public.%I where %I > $1', r.table_name, r.drain_column)
        into v_drain using v_now - interval '1 hour';
    exception when others then
      v_drain := null;
      v_notes := v_notes || jsonb_build_object('queue_' || r.queue_key || '_drain',
        jsonb_build_object('basis','unreadable','error', sqlerrm));
    end;
    if v_drain is not null then
      -- NULL hours means "never at this rate", and the test below treats it as past the threshold.
      v_hours := case when v_drain > 0 then v_cnt::numeric / v_drain else null end;
      v_notes := v_notes || jsonb_build_object('queue_' || r.queue_key || '_drain',
        jsonb_build_object('basis','measured','pending', v_cnt, 'drained_last_hour', v_drain,
          'hours_to_clear', round(v_hours,1), 'threshold_hours', 24, 'drain_column', r.drain_column));
      if v_hours is null or v_hours > 24 then
        v_state := case when v_drain = 0 then 'stopped' else 'degraded' end;
        v_sev   := public.fn_it_severity(v_state, r.surface = 'customer');
        v_key   := 'queue_not_draining:' || r.queue_key;
        v_keys  := v_keys || v_key;
        v_find  := v_find || jsonb_build_object(
          'detector_key', v_key, 'detector', 'queue_not_draining', 'subject', r.queue_key,
          'state', v_state, 'severity', v_sev,
          'title', r.table_name || ': ' || v_cnt || ' row(s) waiting and ' || v_drain
                   || ' cleared in the last hour — '
                   || case when v_drain = 0 then 'nothing is draining this queue'
                           else round(v_hours) || ' hours to clear, past the 24-hour threshold' end,
          'evidence', jsonb_build_object(
            'pending_rows', v_cnt, 'drained_last_hour', v_drain,
            'hours_to_clear', round(v_hours,1), 'threshold_hours', 24,
            'drain_column', r.drain_column, 'predicate', r.pending_predicate,
            'oldest_pending', v_oldest, 'public_surface', r.surface = 'customer',
            'basis','measured: the depth now, divided by the rows this queue completed in the last hour'));
      end if;
    end if;
  end if;

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
perform set_config('lock_timeout', v_lock_prev, true);

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

-- ══ D9. POLITE REFUSALS — A CUSTOMER TURNED AWAY IS INVISIBLE EVERYWHERE ELSE ════════
-- Reads: public.agent_runs (a 24-hour window against the 7 days before it), public.it_watch_subject.
-- Added 9 September 2026 on founder instruction 18: "Every polite refusal is invisible to IT."
--
-- WHY NOTHING ELSE SEES THIS, and why neither half of the blindness was a mistake.
--   supabase/functions/_shared/observe.ts records status='warn' for EVERY 4xx response, and 'warn'
--   is on D1's c_ok list, so a refused request is not 'bad'. Then fn_it_run_is_refusal removes 4xx
--   rows from D1's numerator AND its denominator, so they cannot move the rate either. Both are
--   correct FOR D1: turning away a malformed or unauthenticated request is not that subject's
--   fault, and counting it would make every secret-gated internal function look broken. The
--   consequence is that a subject can refuse everybody and D1 computes a failure rate of exactly
--   0.00. Measured today on the live table: login_otp, which is customer sign-in, returned
--   skipped 88 / 404 24 / 409 6 / 400 1 / 200 6 over seven days — 119 of 125 attempts turned away —
--   and D1 reported nothing whatsoever, because not one of those statuses is 'bad'. 'skipped' is on
--   the success list too, so even the handler's own "I refused a real customer" row read as health.
--
-- WHY THIS IS NOT "COUNT THE 4xx". Refusing a bad request is right most of the time, so a count
-- would fire on every secret-gated function the moment anything probed it, and an engine that
-- fires on everything is as useless as one that fires on nothing. The test is a SHARE, and it may
-- only conclude in two shapes:
--   dominance — a PUBLIC surface (it_watch_subject.public_surface) whose refusals are at least half
--               its traffic. A path a customer opens that turns away most callers is a broken front
--               door whatever the reason; there is no benign version of that number on a public
--               surface. Above 90% it is 'stopped' rather than 'degraded'.
--   departure — ANY subject, public or internal, whose refusal share is 30 points above its own
--               trailing baseline. This is the arm that catches a path that USED to work; without
--               it a rise from 2% to 40% on a private function stays silent forever.
-- Neither arm looks at an absolute count, and severity runs through fn_it_severity(state, public),
-- so the same departure is 'medium' internally and 'high' on a customer surface.
--
-- WHY 24 HOURS AND NOT THE 60-MINUTE WINDOW EVERY OTHER DETECTOR USES. Measured, not assumed: the
-- whole login_otp refusal burst ran 07:34–08:36 today, and the tick that would have judged it runs
-- at 17:4x. A one-hour window sees ZERO of those 125 attempts and returns a clean bill on the exact
-- fault this detector exists for. A refusal pattern is a customer-experience aggregate rather than
-- an outage; the unit that matters is "how many people did we turn away today". The baseline is the
-- seven days ENDING where this window starts, so the window cannot pollute its own reference.
--
-- WHY 'skipped' COUNTS AS A REFUSAL, BUT ONLY ON A PUBLIC SURFACE. This is the one judgement in the
-- detector, so it is written down instead of left inside a predicate. On an internal scheduled job
-- 'skipped' means "there was nothing to do", which is the healthiest thing a drainer can say, and
-- counting it would fire on every idle queue in the estate. On a surface a customer opens, a run
-- exists only because a customer arrived, so 'skipped' means "a real person asked and we said no".
-- login_otp's own note says exactly that — "refused an SMS sign-in because more than one customer
-- account carries this mobile number" — and that row is currently counted as a success. public_
-- surface is precisely the line between the two meanings, it is already in it_watch_subject, and it
-- needs no new column and no per-subject allowlist.
--
-- THE DOUBLE LOG, and why it had to be handled before any share could be trusted. This estate
-- writes TWO rows for one refused request: the handler's semantic row (agent 'login_otp', status
-- 'skipped') and observe.ts's telemetry row (agent 'fn:login_otp', status 'warn', counts.http 404),
-- milliseconds apart. A SUCCESS writes only the telemetry row. Counting both logs would therefore
-- inflate every refusal share while leaving successes alone. A semantic row that has a telemetry
-- twin within five seconds is dropped — the same ±5s pairing fn_it_run_is_refusal already relies on.
-- Measured effect on login_otp today: 118 rows become 106 attempts, and the share falls from a
-- false 1.0000 to a true 0.9434.
--
-- WHAT THIS DETECTOR CANNOT SEE. Stated here rather than left for somebody to discover:
--   1. A refusal that never reaches the handler. The platform's own JWT gate, a CORS preflight, a
--      gateway 429 and a cold-start 5xx each turn a customer away WITHOUT writing an agent_runs
--      row, so they are invisible to this detector and to every other one in this file. ZERO IS
--      AMBIGUOUS here: it cannot distinguish "nobody was turned away" from "nobody arrived" from
--      "the logging itself stopped".
--   2. Whether the refusal was RIGHT, and WHO was refused. A surface under a bot flood and a
--      surface with a broken identity lookup produce identical numbers; so do a real customer and
--      a rehearsal probe, because agent_runs carries no caller identity at all. That matters for
--      the very finding this detector was built to raise: login_otp's 106 attempts today are a
--      seeded burst as much as they are real people, and this engine cannot separate the two. It
--      reports that a customer-facing surface is turning callers away. Whether those callers were
--      customers is a question only the surface itself could answer, and it does not record it.
--   3. Anything under 20 logged attempts in 24 hours. customer_api refused 7 of 7 callers today and
--      sits below that floor, so it is NOT evaluated. The number of subjects skipped for thin
--      traffic is published in notes.refusals every tick so that silence can never be read as
--      health.
--   4. An internal path that has ALWAYS refused everything. It has no baseline to depart from and
--      it is not a public surface, so neither arm can fire. That is deliberate — a secret-gated
--      function refusing anonymous probes is correct — but a permanently broken internal auth path
--      reads clean here, and only a person noticing the constant would ever catch it.
v_ref_eval := 0;
v_ref_thin := 0;
for r in
  with rows0 as (
    select regexp_replace(a.agent, '^fn:', '') subject, a.agent, a.started_at, a.status, a.counts
    from public.agent_runs a
    where a.started_at > v_now - c_base
      -- 14 Sep 2026: a request made inside a rehearsal window is the test harness, not a customer.
      -- Measured: all 264 non-policy login_otp refusals of the day fell inside e2e rehearsal windows and
      -- none outside, and the finding they raised was hours from emailing the founder. The demo
      -- hygiene duty closes any window left open past six hours, which bounds what this can hide.
      and not public.fn_rehearsal_window_covers(a.started_at)
      -- drop the semantic half of a double-logged request; see THE DOUBLE LOG above
      and not (a.agent not like 'fn:%' and exists (
        select 1 from public.agent_runs t
        where t.agent = 'fn:' || a.agent
          and t.started_at between a.started_at - interval '5 seconds'
                               and a.started_at + interval '5 seconds'))),
  j as (
    select r0.subject, r0.started_at,
           coalesce(s.public_surface,false) pub, (s.subject is not null) known,
           -- fn_it_run_is_refusal's four telemetry shapes, MINUS its ±5s neighbour arm. That arm
           -- exists to lend a 4xx to a semantic row whose own counts say nothing; applied to a
           -- telemetry row inside a burst it marks a genuine 200 as refused because a NEIGHBOURING
           -- request 4xx'd two seconds later. Measured: it turned login_otp's six real successes
           -- into refusals and reported a share of 1.0000 instead of 0.9434. The paired rows are
           -- already removed above, so the arm has nothing left to do here.
           ((r0.counts ->> 'http') ~ '^4[0-9][0-9]$'
            or (r0.counts ->> 'signal') in ('forbidden','bad_secret')
            or (r0.counts ->> 'authorised') = '0'
            or coalesce(nullif(r0.counts ->> 'forbidden','')::int, 0) > 0
            or (coalesce(s.public_surface,false) and r0.status = 'skipped'))
           -- ...AND IT IS NOT THE PLATFORM ENFORCING A RULE. Added within the hour of D9 shipping,
           -- because D9's first live read raised a CRITICAL finding that login_otp turns away 94%
           -- of callers -- and 81 of those 100 refusals were two registered guards doing exactly
           -- what the founder specified ("a phone may confirm, never select; email is the
           -- identity"). A detector built to stop real refusals being ignored was about to page him
           -- because his own rules are being obeyed. The exemption is a REGISTER, not the log's own
           -- word for itself: it_refusal_policy holds an explicit (subject, reason) pair with the
           -- rule it enforces written in the row, so opting out of monitoring takes a reviewable
           -- act rather than a flattering sentence in a note.
           and not public.fn_it_refusal_is_policy(r0.subject, r0.counts) refused
    from rows0 r0
    left join public.it_watch_subject s on s.subject = r0.subject),
  w as (
    select subject, pub, known, count(*)::int n, count(*) filter (where refused)::int ref
    from j where started_at > v_now - c_ref_win group by 1,2,3),
  b as (
    select subject, count(*)::int n, count(*) filter (where refused)::int ref
    from j where started_at <= v_now - c_ref_win group by 1)
  select w.subject agent, w.pub, w.known, w.n, w.ref,
         coalesce(b.n,0) bn, coalesce(b.ref,0) bref
  from w left join b on b.subject = w.subject
  order by w.subject
loop
  -- Thin traffic is NOT a clean bill. It is counted and published, never silently dropped.
  if r.n < c_ref_min then
    v_ref_thin := v_ref_thin + 1;
    continue;
  end if;
  v_ref_eval := v_ref_eval + 1;
  v_share  := r.ref::numeric / r.n;
  v_bshare := case when r.bn >= c_ref_min then r.bref::numeric / r.bn else null end;
  v_state := case
               when r.pub and v_share >= 0.90 then 'stopped'
               when r.pub and v_share >= 0.50 then 'degraded'
               when v_bshare is not null and (v_share - v_bshare) >= 0.30 then 'degraded'
               else null end;
  continue when v_state is null;
  v_sev  := public.fn_it_severity(v_state, r.pub);
  v_key  := 'refusal_rate:' || r.agent;
  v_keys := v_keys || v_key;
  v_find := v_find || jsonb_build_object(
    'detector_key', v_key, 'detector', 'refusal_rate', 'subject', r.agent,
    'state', v_state, 'severity', v_sev,
    'title', r.agent || ' turned away ' || r.ref || ' of the ' || r.n
             || ' callers it logged in the last 24 hours (' || round(v_share*100) || '%'
             || case when v_bshare is null then ', with no comparable baseline of its own'
                     else ', against its own baseline of ' || round(v_bshare*100) || '%' end || ')'
             || case when r.pub then ' — and this is a surface a customer opens' else '' end,
    'evidence', jsonb_build_object(
      'window_hours', 24, 'window_attempts', r.n, 'window_refused', r.ref,
      'window_refusal_share', round(v_share,4),
      'baseline_attempts', r.bn, 'baseline_refused', r.bref,
      'baseline_refusal_share', case when v_bshare is null then null else round(v_bshare,4) end,
      'baseline_basis', case when r.bn >= c_ref_min then 'measured' else 'insufficient_history' end,
      'arm', case when r.pub and v_share >= 0.50
                  then 'dominance: a public surface refusing at least half of its logged traffic'
                  else 'departure: refusal share at least 30 points above this subject''s own baseline' end,
      'public_surface', r.pub,
      'surface_basis', case when r.known then 'it_watch_subject.public_surface'
                            else 'subject not in it_watch_subject; treated as internal' end,
      'refusal_definition','counts.http 4xx, or counts.signal forbidden/bad_secret, or counts.authorised=0, or counts.forbidden>0, or status=''skipped'' on a public surface',
      'basis','measured from agent_runs over 24 hours, with semantic rows that have a telemetry twin removed',
      'not_covered','a refusal that never reaches the handler (platform JWT gate, CORS preflight, gateway 429, cold-start 5xx) writes no agent_runs row and is invisible here'));
end loop;
v_notes := v_notes || jsonb_build_object('refusals', jsonb_build_object(
  'window_hours', 24, 'minimum_attempts', c_ref_min,
  'subjects_evaluated', v_ref_eval,
  'subjects_below_minimum', v_ref_thin,
  'basis', case when v_ref_eval = 0
                then 'no subject logged ' || c_ref_min || ' or more attempts in 24 hours, so NOTHING was evaluated and an absence of refusal findings proves nothing'
                else 'measured' end,
  'not_covered','refusals that never reach the handler write no agent_runs row; and this detector cannot tell a correct refusal from a broken one'));

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
$function$;

-- ══ 3b. AND ONE FINDING THAT WAS NEVER TRUE IS CLOSED, BY ITS EXACT KEY ═════════════════════
-- duty:db_health:slow:-4784328982199561541 — "A statement averages 20662.8 ms over 69 calls:
-- select count(*) icp from public.kb_chunks where source_id=$1" — has been open since 14 Sep and
-- was named tonight as the probable root cause of the export timeouts. It is not. Measured
-- 18 Sep 2026:
--   explain (analyze, buffers) of that exact statement, on a real source_id:
--     Aggregate -> Index Only Scan using kb_chunks_source_id_idx
--     Heap Fetches: 1   Buffers: shared hit=3 read=2   Execution Time: 1.576 ms
--   The index it supposedly needs has existed all along, and the planner uses it.
--   pg_stat_statements for the same queryid:  calls 69, min_exec_time 0.04 ms,
--   max_exec_time 117,713 ms, stddev 34,517 ms, shared_blks_read 2,046,009, stats_since 28 Aug.
--   A minimum of 0.04 ms and a maximum of 117 s is not a slow statement. It is a handful of calls
--   that read two million blocks cold while the daily export was scanning the same 9.1 GB table.
--   And the calls have not moved: 69 on 14 Sep, 69 on 18 Sep. Nothing has run this statement since
--   the finding was raised — it is session tooling, and it appears nowhere in the repository.
-- #732 already replaced that duty's lifetime average with a per-interval delta, which is why this
-- finding has not been re-raised since 00:16Z. What was left was the row itself. Closed by its
-- EXACT key, never by a title match: an ilike sweep closed an unfixed Stripe finding on 15 Sep.
update public.it_engineer_finding
   set closed_at = now(),
       close_note = 'Not a slow statement and not a missing index. Measured 18 Sep 2026: the exact '
         || 'statement plans as an Index Only Scan on kb_chunks_source_id_idx, 1.576 ms, 5 buffers. '
         || 'pg_stat_statements min_exec_time is 0.04 ms against a max of 117,713 ms over 69 calls '
         || 'since 28 Aug — cold-cache IO contention with the full export of a 9.1 GB table, not '
         || 'the query. The call count has not changed since the finding was raised (69 on 14 Sep, '
         || '69 on 18 Sep): nothing has run it since, and it exists in no file in the repository. '
         || 'The duty that raised it was corrected by #732 to measure an interval rather than a '
         || '104-day lifetime average, and has not re-raised this since 00:16Z.'
 where issue_key = 'duty:db_health:slow:-4784328982199561541'
   and closed_at is null;

-- ══ 4. PROBE ═══════════════════════════════════════════════════════════════════════════════
-- This file carries DDL, so the probe must not raise: a raise would roll back the CREATE OR
-- REPLACE above it. It reports through the one channel the management API does not discard, a
-- result set, per the convention in scripts/apply_sql.mjs (a NOTICE prints nowhere; measured).
--
-- It RUNS the routine rather than reading it. fn_it_detect(null, false) writes nothing: all three
-- of its writes (it_watch_finding insert, it_watch_finding update, it_watch_tick insert) sit
-- inside "if p_persist then", so this leaves 0 rows behind and touches no real person.
--
-- The source assertions are anchored on code, not on prose, because a check that greps source will
-- match its own explanation: the comments above talk about agent_runs and about queues that are
-- not draining, so the anchors are the exact statement text and the exact detector key instead.
with src as (
  select pg_get_functiondef(p.oid) d
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_it_detect' and p.prokind = 'f'
),
run as materialized (select public.fn_it_detect(null, false) as r),
depth as (
  select count(*) n from public.doc_backups
   where status = 'pending' and entity is distinct from 'zz_demo'
),
chk as (
  select
    (select d like '%into v_prev from public.agent_runs%' from src)              as reads_the_scheduler,
    (select d like '%''scheduler_unreadable''%' from src)                        as empty_read_is_raised,
    (select d like '%''it_detector_ticks_missed''%' from src)                    as own_ticks_have_their_own_key,
    (select d like '%''queue_not_draining:''%' from src)                         as drain_arm_present,
    (select drain_column from public.it_watch_queue where queue_key = 'doc_backups_pending')
                                                                                 as registered_drain_column,
    (select count(*) from pg_indexes
      where schemaname = 'public' and tablename = 'doc_backups'
        and indexname = 'ix_doc_backups_backed_up_at')                            as drain_index,
    (select r -> 'notes' -> 'scheduler' ->> 'basis' from run)                     as scheduler_basis,
    (select r -> 'notes' -> 'queue_doc_backups_pending_drain' ->> 'basis' from run)
                                                                                 as drain_basis,
    (select r -> 'notes' -> 'queue_doc_backups_pending_drain' ->> 'hours_to_clear' from run)
                                                                                 as hours_to_clear,
    (select r -> 'notes' -> 'queue_doc_backups_pending_drain' ->> 'drained_last_hour' from run)
                                                                                 as drained_last_hour,
    (select n from depth)                                                        as pending_now,
    (select count(*) from public.it_watch_tick where ran_at > now() - interval '20 seconds')
                                                                                 as ticks_written_by_the_probe,
    (select count(*) from public.it_engineer_finding
      where issue_key = 'duty:db_health:slow:-4784328982199561541' and closed_at is null)
                                                                                 as stale_slow_still_open
),
verdict as (
  select *,
    -- The drain note is absent only when the queue is empty, and an empty queue is not a failure.
    (drain_basis = 'measured' or (drain_basis is null and pending_now = 0)) as drain_measured
  from chk
)
select case when reads_the_scheduler and empty_read_is_raised and own_ticks_have_their_own_key
             and drain_arm_present and registered_drain_column = 'backed_up_at' and drain_index = 1
             and scheduler_basis = 'measured' and drain_measured
             and ticks_written_by_the_probe = 0 and stale_slow_still_open = 0
       then 'PROBE OK: the scheduler is read from agent_runs (basis ' || coalesce(scheduler_basis,'?')
            || '), this detector''s own missed ticks have their own key, and doc_backups_pending is '
            || 'measured at ' || coalesce(pending_now::text,'?') || ' pending / '
            || coalesce(drained_last_hour,'?') || ' cleared in the last hour = '
            || coalesce(hours_to_clear,'n/a') || ' hours to clear against a 24-hour threshold. '
            || 'The routine was executed with p_persist = false and wrote 0 it_watch_tick rows.'
       else 'PROBE FAILED: reads_the_scheduler=' || coalesce(reads_the_scheduler::text,'null')
            || ' empty_read_is_raised=' || coalesce(empty_read_is_raised::text,'null')
            || ' own_ticks_have_their_own_key=' || coalesce(own_ticks_have_their_own_key::text,'null')
            || ' drain_arm_present=' || coalesce(drain_arm_present::text,'null')
            || ' registered_drain_column=' || coalesce(registered_drain_column,'null')
            || ' drain_index=' || coalesce(drain_index::text,'null')
            || ' scheduler_basis=' || coalesce(scheduler_basis,'null')
            || ' drain_basis=' || coalesce(drain_basis,'null')
            || ' pending_now=' || coalesce(pending_now::text,'null')
            || ' ticks_written_by_the_probe=' || coalesce(ticks_written_by_the_probe::text,'null')
            || ' stale_slow_still_open=' || coalesce(stale_slow_still_open::text,'null')
       end as verdict
from verdict;
