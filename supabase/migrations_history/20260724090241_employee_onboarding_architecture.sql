-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260724090241   name: employee_onboarding_architecture
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============================================================================
-- EMPLOYEE ONBOARDING & CONTINUOUS-LEARNING ARCHITECTURE (2026-07-24)
-- L1 company | L2 profession | L3 live state | L4 organizational experience
-- Onboarding lifecycle: onboarding -> probation -> certified -> recert_due
-- ============================================================================

-- 1) Layer classification on the knowledge store
alter table agent_knowledge add column if not exists layer text
  check (layer in ('company','profession','state','experience'));
update agent_knowledge set layer='company'    where layer is null and agent_key='_global';
update agent_knowledge set layer='state'      where agent_key='_global' and topic in ('company:self_knowledge','Pricing & fees (LIVE — auto-synced)','Company assets (auto-synced from Dropbox)');
update agent_knowledge set layer='experience' where topic like 'Closed-case lesson%';
update agent_knowledge set layer='profession' where layer is null;
alter table agent_knowledge alter column layer set default 'profession';

-- 2) Exam bank gains layer + agent scoping (existing canon questions = L1, all agents)
alter table canon_eval_questions add column if not exists layer text default 'company'
  check (layer in ('company','profession','state','experience'));
alter table canon_eval_questions add column if not exists agent_key text;
update canon_eval_questions set layer='company' where layer is null;

-- 3) Onboarding lifecycle per executive
create table if not exists org_onboarding (
  agent_key text primary key,
  department text,
  status text not null default 'onboarding'
    check (status in ('onboarding','probation','certified','recert_due')),
  l1_score numeric, l1_at timestamptz,
  l2_score numeric, l2_at timestamptz,
  l3_score numeric, l3_at timestamptz,
  l4_score numeric, l4_at timestamptz,
  pass_threshold numeric not null default 85,
  probation_reviews_done int not null default 0,
  probation_reviews_required int not null default 3,
  certified_at timestamptz,
  recert_due date,
  note text,
  updated_at timestamptz default now()
);
alter table org_onboarding enable row level security;

-- 4) UPGRADE the live context assembler in place (same signature: text in/out,
--    every agent runtime adopts the four-layer employee context immediately).
create or replace function public.fn_agent_context(p_agent_key text default null, p_max_chars integer default 9000)
returns text language plpgsql stable security definer set search_path to 'public','pg_temp'
as $function$
declare out text := ''; r record; piece text; cap int; own_cap int;
        v_dept text; v_role text; v_charter text; v_north text; v_health_fn text;
        v_status text; v_state jsonb; v_l4 text := '';
begin
  cap := greatest(coalesce(p_max_chars,9000), 22000);
  own_cap := least(cap/2, 6000);

  -- IDENTITY & EMPLOYMENT (who you are at this company, and how to think)
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
      ||'POSTURE: You are a senior executive employee, not a document-search AI. You have internalized the four knowledge layers below (COMPANY, PROFESSION, LIVE STATE, EXPERIENCE). Reason from executive judgment first; use the layers to VERIFY facts (prices, laws, figures), never as a substitute for thinking. Ground each material claim in a layer. Quote operational numbers ONLY from LIVE STATE, never from memory or prose. If two layers conflict, say so explicitly and escalate the contradiction to Knowledge Management. If your employment status is not certified, mark your outputs as provisional.'||E'\n\n';
  end if;

  -- L2 PROFESSION: the agent's OWN expertise, guaranteed a reserved slice.
  if p_agent_key is not null then
    out := out || '# LAYER 2 - YOUR PROFESSIONAL EXPERTISE'||E'\n\n';
    for r in select topic,content from agent_knowledge
             where agent_key=p_agent_key and coalesce(layer,'profession') in ('profession','state')
             order by priority desc nulls last, updated_at desc loop
      piece := '## '||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
      if length(out)+length(piece) <= own_cap + 2200 then out := out||piece; end if;
    end loop;
  end if;

  -- L1 COMPANY: critical shared canon (priority >= 90) then remaining canon.
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

  -- L3 LIVE STATE: the department's health function, executed now.
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

  -- L4 ORGANIZATIONAL EXPERIENCE: promoted lessons + lint-clean important memory.
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

