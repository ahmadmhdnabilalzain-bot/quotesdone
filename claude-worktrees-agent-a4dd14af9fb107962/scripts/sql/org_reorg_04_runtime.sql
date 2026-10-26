-- REORGANISING THE AGENT COMPANY — 4 of 5: runtime orchestration.
--
-- Five changes, each answering a measured fact rather than a preference:
--
--  1. Knowledge scope follows the merge. 5,775 ops_knowledge rows are tagged with the 22 department
--     keys that no longer exist as departments. Retrieval matched `dept_key = agent.department`
--     exactly, so the day the merge landed every moved employee would have retrieved nothing from
--     its own history. fn_dept_scope closes that without rewriting a single knowledge row.
--  2. The context an agent receives now carries its CANONICAL role: what it may decide, what it may
--     not, when it activates, who it hands off to, who it escalates to, and which committees it
--     sits on. A reorganisation the agents cannot read is a document, not an organisation.
--  3. Independent review actually becomes independent. Measured on production: 285 of 1,882
--     review_chain rows have author_agent = reviewer_agent, and 182 of those are APPROVALS, the
--     most recent at 06:40 UTC today. fn_review_submit already knows the author and never passed
--     it to fn_pick_reviewer, which returns the department head — so whenever the head was the
--     author, the head approved itself.
--  4. Ordinary work stops landing on independent reviewers. A reviewer that carries the
--     department's routine queue is not independent of it.
--  5. Specialist-as-tool and structured handoff, so a manager can invoke a specialist without the
--     customer visibly bouncing between agents, and every handoff names an accountable receiver.

-- CONVERGED 14 Aug 2026 (V3 remediation). fn_context_slice and fn_agent_context_v3 are defined in
-- THREE files. The authoritative bodies are scripts/sql/v3_repair_03_retrieval.sql and
-- scripts/sql/v3_repair_05_ctx_v3_query.sql; the two defects they fix are patched here too so that
-- re-applying THIS file cannot silently revert them. It already did once, mid-session.
--   1. the tsquery filter ended "or true", a tautology that disabled filtering entirely
--   2. the task query used websearch_to_tsquery, which ANDs every word of a task sentence and
--      matched 0 of 8,256 rows where the same words ORed matched 49

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. RETRIEVAL FOLLOWS THE MERGE.
-- ---------------------------------------------------------------------------------------------
-- fn_context_slice IS NOT DEFINED HERE ANY MORE (14 Aug 2026).
-- It lived in three files and was silently reverted twice in one session; the second revert kept
-- the filter but dropped the `match` label that fn_knowledge_gap counts, so the gap signal fired
-- on every task. Authoritative definition: scripts/sql/v3_repair_03_retrieval.sql
-- Apply that file after this one. Do not re-add a copy here.


-- ---------------------------------------------------------------------------------------------
-- 2. THE AGENT READS ITS OWN CANONICAL ROLE.
-- ---------------------------------------------------------------------------------------------
-- Parameter ORDER is the live one (task_class, task_text, category_key); writing it in any other
-- order creates a second overload rather than replacing this function, and both would then be
-- callable.
-- fn_agent_context_v3 IS NOT DEFINED HERE ANY MORE (14 Aug 2026).
-- It lived in three files and was silently reverted twice in one session; the second revert kept
-- the filter but dropped the `match` label that fn_knowledge_gap counts, so the gap signal fired
-- on every task. Authoritative definition: scripts/sql/v3_repair_05_ctx_v3_query.sql
-- Apply that file after this one. Do not re-add a copy here.


-- ---------------------------------------------------------------------------------------------
-- 3. INDEPENDENT REVIEW. The author is never the reviewer.
-- ---------------------------------------------------------------------------------------------
-- The one-argument form is dropped, not kept alongside: two overloads would make fn_pick_reviewer
-- ambiguous for every existing one-argument caller. The new second parameter defaults to null, so
-- those callers keep working with exactly today's behaviour.
drop function if exists public.fn_pick_reviewer(text);
create or replace function public.fn_pick_reviewer(p_dept_key text, p_author text default null)
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare v_head text; v_ok boolean; v_delegate text; v_basis text;
        v_head_tier text; v_head_score numeric; v_score numeric; v_up text;
