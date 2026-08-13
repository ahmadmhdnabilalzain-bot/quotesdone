-- THE RULE THAT STOPS A FAILED STRATEGY BEING REPEATED HAS NEVER HELD A STRATEGY
--
-- 51 agent_actions sit in needs_review on production, the oldest since 10 Aug 2026, and nothing
-- drains them. Two session briefs have called this an authority backlog — "a security decision,
-- not neglect". Measured, it is neither.
--
--   select kind, count(*), count(*) filter (where <the prior-failure predicate>)
--     from agent_actions where status='needs_review' group by kind;
--
--     handoff       35   held by the prior-failure rule: 32
--     strategy_rec   7   held by the prior-failure rule:  0
--     incident       1                                    0
--     report_task    1                                    0
--
-- The rule's own comment says what it is for: "A FAILED STRATEGY IS NOT REPEATED UNKNOWINGLY ...
-- If this action reads like something already tried that ended worse, it goes to a person instead
-- of through." It has held ZERO strategies and 32 handoffs.
--
-- WHY IT CANNOT NOT FIRE ON A HANDOFF. It matches an action's text against the headlines of
-- institutional_memory items graded 'worse', on three or more shared tokens of six characters or
-- more. Here is the oldest held row, with the memory it matched and the tokens they share:
--
--   action  "Handoff — Bundled scheduled_run failure cluster: day_conductor suspected root cause"
--   memory  "knowledge: test.failed on scheduled_run day_conductor"
--   shared  day_conductor, failed, scheduled_run
--
-- The action IS the report of that failure. A handoff that names a failure will always share its
-- vocabulary with the memory of that failure — that is a tautology, not a coincidence, and it means
-- the gate holds the remediation because the thing being remediated is remembered. Work reporting a
-- broken cron has been frozen for three days by the record that the cron broke.
--
-- THE FIX IS THE ONE THE RULE ALREADY IMPLIES. A handoff is not an attempt at anything; it is a
-- request that somebody look at something. An incident is a report. A report_task asks for a
-- report. None of them can repeat a strategy, so none of them is what this rule was written to
-- catch. Everything else stays subject to it — the list is an explicit exclusion of three
-- reporting kinds, so a NEW kind is held by default rather than silently exempted (an allow-list
-- with no third answer is how 24 action kinds went unrouted in this same estate).
--
-- WHAT THIS DOES NOT TOUCH. Every other reason fn_should_escalate can give still applies to a
-- handoff: the legal/financial/compliance triggers (two of the 51 are held by exactly that and
-- stay held), confidence floors, money thresholds, fraud score, and fn_authorize's RBAC check,
-- which is a separate call in trg_action_gate. This narrows ONE heuristic to the kinds it was
-- written for; it removes no gate.
--
-- AND THE FIELD THAT MADE IT UNDIAGNOSABLE. fn_should_escalate could not tell a strategy from a
-- handoff because trg_action_gate never passed the kind — it derived moves_money FROM the kind and
-- then dropped it. That is the same defect the comment beside 'actor' in that trigger already
-- describes: a field that is part of the context, not just of the ledger row.
--
-- Both are CREATE OR REPLACE, so the ACLs are preserved and no GRANT/REVOKE belongs here.

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

  -- RESOLVE THE PARTY. Four attempts, strongest first; each one is a party the org model contains.
  if owner is not null and btrim(owner) <> '' then
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
end $function$
;

CREATE OR REPLACE FUNCTION public.trg_action_gate()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare attrs jsonb; action text; esc jsonb; authz jsonb; blocked boolean:=false; reasons text[]:='{}'; amt numeric;
        v_sources jsonb := '[]'::jsonb; v_dl_id bigint;
        v_taken text; v_other text; v_why text; v_alts jsonb;