-- 5) Probation gate for runtimes
create or replace function fn_onboarding_gate(p_agent text)
returns jsonb language sql security definer set search_path to 'public','pg_temp'
as $fn$
  select coalesce(
    (select jsonb_build_object('agent',agent_key,'status',status,
       'outputs_need_review', status <> 'certified',
       'reason', case status
         when 'certified' then 'fully onboarded'
         when 'probation' then 'passed exams; first '||probation_reviews_required||' outputs need founder/lead review ('||probation_reviews_done||' done)'
         when 'recert_due' then 'certification expired; re-examination pending'
         else 'not yet examined on the four knowledge layers' end)
     from org_onboarding where agent_key=p_agent),
    jsonb_build_object('agent',p_agent,'status','unknown','outputs_need_review',true,
      'reason','no onboarding record - treat as uncertified'));
$fn$;
revoke execute on function fn_onboarding_gate(text) from public, anon, authenticated;

-- 6) Exam-result ingestion + certification state machine
create or replace function fn_onboarding_ingest_runs()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare r record; v_updated int := 0;
begin
  for r in select agent, score_pct, run_at from canon_eval_runs where run_at > now() - interval '8 days' loop
    insert into org_onboarding(agent_key, department)
      values (r.agent, (select department from org_agents where agent_key=r.agent))
      on conflict (agent_key) do nothing;
    update org_onboarding set l1_score=r.score_pct, l1_at=r.run_at, updated_at=now()
      where agent_key=r.agent and (l1_at is null or l1_at < r.run_at);
    v_updated := v_updated + 1;
  end loop;
  update org_onboarding o set status='probation', updated_at=now()
    where o.status in ('onboarding','recert_due')
      and o.l1_score >= o.pass_threshold and o.l2_score >= o.pass_threshold;
  update org_onboarding o set status='certified', certified_at=now(),
      recert_due=(now()+interval '90 days')::date, updated_at=now()
    where o.status='probation' and o.probation_reviews_done >= o.probation_reviews_required;
  update org_onboarding o set status='recert_due', updated_at=now()
    where o.status='certified' and o.recert_due is not null and o.recert_due < current_date;
  return jsonb_build_object('runs_ingested', v_updated);
end $fn$;
revoke execute on function fn_onboarding_ingest_runs() from public, anon, authenticated;

-- 7) Rotating re-certification: examine the executive whose evidence is oldest
create or replace function fn_recert_rotate()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare v_agent text; v_secret text;
begin
  perform fn_onboarding_ingest_runs();
  select agent_key into v_agent from org_onboarding
    order by coalesce(greatest(l1_at,l2_at,l3_at,l4_at), 'epoch'::timestamptz) asc limit 1;
  if v_agent is null then return jsonb_build_object('skipped','no onboarding records'); end if;
  select value into v_secret from app_secrets where key='inbound_secret';
  perform net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/canon_eval',
    body:=jsonb_build_object('__secret', v_secret, 'agent', v_agent, 'limit', 8),
    headers:='{"Content-Type":"application/json"}'::jsonb, timeout_milliseconds:=150000);
  return jsonb_build_object('examined', v_agent);
end $fn$;
revoke execute on function fn_recert_rotate() from public, anon, authenticated;

-- 8) Governed experience promotion: stable, lint-clean org lessons become Layer 4
create or replace function fn_experience_promote()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare r record; v_promoted int:=0; v_rejected int:=0; v_agent text;
begin
  for r in select m.* from org_memory m
           where m.active and m.kind='lesson'
             and m.created_at < now() - interval '7 days'
             and not exists (select 1 from agent_knowledge k
                             where k.layer='experience' and k.topic like '%[org#'||m.id||']')
  loop
    if exists (select 1 from policy_rules p where p.active and r.content ~* p.forbid_regex) then
      v_rejected := v_rejected + 1;
      insert into founder_alerts(level,event,detail,channel)
        values ('warn','experience_promotion_blocked',
                'org_memory lesson #'||r.id||' contradicts policy_rules and was NOT promoted: '||left(r.content,300),'system');
    else
      select coalesce(d.brain_agent,'_global') into v_agent from org_departments d where d.dept_key=r.scope;
      insert into agent_knowledge(agent_key, topic, content, priority, layer)
        values (coalesce(v_agent,'_global'),
                'Experience: '||left(regexp_replace(r.content,'^\[[a-z]+\]\s*',''),60)||' [org#'||r.id||']',
                r.content, 5, 'experience');
      v_promoted := v_promoted + 1;
    end if;
  end loop;
  return jsonb_build_object('promoted', v_promoted, 'lint_rejected', v_rejected);
end $fn$;
revoke execute on function fn_experience_promote() from public, anon, authenticated;