begin
  select lead_agent into v_head from org_departments where dept_key = p_dept_key;

  if v_head is null then
    return jsonb_build_object('reviewer', null, 'available', false,
      'basis', 'no lead_agent recorded for department ' || p_dept_key);
  end if;

  -- THE AUTHOR IS THE HEAD. Measured 14 Aug 2026: 285 of 1,882 review_chain rows had
  -- author_agent = reviewer_agent and 182 of those were approvals, because this function was only
  -- ever told the department and answered with its head. When the head wrote the work, review
  -- climbs: first to an independent reviewer inside the same department, then to the head's own
  -- manager. It never returns the author.
  if p_author is not null and p_author = v_head then
    select a.agent_key into v_delegate
      from org_agents a
      join org_role r on r.runtime_agent_key = a.agent_key and r.status = 'active'
     where a.department = p_dept_key and a.agent_key <> p_author
       and r.runtime_mode = 'independent_reviewer'
       and a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date)
     order by a.agent_key limit 1;

    if v_delegate is not null then
      return jsonb_build_object('reviewer', v_delegate, 'available', true, 'delegated_from', v_head,
        'basis', 'the department head authored this work; review routed to the department''s '
                 || 'independent reviewer, which never approves its own output');
    end if;

    select m.agent_key into v_up
      from org_agents o join org_agents m on m.agent_key = o.manager_key and m.active
     where o.agent_key = v_head
       and m.available and (m.unavailable_until is null or m.unavailable_until < current_date);

    if v_up is not null and v_up <> p_author then
      return jsonb_build_object('reviewer', v_up, 'available', true, 'delegated_from', v_head,
        'basis', 'the department head authored this work and the department has no independent '
                 || 'reviewer available; review escalated one level up the reporting chain');
    end if;

    return jsonb_build_object('reviewer', null, 'available', false, 'delegated_from', v_head,
      'basis', 'the department head authored this work and no independent reviewer or manager is '
               || 'available - escalate rather than approve it');
  end if;

  select (a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date))
    into v_ok from org_agents a where a.agent_key = v_head;

  select p.tier, p.score into v_head_tier, v_head_score
    from agent_reputation p where p.agent_key = v_head;

  if coalesce(v_ok, false) then
    if coalesce(v_head_tier, '') = 'probation' then
      select a.agent_key, p.score into v_delegate, v_score
        from org_agents a
        join agent_reputation p on p.agent_key = a.agent_key
       where a.department = p_dept_key and a.agent_key <> v_head
         and a.agent_key is distinct from p_author
         and a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date)
         and p.tier <> 'probation' and p.score > coalesce(v_head_score, 0)
       order by p.score desc, a.agent_key
       limit 1;

      if v_delegate is not null then
        return jsonb_build_object('reviewer', v_delegate, 'available', true, 'delegated_from', v_head,
          'basis', 'department head ' || v_head || ' is on the probation reputation tier ('
                   || coalesce(v_head_score::text, '?') || '); review routed to the highest-scoring '
                   || 'available employee in ' || p_dept_key || ' (' || coalesce(v_score::text, '?') || ')');
      end if;
    end if;

    return jsonb_build_object('reviewer', v_head, 'available', true, 'delegated_from', null,
      'basis', 'department head (reputation ' || coalesce(v_head_score::text, 'unscored')
               || ', tier ' || coalesce(v_head_tier, 'unscored') || ')');
  end if;

  select d.delegate_to, d.basis into v_delegate, v_basis
  from delegation_rule d
  join org_agents a on a.agent_key = d.delegate_to
  where d.active and d.dept_key = p_dept_key and d.when_agent = v_head
    and a.agent_key is distinct from p_author
    and a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date)
  order by d.rank limit 1;

  if v_delegate is null then
    select a.agent_key,
           'highest-scoring available employee in ' || p_dept_key
             || ' (reputation ' || coalesce(p.score::text, 'unscored') || ')'
      into v_delegate, v_basis
    from org_agents a
    left join agent_reputation p on p.agent_key = a.agent_key
    where a.department = p_dept_key and a.agent_key <> v_head
      and a.agent_key is distinct from p_author
      and a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date)
      and coalesce(p.tier, 'standard') <> 'probation'
    order by p.score desc nulls last, fn_seniority_rank(a.seniority), a.agent_key
    limit 1;
  end if;

  if v_delegate is null then
    return jsonb_build_object('reviewer', null, 'available', false, 'delegated_from', v_head,
      'basis', 'department head unavailable and no delegate available - escalate');
  end if;

  return jsonb_build_object('reviewer', v_delegate, 'available', true,
    'delegated_from', v_head, 'basis', coalesce(v_basis, 'delegation'));
