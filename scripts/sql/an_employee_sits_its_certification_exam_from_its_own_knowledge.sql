-- An employee sits its certification exam from its own knowledge — deterministically, no paid model.
--
-- The founder's rule (6 Sep 2026): "test all agents. if they dont pass them all, then their knowledge
-- is simply not enough." The exam therefore has to measure the KNOWLEDGE THE EMPLOYEE ACTUALLY HAS,
-- not a language model's general competence. So the sitter never calls a model. For each question it
-- assembles the evidence that employee can really reach —
--   * its own head, public.fn_agent_context(agent, 19500) — the hard rules, its role, its playbooks;
--   * public.fn_ops_knowledge_search(department, ...) — the same department-scoped retrieval the
--     playbook binder uses (fn_dept_scope / fn_dept_module_scope live inside it; not re-implemented);
--   * its own public.agent_knowledge rows;
--   * public.kb_chunks matched by the question stem (an AND query: the corpus is 2.6M rows and an OR
--     query over it ranks for ~100s, which would make a 40-question exam unrunnable);
-- — and then scores the four options against that evidence with Postgres full text:
--   score(option) = max over evidence docs of ts_rank_cd(doc, OR-of-the-option's-own-lexemes, 32)
--                   + 0.02 * word_similarity(option, doc)      [pg_trgm, tiebreak only]
-- The QUESTION STEM (plus all four options) forms the RETRIEVAL query, so the evidence set contains
-- the discriminating material; each OPTION forms its own SCORING query, so the four options are
-- separated by what the evidence supports rather than by what they share.
--
-- ABSTENTION. Two thresholds, both deliberately conservative:
--   c_min_support = 0.25 — scores are ts_rank_cd with normalisation 32, i.e. rank/(rank+1), bounded
--     into [0,1). 0.25 is a raw rank of 0.33: roughly three distinctive lexeme hits inside a single
--     document. Below it the employee has no evidence for the option it likes best and would only be
--     guessing.
--   c_min_margin  = 0.15 (relative) — the winner must beat the runner-up by 15% of its own score.
--     Relative rather than absolute because the bounded scale compresses towards 1 once an option is
--     well supported; below the margin the employee cannot TELL THE OPTIONS APART, which is not an
--     answer either.
-- An abstention records chosen = null and counts as WRONG. There is no random tiebreak anywhere: the
-- same employee, bank and knowledge produce the same answers every time (the check proves this by
-- sitting one employee twice inside an aborted transaction).
--
-- Apply: node scripts/apply_sql.mjs scripts/sql/an_employee_sits_its_certification_exam_from_its_own_knowledge.sql --apply --ddl

drop function if exists public.fn_exam_or_tsquery(text);

-- The OR-of-lexemes query for one option, minus the words it shares with p_exclude. That exclusion is
-- what makes the four options separable: every option repeats the question stem's vocabulary, so a
-- query that keeps those words scores all four alike on any long document (on a probe question the
-- employee's own head scored 37.5 for every option and the margin vanished into noise). What
-- discriminates an option is the vocabulary the stem does NOT already contain.
create or replace function public.fn_exam_or_tsquery(p_text text, p_exclude text default null)
 returns tsquery
 language plpgsql
 immutable
 set search_path to 'public', 'pg_temp'
as $function$
declare v_words text[]; v_stop text[]; v_q tsquery;
begin
  v_stop := array(select w from unnest(regexp_split_to_array(
                    lower(regexp_replace(coalesce(p_exclude,''),'[^a-z0-9 ]',' ','g')),'\s+')) w);
  v_words := array(select distinct w from unnest(regexp_split_to_array(
                     lower(regexp_replace(coalesce(p_text,''),'[^a-z0-9 ]',' ','g')),'\s+')) w
                   where length(w) > 2 and not (w = any(v_stop)));
  if array_length(v_words,1) is null then return null; end if;
  begin
    v_q := to_tsquery('english', array_to_string(v_words,' | '));
  exception when others then return null; end;
  if v_q::text = '' then return null; end if;
  return v_q;
end $function$;

create or replace function public.fn_certification_exam_sit(p_agent text, p_certification text)
 returns public.certification_exam_result
 language plpgsql
 volatile
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  c_min_support constant real := 0.25;   -- see the header: bounded rank, about three distinctive hits
  c_min_margin  constant real := 0.15;   -- relative: the winner must clear the runner-up by 15%
  v_dept text; v_pass numeric; v_head text;
  v_q record; v_best record; v_terms text; v_stem tsquery;
  v_chosen char(1); v_ok boolean;
  v_answers jsonb := '[]'::jsonb;
  v_areas jsonb; v_n int; v_correct int; v_score numeric;
  v_row public.certification_exam_result;
begin
  select a.department into v_dept from public.org_agents a where a.agent_key = p_agent and a.active;
  if v_dept is null then
    raise exception 'fn_certification_exam_sit: % is not an active employee', p_agent;
  end if;
  select rc.pass_mark_pct into v_pass from public.role_certification rc
   where rc.agent_key = p_agent and rc.certification = p_certification;
  if v_pass is null then
    raise exception 'fn_certification_exam_sit: % does not hold % in role_certification', p_agent, p_certification;
  end if;
  if not exists (select 1 from public.certification_exam_question q where q.certification = p_certification) then
    raise exception 'fn_certification_exam_sit: no question bank for %', p_certification;
  end if;

  v_head := coalesce(public.fn_agent_context(p_agent, 19500), '');

  for v_q in
    select * from public.certification_exam_question q where q.certification = p_certification order by q.id
  loop
    v_terms := concat_ws(' ', v_q.question, v_q.option_a, v_q.option_b, v_q.option_c, v_q.option_d);
    v_stem  := plainto_tsquery('english', v_q.question);

    with ev as (
      select ('head:' || p_agent)::text as record_id, v_head as content
      union all
      select k.record_id, concat_ws(' ', k.title, k.content)
        from public.fn_ops_knowledge_search(v_dept, v_terms, 20) k
      union all
      select 'agent_knowledge:' || x.id, concat_ws(' ', x.topic, x.content)
        from (select ak.id, ak.topic, ak.content
                from public.agent_knowledge ak
               where ak.agent_key = p_agent
               order by ak.priority desc nulls last, ak.id
               limit 12) x
      union all
      select 'kb_chunks:' || y.id, concat_ws(' ', y.title, y.content)
        from (select c.id, c.title, c.content
                from public.kb_chunks c
               where v_stem is not null and c.fts @@ v_stem
               order by c.id
               limit 5) y
    ), evt as (
      select record_id, to_tsvector('english', content) as tsv, content from ev where content is not null
    ), opt(letter, txt) as (
      values ('A', v_q.option_a), ('B', v_q.option_b), ('C', v_q.option_c), ('D', v_q.option_d)
    ), oq as (
      select letter, txt, public.fn_exam_or_tsquery(txt, v_q.question) as q from opt
    ), sc as (
      select o.letter, e.record_id,
             -- normalisation 32 bounds ts_rank_cd into [0,1) as rank/(rank+1), so a 23,000-character
             -- head and a 400-character knowledge record sit on one scale and an absolute support
             -- threshold means the same thing against either.
             (ts_rank_cd(e.tsv, o.q, 32) + 0.02 * word_similarity(o.txt, e.content))::real as s
        from oq o join evt e on true
       where o.q is not null
    ), per as (
      select distinct on (letter) letter, record_id, s from sc order by letter, s desc, record_id
    ), rk as (
      select letter, record_id, s, row_number() over (order by s desc, letter) as rn from per
    )
    select (select letter    from rk where rn = 1) as letter,
           (select record_id from rk where rn = 1) as record_id,
           coalesce((select s from rk where rn = 1), 0)::real as s1,
           coalesce((select s from rk where rn = 2), 0)::real as s2
      into v_best;

    if v_best.letter is null
       or v_best.s1 < c_min_support
       or (v_best.s1 - v_best.s2) < c_min_margin * v_best.s1 then
      v_chosen := null;                                  -- abstained: counts as wrong
    else
      v_chosen := v_best.letter;
    end if;
    v_ok := (v_chosen is not null and v_chosen = v_q.correct_option);

    v_answers := v_answers || jsonb_build_object(
      'question_id',     v_q.id,
      'syllabus_area',   v_q.syllabus_area,
      'chosen',          v_chosen,
      'key',             v_q.correct_option,
      'correct',         v_ok,
      'abstained',       (v_chosen is null),
      'score',           round(v_best.s1::numeric, 4),
      'margin',          round((v_best.s1 - v_best.s2)::numeric, 4),
      'evidence_record', case when v_chosen is null then null else v_best.record_id end);
  end loop;

  v_n := jsonb_array_length(v_answers);
  select count(*) filter (where (e->>'correct')::boolean) into v_correct
    from jsonb_array_elements(v_answers) e;
  v_score := round(100.0 * v_correct / greatest(v_n,1), 2);

  select coalesce(jsonb_agg(jsonb_build_object('syllabus_area', area, 'asked', asked, 'correct', ok)
                            order by (ok::numeric / asked), area), '[]'::jsonb)
    into v_areas
    from (select coalesce(e->>'syllabus_area','(unstated)') as area,
                 count(*) as asked,
                 count(*) filter (where (e->>'correct')::boolean) as ok
            from jsonb_array_elements(v_answers) e group by 1) t;

  insert into public.certification_exam_result
    (agent_key, certification, questions, correct, score_pct, pass_mark_pct, passed, weakest_areas, answers)
  values
    (p_agent, p_certification, v_n, v_correct, v_score, v_pass, v_score >= v_pass, v_areas, v_answers)
  returning * into v_row;

  return v_row;
end $function$;

-- Sit every pair that has a real bank behind it. A bank under 40 questions is not the exam the body
-- publishes, so it is skipped rather than sat at a shorter length that would flatter the score.
create or replace function public.fn_certification_exam_sit_all()
 returns table(agent_key text, certification text, questions int, score_pct numeric, pass_mark_pct numeric, passed boolean)
 language plpgsql
 volatile
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare p record; r public.certification_exam_result;
begin
  for p in
    select rc.agent_key, rc.certification
      from public.role_certification rc
      join public.org_agents a on a.agent_key = rc.agent_key and a.active
     where (select count(*) from public.certification_exam_question q
             where q.certification = rc.certification) >= 40
     order by rc.agent_key, rc.rank, rc.certification
  loop
    r := public.fn_certification_exam_sit(p.agent_key, p.certification);
    agent_key := r.agent_key; certification := r.certification; questions := r.questions;
    score_pct := r.score_pct; pass_mark_pct := r.pass_mark_pct; passed := r.passed;
    return next;
  end loop;
end $function$;

-- One row per employee: what it was assigned, what it has sat (latest sitting per certification),
-- and the syllabus areas it did worst in across the certifications it failed.
create or replace function public.fn_certification_exam_summary()
 returns table(agent_key text, department text, assigned int, sat int, passed int, failed int, worst_areas text[])
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
  with latest as (
    select distinct on (r.agent_key, r.certification) r.*
      from public.certification_exam_result r
     order by r.agent_key, r.certification, r.sat_at desc, r.id desc
  ), weak as (
    select l.agent_key, w->>'syllabus_area' as area,
           sum((w->>'asked')::int) as asked,
           sum((w->>'correct')::int) as ok
      from latest l, jsonb_array_elements(l.weakest_areas) w
     where not l.passed
     group by 1,2
  )
  select a.agent_key, a.department,
         (select count(*)::int from public.role_certification rc where rc.agent_key = a.agent_key),
         (select count(*)::int from latest l where l.agent_key = a.agent_key),
         (select count(*)::int from latest l where l.agent_key = a.agent_key and l.passed),
         (select count(*)::int from latest l where l.agent_key = a.agent_key and not l.passed),
         (select array_agg(x.area order by (x.ok::numeric / x.asked), x.area)
            from (select * from weak w where w.agent_key = a.agent_key
                   order by (w.ok::numeric / w.asked), w.area limit 5) x)
    from public.org_agents a
   where a.active
   order by a.department, a.agent_key;
$function$;

revoke execute on function public.fn_exam_or_tsquery(text, text) from public, anon, authenticated;
revoke execute on function public.fn_certification_exam_sit(text, text) from public, anon, authenticated;
revoke execute on function public.fn_certification_exam_sit_all() from public, anon, authenticated;
revoke execute on function public.fn_certification_exam_summary() from public, anon, authenticated;

delete from public.kernel_routine_ownership
 where schema_name = 'public'
   and routine_name in ('fn_exam_or_tsquery','fn_certification_exam_sit','fn_certification_exam_sit_all','fn_certification_exam_summary');
insert into public.kernel_routine_ownership
  (schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file)
values
  ('public','fn_exam_or_tsquery','p_text text, p_exclude text','QUOTESDONE_APPLICATION','R4_MANIFEST_DEFINES_IT','defined by the manifest file that builds the certification exam sitter','MANIFEST','scripts/sql/an_employee_sits_its_certification_exam_from_its_own_knowledge.sql'),
  ('public','fn_certification_exam_sit','p_agent text, p_certification text','QUOTESDONE_APPLICATION','R4_MANIFEST_DEFINES_IT','defined by the manifest file that builds the certification exam sitter','MANIFEST','scripts/sql/an_employee_sits_its_certification_exam_from_its_own_knowledge.sql'),
  ('public','fn_certification_exam_sit_all','','QUOTESDONE_APPLICATION','R4_MANIFEST_DEFINES_IT','defined by the manifest file that builds the certification exam sitter','MANIFEST','scripts/sql/an_employee_sits_its_certification_exam_from_its_own_knowledge.sql'),
  ('public','fn_certification_exam_summary','','QUOTESDONE_APPLICATION','R4_MANIFEST_DEFINES_IT','defined by the manifest file that builds the certification exam sitter','MANIFEST','scripts/sql/an_employee_sits_its_certification_exam_from_its_own_knowledge.sql');
