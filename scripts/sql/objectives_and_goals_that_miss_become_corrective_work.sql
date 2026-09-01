-- OBJECTIVES AND GOALS THAT MISS BECOME CORRECTIVE WORK (autonomy audit, blocking gap 2).
--
-- MEASURED. fn_kpi_review turns a missed KPI into an org_task, but KPIs serve only ~4 of 63 company
-- goals; the whole objective tier above them self-corrects for nobody. department_objective and
-- goal_period store actual_value against target_value, and 18 department objectives sit below target
-- with a goal_period 'at_risk' backlog — and NOTHING opens corrective work for any of them. Management
-- reacts at the KPI threshold but never steers toward its own objectives, including the AED 1M target.
--
-- THIS FILE adds fn_objective_review, the objective-tier mirror of fn_kpi_review: for every active
-- department_objective below target and every goal_period at risk / below target, it opens ONE
-- idempotent (title-keyed) corrective org_task tied to the objective. It SELF-PAUSES on the founder
-- stand-down exactly like fn_outcome_evaluate, because it opens corrective work. The re-measure is the
-- loop itself: while the objective stays below target the task stays open; when it recovers no new task
-- is opened. (Formal outcome grading of an objective needs a KPI-linked measure — deferred to the
-- objective-scoring upgrade; opening an unmeasurable outcome_record here would only add noise.)
--
-- The weekly cron is scheduled DISABLED and registered as a committed-scenario cron, so it is
-- enable-ready the moment the founder lifts the stand-down without reddening the kernel gate. Higher =
-- better is assumed; objectives whose unit implies a ceiling (cost/max) are excluded so a within-budget
-- figure is never mistaken for a miss. CREATE OR REPLACE preserves the ACL; the new function is revoked
-- from PUBLIC below because it is freshly created.
--
--   node scripts/apply_sql.mjs scripts/sql/objectives_and_goals_that_miss_become_corrective_work.sql --apply --ddl

begin;

CREATE OR REPLACE FUNCTION public.fn_objective_review()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_opened int:=0; v_missed int:=0; v_title text; v_task bigint; v_detail text;
begin
  -- THE FOUNDER STAND-DOWN. This opens corrective work, so it pauses with the workforce exactly as
  -- fn_outcome_evaluate, fn_reputation_recompute and fn_promotion_review do.
  if exists (select 1 from public.company_stand_down where resumed_at is null) then
    return jsonb_build_object('ok', false, 'status','PAUSED_BY_FOUNDER_STANDDOWN', 'opened',0, 'missed',0,
      'note','Objective review opens corrective work and pauses with the founder hold; it resumes when the hold lifts.');
  end if;

  for r in
    -- department objectives below target (higher = better; a ceiling unit is not a miss)
    select 'department_objective' as kind, o.id, o.dept_key, o.objective as label, o.target_value, o.actual_value,
           o.unit, o.goal_key
      from public.department_objective o
     where o.active and o.status='active'
       and o.target_value is not null and o.actual_value is not null
       and o.actual_value < o.target_value
       and coalesce(o.unit,'') not ilike '%max%' and coalesce(o.unit,'') not ilike '%cost%'
    union all
    -- company goal periods flagged at risk, or measured below target
    select 'goal_period' as kind, g.id, g.owner_dept as dept_key, g.goal_key as label, g.target_value, g.actual_value,
           null::text as unit, g.goal_key
      from public.goal_period g
     where g.status = 'at_risk'
        or (g.target_value is not null and g.actual_value is not null and g.actual_value < g.target_value)
  loop
    v_missed := v_missed + 1;
    v_title := 'Objective off-target: '||left(coalesce(r.label, r.goal_key, 'objective'),80)||' ('||r.kind||'#'||r.id||')';
    if exists (select 1 from public.org_tasks where title = v_title and status <> 'done') then continue; end if;

    v_detail := 'Owner dept: '||coalesce(r.dept_key,'exec')||'. Target '||coalesce(r.target_value::text,'?')||' '||coalesce(r.unit,'')
      ||', actual '||coalesce(r.actual_value::text,'?')
      ||case when coalesce(r.target_value,0) > 0
             then ' ('||round(100.0*coalesce(r.actual_value,0)/nullif(r.target_value,0),1)::text||'% of target)' else '' end
      ||case when r.goal_key is not null then '. Serves company goal: '||r.goal_key else '' end
      ||'. Diagnose the cause and either close the gap or propose a revised target with evidence.';

    insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class, objective_id)
    values (coalesce(r.dept_key,'exec'), v_title, v_detail, 'proposed', 'advisory', false, 'recommend',
            case when r.kind='department_objective' then r.id else null end)
    returning id into v_task;
    v_opened := v_opened + 1;
  end loop;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('objective_review', now(), now(), 'ok',
          jsonb_build_object('missed', v_missed, 'opened', v_opened),
          'Objective review: '||v_missed||' objective(s)/goal(s) below target, '||v_opened||' corrective task(s) opened.');
  return jsonb_build_object('missed', v_missed, 'opened', v_opened);
end $function$;

revoke execute on function public.fn_objective_review() from public;

-- Weekly on Monday 05:30 UTC, after the objective/KPI measures settle and before the exec meeting.
-- Scheduled DISABLED: it opens corrective work while the workforce is stood down, and it self-pauses on
-- the hold regardless; the founder enables it on resume. cron.schedule re-activates on re-apply, so the
-- alter_job disable runs last and the committed state is inactive.
select cron.schedule('objective_review_weekly', '30 5 * * 1', $$select public.fn_objective_review();$$);
select cron.alter_job((select jobid from cron.job where jobname='objective_review_weekly'), active := false);
insert into public.cron_registry (jobname, human_name, category, purpose)
values ('objective_review_weekly', 'Review objectives and goals for misses', 'strategy',
  'Weekly: opens an idempotent corrective org_task for every active department_objective below target and every goal_period at risk or below target — the objective-tier mirror of fn_kpi_review. Self-pauses on the founder stand-down. Scheduled disabled until the founder resumes; registered as a committed-scenario cron before it goes active.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

commit;