end;
$function$;

-- fn_review_submit already held the author and never passed it. One argument.
create or replace function public.fn_review_submit(p_subject_type text, p_subject_id text, p_dept_key text, p_author text, p_content text)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_crit        jsonb;
  v_rule        jsonb;
  v_violations  jsonb := '[]'::jsonb;
  v_unenforced  jsonb := '[]'::jsonb;
  v_critical    int := 0;
  v_major       int := 0;
  v_pick        jsonb;
  v_head        text;
  v_deleg_from  text;
  v_deleg_basis text;
  v_cos         text := 'brief';
  v_decision    text;
  v_reason      text;
  v_conf        numeric;
  v_first_rule  text;
  v_res         jsonb;
begin
  -- Who is actually able to approve for this department right now, GIVEN WHO WROTE IT.
  v_pick        := fn_pick_reviewer(p_dept_key, p_author);
  v_head        := v_pick->>'reviewer';
  v_deleg_from  := v_pick->>'delegated_from';
  v_deleg_basis := v_pick->>'basis';

  -- The Chief of Staff cannot counter-sign its own draft either: that review climbs to the CEO.
  if p_author = v_cos then v_cos := 'ceo'; end if;

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, stage, decision, reason, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, 'drafted', null,
          'Draft submitted for department review', null);

  if v_head is null then
    insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                              decision, reason, confidence, delegated_from, delegation_basis)
    values (p_subject_type, p_subject_id, p_dept_key, p_author, null, 'dept_review',
            'escalate', 'No available approver in ' || p_dept_key || ': ' || coalesce(v_deleg_basis,''), 1.0,
            v_deleg_from, v_deleg_basis);
    return jsonb_build_object('subject_id', p_subject_id, 'outcome', 'escalate',
                              'stopped_at', 'dept_review', 'violations', v_violations,
                              'reason', coalesce(v_deleg_basis,''));
  end if;

  select criteria into v_crit from quality_standard where work_type = p_subject_type;

  if v_crit is not null then
    for v_rule in select * from jsonb_array_elements(v_crit) loop

      if (v_rule ? 'check_fn') then
        begin
          execute format('select %I($1,$2)', v_rule->>'check_fn')
            into v_res using p_subject_id, p_content;
        exception when others then
          v_res := jsonb_build_object('passed', false, 'detail', 'check ' || (v_rule->>'check_fn') || ' errored: ' || sqlerrm);
        end;
        if not coalesce((v_res->>'passed')::boolean, false) then
          v_violations := v_violations || jsonb_build_object(
            'rule', v_rule->>'rule', 'severity', v_rule->>'severity',
            'why', v_rule->>'why', 'detail', v_res->>'detail');
          if (v_rule->>'severity') = 'critical' then v_critical := v_critical + 1;
          elsif (v_rule->>'severity') = 'major' then v_major := v_major + 1; end if;
          if v_first_rule is null then v_first_rule := v_rule->>'rule'; end if;
        end if;

      elsif (v_rule ? 'pattern') and (v_rule ? 'fails_when') then
        if (v_rule->>'fails_when') = 'match' and p_content ~ (v_rule->>'pattern') then
          v_violations := v_violations || jsonb_build_object(
            'rule', v_rule->>'rule', 'severity', v_rule->>'severity', 'why', v_rule->>'why');
          if (v_rule->>'severity') = 'critical' then v_critical := v_critical + 1;
          elsif (v_rule->>'severity') = 'major' then v_major := v_major + 1; end if;
          if v_first_rule is null then v_first_rule := v_rule->>'rule'; end if;
        elsif (v_rule->>'fails_when') = 'no_match' and p_content !~ (v_rule->>'pattern') then
          v_violations := v_violations || jsonb_build_object(
            'rule', v_rule->>'rule', 'severity', v_rule->>'severity', 'why', v_rule->>'why');
          if (v_rule->>'severity') = 'critical' then v_critical := v_critical + 1;
          elsif (v_rule->>'severity') = 'major' then v_major := v_major + 1; end if;
          if v_first_rule is null then v_first_rule := v_rule->>'rule'; end if;
        end if;

      else
        v_unenforced := v_unenforced || jsonb_build_object(
          'rule', v_rule->>'rule', 'severity', v_rule->>'severity', 'why', v_rule->>'why');
      end if;

    end loop;
  end if;

  if v_critical > 0 then
    v_decision := 'reject';
    v_reason   := 'Rejected by department head: ' || v_critical || ' critical rule breach(es) - ' || (v_violations::text);
    v_conf     := 1.0;
  elsif v_major > 0 then
    v_decision := 'request_revision';
    v_reason   := 'Returned for revision: ' || v_major || ' major issue(s) - ' || (v_violations::text);
    v_conf     := 0.9;
  elsif jsonb_array_length(v_unenforced) > 0
        and exists (select 1 from jsonb_array_elements(v_unenforced) u where u->>'severity' = 'critical') then
    v_decision := 'hold_for_human';
    v_reason   := 'Held for human review: no executable check exists for critical criteria - ' || (v_unenforced::text);
    v_conf     := 1.0;
    v_first_rule := (select u->>'rule' from jsonb_array_elements(v_unenforced) u where u->>'severity'='critical' limit 1);
  elsif v_crit is null then
    v_decision := 'hold_for_human';
    v_reason   := 'Held for human review: no quality standard is defined for work type "' || p_subject_type || '"';
    v_conf     := 1.0;
  else
    v_decision := 'approve';
    v_reason   := 'Meets the quality standard for ' || p_subject_type || '; every criterion was checked and passed';
    v_conf     := 0.95;
  end if;

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                            decision, reason, violated_rule, confidence, delegated_from, delegation_basis)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, v_head, 'dept_review',
          v_decision, v_reason, v_first_rule, v_conf, v_deleg_from,
          case when v_deleg_from is not null then v_deleg_basis else null end);

  if v_decision <> 'approve' then
    return jsonb_build_object('subject_id', p_subject_id, 'outcome', v_decision,
                              'stopped_at', 'dept_review', 'violations', v_violations,
                              'unenforceable', v_unenforced,
                              'reviewer', v_head, 'delegated_from', v_deleg_from);
  end if;

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                            decision, reason, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, v_cos, 'cos_review',
          'approve', 'Approved by Chief of Staff: brand-compliant and serves a company goal', 0.9);

  insert into review_chain (subject_type, subject_id, dept_key, author_agent, reviewer_agent, stage,
                            decision, reason, confidence)
  values (p_subject_type, p_subject_id, p_dept_key, p_author, v_cos, 'published',
          'approve', 'Published after full approval chain', 1.0);

  insert into company_event (event_type, entity_type, entity_id, actor, payload)
  values ('content.published', p_subject_type, p_subject_id, p_author,
          jsonb_build_object('dept', p_dept_key));

  return jsonb_build_object('subject_id', p_subject_id, 'outcome', 'published',
                            'stopped_at', 'published', 'violations', v_violations,
                            'unenforceable', v_unenforced,
                            'reviewer', v_head, 'delegated_from', v_deleg_from);
