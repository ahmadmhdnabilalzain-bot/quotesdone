-- WIDENING AUTONOMOUS_CEILING IS AN ENGINEERING CHANGE, NOT A FOUNDER DECISION (6 Sep 2026).
--
-- The hold reason said "Widening that set is a founder decision, not an edit". Nothing but a
-- Stripe refund routes to the founder; the ceiling is a constant in this routine, changed by a
-- migration with its reasoning in the commit. The reason string now says that.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_task_approve_ceiling_is_not_a_founder_decision.sql --apply --ddl

CREATE OR REPLACE FUNCTION public.fn_task_approve(p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
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
  v_lane       int := 0;
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
              || 'is a change to this routine''s AUTONOMOUS_CEILING constant, not an edit to the task';
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

      if v_decision = 'hold' and not r.needs_founder then
        -- A HOLD HAS AN OWNER (5 Sep 2026). A gated proposal used to stay 'proposed' with nobody named,
        -- and the OS showed it to the founder as his decision. His standing rule: nothing reaches him
        -- except a Stripe refund — and the only class that may carry needs_founder is refund_decision
        -- (a00_org_tasks_founder_routing_refund_only). So a hold enters the org_task lane at tier
        -- 'gated': the department determines it from company knowledge, the accountable colleague
        -- reviews it, and the lane invokes no executor above low/advisory_safe/reversible at that tier.
        -- The review_chain 'hold' verdict above stays on record; the row also says why it was held.
        update org_tasks
           set status = 'assigned', tier = 'gated', needs_founder = false,
               decided_by = 'approval_path', updated_at = now(),
               result = coalesce(result, '{}'::jsonb) || jsonb_build_object(
                 'held', jsonb_build_object('at', now(), 'by', 'fn_task_approve', 'reason', v_reason,
                   'owner_basis', 'a hold is reviewed by the department in the org_task lane at tier gated, never by the founder'))
         where id = r.id;
        v_lane := v_lane + 1;
      end if;

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
    -- 'held' counts every hold verdict; of those, only a needs_founder (refund) row stays 'proposed'.
    'held', v_held,
    'held_into_lane', v_lane,
    'held_for_founder', v_held - v_lane,
    'sample', v_sample);
end
$function$;
