-- SPEC FILE #3 s32 — the sixth reputation axis had nowhere to be written.
--
-- The spec names six dimensions an AI employee earns reputation on: correctness, DECISION QUALITY,
-- learning speed, cost efficiency, collaboration and reliability. agent_reputation carried five of
-- them. Measured:
--   select string_agg(column_name, ', ') from information_schema.columns
--    where table_schema='public' and table_name='agent_reputation';
--   -- agent_key, collaboration, computed_at, correctness, cost_efficiency, learning_speed,
--   -- reliability, score, tier
-- No decision-quality column, so the axis could not be absent-with-a-null; it could not exist at all.
--
-- WHAT IT IS ALLOWED TO MEAN HERE. correctness already reads outcome_record verdicts, which is the
-- OUTCOME of a decision. Decision quality is measured as the quality of the decision AS TAKEN: of an
-- employee's decision_log rows in the window, the share that carry a stated confidence, at least one
-- source and at least one reason. A decision recorded with no confidence, no source and no reason
-- may still turn out well; it is not a decision anyone can review, and reviewability is the part of
-- quality that is knowable at the moment it is made. Verified against production before shipping,
-- with the routine's own window: it ('it', 363 decisions) scores 8.3, ops_director 6.3,
-- supplier_verification 0.0 over 138 — a discriminating measure, not a constant.
--
-- IT IS DELIBERATELY NOT IN THE WEIGHTED SCORE. Almost every employee scores near zero on it today,
-- and the reason is that the action gate records a confidence on a small fraction of the rows it
-- writes. That is a property of the gate, not of the employee, and folding it into `score` at any
-- weight would demote people for the gate's recording habit the first time this runs after the hold
-- lifts — the same defect the reliability comment in this routine already warns about. So the axis
-- is measured and stored and reported, and the weights stay as they were. Giving it a weight is a
-- management decision to take once confidence is recorded on more than a fraction of decisions.
--
-- THIS DOES NOT TURN s32-reputation-six-dimensions GREEN AND IS NOT MEANT TO. The check requires the
-- axis to be non-null on EVERY graded employee, which needs a recompute, and this routine refuses to
-- recompute while the founder's stand-down is open — correctly. The column and the computation are
-- what was missing; the reading has to wait for the hold, and saying so is the honest position.

alter table public.agent_reputation add column if not exists decision_quality numeric;

comment on column public.agent_reputation.decision_quality is
  'Spec #3 s32, sixth axis. Share of this employee''s decision_log rows in the observation window '
  'that carry a stated confidence, at least one source and at least one reason — the reviewability '
  'of the decision as taken, as distinct from correctness, which grades the outcome afterwards. '
  'Computed by fn_reputation_recompute. Not folded into score: see the note in that routine.';

CREATE OR REPLACE FUNCTION public.fn_reputation_recompute()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int := 0; v_score numeric; v_tier text;
  v_corr numeric; v_rel numeric; v_cost numeric; v_learn numeric; v_collab numeric; v_decq numeric;
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

    -- DECISION QUALITY (27 Aug 2026, spec #3 s32). The sixth named axis, which had no column until
    -- this migration. Correctness above grades the OUTCOME of a decision from outcome_record; this
    -- grades the decision AS TAKEN: the share of the employee's decisions in the window that a human
    -- could actually review, meaning one that states a confidence, names at least one source and
    -- gives at least one reason. A decision with none of the three may still turn out well and
    -- nobody can tell why. NULL when the employee decided nothing in the window, never 0, because
    -- deciding nothing is not deciding badly.
    select coalesce(round(100.0*count(*) filter (
             where l.confidence is not null
               and l.sources is not null and l.sources::text not in ('null','[]','{}','""')
               and l.reasons  is not null and l.reasons::text  not in ('null','[]','{}','""'))
             /nullif(count(*),0),1), null)
      into v_decq from decision_log l
     where l.actor = r.agent_key and l.created_at > now()-interval '30 days';

    -- collaboration: reviews it took part in that reached approval, over DECIDED VERDICTS ONLY.
    -- ORDER IS LOAD-BEARING: this must be read BEFORE the block below, which uses v_collab both in
    -- the all-null test and in the weighted score. Computing it after would score every employee on
    -- the PREVIOUS employee's collaboration, and the first employee on a null.
    select coalesce(round(100.0*count(*) filter (where decision='approve')/nullif(count(*),0),1), null)
      into v_collab from review_chain
     where (author_agent = r.agent_key or reviewer_agent = r.agent_key)
       and decision in ('approve','reject','request_revision');

    -- ABSENCE OF EVIDENCE IS NOT A SCORE OF 50 (12 Aug 2026). See the header: coalesce(...,50) put
    -- 75 employees who have never executed anything at 51.0, one point above probation and
    -- indistinguishable from a real 50. An employee with no reading on any dimension is now
    -- 'unmeasured' with score NULL, because a score is a measurement and we have not made one.
    -- decision_quality counts toward "has this employee any reading at all", because it is a
    -- reading; it does NOT count toward the weighted score. See the next comment.
    if v_corr is null and v_rel is null and v_cost is null and v_learn is null and v_collab is null
       and v_decq is null then
      v_score := null;
      v_tier  := 'unmeasured';
      v_unmeasured := v_unmeasured + 1;
    else
      -- DECISION QUALITY IS NOT WEIGHTED HERE, DELIBERATELY. Measured on production before this
      -- change shipped, almost every employee scores near zero on it, and the reason is that the
      -- action gate records a confidence on a small fraction of the rows it writes -- a property of
      -- the gate, not of the employee. Giving it any weight would demote people for the gate's
      -- recording habit on the first run after the hold lifts, which is exactly the failure the
      -- reliability note above warns against. The axis is measured, stored and readable; adding it
      -- to the weights is a management decision to take once confidence is recorded on more than a
      -- fraction of decisions.
      v_score := round((coalesce(v_corr,50)*0.30 + coalesce(v_rel,50)*0.30 + coalesce(v_cost,50)*0.15
                      + coalesce(v_learn,50)*0.15 + coalesce(v_collab,50)*0.10), 1);
      v_tier := case when v_score >= 85 then 'senior_trusted'
                     when v_score >= 70 then 'trusted'
                     when v_score >= 50 then 'standard' else 'probation' end;
    end if;

    insert into agent_reputation (agent_key,correctness,reliability,cost_efficiency,learning_speed,collaboration,decision_quality,score,tier,computed_at)
    values (r.agent_key,v_corr,v_rel,v_cost,v_learn,v_collab,v_decq,v_score,v_tier,now())
    on conflict (agent_key) do update set correctness=excluded.correctness, reliability=excluded.reliability,
      cost_efficiency=excluded.cost_efficiency, learning_speed=excluded.learning_speed,
      collaboration=excluded.collaboration, decision_quality=excluded.decision_quality,
      score=excluded.score, tier=excluded.tier, computed_at=now();
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
    ||'advisory-safe grants ('||v_restored||' this run) and no longer counts unmeasured as recovered. '
    ||'Decision quality is measured and stored on every employee and is not weighted into score.');
  return jsonb_build_object('scored',n,'gated',v_gated,'restored',v_restored,'unmeasured',v_unmeasured);
end
$function$;
