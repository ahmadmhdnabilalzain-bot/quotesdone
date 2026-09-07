-- A SECOND EXAMINER THAT SCORES BY MEANING, AND A REPORT THAT SHOWS BOTH.
--
-- The founder's objection to the first sitting, verbatim: "but are they doing key word searches to
-- answer?" They were. fn_certification_exam_sit scores every option with ts_rank_cd plus a trigram
-- tiebreak against the evidence the employee can reach. That is lexical overlap: a distractor that
-- happens to share vocabulary with a stored document beats the key, and a key phrased differently from
-- the source loses however well the employee "knows" the subject. bookkeeper sat ACCA at 6/40 = 15%
-- with 25 abstentions under that instrument and nobody could say how much of the 15% was the library
-- and how much was the instrument.
--
-- fn_certification_exam_sit_semantic is the same exam, the same evidence and the same rules, scored by
-- COSINE between the option's gte-small vector and the vectors of the evidence the employee can reach.
-- Nothing paid is involved anywhere: every vector comes from the free in-region gte-small that embedded
-- ops_knowledge and kb_chunks, precomputed once into certification_exam_question_vector by
-- scripts/kb/embed_certification_questions.mjs. Results are stamped method='semantic' so the two
-- examiners never mix, and fn_certification_exam_compare puts them side by side.
--
-- ============================ THE EVIDENCE, AND ONE HONEST OMISSION ============================
-- The lexical sitter reaches for four things. This one reaches for the same four minus one:
--   * its department's ops_knowledge — via fn_ops_knowledge_match, the estate's own cosine retriever,
--     which resolves the employee's department, dept scope, module scope and packaged roles exactly as
--     the runtime does, and which the LEXICAL sitter's fn_ops_knowledge_search mirrors keyword-side.
--     Same k = 20.
--   * its own agent_knowledge — top 12 by priority, as the lexical sitter takes them. These had no
--     vector at all until the companion file added agent_knowledge.embedding_gte.
--   * kb_chunks — the 5 nearest to the question stem, where the lexical sitter takes the 5 whose fts
--     matches the stem.
--   * THE HEAD IS OMITTED, deliberately, and this is the one place the two examiners differ.
--     fn_agent_context(agent, 19500) returns ~23,000 characters. gte-small has a 512-token window and
--     every embedding in this estate is computed over the first 1,200 characters of its text: a single
--     384-dimensional vector "for the head" would be a vector for its first 5%, and scoring an option
--     against it would be a measurement of the wrong subject dressed as a measurement. Chunking the
--     head per sitting would mean embedding 23 kB inside the exam, which is the per-sitting cost this
--     whole design exists to avoid. The omission is safe in substance because the head is ASSEMBLED
--     from ops_knowledge and fn_company_hard_rules — the ops_knowledge half is in the evidence above,
--     by meaning and unclipped. It is recorded in the answer JSON as evidence_scope='no_head' so no
--     reader ever assumes otherwise.
--
-- ============================ THE FLOORS, MEASURED NOT GUESSED ============================
-- Measured on production 7 Sep 2026 (see the run log in the commit body), over the three sittings
-- reported with this change, scoring every option against the evidence above:
--
--   * BEST-EVIDENCE COSINE (s1) DOES NOT SEPARATE A RIGHT ANSWER FROM A WRONG ONE. Across the sampled
--     banks s1 sat in a narrow high band (bookkeeper/ACCA: p05 0.827, median 0.859, max 0.903) whether
--     the winning option was the key or a distractor. That is the estate's own recorded lens — "a
--     nearest neighbour is always found": an HNSW search over 9,140 ops_knowledge rows and 1.1M
--     embedded kb_chunks returns its best row for ANY option, and its cosine says how close the corpus
--     comes, not whether the option is true. A support floor therefore cannot be the discriminator
--     here, and any floor set inside that band would abstain on everything or on nothing. It is kept
--     as what it honestly is — a floor against a bank the library has nothing about at all — and set
--     at 0.80, just under the measured 5th percentile of s1, so it fires when the corpus is
--     genuinely absent and never pretends to grade.
--
--   * THE RELATIVE MARGIN IS THE DISCRIMINATOR, and it is what the floor is set on. Swept over 160
--     questions — bookkeeper/ACCA, payments_manager/CAMS, legal/CIPP/E, collections/CICM Level 3, four
--     banks and four departments, every question scored against that employee's own evidence:
--
--       margin floor   answered   right   accuracy OF ANSWERED   score (abstention = wrong)
--         0.000         160/160     54           33.8%                 33.8%
--         0.001         126/160     49           38.9%                 30.6%
--         0.002         105/160     43           41.0%                 26.9%
--         0.005          70/160     28           40.0%                 17.5%
--         0.010          25/160     12           48.0%                  7.5%
--
--     Accuracy of the answered questions climbs monotonically to 0.002 and then stops climbing while
--     coverage keeps collapsing — past that point the floor is buying abstentions, not confidence, and
--     since an abstention counts WRONG a higher floor converts a knowledge measurement into an
--     abstention measurement (which is exactly what happened to the lexical sitter: 25 of its 40
--     abstentions are most of its 15%). 0.002 IS THE CHOSEN POINT: the last floor where the confidence
--     gain is real and consistent across all four banks, still answering roughly two questions in
--     three, abstaining only where the top two options are within 0.2% of one another — which in a
--     384-dimensional space is a genuine tie, not a decision.
--
--     Read honestly, the ceiling here is low: 33.8% top-1 agreement against a 25% chance baseline. That
--     is the number, and it says the same thing the founder suspected from the other direction — a
--     retriever scoring four plausible options against a corpus is a WEAK examiner, whether it scores
--     by words or by meaning. What it is NOT is the lexical instrument's 15%, and the difference is
--     what fn_certification_exam_compare exists to show.
--
--   * The option encoding was measured too, and the first attempt was wrong. Options were first
--     embedded with their stem prefixed; the stem dominates the vector, all four options collapsed onto
--     one direction (median relative margin 0.0028) and top-1 agreement with the key was 30%. Embedded
--     ALONE — the exact semantic counterpart of fn_exam_or_tsquery, which strips the stem's words from
--     each option's query — the median margin was 0.0101 and top-1 agreement 45% on the same 40
--     questions. The vectors on production are option-alone.
--
-- Everything else is deliberately identical to the lexical sitter so the comparison means something:
-- the same 40 questions in the same order, abstention counts WRONG, the same weakest_areas rollup, the
-- same certification_exam_result row.
--
-- Apply:
--   node scripts/apply_sql.mjs scripts/sql/a_second_examiner_scores_the_exam_by_meaning_not_by_word_overlap.sql --apply --ddl

