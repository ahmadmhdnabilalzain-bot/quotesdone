-- LAUNCH STEP 1 — THE APEX ESCALATES TO THE FOUNDER, NOT DOWN TO A SUBORDINATE.
--
-- Measured 2026-08-31 on htdblwldjkcgjvmqkbeh: fn_should_escalate resolves the escalation target off
-- org_agents.manager_key (the reporting line). The CEO is the one active agent with manager_key NULL
-- (the apex reports to the founder, not to another agent). With no manager_key the reporting-line
-- branch cannot fire, so a CEO escalation fell through to the exec-department fallback and was
-- addressed to 'brief' (chief_of_staff) — a SUBORDINATE. The company's apex escalated DOWN.
--
-- The founder's rule (LAUNCH_READINESS_PLAN.md, 27 Aug 2026): the only human signal is the founder,
-- and "only the CEO's genuine major-issue escalation may reach" him. The party above the apex IS the
-- founder; there is no internal role above the CEO. This adds that one branch.
--
-- It is placed FIRST in party resolution — before the configured review_owner — because a configured
-- subordinate owner must never capture an apex escalation, and the apex has no internal superior for
-- the reporting-line branch to find. The apex is identified by manager_key IS NULL (active), not by a
-- hardcoded 'ceo', so a future rename of the seat does not silently re-break this.
--
-- route_to = 'founder' is a routing DECISION, recorded in decision_log.route_to by trg_action_gate.
-- The DELIVERY of a founder alert to his email/WhatsApp channel is Stage-4 work and is unchanged
-- here; this fixes only that the routing points UP to the founder rather than DOWN to a subordinate.
--
-- Not a frozen subject (verified against phase_c_frozen_subject). Escalate-target resolution is a
-- runtime routing function, not a kernel primitive or a refund guard.
--
--   node scripts/apply_sql.mjs scripts/sql/launch_step1_ceo_escalates_to_founder.sql --apply

