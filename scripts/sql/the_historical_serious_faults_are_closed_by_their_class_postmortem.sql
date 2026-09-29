-- THE HISTORICAL SERIOUS FAULTS ARE CLOSED BY THEIR CLASS POSTMORTEM, AND A FINDING OPEN MORE THAN A DAY
-- IS CHASED WITH THE SEAT THAT OWNS IT.
--
-- Seat: it_engineer. 28 Sep 2026. Needs every_serious_incident_gets_a_postmortem.sql (duty it_engineer.postmortem),
-- every_new_bug_leaves_a_playbook_entry_a_check_and_an_incident_record.sql (it_incident, fn_it_incident_open) and
-- the_it_engineer_closes_every_loop_it_opens.sql (fn_seat_handoff, the it.finding conversation).
--
-- WHAT WAS MEASURED (production htdblwldjkcgjvmqkbeh, 28 Sep 2026 ~13:40 UTC, read-only):
--   * Closed it.finding handoffs of severity critical/high with no it_incident row, id <= 101627: 563 (24 critical),
--     in 30 classes (first two segments of the issue key). fn_it_engineer_postmortem() calls this number
--     historical_without_postmortem and deliberately does not back-fill it (no model spend on closed faults).
--   * There is NO postmortem table. public.it_incident is the postmortem record (cause, fix, regression_check).
--   * docs/it/postmortems/ now holds one blameless postmortem per class for 11 issue-key families covering 532 of
--     the 563; docs/it/postmortems/INDEX.md maps all 30 classes to their count and carries the query.
--   * it_engineer_finding open: 33; open more than 24 hours: 30. Every one of the 30 already has an it.finding
--     handoff that is PENDING at its owning seat; fn_it_handoff_sla_items reports them to the CEO only, grouped per
--     seat ("21 it.finding handoff(s) to ceo were answered more than 24 hours ago ..."). Nothing goes back to the
--     OWNING seat once its first reply is on the row.
--
-- WHAT THIS CHANGES
--   1. Backlog closed by class (one-off data, idempotent): every handoff in a covered class, id <= 101627, gets its
--      it_incident row (fn_it_incident_open) with the class's root cause, fix and regression check, and recorded_by
--      naming the postmortem file. The 31 handoffs in the 19 uncovered classes are NOT touched and stay in
--      historical_without_postmortem, so the number that remains is the true remainder.
--   2. seat_duty it_engineer.finding_chase (1 hour), fn_it_engineer_finding_chase(): for each open, non-demo
--      finding older than 24 hours, one it.finding handoff a day to the seat that owns it (the seat of the
--      finding's latest it.finding handoff; with none, the normal loop is opened by fn_it_loop_open). The chase
--      carries chase=true, age_hours and the original handoff id. It carries NO 'severity' (its finding_severity
--      is informational), so fn_it_engineer_postmortem never opens a second incident for the same occurrence, and it
--      carries 'escalated_report_id' copied from the original so fn_it_loop_reverify does not report the same
--      occurrence to the CEO a second time: the CEO already has it; the chase is to the owner.
--      duty:handoff_sla:* findings are excluded: they are themselves the chase of other handoffs.
--      Read-only dry count, 28 Sep 2026: part 1 selects 532 handoffs; part 2 would chase 17 of the 30 findings
--      open more than 24 hours (the other 13 are duty:handoff_sla:*). The first run sends at most 40.
--
-- WHAT THIS DOES NOT CHANGE: fn_it_engineer_postmortem, fn_it_loop_reverify, fn_it_handoff_sla_items and the
-- it.finding answering routine are untouched. The chase does not fix anything: for most classes the owning seat's
-- answer is "no deterministic remedy" (fn_seat_answers_it_finding); what it adds is that the owner is asked again,
-- every day, on the record, instead of the finding ageing silently in a CEO-level count.
--
-- PENDING: committed, not applied. Apply: node scripts/apply_sql.mjs scripts/sql/the_historical_serious_faults_are_closed_by_their_class_postmortem.sql --apply --ddl

-- ── 1. THE BACKLOG, CLOSED BY CLASS ──────────────────────────────────────────────────────────────
do $backlog$
declare c record; v_inc bigint;
begin
  for c in
    with cls(family, doc, cause, fix, regression_check) as (values
      ('duty:heartbeat', 'docs/it/postmortems/2026-09-15_duty_heartbeat.md',
       'A resilience_ping step did not fit the shared tick budget: fn_it_detect took 10,999 ms against the 8 s statement timeout and starved later steps; steps ran in list order; orphans.wa_templates_watch answers HTTP 403 (cause not determined).',
       '1de84e3 (#767) bounded detector; b0357f0 (#754) stalest step first; 5afd873 (#810) a carried step is held; 1c0abad (#948) exam in slices.',
       'supabase/functions/resilience_ping/steps.test.ts; scripts/checks/it_engineer_loop_is_closed.test.mjs section 2; duty it_engineer.heartbeat'),
      ('duty:smoke', 'docs/it/postmortems/2026-09-14_duty_smoke.md',
       'Customer overview data settled in about 3,031 ms (six portal reads queued behind the client bundle); one failed run fans out into one finding per downstream step; fixture setup/teardown failures (cause not determined).',
       '0df19fc (#663), 670a222/d9af10e (#671), 6e5ea2b latency budget duty, 0e34dab. No front-end latency fix identified in git.',
       'duty it_engineer.smoke re-asserts after every deploy to main; scripts/sql/the_it_engineer_holds_the_portals_to_their_latency_budget.sql'),
      ('duty:demo', 'docs/it/postmortems/2026-09-14_duty_demo.md',
       'A run opened a rehearsal_window (or wrote demo rows) and exited without closing it; each key is one abandoned run.',
       'aa96d9c: the answering routine closes an abandoned window; ce156db/cec2d4c (#683). The leak in the runners is not fixed.',
       'duty it_engineer.demo; fn_seat_answers_it_finding closes the window'),
      ('duty:delivery', 'docs/it/postmortems/2026-09-15_duty_delivery.md',
       'send_whatsapp did not store the provider message id, so the delivery watch could not confirm an outcome (measured 18-21 Sep); the 15 Sep requests were not re-measured.',
       '1de84e3 (#767) provider id stored and a CEO decider; dc09a9f delivery outcomes recorded; df4cfcb (#832).',
       'scripts/checks/it_failures_of_18_to_21_september_do_not_recur.test.mjs; the delivery duty'),
      ('duty:journey', 'docs/it/postmortems/2026-09-14_duty_journey.md',
       'One nightly run on 18 Sep failed its crawl across every customer page (transient, closed next run) plus the overview latency; one Stripe test checkout did not return (not diagnosed).',
       '1bfbcf2, 368841e (#728), 582f52a, de0199c (#847), 4c96db8 (#957).',
       'duty it_engineer.journey re-asserts every step nightly'),
      ('watch:run_failure', 'docs/it/postmortems/2026-09-14_watch_run_failure.md',
       'ai_gateway: the founder''s OpenRouter hold (HTTP 503 circuit_open) logged as error; the other single-hour bursts left no cause on the record.',
       '9744feb (#785): a run the founder''s hold refused is held, not failed.',
       'fn_it_detect run_failure arm; scripts/sql/a_run_the_founders_hold_refused_is_held_not_failed.sql'),
      ('duty:unsigned_revision', 'docs/it/postmortems/2026-09-14_duty_unsigned_routine_change.md',
       'Apply-then-merge: SQL applied from a branch commit that a later rebase removed, so the applied revision was on no branch GitHub could find.',
       'c4e73c8 (#824) a revision off main settles once its routines are re-applied or accepted; 3b30e6a (#838) an apply from an open PR waits for its merge.',
       'duty it_engineer.unsigned_revision (fn_it_change_watch)'),
      ('duty:unsigned_change', 'docs/it/postmortems/2026-09-14_duty_unsigned_routine_change.md',
       'Routines changed by mgmt-api as postgres outside the reviewed path (18 Sep 07:31Z).',
       'Every routine touched was re-applied from a reviewed revision (close note); 0b0482b the duty.',
       'duty it_engineer.unsigned_change (fn_it_change_watch)'),
      ('watch:run_silent', 'docs/it/postmortems/2026-09-15_watch_run_silent.md',
       'send_whatsapp ran only when something was queued, and the run_silent arm judged the idle function by its own rhythm; conversation_archive and wa_status not determined.',
       '1de84e3 (#767): resilience_ping calls send_whatsapp every tick.',
       'scripts/checks/it_failures_of_18_to_21_september_do_not_recur.test.mjs section 5'),
      ('monitor:detect_tick_blind', 'docs/it/postmortems/2026-09-18_monitor_detect_tick_blind.md',
       'fn_it_detect took 10,999 ms against the 8 s statement timeout after backfills wrote about 6,000 agent_runs rows an hour; no tick persisted for about 50 hours.',
       '1de84e3 (#767) bounded detector and liveness reads the scheduler; 247231d (#752).',
       'scripts/checks/it_engineer_loop_is_closed.test.mjs section 2 (20,000-row flood under 6,000 ms)'),
      ('duty:security', 'docs/it/postmortems/2026-09-23_duty_security.md',
       'CREATE FUNCTION grants EXECUTE to PUBLIC; fn_task_is_demand(text) was re-created without a revoke from authenticated.',
       'Revoked: authenticated cannot execute it (measured 28 Sep 2026); the revoking commit was not identified.',
       'duty it_engineer.security (authenticated_executable_definer)'))
    select a.id handoff_id, cls.*, f.closed_at f_closed, a.decided_at
      from public.agent_actions a
      join cls on split_part(a.detail->>'issue_key', ':', 1) || ':' || split_part(a.detail->>'issue_key', ':', 2) = cls.family
      left join public.it_engineer_finding f on f.issue_key = a.detail->>'issue_key'
     where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'done'
       and a.detail->>'severity' in ('critical', 'high') and a.id <= 101627
       and not exists (select 1 from public.it_incident i where i.handoff_id = a.id)
     order by a.id
  loop
    v_inc := public.fn_it_incident_open(c.handoff_id);
    update public.it_incident
       set cause            = coalesce(nullif(btrim(cause), ''), c.cause),
           fix              = coalesce(nullif(btrim(fix), ''), c.fix),
           regression_check = coalesce(nullif(btrim(regression_check), ''), c.regression_check),
           ended_at         = coalesce(ended_at, c.f_closed, c.decided_at),
           recorded_by      = coalesce(recorded_by, 'it_engineer.postmortem (' || c.doc || ')'),
           updated_at       = now()
     where id = v_inc;
  end loop;
end $backlog$;

-- ── 2. A FINDING OPEN MORE THAN A DAY IS CHASED WITH ITS OWNER ────────────────────────────────────
create or replace function public.fn_it_engineer_finding_chase()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare f public.it_engineer_finding; o public.agent_actions; n_chased int := 0; n_opened int := 0; v_day int; v_id bigint;
        v_seats jsonb := '{}'::jsonb;
begin
  for f in
    select * from public.it_engineer_finding
     where closed_at is null and started_at < now() - interval '24 hours'
       and issue_key not like 'duty:handoff_sla:%'
       and title not ilike '%ZZ DEMO%' and not coalesce((evidence->>'demo')::boolean, false)
     order by started_at limit 40
  loop
    select * into o from public.agent_actions
     where kind = 'handoff' and detail->>'type' = 'it.finding' and detail->>'from' = 'it_engineer'
       and detail->>'issue_key' = f.issue_key and not coalesce((detail->>'chase')::boolean, false)
     order by id desc limit 1;
    if not found then
      perform public.fn_it_loop_open(f.issue_key);   -- no loop yet: open the ordinary one, owner resolved there
      n_opened := n_opened + 1;
      continue;
    end if;
    v_day := floor(extract(epoch from now() - f.started_at) / 86400)::int;
    v_id := public.fn_seat_handoff('it_engineer', o.agent, 'it.finding', 'it_engineer_finding',
      f.issue_key || '@' || floor(extract(epoch from f.started_at))::bigint || '@chase' || v_day,
      jsonb_build_object(
        'issue_key', f.issue_key, 'occurrence_started_at', f.started_at, 'duty', coalesce(o.detail->>'duty', 'fault'),
        'subject', o.detail->>'subject', 'title', 'Open ' || v_day || ' day(s): ' || f.title, 'where_it_is', f.where_it_is,
        'chase', true, 'age_hours', round(extract(epoch from now() - f.started_at) / 3600),
        'original_handoff_id', o.id, 'finding_severity', public.fn_it_engineer_severity(f.blast, f.affected, f.started_at),
        'escalated_report_id', o.detail->'escalated_report_id'));
    n_chased := n_chased + 1;
    v_seats := jsonb_set(v_seats, array[o.agent], to_jsonb(coalesce((v_seats->>o.agent)::int, 0) + 1));
  end loop;
  return jsonb_build_object('chased', n_chased, 'loops_opened', n_opened, 'by_seat', v_seats);
end $fn$;
revoke execute on function public.fn_it_engineer_finding_chase() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_finding_chase() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('it_engineer.finding_chase', 'it_engineer', interval '1 hour', 'fn_it_engineer_finding_chase',
   'Every non-demo finding open more than 24 hours is handed again, once a day, to the seat that owns it.',
   'scripts/sql/the_historical_serious_faults_are_closed_by_their_class_postmortem.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- ── VERDICT ─────────────────────────────────────────────────────────────────────────────────────
select case
  when to_regprocedure('public.fn_it_engineer_finding_chase()') is null then 'PROBE FAILED: the chase routine is missing'
  when not exists (select 1 from public.seat_duty where duty = 'it_engineer.finding_chase') then 'PROBE FAILED: the chase duty is not registered'
  when has_function_privilege('anon', 'public.fn_it_engineer_finding_chase()', 'execute')
    or has_function_privilege('authenticated', 'public.fn_it_engineer_finding_chase()', 'execute') then 'PROBE FAILED: the chase routine is callable by anon/authenticated'
  when (select count(*) from public.it_incident where recorded_by like 'it_engineer.postmortem (docs/it/postmortems/%'
          and (coalesce(btrim(cause), '') = '' or coalesce(btrim(regression_check), '') = '')) > 0 then 'PROBE FAILED: a class incident has no cause or regression check'
  when exists (select 1 from public.agent_actions a
                where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'done' and a.id <= 101627
                  and a.detail->>'severity' in ('critical', 'high')
                  and split_part(a.detail->>'issue_key', ':', 1) || ':' || split_part(a.detail->>'issue_key', ':', 2) in
                      ('duty:heartbeat', 'duty:smoke', 'duty:demo', 'duty:delivery', 'duty:journey', 'watch:run_failure',
                       'duty:unsigned_revision', 'duty:unsigned_change', 'watch:run_silent', 'monitor:detect_tick_blind', 'duty:security')
                  and not exists (select 1 from public.it_incident i where i.handoff_id = a.id)) then 'PROBE FAILED: a covered handoff has no incident'
  else 'PROBE OK' end as verdict;
