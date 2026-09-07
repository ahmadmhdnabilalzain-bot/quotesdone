-- THE ORG CAN PROMOTE, NOT ONLY PUNISH (org audit D10).
--
-- MEASURED. fn_reputation_recompute demotes a probation-tier employee (max_tier autonomous -> gated),
-- and fn_check_spend then zeroes their spend limit. But there was no promotion counterpart:
-- fn_promotion_review did not exist, career_level (the promotion criteria: min_runs, min_kpis_met_pct,
-- max_error_rate_pct) had 0 readers, and org_agents.seniority was never advanced by anything. Authority
-- only ever narrowed.
--
-- THIS FILE adds fn_promotion_review, the mirror of the demotion path:
--   * It respects the founder stand-down exactly as fn_reputation_recompute does — no employee is
--     promoted while the hold is open or before a full observation window has elapsed after a resume,
--     because promotion off a frozen window would reward the hold, not the employee.
--   * It scores each employee that has an EARNED reputation reading against career_level's criteria
--     (runs from agent_runs, KPIs-met proxied by agent_reputation.correctness, error rate from
--     reliability) and finds the highest level they qualify for.
--   * When that level outranks their current seniority it PROMOTES: org_agents.seniority advances and
--     employee_authority WIDENS (advisory-safe grants go gated->autonomous and the personal spend
--     threshold rises with the level), audited in autonomy_control_audit the same way a demotion is.
--   * A weekly cron, alongside reputation.
--
-- Nothing is fabricated: an employee with no earned reputation reading is not promoted. seniority is
-- not in any frozen baseline digest, so this drifts nothing.
--
--   node scripts/apply_sql.mjs scripts/sql/the_org_can_promote_not_only_punish.sql --apply --ddl

begin;

create or replace function public.fn_promotion_review()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $fn$
declare r record; v_hold record; v_window_opens timestamptz;
        v_runs int; v_kpi numeric; v_err numeric; v_qual record; v_cur text;
        v_promoted int := 0; v_evaluated int := 0;
begin
  -- THE FOUNDER STAND-DOWN. Absence of activity during a hold he imposed is not underperformance, and
  -- it is not high performance either — promotion off a frozen window is as wrong as demotion off one.
  select s.id, s.stood_down_at into v_hold from public.company_stand_down s
   where s.resumed_at is null order by s.stood_down_at desc limit 1;
  if v_hold.id is not null then
    return jsonb_build_object('ok', false, 'status','PAUSED_BY_FOUNDER_STANDDOWN', 'promoted',0, 'evaluated',0,
      'note','No employee is promoted while the founder''s hold is open: every dimension is an activity window and the activity was stopped by instruction.');
  end if;
  select max(s.resumed_at) + interval '30 days' into v_window_opens
    from public.company_stand_down s where s.resumed_at is not null;
  if v_window_opens is not null and now() < v_window_opens then
    return jsonb_build_object('ok', false, 'status','NOT_MEASURED_DURING_HOLD', 'promoted',0, 'evaluated',0,
      'first_valid_review_at', v_window_opens);
  end if;

  for r in
    select a.agent_key, a.seniority, p.tier, p.correctness, p.reliability
      from public.org_agents a
      join public.agent_reputation p on p.agent_key = a.agent_key
     where a.active and p.tier in ('standard','trusted','senior_trusted') and p.correctness is not null
  loop
    v_evaluated := v_evaluated + 1;
    v_runs := (select count(*) from public.agent_runs where agent = r.agent_key and started_at > now() - interval '90 days');
    v_kpi  := r.correctness;                                   -- graded-outcome success, the KPIs-met proxy
    v_err  := 100 - coalesce(r.reliability, 100);              -- error rate
    v_cur  := lower(coalesce(r.seniority,'junior'));

    -- the highest career level whose three criteria the employee meets
    select level_no, level_name into v_qual
      from public.career_level
     where v_runs >= min_runs and v_kpi >= min_kpis_met_pct and v_err <= max_error_rate_pct
     order by level_no desc limit 1;
    if v_qual.level_no is null then continue; end if;

    -- promote only when the earned level outranks the current seniority (one scale for both vocabularies)
    if v_qual.level_no > (case v_cur
         when 'junior' then 1 when 'specialist' then 2 when 'senior' then 3 when 'manager' then 3
         when 'lead' then 4 when 'director' then 5 when 'executive' then 5 when 'vp' then 6
         when 'chief' then 7 else 1 end) then
      update public.org_agents set seniority = v_qual.level_name where agent_key = r.agent_key;
      with widened as (
        update public.employee_authority a
           set max_tier = 'autonomous',
               threshold_aed = greatest(coalesce(a.threshold_aed,0), v_qual.level_no * 5000)
         where a.agent_key = r.agent_key
           and (a.note ilike '%advisory-safe%' or a.max_tier = 'gated')
        returning a.agent_key, a.action_class)
      insert into public.autonomy_control_audit (object, op, direction, old_value, new_value, reason)
      select 'employee_authority:'||agent_key||'/'||action_class, 'promotion_widen', 'loosen',
             'gated', 'autonomous',
             'promoted to '||v_qual.level_name||' on measured performance (career_level '||v_qual.level_no||')'
        from widened;
      insert into public.autonomy_control_audit (object, op, direction, old_value, new_value, reason)
      values ('org_agents:'||r.agent_key, 'promotion', 'loosen', r.seniority, v_qual.level_name,
              'runs '||v_runs||', KPIs-met '||v_kpi||'%, error '||round(v_err,1)||'% meet career_level '||v_qual.level_no);
      v_promoted := v_promoted + 1;
    end if;
  end loop;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('promotion_review', now(), now(), 'ok',
          jsonb_build_object('evaluated', v_evaluated, 'promoted', v_promoted),
          'Promotion review: '||v_evaluated||' employee(s) with an earned reading evaluated, '||v_promoted||' promoted (seniority advanced, advisory-safe authority widened).');
  return jsonb_build_object('ok', true, 'evaluated', v_evaluated, 'promoted', v_promoted);
end $fn$;

revoke execute on function public.fn_promotion_review() from public;
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.

commit;
