-- ---------------------------------------------------------------------------------------------
-- WHAT ACTUALLY MAKES THE ERROR SURFACE FEEL HEAVY. IT WAS NEVER error_events.
--
-- The brief said error_events holds 10 rows and something else must be doing it. Measured on
-- htdblwldjkcgjvmqkbeh, 16 Aug 2026, over the trailing 24 hours:
--
--   agent_runs status='error'                                          70
--     "the model returned nothing" / "returned no content" / etc.      43
--     workflow_step_sweep "STALLED: 3 workflow step(s) are ready"      25
--     boq_fixture_check "every model route ... is open-circuit"         1
--     resend_inbound "LLM call failed (http 503)"                       1
--     scenario_rehearsal - a run that reports what it accomplished      1
--   agent_runs status='ok' over the same window                       941
--   llm_attempt rows over the same window                               0   (last: 15 Aug 02:51)
--   founder alerts "[Action needed] Scheduled runs failed (N agent(s))"
--     over 7 days                                                      56, each in a distinct hour
--
-- So the error surface is not seventy things going wrong. It is TWO STANDING CONDITIONS repeated
-- once an hour:
--
--   1. Paid inference is switched off. The founder ordered that hold and it is still in force -
--      zero model calls in 25 hours. Every agent that tries to think reports "the model returned
--      nothing" and marks itself failed. The machine is reporting his own decision back to him as
--      an outage, seven or eight times a day.
--   2. Three workflow steps are stuck. That is one fact. It was alerted 25 times in a day because
--      the sweep re-reports the same standing condition on every pass.
--
-- fn_watch_failed_runs counted every error row equally and its dedupe_key contains the hour, so it
-- could never dedupe across hours by construction.
--
-- WHAT THIS CHANGES, AND WHAT IT DELIBERATELY DOES NOT.
--
-- It does not stop measuring anything, and it does not stop reporting anything. Every count is
-- still computed and still returned in the JSON, so the state is readable at any time whether or
-- not an alert fires. Two rules decide what is worth an interruption:
--
--   HELD, not failed. A run whose note says a model did not answer is reclassified as `held`
--   ONLY WHILE there has been no successful model call in the window. That condition is the whole
--   safety of it: the moment the founder releases the hold and one call succeeds, the same note
--   counts as a failure again and alerts. It cannot become a permanent excuse, because it disarms
--   itself on the first sign of a working model. This is not a weakened check - a check that
--   reports a deliberate configuration as an outage is not a strong check, it is a broken one, and
--   its noise is what buries the twenty-seventh error that matters.
--
--   ONCE PER CONDITION, not once per pass. A real failure alerts when its signature (agent + the
--   shape of its note) has not alerted in 24 hours. A new failure still alerts within the hour.
--   A standing one alerts on day one and then stops shouting.
--
-- Expected effect on today's data: 43 held, 27 real across 4 signatures, 4 alerts on the first
-- pass and 0 on every pass after that until something changes - against 7-8 per day today.
-- ---------------------------------------------------------------------------------------------

create table if not exists public.alert_signature (
  watcher        text        not null,
  signature      text        not null,
  first_seen_at  timestamptz not null default now(),
  last_seen_at   timestamptz not null default now(),
  last_alerted_at timestamptz,
  seen_count     bigint      not null default 1,
  primary key (watcher, signature)
);
alter table public.alert_signature enable row level security;
revoke all on public.alert_signature from anon, authenticated;

comment on table public.alert_signature is
  'One row per distinct failure condition a watcher has seen. Lets a watcher alert once for a '
  'standing condition instead of once per pass, without losing the fact that it is still standing '
  '- last_seen_at and seen_count keep saying so.';

create or replace function public.fn_watch_failed_runs()
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $fn$
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
  v_secret   text;
  v_models_answering boolean;
  v_url      text;
begin
  -- The project ref is read, not written into the body. This function was one of the 48 places
  -- that embedded it as a literal, and an export that names the project it came from is not
  -- portable. Same pattern as fn_action_invoke_dispatch and fn_rfq_redispatch_sweep.
  select 'https://' || value || '.supabase.co/functions/v1/alert_founder' into v_url
    from app_secrets where key = 'project_ref';

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
          set last_seen_at = now(), seen_count = alert_signature.seen_count + 1;
      continue;
    end if;

    v_real := v_real + v_fail.fails;

    -- ONCE PER CONDITION. A signature alerted inside the last 24 hours is still recorded as seen,
    -- and does not interrupt him again.
    insert into public.alert_signature (watcher, signature)
      values ('failed_runs', v_fail.signature)
      on conflict (watcher, signature) do update
        set last_seen_at = now(), seen_count = alert_signature.seen_count + 1;

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
    on conflict (watcher, signature) do update set last_seen_at = now(), seen_count = alert_signature.seen_count + 1;
    if exists (select 1 from public.alert_signature s where s.watcher = 'failed_runs'
                 and s.signature = 'cron_stale:' || v_stale.jobname and s.last_alerted_at > now() - interval '24 hours') then
      continue;
    end if;
    v_detail := v_detail || 'cron ' || v_stale.jobname || ' has NOT FIRED: ' || v_stale.why || E'\n';
    v_alerts := v_alerts + 1;
    update public.alert_signature set last_alerted_at = now() where watcher = 'failed_runs' and signature = 'cron_stale:' || v_stale.jobname;
  end loop;

  if v_rehearsal > 0 then
    v_detail := v_detail || E'\n' || v_rehearsal || ' further run(s) failed inside a declared sandbox rehearsal window and were not paged.' || E'\n';
  end if;

  if v_alerts > 0 then
    -- cred_db_internal, NOT the legacy shared inbound_secret. Rebuilding this function from its
    -- 26 Jul migration text carried the old shared-secret read back in with it, and
    -- schema_dump_not_replayable caught it: the live definition had already been migrated by
    -- audit 9.5 / WI-001 and the file I rebuilt from predated that. Same credential
    -- fn_resilience_watch uses to reach alert_founder. A guard refusing your own code is the
    -- guard working.
    select value into v_secret from app_secrets where key = 'cred_db_internal';
    perform net.http_post(
      url := v_url,
      headers := '{"Content-Type":"application/json"}'::jsonb,
      body := jsonb_build_object(
        '__secret', v_secret,
        'event', 'Scheduled runs failed (' || v_alerts || ' new condition(s))',
        'detail', v_detail,
        'level', 'error',
        -- Dedupe on the day, not the hour. The hour made the key change every pass, which is why
        -- a dedupe key existed for three weeks and never deduplicated anything.
        'dedupe_key', 'failed_runs:' || to_char(now(),'YYYY-MM-DD')
      ),
      timeout_milliseconds := 20000
    );
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
$fn$;
