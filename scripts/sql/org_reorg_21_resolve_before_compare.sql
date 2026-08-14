-- REORGANISING THE AGENT COMPANY - 21: resolve the identity before comparing it.
--
-- Section 2 requires every live entry point to resolve identity before it is used. 101 routines
-- take an agent/actor/assignee/reviewer/manager/role/employee identifier; 11 resolved. This file
-- closes the mechanical majority of the rest: the plpgsql routines whose identity parameter is a
-- real org_agents.agent_key and which compare it, join on it, or write it.
--
-- ONE LINE EACH, as the first statement after begin, because every downstream use reads the same
-- parameter. coalesce keeps an unknown key unknown, so existing "unknown agent" refusals still fire
-- and nothing that previously errored now silently succeeds.
--
-- WHY THIS IS NOT COSMETIC. Each of these was defeated by spelling in exactly the way
-- fn_pick_reviewer was, and each failed SILENTLY rather than loudly:
--
--   fn_check_spend        an aliased employee had NO personal spending limit and NO reputation
--                         tier, so the probation demotion could not fire and the ceiling was absent
--   fn_validate_lesson    "if p_validator = v.agent_key then refuse" - an agent passing its own
--                         alias VALIDATED ITS OWN LESSON. A live self-validation bypass.
--   fn_exam_revert        matched nothing and returned {"reverted":0}: it failed safe, but it also
--                         did nothing while reporting success
--   fn_agent_context      the older 2- and 3-argument context path, still called by edge functions
--   fn_propose_lesson     the unknown-agent guard, the agent_key insert and the owner_agent insert
--
-- Routines deliberately NOT changed, having been examined and cleared: fn_control_mode_* and
-- fn_approval_decide (Supabase auth email / uuid - the resolver returns NULL for every value they
-- can hold, and a collision would rewrite the audit stamp on a privilege grant), fn_trade_confirm,
-- fn_trade_reject and fn_refund_amount_resolve (free-text provenance labels like 'ops:zaino',
-- never compared to an agent), and match_suppliers / match_suppliers_kw (p_role is a SUPPLIER
-- catalogue role - manufacturer, distributor - not an org role).
--
-- Bodies below are the live staging definitions with only that one line inserted, generated rather
-- than retyped.

begin;

