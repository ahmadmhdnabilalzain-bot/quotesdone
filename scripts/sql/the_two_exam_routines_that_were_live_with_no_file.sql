-- THE TWO EXAM ROUTINES THAT WERE LIVE WITH NO FILE
--
-- Found by the canonical-routine check on PR #526: fn_certification_exam_compare and
-- fn_certification_exam_sit_semantic were running on production and defined in no repository file at
-- all. They were applied during this session's certification work by a background agent whose other
-- five routines live in a_failed_exam_becomes_ingested_knowledge_or_an_honest_gap.sql; these two never
-- got a home.
--
-- A live routine with no canonical file is exactly the drift this check exists to catch. It means
-- nobody can review what is running, a clean rebuild would not produce it, and the next person to
-- read the repository would conclude the estate does something it does not.
--
-- These definitions are read back verbatim from production, so applying this file is a no-op against
-- the current database and a correct build from empty.

-- fn_certification_exam_compare
CREATE OR REPLACE FUNCTION public.fn_certification_exam_compare()
 RETURNS TABLE(agent_key text, department text, certification text, pass_mark_pct numeric, lexical_pct numeric, lexical_passed boolean, semantic_pct numeric, semantic_passed boolean, better text, delta_pct numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with latest as (
    select distinct on (r.agent_key, r.certification, r.method)
           r.agent_key, r.certification, r.method, r.score_pct, r.passed, r.pass_mark_pct
      from public.certification_exam_result r
     order by r.agent_key, r.certification, r.method, r.sat_at desc, r.id desc
  )
  select rc.agent_key, a.department, rc.certification, rc.pass_mark_pct,
         lx.score_pct, lx.passed, sm.score_pct, sm.passed,
         case when lx.score_pct is null or sm.score_pct is null then null
              when sm.score_pct > lx.score_pct then 'semantic'
              when lx.score_pct > sm.score_pct then 'lexical'
              else 'tie' end,
         case when lx.score_pct is null or sm.score_pct is null then null
              else sm.score_pct - lx.score_pct end
    from public.role_certification rc
    join public.org_agents a on a.agent_key = rc.agent_key and a.active
    left join latest lx on lx.agent_key = rc.agent_key and lx.certification = rc.certification and lx.method = 'lexical'
    left join latest sm on sm.agent_key = rc.agent_key and sm.certification = rc.certification and sm.method = 'semantic'
   where lx.score_pct is not null or sm.score_pct is not null
   order by a.department, rc.agent_key, rc.rank, rc.certification;
$function$
;

-- fn_certification_exam_sit_semantic
CREATE OR REPLACE FUNCTION public.fn_certification_exam_sit_semantic(p_agent text, p_certification text)
 RETURNS certification_exam_result
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_min_support constant real := 0.80;  -- see the header: a floor against an absent corpus
  c_min_margin  constant real := 0.002;   -- see the header: this is the discriminator
  v_dept text; v_pass numeric;
  v_q record; v_best record; v_stemv vector(384);
  v_chosen char(1); v_ok boolean;
  v_answers jsonb := '[]'::jsonb;
  v_areas jsonb; v_n int; v_correct int; v_score numeric;
  v_row public.certification_exam_result;
begin
  select a.department into v_dept from public.org_agents a where a.agent_key = p_agent and a.active;
  if v_dept is null then
    raise exception 'fn_certification_exam_sit_semantic: % is not an active employee', p_agent;
  end if;
  select rc.pass_mark_pct into v_pass from public.role_certification rc
   where rc.agent_key = p_agent and rc.certification = p_certification;
  if v_pass is null then
    raise exception 'fn_certification_exam_sit_semantic: % does not hold % in role_certification', p_agent, p_certification;
  end if;
  if not exists (select 1 from public.certification_exam_question q where q.certification = p_certification) then
    raise exception 'fn_certification_exam_sit_semantic: no question bank for %', p_certification;
  end if;
  -- Refuse rather than mis-report. A bank whose vectors are missing would score every question as an
  -- abstention and write a 0% that looks like ignorance instead of an unfinished backfill.
  if exists (select 1 from public.certification_exam_question q
              where q.certification = p_certification
                and (select count(*) from public.certification_exam_question_vector v
                      where v.question_id = q.id) < 5) then
    raise exception 'fn_certification_exam_sit_semantic: % is not fully vectorised; run scripts/kb/embed_certification_questions.mjs', p_certification;
  end if;

  for v_q in
    select * from public.certification_exam_question q where q.certification = p_certification order by q.id
  loop
    select v.embedding into v_stemv from public.certification_exam_question_vector v
      where v.question_id = v_q.id and v.kind = 'stem';

    with ev as (
      -- the department's own operating knowledge, retrieved BY MEANING by the estate's own retriever
      select m.record_id, o.embedding_gte as emb
        from public.fn_ops_knowledge_match(v_stemv, p_agent, 20) m
        join public.ops_knowledge o on o.record_id = m.record_id
       where o.embedding_gte is not null
      union all
      -- the employee's own notes, the same twelve the lexical sitter reads
      select 'agent_knowledge:' || x.id, x.embedding_gte
        from (select ak.id, ak.embedding_gte
                from public.agent_knowledge ak
               where ak.agent_key = p_agent and ak.embedding_gte is not null
               order by ak.priority desc nulls last, ak.id
               limit 12) x
      union all
      -- the five nearest library chunks, where the lexical sitter takes the five the stem's fts matches
      select 'kb_chunks:' || y.id, y.embedding_gte
        from (select c.id, c.embedding_gte
                from public.kb_chunks c
               where c.embedding_gte is not null and v_stemv is not null
               order by c.embedding_gte <=> v_stemv
               limit 5) y
    ), opt as (
      select v.kind::char(1) as letter, v.embedding
        from public.certification_exam_question_vector v
       where v.question_id = v_q.id and v.kind <> 'stem'
    ), per as (
      -- one number per option: how close the CLOSEST thing the employee can reach comes to it
      select o.letter,
             max(1 - (e.emb <=> o.embedding))::real as s,
             (array_agg(e.record_id order by (e.emb <=> o.embedding)))[1] as record_id
        from opt o join ev e on true
       group by o.letter
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
      'evidence_scope',  'no_head',
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
    (agent_key, certification, questions, correct, score_pct, pass_mark_pct, passed, weakest_areas, answers, method)
  values
    (p_agent, p_certification, v_n, v_correct, v_score, v_pass, v_score >= v_pass, v_areas, v_answers, 'semantic')
  returning * into v_row;

  return v_row;
end $function$
;
