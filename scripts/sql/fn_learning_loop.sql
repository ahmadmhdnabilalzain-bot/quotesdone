-- "EVERY COMPLETED TASK SHOULD GENERATE LEARNING" — 104 tasks done, 31 lesson rows, and
-- institutional_memory frozen for nine days while outcome_evaluate_daily reported 8/8 successes.
--
-- Spec file #1, "Employees Must Learn": every completed task should generate learning — what
-- worked, what failed, what can be improved. What existed instead was dept_learn_daily writing
-- per-department-per-day DIGESTS (and writing zero of them on two of the last three days), so the
-- claim was false by a factor of three and the grain was wrong: a digest cannot say which task
-- taught what.
--
-- The lesson is written by the REVIEWER, deterministically, at the moment the verdict is known.
-- No model call: the review already establishes what was wrong (which rule, which severity, which
-- department dissented and why), and that is the lesson. A rejection is the most valuable record
-- this loop can produce and it was the one being thrown away.

-- ---------------------------------------------------------------------------------------------
-- 1. LAYER 4 MUST BE ABLE TO CHANGE. fn_agent_institutional_memory ordered by `confidence desc,
-- occurred_at desc` with limit 6 — so the six highest-confidence rows won permanently and nothing
-- learned afterwards could ever reach an agent. That is a memory that cannot learn, which is the
-- opposite of the section it implements. Ordered by recency now, with confidence as a FILTER
-- rather than the sort key: routine approvals are recorded for the audit trail at 0.5 and stay out
-- of the prompt, while rejections (0.85) and curated lessons (0.95) surface newest-first.
create or replace function public.fn_agent_institutional_memory(p_agent_key text, p_limit integer default 6)
returns text
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_dept text; v_cat text; out text := ''; r record;
begin
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
end; $function$;

-- ---------------------------------------------------------------------------------------------
-- 2. The reviewer records the lesson.
create or replace function public.fn_task_lesson(p_task_id bigint, p_outcome text, p_review jsonb)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare
  t record; v_id bigint; v_kind text; v_conf numeric; v_detail text; v_what text;
begin
  select o.id, o.dept_key, o.title, o.action_class, o.tier from org_tasks o
    into t where o.id = p_task_id;
  if t.id is null then return null; end if;

  -- What the review actually found, in the review's own words. Violations first because a failure
  -- is the lesson; dissents next; otherwise the approval and who gave it.
  select string_agg(distinct (v->>'rule') || ' (' || (v->>'severity') || '): ' || coalesce(v->>'why',''), ' | ')
    into v_detail from jsonb_array_elements(coalesce(p_review->'violations','[]'::jsonb)) v;

  if v_detail is null or v_detail = '' then
    select string_agg((d->>'by') || ' ' || (d->>'stance') || ': ' || left(coalesce(d->>'reasoning',''), 300), ' | ')
      into v_detail from jsonb_array_elements(coalesce(p_review->'dissents','[]'::jsonb)) d;
  end if;

  if p_outcome = 'published' and (v_detail is null or v_detail = '') then
    v_kind   := 'lesson';
    v_conf   := 0.5;   -- recorded for the audit trail; below fn_agent_institutional_memory's 0.6 floor
    v_detail := 'Cleared the quality standard for a department deliverable on the first pass and was '
             || 'approved by ' || coalesce(p_review->>'reviewer','the department head') || ' and the Chief of Staff.';
    v_what   := 'success';
  elsif p_outcome = 'published' then
    v_kind   := 'lesson_learned';
    v_conf   := 0.85;  -- shipped OVER a recorded objection: the most useful thing to remember
    v_detail := 'Approved and published despite a recorded objection. ' || v_detail;
    v_what   := 'success_over_dissent';
  else
    v_kind   := 'lesson_learned';
    v_conf   := 0.85;
    v_detail := 'Returned by review (' || p_outcome || '). ' || coalesce(v_detail, 'see review_chain');
    v_what   := 'worse';
  end if;

  insert into institutional_memory
    (kind, subject_type, subject_id, headline, detail, outcome, learned_by, confidence,
     evidence_ref, visible_to, occurred_at)
  values (v_kind, 'org_task', t.id::text,
          left(t.dept_key || ': ' || coalesce(t.title,'(untitled task)'), 200),
          left(v_detail, 2000), v_what, t.dept_key, v_conf,
          'review_chain:org_task:' || t.id, array[t.dept_key], now())
  returning id into v_id;

  return v_id;
end $function$;

comment on function public.fn_task_lesson(bigint, text, jsonb) is
  'Writes the lesson from a reviewed department task into institutional_memory, per task rather '
  'than per department-day. Deterministic: the review verdict IS the lesson, so no model call. '
  'Routine first-pass approvals are recorded at confidence 0.5 (audit trail only); rejections and '
  'ships-over-dissent at 0.85, which is above fn_agent_institutional_memory''s 0.6 floor and so '
  'reaches every agent in the department through LAYER 4.';
