-- REPUTATION CHANGES AUTHORITY IN ALL FIVE AUTHORITY ROUTINES, NOT THREE.
--
-- Measured 3 Sep 2026: fn_decide, fn_decision_gate and fn_check_spend consult agent_reputation;
-- fn_dept_authority and fn_task_approve do not. A department's tier came from org_authority and the
-- hard gates alone, and the hourly approver promoted a proposed task to 'assigned' without asking
-- who would do it or how that employee's work has been graded.
--
--   fn_dept_authority  — a department whose measured employees average below the probation line
--                        (score < 50 over employees with a measured tier) is capped from
--                        'autonomous' to 'supervised' for every action class. Unmeasured employees
--                        do not count: absence of evidence is not a penalty. The reply carries the
--                        reputation it read (avg score, measured count, on-probation count) so the
--                        founder sees why a tier was capped.
--   fn_task_approve    — the task's assignee (org_tasks.assigned_agent) or, when none is assigned
--                        yet, the agent that proposed it (decided_by) is looked up in
--                        agent_reputation; a probation tier holds the task for review instead of
--                        approving it, and the review_chain reason names the tier either way.
--
-- Both are deterministic reads of a table the weekly recompute writes; no model, no new tables.
--
--   node scripts/apply_sql.mjs scripts/sql/authority_consults_reputation_in_all_five_routines.sql --apply

create or replace function public.fn_dept_authority(p_dept text, p_action_class text, p_amount_aed numeric default null::numeric)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_catalog'
as $function$
declare
  v jsonb;
  v_tier text;
  v_reason text;
  v_avg numeric; v_measured int; v_probation int;
  v_capped boolean := false;
begin
  v := public.fn_ops_authority_check(p_dept, p_action_class, p_amount_aed, null);
  v_tier := v->>'effective_tier';
  v_reason := v->>'reason';

  -- The department's earned reputation: only employees with a measured tier count.
  select round(avg(r.score), 1), count(*), count(*) filter (where r.tier = 'probation')
    into v_avg, v_measured, v_probation
    from public.agent_reputation r
    join public.org_agents a on a.agent_key = r.agent_key
   where a.active and a.department = p_dept and r.tier <> 'unmeasured' and r.score is not null;

  if v_tier = 'autonomous' and coalesce(v_measured, 0) > 0 and v_avg < 50 then
    v_tier := 'supervised';
    v_capped := true;
    v_reason := format('capped by reputation: %s measured employee(s) in %s average %s, below the '
                       || 'probation line of 50, so autonomous work runs supervised until the '
                       || 'department earns it back (%s)', v_measured, p_dept, v_avg, v_reason);
  end if;

  return jsonb_build_object(
    'dept', p_dept,
    'action_class', p_action_class,
    'tier', v_tier,
    'threshold_aed', (v->>'threshold_aed')::numeric,
    'capped', coalesce(v->>'production_tier', 'gated') is distinct from v_tier,
    'capped_by_reputation', v_capped,
    'reputation', jsonb_build_object('avg_score', v_avg, 'measured', coalesce(v_measured, 0),
                                     'on_probation', coalesce(v_probation, 0)),
    'reviewed', (v->>'reviewed')::boolean,
    'reason', v_reason);
end $function$;