begin
  -- build context defensively (detail may be jsonb or text)
  begin
    attrs := case when jsonb_typeof(to_jsonb(NEW.detail)) = 'object' then to_jsonb(NEW.detail) else '{}'::jsonb end;
  exception when others then attrs := '{}'::jsonb; end;
  begin amt := nullif(attrs->>'amount_aed','')::numeric; if amt is null then amt := nullif(attrs->>'amount','')::numeric; end if; exception when others then amt := null; end;
  -- 'actor' IS PART OF THE CONTEXT, NOT JUST OF THE LEDGER ROW. NEW.agent was written to
  -- decision_log.actor and withheld from fn_should_escalate, so the router had nobody to route
  -- FROM and every one of these rows carried the same company-wide addressee. With it the
  -- escalation travels up the escalating employee's own reporting line.
  attrs := attrs || jsonb_build_object('amount_aed', amt, 'text', lower(coalesce(NEW.title,'')||' '||coalesce(NEW.recommendation,'')),
                                       'category', coalesce(attrs->>'category',''), 'moves_money', (lower(coalesce(NEW.kind,'')) ~ '(refund|payout|charge|payment|transfer)'),
                                       'actor', coalesce(NEW.agent,'agent'),
                                       -- KIND, FOR THE SAME REASON ACTOR IS HERE. fn_should_escalate
                                       -- has a rule that only makes sense for actions that ACT, and
                                       -- it could not tell a strategy from a handoff because the one
                                       -- field that says which is which was never passed.
                                       'kind', lower(coalesce(NEW.kind,'')));
  -- map action kind to an RBAC action
  action := case
    when lower(coalesce(NEW.kind,'')) ~ 'refund' then 'issue_refund'
    when lower(coalesce(NEW.kind,'')) ~ 'approve.*suppl|suppl.*approve|kyc' then 'approve_supplier'
    when lower(coalesce(NEW.kind,'')) ~ 'price|fee|commission' then 'edit_pricing'
    when lower(coalesce(NEW.kind,'')) ~ 'publish|post|content|blog|campaign' then 'publish_content'
    when lower(coalesce(NEW.kind,'')) ~ 'message|email|notify|send' then 'send_message'
    else 'run_agent_action' end;

  begin
    esc  := public.fn_should_escalate(attrs);
    authz:= public.fn_authorize(coalesce(NEW.agent,'agent'), action, attrs);
    if (esc->>'escalate')::boolean then blocked:=true; reasons := reasons || array(select jsonb_array_elements_text(coalesce(esc->'reasons','[]'))); end if;
    if not (authz->>'allowed')::boolean then blocked:=true; reasons := array_append(reasons, authz->>'reason'); end if;
  exception when others then blocked:=true; reasons := array_append(reasons,'gate error — held for review: '||sqlerrm); end;

  -- WHAT THIS DECISION WAS TAKEN ON. Each element is a retrieval that actually returned: if the
  -- call above raised, the variable is still NULL, nothing is appended, and the ledger row says so.
  if esc is not null then
    v_sources := v_sources || jsonb_build_array(jsonb_build_object(
      'kind', 'policy_check', 'ref', 'fn_should_escalate', 'result', esc));
  end if;
  if authz is not null then
    v_sources := v_sources || jsonb_build_array(jsonb_build_object(
      'kind', 'authority_check', 'ref', 'fn_authorize', 'result', authz));
  end if;

  -- enforce: a gated action can never be auto-approved; force human review
  if blocked and coalesce(NEW.status,'pending') in ('approved','auto','auto_approved','executed','done') then
    NEW.status := 'needs_review';
  elsif blocked and coalesce(NEW.status,'pending')='pending' then
    NEW.status := 'needs_review';
  end if;

  -- THE OPTION THAT WAS NOT TAKEN. Two outcomes were genuinely available and one was genuinely
  -- rejected; the reasons it lost are the ones already computed above, not a new narrative.
  v_taken := case when blocked then 'held_for_review' else 'permitted' end;
  v_other := case when blocked then 'permitted' else 'held_for_review' end;
  v_why := case when blocked
    then case when array_length(reasons,1) is null
              then 'the gate blocked without recording a reason, which is itself the finding'
              else array_to_string(reasons, ' | ') end
    else 'fn_should_escalate did not fire and fn_authorize allowed it, so there was no ground to hold it' end;
  v_alts := jsonb_build_array(
    jsonb_build_object('option', v_taken, 'selected', true,
                       'basis', 'fn_should_escalate + fn_authorize on this action''s own context'),
    jsonb_build_object('option', v_other, 'selected', false, 'rejected_because', v_why));

  -- immutable audit
  begin
    insert into decision_log(actor,kind,ctx,decision,confidence,reasons,sources,route_to,alternatives)
    values (coalesce(NEW.agent,'agent'),'action_gate',
            jsonb_build_object('action',action,'kind',NEW.kind,'risk',NEW.risk,'attrs',attrs),
            case when blocked then 'held_for_review' else 'permitted' end,
            -- NEW.confidence, not a literal null. This trigger is named zzz_action_gate so it fires
            -- AFTER trg_governance_stamp, which is what stamps the 0.9 — see
            -- action_gate_runs_after_the_stamp.sql. Reading it any earlier reads a NULL.
            NEW.confidence,
            to_jsonb(reasons), v_sources, esc->>'route_to', v_alts)
    returning id into v_dl_id;
  exception when others then v_dl_id := null; end;

  NEW.decision_log_id := v_dl_id;
  return NEW;
end $function$
;