-- fn_agent_context(p_agent_key text, p_max_chars integer)
CREATE OR REPLACE FUNCTION public.fn_agent_context(p_agent_key text DEFAULT NULL::text, p_max_chars integer DEFAULT 9000)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare out text := ''; r record; piece text; cap int; own_cap int;
        v_ops jsonb; v_ops_txt text;
        v_dept text; v_role text; v_charter text; v_north text; v_health_fn text;
        v_status text; v_state jsonb; v_l4 text := '';
        v_emp text := ''; v_title text; v_resp text; v_mgr text; v_sen text; v_plan text;
        v_cap_tasks int; v_line text; v_n int; v_os text; v_pad int := 0;
        v_genome text;
        v_risks text;
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
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
  -- TRUNCATE, DO NOT DROP. See the migration header: the per-item guard below compares one
  -- item against the WHOLE-context cap, so "Company FAQ (canonical answers)" — 197,956 chars
  -- at priority 96, the highest global row there is — could never fit and was silently
  -- skipped on every call for every employee.
  for r in select topic,content from agent_knowledge
           where agent_key='_global' and coalesce(priority,0)>=90 order by priority desc nulls last, updated_at desc loop
    piece := '## '||coalesce(r.topic,'')||E'\n'||
             case when length(coalesce(r.content,'')) > 1500
                  then left(r.content, 1500)||E'\n'||'[… truncated here at 1,500 of '
                       ||length(r.content)||' characters. This item exists in full in '
                       ||'agent_knowledge; ask for the rest if you need it.]'
                  else coalesce(r.content,'') end||E'\n\n';
    if length(out)+length(piece) <= cap then out := out||piece; end if;
  end loop;
  for r in select topic,content from agent_knowledge
           where agent_key='_global' and coalesce(priority,0)<90 order by priority desc nulls last, updated_at desc loop
    piece := '## '||coalesce(r.topic,'')||E'\n'||
             case when length(coalesce(r.content,'')) > 1500
                  then left(r.content, 1500)||E'\n'||'[… truncated here at 1,500 of '
                       ||length(r.content)||' characters. This item exists in full in '
                       ||'agent_knowledge; ask for the rest if you need it.]'
                  else coalesce(r.content,'') end||E'\n\n';
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

  -- ---- THE TARGET OPERATING MODEL — the Company Operations pack, finally addressed to a person ---
  -- ops_kb_stage carries twelve relational projections of the pack (departments, roles, sops, kpis,
  -- workflows, handoffs, event_subscriptions, live_bindings, scenarios, templates, decision_rules,
  -- exception_playbooks) and on 2026-08-10 not one of them had a runtime reader:
  -- fn_ops_department_context, the only function that reads them, had ZERO callers. That is the
  -- same defect as the 115,148 knowledge records that sat in kb_stage while every customer path
  -- read kb_chunks — complete, enabled, unread.
  --
  -- Bounded HARD. agent_brain times out around 56 s on a ~30,800-token prompt; the handoff inbox
  -- that caused two of those timeouts added 2,082 characters and is now capped at 647. This block
  -- is a DIGEST plus a pointer, not the corpus: the full text stays one call away in
  -- fn_ops_department_context(dept, topic). Cap below: 900 characters.
  if v_dept is not null then
    v_ops := public.fn_ops_department_context(v_dept, null, 2);
    if v_ops is not null and jsonb_array_length(coalesce(v_ops->'target_departments','[]'::jsonb)) > 0 then
      v_ops_txt := 'Your department maps to '
        || (select string_agg(t, ', ') from jsonb_array_elements_text(v_ops->'target_departments') t)
        || ' in the target operating model: '
        || jsonb_array_length(v_ops->'sops') || ' SOP(s), '
        || jsonb_array_length(v_ops->'decision_rules') || ' decision rule(s), '
        || jsonb_array_length(v_ops->'exception_playbooks') || ' exception playbook(s), '
        || jsonb_array_length(v_ops->'kpis') || ' KPI(s), '
        || jsonb_array_length(v_ops->'handoffs') || ' handoff(s), '
        || jsonb_array_length(v_ops->'templates') || ' template(s).' || E'\n';

      -- the two highest-priority decision rules, which is what actually changes a decision
      select coalesce(string_agg('- RULE ' || coalesce(d->>'rule_id','?') || ': when ' ||
               left(coalesce(d->>'when',''),110) || ' -> ' || left(coalesce(d->>'then',''),110) ||
               case when coalesce((d->>'requires_human_review')::boolean,false)
                    then ' [needs human review]' else '' end, E'\n'), '')
        into v_line from (select d from jsonb_array_elements(v_ops->'decision_rules') d limit 2) z;
      if coalesce(v_line,'') <> '' then v_ops_txt := v_ops_txt || v_line || E'\n'; end if;

      -- who you hand work to and who hands it to you: the pack's cross-department contract
      select coalesce(string_agg('- ' || (h->>'direction') || ' ' || coalesce(h->>'workflow','') ||
               ' (' || coalesce(h->>'from','?') || ' -> ' || coalesce(h->>'to','?') || '): ' ||
               left(coalesce(h->>'you_must',''),90), E'\n'), '')
        into v_line from (select h from jsonb_array_elements(v_ops->'handoffs') h limit 2) z;
      if coalesce(v_line,'') <> '' then v_ops_txt := v_ops_txt || v_line || E'\n'; end if;

      -- the events the target model says this department consumes. NOT live on the bus, and said
      -- so rather than implied: all 100 pack subscriptions carry active=false.
      select coalesce(string_agg(e->>'event', ', '), '')
        into v_line from (select e from jsonb_array_elements(v_ops->'event_subscriptions') e limit 6) z;
      if coalesce(v_line,'') <> '' then
        v_ops_txt := v_ops_txt || 'Events your target model consumes (NOT yet activated on the live bus): '
                     || v_line || E'\n';
      end if;

      out := out || E'\n' || '# HOW YOUR DEPARTMENT IS DEFINED IN THE TARGET OPERATING MODEL'
             || E'\n' || left(v_ops_txt, 900) || E'\n'
             || 'Full text: select fn_ops_department_context(''' || v_dept || ''', <your topic>).' || E'\n';
    end if;
  end if;

  return out;
end $function$
;

-- fn_agent_context(p_agent_key text, p_max_chars integer, p_query text)
CREATE OR REPLACE FUNCTION public.fn_agent_context(p_agent_key text, p_max_chars integer, p_query text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare out text; v_dept text; lib text := ''; ops text := ''; r record; r2 record;
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  out := public.fn_agent_context(p_agent_key, p_max_chars);
  if p_agent_key is null or coalesce(p_query,'') = '' then return out; end if;
  select a.department into v_dept from org_agents a where a.agent_key = p_agent_key;
  for r in
    with hits as (
      select 1 as ord, s.* from public.fn_dept_library_search(v_dept, p_query, 4) s
      union all
      select 2 as ord, s.* from public.fn_dept_library_search('company', p_query, 2) s
    ), uniq as (
      select distinct on (id) id, title, content, ord, rank from hits order by id, ord
    )
    select title, content from uniq order by ord, rank desc
  loop
    exit when length(lib) > 2600;
    lib := lib || '## ' || coalesce(r.title,'') || E'\n' || left(coalesce(r.content,''), 700) || E'\n\n';
  end loop;
  if lib <> '' then
    out := out || E'\n' ||
      '# LAYER 2b - YOUR DEPARTMENT REFERENCE LIBRARY (retrieved from dept_library for this task; cite the title in [brackets] when you use it)' ||
      E'\n\n' || lib;
  end if;

  for r2 in
    select title, content, record_type, authority_tier, implementation_status, rank
      from public.fn_ops_knowledge_search(v_dept, p_query, 5)
     order by rank desc
  loop
    exit when length(ops) > 2400;
    ops := ops || '## [' || coalesce(r2.record_type,'record') || ' · authority: ' ||
           coalesce(r2.authority_tier,'?') || ' · ' || coalesce(r2.implementation_status,'?') || '] ' ||
           coalesce(r2.title,'') || E'\n' || left(coalesce(r2.content,''), 700) || E'\n\n';
  end loop;
  if ops <> '' then
    out := out || E'\n' ||
      '# LAYER 2c - HOW THIS COMPANY OPERATES (your department''s own SOPs, decision rules, exception playbooks and KPI definitions). ' ||
      'These OVERRIDE generic practice. Respect the authority tier on each: gated means it needs approval, ' ||
      'supervised means a human reviews it, autonomous means you may act. A record marked target_state describes ' ||
      'a capability the company has NOT built yet — plan around it, do not assume it exists.' ||
      E'\n\n' || ops;
  end if;

  -- LAYER 2d/2e/2f: the V3 delivery. Added here rather than in a new function because this is
  -- the path every agent already calls; a second assembler would have been a corpus no runtime
  -- function reads. fn_agent_context_v3 does the deterministic filtering and the budgeting.
  declare v3 jsonb; sec text := ''; itm jsonb; begin
    v3 := public.fn_agent_context_v3(p_agent_key, null, p_query, null, 9000);
    if v3 ? 'role_knowledge' then
      for itm in select * from jsonb_array_elements(v3->'role_knowledge') loop
        exit when length(sec) > 2400;
        sec := sec || '## ' || coalesce(itm->>'title','') || ' [' || coalesce(itm->>'record_id','') || ']' || E'
'
            || left(coalesce(itm->>'content',''), 700) || E'

';
      end loop;
      if sec <> '' then
        out := out || E'
' ||
          '# LAYER 2d - YOUR PROFESSIONAL ROLE KNOWLEDGE (the packaged role identity you hold: purpose, ' ||
          'competencies, expert decision checklist and evidence contract). Cite the [record_id] you use.'
          || E'

' || sec;
      end if;
    end if;

    sec := '';
    for itm in select * from jsonb_array_elements(coalesce(v3->'deterministic_rules','[]'::jsonb)) loop
      exit when length(sec) > 2000;
      sec := sec || '- [' || coalesce(itm->>'record_id','') || ' · ' || coalesce(itm->>'layer','') ||
             ' · authority ' || coalesce(itm->>'authority_tier','?') || '] ' || coalesce(itm->>'title','') || E'
';
    end loop;
    if sec <> '' then
      out := out || E'
' ||
        '# LAYER 2f - DETERMINISTIC RULES THAT BIND YOU (authority, policy, decision playbooks, KPI ' ||
        'definitions). These are looked up as structured records, never inferred from similarity. If a ' ||
        'rule here contradicts anything above, the rule wins.' || E'

' || sec;
    end if;

    sec := '';
    for itm in select * from jsonb_array_elements(coalesce(v3->'live_data_required','[]'::jsonb)) loop
      exit when length(sec) > 900;
      sec := sec || '- ' || coalesce(itm->>'title','') || E'
';
    end loop;
    if sec <> '' then
      out := out || E'
' ||
        '# LAYER 2g - FACTS YOU MUST FETCH, NOT REMEMBER. For each of these the current value comes from ' ||
        'a live authorised tool. Answering one of them from the text above is a wrong answer, however ' ||
        'confident it reads.' || E'

' || sec;
    end if;
    -- The trace has to be able to name what was read. Recorded here because this is where
    -- the assembled context and its record ids are both in scope. A STABLE function may not
    -- execute an INSERT, which is why this one and its caller are now VOLATILE.
    perform public.fn_record_context_retrieval(
      p_agent_key, null, null,
      (select array_agg(x) from jsonb_array_elements_text(coalesce(v3->'knowledge_ids','[]'::jsonb)) x),
      p_max_chars, length(out));
  end;
  return out;
end
$function$
;

-- fn_agent_institutional_memory(p_agent_key text, p_limit integer)
CREATE OR REPLACE FUNCTION public.fn_agent_institutional_memory(p_agent_key text, p_limit integer DEFAULT 6)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_dept text; v_cat text; out text := ''; r record;
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  if p_agent_key is null then return ''; end if;

  select department into v_dept from org_agents where agent_key = p_agent_key;
  if p_agent_key like 'cat:%' then v_cat := replace(p_agent_key, 'cat:', ''); end if;

  for r in
    select m.kind, m.headline, m.detail, m.outcome, m.money_aed, m.category_slug, m.confidence
    from institutional_memory m
    where (m.visible_to is null
           or array_length(m.visible_to,1) is null
           or 'all' = any(m.visible_to)
           or v_dept = any(m.visible_to)
           or p_agent_key = any(m.visible_to))
      and (m.category_slug is null or m.category_slug = v_cat)
      and coalesce(m.confidence, 1) >= 0.6
    order by coalesce(m.occurred_at, m.created_at) desc, coalesce(m.confidence,0) desc
    limit greatest(coalesce(p_limit,6), 1)
  loop
    out := out || '## lesson (' || coalesce(r.kind,'note') || ')' || E'\n'
        || coalesce(r.headline,'') || E'\n'
        || left(coalesce(r.detail,''), 600)
        || case when r.outcome is not null then E'\n' || 'What changed as a result: ' || left(r.outcome, 300) else '' end
        || case when coalesce(r.money_aed,0) <> 0 then ' (AED ' || r.money_aed || ' at stake)' else '' end
        || E'\n\n';
  end loop;

  return out;
end; $function$
;

-- fn_assign_training(p_agent_key text, p_competency text, p_purpose text, p_n integer)
CREATE OR REPLACE FUNCTION public.fn_assign_training(p_agent_key text, p_competency text, p_purpose text DEFAULT 'practice'::text, p_n integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_roles text[]; v_dept text; v_rows jsonb;
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  if p_purpose not in ('practice','retest','drift_check') then
    raise exception 'purpose must be practice, retest or drift_check';
  end if;
  select array_agg(packaged_role_id) into v_roles from org_role_identity where agent_key = p_agent_key;
  select packaged_department into v_dept from org_role_identity where agent_key = p_agent_key limit 1;
  if v_roles is null then
    return jsonb_build_object('assigned', 0, 'reason', 'agent has no role identity');
  end if;

  with pool as (
    select c.case_id, c.case_family, c.competency, c.scope_key
      from agent_training_case c
     -- The parentheses matter: AND binds tighter than OR, so without them the competency
     -- filter applied only to the department branch and every role case slipped past it.
     where ((c.scope_type = 'role' and c.scope_key = any(v_roles))
         or (c.scope_type = 'department' and c.scope_key = v_dept))
       and (p_competency is null or c.competency = p_competency)
  ), unseen as (
    select p.* from pool p
     where not exists (select 1 from agent_training_attempt a
                        where a.agent_key = p_agent_key and a.case_id = p.case_id)
     order by md5(p.case_id || p_agent_key || p_purpose)     -- stable per (agent,purpose), not an ordered list
     limit greatest(coalesce(p_n, 5), 1)
  ), ins as (
    insert into agent_training_attempt (agent_key, case_id, purpose, competency)
    select p_agent_key, case_id, p_purpose, competency from unseen
    on conflict (agent_key, case_id, purpose) do nothing
    returning id, case_id
  )
  select jsonb_agg(jsonb_build_object('attempt_id', i.id, 'case_id', i.case_id,
                                      'payload', c.payload))
    into v_rows
    from ins i join agent_training_case c on c.case_id = i.case_id;

  return jsonb_build_object('assigned', coalesce(jsonb_array_length(v_rows), 0),
                            'purpose', p_purpose, 'cases', coalesce(v_rows, '[]'::jsonb));
end $function$
;

-- fn_check_spend(p_dept text, p_amount numeric, p_agent text)
CREATE OR REPLACE FUNCTION public.fn_check_spend(p_dept text, p_amount numeric, p_agent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_avail numeric; v_month numeric; v_limit numeric; v_route text; v_afford boolean;
  v_tier text; v_gated boolean := false;
begin
  p_agent := coalesce(public.fn_org_agent_resolve(p_agent), p_agent);
  select coalesce(monthly_aed,0), fn_budget_available(p_dept) into v_month, v_avail
  from department_budget where dept_key = p_dept;

  if v_month is null then
    return jsonb_build_object('ok', false, 'reason',
      'no budget is recorded for department "' || p_dept || '", so no spend can be authorised against it',
      'route_to','finance');
  end if;

  v_afford := coalesce(p_amount,0) <= v_avail;

  select max(threshold_aed) into v_limit
  from employee_authority where agent_key = p_agent;

  -- REPUTATION REACHES THE MOMENT THE MONEY WOULD MOVE.
  -- fn_reputation_recompute already demotes a probation-tier employee's max_tier from 'autonomous'
  -- to 'gated'; until now nothing consulted that at the point of spend, so a demoted employee kept
  -- their nominal ceiling. On probation the personal limit does not apply and the spend goes to a
  -- person — the same decision, applied where it bites.
  select r.tier into v_tier from agent_reputation r where r.agent_key = p_agent;
  if v_tier = 'probation' then v_gated := true; v_limit := 0; end if;

  v_route := case
    when coalesce(p_amount,0) >  10000 then 'founder'
    when coalesce(p_amount,0) >= 1000  then 'brief'
    -- a gated employee is never the approver of their own spend
    when v_gated then 'brief'
    else coalesce(p_agent,'department head') end;

  return jsonb_build_object(
    'ok', v_afford and (v_limit is null or coalesce(p_amount,0) <= v_limit),
    'affordable', v_afford,
    'requested_aed', coalesce(p_amount,0),
    'available_aed', v_avail,
    'monthly_aed', v_month,
    'agent_limit_aed', v_limit,
    'reputation_tier', coalesce(v_tier,'ungraded'),
    'route_to', v_route,
    'reason', case
      when not v_afford then format('Requested AED %s exceeds the AED %s remaining in the %s budget this period. Reduce the scope, defer to next period, or ask Finance to reallocate.', coalesce(p_amount,0), v_avail, p_dept)
      when v_gated then format('Affordable, but %s is on probation in the reputation system, so their personal spending limit does not apply. Route to %s.', coalesce(p_agent,'this employee'), v_route)
      when v_limit is not null and coalesce(p_amount,0) > v_limit then format('Affordable, but AED %s is above %s''s personal limit of AED %s. Route to %s.', coalesce(p_amount,0), p_agent, v_limit, v_route)
      else format('Within budget: AED %s of AED %s available. Approver: %s.', coalesce(p_amount,0), v_avail, v_route) end);
end; $function$
;

-- fn_employee_scorecard(p_agent_key text, p_max_chars integer)
CREATE OR REPLACE FUNCTION public.fn_employee_scorecard(p_agent_key text, p_max_chars integer DEFAULT 1400)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_cap  int := greatest(coalesce(p_max_chars, 1400), 300);
  v_out  text := '';
  v_line text;
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  if coalesce(btrim(p_agent_key),'') = '' then return null; end if;

  -- YOUR NUMBER. attainment mirrors fn_kpi_scoreboard exactly, including the percent_max
  -- inversion; it is NOT recomputed with a different rule, because two rules that must agree is
  -- how sec() and J() ended up with 8 and 11 variants of the same helper.
  -- An unmeasured KPI says so in words. It must never read as a zero.
  select string_agg(
           '- '||z.kpi||': target '||coalesce(z.target_value::text,'?')||' '||coalesce(z.unit,'')
           ||case
               when z.actual_value is null then ' — NOT MEASURED YET (no number exists; do not assume one)'
               else ' — you are at '||z.actual_value::text
                    ||case when z.target_value is null then ''
                    when z.target_value = 0 then
                      case when z.actual_value <= 0 then ', at the zero-defect target (MET)'
                           else ', against a target of ZERO (MISSED)' end
                           when z.unit = 'percent_max'
                             then ', '||round(least(100.0, 100.0 * z.target_value / nullif(z.actual_value,0)),0)::text||'% of target'
                           else ', '||round(100.0 * z.actual_value / z.target_value,0)::text||'% of target' end
                    ||case
                        when z.target_value is null or z.target_value = 0 then ''
                        when z.unit = 'percent_max' then
                          case when z.actual_value <= z.target_value then ' (MET)' else ' (MISSED)' end
                        else
                          case when z.actual_value >= z.target_value then ' (MET)'
                               when z.actual_value >= 0.9 * z.target_value then ' (NEAR)'
                               else ' (MISSED)' end end
             end
           ||case when z.serves_goal is not null then ' — serves company goal '||z.serves_goal else '' end,
           E'\n' order by z.kpi)
    into v_line
    from (select k.kpi, k.target_value, k.unit, k.actual_value, k.serves_goal
            from employee_kpi k
           where k.agent_key = p_agent_key and k.active
           order by k.kpi limit 8) z;

  if v_line is not null then
    v_out := v_out || E'\n# YOUR NUMBER RIGHT NOW — measured, not asserted\n' || v_line || E'\n';
  end if;

  -- YOUR DEPARTMENT'S OBJECTIVE and the company goal it serves. This is the chain the founder
  -- described, delivered to the one employee that has to act on it.
  select string_agg(
           '- '||d.objective
           ||case when d.target_value is not null then ' (target '||d.target_value::text||' '||coalesce(d.unit,'')||')' else '' end
           ||case when d.actual_value is not null then ', department is at '||d.actual_value::text
                  when d.measure_sql is not null then ', not yet measured'
                  else '' end
           ||case when g.key is not null then E'\n    serves company goal '||g.key||' — "'||g.goal||'"' else '' end,
           E'\n' order by d.sort, d.id)
    into v_line
    from department_objective d
    join org_agents a on a.agent_key = p_agent_key and a.department = d.dept_key
    left join company_goals g on g.key = d.goal_key and g.active
   where d.active
   limit 6;

  if v_line is not null then
    v_out := v_out || E'\n# WHAT YOUR DEPARTMENT IS FOR\n' || v_line || E'\n';
  end if;

  if v_out = '' then return null; end if;
  return left(v_out, v_cap);
end $function$
;

-- fn_exam_revert(p_agent_key text)
CREATE OR REPLACE FUNCTION public.fn_exam_revert(p_agent_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare n int;
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  delete from agent_knowledge
    where topic like 'exam:%' and (p_agent_key is null or agent_key = p_agent_key);
  get diagnostics n = row_count;
  update knowledge_exam_results set filled = false, knowledge_id = null
    where filled and (p_agent_key is null or agent_key = p_agent_key);
  return jsonb_build_object('reverted', n, 'agent', coalesce(p_agent_key,'(all)'));
end $function$
;

-- fn_handoff_answer(p_id bigint, p_agent_key text, p_answer text)
CREATE OR REPLACE FUNCTION public.fn_handoff_answer(p_id bigint, p_agent_key text, p_answer text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_asker text;
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  if coalesce(btrim(p_answer),'') = '' then
    return jsonb_build_object('ok', false, 'reason', 'empty answer');
  end if;
  select * into r from agent_actions
   where id = p_id and agent = p_agent_key
     and status in ('pending','needs_review');
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no open item with that id for this agent');
  end if;

  -- The refusal that keeps this honest. An employee may finish the company's own work; it may not
  -- close a legal flag, a security incident, a customer escalation, a compliance update, a money
  -- item or a prompt approval by writing a paragraph about it.
  if not (r.kind = any(fn_agent_inbox_closable_kinds())) then
    return jsonb_build_object('ok', false, 'kind', r.kind,
      'reason', 'items of kind '||r.kind||' are decided by the founder, not closed by an employee');
  end if;

  update agent_actions
     set status = 'done', decided_at = now(), decided_by = p_agent_key,
         detail = coalesce(detail,'{}'::jsonb)
                  || jsonb_build_object('answer', left(p_answer, 4000), 'answered_at', now())
   where id = p_id;

  -- Only a handoff has an asker waiting on a reply. Self-raised work has nobody to notify, and
  -- the existing guard already handles that rather than inventing a recipient.
  v_asker := coalesce(r.detail->>'from', '');
  if v_asker <> '' and exists (select 1 from org_agents o where o.agent_key = v_asker) then
    insert into agent_memory (agent_key, kind, content, source, importance)
    values (v_asker, 'learned',
            'Answer to the '||r.kind||' you raised — "'||coalesce(r.title,'(untitled)')||'": '
              ||left(p_answer, 1200),
            r.kind||':'||p_id, 4);
  end if;

  return jsonb_build_object('ok', true, 'id', p_id, 'kind', r.kind, 'asker_notified', v_asker <> '');
end $function$
;

-- fn_outcome_open(p_actor text, p_decision text, p_subject_type text, p_subject_id text, p_expected_kpi_id bigint, p_rationale text, p_evidence jsonb, p_direction text, p_measure_after interval)
CREATE OR REPLACE FUNCTION public.fn_outcome_open(p_actor text, p_decision text, p_subject_type text DEFAULT 'manual'::text, p_subject_id text DEFAULT NULL::text, p_expected_kpi_id bigint DEFAULT NULL::bigint, p_rationale text DEFAULT NULL::text, p_evidence jsonb DEFAULT '[]'::jsonb, p_direction text DEFAULT 'up'::text, p_measure_after interval DEFAULT '14 days'::interval)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_sql text; v_base numeric; v_metric text; v_dept text; v_id bigint;
begin
  p_actor := coalesce(public.fn_org_agent_resolve(p_actor), p_actor);
  if p_expected_kpi_id is not null then
    select measure_sql, metric into v_sql, v_metric from employee_kpi where id = p_expected_kpi_id;
    begin
      if v_sql is not null then execute v_sql into v_base; end if;
    exception when others then v_base := null; end;
  end if;

  select a.department into v_dept from org_agents a where a.agent_key = p_actor;

  insert into outcome_record (actor, dept_key, subject_type, subject_id, decision, rationale,
                              evidence, expected_kpi_id, expected_metric, expected_direction,
                              baseline_value, measure_after, due_at)
  values (p_actor, v_dept, p_subject_type, p_subject_id, p_decision, p_rationale,
          coalesce(p_evidence,'[]'::jsonb), p_expected_kpi_id, v_metric,
          coalesce(p_direction,'up'), v_base, coalesce(p_measure_after, interval '14 days'),
          now() + coalesce(p_measure_after, interval '14 days'))
  returning id into v_id;
  return v_id;
end $function$
;

-- fn_propose_lesson(p_agent_key text, p_topic text, p_statement text, p_evidence jsonb, p_confidence numeric, p_valid_until date)
CREATE OR REPLACE FUNCTION public.fn_propose_lesson(p_agent_key text, p_topic text, p_statement text, p_evidence jsonb, p_confidence numeric DEFAULT 0.5, p_valid_until date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id bigint;
  v_obs int := coalesce(jsonb_array_length(p_evidence->'observations'), 0);
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  if p_agent_key is null or not exists (select 1 from org_agents where agent_key = p_agent_key) then
    raise exception 'unknown agent %', p_agent_key;
  end if;
  if coalesce(btrim(p_statement), '') = '' then
    raise exception 'a lesson needs a statement';
  end if;
  -- Two independent observations minimum. One outcome is an anecdote; the loop is allowed
  -- to record it as evidence but not to call it a lesson.
  if v_obs < 2 then
    return jsonb_build_object('accepted', false, 'reason', 'insufficient_evidence',
      'detail', format('a proposed lesson needs at least 2 observations; %s supplied', v_obs));
  end if;

  insert into agent_knowledge
    (agent_key, topic, content, priority, layer, source_ref, owner_agent, version,
     confidence, validation_status, review_due, valid_until, supporting_evidence)
  values (p_agent_key, p_topic, p_statement, 5, 'experience', 'learning_loop', p_agent_key, 1,
          least(coalesce(p_confidence, 0.5), 0.9), 'proposed',
          current_date + 30, p_valid_until, p_evidence::text)
  returning id into v_id;

  return jsonb_build_object('accepted', true, 'lesson_id', v_id, 'validation_status', 'proposed',
    'note', 'not retrievable until validated by someone other than its author');
end $function$
;

-- fn_retrieval_leak_check(p_agent_key text, p_task_text text)
CREATE OR REPLACE FUNCTION public.fn_retrieval_leak_check(p_agent_key text, p_task_text text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ctx jsonb; v_mine text[]; v_leak int;
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  select coalesce(array_agg(packaged_role_id),'{}') into v_mine
    from org_role_identity where agent_key = p_agent_key;
  v_ctx := public.fn_agent_context_v3(p_agent_key, null, p_task_text, null, 24000);
  select count(*) into v_leak
    from jsonb_array_elements(coalesce(v_ctx->'role_knowledge','[]'::jsonb)) e
    join ops_knowledge k on k.record_id = e->>'record_id'
   where k.role_key is not null and not (k.role_key = any(v_mine));
  return jsonb_build_object('agent_key', p_agent_key, 'own_roles', to_jsonb(v_mine),
                            'foreign_role_records', v_leak,
                            'clean', v_leak = 0);
end $function$
;

-- fn_validate_lesson(p_lesson_id bigint, p_validator text, p_verdict text, p_reason text)
CREATE OR REPLACE FUNCTION public.fn_validate_lesson(p_lesson_id bigint, p_validator text, p_verdict text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v agent_knowledge; v_mgr text;
begin
  p_validator := coalesce(public.fn_org_agent_resolve(p_validator), p_validator);
  select * into v from agent_knowledge where id = p_lesson_id;
  if v.id is null then raise exception 'unknown lesson %', p_lesson_id; end if;
  if v.validation_status <> 'proposed' then
    return jsonb_build_object('ok', false, 'reason', 'not_proposed', 'status', v.validation_status);
  end if;
  if p_validator = v.agent_key then
    return jsonb_build_object('ok', false, 'reason', 'self_validation_refused',
      'detail', 'the agent that proposed a lesson cannot be the one that validates it');
  end if;
  if p_verdict not in ('validated','rejected') then
    raise exception 'verdict must be validated or rejected, got %', p_verdict;
  end if;

  select manager_key into v_mgr from org_agents where agent_key = v.agent_key;
  update agent_knowledge
     set validation_status = p_verdict,
         updated_at = now(),
         supporting_evidence = coalesce(supporting_evidence, '') ||
           format(E'\n[%s by %s%s] %s', p_verdict, p_validator,
                  case when p_validator = v_mgr then ' (line manager)' else '' end,
                  coalesce(p_reason, ''))
   where id = p_lesson_id;
  return jsonb_build_object('ok', true, 'lesson_id', p_lesson_id, 'status', p_verdict,
                            'validator', p_validator, 'was_line_manager', p_validator = v_mgr);
end $function$
;

commit;
