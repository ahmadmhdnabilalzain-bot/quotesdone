-- REORGANISING THE AGENT COMPANY - 16: reviewer independence survives the alias.
--
-- SECTION 3 of the closure brief asks for proof that "merged aliases cannot make one employee
-- appear as two reviewers". Measured on production, 14 Aug 2026, they could - in all ten
-- departments, every time:
--
--   dept                 head            author passed as                       reviewer returned
--   assurance            qa_manager      qa-and-testing-analyst-controller      qa_manager
--   customer_experience  followup        customer_success                       followup
--   data_intel           intel_director  analytics_director                     intel_director
--   exec                 ceo             CEO AI                                 ceo
--   finance              cfo             Finance Director                       cfo
--   growth               sales_director  chief_revenue_officer                  sales_director
--   legal                legal           general_counsel                        legal
--   marketplace          procurement     marketplace_director                   procurement
--   people_ops           ops_director    administration-and-operations-director ops_director
--   product_eng          cto             CTO AI                                 cto
--
-- Passing the SAME author under its canonical key correctly returned an independent reviewer in
-- nine of the ten (exec correctly refused). So the guard added when the 182 self-approvals were
-- found works - and is defeated by spelling. fn_org_agent_resolve resolves every one of those
-- aliases to the head; fn_pick_reviewer simply never called it.
--
-- This is the fourth instance of the recurring root cause in this codebase: a decision addressed
-- to an identity the resolver knows, taken by a path that compares raw strings instead of asking.
--
-- Two functions get one line each, and then a trigger makes the property structural rather than
-- dependent on every future caller remembering. Historical rows are untouched: the trigger fires
-- BEFORE INSERT and the 285 existing self-review rows are the subject of the register, not of a
-- rewrite.

begin;

CREATE OR REPLACE FUNCTION public.fn_pick_reviewer(p_dept_key text, p_author text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_head text; v_ok boolean; v_delegate text; v_basis text;
        v_head_tier text; v_head_score numeric; v_score numeric; v_up text;
begin
  -- THE AUTHOR ARRIVES UNDER WHATEVER NAME THE CALLER HAD (14 Aug 2026).
  -- Every comparison below is a raw string test - p_author = v_head, and three
  -- "a.agent_key is distinct from p_author" filters. All ten department heads carry aliases, so
  -- an author passed as 'finance_ai', 'marketplace_director' or 'CEO AI' was not equal to 'cfo',
  -- 'procurement' or 'ceo', the guard did not fire, and this function returned the author as its
  -- own reviewer. Measured on production before this line: 10 of 10 departments.
  -- Resolving once here fixes every comparison at the same time, because they all read p_author.
  p_author := coalesce(public.fn_org_agent_resolve(p_author), p_author);

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
$function$
;

CREATE OR REPLACE FUNCTION public.fn_review_submit(p_subject_type text, p_subject_id text, p_dept_key text, p_author text, p_content text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  -- CANONICAL AUTHOR, OR THE LEDGER CANNOT SEE ITS OWN SELF-REVIEWS.
  -- review_chain.author_agent was written with whatever string the caller passed while
  -- reviewer_agent was always resolved. A head authoring under an alias therefore produced a row
  -- whose author and reviewer were the SAME employee under two names - and every self-review
  -- count in this system is "author_agent = reviewer_agent", which such a row passes.
  -- So the reported zero was a property of the spelling, not of the behaviour.
  p_author := coalesce(public.fn_org_agent_resolve(p_author), p_author);

  -- Who is actually able to approve for this department right now, GIVEN WHO WROTE IT.
  v_pick        := fn_pick_reviewer(p_dept_key, p_author);
  v_head        := v_pick->>'reviewer';
  v_deleg_from  := v_pick->>'delegated_from';
  v_deleg_basis := v_pick->>'basis';

  -- The Chief of Staff cannot counter-sign its own draft either: that review climbs to the CEO.
  if p_author = coalesce(public.fn_org_agent_resolve(v_cos), v_cos) then v_cos := 'ceo'; end if;

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
$function$
;

-- ---------------------------------------------------------------------------------------------
-- THE INVARIANT, ENFORCED WHERE NO CALLER CAN MISS IT.
-- ---------------------------------------------------------------------------------------------
-- The two fixes above are correct and would hold until the next function writes review_chain
-- directly. Section 3 asks specifically that "direct database functions cannot bypass the
-- restriction", so the rule lives on the table.
--
-- It canonicalises both sides first, so this catches the alias case rather than only the
-- identical-string case that was already impossible to write by accident. Rows with no reviewer
-- (the 'drafted' stage) are untouched.
create or replace function public.trg_review_chain_no_self_review()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare v_a text; v_r text;
begin
  if new.author_agent is null or new.reviewer_agent is null then return new; end if;

  v_a := coalesce(public.fn_org_agent_resolve(new.author_agent), new.author_agent);
  v_r := coalesce(public.fn_org_agent_resolve(new.reviewer_agent), new.reviewer_agent);

  if v_a = v_r then
    raise exception
      'review_chain refuses a self-review: author "%" and reviewer "%" are the same employee (%). %',
      new.author_agent, new.reviewer_agent, v_a,
      'Call fn_pick_reviewer(dept, author) and use what it returns; if it returns no reviewer, escalate.'
      using errcode = 'check_violation';
  end if;

  -- Store both sides canonical, so every count over this table measures employees and not spelling.
  new.author_agent   := v_a;
  new.reviewer_agent := v_r;
  return new;
end $function$;

drop trigger if exists a00_review_chain_no_self_review on review_chain;
-- a00_ prefix: BEFORE triggers fire in NAME order, and this one must canonicalise before anything
-- else on this table reads the two columns.
create trigger a00_review_chain_no_self_review
  before insert or update on review_chain
  for each row execute function public.trg_review_chain_no_self_review();

-- trg_review_chain_no_self_review is CREATEd here for the first time, so it carries the default
-- EXECUTE to PUBLIC. A trigger function is never called directly; nothing should hold it.
-- (fn_pick_reviewer and fn_review_submit above are CREATE OR REPLACE of existing routines, which
-- preserves their ACL - revoking there would change an access decision this file is not making.)
revoke all on function public.trg_review_chain_no_self_review() from public, anon, authenticated;

commit;
