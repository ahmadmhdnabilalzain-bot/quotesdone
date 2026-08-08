-- "Should I escalate?" must route to a NAMED PARTY, and until now it routed to a label.
--
-- Measured on production 6 Aug 2026: 1,101 of 1,101 escalations raised in 30 days carry
-- route_to = 'Secretary'. `select agent_key from org_agents where agent_key ilike '%secret%'
-- or title ilike '%secret%'` returns NULL across all 66 active employees, and there is no
-- org_departments row with that key. Every escalation this company has raised this month is
-- addressed to a party the org model does not contain — the escalation is recorded and reaches
-- nobody. decision_policy.review_owner is a LABEL; a label is not a party.
--
-- The owner is now RESOLVED before it is returned, in the same order comp-14-who-reviews resolves a
-- reviewer, and the ORDER matters: an active employee first, because a person is the strongest
-- answer; then a STAFFED department, because a department with no employees is the same nobody the
-- label was; then an active employee whose TITLE is that label, which is how a role name like
-- 'Secretary' would legitimately resolve if the company ever hires one; and finally the executive
-- department's own head, because an escalation that reaches nobody is worse than one that reaches
-- the wrong desk.
--
-- If even that does not resolve, the configured label is returned UNCHANGED. That is deliberate:
-- the routing then still says exactly what the configuration says, and the scorer's per-row
-- resolution leg can see that it names nobody. Substituting a party the org does not contain would
-- hide the configuration gap, which is the defect this change exists to remove.
--
-- `route_basis` is added to the returned object so the ledger records HOW the party was found —
-- trg_action_gate stores this whole result in decision_log.sources as the 'policy_check' element,
-- so a routing that fell back is visible after the fact instead of being indistinguishable from one
-- that resolved cleanly. Existing callers read only ->>'route_to' and ->>'escalate'; adding a key
-- cannot change what they see. The signature is unchanged — a different argument list would make an
-- OVERLOAD, and trg_action_gate would keep calling the old body.
create or replace function public.fn_should_escalate(ctx jsonb)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  reasons text[] := '{}';
  conf_min numeric; fin_review numeric; auto_max numeric; fraud_max numeric;
  legal jsonb; sens jsonb; owner text;
  c_conf numeric := nullif(ctx->>'confidence','')::numeric;
  c_amt  numeric := nullif(ctx->>'amount_aed','')::numeric;
  c_fraud numeric := nullif(ctx->>'fraud_score','')::numeric;
  c_cat  text := lower(coalesce(ctx->>'category',''));
  c_txt  text := lower(coalesce(ctx->>'text',''));
  c_money boolean := coalesce((ctx->>'moves_money')::boolean,false);
  trg text;
  v_route text; v_basis text; v_note text;
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
