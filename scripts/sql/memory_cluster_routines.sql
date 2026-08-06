-- Spec file #2, components 11-13 (memory cluster) — the five routines.
--
-- Every change here has the same shape: something was being computed and thrown away.
--   * org_tasks.root_cause  — the diagnosis the agent wrote lives in result->>'deliverable' and the
--                             structured column stayed null on all 633 rows.
--   * agent_reputation      — 66 scored employees whose only reference was the function that wrote
--                             them, so a probation score changed nothing about who reviews work.
--   * institutional_memory  — fn_sop_update filtered on a vocabulary no writer of that table uses,
--                             so it ran weekly and wrote 0 runbooks out of 21 graded lessons.
--   * agent_memory          — fn_promote_memory had 0 callers, so nothing was ever promoted.
--
-- Apply:  node scripts/apply_sql.mjs scripts/sql/memory_cluster_routines.sql --promote
-- Then:   node scripts/apply_sql.mjs scripts/sql/memory_cluster_ddl.sql --promote --ddl

-- ---------------------------------------------------------------------------------------------
-- 1. A KPI-miss task may not close without a root cause.
--
-- The task text already asks the owner to "diagnose the cause", and the owners do: 7 of the 8
-- closed KPI-miss tasks carry a "Root cause" paragraph inside result->>'deliverable'. Nothing
-- lifted it into the column, so the next employee to miss the same target starts from zero.
-- The guard CAPTURES first and only refuses when there is genuinely no cause anywhere — demanding
-- a retype of something already written would just get worked around.
--
-- The needle is 'root[-_ ]?cause', not 'root cause'. Measured 6 Aug 2026: org_tasks #163 closed
-- with an empty column while its deliverable carried a paragraph headed "Root-cause hypothesis,
-- evidence-linked:" — one hyphen was the whole difference between a diagnosis captured and a
-- diagnosis lost, and it is the only KPI-miss task in the system that closed without a cause.
create or replace function public.fn_org_task_root_cause_guard()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare v_rc text;
begin
  if new.status = 'done' and coalesce(old.status, '') <> 'done'
     and new.title ilike 'KPI missed%' and coalesce(btrim(new.root_cause), '') = '' then

    v_rc := nullif(btrim(regexp_replace(
              coalesce(substring(coalesce(new.result ->> 'deliverable', '')
                                 from '(?i)root[-_ ]?cause[^\n]{0,250}'), ''),
              '\s+', ' ', 'g')), '');

    if v_rc is null then
      raise exception 'org_tasks #% (%) is a KPI-miss task and cannot close without root_cause: record the cause of the variance in org_tasks.root_cause, or state it under a "Root cause" heading in the deliverable and this trigger captures it.', new.id, left(new.title, 70);
    end if;

    new.root_cause := left(v_rc, 500);
  end if;
  return new;
end
$function$;

-- ---------------------------------------------------------------------------------------------
-- 2. Measured performance decides who reviews.
--
-- Same signature (p_dept_key text) — checked against pg_get_function_identity_arguments before
-- editing, because a different argument list would create an overload and leave fn_review_submit
-- calling the old body.
--
-- fn_reputation_recompute already demotes a probation-tier employee from autonomous to gated
-- authority. Reviewing someone else's work is an authority act, so a probation head does not stay
-- reviewer of record while a higher-scoring colleague is available. It does NOT hard-refuse: when
-- the department has no better-scoring alternative the head still reviews, because stranding a
-- department with reviewer=null is worse than a weak reviewer and would break fn_review_submit.
create or replace function public.fn_pick_reviewer(p_dept_key text)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_head text; v_ok boolean; v_delegate text; v_basis text;
        v_head_tier text; v_head_score numeric; v_score numeric;