end;
$function$;

-- The constraint that makes it unrepresentable going forward. NOT VALID on purpose: the 285
-- historical rows stay exactly as they happened. Deleting them would be erasing the evidence that
-- this defect was real.
alter table public.review_chain drop constraint if exists review_chain_no_self_approval_ck;
alter table public.review_chain add constraint review_chain_no_self_approval_ck
  check (reviewer_agent is null or author_agent is null or reviewer_agent <> author_agent) not valid;

-- ---------------------------------------------------------------------------------------------
-- 4. ORDINARY WORK STOPS LANDING ON INDEPENDENT REVIEWERS.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_org_task_assign(p_limit integer default 200)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_assigned int := 0; v_no_capacity int := 0; v_considered int := 0; v_saturated text;
begin
  with open_tasks as (
    select t.id, t.dept_key, t.created_at, t.action_class
      from public.org_tasks t
     where t.assigned_agent is null
       and t.status in ('assigned','in_progress')
     order by t.created_at
     limit greatest(coalesce(p_limit, 200), 1)
  ),
  load as (
    select a.agent_key, a.department, coalesce(a.max_open_tasks, 6) as cap,
           coalesce(r.runtime_mode, 'on_demand_specialist') as runtime_mode,
           (select count(*) from public.org_tasks o
             where o.assigned_agent = a.agent_key and o.status in ('assigned','in_progress')) as open_now,
           case when p.tier = 'probation' then 1 else 0 end as probation_rank
      from public.org_agents a
      left join public.agent_reputation p on p.agent_key = a.agent_key
      left join public.org_role r on r.runtime_agent_key = a.agent_key and r.status = 'active'
     where a.active
       and coalesce(a.available, true)
       and (a.unavailable_until is null or a.unavailable_until < now())
  ),
  ranked as (
    select ot.id as task_id, l.agent_key, l.cap, l.open_now,
           row_number() over (partition by ot.id
                              order by l.probation_rank, l.open_now, l.agent_key) as pick,
           row_number() over (partition by l.agent_key
                              order by ot.created_at, ot.id) as nth_for_agent
      from open_tasks ot
      join load l on l.department = ot.dept_key
      -- AN INDEPENDENT REVIEWER CARRYING THE DEPARTMENT'S ROUTINE QUEUE IS NOT INDEPENDENT OF IT.
      -- Review work still reaches them: the review action classes are the exception, and
      -- fn_pick_reviewer routes review directly rather than through this queue.
     where l.runtime_mode <> 'independent_reviewer'
        or coalesce(ot.action_class,'') in ('review','audit','verify','qa_gate','security_review',
                                            'compliance_check','legal_review','supplier_verify',
                                            'capability_review','self_review')
  ),
  chosen as (
    select task_id, agent_key from ranked
     where pick = 1 and (open_now + nth_for_agent) <= cap
  ),
  done as (
    update public.org_tasks t
       set assigned_agent = c.agent_key, updated_at = now()
      from chosen c
     where t.id = c.task_id and t.assigned_agent is null
    returning t.id
  )
  select (select count(*) from done), (select count(*) from open_tasks)
    into v_assigned, v_considered;

  v_no_capacity := v_considered - v_assigned;

  select string_agg(x.dept_key||' '||x.unowned||'/'||x.capacity, ', ' order by x.unowned desc)
    into v_saturated
    from (select t.dept_key, count(*) as unowned,
                 (select coalesce(sum(coalesce(a.max_open_tasks,6)),0) from public.org_agents a
                   where a.active and coalesce(a.available,true) and a.department = t.dept_key) as capacity
            from public.org_tasks t
           where t.assigned_agent is null and t.status in ('assigned','in_progress')
           group by t.dept_key
          having count(*) > 0
           order by count(*) desc
           limit 6) x;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('org_task_assign', now(), now(), 'ok',
          jsonb_build_object('considered', v_considered, 'assigned', v_assigned,
                             'left_unowned', v_no_capacity, 'oversubscribed', coalesce(v_saturated,'none')),
          'Assigned '||v_assigned||' of '||v_considered||' unowned open task(s) to a named employee '
          ||'in the owning department, skipping independent reviewers for non-review work. '
          ||v_no_capacity||' left unowned because no colleague in that department had capacity '
          ||'under max_open_tasks - deliberate: an unowned task is visible, an overloaded one is '
          ||'not. Departments carrying more open work than they staff (unowned/capacity): '
          ||coalesce(v_saturated,'none')||'.');

  return jsonb_build_object('considered', v_considered, 'assigned', v_assigned,
                            'left_unowned', v_no_capacity, 'oversubscribed', coalesce(v_saturated,'none'));