CREATE OR REPLACE FUNCTION public.fn_should_escalate(ctx jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  reasons text[] := '{}';
  conf_min numeric; fin_review numeric; auto_max numeric; fraud_max numeric;
  legal jsonb; sens jsonb; owner text;
  c_conf numeric := nullif(ctx->>'confidence','')::numeric;
  c_amt  numeric := nullif(ctx->>'amount_aed','')::numeric;
  c_fraud numeric := nullif(ctx->>'fraud_score','')::numeric;
  c_cat  text := lower(coalesce(ctx->>'category',''));
  c_txt  text := lower(coalesce(ctx->>'text',''));
  c_kind text := lower(coalesce(ctx->>'kind',''));
  -- KINDS THAT REPORT RATHER THAN ACT. See the note above the prior-failure rule.
  REPORTING_KINDS constant text[] := array['handoff','incident','report_task'];
  c_money boolean := coalesce((ctx->>'moves_money')::boolean,false);
  trg text;
  -- WHO IS ESCALATING. Every caller knows it and none of them used to say it, so the router had
  -- exactly one input for "who takes this" — decision_policy.review_owner — and therefore exactly
  -- one answer for all 67 employees and every situation.
  c_actor text := nullif(btrim(coalesce(ctx->>'actor', ctx->>'agent_key', '')), '');
  v_route text; v_basis text; v_note text;
  v_mgr text; v_mgr_dept text; v_pick jsonb;
  v_actor_res text;
begin
  select value::numeric into conf_min   from decision_policy where key='confidence_min';
  select value::numeric into fin_review  from decision_policy where key='financial_review_aed';
  select value::numeric into auto_max    from decision_policy where key='auto_action_max_aed';
  select value::numeric into fraud_max   from decision_policy where key='fraud_score_max';
  select value into legal                from decision_policy where key='legal_triggers';
  select value into sens                 from decision_policy where key='sensitive_categories';
  select value #>> '{}' into owner       from decision_policy where key='review_owner';

  if c_conf is not null and c_conf < conf_min then
     reasons := array_append(reasons, 'confidence '||round(c_conf,2)::text||' < min '||round(conf_min,2)::text); end if;
  if c_amt is not null and c_amt >= fin_review then
     reasons := array_append(reasons, 'amount AED '||c_amt::text||' >= review threshold '||fin_review::text); end if;
  if c_money and (c_amt is null or c_amt > auto_max) then
     reasons := array_append(reasons, 'action moves money beyond autonomous limit'); end if;
  if c_fraud is not null and c_fraud >= fraud_max then
     reasons := array_append(reasons, 'fraud score '||round(c_fraud,2)::text||' >= max '||round(fraud_max,2)::text); end if;
  if c_cat <> '' and sens ? c_cat and (c_conf is null or c_conf < conf_min) then
     reasons := array_append(reasons, 'sensitive category "'||c_cat||'" with low/absent confidence'); end if;
  for trg in select jsonb_array_elements_text(legal) loop
     if c_txt <> '' and position(trg in c_txt) > 0 then
        reasons := array_append(reasons, 'legal trigger: "'||trg||'"'); end if;
  end loop;

  -- A FAILED STRATEGY IS NOT REPEATED UNKNOWINGLY.
  -- institutional_memory is the company's ledger of what happened after it acted; 287 items, 9 of
  -- them graded 'worse'. Nothing on the path an action takes has ever read it. If this action reads
  -- like something already tried that ended worse, it goes to a person instead of through.
  --
  -- THREE distinct tokens from the SAME lesson, not one. The 'worse' headlines carry words like
  -- "review", "status", "failed" and "knowledge"; a single-token match would escalate most of the
  -- 1,229 actions the gate sees in a month. A headline too short to supply three tokens can never
  -- fire, which is the right answer for one — "OS review [amber]: Technology OS" is not evidence
  -- that anything in particular was tried.
  if c_txt <> '' and not (c_kind = any (REPORTING_KINDS)) then
    for trg in
      select m.headline from institutional_memory m
       where m.outcome = 'worse' and coalesce(m.headline,'') <> ''
         and (select count(distinct w) from regexp_split_to_table(lower(m.headline), '[^a-z0-9_]+') w
               where length(w) >= 6 and position(w in c_txt) > 0) >= 3
       order by m.created_at desc limit 2
    loop
      reasons := array_append(reasons,
        'a prior attempt on record ended worse: "'||left(trg, 120)||'"');
    end loop;
  end if;

  -- THE APEX ESCALATES TO THE FOUNDER (2026-08-31). Resolved FIRST, before any other party, because
  -- the company's apex has no internal superior and a configured subordinate owner must not capture
  -- its escalation. The apex is the active agent with no manager_key — the CEO reports to the founder,
  -- not to another agent — so the only party "up" from it is the founder himself. Without this the
  -- CEO's escalation fell to the exec fallback below and was addressed to chief_of_staff, routing the
  -- apex DOWN to a subordinate. 'founder' is the routing decision; delivering the alert to his channel
  -- is Stage-4 work and is not done here.
  if c_actor is not null then
    v_actor_res := coalesce(public.fn_org_agent_resolve(c_actor), c_actor);
    perform 1 from org_agents a where a.agent_key = v_actor_res and a.active and a.manager_key is null;
    if found then
      v_route := 'founder'; v_basis := 'apex_to_founder';
      v_note  := 'the company apex ('||v_actor_res||') has no manager; the only party above it is the '
              || 'founder, whose major-issue channel is the single human signal the design allows';
    end if;
  end if;

  -- RESOLVE THE PARTY. Four attempts, strongest first; each one is a party the org model contains.
  if v_route is null and owner is not null and btrim(owner) <> '' then
    select a.agent_key into v_route from org_agents a
     where a.active and a.agent_key = owner limit 1;
    if v_route is not null then v_basis := 'employee'; end if;

    if v_route is null then
      select d.dept_key into v_route from org_departments d
       where d.dept_key = owner
         and exists (select 1 from org_agents a where a.department = d.dept_key and a.active)
       limit 1;
      if v_route is not null then v_basis := 'staffed_department'; end if;
    end if;

    if v_route is null then
      select a.agent_key into v_route from org_agents a
       where a.active and a.title ilike '%'||owner||'%'
       order by a.agent_key limit 1;
      if v_route is not null then v_basis := 'employee_by_title'; end if;
    end if;
  end if;

  -- THE REPORTING LINE. The configured owner named nobody, and before this rung existed the next
  -- thing to run was the exec fallback — so every escalation in the company, whoever raised it and
  -- whatever it was about, was addressed to one person. "Who must approve? Who must review?" was
  -- being answered with a constant. org_agents.manager_key is the only column in the company that
  -- records what "up" is (65 of 66 active employees carry one and all 65 resolve to an active
  -- employee), and escalation means up. It sits AFTER the configured owner deliberately: an explicit
  -- review_owner that resolves is founder configuration and still wins.
  --
  -- AVAILABILITY IS PART OF NAMING A PARTY. A manager on leave is the same nobody an unstaffed
  -- department is, so the manager must be active AND available; if they are not, the standing deputy
  -- is resolved by fn_pick_reviewer — which already owns delegation_rule, the reputation tier and
  -- the seniority tie-break for exactly this question, and is not reimplemented here.
  if v_route is null and c_actor is not null then
    select a.manager_key into v_mgr from org_agents a where a.agent_key = c_actor and a.active;
    if v_mgr is not null and v_mgr <> c_actor then
      select a.agent_key into v_route from org_agents a
       where a.agent_key = v_mgr and a.active and a.available
         and (a.unavailable_until is null or a.unavailable_until < current_date);
      if v_route is not null then v_basis := 'reporting_line'; end if;

      if v_route is null then
        select a.department into v_mgr_dept from org_agents a where a.agent_key = v_mgr;
        begin v_pick := public.fn_pick_reviewer(v_mgr_dept);
        exception when others then v_pick := null; end;
        v_route := public.fn_route_party(v_pick->>'reviewer');
        -- ESCALATING TO YOURSELF IS ESCALATING TO NOBODY. Measured on staging while proving this
        -- branch: with cfo marked unavailable, delegation_rule #4 names ap_specialist as finance's
        -- standing deputy — and ap_specialist was the employee raising the escalation, so the
        -- router handed the item straight back to them. When the deputy is the escalator the rung
        -- yields and the exec fallback below takes it up instead.
        if v_route = c_actor then v_route := null; end if;
        if v_route is not null then
          v_basis := 'reporting_line_delegated';
          v_note  := 'manager '||v_mgr||' is unavailable; '
                  || coalesce(v_pick->>'basis','delegation_rule standing deputy');
        end if;
      end if;
    end if;
  end if;

  -- The configured owner names nobody. Escalate to the executive department's own head rather than
  -- to a string: brain_agent first (the department's reasoning seat), then lead_agent, then any
  -- active member. Recorded as a fallback so the configuration gap stays visible.
  if v_route is null then
    select coalesce(
             (select d.brain_agent from org_departments d where d.dept_key='exec'
               and exists (select 1 from org_agents a where a.agent_key=d.brain_agent and a.active)),
             (select d.lead_agent  from org_departments d where d.dept_key='exec'
               and exists (select 1 from org_agents a where a.agent_key=d.lead_agent and a.active)),
             (select a.agent_key from org_agents a where a.active and a.department='exec'
               order by a.agent_key limit 1))
      into v_route;
    if v_route is not null then
      v_basis := 'fallback_exec';
      v_note := 'configured review_owner "'||coalesce(owner,'(unset)')||'" names no active employee '
             || 'and no staffed department; escalation addressed to '||v_route||' instead';
    end if;
  end if;

  -- Nothing in the org model resolves. Return the configured label unchanged and say so, so the
  -- gap is measurable rather than papered over.
  if v_route is null then
    v_route := owner; v_basis := 'unresolved';
    v_note := 'configured review_owner "'||coalesce(owner,'(unset)')||'" resolves to no party in the '
           || 'org model, and no active executive employee was available to take it';
  end if;

  -- ROUTING IS NOT A REASON TO ESCALATE. `reasons` is what makes `escalate` true and what
  -- trg_action_gate copies into decision_log.reasons, so appending a routing note here would have
  -- made EVERY gated action escalate — the note lives in its own key for exactly that reason.
  return jsonb_build_object(
    'escalate', array_length(reasons,1) is not null,
    'reasons', to_jsonb(reasons),
    'route_to', v_route,
    'route_basis', v_basis,
    'route_note', v_note,
    'route_owner_configured', owner);
end $function$;
