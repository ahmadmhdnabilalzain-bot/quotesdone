-- THE WATCHERS ROUTE TO PRODUCT_ENG, NOT TO HIS INBOX (6 Sep 2026). Companion to
-- the_founder_is_emailed_exceptions_only.sql; founder's order: "so many errors were sent to me from the engine."
--
-- MEASURED, notifications to the founder, 30 days to 6 Sep 2026: these six routines sent him 176 emails —
-- 88 "Scheduled runs failed" (fn_watch_failed_runs), 42 "Scheduled job stopped/failing" and 4 "employee(s) have
-- stopped working" (fn_agent_silence_watch, fn_runner_silence_watch), 20 "Resilience" (fn_resilience_watch),
-- 12 "Business health" (fn_watch_health), 2 "Red view" (fn_red_view_alert). Not one was his to act on: every
-- one names a cron job, a runner, a watchdog finding or a department score that an engineer or a lead fixes.
--
-- WHAT CHANGES, every other line the live definition (pg_get_functiondef, 6 Sep 2026):
--   * the four routines that reached him through net.http_post -> alert_founder now call fn_notify_founder
--     directly with a named kind (scheduled_runs_failed, red_view / platform_down, business_health_at_risk,
--     resilience). The HTTP hop, its credential read and the raise-on-missing-secret go with it; the 24h
--     dedupe_key contract is kept by fn_notify_founder.
--   * fn_red_view_alert: a failing health check (a page down) is the platform_down kind, which the policy
--     allows; every other red is red_view, which it routes.
--   * fn_agent_silence_watch and fn_runner_silence_watch wrote notifications rows directly, with no to_role,
--     which is also why the digest never held them. They now call fn_founder_mail_route with their kind; their
--     own founder_alerts rows stay as their once-per-episode ledger.
--   * fn_resilience_watch no longer writes the 'digested' resilience_alert notifications row; the org_task is
--     the record.
-- Each kind opens ONE org_task for the IT operations engineer (runtime agent 'it', product_eng), or the COO
-- for runner_silence, or the CEO for business_health_at_risk, and an unchanged condition bumps that task.
--
--   node scripts/apply_sql.mjs scripts/sql/founder_mail_the_watchers_route_to_product_eng.sql --apply

CREATE OR REPLACE FUNCTION public.fn_watch_failed_runs()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_stale record;
  v_stale_n int := 0;
  v_rehearsal int := 0;
  v_since    timestamptz;
  v_fail     record;
  v_alerts   int := 0;
  v_held     int := 0;
  v_real     int := 0;
  v_detail   text := '';
  v_models_answering boolean;
