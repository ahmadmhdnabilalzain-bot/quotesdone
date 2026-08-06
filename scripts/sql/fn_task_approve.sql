-- THE APPROVAL PATH. The thing dept_plan's own source said did not exist.
--
--   dept_plan/index.ts:65-69 — "`proposed` means 'waiting on a founder decision', and there is no
--   approval path, so a proposed row can never clear."
--
-- Measured on production 6 Aug 2026: 150 org_tasks parked at 'proposed', 114 of them more than a
-- week old, the oldest 25 July. 129 are advisory tier. NOT ONE advisory task has EVER reached
-- 'done' — only autonomous tasks complete (96). The improvement loop the whole architecture spec
-- rests on ("Every Task Has a Review Process", "Employees Must Plan") had no way to start.
--
-- THE ROOT CAUSE IS NOT dept_plan. dept_plan already routes correctly: it resolves the tier from
-- fn_dept_authority and writes status='assigned' for anything the model clears. The parked rows
-- come from the OTHER fourteen writers — fn_kpi_review, fn_os_review, fn_supply_gap_scan,
-- fn_outcome_evaluate, fn_edge_health_scan and friends — every one of which hardcodes
-- status='proposed' and never asks the authority model at all. Patching fourteen writers is
-- fourteen places to drift. The missing thing is genuinely one approval path, so this is it.
--
-- THE PREDICATE IS dept_plan's ROUTING RULE, DELIBERATELY IDENTICAL. That identity is the whole
-- safety argument: a row this function promotes is indistinguishable from a row dept_plan would
-- have written as 'assigned' in the first place. Any other predicate would be a second, competing
-- definition of what may run unattended — the "six vocabularies" defect this project has hit
-- repeatedly. The four clauses, in order:
--   1. the granted tier comes from fn_dept_authority, re-resolved NOW, never from the stored tier
--      (a permission carried in the payload is a claim by the caller, not a permission);
--   2. an unreadable or unknown tier fails closed to 'gated';
--   3. AUTONOMOUS_CEILING clamps: a class outside that set can never rise above 'gated' here even
--      when org_authority grants more. This is what holds supplier_approve_clean, role_define and
--      capability_review back despite an 'autonomous' grant, and it must stay in step with
--      supabase/functions/dept_plan/index.ts;
--   4. needs_founder only ever TIGHTENS, never loosens.
--
-- EVERY DISPOSITION IS WRITTEN WITH ITS REASON, approve or hold — founder's instruction, 6 Aug
-- 2026: "i need to know the reason." review_chain is the store because that is already where the
-- department-head and Chief-of-Staff decisions land, so there is one place to read who decided
-- what and why, not two.
create or replace function public.fn_task_approve(p_dry_run boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare
  r            record;
  v_granted    text;
  v_ceiling    text;
  v_tier       text;
  v_final      text;
  v_why        text;
  v_reason     text;
  v_decision   text;
  v_authreason text;
  v_promoted   int := 0;
  v_held       int := 0;
  v_sample     jsonb := '[]'::jsonb;
  -- Mirrors AUTONOMOUS_CEILING in supabase/functions/dept_plan/index.ts byte for byte.
  c_ceiling constant text[] := array['content_draft','knowledge_fill','recommend','invite',
                                     'analysis','research','seo','monitor','reconcile','outreach_draft'];
begin
  for r in
    select id, dept_key, action_class, tier, coalesce(needs_founder,false) needs_founder,
           coalesce(decided_by,'(unattributed)') decided_by, title
      from org_tasks
     where status = 'proposed'
     order by id
  loop
    v_authreason := coalesce(fn_dept_authority(r.dept_key, r.action_class)->>'reason', 'no reason given');
    v_granted    := coalesce(nullif(fn_dept_authority(r.dept_key, r.action_class)->>'tier',''), 'gated');
    if v_granted not in ('advisory','gated','supervised','autonomous') then v_granted := 'gated'; end if;

    v_ceiling := case when r.action_class = any(c_ceiling) then 'autonomous' else 'gated' end;
    v_tier    := case when fn_authority_rank(v_granted) > fn_authority_rank(v_ceiling)
                      then v_ceiling else v_granted end;
    v_final   := case when r.needs_founder and fn_authority_rank(v_tier) > fn_authority_rank('gated')
                      then 'gated' else v_tier end;

    -- Name the ACTUAL cause. Three different things produce a hold and they need different fixes:
    -- a hard gate is permanent, a missing org_authority row is a configuration gap someone should
    -- close, and a ceiling clamp is a deliberate refusal to widen autonomy from a file.
    if v_final <> 'gated' then
      v_decision := 'approve';
      v_reason := 'Approved by the authority model: ' || r.dept_key || '/' || r.action_class
        || ' resolves to tier "' || v_final || '" (' || v_authreason || '). '
        || 'No founder gate applies — decision_policy.founder_review_gates covers refunds outside '
        || 'policy, money moves above the limit, published marketing, legal action, strategy '
        || 'changes, partnerships and executive security incidents only.';
    else
      v_decision := 'hold';
      if v_granted = 'gated' then
        v_why := 'the authority model itself grants no more than "gated" — ' || v_authreason;
      elsif fn_authority_rank(v_granted) > fn_authority_rank(v_ceiling) then
        v_why := 'org_authority grants "' || v_granted || '" but "' || r.action_class
              || '" sits outside AUTONOMOUS_CEILING, so it is clamped to "gated". Widening that set '
              || 'is a founder decision, not an edit';
      else
        v_why := 'the task was written with needs_founder=true by ' || r.decided_by
              || ', and needs_founder can only tighten';
      end if;
      v_reason := 'Held for the founder: ' || r.dept_key || '/' || r.action_class || ' — ' || v_why || '.';
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
        'granted', v_granted, 'final', v_final, 'decision', v_decision));
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

comment on function public.fn_task_approve(boolean) is
  'The approval path for org_tasks parked at status=proposed. Applies dept_plan''s exact routing '
  'rule (fn_dept_authority, fail closed, AUTONOMOUS_CEILING clamp, needs_founder tightens only) and '
  'promotes what the authority model clears to status=assigned. Every disposition, approve or hold, '
  'is written to review_chain with its reason. Idempotent on the decision.';