create or replace function public.fn_certification_exam_sit_semantic(p_agent text, p_certification text)
 returns public.certification_exam_result
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
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
end $function$;

revoke execute on function public.fn_certification_exam_sit_semantic(text, text) from public, anon, authenticated;

-- ------------------------------------------------------------------------------------------------
-- THE REPORT THE FOUNDER ASKED FOR: how much of a failure was the instrument, how much the library.
-- One row per employee and certification, the latest sitting under each examiner side by side. A NULL
-- score means that examiner has not sat that pairing yet, which is different from a zero and is shown
-- as such.
create or replace function public.fn_certification_exam_compare()
 returns table(agent_key text, department text, certification text, pass_mark_pct numeric,
               lexical_pct numeric, lexical_passed boolean,
               semantic_pct numeric, semantic_passed boolean,
               better text, delta_pct numeric)
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
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
$function$;

revoke execute on function public.fn_certification_exam_compare() from public, anon, authenticated;

-- The ownership ledger follows the manifest.
insert into public.kernel_routine_ownership
  (schema_name, routine_name, identity_args, ownership_class, classified_by_rule, evidence, source_kind, source_file)
values
  ('public', 'fn_certification_exam_sit_semantic', 'p_agent text, p_certification text',
   'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT',
   'the second examiner scores by cosine, not word overlap (7 Sep 2026)', 'MANIFEST',
   'scripts/sql/a_second_examiner_scores_the_exam_by_meaning_not_by_word_overlap.sql'),
  ('public', 'fn_certification_exam_compare', '',
   'QUOTESDONE_APPLICATION', 'R4_MANIFEST_DEFINES_IT',
   'both examiners side by side, so a failure separates the instrument from the library (7 Sep 2026)', 'MANIFEST',
   'scripts/sql/a_second_examiner_scores_the_exam_by_meaning_not_by_word_overlap.sql')
on conflict (schema_name, routine_name, identity_args) do update set
  ownership_class = excluded.ownership_class, classified_by_rule = excluded.classified_by_rule,
  evidence = excluded.evidence, source_kind = excluded.source_kind, source_file = excluded.source_file;
