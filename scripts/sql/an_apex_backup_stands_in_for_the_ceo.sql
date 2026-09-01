-- AN APEX BACKUP STANDS IN FOR THE CEO (org audit D11).
--
-- MEASURED. fn_should_escalate resolves the apex first: an active agent with manager_key NULL (only
-- the CEO) routes to the founder. But there was no backup for the apex — when an escalation did not
-- resolve up the line (no configured owner, no available manager), it fell through to the GENERIC
-- executive fallback (exec brain_agent, which is 'brief'/chief_of_staff), i.e. whichever exec member
-- the fallback happened to name, rather than a designated deputy-apex.
--
-- THIS FILE adds a decision_policy key apex_backup (the COO, the CEO's operational number-two) and has
-- fn_should_escalate consult it BEFORE the generic exec fallback. The CEO still routes to the founder
-- (apex_to_founder is unchanged and resolved first); this only changes where an otherwise-unresolved
-- apex-level escalation lands — now on a named backup instead of a fallback string.
--
--   node scripts/apply_sql.mjs scripts/sql/an_apex_backup_stands_in_for_the_ceo.sql --apply --ddl

begin;

insert into public.decision_policy (key, value, description, updated_at)
values ('apex_backup', to_jsonb('ops_director'::text),
        'The deputy-apex that stands in when an escalation cannot resolve up the line and would '
        'otherwise fall to the generic executive fallback. The COO (chief_operating_officer / '
        'ops_director) is the CEO''s operational number-two. The CEO itself still routes to the '
        'founder (apex_to_founder, resolved first).', now())
on conflict (key) do update set value = excluded.value, description = excluded.description, updated_at = now();

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
  REPORTING_KINDS constant text[] := array['handoff','incident','report_task'];
  c_money boolean := coalesce((ctx->>'moves_money')::boolean,false);
  trg text;
  c_actor text := nullif(btrim(coalesce(ctx->>'actor', ctx->>'agent_key', '')), '');
  v_route text; v_basis text; v_note text;
  v_mgr text; v_mgr_dept text; v_pick jsonb;
  v_actor_res text;
  v_apex_backup text;   -- D11: the named deputy-apex
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

  -- THE APEX ESCALATES TO THE FOUNDER. Resolved FIRST: the active agent with no manager_key (the CEO)
  -- reports to the founder, not to another agent.
  if c_actor is not null then
    v_actor_res := coalesce(public.fn_org_agent_resolve(c_actor), c_actor);
    perform 1 from org_agents a where a.agent_key = v_actor_res and a.active and a.manager_key is null;
    if found then
      v_route := 'founder'; v_basis := 'apex_to_founder';
      v_note  := 'the company apex ('||v_actor_res||') has no manager; the only party above it is the '
              || 'founder, whose major-issue channel is the single human signal the design allows';
    end if;
  end if;

  -- RESOLVE THE PARTY. The configured review_owner (employee / staffed department / title).
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

  -- THE REPORTING LINE. The actor's manager (active AND available), else the standing deputy.
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
        if v_route = c_actor then v_route := null; end if;
        if v_route is not null then
          v_basis := 'reporting_line_delegated';
          v_note  := 'manager '||v_mgr||' is unavailable; '
                  || coalesce(v_pick->>'basis','delegation_rule standing deputy');
        end if;
      end if;
    end if;
  end if;

  -- D11: THE APEX BACKUP. Before the generic executive fallback, a named deputy-apex (the COO) takes
  -- an escalation that did not resolve up the line, so an apex-level item reaches a designated backup
  -- rather than whichever exec member the fallback names. Configured in decision_policy.apex_backup.
  if v_route is null then
    select value #>> '{}' into v_apex_backup from decision_policy where key='apex_backup';
    if v_apex_backup is not null and btrim(v_apex_backup) <> '' then
      select a.agent_key into v_route from org_agents a
       where a.active and a.agent_key = coalesce(public.fn_org_agent_resolve(v_apex_backup), v_apex_backup)
       limit 1;
      if v_route is not null then
        v_basis := 'apex_backup';
        v_note := 'no manager or configured owner resolved; the designated apex backup ('||v_route
               || ') stands in before the generic executive fallback';
      end if;
    end if;
  end if;

  -- The configured owner names nobody and no apex backup resolved. Escalate to the executive
  -- department's own head, recorded as a fallback so the configuration gap stays visible.
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

  if v_route is null then
    v_route := owner; v_basis := 'unresolved';
    v_note := 'configured review_owner "'||coalesce(owner,'(unset)')||'" resolves to no party in the '
           || 'org model, and no active executive employee was available to take it';
  end if;

  return jsonb_build_object(
    'escalate', array_length(reasons,1) is not null,
    'reasons', to_jsonb(reasons),
    'route_to', v_route,
    'route_basis', v_basis,
    'route_note', v_note,
    'route_owner_configured', owner);
end $function$;

commit;