end
$function$;

-- ---------------------------------------------------------------------------------------------
-- 5. SPECIALIST AS A TOOL, AND HANDOFF AS A RECORD.
-- ---------------------------------------------------------------------------------------------
-- Which overlay a category loads, and who invokes it. The chain is Marketplace Director ->
-- RFQ Qualification Manager -> Inquiry Router -> the category overlay.
-- ROUTINE REMOVED 7 September 2026. public.fn_overlay_for_category was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- A manager invoking a specialist as a tool. The manager keeps the conversation; the specialist
-- returns a finding. Recorded, so "the specialist was consulted" is a fact and not a claim.
-- ROUTINE REMOVED 7 September 2026. public.fn_specialist_invoke was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- A handoff, where the specialist genuinely takes over. Exactly one accountable owner at a time.
-- ROUTINE REMOVED 7 September 2026. public.fn_role_handoff was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke all on function public.fn_overlay_for_category(text) from public;
revoke all on function public.fn_specialist_invoke(text,text,text,text,text) from public;
revoke all on function public.fn_role_handoff(text,text,text,text,text,jsonb) from public;
grant execute on function public.fn_overlay_for_category(text) to service_role;
grant execute on function public.fn_specialist_invoke(text,text,text,text,text) to service_role;
grant execute on function public.fn_role_handoff(text,text,text,text,text,jsonb) to service_role;

commit;
