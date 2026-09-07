-- THE SCORER WOULD HAVE READ A FOUNDER-IMPOSED SILENCE AS UNDERPERFORMANCE.
--
-- NO TRANSACTION CONTROL. One CREATE OR REPLACE, one new read-only board, one assertion block.
-- fn_reputation_recompute is not a frozen Phase C subject (public.phase_c_frozen_subject lists 25
-- objects and it is not among them), so no PCCR amendment is raised by this file.
--
-- ================================================================================================
-- WHAT WAS ABOUT TO HAPPEN
-- ================================================================================================
--
-- public.agent_reputation holds 93 rows, every one computed 2026-08-12 13:45:16.723325+00. The
-- founder stood the workforce down four days later, 2026-08-16 06:10:19.732174+00, in his own
-- words: "no one should have a single task now until we fix the workflow and chain of command",
-- then "hold the automation ... and wait for my workflow". 183 of 206 cron jobs are paused; the 23
-- that are active are backups, uptime probes and governance monitors.
--
-- Every dimension fn_reputation_recompute reads is an ACTIVITY WINDOW ending at now():
--
--   correctness      outcome_record verdicts
--   reliability      agent_runs, started_at > now() - 30 days
--   cost efficiency  ai_cost_log, occurred_at > now() - 30 days
--   collaboration    review_chain decisions
--
-- Eleven days into a hold those windows are empty by instruction. The routine does not treat an
-- empty window as "no reading" on every dimension at once -- that path is the `unmeasured` tier and
-- it deliberately changes no authority -- but a PARTIAL reading is scored, and a partial reading
-- built from a stopped company scores low. Below 50 is `probation`, and twenty lines further down
-- probation writes:
--
--     update employee_authority a set max_tier = 'gated' ... where p.tier = 'probation'
--
-- That is a real loss of authority, caused by the clock moving rather than by anything anyone did.
-- The scorer is not resumed to prove it and the snapshot is not recomputed to make a board green;
-- the routine is taught that a founder-imposed silence is not a measurement.
--
-- THE SNAPSHOT IS NOT DELETED AND NOT HIDDEN. It remains readable and remains the basis of every
-- tier in use -- fn_check_spend, fn_org_task_assign and fn_pick_reviewer all read
-- agent_reputation.tier. fn_reputation_hold_state() is what states out loud that it is stale, since
-- when, and why, so a reader is not left to infer freshness from a timestamp.
--
-- reputation_weekly (cron 161) and outcome_evaluate_daily (cron 143) both remain INACTIVE. This
-- file does not activate anything.
--
-- ================================================================================================

CREATE OR REPLACE FUNCTION public.fn_reputation_recompute()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int := 0; v_score numeric; v_tier text;
  v_corr numeric; v_rel numeric; v_cost numeric; v_learn numeric; v_collab numeric;
  v_gated int := 0; v_restored int := 0; v_unmeasured int := 0;
  v_hold record; v_window_opens timestamptz;