begin
  select lead_agent into v_head from org_departments where dept_key = p_dept_key;

  if v_head is null then
    return jsonb_build_object('reviewer', null, 'available', false,
      'basis', 'no lead_agent recorded for department ' || p_dept_key);
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

  -- Explicit delegation first.
  select d.delegate_to, d.basis into v_delegate, v_basis
  from delegation_rule d
  join org_agents a on a.agent_key = d.delegate_to
  where d.active and d.dept_key = p_dept_key and d.when_agent = v_head
    and a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date)
  order by d.rank limit 1;

  -- Otherwise the best-performing available employee in the department, seniority breaking ties.
  -- This used to be seniority alone, which is the one ordering that cannot be affected by anything
  -- an employee does.
  if v_delegate is null then
    select a.agent_key,
           'highest-scoring available employee in ' || p_dept_key
             || ' (reputation ' || coalesce(p.score::text, 'unscored') || ')'
      into v_delegate, v_basis
    from org_agents a
    left join agent_reputation p on p.agent_key = a.agent_key
    where a.department = p_dept_key and a.agent_key <> v_head
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
end
$function$;

-- ---------------------------------------------------------------------------------------------
-- 3. SOP update: match the vocabulary that is actually written.
--
-- The old filter was `outcome in ('worse','improved')`, which is fn_outcome_evaluate's verdict
-- vocabulary. institutional_memory is written by several other paths that grade with 'success' /
-- 'success_over_dissent'. MEASURED on production 6 Aug 2026: the old filter matched 0 of 38 rows,
-- these four match 21 — the function ran every Monday and wrote nothing.
--
-- Constraining the column instead was the other option and was rejected on measurement: 10 rows
-- carry free-text narrative in `outcome`, so a constraint would either fail or require rewriting
-- other writers' data to fit this reader's vocabulary. 'no_change' and 'pending' stay excluded:
-- neither is a graded result worth codifying as a standard operating procedure.
--
-- The created_at window is gone too. It admitted only the last seven days, and since the function
-- had never written a row that excluded the entire backlog. The `not exists` clause is what
-- actually prevents rework, and it does so permanently rather than for a week.
--
-- os_runbooks.os_key is written. It was 0 of 31 rows while this function held the value in hand and
-- dropped it into `category` instead — one of the five columns spec file #2 names as "added but
-- never written to", and the only one of them this section owns. institutional_memory.os_key is
-- null on 70 of 100 rows, so the lesson's own task resolves the rest through the department that
-- did the work, and the department that recorded it after that. All 83 graded rows on production
-- resolve through one of the three. A lesson that resolves through none of them writes a null, and
-- comp-12-best-practices goes red on it — deliberately: the remedy is a department-to-OS mapping,
-- and a runbook nobody can route to an operating system is a runbook nobody will be handed.
create or replace function public.fn_sop_update()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; n_new int := 0; v_slug text;
begin
  for r in
    select m.id, m.headline, m.detail, m.outcome,
           coalesce(m.os_key,
                    (select d.os_key from org_tasks o join os_department d on d.dept_key = o.dept_key
                      where m.subject_type = 'org_task' and o.id::text = m.subject_id limit 1),
                    (select d.os_key from os_department d where d.dept_key = m.learned_by limit 1)) as os_key
    from institutional_memory m
    where m.outcome in ('worse', 'improved', 'success', 'success_over_dissent')
      and not exists (select 1 from os_runbooks b where b.slug = 'lesson-' || m.id)
    order by m.created_at desc
    limit 25
  loop
    v_slug := 'lesson-' || r.id;
    insert into os_runbooks (slug, title, category, when_to_use, steps, sort, os_key)
    values (v_slug, left(coalesce(r.headline, 'Lesson ' || r.id), 120),
            coalesce(r.os_key, 'operations'),
            case when r.outcome = 'worse'
              then 'Before repeating this change. It was tried and it made things worse.'
              else 'When this situation recurs. This approach was measured and it worked.' end,
            coalesce(r.detail, ''), 100, r.os_key);
    n_new := n_new + 1;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('sop_update', now(), now(), 'ok', jsonb_build_object('runbooks_written', n_new),
    'SOP update: ' || n_new || ' graded lesson(s) written into the runbook library so the company cannot repeat them by accident.');
  return jsonb_build_object('written', n_new);
