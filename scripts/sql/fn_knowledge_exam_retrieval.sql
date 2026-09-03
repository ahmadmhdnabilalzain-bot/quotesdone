-- THE KNOWLEDGE EXAM SITS WITHOUT A MODEL (3 Sep 2026).
--
-- employee-learning-progress: "an employee's learning progress is visible in their workspace". The
-- drawer renders exam_days / exam_score_pct / exam_trend from knowledge_exam_results; the DB leg
-- wants at least two dated results for every active employee, and 71 of 71 had fewer — the only
-- writer was the knowledge_exam edge function (model-graded, cron 135, off since 16 Aug; last
-- result 15 Aug), and 53 active employees have never sat an exam at all.
--
-- A real employee does not stop learning because the tutor is away. This is a RETRIEVAL exam,
-- deterministic end to end, and it says so on every row it writes:
--
--   the question bank  — the model-written questions where they exist; otherwise questions
--                        generated from the company's own verified operating knowledge
--                        (ops_knowledge: the employee's department, then company-wide records),
--                        "What does the company's operating knowledge say about: <title>?", with
--                        the record's content as the reference answer. Topic 'ops:<record_id>'
--                        keeps the provenance.
--   the sitting        — for each question, the best-matching item in what the employee actually
--                        holds (agent_knowledge: its own rows plus the '_global' rows every
--                        employee inherits), by full-text rank against the question. That excerpt
--                        is the examinee's answer.
--   the grade          — the share of the reference answer's lexemes (english stemmer, stopwords
--                        removed, 4+ chars) present in that excerpt: >= 0.6 correct, >= 0.3
--                        partial, else wrong; no match at all is not_covered. grader_confidence
--                        carries the share; grader_answer carries the reference; converged is
--                        true because the same corpus gives the same grade.
--   the learning       — a not_covered or wrong question generated from a verified ops record is
--                        FILLED: the reference is written into the employee's agent_knowledge
--                        (layer experience, topic 'exam:<question_id> <title>', source_ref
--                        ops_knowledge:<record_id>), at most 3 per employee per sitting, exactly
--                        as the model loop filled verified gaps. filled / knowledge_id record it.
--
-- What this does NOT claim: a retrieval grade measures whether the employee's knowledge base can
-- answer, not whether a reasoning step would. The model exam, when the runtime is on, layers
-- judgement on top; it does not gate learning into dormancy.
--
-- Five questions per employee per sitting, every active employee, daily at 03:23 UTC as
-- knowledge_exam_retrieval_daily, wrapped through the kernel under the knowledge director like the
-- other knowledge crons.

create or replace function public.fn_knowledge_exam_sit(p_agent text, p_questions integer default 5)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  q record;
  v_dept text; v_bank int; v_gen int := 0;
  v_best_id bigint; v_best_topic text; v_best_tsv tsvector; v_q tsquery;
  v_ref_lex text[]; v_hit int; v_cov numeric; v_verdict text; v_fill_left int := 3;
  v_kid bigint; v_rec_id text; v_rec_title text; v_rec_content text;
  n_asked int := 0; n_correct int := 0; n_filled int := 0;
