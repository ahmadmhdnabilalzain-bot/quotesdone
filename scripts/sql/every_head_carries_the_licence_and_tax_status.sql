-- EVERY HEAD CARRIES THE LICENCE AND TAX STATUS (6 Sep 2026).
--
-- the_company_knows_its_own_licence_and_tax_status.sql recorded the DET trade licence and the VAT
-- ruling in company_registration and rendered them as qd-company:registration, which an agent only
-- sees when retrieval matches. The founder said never to ask about either again, so the answer has
-- to be in front of every agent: LAYER 1 now opens with the four hard rules and then one line from
-- company_registration (licence, expiry, activities, VAT status and threshold). The 2-argument
-- overload of fn_agent_context is restated here in full; the 3-argument overload is unchanged and
-- stays canonical in fn_agent_context_both_overloads_are_canonical.sql.
--
--   node scripts/apply_sql.mjs scripts/sql/every_head_carries_the_licence_and_tax_status.sql --apply --ddl
CREATE OR REPLACE FUNCTION public.fn_agent_context(p_agent_key text DEFAULT NULL::text, p_max_chars integer DEFAULT 9000)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare out text := ''; r record; piece text; cap int;
        c_keep constant int := 19500;   -- what fn_agent_context_capped keeps of the head at 24,000
        v_room int; l2_cap int; l1_cap int; l3_cap int; l4_cap int; v_used int; v_first boolean;
        v_ops jsonb; v_ops_txt text;
        v_dept text; v_role text; v_charter text; v_north text; v_health_fn text;
        v_status text; v_state jsonb; v_l4 text := '';
        v_emp text := ''; v_loop text := ''; v_title text; v_resp text; v_mgr text; v_sen text; v_plan text;
        v_cap_tasks int; v_line text; v_n int; v_os text;
        v_genome text;
        v_risks text;
