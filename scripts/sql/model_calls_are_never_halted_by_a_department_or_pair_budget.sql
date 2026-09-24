-- MODEL CALLS ARE NEVER HALTED BY A DEPARTMENT OR A PAIR BUDGET.
-- Seat: it_engineer. 24 Sep 2026. Founder ruling (founder_instruction 987): no caps on LLM spend; idle spend stays at or
-- below USD 1-2 a day because the code is correct, not because a ceiling stops it.
--
-- MEASURED (production htdblwldjkcgjvmqkbeh, 24 Sep 2026, read-only):
--   * public.fn_ai_route refused every non-gated call once a department passed department_budget.halt_at_pct of its
--     monthly_aed (marketing 100 @ 85 %, marketplace 1300 @ 95 %, finance 40 @ 90 %, it 40 @ 85 %, exec 60 @ 90 %,
--     customer_experience 60 @ 90 %), and swapped to a cheaper tier past degrade_at_pct. ai_gateway answered it as
--     outcome budget_halted.
--   * public.fn_seat_deliberation_budget refused the CEO's review of marketing's monthly plan past
--     seat_deliberation_ceiling.cap_aed_month (AED 50), so fn_seat_deliberation_step held it.
--
-- WHY REMOVING THEM IS SAFE, PATH BY PATH (the correctness that bounds spend instead):
--   * fn_ai_route is a pure routing function: it chooses a model, it never loops and it calls nothing. What each caller
--     sends is bounded by that caller (routine work is code, think() internal steps on GLM, 2 provider calls per request,
--     3 tries per held row, fixture traffic stubbed; the idle proof in PR #936 sums it to about USD 0.20/day).
--   * The seat deliberation is real judgement (the CEO reviewing marketing's month, founder_instruction 873), not routine.
--     It is started by the author once per plan; fn_seat_deliberation_step is one model step per phase and round, a
--     recorded turn is unique per (deliberation, round, phase), rounds are at most 3 (CHECK max_rounds <= 3), and
--     fn_seat_deliberation_due stops offering a deliberation after 3 failed turns in a round. So a model that keeps
--     failing is asked at most 3 times per round, never every heartbeat. A demo deliberation never reaches a model.
--   What stays: department_budget and seat_deliberation_ceiling as DATA (the books' budget_vs_actual, and which
--   department a pair's review is charged to). fn_check_spend / fn_budget_available authorise company money for
--   actions, not model calls, and are untouched.
--
-- CANONICAL BODIES STARTED FROM: fn_ai_route <- every_routine_that_still_addressed_a_seat_nobody_holds.sql (read back
-- from production, pg_get_functiondef, 24 Sep 2026; only the halt/degrade block changed);
-- fn_seat_deliberation_budget <- a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql (ok = the pair is registered).
-- CREATE OR REPLACE keeps each routine's ACL, so no revoke here.
-- Pending: scripts/sql/pending/model_calls_are_never_halted_by_a_department_or_pair_budget.txt
-- Prevented by: scripts/checks/a_held_row_is_tried_three_times_and_no_spend_ceiling_exists.test.mjs

CREATE OR REPLACE FUNCTION public.fn_ai_route(p_task_class text DEFAULT NULL::text, p_dept_key text DEFAULT NULL::text, p_confidence numeric DEFAULT NULL::numeric, p_fn text DEFAULT NULL::text, p_escalate boolean DEFAULT false, p_require_caps text[] DEFAULT NULL::text[], p_agent_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_class   text;
  v_src     text;
  v_pol     model_policy%rowtype;
  v_reg     model_registry%rowtype;
  v_fb      model_registry%rowtype;
  v_bud     department_budget%rowtype;
  v_pct     numeric := 0;
  v_model   text;
  v_why     text;
  v_min     numeric;
  v_tier    text;
  v_vis     boolean := 'vision' = any(coalesce(p_require_caps, '{}'::text[]));
  v_aud     boolean := 'audio'  = any(coalesce(p_require_caps, '{}'::text[]));
  v_tls     boolean := 'tools'  = any(coalesce(p_require_caps, '{}'::text[]));
  v_sub     model_registry%rowtype;
  v_want    int;
  v_idp     model_policy_by_identity%rowtype;
  v_generic boolean := false;
  v_rt      jsonb;
  v_prior   jsonb;
  v_conf    numeric;
  v_rtier   text;
  v_canon   text;
begin
  if p_task_class is not null and length(btrim(p_task_class)) > 0 then
    v_class := p_task_class; v_src := 'caller-supplied task_class';
  else
    select task_class into v_class from fn_task_class where fn = p_fn and active;
    if v_class is not null then
      v_src := 'classified from calling function "' || p_fn || '"';
    else
      v_class := 'general_drafting';
      v_generic := true;
      v_src := 'UNMAPPED function "' || coalesce(p_fn,'?') || '" - defaulted to general_drafting (medium). Add a fn_task_class row to route this properly.';
    end if;
  end if;

  -- THE PACK'S FOUR-ROLE TAXONOMY REACHES THE PATH IT WAS WRITTEN FOR (14 Aug 2026).
  --
  -- All 93 employees carry org_agents.routing_tier - director 36, operations_specialist 23,
  -- analyst_controller 21, reviewer_auditor 10 - and on the main employee path it was DEAD.
  -- fn_routing_tier_model below only fires when v_generic is true, i.e. when the calling function
  -- is unmapped; agent_brain IS mapped, to agent_reasoning, so every employee from a marketing
  -- copywriter to the CEO got the same blanket large tier.
  --
  -- Meanwhile model_policy carries routine_employee_reasoning at MEDIUM, and its own rationale
  -- says: "Pack: replaces the current blanket large-tier agent_reasoning. agent_reasoning is LIVE
  -- on anthropic/claude-sonnet-5 and agent_brain is ~93% of OpenRouter spend." It had ZERO callers.
  -- A policy written to replace something, that nothing points at, is a build order nobody wired.
  --
  -- This is a ROUTING decision taken from the role, not an override of task_class routing: the
  -- class is chosen by who is asking, then the policy for that class applies normally.
  --
  -- WHO STAYS ON LARGE, AND WHY. Only operations_specialist moves. reviewer_auditor stays large
  -- deliberately - all 24 Reviewer/Auditor rows in the pack name a large model, and a reviewer on
  -- the cheap model is a green check that means nothing. director and analyst_controller stay
  -- because their work is the consequential kind the large tier exists for.
  if v_class = 'agent_reasoning' and p_agent_key is not null then
    v_canon := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
    select a.routing_tier into v_rtier from org_agents a
     where a.agent_key = v_canon and a.active;
    if v_rtier = 'operations_specialist'
       and exists (select 1 from model_policy mp
                    where mp.task_class = 'routine_employee_reasoning' and mp.active) then
      v_class := 'routine_employee_reasoning';
      v_src := v_src || ' | routing_tier "operations_specialist" for "' || v_canon
                     || '" selected the routine employee class instead of the blanket large tier';
    end if;
  end if;

  select * into v_pol from model_policy where task_class = v_class and active;
  if not found then
    select * into v_pol from model_policy where task_class = 'general_drafting' and active;
    v_src := v_src || ' | no policy for "' || v_class || '", fell back to general_drafting';
    v_generic := true;
  end if;

  -- THE ROLE DEFAULT. model_policy_by_identity carries 120 rows — 96 target employees and 24
  -- current production agents — and had NO reader in the database at all. The pack states its own
  -- precedence on every row: note = 'Role default only; task_class routing overrides it.' So it
  -- applies only where the caller would otherwise get the generic general_drafting fallback:
  -- either the named class has no policy, or the calling function is unmapped in fn_task_class.
  --
  -- v_generic exists because the first version of this branch was UNREACHABLE. It hung off
  -- `if not found` on the model_policy lookup, and an unmapped function has already had v_class
  -- rewritten to 'general_drafting' by then — which IS found. Measured: fn_ai_route(...,'ceo')
  -- returned identity_policy null. Same shape as the unreachable block in
  -- fn_kb_route_activation_blocked found earlier today: a branch guarded by a condition that
  -- cannot occur.
  --
  -- 23 of the 24 current_agent keys resolve to a real org_agents row; 'cat:*' covers the
  -- category desks.
  if v_generic and p_agent_key is not null then
    select * into v_idp from model_policy_by_identity
     where scope = 'current_agent'
       and (identity_key = p_agent_key
            or (identity_key = 'cat:*' and p_agent_key like 'cat:%'))
     order by (identity_key = p_agent_key) desc
     limit 1;
    if found and v_idp.primary_model is not null then
      v_pol.model_primary  := v_idp.primary_model;
      v_pol.model_fallback := coalesce(v_idp.fallback_model, v_pol.model_fallback);
      v_pol.max_tokens     := coalesce(v_idp.max_output_tokens, v_pol.max_tokens);
      v_src := v_src || ' | role default for "' || p_agent_key || '" applied from model_policy_by_identity';
    end if;
  end if;

  -- ---- ROUTING TIER, added 11 Aug 2026 ---------------------------------------------------------
  -- The pack's four-role taxonomy carried onto the 93 real employees as org_agents.routing_tier.
  -- Fires LAST and only if the pack had nothing to say about this specific agent, so an explicit
  -- current_agent row always wins. Resolves tier -> registry tier -> cheapest active approved model
  -- AT CALL TIME: no model id is stored anywhere, so this follows the fleet instead of going stale.
  -- Measured direction against the general_drafting default (haiku, 1.00 USD/Mtok in):
  -- operations_specialist 4x cheaper, analyst/director unchanged, reviewer_auditor 2x dearer and
  -- deliberately so - all 24 Reviewer/Auditor rows in the pack name sonnet-5, and a reviewer on the
  -- cheap model is a green check that means nothing.
  if v_generic and p_agent_key is not null and v_idp.identity_key is null then
    v_rt := public.fn_routing_tier_model(p_agent_key);
    if v_rt is not null and (v_rt->>'model') is not null then
      v_pol.model_primary := v_rt->>'model';
      v_pol.tier          := v_rt->>'registry_tier';
      v_src := v_src || ' | routing_tier "' || (v_rt->>'routing_tier') || '" for "' || p_agent_key
                     || '" resolved to ' || (v_rt->>'model') || ' (' || (v_rt->>'registry_tier') || ' tier)';
    end if;
  end if;
  -- ----------------------------------------------------------------------------------------------

  if v_pol.tier = 'none' then
    return jsonb_build_object(
      'use_llm', false, 'task_class', v_class, 'tier', 'none',
      'why', 'REFUSED. ' || coalesce(v_pol.deterministic_alternative, 'This is deterministic - use code.')
             || ' [' || v_src || ']',
      'deterministic_alternative', v_pol.deterministic_alternative);
  end if;

  v_tier  := v_pol.tier;
  v_model := v_pol.model_primary;
  v_why   := coalesce(v_pol.rationale, 'policy for ' || v_class) || ' [' || v_src || ']';

  if p_escalate then
    v_model := coalesce(v_pol.model_fallback, v_model);
    v_why   := v_why || ' | ESCALATED one tier after an unsatisfactory cheaper attempt';
  end if;

  select (value #>> '{}')::numeric into v_min from decision_policy where key = 'confidence_min';
  -- THE PRIOR, 11 Aug 2026. Both arms below are original and NEITHER HAS EVER FIRED, because
  -- p_confidence is the confidence of THIS call and no caller can know that before the call.
  -- Measured the day this was written: 7 of 1,746 model calls in seven days carried a confidence at
  -- all. The only confidence that CAN exist beforehand is the agent's own recent record on this
  -- task class, so that is what a caller supplying nothing now routes on.
  --
  -- fn_ai_confidence_prior returns null unless there are at least 5 observations AND they vary.
  -- The variance guard is the important half: the two callers that emitted a confidence before
  -- tonight always emitted exactly 1.0000, and a model reporting the same number every time would
  -- otherwise downgrade itself to a cheaper tier on the strength of its own unvarying optimism.
  v_conf := p_confidence;
  if v_conf is null and p_agent_key is not null then
    v_prior := public.fn_ai_confidence_prior(p_agent_key, v_class);
    if v_prior is not null then v_conf := (v_prior->>'prior')::numeric; end if;
  end if;

  if v_conf is not null then
    if v_conf >= 0.95 and v_tier in ('large','xlarge') then
      select model_id into v_model from model_registry
       where active and approved and tier = 'medium' order by in_per_mtok_usd limit 1;
      v_why := v_why || ' | confidence ' || v_conf
               || case when v_prior is null then ''
                       else ' (' || p_agent_key || ' own median over ' || (v_prior->>'n')
                            || ' calls on ' || v_class || ', spread ' || (v_prior->>'spread') || ')' end
               || ' >= 0.95, downgraded to medium - no second opinion needed';
    elsif v_min is not null and v_conf < v_min and v_tier = 'small' then
      v_model := coalesce(v_pol.model_fallback, v_model);
      v_why := v_why || ' | confidence ' || v_conf
               || case when v_prior is null then ''
                       else ' (' || p_agent_key || ' own median over ' || (v_prior->>'n') || ' calls)' end
               || ' below floor ' || v_min || ', escalated a tier';
    end if;
  end if;

  -- (Historical, 13 Aug 2026: the halt that used to follow needed a department.) A CALL WITH NO DEPARTMENT: the lookup below needs a
  -- dept_key to find a budget, and 59 of this month's calls arrived without one - inquiry_intake,
  -- drawing_boq, doc_extract, license_extract, supplier_onboard and eleven more, i.e. the demand
  -- path. fn_task_class already maps fn -> task_class for this same function's model choice; it now
  -- carries the owning department too, so an un-attributed call is attributed by what it IS rather
  -- than left outside every ceiling. An explicit p_dept_key from the caller still wins.
  -- CANONICAL BEFORE THE CEILING (14 Aug 2026). department_budget holds the ten canonical rows;
  -- a caller passing a merged-away key ('procurement', 'marketing', 'sales' ...) found NO budget
  -- row and skipped the ceiling entirely. fn_dept_canonical resolves the key the caller used to
  -- the department that actually owns it.
  if public.fn_dept_canonical(coalesce(p_dept_key, (select t.dept_key from fn_task_class t where t.fn = p_fn and t.active))) is not null then
    select * into v_bud from department_budget
     where dept_key = public.fn_dept_canonical(coalesce(p_dept_key, (select t.dept_key from fn_task_class t where t.fn = p_fn and t.active)));
    if found and v_bud.monthly_aed > 0 then
      v_pct := round(100 * coalesce(
        (select sum(cost_aed) from ai_cost_log
          where dept_key = any(public.fn_dept_scope(v_bud.dept_key))
            and occurred_at >= date_trunc('month', now())), 0)
        / v_bud.monthly_aed, 2);
      -- NO HALT AND NO DEGRADE (24 Sep 2026, founder_instruction 987: no caps on LLM spend). v_pct is still
      -- reported as budget_pct so the books can see a department's spend; it no longer refuses or downgrades a call.
    end if;
  end if;

  select * into v_reg from model_registry where model_id = v_model and active;
  if not found then
    select * into v_reg from model_registry
     where active and approved and tier = (case v_tier when 'xlarge' then 'xlarge' else v_tier end)
     order by in_per_mtok_usd limit 1;
    v_why := v_why || ' | WARNING: policy model "' || v_model || '" is not in model_registry; substituted ' || coalesce(v_reg.model_id,'(none)');
    v_model := v_reg.model_id;
  end if;

  -- CAPABILITY. Price and tier chose the model above; if it cannot see, hear or call tools the
  -- provider will simply reject the payload. Substitute the nearest capable model, preferring the
  -- intended tier, then the closest tier ABOVE it, and only then below - a capability substitution
  -- must never quietly become a quality downgrade.
  v_want := fn_ai_route_tier_rank(v_tier);
  if (v_vis or v_aud or v_tls)
     and not ( (not v_vis or coalesce(v_reg.supports_vision,false))
           and (not v_aud or coalesce(v_reg.supports_audio, false))
           and (not v_tls or coalesce(v_reg.supports_tools, false)) ) then

    select * into v_sub from model_registry
     where active and approved
       and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools)
     order by (fn_ai_route_tier_rank(tier) < v_want),                 -- at-or-above the tier first
              abs(fn_ai_route_tier_rank(tier) - v_want),              -- then closest to it
              in_per_mtok_usd                                          -- then cheapest
     limit 1;

    if found then
      v_why := v_why || ' | CAPABILITY OVERRIDE: ' || v_model || ' cannot do ('
               || array_to_string(coalesce(p_require_caps,'{}'::text[]), '+') || '); substituted ' || v_sub.model_id
               || ' (' || v_sub.tier || ' tier, intended ' || v_tier || ')';
      v_reg := v_sub; v_model := v_sub.model_id;
    else
      return jsonb_build_object(
        'use_llm', false, 'task_class', v_class, 'tier', v_tier, 'caps', to_jsonb(p_require_caps),
        'why', 'REFUSED. No active approved model in model_registry supports ('
               || array_to_string(coalesce(p_require_caps,'{}'::text[]), '+')
               || '). Add one, or mark the capability on an existing model.');
    end if;
  end if;

  select * into v_fb from model_registry
   where model_id = v_pol.model_fallback and active
     and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools);
  if not found and (v_vis or v_aud or v_tls) then
    select * into v_fb from model_registry
     where active and approved and model_id <> v_model
       and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools)
     order by (fn_ai_route_tier_rank(tier) < v_want), abs(fn_ai_route_tier_rank(tier) - v_want), in_per_mtok_usd
     limit 1;
  end if;

  return jsonb_build_object(
    'use_llm', true,
    'task_class', v_class,
    'tier', v_tier,
    'model', v_model,
    'fallback', v_fb.model_id,
    'max_tokens', v_pol.max_tokens,
    'cache_ttl_min', coalesce(v_pol.cache_ttl_min, 0),
    'cache', coalesce(v_reg.supports_cache, false),
    'stream', coalesce(v_reg.supports_streaming, true),
    'caps', to_jsonb(coalesce(p_require_caps, '{}'::text[])),
    'in_per_mtok_usd', v_reg.in_per_mtok_usd,
    'out_per_mtok_usd', v_reg.out_per_mtok_usd,
    'cache_read_per_mtok_usd', v_reg.cache_read_per_mtok_usd,
    'budget_pct', v_pct,
    'identity_policy', case when v_idp.identity_key is null then null else jsonb_build_object(
        'identity_key', v_idp.identity_key, 'deterministic_first', v_idp.deterministic_first,
        'reasoning_effort', v_idp.reasoning_effort, 'authority_tier', v_idp.authority_tier) end,
    'routing_tier', v_rt,
    'confidence_prior', v_prior,
    'confidence_used', v_conf,
    'why', v_why);
end $function$;

-- A PAIR IS ALLOWED WHEN IT IS REGISTERED; ITS SPEND IS REPORTED, NEVER COMPARED WITH A LIMIT. The row still names the
-- department the review is charged to (dept), which fn_seat_deliberation_step passes on to the router.
CREATE OR REPLACE FUNCTION public.fn_seat_deliberation_budget(p_author_seat text, p_reviewer_seat text, p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when c.author_seat is null
    then jsonb_build_object('ok', false, 'dept', null, 'why', 'no seat_deliberation_ceiling row for ' || p_author_seat || ' -> ' || p_reviewer_seat)
    else jsonb_build_object('ok', true, 'dept', c.dept_key, 'spent_aed', s.spent,
                            'why', 'reviews ' || p_author_seat || ' -> ' || p_reviewer_seat || ' spent AED ' || s.spent
                                   || ' this month (' || c.dept_key || '); no limit (founder_instruction 987)') end
    from (select 1) one
    left join public.seat_deliberation_ceiling c on c.author_seat = p_author_seat and c.reviewer_seat = p_reviewer_seat
    left join lateral (select coalesce(sum(l.cost_aed), 0) spent from public.ai_cost_log l
                        where l.task_class in ('seat_deliberation_blind', 'seat_deliberation_compare')
                          and l.dept_key = c.dept_key and l.agent_key = p_reviewer_seat
                          and l.occurred_at >= (date_trunc('month', p_at at time zone 'Asia/Dubai') at time zone 'Asia/Dubai')) s on true
$function$;

-- Verdict row (DDL in this file, so no raise).
select case
  when pg_get_functiondef('public.fn_ai_route(text,text,numeric,text,boolean,text[],text)'::regprocedure) ~ 'halt_at_pct|degrade_at_pct'
    then 'PROBE FAILED: fn_ai_route still reads a halt or degrade threshold'
  when (public.fn_ai_route(null, 'marketing', null, null, false, null, null) ? 'halted')
    then 'PROBE FAILED: fn_ai_route still answers halted'
  when coalesce((public.fn_seat_deliberation_budget('marketing', 'ceo')->>'ok')::boolean, false) is not true
    then 'PROBE FAILED: the registered marketing -> ceo pair is refused'
  else 'PROBE OK' end as verdict;
