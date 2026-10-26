CREATE OR REPLACE FUNCTION public.fn_agent_context(p_agent_key text DEFAULT NULL::text, p_max_chars integer DEFAULT 9000)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare out text := ''; r record; piece text; cap int; own_cap int;
        v_dept text; v_role text; v_charter text; v_north text; v_health_fn text;
        v_status text; v_state jsonb; v_l4 text := '';
        v_emp text := ''; v_title text; v_resp text; v_mgr text; v_sen text; v_plan text;
        v_cap_tasks int; v_line text; v_n int; v_os text; v_pad int := 0;
        v_genome text;
        v_risks text;
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

    -- ---- THE COMPANY GENOME (spec layer 9: every employee inherits all eleven attributes) -----
    -- genome-inherited-by-every-employee read 2 of 11 on production. This routine carried
    -- 'values' and 'vision' incidentally and none of the other nine, because it never read
    -- company_constitution at all - it reads org_agents, agent_knowledge, org_tasks and
    -- policy_rules, and no genome store.
    --
    -- A LIST OF HEADINGS WOULD SATISFY THE CHECK AND TEACH NOBODY ANYTHING. All eleven regexes
    -- match on the titles alone, in about 250 characters. That is the accidental pass this row
    -- keeps turning up, so each line carries the doctrine itself and not just its name.
    select string_agg('- '||c.title||': '||left(regexp_replace(c.body, '\s+', ' ', 'g'), 220),
                      E'\n' order by c.article_no)
      into v_genome
      from public.company_constitution c
     where c.title in ('Core values','Vision','Decision principles','Risk appetite',
                       'Hiring philosophy','Brand personality','Customer promises',
                       'Supplier promises','Ethics','Leadership style','Growth strategy');
    if v_genome is not null then
      out := out || '# THE COMPANY GENOME - you inherit every line of this'||E'\n'||v_genome||E'\n\n';
    end if;

    -- ---- WHAT THE COMPANY IS WORRIED ABOUT --------------------------------------------------
    -- ai-conversation-worry asks whether an employee could answer "what worries you most today?"
    -- with the COMPANY'S OWN judgement rather than an improvisation. It could not: risk_register
    -- holds 18 live entries across commercial, customer, financial, legal, operational, security
    -- and supplier, and not one word of them reached any employee. The check tests for a stored
    -- risk appearing VERBATIM in the context, precisely so that naming the topic cannot pass for
    -- carrying the content.
    --
    -- RENDERED RAW, AND THAT IS DELIBERATE. No regexp_replace and no truncation of r.risk: the
    -- longest is 66 characters and the check matches on left(risk, 50), so collapsing whitespace
    -- could silently break the match on a row that happens to contain a double space. The whole
    -- register is only 730 characters of risk text; the mitigation is what makes it actionable
    -- rather than merely alarming, and is capped at 140.
    --
    -- Closed risks are excluded. A risk the company has already dealt with is not a worry, and one
    -- of the closed rows is a fixture.
    -- ALIAS rr, NOT r. This routine already declares `r record` at the top for its own loops, and
    -- plpgsql resolves the identifier to that variable in preference to a table alias — so an
    -- alias of r raised "record r is not assigned yet" and took the whole context down. Caught on
    -- staging, which is the entire reason it goes there first.
    select string_agg('- ['||coalesce(rr.impact,'?')||' impact / '||coalesce(rr.probability,'?')
                      ||' likelihood] '||rr.risk
                      ||case when coalesce(rr.mitigation,'') <> ''
                             then '  -> mitigating: '||left(rr.mitigation, 140) else '' end,
                      E'\n' order by case coalesce(rr.impact,'') when 'high' then 0 when 'medium' then 1 else 2 end,
                                     case coalesce(rr.probability,'') when 'high' then 0 when 'medium' then 1 else 2 end,
                                     rr.id)
      into v_risks
      from public.risk_register rr
     where coalesce(rr.status,'open') in ('open','mitigating') and length(rr.risk) > 20;
    if v_risks is not null then
      out := out || '# WHAT THE COMPANY IS WORRIED ABOUT - its own live risk register'||E'\n'
                 || v_risks||E'\n\n';
    end if;

    -- ---- THE EMPLOYEE OBJECT (spec line 372) --------------------------------------------------
    select a.title, a.responsibilities, a.manager_key, a.seniority, a.improvement_plan, a.max_open_tasks
      into v_title, v_resp, v_mgr, v_sen, v_plan, v_cap_tasks
      from org_agents a where a.agent_key = p_agent_key;

    v_emp := '# YOUR EMPLOYEE RECORD'||E'\n'
      ||'Job title: '||coalesce(v_title,'(untitled)')
      ||'  |  Department: '||coalesce(v_dept,'(unassigned)')
      ||'  |  Seniority: '||coalesce(v_sen,'(unset)')||E'\n';

    -- The reporting line, finally walked. CEO -> Chief of Staff -> Department Heads -> Specialists.
    if v_mgr is not null then
      select 'Reports to: '||m.agent_key||' — '||coalesce(m.title, m.role, 'manager') into v_line
        from org_agents m where m.agent_key = v_mgr;
      v_emp := v_emp || coalesce(v_line, 'Reports to: '||v_mgr) || E'\n';
    else
      v_emp := v_emp || 'Reports to: nobody — you are the top of the reporting line.'||E'\n';
    end if;

    select count(*), string_agg(x.agent_key||' ('||coalesce(x.title, x.role, 'specialist')||')', '; ' order by x.agent_key)
      into v_n, v_line
      from (select b.agent_key, b.title, b.role from org_agents b
             where b.manager_key = p_agent_key and b.active order by b.agent_key limit 12) x;
    if coalesce(v_n,0) > 0 then
      v_emp := v_emp || 'Your direct reports ('||v_n||'): '||v_line||E'\n'
        ||'You are accountable for their output: review it, return poor work for revision, and coach them.'||E'\n';
    end if;

    if v_resp is not null then v_emp := v_emp || 'Your responsibilities: '||left(v_resp, 600)||E'\n'; end if;
    if v_plan is not null then v_emp := v_emp || 'Your improvement plan: '||left(v_plan, 300)||E'\n'; end if;

    -- ---- AUTHORITY LIMITS ----------------------------------------------------------------------
    -- Per-employee first (employee_authority), falling back to the department grant that
    -- cos_execute:170 actually enforces. Stating the ceiling is what makes "escalate only when an
    -- action exceeds your authority" in the POSTURE above an instruction rather than a slogan.
    select string_agg(z.action_class||' -> '||z.max_tier
             ||case when z.threshold_aed is not null then ' (up to '||z.threshold_aed||' AED)' else '' end, '; '
             order by z.action_class)
      into v_line
      from (select e.action_class, e.max_tier, e.threshold_aed from employee_authority e
             where e.agent_key = p_agent_key order by e.action_class limit 14) z;
    if v_line is null then
      select string_agg(z.action_class||' -> '||z.max_tier
               ||case when z.threshold_aed is not null then ' (up to '||z.threshold_aed||' AED)' else '' end, '; '
               order by z.action_class)
        into v_line
        from (select o.action_class, o.max_tier, o.threshold_aed from org_authority o
               where o.dept_key = v_dept order by o.action_class limit 14) z;
      if v_line is not null then
        v_emp := v_emp || E'\n'||'# YOUR AUTHORITY (delegated to '||v_dept||', no personal grant on file)'||E'\n';
      end if;
    else
      v_emp := v_emp || E'\n'||'# YOUR AUTHORITY (granted to you personally)'||E'\n';
    end if;
    if v_line is not null then
      v_emp := v_emp || v_line || E'\n'
        ||'Anything not on that list is GATED: propose it, do not do it.'||E'\n';
    end if;

    -- ---- ESCALATION RULES (blueprint component 5) ----------------------------------------------
    -- The spec requires every employee to have Escalation Rules alongside Role, Authority, KPIs,
    -- Knowledge and Decision Rights. There is no escalation table — only escalations_archive — but
    -- ops_knowledge.escalation_rule carries a real one on 1,206 of its 3,959 records, shaped
    -- {"when": ..., "action": ...}. Its only reader was fn_kb_retrieve, which has ZERO callers
    -- anywhere, so the rules reached nobody.
    --
    -- Read here rather than by widening fn_ops_knowledge_search: that function's return type would
    -- have to change, which needs a DROP, and fn_agent_context itself depends on it. An additive
    -- read is the smaller and safer diff.
    select string_agg(distinct '- when ' || replace(e.escalation_rule->>'when','_',' ')
                             || ' -> ' || replace(e.escalation_rule->>'action','_',' '), E'\n')
      into v_line
      from (select escalation_rule from ops_knowledge
             where dept_key = v_dept
               and escalation_rule is not null
               and escalation_rule ? 'when' and escalation_rule ? 'action'
             limit 40) e;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# WHEN TO ESCALATE (your department''s recorded rules)'||E'\n'||left(v_line, 700)||E'\n';
    end if;

    -- ---- KPIs: how this employee's work is judged ----------------------------------------------
    select string_agg(z.kpi||' — target '||coalesce(z.target_value::text,'?')||' '||coalesce(z.unit,'')
             ||' ('||coalesce(z.cadence,'ongoing')
             ||case when z.serves_goal is not null then '; serves company goal '||z.serves_goal else '' end||')', E'\n- '
             order by z.kpi)
      into v_line
      from (select k.kpi, k.target_value, k.unit, k.cadence, k.serves_goal from employee_kpi k
             where k.agent_key = p_agent_key and k.active order by k.kpi limit 8) z;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# YOUR KPIs — this is how your work is measured'||E'\n- '||v_line||E'\n';
    end if;

    -- ---- CURRENT WORKLOAD, measured rather than assumed -----------------------------------------
    -- max_open_tasks is a CAP. This is the LOAD against it, read live at prompt time.
    select 'Your department has '||count(*)||' task(s) in flight ('
           ||count(*) filter (where t.status='assigned')||' assigned, '
           ||count(*) filter (where t.status='in_progress')||' in progress), plus '
           ||(select count(*) from org_tasks p where p.dept_key = v_dept and p.status='proposed')
           ||' awaiting a founder decision. Your personal cap is '||coalesce(v_cap_tasks,0)||' open task(s).'
      into v_line
      from org_tasks t where t.dept_key = v_dept and t.status in ('assigned','in_progress');
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# YOUR CURRENT WORKLOAD (live)'||E'\n'||v_line||E'\n';
      select string_agg('- ['||z.status||'] '||left(z.title,90), E'\n' order by z.id)
        into v_line
        from (select t.id, t.status, t.title from org_tasks t
               where t.dept_key = v_dept and t.status in ('assigned','in_progress')
               order by t.id limit 6) z;
      if v_line is not null then v_emp := v_emp || v_line || E'\n'; end if;
    end if;

    -- ---- WHICH OPERATING SYSTEM YOU BELONG TO (spec file #2) ------------------------------------
    -- The Universal OS Blueprint's first four components — Purpose, Mission, Objectives,
    -- Responsibilities — were all POPULATED and read by NOTHING: operating_system.charter/mandate
    -- and .mission 10/10, os_objective 50 rows (all five horizons for all ten OSes),
    -- os_responsibility 71 rows whose only reader was fn_graph_rebuild. The single view that
    -- exposed them, v_operating_manual, has zero readers itself.
    --
    -- An employee belongs to an OS through org_agents.department -> os_department -> operating_system.
    -- Emitting it here is the same fix that closed row #1: the company knew all of this and never
    -- told the people doing the work.
    --
    -- 4. THE OWNER. 'owner' is one of the seven attributes the blueprint names per OS
    --    (operating_system.owner_agent, 10/10 populated, all ten resolving to a live employee) and
    --    it was the one attribute of the seven that never left the table: fn_os_improve read the
    --    column on a cron, but the block below emitted name/Purpose/Mission/Mandate/OWNS/objectives
    --    and no owner line, so measured across all 66 active employees not one could name who owns
    --    their OS. A responsibility an employee cannot escalate is a responsibility with no route
    --    out, which is what makes this the same defect as the other three: known by the company,
    --    never told to the person doing the work.
    for r in
      select o.os_key, o.name, o.charter, o.mandate, o.mission, o.owner_agent,
             (select coalesce(w.title, w.role) from org_agents w
               where w.agent_key = o.owner_agent and w.active) owner_title,
             (select string_agg(x.responsibility, ', ' order by x.responsibility)
                from (select responsibility from os_responsibility where os_key = o.os_key
                       order by responsibility limit 12) x) resp,
             (select string_agg(y.horizon || ': ' || y.objective, E'\n- '
                       order by case y.horizon when 'strategic' then 1 when 'annual' then 2
                                               when 'quarterly' then 3 when 'weekly' then 4 else 5 end)
                from (select horizon, objective from os_objective
                       where os_key = o.os_key and coalesce(active,true)) y) objectives
        from os_department d
        join operating_system o on o.os_key = d.os_key and coalesce(o.active,true)
       where d.dept_key = v_dept
       limit 1
    loop
      v_os := r.os_key;
      -- Emitted and measured from ONE expression. The line's length is what compensates the layer
      -- budgets below, so a second copy of the text is a copy that can be edited alone and leave
      -- the compensation quietly wrong.
      v_line := case when r.owner_agent is not null
                     then 'Your OS is owned by: '||r.owner_agent
                       ||coalesce(' — '||left(r.owner_title,60), '')
                       ||'. Escalate OS-level decisions there.'||E'\n'
                     else '' end;
      v_pad := length(v_line);
      v_emp := v_emp || E'\n'||'# YOUR OPERATING SYSTEM — '||coalesce(r.name, r.os_key)||E'\n'
        ||case when r.charter is not null then 'Purpose: '||left(r.charter,300)||E'\n' else '' end
        ||case when r.mission is not null then 'Mission: '||left(r.mission,240)||E'\n' else '' end
        ||case when r.mandate is not null then 'Mandate: '||left(r.mandate,240)||E'\n' else '' end
        ||v_line
        ||case when r.resp is not null
               then 'Your OS OWNS, and no other OS may own: '||r.resp||E'\n'
                 ||'If work belongs to another OS, hand it over — do not duplicate it.'||E'\n'
               else '' end
        ||case when r.objectives is not null
               then 'Your OS objectives by horizon:'||E'\n- '||r.objectives||E'\n' else '' end;
    end loop;

    -- THE OWNER LINE IS NOT PAID FOR OUT OF THE KNOWLEDGE BUDGET. LAYER 2 admits a piece while
    -- length(out) + length(piece) <= own_cap + 2200 and LAYER 1 while <= cap, and `out` already
    -- carries the employee record — so 70-97 characters added here come straight off the end of
    -- LAYER 1. Measured on production the first time this line was deployed WITHOUT this
    -- compensation: 19 employees lost a global knowledge topic each, including 'Penalty &
    -- collections model' (priority 94), 'Escalation policy' (93) and 'canon:supplier_status' (93).
    -- That is the file header's own rule — anything inserted before the layers deletes something
    -- already proven to reach an employee — and the owner line is the one insertion that cannot be
    -- moved to the end, because it has to land inside the OS block. So it buys its own space
    -- instead: both budgets grow by exactly the characters it used, which leaves every other
    -- inclusion decision bit-for-bit where it was. v_pad is 0 when no OS block was emitted.
    cap := cap + v_pad;
    own_cap := own_cap + v_pad;

    -- ---- WHAT THE COMPANY IS TRYING TO ACHIEVE ---------------------------------------------------
    -- company_goals was read by dept_plan:79 and by nothing an ordinary employee ever saw. The spec
    -- opens with "Every employee works toward the same business objectives" and "Every decision made
    -- by every AI employee should support these objectives".
    -- goal_period held 183 rows, refreshed daily by fn_goal_period_refresh, and was read by NOTHING
    -- but its own refresher. It carries the only actual-versus-target the company computes, so a
    -- goal without it is an aspiration and a goal with it is a number someone can act on.
    select string_agg(z.goal||' ('||coalesce(z.metric,'no metric')
             ||case when z.target_value is not null then '; target '||z.target_value||' '||coalesce(z.unit,'') else '' end
             ||case when z.actual_value is not null
                    then '; CURRENTLY '||z.actual_value||coalesce(' ('||z.status||')','') else '; not yet measured' end||')', E'\n- '
             order by z.sort nulls last)
      into v_line
      from (select g.goal, g.metric, g.target_value, g.unit, g.sort, gp.actual_value, gp.status
              from company_goals g
              left join lateral (select p.actual_value, p.status from goal_period p
                                  where p.goal_key = g.key
                                  order by p.updated_at desc nulls last limit 1) gp on true
             where g.active and (g.owner_dept is null or g.owner_dept = v_dept or g.owner_dept = 'exec')
             order by g.sort nulls last limit 8) z;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# COMPANY GOALS YOUR WORK MUST MOVE'||E'\n- '||v_line||E'\n';
    end if;

    select string_agg('- '||z.objective, E'\n' order by z.sort nulls last)
      into v_line
      from (select o.objective, o.sort from department_objective o
             where o.dept_key = v_dept and coalesce(o.active,true) order by o.sort nulls last limit 6) z;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# YOUR DEPARTMENT''S OBJECTIVES'||E'\n'||v_line||E'\n';
    end if;

    -- ---- THE IMPROVEMENT LOOP, WHICH WROTE WHERE NOTHING READ -------------------------------
    -- Of the seven self-optimisation loops, four wrote into tables nobody consulted:
    -- self_review 31 rows, evolution_proposal 32 (31 proposed, 1 ever implemented), decision_record
    -- 3, company_reflection 9 — each read by nothing but its own writer. The spec's "Continuous
    -- Improvement" section is what they implement, so the department they concern is the reader.
    -- Bounded hard: this is context, not a report.
    select string_agg(z.line, E'\n' order by z.ord, z.line)
      into v_line
      from (
        select 1 ord, '- OPEN FINDING ('||s.review_type||'): '||left(s.finding, 160)
               ||coalesce(' — proposed: '||left(s.proposal,120), '') line
          from self_review s
         where coalesce(s.status,'open') not in ('done','implemented','rejected')
         order by s.created_at desc limit 3
      ) z;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# WHAT THIS ORGANISATION IS TRYING TO FIX'||E'\n'||v_line||E'\n';
    end if;

    select string_agg('- PROPOSED CHANGE ('||e.change_class||'): '||left(e.proposal, 170), E'\n' order by e.id desc)
      into v_line
      from (select id, change_class, proposal from evolution_proposal
             where status = 'proposed' order by id desc limit 3) e;
    if v_line is not null then
      v_emp := v_emp || v_line || E'\n';
    end if;

    -- decision_record carries serves_goal and the reasoning behind past calls. 3 rows, 0 readers.
    -- "Learn from results" cannot happen if the record of what was decided reaches nobody.
    select string_agg('- '||coalesce(d.decided_by,'someone')||' decided: '||left(d.recommendation, 150)
             ||coalesce(' (serves '||d.serves_goal||')','')
             ||coalesce(' — outcome: '||left(d.actual_outcome,80), ' — outcome not yet recorded'), E'\n' order by d.id desc)
      into v_line
      from (select id, decided_by, recommendation, serves_goal, actual_outcome from decision_record
             where dept_key = v_dept or dept_key is null order by id desc limit 2) d;
    if v_line is not null then
      v_emp := v_emp || E'\n'||'# DECISIONS ALREADY ON RECORD FOR YOUR DEPARTMENT'||E'\n'||v_line||E'\n';
    end if;

    -- company_reflection: 9 rows, written nightly by fn_company_reflect, read by nothing but its
    -- own writer. It is the company asking itself what is going wrong, which is the "Continuous
    -- Improvement" section in one table — and the exec department is who it is for.
    if v_dept = 'exec' then
      select '- '||to_char(c.reflected_on,'DD Mon')||': '||c.concerns||' concern(s), '||c.actions
             ||' action(s) — '||left(coalesce(c.answers->>'biggest_risk', c.answers::text), 200)
        into v_line
        from company_reflection c order by c.reflected_on desc limit 1;
      if v_line is not null then
        v_emp := v_emp || E'\n'||'# THE COMPANY''S OWN LATEST REFLECTION'||E'\n'||v_line||E'\n';
      end if;
    end if;

    out := out || left(v_emp, 6200) || E'\n\n';
  end if;
  if p_agent_key is not null then
    out := out || '# LAYER 2 - YOUR PROFESSIONAL EXPERTISE'||E'\n\n';
    for r in select topic,content from agent_knowledge
             where coalesce(layer,'profession') in ('profession','state')
               and (agent_key = p_agent_key
                    or (v_dept is not null
                        and not exists (select 1 from agent_knowledge k2
                                         where k2.agent_key = p_agent_key
                                           and coalesce(k2.layer,'profession') in ('profession','state'))
                        and agent_key in (select b.agent_key from org_agents b
                                           where b.active and b.department = v_dept
                                             and b.agent_key <> p_agent_key)))
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
    v_l4 := v_l4 || coalesce(public.fn_agent_institutional_memory(p_agent_key, 6), '');
    if v_l4 <> '' then
      out := out || '# LAYER 4 - WHAT THIS ORGANIZATION HAS LEARNED'||E'\n\n'|| left(v_l4, 3500);
    end if;
  end if;
  -- ---- THE OS LAYER'S THREE UNREAD OUTPUTS ------------------------------------------------------
  -- Appended at the END on purpose. v_emp is truncated at 6,200 characters and LAYER 2 is budgeted
  -- against length(out); adding any of this earlier would silently delete something already proven
  -- to reach the employee. An output landing exactly on a ceiling is truncation, not coincidence.
  if v_os is not null then
    -- os_objective.measure was a LABEL on all 50 rows — 'gl_journal', 'qualified pipeline',
    -- 'KPI instrumentation'. A label cannot be met or missed. measure_sql now resolves to a number
    -- on a daily cron and this is the only place that number reaches a person.
    select string_agg(z.horizon||': '||z.objective||' — reads '
             ||coalesce(z.actual_value::text,'no value')
             ||coalesce(' (measured '||to_char(z.measured_at,'DD Mon')||')', ' (measure failed)'),
             E'\n- '
             order by case z.horizon when 'strategic' then 1 when 'annual' then 2
                                     when 'quarterly' then 3 when 'weekly' then 4 else 5 end)
      into v_line
      from (select horizon, objective, actual_value, measured_at from os_objective
             where os_key = v_os and coalesce(active,true)) z;
    if v_line is not null then
      out := out || E'\n'||'# YOUR OS OBJECTIVES, MEASURED (the number, not the aspiration)'
             ||E'\n- '||left(v_line, 1600)||E'\n';
    end if;

    -- OS.txt line 109: "Leadership OS should not duplicate this knowledge; it queries Finance OS
    -- when needed." os_knowledge_domain wrote that routing down 315 times and nothing resolved it;
    -- its only reader, fn_knowledge_gaps, takes no os_key and cannot answer "who owns this".
    v_line := public.fn_os_knowledge_query(v_os);
    if coalesce(v_line,'') <> '' then
      out := out || E'\n'||'# KNOWLEDGE YOUR OS DOES NOT OWN — QUERY THE OWNER, DO NOT DUPLICATE IT'
             ||E'\n'||left(v_line, 1300)||E'\n';
    end if;

    -- workflow_run and workflow_step_run were 0 rows with 0 readers while workflow held 14 active
    -- definitions and workflow_step 117 steps. A run nobody can see is the diagram again.
    select string_agg('- '||coalesce(w.name, x.workflow_key)||': step '||coalesce(x.current_step,0)
             ||' of '||(select count(*) from workflow_step s where s.workflow_key = x.workflow_key)
             ||' ('||x.status||')'
             ||coalesce(' — now: '||(select sr.input->>'step' from workflow_step_run sr
                                      where sr.workflow_run_id = x.id
                                        and sr.step_no = x.current_step), ''),
             E'\n' order by x.started_at desc nulls last)
      into v_line
      -- THE LIMIT MUST SIT AFTER THE FILTER, NOT BEFORE IT. This subquery used to take the 8
      -- newest runs COMPANY-WIDE and only then join workflow and filter on os_key, so the moment
      -- one OS owned all 8 newest runs every other OS's employees saw nothing. Measured on
      -- production 6 Aug 2026: all 8 newest in-flight runs were operations, while intelligence had
      -- 19 running, leadership 12, evolution 6 and knowledge 2 — and not one of those employees'
      -- prompts carried this section. The os_key filter now sits INSIDE the subquery so the 8 is
      -- per-OS; the outer join and where are left in place so the emitted text is byte-identical
      -- for an OS that was already inside the company-wide window.
      from (select r2.id, r2.workflow_key, r2.current_step, r2.status, r2.started_at
              from workflow_run r2 join workflow w2 on w2.workflow_key = r2.workflow_key
             where r2.status in ('queued','running') and w2.os_key = v_os
             order by r2.started_at desc nulls last limit 8) x
      join workflow w on w.workflow_key = x.workflow_key
     where w.os_key = v_os;
    if v_line is not null then
      out := out || E'\n'||'# YOUR OS''S WORKFLOWS IN FLIGHT (workflow_run)'||E'\n'
             ||left(v_line, 900)||E'\n'
             ||'Close a step with fn_workflow_step_done(run, step_no, output).'||E'\n';
    end if;
  end if;

  return out;
end $function$
