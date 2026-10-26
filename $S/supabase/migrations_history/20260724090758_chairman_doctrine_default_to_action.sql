-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724090758   name: chairman_doctrine_default_to_action
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============================================================================
-- CHAIRMAN'S OPERATING DOCTRINE (2026-07-24): employees, not assistants.
-- Default to action within authority; escalate only outside-authority or
-- material-risk decisions. Founder-instructed change to the autonomy framework.
-- ============================================================================

-- 1) fn_autonomy_class: carve out policy-bounded within-window refunds from the
--    blanket money rail (the refund flow itself still enforces windows, notice
--    steps and working-day arithmetic; outside-policy refunds remain founder).
create or replace function public.fn_autonomy_class(p_kind text, p_target_table text, p_recommendation text)
 returns text language plpgsql stable set search_path to 'public','pg_catalog'
as $function$
declare pol jsonb; d text;
begin
  -- Policy-bounded carve-out (chairman doctrine 2026-07-24): a refund fully inside
  -- the published policy window is routine work, not an executive decision.
  if p_kind = 'refund_within_window' then return 'ack'; end if;
  -- HARD RAILS: money, destructive, and supplier approval can never be auto-cleared by policy.
  if p_kind ~* 'refund|payout|payment|withdraw|transfer|invoice_pay|money|charge' then return 'founder'; end if;
  if p_kind ~* 'delete|purge|remove_record' and coalesce(p_target_table,'') in ('leads','customers') then return 'founder'; end if;
  if p_kind='approve_supplier' and coalesce(p_recommendation,'')='approve' then return 'clean_supplier'; end if;
  if p_kind='approve_supplier' then return 'founder'; end if;
  -- POLICY: founder-editable per-kind disposition.
  select value into pol from public.decision_policy where key='action_autonomy';
  d := pol->>p_kind;
  if d in ('ack','founder','keep') then return d; end if;
  -- LEGACY FALLBACK
  if p_kind in ('security_alert','compliance_update','incident','supply_health','sla_no_supply') then return 'ack'; end if;
  return 'keep';
end $function$;

-- 2) Posture: add default-to-action to every executive's identity block.
--    (Only the POSTURE string changes; assembly logic is identical.)
create or replace function public.fn_agent_context(p_agent_key text default null, p_max_chars integer default 9000)
returns text language plpgsql stable security definer set search_path to 'public','pg_temp'
as $function$
declare out text := ''; r record; piece text; cap int; own_cap int;
        v_dept text; v_role text; v_charter text; v_north text; v_health_fn text;
        v_status text; v_state jsonb; v_l4 text := '';
begin
  cap := greatest(coalesce(p_max_chars,9000), 22000);
  own_cap := least(cap/2, 6000);
  if p_agent_key is not null then
    select a.department, a.role into v_dept, v_role from org_agents a where a.agent_key=p_agent_key;
    select d.charter, d.north_star, d.health_fn into v_charter, v_north, v_health_fn
      from org_departments d where d.dept_key=v_dept;
    select status into v_status from org_onboarding where agent_key=p_agent_key;
    out := out || '# YOUR IDENTITY AT QUOTESDONE'||E'\n'
      ||'You are '||coalesce(v_role, p_agent_key||' (senior specialist)')
      ||case when v_charter is not null then '. Department charter: '||v_charter else '' end
      ||case when v_north is not null then ' North star: '||v_north||'.' else '' end
      ||' Employment status: '||coalesce(v_status,'onboarding')||'.'||E'\n'
      ||'POSTURE: You are a senior executive employee, not an assistant. DEFAULT TO ACTION: if work falls within your delegated authority (org_authority tiers), execute it completely, then report the result - do not ask permission you already have. Proactively identify work from your charter and live state; do not wait for tasks. Escalate ONLY when an action exceeds your authority, carries material business risk, or hits a constitutional gate (money movement, identity/auth, security and secrets, destructive operations, legal judgment, the autonomy framework itself). Reason from executive judgment first; use the layers to VERIFY facts, never as a substitute for thinking. Quote operational numbers ONLY from LIVE STATE. If two layers conflict, say so explicitly and escalate the contradiction to Knowledge Management. Close every piece of work with the loop: measure the outcome, record the lesson, improve the playbook. If your employment status is not certified, mark your outputs as provisional.'||E'\n\n';
  end if;
  if p_agent_key is not null then
    out := out || '# LAYER 2 - YOUR PROFESSIONAL EXPERTISE'||E'\n\n';
    for r in select topic,content from agent_knowledge
             where agent_key=p_agent_key and coalesce(layer,'profession') in ('profession','state')
             order by priority desc nulls last, updated_at desc loop
      piece := '## '||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
      if length(out)+length(piece) <= own_cap + 2200 then out := out||piece; end if;
    end loop;
  end if;
  out := out || '# LAYER 1 - COMPANY KNOWLEDGE (authoritative; pricing marked LIVE overrides any other figure)'||E'\n\n';
  for r in select topic,content from agent_knowledge
           where agent_key='_global' and coalesce(priority,0)>=90 order by priority desc nulls last, updated_at desc loop
    piece := '## '||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
    if length(out)+length(piece) <= cap then out := out||piece; end if;
  end loop;
  for r in select topic,content from agent_knowledge
           where agent_key='_global' and coalesce(priority,0)<90 order by priority desc nulls last, updated_at desc loop
    piece := '## '||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
    if length(out)+length(piece) <= cap then out := out||piece; end if;
  end loop;
  if v_health_fn is not null then
    begin
      execute format('select %I()', v_health_fn) into v_state;
      piece := '# LAYER 3 - LIVE OPERATIONAL STATE (from '||v_health_fn||' at '||now()::timestamptz(0)||'; the ONLY valid source for operational numbers)'||E'\n'
               ||left(coalesce(v_state::text,'{}'), 2600)||E'\n\n';
      if length(out)+length(piece) <= cap + 3000 then out := out||piece; end if;
    exception when others then
      out := out || '# LAYER 3 - LIVE OPERATIONAL STATE unavailable ('||sqlerrm||'); do not quote operational numbers this turn.'||E'\n\n';
    end;
  end if;
  if p_agent_key is not null then
    for r in select topic, content from agent_knowledge
             where layer='experience' and agent_key in (p_agent_key,'_global')
             order by updated_at desc limit 12 loop
      v_l4 := v_l4 || '## '||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
    end loop;
    for r in select kind, content from agent_memory m
             where m.agent_key=p_agent_key and m.importance >= 5
               and not exists (select 1 from policy_rules p where p.active and m.content ~* p.forbid_regex)
             order by m.importance desc, m.created_at desc limit 8 loop
      v_l4 := v_l4 || '## memory ('||r.kind||')'||E'\n'||r.content||E'\n\n';
    end loop;
    if v_l4 <> '' then
      out := out || '# LAYER 4 - WHAT THIS ORGANIZATION HAS LEARNED'||E'\n\n'|| left(v_l4, 3500);
    end if;
  end if;
  return out;
end $function$;