end
$function$;

-- ---------------------------------------------------------------------------------------------
-- 4. The improvement plan reads the root causes the department already recorded.
--
-- This is the reader that makes org_tasks.root_cause a mechanism rather than a column: a diagnosis
-- written once now reaches the prompt of everyone in that department, which is the whole point of
-- the Variance -> Root Cause -> Improvement Plan chain in the blueprint.
create or replace function public.fn_improvement_plan_refresh()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare
  a record; v_parts text[]; v_line text; v_plan text;
  v_written int := 0; v_cleared int := 0;
begin
  for a in select agent_key, department from org_agents where active loop
    v_parts := array[]::text[];

    -- 1. What this department's work has been returned for, most recent first.
    select 'Your department has had ' || count(*) || ' deliverable(s) returned by review recently. '
        || 'The reasons on record: ' || string_agg(distinct left(m.detail, 120), '; ')
      into v_line
      from institutional_memory m
     where m.subject_type = 'org_task' and m.outcome = 'worse'
       and a.department = any(coalesce(m.visible_to, array[]::text[]))
       and m.created_at > now() - interval '30 days';
    if v_line is not null and v_line not like '%has had 0 %' then
      v_parts := v_parts || v_line;
    end if;

    -- 2. KPIs this employee owns that are behind. Their own targets, not the department's.
    select 'You own ' || count(*) || ' KPI(s) with a target you are not currently meeting: '
        || string_agg(k.kpi || ' (target ' || coalesce(k.target_value::text,'?') || ' ' || coalesce(k.unit,'') || ')', '; ')
      into v_line
      from employee_kpi k
     where k.agent_key = a.agent_key and k.active
       and exists (select 1 from goal_period g
                    where g.goal_key = k.serves_goal
                      and g.status in ('at_risk','missed','behind'));
    if v_line is not null and v_line not like '%own 0 KPI%' then
      v_parts := v_parts || v_line;
    end if;

    -- 3. Root causes already diagnosed against KPI misses in this department.
    select 'Root cause(s) already recorded against KPI misses in your department: '
        || string_agg(left(t.root_cause, 180), ' | ')
      into v_line
      from (select o.root_cause, o.updated_at
              from org_tasks o
             where o.dept_key = a.department
               and o.title ilike 'KPI missed%'
               and coalesce(o.root_cause, '') <> ''
             order by o.updated_at desc
             limit 2) t;
    if v_line is not null then v_parts := v_parts || v_line; end if;

    -- 4. Open findings the organisation has already recorded against this department.
    select 'Open findings against your department: ' || string_agg(left(s.finding, 110), '; ')
      into v_line
      from (select finding from self_review
             where coalesce(status,'open') not in ('done','implemented','rejected')
             order by created_at desc limit 2) s;
    if v_line is not null then v_parts := v_parts || v_line; end if;

    v_plan := nullif(array_to_string(v_parts, ' '), '');

    -- NULL when there is nothing on record. An empty plan is honest; a generic one is noise that
    -- would reach 66 prompts and mean nothing in any of them.
    update org_agents set improvement_plan = left(v_plan, 900) where agent_key = a.agent_key;
    if v_plan is null then v_cleared := v_cleared + 1; else v_written := v_written + 1; end if;
  end loop;

  return jsonb_build_object('agents', v_written + v_cleared,
                            'with_a_plan', v_written, 'nothing_on_record', v_cleared);
end
$function$;