begin
  p_agent_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  cap := greatest(coalesce(p_max_chars,9000), 22000);
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
    -- A LIST OF HEADINGS WOULD SATISFY THE CHECK AND TEACH NOBODY ANYTHING, so each line carries the
    -- doctrine itself. 170 characters of it (was 220): the 550 characters bought back are what pay
    -- for the first profession row in the head.
    select string_agg('- '||c.title||': '||left(regexp_replace(c.body, '\s+', ' ', 'g'), 170),
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
    -- RENDERED RAW: the check matches left(risk, 50) verbatim. Highest impact and likelihood first;
    -- capped at 12 entries so the register cannot crowd the profession out of the head.
    -- ALIAS rr, NOT r: `r record` is declared above and plpgsql resolves the identifier to it.
    select string_agg('- ['||coalesce(z.impact,'?')||' impact / '||coalesce(z.probability,'?')
                      ||' likelihood] '||z.risk
                      ||case when coalesce(z.mitigation,'') <> ''
                             then '  -> mitigating: '||left(z.mitigation, 120) else '' end,
                      E'\n' order by z.ord)
      into v_risks
      from (select rr.impact, rr.probability, rr.risk, rr.mitigation,
                   row_number() over (order by case coalesce(rr.impact,'') when 'high' then 0 when 'medium' then 1 else 2 end,
                                               case coalesce(rr.probability,'') when 'high' then 0 when 'medium' then 1 else 2 end,
                                               rr.id) ord
              from public.risk_register rr
             where coalesce(rr.status,'open') in ('open','mitigating') and length(rr.risk) > 20) z
     where z.ord <= 12;
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
    select 'Your department has '||count(*)||' task(s) in flight ('
           ||count(*) filter (where t.status='assigned')||' assigned, '
           ||count(*) filter (where t.status='in_progress')||' in progress), plus '
           ||(select count(*) from org_tasks p where p.dept_key = v_dept and p.status='proposed')
           ||' proposed (held for review with '
           ||coalesce((select d.lead_agent from org_departments d where d.dept_key = v_dept), 'the department lead')
           ||', not the founder — a refund is the only decision that goes to him). Your personal cap is '||coalesce(v_cap_tasks,0)||' open task(s).'
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
      v_line := case when r.owner_agent is not null
                     then 'Your OS is owned by: '||r.owner_agent
                       ||coalesce(' — '||left(r.owner_title,60), '')
                       ||'. Escalate OS-level decisions there.'||E'\n'
                     else '' end;
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

    -- ---- WHAT THE COMPANY IS TRYING TO ACHIEVE ---------------------------------------------------
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
    -- Collected into v_loop and emitted AFTER LAYER 4 (see below): still read by every uncapped
    -- caller, no longer paid for out of the head that carries the profession and the live state.
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
      v_loop := v_loop || E'\n'||'# WHAT THIS ORGANISATION IS TRYING TO FIX'||E'\n'||v_line||E'\n';
    end if;

    select string_agg('- PROPOSED CHANGE ('||e.change_class||'): '||left(e.proposal, 170), E'\n' order by e.id desc)
      into v_line
      from (select id, change_class, proposal from evolution_proposal
             where status = 'proposed' order by id desc limit 3) e;
    if v_line is not null then
      v_loop := v_loop || v_line || E'\n';
    end if;

    select string_agg('- '||coalesce(d.decided_by,'someone')||' decided: '||left(d.recommendation, 150)
             ||coalesce(' (serves '||d.serves_goal||')','')
             ||coalesce(' — outcome: '||left(d.actual_outcome,80), ' — outcome not yet recorded'), E'\n' order by d.id desc)
      into v_line
      from (select id, decided_by, recommendation, serves_goal, actual_outcome from decision_record
             where dept_key = v_dept or dept_key is null order by id desc limit 2) d;
    if v_line is not null then
      v_loop := v_loop || E'\n'||'# DECISIONS ALREADY ON RECORD FOR YOUR DEPARTMENT'||E'\n'||v_line||E'\n';
    end if;

    if v_dept = 'exec' then
      select '- '||to_char(c.reflected_on,'DD Mon')||': '||c.concerns||' concern(s), '||c.actions
             ||' action(s) — '||left(coalesce(c.answers->>'biggest_risk', c.answers::text), 200)
        into v_line
        from company_reflection c order by c.reflected_on desc limit 1;
      if v_line is not null then
        v_loop := v_loop || E'\n'||'# THE COMPANY''S OWN LATEST REFLECTION'||E'\n'||v_line||E'\n';
      end if;
    end if;

    out := out || left(v_emp, 5200) || E'\n\n';

    -- ---- YOUR THRESHOLDS: the decision_policy rows the gates enforce for this department ---------
    v_line := public.fn_dept_decision_thresholds(v_dept);
    if v_line is not null then out := out || v_line || E'\n\n'; end if;
  end if;

  -- ================= THE BUDGETED LAYERS. Everything below is measured against c_keep. ============
  -- v_room is what is left of the 19,500 the capped path keeps. LAYER 2 takes its share first (and the
  -- first row is admitted unconditionally); the remainder is re-split among LAYER 1, 3 and 4 after
  -- LAYER 2 has actually been emitted, so an employee with one 700-character profession row hands the
  -- slack on rather than leaving it empty.
  v_room := greatest(c_keep - length(out), 3200);
  l2_cap := greatest(1200, v_room * 27 / 100);

  if p_agent_key is not null then
    out := out || '# LAYER 2 - YOUR PROFESSIONAL EXPERTISE'||E'\n\n';
    v_used := 0; v_first := true;
    for r in select topic,content,review_due,validation_status from agent_knowledge
             where coalesce(layer,'profession') in ('profession','state')
               and coalesce(validation_status,'') <> 'quarantined'
               and (agent_key = p_agent_key
                    or (v_dept is not null
                        and not exists (select 1 from agent_knowledge k2
                                         where k2.agent_key = p_agent_key
                                           and coalesce(k2.layer,'profession') in ('profession','state'))
                        and agent_key in (select b.agent_key from org_agents b
                                           where b.active and b.department = v_dept
                                             and b.agent_key <> p_agent_key)))
             order by priority desc nulls last, updated_at desc loop
      piece := '## '||public.fn_knowledge_staleness_tag(r.review_due, r.validation_status)||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
      if v_first then
        -- the first profession row ALWAYS lands: truncated to the budget if it is longer than the budget
        if length(piece) > l2_cap then
          piece := left(piece, l2_cap - 90)||E'\n'||'[… profession row truncated to the LAYER 2 budget; the full row is in agent_knowledge.]'||E'\n\n';
        end if;
        out := out || piece; v_used := v_used + length(piece); v_first := false;
      elsif v_used + length(piece) <= l2_cap then
        out := out || piece; v_used := v_used + length(piece);
      end if;
    end loop;
    if v_first then
      out := out || '(no profession row is on file for you or your department yet; ask people_ops to seed one)'||E'\n\n';
    end if;
  end if;

  -- re-split what is left among LAYER 1 / 3 / 4
  v_room := greatest(c_keep - length(out), 2400);
  l1_cap := greatest(800, v_room * 36 / 100);
  l3_cap := greatest(700, v_room * 28 / 100);
  l4_cap := greatest(700, v_room - l1_cap - l3_cap - 160);

  -- ---- LAYER 1: the four hard rules, the LIVE company rows, then the _global canon ----------------
  out := out || '# LAYER 1 - COMPANY KNOWLEDGE (authoritative; pricing marked LIVE overrides any other figure)'||E'\n\n';
  piece := coalesce(public.fn_company_hard_rules(), '');
  out := out || piece || E'\n';
  -- 6 SEP 2026: the company's licence and tax status in one line, read from company_registration
  -- (the founder supplied the licence and ruled on VAT that day; the full record is qd-company:registration).
  select 'LICENCE & TAX: ' || cr.authority || ' ' || cr.license_type || ' no. ' || cr.license_no || ' "' || cr.trade_name || '", expires '
         || to_char(cr.expires_on, 'DD Mon YYYY') || '; activities ' || left(cr.activities, 90) || '. '
         || case when cr.vat_registered then 'VAT-registered, TRN ' || coalesce(cr.trn, '?') || '.'
                 else 'NOT VAT-registered: no VAT is charged or shown until AED ' || to_char(cr.vat_threshold_aed, 'FM999,999,999')
                      || ' taxable supplies in 12 months (founder ruling ' || to_char(cr.vat_ruling_on, 'DD Mon YYYY') || '; never ask the founder about VAT or the TRN).' end
    into piece from public.company_registration cr order by cr.recorded_at desc limit 1;
  if piece is not null then out := out || piece || E'\n\n'; end if;
  v_used := 0;
  for r in select o.record_id, o.title, o.content, o.effective_date
             from ops_knowledge o
            where o.record_id in ('qd-company:stage','qd-company:live-state')
            order by case o.record_id when 'qd-company:stage' then 1 else 2 end loop
    piece := '## '||coalesce(r.title, r.record_id)||' (live, effective '||coalesce(to_char(r.effective_date,'DD Mon YYYY'),'?')||')'||E'\n'
             ||left(regexp_replace(coalesce(r.content,''), E'\n\nYou can answer questions about:.*$', ''), 700)||E'\n\n';
    if v_used + length(piece) <= l1_cap then out := out || piece; v_used := v_used + length(piece); end if;
  end loop;
  -- The _global canon, highest priority first, each cut at 500 inside the head. company:self_knowledge
  -- is skipped here (the live rows above replaced it); the untruncated remainder follows LAYER 4.
  for r in select id, topic,content,review_due,validation_status from agent_knowledge
           where agent_key='_global' and coalesce(priority,0)>=90 and coalesce(validation_status,'') <> 'quarantined'
             and topic <> 'company:self_knowledge'
           order by priority desc nulls last, updated_at desc loop
    piece := '## '||public.fn_knowledge_staleness_tag(r.review_due, r.validation_status)||coalesce(r.topic,'')||E'\n'||
             case when length(coalesce(r.content,'')) > 500
                  then left(r.content, 500)||E'\n'||'[… cut at 500 of '||length(r.content)||' characters; the full item is in agent_knowledge.]'
                  else coalesce(r.content,'') end||E'\n\n';
    if v_used + length(piece) <= l1_cap then out := out||piece; v_used := v_used + length(piece); end if;
  end loop;

  -- ---- LAYER 3: live operational state, inside the head -----------------------------------------
  if v_health_fn is not null then
    begin
      execute format('select %I()', v_health_fn) into v_state;
      piece := '# LAYER 3 - LIVE OPERATIONAL STATE (from '||v_health_fn||' at '||now()::timestamptz(0)||'; the ONLY valid source for operational numbers)'||E'\n'
               ||left(coalesce(v_state::text,'{}'), l3_cap - 160)||E'\n\n';
      out := out || piece;
    exception when others then
      out := out || '# LAYER 3 - LIVE OPERATIONAL STATE unavailable ('||sqlerrm||'); do not quote operational numbers this turn.'||E'\n\n';
    end;
  end if;

  -- ---- LAYER 4: what the organisation has learned, inside the head --------------------------------
  if p_agent_key is not null then
    for r in select topic, content, review_due, validation_status from agent_knowledge
             where layer='experience' and agent_key in (p_agent_key,'_global')
               and coalesce(validation_status,'') <> 'quarantined'
             order by updated_at desc limit 12 loop
      v_l4 := v_l4 || '## '||public.fn_knowledge_staleness_tag(r.review_due, r.validation_status)||coalesce(r.topic,'')||E'\n'||coalesce(r.content,'')||E'\n\n';
    end loop;
    for r in select kind, content from agent_memory m
             where m.agent_key=p_agent_key and m.importance >= 5
               and not exists (select 1 from policy_rules p where p.active and m.content ~* p.forbid_regex)
             order by m.importance desc, m.created_at desc limit 8 loop
      v_l4 := v_l4 || '## memory ('||r.kind||')'||E'\n'||r.content||E'\n\n';
    end loop;
    v_l4 := v_l4 || coalesce(public.fn_agent_institutional_memory(p_agent_key, 6), '');
    if v_l4 <> '' then
      out := out || '# LAYER 4 - WHAT THIS ORGANIZATION HAS LEARNED'||E'\n\n'|| left(v_l4, l4_cap - 60) || E'\n';
    end if;
  end if;

  -- ================= AFTER THE HEAD. Reaches the uncapped callers; bounded by cap. ==============
  -- The improvement loop, then the rest of the _global canon in full.
  if v_loop <> '' then out := out || v_loop || E'\n'; end if;

  out := out || '# LAYER 1 (continued) - THE REST OF THE COMPANY CANON'||E'\n\n';
  for r in select topic,content,review_due,validation_status from agent_knowledge
           where agent_key='_global' and coalesce(validation_status,'') <> 'quarantined'
             and topic <> 'company:self_knowledge'
           order by priority desc nulls last, updated_at desc loop
    piece := '## '||public.fn_knowledge_staleness_tag(r.review_due, r.validation_status)||coalesce(r.topic,'')||E'\n'||
             case when length(coalesce(r.content,'')) > 1500
                  then left(r.content, 1500)||E'\n'||'[… truncated here at 1,500 of '
                       ||length(r.content)||' characters. This item exists in full in '
                       ||'agent_knowledge; ask for the rest if you need it.]'
                  else coalesce(r.content,'') end||E'\n\n';
    if length(out)+length(piece) <= cap then out := out||piece; end if;
  end loop;

  -- ---- THE OS LAYER'S THREE UNREAD OUTPUTS ------------------------------------------------------
  if v_os is not null then
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

    v_line := public.fn_os_knowledge_query(v_os);
    if coalesce(v_line,'') <> '' then
      out := out || E'\n'||'# KNOWLEDGE YOUR OS DOES NOT OWN — QUERY THE OWNER, DO NOT DUPLICATE IT'
             ||E'\n'||left(v_line, 1300)||E'\n';
    end if;

    select string_agg('- '||coalesce(w.name, x.workflow_key)||': step '||coalesce(x.current_step,0)
             ||' of '||(select count(*) from workflow_step s where s.workflow_key = x.workflow_key)
             ||' ('||x.status||')'
             ||coalesce(' — now: '||(select sr.input->>'step' from workflow_step_run sr
                                      where sr.workflow_run_id = x.id
                                        and sr.step_no = x.current_step), ''),
             E'\n' order by x.started_at desc nulls last)
      into v_line
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

      select coalesce(string_agg('- RULE ' || coalesce(d->>'rule_id','?') || ': when ' ||
               left(coalesce(d->>'when',''),110) || ' -> ' || left(coalesce(d->>'then',''),110) ||
               case when coalesce((d->>'requires_human_review')::boolean,false)
                    then ' [needs human review]' else '' end, E'\n'), '')
        into v_line from (select d from jsonb_array_elements(v_ops->'decision_rules') d limit 2) z;
      if coalesce(v_line,'') <> '' then v_ops_txt := v_ops_txt || v_line || E'\n'; end if;

      select coalesce(string_agg('- ' || (h->>'direction') || ' ' || coalesce(h->>'workflow','') ||
               ' (' || coalesce(h->>'from','?') || ' -> ' || coalesce(h->>'to','?') || '): ' ||
               left(coalesce(h->>'you_must',''),90), E'\n'), '')
        into v_line from (select h from jsonb_array_elements(v_ops->'handoffs') h limit 2) z;
      if coalesce(v_line,'') <> '' then v_ops_txt := v_ops_txt || v_line || E'\n'; end if;

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
