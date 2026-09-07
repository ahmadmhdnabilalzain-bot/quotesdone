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
-- ROUTINE REMOVED 7 September 2026. public.fn_sop_update was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ---------------------------------------------------------------------------------------------
-- 4. The improvement plan reads the root causes the department already recorded.
--
-- This is the reader that makes org_tasks.root_cause a mechanism rather than a column: a diagnosis
-- written once now reaches the prompt of everyone in that department, which is the whole point of
-- the Variance -> Root Cause -> Improvement Plan chain in the blueprint.
-- ROUTINE REMOVED 7 September 2026. public.fn_improvement_plan_refresh was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


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
-- ROUTINE REMOVED 7 September 2026. public.fn_promote_memory was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ---------------------------------------------------------------------------------------------
-- 5. The sweeper that gives fn_promote_memory a caller.
--
-- fn_promote_memory is per-memory and had zero callers, so memory_promotions had never held a row
-- and short-term memory was never promoted to long-term — the distinction the blueprint draws was
-- decorative. The selection rule is the promotion criterion, stated once here: a LEARNED memory
-- (instructions are long-term by definition, reflections are moment-in-time), at least a week old
-- so it has survived contact with more work, and substantial enough to be worth a knowledge-base
-- chunk. Everything else stays short-term.
-- ROUTINE REMOVED 7 September 2026. public.fn_promote_memory_sweep was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