-- ---------------------------------------------------------------------------------------------
-- 5a. Promotion refuses a memory that is already long-term.
--
-- agent_memory.horizon was the fourth of the five columns that exist and mean nothing: 233 rows
-- carried a value, 184 short and 49 long, and the ONLY routine that consulted it was
-- fn_promote_memory_sweep — which also sets it. A distinction maintained solely by its own
-- maintainer is decorative, and comp-12-short-term scored MISSING on exactly that, correctly.
--
-- This is the moment in the system where short and long have to mean different things: promotion IS
-- the short-to-long transition. Promoting a memory that is already long-term is not a no-op, it
-- writes a second kb_chunk for content already in the knowledge base, and the ledger's own
-- "already promoted" guard misses it whenever the earlier promotion came from another path.
-- Signature unchanged (bigint, text, text) — a different argument list would create an OVERLOAD and
-- leave fn_promote_memory_sweep calling the old body.
create or replace function public.fn_promote_memory(p_memory_id bigint, p_category text, p_by text default 'founder')
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare m record; v_chunk_id bigint;
begin
  select * into m from public.agent_memory where id = p_memory_id;
  if not found then raise exception 'memory % not found', p_memory_id; end if;
  if coalesce(m.horizon, 'short') <> 'short' then
    raise exception 'memory % is already long-term (horizon=%): promotion is the short-to-long transition and there is nothing left to promote', p_memory_id, m.horizon;
  end if;
  if exists (select 1 from public.memory_promotions where memory_id = p_memory_id) then
    raise exception 'memory % already promoted', p_memory_id;
  end if;
  insert into public.kb_chunks(source_kind, source_id, category, title, content, citation, effective_date)
  values('memory', p_memory_id::text, coalesce(nullif(p_category,''),'general'),
         left(m.content, 80), m.content,
         'agent_memory #'||p_memory_id||' ('||coalesce(m.agent_key,'?')||')', current_date)
  returning id into v_chunk_id;
  insert into public.memory_promotions(memory_id, kb_chunk_id, category, promoted_by)
  values(p_memory_id, v_chunk_id, coalesce(nullif(p_category,''),'general'), p_by);
  return v_chunk_id;
end $function$;

-- ---------------------------------------------------------------------------------------------
-- 5. The sweeper that gives fn_promote_memory a caller.
--
-- fn_promote_memory is per-memory and had zero callers, so memory_promotions had never held a row
-- and short-term memory was never promoted to long-term — the distinction the blueprint draws was
-- decorative. The selection rule is the promotion criterion, stated once here: a LEARNED memory
-- (instructions are long-term by definition, reflections are moment-in-time), at least a week old
-- so it has survived contact with more work, and substantial enough to be worth a knowledge-base
-- chunk. Everything else stays short-term.
create or replace function public.fn_promote_memory_sweep(p_limit integer default 20)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; n int := 0; n_err int := 0;
begin
  for r in
    select m.id, coalesce(g.department, 'general') as dept
      from agent_memory m
      left join org_agents g on g.agent_key = m.agent_key
     where coalesce(m.horizon, 'short') = 'short'
       and m.kind = 'learned'
       and m.created_at < now() - interval '7 days'
       and length(coalesce(m.content, '')) >= 120
       and not exists (select 1 from memory_promotions p where p.memory_id = m.id)
       and not exists (select 1 from kb_chunks c
                        where c.source_kind = 'memory' and c.source_id = m.id::text)
     order by m.created_at
     limit greatest(coalesce(p_limit, 20), 0)
  loop
    begin
      perform fn_promote_memory(r.id, r.dept, 'memory_sweeper');
      update agent_memory set horizon = 'long' where id = r.id;
      n := n + 1;
    exception when others then
      -- One unpromotable row must not stop the sweep forever; it is counted, not swallowed.
      n_err := n_err + 1;
    end;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('memory_promotion', now(), now(), case when n_err > 0 then 'partial' else 'ok' end,
          jsonb_build_object('promoted', n, 'failed', n_err),
    'Memory promotion sweep: ' || n || ' short-term learned memory(ies) at least a week old promoted '
    || 'into the knowledge base and marked long-term, ' || n_err || ' could not be promoted.');
  return jsonb_build_object('promoted', n, 'failed', n_err);
end
$function$;
