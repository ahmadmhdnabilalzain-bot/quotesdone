-- THE EXAM SAMPLES ITS OWN SCOPE AND NEVER WRITES A WRONG VERDICT (6 Sep 2026). Knowledge audit company_wide.md §4, action #5.
--
-- MEASURED. fn_knowledge_exam_sit topped an employee's question bank up from ops_knowledge rows where
-- `dept_key = v_dept or dept_key is null` - and 1,204 of the 2,095 null-dept rows are supplier-category
-- route files (scope_type = 'category'). 506 of the 591 bank questions of the 54 active employees are
-- the template "What does the company's operating knowledge say about: <title>?"; 135 of them point
-- at a category record, 116 of those for employees outside marketplace (the CTO was examined on
-- Warehousing & 3PL; people_ops on bakery equipment and lifts). When the lexeme grader returned
-- 'wrong' or 'not_covered' the reference text was INSERTED into agent_knowledge as an `experience`
-- row (author_verified, confidence 0.85) - 147 category-YAML fills sit in non-marketplace employees
-- (129 of them in active ones, 56 agents), and 268 fills across 79 agents were written on a 'wrong'
-- verdict: the employee HAD a row on the topic and the grader scored its lexeme overlap under 0.3,
-- which a lexeme grader cannot tell apart from a differently-worded correct answer. Those rows then
-- rendered in LAYER 4 as what the organisation has learned.
--
-- THE MECHANISM, fixed in fn_knowledge_exam_sit:
--   * fn_exam_record_in_scope(dept, record_id): the record is in the employee's scope exactly as the
--     retrieval paths define it - fn_dept_scope + fn_dept_module_scope, company/external_source, an
--     unowned workflow - and a category-pack record is in scope for marketplace only.
--   * The bank is topped up only from in-scope records; the sitting asks only in-scope questions (the
--     polluted questions stay in the table - results reference them - and are simply never asked
--     again; the top-up threshold counts in-scope questions only, so a polluted bank refills).
--   * A fill happens only on 'not_covered' - the employee holds NOTHING on the topic - never on 'wrong'.
--
-- THE DATA, quarantined (never deleted): validation_status = 'quarantined' with the reason appended to
-- supporting_evidence on (a) every category-pack fill held by an employee outside marketplace and
-- (b) every fill written on a 'wrong' verdict. Quarantined rows leave LAYER 4 (fn_agent_context reads
-- only non-quarantined experience) and the exam corpus.
--
--   node scripts/apply_sql.mjs scripts/sql/the_exam_samples_its_own_scope_and_never_writes_a_wrong_verdict.sql --apply --ddl

begin;

create or replace function public.fn_exam_record_in_scope(p_dept text, p_record_id text)
returns boolean
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  select exists (
    select 1 from public.ops_knowledge o
     where o.record_id = p_record_id
       and o.runtime_eligible
       and (
            o.dept_key = any(public.fn_dept_scope(p_dept))
         or o.module = any(public.fn_dept_module_scope(p_dept))
         or o.scope_type in ('company','external_source')
         or (o.scope_type = 'workflow' and o.dept_key is null)
         or (o.scope_type = 'category' and p_dept = 'marketplace')
       )
       and (o.scope_type <> 'category' or p_dept = 'marketplace'));
$function$;

revoke execute on function public.fn_exam_record_in_scope(text, text) from public, anon, authenticated;
grant execute on function public.fn_exam_record_in_scope(text, text) to service_role;