create or replace function public.fn_task_approve(p_dry_run boolean default false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_catalog'
as $function$
declare
  r            record;
  v_auth       jsonb;
  v_granted    text;
  v_ceiling    text;
  v_tier       text;
  v_final      text;
  v_why        text;
  v_reason     text;
  v_decision   text;
  v_authreason text;
  v_rep_key    text;
  v_rep_tier   text;
  v_promoted   int := 0;
  v_held       int := 0;
  v_sample     jsonb := '[]'::jsonb;
  -- Mirrors AUTONOMOUS_CEILING in supabase/functions/dept_plan/index.ts byte for byte.
  c_ceiling constant text[] := array['content_draft','knowledge_fill','recommend','invite',
                                     'analysis','research','seo','monitor','reconcile','outreach_draft'];
begin
  for r in
    select id, dept_key, action_class, tier, coalesce(needs_founder,false) needs_founder,
           coalesce(decided_by,'(unattributed)') decided_by, title, assigned_agent
      from org_tasks
     where status = 'proposed'
     order by id
  loop
    v_auth       := fn_dept_authority(r.dept_key, r.action_class);
    v_authreason := coalesce(v_auth->>'reason', 'no reason given');
    v_granted    := coalesce(nullif(v_auth->>'tier',''), 'gated');
    if v_granted not in ('advisory','gated','supervised','autonomous') then v_granted := 'gated'; end if;

    -- WHO WILL DO IT, AND HOW HAS THEIR WORK BEEN GRADED. The assignee when one exists, else the
    -- proposer; an employee on reputation probation does not get its task waved through.
    v_rep_key := coalesce(r.assigned_agent, nullif(r.decided_by, '(unattributed)'));
    select p.tier into v_rep_tier from public.agent_reputation p where p.agent_key = v_rep_key;

    v_ceiling := case when r.action_class = any(c_ceiling) then 'autonomous' else 'gated' end;
    v_tier    := case when fn_authority_rank(v_granted) > fn_authority_rank(v_ceiling)
                      then v_ceiling else v_granted end;
    v_final   := case when r.needs_founder and fn_authority_rank(v_tier) > fn_authority_rank('gated')
                      then 'gated' else v_tier end;
    if v_rep_tier = 'probation' and v_final <> 'gated' then v_final := 'gated'; end if;

    -- Name the ACTUAL cause. Four different things produce a hold and they need different fixes:
    -- a hard gate is permanent, a missing org_authority row is a configuration gap someone should
    -- close, a ceiling clamp is a deliberate refusal to widen autonomy from a file, and a probation
    -- tier is the employee's own record.
    if v_final <> 'gated' then
      v_decision := 'approve';
      v_reason := 'Approved by the authority model: ' || r.dept_key || '/' || r.action_class
        || ' resolves to tier "' || v_final || '" (' || v_authreason || '); '
        || coalesce(v_rep_key, 'nobody') || ' holds reputation tier '
        || coalesce(v_rep_tier, 'unmeasured') || '. '
        || 'No founder gate applies — decision_policy.founder_review_gates covers refunds outside '
        || 'policy, money moves above the limit, published marketing, legal action, strategy '
        || 'changes, partnerships and executive security incidents only.';
    else
      v_decision := 'hold';
      if v_rep_tier = 'probation' then
        v_why := coalesce(v_rep_key, 'the proposer') || ' is on reputation probation, and a task '
              || 'of theirs is reviewed before it runs';
      elsif v_granted = 'gated' then
        v_why := 'the authority model itself grants no more than "gated" — ' || v_authreason;
      elsif fn_authority_rank(v_granted) > fn_authority_rank(v_ceiling) then
        v_why := 'org_authority grants "' || v_granted || '" but "' || r.action_class
              || '" sits outside AUTONOMOUS_CEILING, so it is clamped to "gated". Widening that set '
              || 'is a founder decision, not an edit';
      else
        v_why := 'the task was written with needs_founder=true by ' || r.decided_by
              || ', and needs_founder can only tighten';
      end if;
      v_reason := 'Held for review: ' || r.dept_key || '/' || r.action_class || ' — ' || v_why || '.';
    end if;

    if not p_dry_run then
      -- Idempotent on the DECISION, not on the run. An hourly sweep must not restate the same
      -- verdict 24 times a day; it must speak the moment a verdict CHANGES.
      insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent,
                                stage, decision, reason, confidence)
      select 'org_task', r.id::text, r.dept_key, r.decided_by, 'approval_path',
             'approval', v_decision, v_reason, 1.0
      where not exists (
        select 1 from review_chain rc
         where rc.subject_type = 'org_task' and rc.subject_id = r.id::text
           and rc.stage = 'approval' and rc.decision = v_decision);

      if v_decision = 'approve' then
        -- Write the RESOLVED tier, exactly as dept_plan does. Leaving the stale tier behind is the
        -- same "permission in the payload" defect audit 7.3 fixed in fn_event_dispatch, and
        -- cos_execute reads t.tier for its advisory_safe and review_pending decisions.
        update org_tasks
           set status = 'assigned', tier = v_final, needs_founder = false,
               decided_by = 'approval_path', updated_at = now()
         where id = r.id;
      end if;
    end if;

    if v_decision = 'approve' then v_promoted := v_promoted + 1; else v_held := v_held + 1; end if;
    if jsonb_array_length(v_sample) < 12 then
      v_sample := v_sample || jsonb_build_array(jsonb_build_object(
        'task', r.id, 'dept', r.dept_key, 'class', r.action_class,
        'granted', v_granted, 'final', v_final, 'decision', v_decision,
        'reputation', jsonb_build_object('agent', v_rep_key, 'tier', v_rep_tier)));
    end if;
  end loop;

  return jsonb_build_object(
    'dry_run', p_dry_run,
    'considered', v_promoted + v_held,
    'approved', v_promoted,
    'held_for_founder', v_held,
    'sample', v_sample);
end
$function$;