begin
  select coalesce(last_run_at, now() - interval '24 hours') into v_since
    from alert_watermark where watcher = 'failed_runs';
  if not found then
    insert into alert_watermark (watcher, last_run_at) values ('failed_runs', now() - interval '24 hours');
    v_since := now() - interval '24 hours';
  end if;

  -- IS A MODEL ANSWERING AT ALL? This one boolean is what separates "the AI is broken" from
  -- "the AI is switched off", and it is measured, not configured - nothing here reads a flag that
  -- someone could forget to clear. A single successful attempt in the last 24 hours is enough to
  -- put every model-unavailable error back on the failure side.
  select exists (select 1 from public.llm_attempt
                  where created_at > now() - interval '24 hours' and coalesce(ok, false))
    into v_models_answering;
  -- Rows inside a declared sandbox rehearsal window (demo_factory.withRun): counted, stated in the
  -- message if one goes out, never the reason one goes out. A rehearsal on the production database
  -- paged the founder twice on 3 Sep 2026 about the operator's own probes; this is the fix.
  select count(*) into v_rehearsal
    from agent_runs r
   where r.started_at > v_since and r.status = 'error'
     and public.fn_rehearsal_window_covers(r.started_at);

  for v_fail in
    select r.agent,
           count(*) as fails,
           max(r.started_at) as latest,
           left(coalesce(max(r.note), ''), 300) as sample_note,
           -- The signature is the agent plus the shape of the note, not the note itself: the same
           -- standing condition arrives with different numbers in it every pass ("3 step(s) are
           -- ready" one hour, "4" the next) and must still be recognised as the same condition.
           r.agent || ':' || left(regexp_replace(coalesce(max(r.note), ''), '[0-9]+', '#', 'g'), 120) as signature,
           bool_or(coalesce(r.note, '') ~* '(model returned nothing|returned no content|generation_failed|returned nothing for|model call failed|open-circuit|LLM call failed)') as model_shaped
      from agent_runs r
     where r.started_at > v_since and r.status = 'error'
       -- a row inside a DECLARED rehearsal window is counted below, not paged (3 Sep 2026)
       and not public.fn_rehearsal_window_covers(r.started_at)
     group by r.agent, left(regexp_replace(coalesce(r.note, ''), '[0-9]+', '#', 'g'), 120)
     order by count(*) desc
  loop
    -- HELD: a model did not answer, and no model has answered at all. Counted, recorded, not
    -- alerted. The moment v_models_answering flips true this branch stops being taken.
    if v_fail.model_shaped and not v_models_answering then
      v_held := v_held + v_fail.fails;
      insert into public.alert_signature (watcher, signature)
        values ('failed_runs', v_fail.signature)
        on conflict (watcher, signature) do update
          set last_seen_at = now(), seen_count = alert_signature.seen_count + 1, resolved_at = null;
      continue;
    end if;

    v_real := v_real + v_fail.fails;

    -- ONCE PER CONDITION. A signature alerted inside the last 24 hours is still recorded as seen,
    -- and does not interrupt him again.
    insert into public.alert_signature (watcher, signature)
      values ('failed_runs', v_fail.signature)
      on conflict (watcher, signature) do update
        set last_seen_at = now(), seen_count = alert_signature.seen_count + 1, resolved_at = null;

    if exists (select 1 from public.alert_signature s
                where s.watcher = 'failed_runs' and s.signature = v_fail.signature
                  and s.last_alerted_at > now() - interval '24 hours') then
      continue;
    end if;

    v_detail := v_detail || v_fail.agent || ': ' || v_fail.fails || ' failure(s). ' || v_fail.sample_note || E'\n';
    v_alerts := v_alerts + 1;
    update public.alert_signature set last_alerted_at = now()
      where watcher = 'failed_runs' and signature = v_fail.signature;
  end loop;

  -- The hold is stated once, in the same message, so it is never invisible: he should be able to
  -- see that the quiet is his own decision and not a working company.
  if v_held > 0 then
    v_detail := v_detail || E'\n' || v_held ||
      ' further run(s) could not reach a model. No model call has succeeded in 24 hours, so these ' ||
      'are counted as held by the paid-inference hold, not as failures. They will be reported as ' ||
      'failures again the moment a model answers.' || E'\n';
  end if;

  -- THE DEAD-GUARD BLIND SPOT (3 Sep 2026). A job that never fires produces no failure. v_cron_stale
  -- lists active jobs with no run of any status inside twice their schedule, measured from activation
  -- (scripts/sql/v_cron_stale_the_dead_guard_blind_spot.sql). Same ledger, same once-per-24h rule.
  for v_stale in select jobname, schedule, why from public.v_cron_stale order by jobname loop
    v_stale_n := v_stale_n + 1;
    insert into public.alert_signature (watcher, signature) values ('failed_runs', 'cron_stale:' || v_stale.jobname)
    on conflict (watcher, signature) do update set last_seen_at = now(), seen_count = alert_signature.seen_count + 1, resolved_at = null;
    if exists (select 1 from public.alert_signature s where s.watcher = 'failed_runs'
                 and s.signature = 'cron_stale:' || v_stale.jobname and s.last_alerted_at > now() - interval '24 hours') then
      continue;
    end if;
    v_detail := v_detail || 'cron ' || v_stale.jobname || ' has NOT FIRED: ' || v_stale.why || E'\n';
    v_alerts := v_alerts + 1;
    update public.alert_signature set last_alerted_at = now() where watcher = 'failed_runs' and signature = 'cron_stale:' || v_stale.jobname;
  end loop;

  -- A SIGNATURE RESOLVES ON MERIT, NOT ON THE CLOCK (5 Sep 2026). The red view carried a watcher
  -- episode for 24 h after the last sighting whatever the subject did next. kb_embed had run
  -- 'ok' 83 times after its last error and dr_drill 4 times, and both stayed red; monthly_report was
  -- listed stale every hour and paged every day because v_cron_stale read '0 7 1 * *' as daily.
  -- Two rules, both measured from the subject's own ledger:
  --   failed-run signature  -> resolved when the agent has a status='ok' run started AFTER the
  --                            watcher last saw the failure (last_seen_at). A later failure re-opens
  --                            it through the upsert above (resolved_at = null), which the red view
  --                            then treats as a NEW episode and pages again.
  --   cron_stale signature  -> resolved when the job is no longer listed by v_cron_stale on this
  --                            pass, i.e. a run of any status has been recorded since.
  update public.alert_signature s
     set resolved_at = now()
   where s.watcher = 'failed_runs' and s.resolved_at is null
     and s.signature not like 'cron_stale:%'
     and exists (select 1 from public.agent_runs ok
                  where ok.agent = split_part(s.signature, ':', 1)
                    and ok.status = 'ok' and ok.started_at > s.last_seen_at);
  update public.alert_signature s
     set resolved_at = now()
   where s.watcher = 'failed_runs' and s.resolved_at is null
     and s.signature like 'cron_stale:%'
     and not exists (select 1 from public.v_cron_stale c where 'cron_stale:' || c.jobname = s.signature);

  if v_rehearsal > 0 then
    v_detail := v_detail || E'\n' || v_rehearsal || ' further run(s) failed inside a declared sandbox rehearsal window and were not paged.' || E'\n';
  end if;

  if v_alerts > 0 then
    -- 6 SEP 2026: fn_notify_founder, not an HTTP hop to alert_founder. founder_mail_policy routes this kind
    -- (scheduled_runs_failed) to the IT operations engineer as ONE org_task per condition; it never emails him.
    perform public.fn_notify_founder(
      'Scheduled runs failed (' || v_alerts || ' new condition(s))', v_detail, 'error',
      p_kind => 'scheduled_runs_failed',
      -- Dedupe on the day, not the hour. The hour made the key change every pass, which is why
      -- a dedupe key existed for three weeks and never deduplicated anything.
      p_dedupe_key => 'failed_runs:' || to_char(now(),'YYYY-MM-DD'));
    update alert_watermark set last_alert_at = now() where watcher = 'failed_runs';
  end if;

  update alert_watermark set last_run_at = now() where watcher = 'failed_runs';
  return jsonb_build_object(
    'checked_since', v_since,
    'models_answering', v_models_answering,
    'runs_failed', v_real,
    'runs_held_by_ai_hold', v_held,
    'runs_in_declared_rehearsal', v_rehearsal,
    'crons_stale', v_stale_n,
    'new_conditions_alerted', v_alerts,
    'alerted', v_alerts > 0);
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_agent_silence_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int:=0; f int:=0; g int:=0; nr int:=0; v_email text; v_run bigint;
begin
  insert into agent_runs(agent, started_at) values ('agent_silence_watch', clock_timestamp()) returning id into v_run;

  select to_email into v_email from notifications
   where type='founder_brief' and to_email is not null order by created_at desc limit 1;

  insert into cron_job_seen (jobid, jobname, schedule)
  select j.jobid, j.jobname, j.schedule from cron.job j where j.active
  on conflict (jobid) do update set last_seen = now(), jobname = excluded.jobname, schedule = excluded.schedule;

  -- Record successes BEFORE evaluating, so they survive the 14-day history prune.
  update cron_job_seen s
     set last_success = h.last_ok
    from (select jobid, max(start_time) as last_ok
            from cron.job_run_details where status='succeeded' group by jobid) h
   where h.jobid = s.jobid
     and (s.last_success is null or s.last_success < h.last_ok);

  for r in
    -- ONE AGGREGATE, NOT THREE CORRELATED SUBQUERIES PER JOB. This loop used to ask
    -- cron.job_run_details three separate questions for each of 165 active jobs against an 80 MB
    -- heap with no usable index, and on 11 Aug 2026 it began exceeding the statement timeout and
    -- stopped watching anything at all. A watchdog that dies silently is worse than no watchdog:
    -- fn_agent_silence_watch is the routine that would have reported its own absence.
    with h as (
      select jobid,
             count(*)                                                        as history_rows,
             max(start_time) filter (where status='succeeded')               as last_ok_live,
             count(*) filter (where status='failed'
                              and start_time > now() - interval '24 hours')  as fails_24h
        from cron.job_run_details
       group by jobid)
    select j.jobid, j.jobname,
           case when split_part(j.schedule,' ',5) <> '*' then 336
                when split_part(j.schedule,' ',3) <> '*' then 1440
                when split_part(j.schedule,' ',2) =  '*' then 6
                else 72 end as thresh_h,
           coalesce(h.history_rows, 0) as history_rows,
           greatest(h.last_ok_live, s.last_success) as last_ok,
           coalesce(h.fails_24h, 0) as fails_24h,
           s.first_seen,
           s.last_success as stored_ok
      from cron.job j
      left join h on h.jobid = j.jobid
      left join cron_job_seen s on s.jobid = j.jobid
     where j.active
  loop
    -- ACTIVATION IS THE FLOOR (3 Sep 2026). A job re-enabled today with a last success from before
    -- the 16 Aug stand-down is not silent — its clock starts when it was put back on (the kernel
    -- wrapper's wrapped_at). This watch paged the founder about 15 such jobs in one day.
    if exists (select 1 from public.phase_c_system_execution_wrapper w
                where w.jobid = r.jobid and w.wrapped_at > now() - (r.thresh_h||' hours')::interval) then
      continue;
    end if;
    -- Never-run: only when there is NO history AND we have never recorded a success.
    if r.history_rows = 0 and r.stored_ok is null then
      if r.first_seen is not null and r.first_seen < now() - (r.thresh_h||' hours')::interval then
        if not exists (select 1 from founder_alerts where event='cron_never_ran'
                        and detail like '%"'||r.jobname||'"%'
                        and created_at > now() - interval '24 hours') then
          insert into founder_alerts(level,event,detail,channel)
          values ('high','cron_never_ran', jsonb_build_object(
            'job', r.jobname,
            'first_seen', r.first_seen::text,
            'known_for_hours', round(extract(epoch from (now()-r.first_seen))/3600),
            'expected_within_hours', r.thresh_h)::text, 'email');
          -- 6 SEP 2026: routed to the IT operations engineer as one org_task per job, never emailed
          -- (founder_mail_policy.agent_silence); this watcher's own founder_alerts row above is its ledger.
          perform public.fn_founder_mail_route('agent_silence', 'Scheduled job has never run: '||r.jobname,
              'Job "'||r.jobname||'" is active but has no run history at all. It has been registered since '||
              r.first_seen::text||' and should have run at least every '||r.thresh_h||' hours. It is likely misregistered.', 'high');
          nr := nr + 1;
        end if;
      else
        g := g + 1;
      end if;
      continue;
    end if;

    if r.last_ok is null or r.last_ok < now() - (r.thresh_h||' hours')::interval then
      -- ONCE PER SILENCE EPISODE (3 Sep 2026): the episode is (job, last_success). It is paged the
      -- first time it is seen and never again until the job succeeds again — the 24-hour dedupe
      -- this replaced re-paged every silent job every day.
      if not exists (select 1 from founder_alerts where event='cron_silent'
                      and detail like '%"job": "'||r.jobname||'"%'
                      and detail like '%"last_success": "'||coalesce(r.last_ok::text,'no success on record')||'"%') then
        insert into founder_alerts(level,event,detail,channel)
        values ('high','cron_silent', jsonb_build_object(
          'job',r.jobname,'last_success',coalesce(r.last_ok::text,'no success on record'),
          'silent_hours',round(extract(epoch from (now()-r.last_ok))/3600),
          'expected_within_hours',r.thresh_h)::text,'email');
        perform public.fn_founder_mail_route('agent_silence', 'Scheduled job stopped: '||r.jobname,
            'Job "'||r.jobname||'" last succeeded '||coalesce(r.last_ok::text,'unknown')||
            '. Expected at least every '||r.thresh_h||' hours.', 'high');
        n := n + 1;
      end if;
    end if;

    if r.fails_24h > 0 then
      if not exists (select 1 from founder_alerts where event='cron_failing'
                      and detail like '%"'||r.jobname||'"%'
                      and created_at > now() - interval '24 hours') then
        insert into founder_alerts(level,event,detail,channel)
        values ('high','cron_failing',
          jsonb_build_object('job',r.jobname,'failures_24h',r.fails_24h,
                             'last_success',coalesce(r.last_ok::text,'unknown'))::text,'email');
        perform public.fn_founder_mail_route('agent_silence', 'Scheduled job failing: '||r.jobname,
            'Job "'||r.jobname||'" has failed '||r.fails_24h||' time(s) in the last 24 hours. Last success: '||
            coalesce(r.last_ok::text,'unknown')||'. Check cron.job_run_details for the error text.', 'high');
        f := f + 1;
      end if;
    end if;
  end loop;

  update agent_runs
     set finished_at=clock_timestamp(), status='ok',
         counts=jsonb_build_object('active_jobs',(select count(*) from cron.job where active),
                                   'in_grace',g,'silent',n,'failing',f,'never_ran',nr)
   where id=v_run;

  return jsonb_build_object('ran_at',now(),
    'active_jobs',(select count(*) from cron.job where active),
    'in_grace',g,'silent_alerts',n,'failing_alerts',f,'never_ran_alerts',nr);
exception when others then
  update agent_runs set finished_at=clock_timestamp(), status='error', note=left(sqlerrm,500) where id=v_run;
  raise;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_runner_silence_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_run bigint; n_alert int := 0; n_watched int := 0; v_email text;
begin
  insert into agent_runs(agent, started_at) values ('runner_silence_watch', clock_timestamp()) returning id into v_run;

  select to_email into v_email from notifications
   where type='founder_brief' and to_email is not null order by created_at desc limit 1;

  -- RE-DERIVE, NEVER SEED. One pass over 30 days of runs gives every runner its own observed
  -- cadence. A runner seen fewer than 5 times has no cadence worth calling regular and is recorded
  -- as on-demand rather than alerted on — which is what stops this becoming the noise generator the
  -- 18 July snapshot would have been if anything had ever read it.
  with runs as (
    select agent, started_at, counts,
           started_at - lag(started_at) over (partition by agent order by started_at) gap
      from agent_runs where started_at > now() - interval '30 days'),
  agg as (
    select agent,
           count(*) as n,
           -- A CADENCE IS NOT A BURST. Measured on the first run: doc_extract, match, quote_compare,
           -- inquiry_intake and stripe_webhook all showed a "median gap" of 0.00-0.08 hours, because
           -- they are EVENT-DRIVEN and fire in clusters when work arrives. Treating a cluster as a
           -- schedule makes every quiet day an alert. A real cadence shows up on separate DAYS, so
           -- that is what is counted.
           count(distinct started_at::date) as active_days,
           -- A RUNNER LOGGED ONLY ON EXCEPTIONS HAS NO CADENCE EITHER. cos_execute writes an
           -- agent_runs row under its own name ONLY when it has a throttled signal to report (a
           -- refused task start); its ordinary hourly work is logged under 'chief_of_staff'. So its
           -- rows stop the moment it stops having a PROBLEM, and the first version of this watch
           -- read that as the runner going silent -- alerting daily on a loop that was working.
           count(*) filter (where coalesce(counts ? 'signal', false)) as signal_rows,
           max(started_at) as last_seen,
           percentile_cont(0.5) within group (order by extract(epoch from gap)/3600.0) as median_gap_h
      from runs group by agent)
  insert into agent_expectations (agent, kind, max_silence_hours, on_demand, median_gap_hours,
                                  runs_observed, last_seen, note, updated_at)
  select a.agent,
         case when exists (select 1 from org_agents o where o.agent_key = a.agent) then 'employee' else 'code' end,
         -- Three times its own median, floored at 6 hours and capped at two weeks. Derived from the
         -- runner rather than from its schedule, because the schedule is what fn_agent_silence_watch
         -- already checks and is exactly what stayed green while the work stopped.
         case when a.n >= 5 and a.active_days >= 5 and a.median_gap_h >= 0.5 and a.n > a.signal_rows
              then least(336, greatest(6, ceil(a.median_gap_h * 3)))
              else 999999 end,
         not (a.n >= 5 and a.active_days >= 5 and a.median_gap_h >= 0.5 and a.n > a.signal_rows),
         round(a.median_gap_h::numeric, 2),
         a.n,
         a.last_seen,
         case when a.n >= 5 and a.active_days >= 5 and a.median_gap_h >= 0.5 and a.n > a.signal_rows
              then 'cadence learned from '||a.n||' run(s) across '||a.active_days||' day(s) in 30d, median gap '||round(a.median_gap_h::numeric,2)||'h'
              else 'no steady cadence ('||a.n||' run(s) across '||a.active_days||' day(s), median gap '
                   ||coalesce(round(a.median_gap_h::numeric,2)::text,'n/a')||'h) — event-driven or on-demand, not watched' end,
         now()
    from agg a
  on conflict (agent) do update set
    kind = excluded.kind, max_silence_hours = excluded.max_silence_hours,
    on_demand = excluded.on_demand, median_gap_hours = excluded.median_gap_hours,
    runs_observed = excluded.runs_observed, last_seen = excluded.last_seen,
    note = excluded.note, updated_at = now();

  select count(*) into n_watched from agent_expectations where not on_demand;

  -- EVERY row, not just the watched ones. Scoping this to `not on_demand` left a stale silent=true
  -- on any runner that moved INTO on_demand — measured on the first run: five event-driven runners
  -- kept a silent flag they could no longer clear.
  update agent_expectations e
     set silent = (not e.on_demand
                   and e.last_seen is not null
                   and e.last_seen < now() - (e.max_silence_hours || ' hours')::interval);

  -- ONCE PER SILENCE EPISODE, ONE EMAIL PER RUN (3 Sep 2026). This loop paged the founder once per
  -- silent employee per DAY — 21 "Employee has stopped working" emails in the 24 hours measured on
  -- 3 Sep, 59 all-time — for runners whose schedules were switched off by his own 16 Aug stand-down
  -- and re-enabled on 2-3 Sep. A silence is one fact, not a daily one: an episode is (runner,
  -- last_seen); it is paged the first time it is seen and never again until the runner has run
  -- (a new last_seen is a new episode). And the employees newly silent in one pass go into ONE
  -- email, never one email each. Nothing is hidden: every silent runner is still in
  -- agent_expectations.silent and in the company snapshot.
  declare v_new text := ''; v_new_n int := 0;
  begin
  for r in select agent, kind, last_seen, max_silence_hours, median_gap_hours
             from agent_expectations where silent and not on_demand order by agent
  loop
    if not exists (select 1 from founder_alerts
                    where event='runner_silent'
                      and detail like '%"runner": "'||r.agent||'"%'
                      and detail like '%"last_run": "'||coalesce(r.last_seen::text,'')||'"%') then
      insert into founder_alerts(level, event, detail, channel)
      values (case when r.kind='employee' then 'high' else 'warn' end, 'runner_silent',
        jsonb_build_object('runner', r.agent, 'kind', r.kind,
          'last_run', r.last_seen::text,
          'silent_hours', round(extract(epoch from (now()-r.last_seen))/3600),
          'own_median_gap_hours', r.median_gap_hours,
          'expected_within_hours', r.max_silence_hours)::text, 'email');
      if r.kind = 'employee' then
        v_new_n := v_new_n + 1;
        v_new := v_new || '- ' || r.agent || ': last did anything at ' || coalesce(r.last_seen::text,'unknown')
              || ' (own cadence one run every ' || coalesce(r.median_gap_hours::text,'?') || ' hours)' || E'\n';
      end if;
      n_alert := n_alert + 1;
    end if;
  end loop;
  if v_new_n > 0 then
    -- 6 SEP 2026: routed to the COO as one org_task per condition, never emailed
    -- (founder_mail_policy.runner_silence); this watcher's own founder_alerts rows are its ledger.
    perform public.fn_founder_mail_route('runner_silence',
      v_new_n || ' employee(s) have stopped working',
      'These runners went past their own observed cadence for the first time since they last ran:' || E'\n' || v_new ||
      E'\n' || 'Each is reported once per silence; it will be reported again only after it runs and stops again. ' ||
      'A scheduled job may still be succeeding — this watch looks at what the runner DID, not at whether its schedule fired.',
      'high');
  end if;
  end;

  update agent_runs set finished_at=clock_timestamp(), status='ok',
      counts=jsonb_build_object('runners', (select count(*) from agent_expectations),
                                'watched', n_watched, 'silent', (select count(*) from agent_expectations where silent),
                                'alerts', n_alert,
                                'employees', (select count(*) from agent_expectations where kind='employee'))
   where id=v_run;

  return jsonb_build_object('runners',(select count(*) from agent_expectations),
                            'watched',n_watched,'alerts',n_alert);
exception when others then
  update agent_runs set finished_at=clock_timestamp(), status='error', note=left(sqlerrm,500) where id=v_run;
  raise;
end $function$;

CREATE OR REPLACE FUNCTION public.fn_red_view_alert(p_boards boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_now        timestamptz := clock_timestamp();
  v_t0         timestamptz := clock_timestamp();
  v_red        int;
  v_opened     int := 0;
  v_resolved   int := 0;
  v_pending    int := 0;
  v_shown      int;
  v_open_total int;
  v_level      text;
  v_high       boolean;
  v_detail     text;
  v_keys       text;
  v_dedupe     text;
  v_req        bigint;
  v_suppressed int := 0;
begin
  create temp table if not exists red_now (source text, check_key text, detail text, opened_at timestamptz) on commit drop;
  delete from red_now;

  -- 1. kernel boards
  if p_boards then
    insert into red_now
    select 'board', 'board:' || b.board || ':' || b.check_name,
           left('expected ' || coalesce(b.expected,'') || ' | actual ' || coalesce(b.actual,''), 300), v_now
      from public.fn_kernel_all_boards() b
     where not b.ok;
  end if;

  -- 2. crons: latest run failed (pg_cron's own record) ...
  insert into red_now
  select 'cron', 'cron:' || j.jobname, left(coalesce(d.return_message,''), 300), d.start_time
    from cron.job j
    join (select distinct on (jobid) jobid, status, start_time, return_message
            from cron.job_run_details
           where start_time > v_now - interval '8 days'
           order by jobid, start_time desc, runid desc) d on d.jobid = j.jobid
   where j.active and d.status = 'failed';
  -- ... or latest kernel trace failed (the wrapper records the failure and returns normally)
  insert into red_now
  select 'cron', 'cron:' || j.jobname, left(coalesce(e.failure,''), 300), e.finished_at
    from cron.job j
    join public.phase_c_system_execution_wrapper w on w.jobid = j.jobid
    join (select distinct on (component_id) component_id, result, failure, finished_at
            from public.phase_c_system_execution
           where finished_at > v_now - interval '8 days'
           order by component_id, finished_at desc, trace_id desc) e on e.component_id = w.component_id
   where j.active and e.result = 'failed';

  -- 2b. credentials: an internal credential within 7 days of expiry. credential_rotate_daily
  -- renews every fn.<edge> credential 30 days ahead, so a row still here at 7 days means the
  -- rotation has been failing for three weeks -- and fn_internal_auth refuses it on the day.
  insert into red_now
  select 'credential', 'credential:' || c.context,
         left('expires ' || to_char(c.expires_at, 'YYYY-MM-DD HH24:MI') || ' UTC and no rotation has replaced it (credential_rotate_daily)', 300),
         c.expires_at - interval '7 days'
    from public.internal_credential c
   where c.active and c.retired_at is null and c.expires_at is not null and c.expires_at <= v_now + interval '7 days';
  -- 3. health checks: the latest row per target is failing
  insert into red_now
  select 'health', 'health:' || h.check_kind || ':' || h.target,
         left(coalesce(h.detail,'') || case when h.status_code is not null then ' (http ' || h.status_code || ')' else '' end, 300),
         h.created_at
    from (select distinct on (check_kind, target) *
            from public.health_checks
           where created_at > v_now - interval '24 hours'
           order by check_kind, target, created_at desc, id desc) h
   where h.ok = false;

  -- 4. connectivity register
  insert into red_now
  select 'connectivity', 'connectivity:' || r.gap_class || ':' || left(r.subject, 120), left(r.detail, 300), v_now
    from public.fn_company_connectivity_register() r;

  -- 5. department health board
  insert into red_now
  select 'department', 'department:' || v.dept_key,
         left(v.department || ' score ' || v.score::text || ' — ' || v.basis, 300), v_now
    from public.v_department_health v
    join public.org_departments d on d.dept_key = v.dept_key and d.active
   where v.status = 'at risk';

  -- 6. what the failed-runs watcher already paged (kept in the register, never paged twice)
  insert into red_now
  select 'watcher', 'watcher:' || left(s.signature, 150), left(s.signature, 300), s.first_seen_at
    from public.alert_signature s
   where s.watcher = 'failed_runs' and s.last_alerted_at is not null
     and s.last_seen_at > v_now - interval '24 hours'
     -- 5 Sep 2026: a signature the watcher has resolved on merit (its subject succeeded since) is green
     and s.resolved_at is null;

  select count(distinct check_key) into v_red from red_now;

  -- open what is new
  insert into public.red_episode (source, check_key, detail, opened_at, observed_at, last_seen_at, alerted_at, paged_by)
  select r.source, r.check_key, r.detail, r.opened_at, v_now, v_now,
         case when r.source = 'watcher' then v_now end,
         case when r.source = 'watcher' then 'failed_runs' end
    from (select distinct on (check_key) * from red_now order by check_key, opened_at) r
   where not exists (select 1 from public.red_episode e where e.check_key = r.check_key and e.resolved_at is null);
  get diagnostics v_opened = row_count;

  -- keep what is still red current
  update public.red_episode e
     set last_seen_at = v_now, detail = r.detail
    from (select distinct on (check_key) * from red_now order by check_key, opened_at) r
   where r.check_key = e.check_key and e.resolved_at is null;

  -- resolve what is green again (board episodes only on a pass that read the boards)
  update public.red_episode e
     set resolved_at = v_now
   where e.resolved_at is null
     and (p_boards or e.source <> 'board')
     and not exists (select 1 from red_now r where r.check_key = e.check_key);
  get diagnostics v_resolved = row_count;

  -- page the founder once for everything open and not yet alerted
  select count(*) into v_pending from public.red_episode where resolved_at is null and alerted_at is null;
  if v_pending > 0 then
    if public.fn_rehearsal_window_covers(v_now) then
      v_suppressed := v_pending;      -- a declared rehearsal: posted by the first pass after it closes
    else
      select count(*) into v_open_total from public.red_episode where resolved_at is null;
      -- the EPISODE ids are in the hash, not just the keys: the same key going red a second time is a
      -- new episode and must not be held by alert_founder's 24 h dedupe on the previous message's key
      -- (the probe caught exactly that before this line carried the id)
      select string_agg(check_key || '#' || id, ',' order by check_key, id),
             bool_or(source = 'health')
        into v_keys, v_high
        from public.red_episode where resolved_at is null and alerted_at is null;
      -- a page down is 'high' (alert_founder sends WhatsApp for high); everything else is 'error' (email)
      v_level  := case when v_high then 'high' else 'error' end;
      v_dedupe := 'red_view:' || md5(v_keys);
      select string_agg(left(check_key, 70) || ' — ' || left(coalesce(detail,''), 90), E'\n' order by opened_at), count(*)
        into v_detail, v_shown
        from (select check_key, detail, opened_at from public.red_episode
               where resolved_at is null and alerted_at is null
               order by opened_at limit 12) x;
      v_detail := v_pending || ' signal(s) went red and had not been alerted; ' || v_open_total
               || ' red in total right now.' || E'\n\n' || v_detail
               || case when v_pending > v_shown then E'\n… and ' || (v_pending - v_shown) || ' more (public.red_episode)' else '' end;

      -- 6 SEP 2026: fn_notify_founder, not an HTTP hop to alert_founder. A page down (source = 'health') is
      -- the platform_down kind and may reach him; every other red is the red_view kind, which
      -- founder_mail_policy routes to the IT operations engineer as ONE org_task per condition.
      perform public.fn_notify_founder(
        'Red view: ' || v_pending || ' new red signal(s)', left(v_detail, 1000), v_level,
        p_kind => case when v_high then 'platform_down' else 'red_view' end,
        p_dedupe_key => v_dedupe);
      update public.red_episode
         set alerted_at = clock_timestamp(), alert_dedupe_key = v_dedupe, paged_by = 'red_view'
       where resolved_at is null and alerted_at is null;
    end if;
  end if;

  return jsonb_build_object(
    'red_now', v_red, 'opened', v_opened, 'resolved', v_resolved,
    'paged', case when v_suppressed = 0 then v_pending else 0 end,
    'pending_in_rehearsal', v_suppressed,
    'level', v_level, 'dedupe_key', v_dedupe, 'request_id', v_req,
    'boards_read', p_boards,
    'elapsed_ms', round(extract(epoch from (clock_timestamp() - v_t0)) * 1000));
end $function$;

-- ROUTINE REMOVED 7 September 2026. public.fn_watch_health was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ROUTINE REMOVED 7 September 2026. public.fn_resilience_watch was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