CREATE OR REPLACE FUNCTION public.fn_knowledge_exam_sit(p_agent text, p_questions integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

  -- 1. the bank: top up from verified operating knowledge IN THIS EMPLOYEE'S SCOPE when fewer than 10
  --    in-scope questions exist. Scope = fn_exam_record_in_scope: the retrieval paths' own predicate.
  select count(*) into v_bank from public.knowledge_exam_questions x
   where x.agent_key = p_agent
     and (x.topic not like 'ops:%' or public.fn_exam_record_in_scope(v_dept, substring(x.topic from 5)));
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
           and public.fn_exam_record_in_scope(v_dept, record_id)
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

  -- 3. the sitting: the least-recently-asked IN-SCOPE questions first. A question the bank acquired
  --    from another department's rows or a category pack is never asked again.
  for q in
    select id, question, reference_answer, topic
      from public.knowledge_exam_questions x
     where x.agent_key = p_agent
       and (x.topic not like 'ops:%' or public.fn_exam_record_in_scope(v_dept, substring(x.topic from 5)))
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

    -- 4. learning: ONLY a gap - the employee holds nothing on the topic - is written into what it
    --    holds. A 'wrong' verdict is a lexeme-overlap score under 0.3 against a row the employee DOES
    --    hold; writing the reference over that is how 268 rows of other departments' text became
    --    "what this organisation has learned". Never again.
    v_kid := null;
    if v_verdict = 'not_covered' and q.topic like 'ops:%' and v_fill_left > 0 then
      v_rec_id := null; v_rec_title := null; v_rec_content := null;
      select record_id, title, content into v_rec_id, v_rec_title, v_rec_content from public.ops_knowledge
       where record_id = substring(q.topic from 5) and runtime_eligible
         and validation_status in ('reviewed', 'source_verified', 'validated', 'author_verified')
         and public.fn_exam_record_in_scope(v_dept, record_id);
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

-- ---------------------------------------------------------------------------------------------
-- THE DATA. Quarantine, with the reason on the row. Never a delete.
-- ---------------------------------------------------------------------------------------------
-- (a) category-pack fills held by an employee outside marketplace
update public.agent_knowledge k
   set validation_status = 'quarantined',
       supporting_evidence = coalesce(k.supporting_evidence, '')
         || ' | QUARANTINED 2026-09-06: supplier-category route file written by the retrieval exam into an employee outside marketplace (source '
         || k.source_ref || '); the exam now samples only the employee''s own scope. Kept for the record; not served.'
 where k.layer = 'experience'
   and k.source_ref like 'ops_knowledge:%'
   and coalesce(k.validation_status, '') <> 'quarantined'
   and k.agent_key not like 'cat:%'
   and not exists (select 1 from public.org_agents a where a.agent_key = k.agent_key and a.department = 'marketplace')
   and exists (select 1 from public.ops_knowledge o where o.record_id = substring(k.source_ref from 15) and o.scope_type = 'category');

-- (b) fills written on a 'wrong' verdict
update public.agent_knowledge k
   set validation_status = 'quarantined',
       supporting_evidence = coalesce(k.supporting_evidence, '')
         || ' | QUARANTINED 2026-09-06: written by the retrieval exam on a WRONG verdict (lexeme overlap < 0.3 against a row the employee already held) - a grader score, not a fact the employee lacked. Kept for the record; not served.'
  from public.knowledge_exam_results r
 where r.knowledge_id = k.id
   and r.verdict = 'wrong' and r.filled
   and coalesce(k.validation_status, '') <> 'quarantined';

-- PROOF, in-file and read-only afterwards.
do $proof$
declare n_cat int; n_wrong int; n_l4 int;
begin
  select count(*) into n_cat from public.agent_knowledge k
   where k.layer = 'experience' and k.source_ref like 'ops_knowledge:%' and coalesce(k.validation_status,'') <> 'quarantined'
     and k.agent_key not like 'cat:%'
     and not exists (select 1 from public.org_agents a where a.agent_key = k.agent_key and a.department = 'marketplace')
     and exists (select 1 from public.ops_knowledge o where o.record_id = substring(k.source_ref from 15) and o.scope_type = 'category');
  select count(*) into n_wrong from public.knowledge_exam_results r join public.agent_knowledge k on k.id = r.knowledge_id
   where r.verdict = 'wrong' and r.filled and coalesce(k.validation_status,'') <> 'quarantined';
  if n_cat <> 0 or n_wrong <> 0 then raise exception 'still served: % category fills outside marketplace, % wrong-verdict fills', n_cat, n_wrong; end if;
  -- the scope predicate refuses a category record for a non-marketplace employee and admits it for marketplace
  if public.fn_exam_record_in_scope('exec', (select record_id from public.ops_knowledge where scope_type = 'category' limit 1)) then
    raise exception 'fn_exam_record_in_scope admitted a category record for exec';
  end if;
  if not public.fn_exam_record_in_scope('people_ops', (select record_id from public.ops_knowledge where dept_key = 'hr' and runtime_eligible limit 1)) then
    raise exception 'fn_exam_record_in_scope refused an hr record for people_ops';
  end if;
end $proof$;

commit;