begin
  -- scalars, not a record: a record that is never assigned raises on its first field reference
  select department into v_dept from public.org_agents where agent_key = p_agent and active;
  if not found then
    return jsonb_build_object('agent', p_agent, 'ok', false, 'error', 'not an active employee');
  end if;

  -- 1. the bank: top up from verified operating knowledge when fewer than 10 questions exist
  select count(*) into v_bank from public.knowledge_exam_questions where agent_key = p_agent;
  if v_bank < 10 then
    insert into public.knowledge_exam_questions (agent_key, question, reference_answer, topic, difficulty, times_asked)
    select p_agent,
           'What does the company''s operating knowledge say about: ' || k.title || '?',
           left(k.content, 700), 'ops:' || k.record_id, 'core', 0
      from (
        select record_id, title, content,
               row_number() over (partition by (dept_key is null) order by md5(record_id || p_agent)) rn,
               (dept_key is null) companywide
          from public.ops_knowledge
         where runtime_eligible
           and validation_status in ('reviewed', 'source_verified', 'validated', 'author_verified')
           and coalesce(btrim(title), '') <> '' and length(coalesce(content, '')) >= 80
           and (dept_key = v_dept or dept_key is null)
           and not exists (select 1 from public.knowledge_exam_questions x
                            where x.agent_key = p_agent and x.topic = 'ops:' || ops_knowledge.record_id)
      ) k
     where (not k.companywide and k.rn <= 3) or (k.companywide and k.rn <= 2)
     order by k.companywide, k.rn;
    get diagnostics v_gen = row_count;
  end if;

  -- 2. what the employee actually holds
  create temporary table if not exists _exam_corpus (id bigint, agent_key text, topic text, tsv tsvector) on commit drop;
  delete from _exam_corpus;
  insert into _exam_corpus
  select id, agent_key, topic, to_tsvector('english', coalesce(topic, '') || ' ' || left(content, 6000))
    from public.agent_knowledge
   where agent_key in (p_agent, '_global') and coalesce(validation_status, '') <> 'quarantined';

  -- 3. the sitting: the least-recently-asked questions first
  for q in
    select id, question, reference_answer, topic
      from public.knowledge_exam_questions
     where agent_key = p_agent
     order by last_asked asc nulls first, times_asked asc, id
     limit greatest(p_questions, 1)
  loop
    select array_agg(distinct w.lexeme) into v_ref_lex
      from unnest(to_tsvector('english', coalesce(q.reference_answer, ''))) w
     where length(w.lexeme) >= 4;

    -- The retrieval query is the question's own significant lexemes, ANY of them (websearch's
    -- AND over every word of "What does the company's operating knowledge say about: X?" matched
    -- almost nothing); the generated questions' boilerplate prefix is stripped so the subject
    -- terms decide the rank. 'simple' because the lexemes are already stemmed.
    select to_tsquery('simple', string_agg('''' || replace(w.lexeme, '''', '''''') || '''', ' | ')) into v_q
      from unnest(to_tsvector('english',
             regexp_replace(coalesce(q.question, ''), '^What does the company''s operating knowledge say about: ', ''))) w
     where length(w.lexeme) >= 4;
    v_best_id := null; v_best_topic := null; v_best_tsv := null;
    if v_q is not null then
      select c.id, c.topic, c.tsv into v_best_id, v_best_topic, v_best_tsv
        from _exam_corpus c
       where c.tsv @@ v_q
       order by ts_rank(c.tsv, v_q) desc, c.id
       limit 1;
    end if;

    if v_best_id is null or v_ref_lex is null or cardinality(v_ref_lex) = 0 then
      v_verdict := 'not_covered'; v_cov := 0;
    else
      select count(*) into v_hit from unnest(v_ref_lex) l where v_best_tsv @@ plainto_tsquery('simple', l);
      v_cov := round(v_hit::numeric / cardinality(v_ref_lex), 2);
      v_verdict := case when v_cov >= 0.6 then 'correct' when v_cov >= 0.3 then 'partial' else 'wrong' end;
    end if;

    -- 4. learning: a verified ops record the employee could not answer from is written into what it holds
    v_kid := null;
    if v_verdict in ('not_covered', 'wrong') and q.topic like 'ops:%' and v_fill_left > 0 then
      v_rec_id := null; v_rec_title := null; v_rec_content := null;
      select record_id, title, content into v_rec_id, v_rec_title, v_rec_content from public.ops_knowledge
       where record_id = substring(q.topic from 5) and runtime_eligible
         and validation_status in ('reviewed', 'source_verified', 'validated', 'author_verified');
      if v_rec_id is not null
         and not exists (select 1 from public.agent_knowledge k where k.agent_key = p_agent and k.source_ref = 'ops_knowledge:' || v_rec_id) then
        insert into public.agent_knowledge (agent_key, topic, content, priority, layer, source_ref, owner_agent, confidence, validation_status)
        values (p_agent, 'exam:' || q.id || ' ' || left(v_rec_title, 160), left(v_rec_content, 4000), 50, 'experience',
                'ops_knowledge:' || v_rec_id, p_agent, 0.85, 'author_verified')
        returning id into v_kid;
        v_fill_left := v_fill_left - 1; n_filled := n_filled + 1;
      end if;
    end if;

    insert into public.knowledge_exam_results
      (agent_key, question_id, examinee_answer, verdict, grader_answer, grader_confidence, converged, gap_fact, filled, knowledge_id)
    values (p_agent, q.id,
            case when v_best_id is null then 'NOT_COVERED' else 'retrieved from agent_knowledge #' || v_best_id || ' (' || left(coalesce(v_best_topic, ''), 120) || ')' end,
            v_verdict,
            'retrieval grader, reference: ' || left(coalesce(q.reference_answer, ''), 700),
            v_cov, true,
            case when v_verdict <> 'correct' then left(coalesce(q.reference_answer, ''), 700) end,
            v_kid is not null, v_kid);

    update public.knowledge_exam_questions set times_asked = coalesce(times_asked, 0) + 1, last_asked = now() where id = q.id;
    n_asked := n_asked + 1;
    if v_verdict = 'correct' then n_correct := n_correct + 1; end if;
  end loop;

  return jsonb_build_object('agent', p_agent, 'ok', true, 'asked', n_asked, 'correct', n_correct,
                            'filled', n_filled, 'generated', v_gen);
end $function$;

revoke execute on function public.fn_knowledge_exam_sit(text, integer) from public, anon, authenticated;

-- Every active employee sits, one tick.
create or replace function public.fn_knowledge_exam_retrieval()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare a record; r jsonb; n_agents int := 0; n_asked int := 0; n_correct int := 0; n_filled int := 0;
begin
  for a in select agent_key from public.org_agents where active order by agent_key loop
    r := public.fn_knowledge_exam_sit(a.agent_key, 5);
    n_agents := n_agents + 1;
    n_asked := n_asked + coalesce((r->>'asked')::int, 0);
    n_correct := n_correct + coalesce((r->>'correct')::int, 0);
    n_filled := n_filled + coalesce((r->>'filled')::int, 0);
  end loop;
  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('knowledge_exam', now(), now(), 'ok',
          jsonb_build_object('agents', n_agents, 'asked', n_asked, 'correct', n_correct, 'filled', n_filled, 'grader', 'retrieval'),
          'Retrieval exam: ' || n_agents || ' employee(s) sat ' || n_asked || ' question(s), ' || n_correct
            || ' answered from their own knowledge, ' || n_filled || ' verified gap(s) written into it. No model.');
  return jsonb_build_object('agents', n_agents, 'asked', n_asked, 'correct', n_correct, 'filled', n_filled);
end $function$;

revoke execute on function public.fn_knowledge_exam_retrieval() from public, anon, authenticated;

begin;
do $$
declare v_job bigint;
begin
  select jobid into v_job from cron.job where jobname = 'knowledge_exam_retrieval_daily';
  if v_job is null then
    v_job := cron.schedule('knowledge_exam_retrieval_daily', '23 3 * * *', 'select public.fn_knowledge_exam_retrieval();');
  end if;
  perform public.fn_kernel_wrap_and_enable_cron(v_job, 'knowledge_director', 'data_intel', 'knowledge_publish');
  update public.phase_c_component
     set repair_or_keep_action = 'built 3 Sep 2026: the deterministic retrieval exam every active employee sits daily (scripts/sql/fn_knowledge_exam_retrieval.sql)',
         evidence = 'scheduled and wrapped 3 Sep 2026 as the daily retrieval exam; pure SQL, no model'
   where component_id = 'cron:knowledge_exam_retrieval_daily';
  insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
  values (v_job, 'knowledge_exam_retrieval_daily',
          'Pure SQL: INSERTs knowledge_exam_questions (from verified ops_knowledge), knowledge_exam_results (one per question sat), agent_knowledge (at most 3 filled gaps per employee, layer experience), and one agent_runs row. No HTTP, no model.',
          'Daily 03:23 UTC; own transaction on a scheduled tick; reads and writes only rows keyed by real org_agents.agent_key; a scenario''s fixtures carry ZZ DEMO names and qd_run tags and are torn down by the run that made them; close() asserts scenario rows by id/marker.')
  on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;
  insert into public.cron_registry (jobname, human_name, category, purpose)
  values ('knowledge_exam_retrieval_daily', 'Retrieval knowledge exam', 'Knowledge',
          'Daily 03:23 UTC: every active employee sits five questions graded by retrieval over its own knowledge; verified gaps are written into agent_knowledge. No model.')
  on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
end $$;
commit;

do $ctl$
begin
  if not exists (select 1 from cron.job where jobname = 'knowledge_exam_retrieval_daily' and active and command ilike '%fn_kernel_cron_exec%') then
    raise exception 'knowledge_exam_retrieval_daily is not active and wrapped';
  end if;
end $ctl$;