begin
  -- ---- THE FOUNDER STAND-DOWN, 27 AUG 2026 -----------------------------------------------------
  -- ABSENCE OF ACTIVITY DURING A HOLD HE IMPOSED IS NOT UNDERPERFORMANCE.
  --
  -- Every dimension below reads a window ending at now(): outcome_record verdicts, agent_runs over
  -- 30 days, ai_cost_log over 30 days, review_chain decisions. The founder stood the workforce down
  -- on 2026-08-16 06:10:19.732174+00 ("no one should have a single task now until we fix the
  -- workflow and chain of command") and every work-creating cron job has been paused since. Running
  -- this routine against that window does not measure employees; it measures the hold. It would
  -- read four employees down to probation and, twenty lines further down, write
  -- employee_authority.max_tier = 'gated' for each of them -- a real loss of authority caused by the
  -- clock moving, not by anything anyone did.
  --
  -- So the scorer PAUSES rather than scoring. It does not return ok:true, it does not touch
  -- agent_reputation, and it does not touch employee_authority. The last valid snapshot
  -- (2026-08-12 13:45:16.723325+00, 93 employees) stays exactly where it is and stays readable;
  -- fn_reputation_hold_state() is what says out loud that it is stale and why.
  select s.id, s.stood_down_at, s.resumed_at into v_hold
    from public.company_stand_down s
   where s.resumed_at is null
   order by s.stood_down_at desc limit 1;
  if v_hold.id is not null then
    return jsonb_build_object(
      'ok', false,
      'status', 'PAUSED_BY_FOUNDER_STANDDOWN',
      'scored', 0, 'gated', 0, 'restored', 0, 'unmeasured', 0,
      'stand_down_id', v_hold.id,
      'observation_window_frozen_at', v_hold.stood_down_at,
      'last_valid_snapshot_at', (select max(computed_at) from public.agent_reputation),
      'note', 'The observation window is frozen at the stand-down. No employee is scored, promoted '
           || 'or demoted while the founder''s hold is open, because every dimension this routine '
           || 'reads is an activity window and the activity was stopped by instruction. This is not '
           || 'a PASS and it is not a performance regression.');
  end if;

  -- ---- A COMPLETE NEW OBSERVATION WINDOW AFTER THE HOLD LIFTS -----------------------------------
  -- Resuming is not enough. The dimensions read 30 days back, so a recompute on the day the hold
  -- lifts would still be reading the held period and would still penalise it retroactively. The
  -- first score after a resume is taken only once a full 30-day window has elapsed ENTIRELY after
  -- the resume.
  select max(s.resumed_at) + interval '30 days' into v_window_opens
    from public.company_stand_down s where s.resumed_at is not null;
  if v_window_opens is not null and now() < v_window_opens then
    return jsonb_build_object(
      'ok', false,
      'status', 'NOT_MEASURED_DURING_HOLD',
      'scored', 0, 'gated', 0, 'restored', 0, 'unmeasured', 0,
      'first_valid_recompute_at', v_window_opens,
      'note', 'The hold has lifted but the 30-day windows this routine reads still overlap it. '
           || 'Scoring now would carry the held period into the score. The first recompute after a '
           || 'resume waits for a complete new observation window.');
  end if;
  for r in select agent_key from org_agents where active loop
    -- correctness: graded improvements that moved the metric the right way
    select coalesce(round(100.0*count(*) filter (where verdict='improved')
             /nullif(count(*) filter (where verdict in ('improved','no_change','worse')),0),1), null)
      into v_corr from outcome_record where actor = r.agent_key;
    -- reliability: runs that did not error.
    -- NOTE (10 Aug 2026): for EMPLOYEES this is the wrong table - agent_runs is the cron log and
    -- only nine of its 111 agent values are org_agents keys. Left alone deliberately: every value
    -- present is >= 93, so it only ever raises a score. Do not "fix" it into something that starts
    -- lowering scores without first deciding what employee reliability means.
    select coalesce(round(100.0*count(*) filter (where status<>'error')/nullif(count(*),0),1), null)
      into v_rel from agent_runs where agent = r.agent_key and started_at > now()-interval '30 days';
    -- cost efficiency: share of calls a cheaper model could NOT have served
    select coalesce(round(100.0*count(*) filter (where not coalesce(could_be_cheaper,false))/nullif(count(*),0),1), null)
      into v_cost from ai_cost_log where agent_key = r.agent_key and occurred_at > now()-interval '30 days';

    -- learning speed: UNMEASURABLE, so NULL for everyone. See the header of the 10 Aug change.
    v_learn := null;

    -- collaboration: reviews it took part in that reached approval, over DECIDED VERDICTS ONLY.
    select coalesce(round(100.0*count(*) filter (where decision='approve')/nullif(count(*),0),1), null)
      into v_collab from review_chain
     where (author_agent = r.agent_key or reviewer_agent = r.agent_key)
       and decision in ('approve','reject','request_revision');

    -- ABSENCE OF EVIDENCE IS NOT A SCORE OF 50 (12 Aug 2026). See the header: coalesce(...,50) put
    -- 75 employees who have never executed anything at 51.0, one point above probation and
    -- indistinguishable from a real 50. An employee with no reading on any dimension is now
    -- 'unmeasured' with score NULL, because a score is a measurement and we have not made one.
    if v_corr is null and v_rel is null and v_cost is null and v_learn is null and v_collab is null then
      v_score := null;
      v_tier  := 'unmeasured';
      v_unmeasured := v_unmeasured + 1;
    else
      v_score := round((coalesce(v_corr,50)*0.30 + coalesce(v_rel,50)*0.30 + coalesce(v_cost,50)*0.15
                      + coalesce(v_learn,50)*0.15 + coalesce(v_collab,50)*0.10), 1);
      v_tier := case when v_score >= 85 then 'senior_trusted'
                     when v_score >= 70 then 'trusted'
                     when v_score >= 50 then 'standard' else 'probation' end;
    end if;

    insert into agent_reputation (agent_key,correctness,reliability,cost_efficiency,learning_speed,collaboration,score,tier,computed_at)
    values (r.agent_key,v_corr,v_rel,v_cost,v_learn,v_collab,v_score,v_tier,now())
    on conflict (agent_key) do update set correctness=excluded.correctness, reliability=excluded.reliability,
      cost_efficiency=excluded.cost_efficiency, learning_speed=excluded.learning_speed,
      collaboration=excluded.collaboration, score=excluded.score, tier=excluded.tier, computed_at=now();
    n := n + 1;
  end loop;

  -- probation is a real consequence: any agent below the floor loses autonomous authority.
  -- 'unmeasured' deliberately does NOT trigger this - see the header. No authority is revoked by
  -- introducing the tier.
  with demoted as (
    update employee_authority a set max_tier='gated'
      from agent_reputation p
     where p.agent_key=a.agent_key and p.tier='probation' and a.max_tier='autonomous'
    returning a.agent_key, a.action_class)
  insert into autonomy_control_audit (object, op, direction, old_value, new_value, reason)
  select 'employee_authority:'||agent_key||'/'||action_class, 'reputation_demote', 'tighten',
         'autonomous', 'gated', 'reputation tier fell to probation'
    from demoted;
  get diagnostics v_gated = row_count;

  -- ...and recovery is a real consequence too. NARROWED 12 Aug 2026: this read `tier <> 'probation'`,
  -- which an employee that has never executed anything satisfied - so "never worked" was being
  -- treated as "recovered" and handed back autonomous authority. Recovery now requires a tier that
  -- was actually earned from a reading.
  with restored as (
    update employee_authority a set max_tier='autonomous'
      from agent_reputation p
     where p.agent_key=a.agent_key
       and a.max_tier='gated'
       and p.tier in ('standard','trusted','senior_trusted')
       and a.note = 'Advisory-safe action, may run autonomously'
    returning a.agent_key, a.action_class)
  insert into autonomy_control_audit (object, op, direction, old_value, new_value, reason)
  select 'employee_authority:'||agent_key||'/'||action_class, 'reputation_restore', 'loosen',
         'gated', 'autonomous',
         'reputation recovered above probation and the grant note records the action as advisory-safe'
    from restored;
  get diagnostics v_restored = row_count;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('reputation',now(),now(),'ok',
    jsonb_build_object('scored',n,'gated',v_gated,'restored',v_restored,'unmeasured',v_unmeasured),
    'Reputation recomputed for '||n||' employee(s), of which '||v_unmeasured||' have no reading on '
    ||'any dimension and are recorded as unmeasured with a NULL score rather than a default 50. '
    ||'Probation demotes autonomous authority to gated ('||v_gated||' this run); recovery restores '
    ||'advisory-safe grants ('||v_restored||' this run) and no longer counts unmeasured as recovered.');
  return jsonb_build_object('scored',n,'gated',v_gated,'restored',v_restored,'unmeasured',v_unmeasured);
end
$function$
;

-- ---- THE BOARD THAT SAYS WHAT THE SNAPSHOT IS WORTH ----------------------------------------------
-- ROUTINE REMOVED 7 September 2026. public.fn_reputation_hold_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke execute on function public.fn_reputation_hold_state() from public;
revoke execute on function public.fn_reputation_hold_state() from anon;

-- ---- THE ASSERTIONS ------------------------------------------------------------------------------
do $assert$
declare v jsonb; v_before int; v_after int; v_auth_before int; v_auth_after int; v_red int; v_stamp timestamptz;
begin
  select count(*), max(computed_at) into v_before, v_stamp from public.agent_reputation;
  select count(*) into v_auth_before from public.employee_authority where max_tier = 'gated';

  -- FORCE THE GUARD TO FIRE. A branch that returns zero because the system is idle proves nothing;
  -- this calls the routine for real, with the hold open, and asserts on what came back and on what
  -- did NOT change.
  v := public.fn_reputation_recompute();

  select count(*) into v_after from public.agent_reputation;
  select count(*) into v_auth_after from public.employee_authority where max_tier = 'gated';

  if v->>'status' not in ('PAUSED_BY_FOUNDER_STANDDOWN','NOT_MEASURED_DURING_HOLD') then
    raise exception 'the scorer did not pause while a stand-down is open: %', v::text;
  end if;
  if (v->>'ok')::boolean then
    raise exception 'the scorer reported ok:true while paused; a pause is not a pass: %', v::text;
  end if;
  if v_after <> v_before then
    raise exception 'agent_reputation moved from % to % during a paused recompute', v_before, v_after;
  end if;
  if v_stamp is distinct from (select max(computed_at) from public.agent_reputation) then
    raise exception 'the snapshot timestamp moved during a paused recompute';
  end if;
  if v_auth_after <> v_auth_before then
    raise exception 'employee_authority gated count moved from % to % during a paused recompute', v_auth_before, v_auth_after;
  end if;

  select count(*) into v_red from public.fn_reputation_hold_state() where not ok;
  if v_red <> 0 then
    raise exception 'fn_reputation_hold_state is red on % row(s)', v_red;
  end if;

  raise notice 'OK  scorer=% agent_reputation=% (unchanged) gated=% (unchanged)',
    v->>'status', v_after, v_auth_after;
end
$assert$;
