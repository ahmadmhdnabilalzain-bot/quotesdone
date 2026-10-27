-- A REHEARSAL FILES NO KNOWLEDGE GAP, AND ITS CHAT ROWS CARRY ITS RUN TAG (customer_support, 27 Oct 2026).
-- Seat: customer_support (owner of the conversation bank and its harness). sales_engineer owns fn_sales_assist; the
-- change to it is the rehearsal branch only.
--
-- MEASURED 27 Oct 2026 (PR #1635, production). One session of scripts/e2e/live_seat_conversations.mjs - 22 scenarios,
-- about 270 portal turns as ZZ DEMO customers - left behind after its own teardown:
--   assistant_logs             273  one per answered turn, audience 'customer:<id>' of a customer since deleted
--   sales_decision_log         269  one per turn, query = the scripted customer message
--   support_reply_readability  273  demo = false: support_reply.ts sets p_demo only for a message starting "ZZ DEMO"
--   sales_knowledge_gap         97  and 97 org_tasks (sales_engineer, knowledge_gap) - tasks nobody confirmed
-- They were removed by hand, matched by the md5 of the bank's scripted texts. The scheduled daily slice
-- (seat-exam-and-gap-audit.yml step 7) would have made the same every day.
--
-- 1. fn_e2e_rehearsal_tag(): the run tag of THIS request, when it names a real rehearsal window (open or closed).
--    It is fn_e2e_run_tag_current() - honoured only for a service-role request whose edge function already checked
--    the run's proof (_shared/e2e_run.ts), or app.e2e_run_tag set inside a SQL session - plus the window lookup,
--    so a tag that names no run marks nothing.
-- 2. assistant_logs, sales_decision_log and support_reply_readability gain e2e_run_tag, stamped BEFORE INSERT by
--    a00_chat_row_e2e_run_tag (null for all real traffic). A tagged readability row is demo = true, so the monthly
--    self-review never counts a rehearsal. The harness's teardown (scripts/lib/demo_factory.mjs) deletes by the tag,
--    and closeRun's leftovers() counts by it, so a run that leaves a row fails visibly.
-- 3. fn_sales_assist (portal) and fn_support_knowledge_gap (widget) file NO gap and NO org_task for a rehearsal, and
--    do not raise an existing gap's count or its task's priority. The reply is unchanged apart from the task number,
--    so the bank still measures what a customer sees. Both bodies are otherwise the canonical ones, byte for byte:
--    fn_sales_assist from the_sales_engineer_could_not_see_the_faq_and_an_arabic_question_arrived_as_question_marks.sql,
--    fn_support_knowledge_gap from the_working_week_is_monday_to_friday_in_the_database_too.sql.
--
-- CREATE OR REPLACE keeps the ACL of the two existing routines (service_role only); the two NEW routines are revoked.
-- Prevented by: scripts/checks/a_rehearsal_leaves_no_chat_rows_and_files_no_task.test.mjs.

create or replace function public.fn_e2e_rehearsal_tag()
returns text language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_tag text;
begin
  v_tag := public.fn_e2e_run_tag_current();
  if v_tag is null or v_tag !~ '^[a-z0-9]{4,16}$' then return null; end if;
  if not exists (select 1 from public.rehearsal_window w where w.run_tag = 'qd_run:' || v_tag) then return null; end if;
  return v_tag;
exception when others then
  return null;
end $fn$;
revoke execute on function public.fn_e2e_rehearsal_tag() from public, anon, authenticated;
comment on function public.fn_e2e_rehearsal_tag() is
  'The harness run tag of this request when it names a rehearsal_window row, else null. Built on fn_e2e_run_tag_current (service-role header or app.e2e_run_tag). A rehearsal files no knowledge gap or task, and its chat rows carry the tag for teardown.';

alter table public.assistant_logs            add column if not exists e2e_run_tag text;
alter table public.sales_decision_log        add column if not exists e2e_run_tag text;
alter table public.support_reply_readability add column if not exists e2e_run_tag text;
create index if not exists assistant_logs_e2e_run_tag_idx            on public.assistant_logs (e2e_run_tag) where e2e_run_tag is not null;
create index if not exists sales_decision_log_e2e_run_tag_idx        on public.sales_decision_log (e2e_run_tag) where e2e_run_tag is not null;
create index if not exists support_reply_readability_e2e_run_tag_idx on public.support_reply_readability (e2e_run_tag) where e2e_run_tag is not null;
comment on column public.assistant_logs.e2e_run_tag is
  'Run tag of the harness rehearsal that wrote this row (a00_chat_row_e2e_run_tag). Null for all real traffic. Teardown deletes by it.';
comment on column public.sales_decision_log.e2e_run_tag is
  'Run tag of the harness rehearsal that wrote this row (a00_chat_row_e2e_run_tag). Null for all real traffic. Teardown deletes by it.';
comment on column public.support_reply_readability.e2e_run_tag is
  'Run tag of the harness rehearsal that wrote this row (a00_chat_row_e2e_run_tag); such a row is also demo. Null for all real traffic.';

create or replace function public.fn_chat_row_e2e_run_tag()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  new.e2e_run_tag := coalesce(new.e2e_run_tag, public.fn_e2e_rehearsal_tag());
  if new.e2e_run_tag is not null and tg_table_name = 'support_reply_readability' then
    new.demo := true;
  end if;
  return new;
exception when others then
  return new;   -- the chat row is never lost to its tag
end $fn$;
revoke execute on function public.fn_chat_row_e2e_run_tag() from public, anon, authenticated;

drop trigger if exists a00_chat_row_e2e_run_tag on public.assistant_logs;
create trigger a00_chat_row_e2e_run_tag before insert on public.assistant_logs
  for each row execute function public.fn_chat_row_e2e_run_tag();
drop trigger if exists a00_chat_row_e2e_run_tag on public.sales_decision_log;
create trigger a00_chat_row_e2e_run_tag before insert on public.sales_decision_log
  for each row execute function public.fn_chat_row_e2e_run_tag();
drop trigger if exists a00_chat_row_e2e_run_tag on public.support_reply_readability;
create trigger a00_chat_row_e2e_run_tag before insert on public.support_reply_readability
  for each row execute function public.fn_chat_row_e2e_run_tag();

create or replace function public.fn_sales_assist(p_text text, p_embedding vector, p_min_similarity numeric DEFAULT 0.86, p_min_rank numeric DEFAULT 0.05, p_k integer DEFAULT 5, p_actor text DEFAULT 'sales_engineer'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_k         int := greatest(1, least(coalesce(p_k, 5), 20));
  -- Per-corpus candidate width. Wider than the answer width so the floors have something to reject
  -- and the decision log records the near-misses that justify the floor.
  v_wide      int := greatest(v_k * 4, 20);
  -- LEXICAL-ONLY ADMISSION BAR. Applied only to rows with no embedding, where there is no vector
  -- to corroborate with. Deliberately 4x p_min_rank's default: it is carrying the whole burden of
  -- proof on its own. Measured basis in the report accompanying this file.
  -- Floored at 0.20 but never BELOW p_min_rank, so a caller that raises the corroboration bar
  -- raises this one too. Without that tie the lexical-only route would be untestable: the probe
  -- that proves a floor bites by raising it above the best hit would leave this route wide open
  -- and conclude the floors do not fire. A gate nobody can prove fires is not a gate.
  c_lex_only  numeric := greatest(0.20, coalesce(p_min_rank, 0));
  -- ponytail: kb_chunks lexical route takes the first 4,000 index matches and ranks those, not the
  -- global best of 2.5m unembedded rows. Ranking every match of a common term would be a table
  -- scan on every portal message. Raise it, or embed the rest, if recall proves short.
  c_kb_scan   int := 4000;
  -- Out of scope by the company's own exclusion, and by slug so it cannot drift.
  c_fnb       text[] := array['cat:catering-companies','cat:bakery-equipment-suppliers',
                              'cat:food-processing-equipment-suppliers','cat:hospitality-supplies-companies',
                              'cat:cold-room-and-refrigeration-suppliers'];
  v_tq        tsquery;
  -- The Arabic arm. company_faq is the only corpus this routine reads that is written in both
  -- languages (22 of its 508 approved rows carry Arabic, measured 18 Sep 2026), and it is the
  -- only corpus here with no precomputed tsvector, so both configurations are built on the fly
  -- for it at no structural cost. fn_ar_norm is the same normaliser fn_support_corpus_search
  -- uses, so an Arabic question reaches an Arabic FAQ by exactly one rule, not two.
  --
  -- AND IT NEEDS THE BEST-TERMS FALLBACK, because the estate has already paid for learning why.
  -- scripts/sql/an_arabic_question_is_not_six_words_that_must_all_appear.sql measured it on
  -- production: the 'arabic' text-search configuration Postgres ships has NO STOPWORD LIST, so
  -- ما / هي / عن / كم / في survive as ordinary content lexemes and websearch_to_tsquery ANDs every
  -- one of them. A nine-word Arabic question then demands one FAQ containing all nine words and
  -- ranks 0.0000 — and because a vector-bearing row here must ALSO corroborate lexically, a good
  -- Arabic embedding hit would be thrown out for want of corroboration that could never arrive.
  -- The Arabic arm would have been a column in a greatest() that contributes nothing.
  --
  -- So the same shape fn_support_corpus_search settled on is used here: the strict query first,
  -- and the SAME lexemes OR'd as a fallback, scored at HALF so a loose match can never outrank a
  -- strict one. Built from the question's own tsvector rather than from a second tokenisation, so
  -- it cannot drift from what was actually searched.
  --
  -- MEASURED on the 508 approved FAQs, 18 Sep 2026, with the recovered Arabic question
  -- "كم تكلفة السقف الجبسي المستعار للمتر المربع في دبي": strict returns 0 rows, the fallback
  -- returns 11. And the floors still hold — the fallback's best row is "ما هو QuotesDone؟" at
  -- ts_rank 0.0169, which halves to 0.0085 and is refused by both the 0.05 corroboration floor and
  -- the 0.20 lexical-only bar. That is the intended shape and worth stating plainly: the fallback's
  -- job is to give an Arabic VECTOR hit something it can corroborate against, not to admit rows on
  -- its own strength. A nearest neighbour is always found; this does not make one citable.
  v_tq_ar     tsquery;
  v_or_ar     text;
  v_tq_ar_or  tsquery;
  -- LEXEME OVERLAP — MEASURED, TRIED, AND REJECTED AS AN ADMISSION RULE. Recorded here because a
  -- rejected relaxation is worth more to the next reader than a silent one.
  --
  -- Over 18 realistic portal questions on 9 Sep 2026, all 5 that fell through did so at
  -- lexical_rank EXACTLY 0.0000 while their best vector hit sat at 0.888–0.916. Not weak evidence
  -- — NO lexical match at all, because websearch_to_tsquery ANDs every term and no single passage
  -- contains all of "dubai & supplier & cover & abu & dhabi". So lowering p_min_rank would have
  -- recovered nothing, and the measurement is what says so rather than a guess.
  --
  -- The obvious relaxation was to corroborate on lexeme OVERLAP instead: admit a row that clears
  -- cosine 0.86 and carries at least 40% of the question's own lexemes literally. It was built,
  -- applied and measured. "does a Dubai supplier cover Abu Dhabi as well" then returned a joinery
  -- FIRE-DOOR CERTIFICATION passage — cosine 0.888, lexemes "dubai" and "suppli" present, subject
  -- entirely wrong. A confidently wrong answer to a procurement question is the exact failure the
  -- floors exist to prevent, so the relaxation was reverted within the hour. The overlap count is
  -- still computed and logged as a DIAGNOSTIC, because it is the cheapest signal for which gaps
  -- are a phrasing problem and which are a genuinely absent subject — it is simply not allowed to
  -- admit anything.
  v_lex       text[];
  v_need      int;
  v_cands     jsonb  := '[]'::jsonb;
  v_cited     text[] := '{}';
  v_answer    jsonb  := '[]'::jsonb;
  v_refusal   text;
  v_norm      text;
  v_gap       public.sales_knowledge_gap%rowtype;
  v_task      bigint;
  v_rehearsal text := public.fn_e2e_rehearsal_tag();
  v_best_sim  numeric;
  v_best_rank numeric;
  v_best_corp text;
  v_handoff   text;
begin
  if coalesce(btrim(p_text), '') = '' then
    return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    'ok', false, 'answered', false, 'refusal', 'empty_query');
  end if;

  -- THE QUESTION ARRIVED WITH ITS SCRIPT STRIPPED. See fn_text_lost_its_script for the measured
  -- case. Nothing downstream can answer a question whose letters were replaced by question marks
  -- before it reached us, and filing it as a knowledge gap manufactures a task nobody can work:
  -- org_tasks 578945 sat in the queue for nine days under a title made entirely of them. Refuse
  -- here, say so, and open nothing.
  --
  -- THE REPLY CARRIES BOTH LANGUAGES, AND THAT IS NOT BELT AND BRACES. Every surface in this
  -- estate decides the asker's language from the SCRIPT they typed in — site_assistant tests
  -- /[؀-ۿ]/ against the message, fn_support_corpus_search reads ask_lang the same way. The script
  -- is precisely what was destroyed here: a stripped message is pure ASCII, so every one of those
  -- detectors concludes "English" for the one visitor who most needs the Arabic sentence. The
  -- language is unknowable by construction on this branch, so the choice is not made. 'handoff' is
  -- what the sales_engineer edge function already reads, so putting both paragraphs there is what
  -- makes the Arabic reach a person at all; 'handoff_ar' is kept for a caller that wants the
  -- Arabic alone.
  if public.fn_text_lost_its_script(p_text) then
    return jsonb_build_object(
      'company', public.fn_company_context(),
      'ok', false, 'answered', false, 'refusal', 'text_lost_its_script',
      'handoff', public.fn_text_did_not_survive_reply('en') || E'\n\n'
                 || public.fn_text_did_not_survive_reply('ar'),
      'handoff_en', public.fn_text_did_not_survive_reply('en'),
      'handoff_ar', public.fn_text_did_not_survive_reply('ar'));
  end if;

  v_tq := websearch_to_tsquery('english', p_text);
  -- 21 SEP 2026 — THE ARABIC ARMS EXIST ONLY FOR A QUESTION WRITTEN IN ARABIC. Measured on
  -- production with the customer's English question "the quote excludes scaffolding above 4 m but
  -- my ceilings are 3.2 m, does that exclusion matter": the 'arabic' configuration has no stopword
  -- list, so 'the', 'does', 'that', 'are' became query lexemes, and ts_rank scores PARTIAL matches —
  -- FAQ 624 "Does a Dubai supplier cover Abu Dhabi as well?" ranked 0.7640 under the strict Arabic
  -- query while `@@` was FALSE for it. Five unrelated FAQs cleared the 0.20 lexical-only bar that
  -- way and were dumped on the customer as the answer. An English question now carries null Arabic
  -- arms, and (below) every rank is gated by its own `@@`, so a rank can no longer be earned by a
  -- query the row does not actually match.
  if p_text ~ '[؀-ۿ]' then
    v_tq_ar := websearch_to_tsquery('arabic', public.fn_ar_norm(p_text));
    select nullif(array_to_string(array(
             select lexeme from unnest(to_tsvector('arabic', public.fn_ar_norm(p_text)))), ' | '), '')
      into v_or_ar;
    v_tq_ar_or := case when v_or_ar is null then null else to_tsquery('arabic', v_or_ar) end;
  else
    v_tq_ar := null; v_or_ar := null; v_tq_ar_or := null;
  end if;
  select array_agg(distinct u.lexeme) into v_lex from unnest(to_tsvector('english', p_text)) u;
  v_need := least(coalesce(cardinality(v_lex), 0), greatest(2, ceil(0.4 * coalesce(cardinality(v_lex), 0))::int));

  -- Every corpus produces the same six columns so the union is a fact about provenance, not about
  -- shape. `route` records HOW a row could be admitted, and is what stops a vector-bearing row
  -- being let in on lexical evidence alone.
  create temporary table if not exists _sa_cand (
    corpus text, record_id text, title text, content text, provenance text,
    similarity numeric, lexical_rank numeric, has_vector boolean, lex_hits int default 0
  ) on commit drop;
  -- truncate, not delete: the estate has a guard that refuses an unqualified DELETE, and a
  -- WHERE-less delete on a scratch table is exactly what that guard exists to catch elsewhere.
  truncate table _sa_cand;

  -- sales_knowledge — the seat's own pack. 1,136 rows, 100% embedded.
  if p_embedding is not null then
    insert into _sa_cand
    select 'sales_knowledge', k.record_id, k.title, left(k.content, 4000),
           coalesce(k.record_type, '') || case when k.domain is null then '' else ' · ' || k.domain end
             || case when k.epistemic_status is null then '' else ' · ' || k.epistemic_status end,
           (1 - (k.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(k.search, v_tq), 0)::numeric * (case when k.search @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(k.search) u where u.lexeme = any (v_lex))
      from sales_knowledge k
     where k.embedding_gte is not null
     order by k.embedding_gte <=> p_embedding
     limit v_wide;
  end if;
  insert into _sa_cand
  select 'sales_knowledge', k.record_id, k.title, left(k.content, 4000),
         coalesce(k.record_type, ''), null::numeric, ts_rank(k.search, v_tq)::numeric, false, 0
    from sales_knowledge k
   where k.embedding_gte is null and k.search @@ v_tq
   order by ts_rank(k.search, v_tq) desc
   limit v_wide;

  -- ops_knowledge — 9,139 rows, 100% embedded, tsv + hnsw.
  if p_embedding is not null then
    insert into _sa_cand
    select 'ops_knowledge', o.record_id, o.title, left(o.content, 4000),
           coalesce(o.record_type, '') || case when o.authority_tier is null then '' else ' · authority ' || o.authority_tier end,
           (1 - (o.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(o.tsv, v_tq), 0)::numeric * (case when o.tsv @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(o.tsv) u where u.lexeme = any (v_lex))
      from ops_knowledge o
     where o.embedding_gte is not null
       and coalesce(o.supersession_state, 'current') = 'current'   -- never quote a superseded rule
     order by o.embedding_gte <=> p_embedding
     limit v_wide;
  end if;

  -- kb_chunks — 2,686,026 rows. Both routes matter here and the lexical one matters most: 93.8% of
  -- this corpus has no vector at all, so a vector-only reader sees 6% of the category and trade
  -- field body.
  if p_embedding is not null then
    insert into _sa_cand
    select 'kb_chunks', c.id::text, c.title, left(c.content, 4000),
           coalesce(c.source_kind, '') || case when c.category is null then '' else ' · ' || c.category end
             || case when c.citation is null then '' else ' · ' || c.citation end,
           (1 - (c.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(c.fts, v_tq), 0)::numeric * (case when c.fts @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(c.fts) u where u.lexeme = any (v_lex))
      from kb_chunks c
     where c.embedding_gte is not null
     order by c.embedding_gte <=> p_embedding
     limit v_wide;
  end if;
  insert into _sa_cand
  select 'kb_chunks', x.id::text, x.title, left(x.content, 4000),
         coalesce(x.source_kind, '') || case when x.category is null then '' else ' · ' || x.category end
           || case when x.citation is null then '' else ' · ' || x.citation end,
         null::numeric, ts_rank(x.fts, v_tq)::numeric, false, 0
    from (select c.id, c.title, c.content, c.source_kind, c.category, c.citation, c.fts
            from kb_chunks c
           where c.embedding_gte is null and c.fts @@ v_tq
           limit c_kb_scan) x
   order by ts_rank(x.fts, v_tq) desc
   limit v_wide;

  -- agent_knowledge — 2,556 rows. The 1,627 'cat:%' rows carry no embedding, which is exactly why
  -- section 1 of this file exists. F&B excluded by slug.
  if p_embedding is not null then
    insert into _sa_cand
    select 'agent_knowledge', a.id::text, a.topic, left(a.content, 4000),
           a.agent_key || case when a.layer is null then '' else ' · ' || a.layer end,
           (1 - (a.embedding_gte <=> p_embedding))::numeric,
           coalesce(ts_rank(a.search, v_tq), 0)::numeric * (case when a.search @@ v_tq then 1 else 0 end),
           true,
           (select count(*) from unnest(a.search) u where u.lexeme = any (v_lex))
      from agent_knowledge a
     where a.embedding_gte is not null
       and not (a.agent_key = any (c_fnb))
       and coalesce(a.validation_status, '') <> 'quarantined'
     order by a.embedding_gte <=> p_embedding
     limit v_wide;
  end if;
  insert into _sa_cand
  select 'agent_knowledge', a.id::text, a.topic, left(a.content, 4000),
         a.agent_key || case when a.layer is null then '' else ' · ' || a.layer end,
         null::numeric, ts_rank(a.search, v_tq)::numeric, false, 0
    from agent_knowledge a
   where a.embedding_gte is null and a.search @@ v_tq
     and not (a.agent_key = any (c_fnb))
     and coalesce(a.validation_status, '') <> 'quarantined'
   order by ts_rank(a.search, v_tq) desc
   limit v_wide;

  -- support_knowledge — 408 rows, tsvector only. Lexical is not a fallback here, it is the only
  -- instrument the table has.
  insert into _sa_cand
  select 'support_knowledge', s.record_id, s.title, left(s.body, 4000),
         coalesce(s.record_kind, '') || case when s.domain is null then '' else ' · ' || s.domain end,
         null::numeric, ts_rank(s.search, v_tq)::numeric, false, 0
    from support_knowledge s
   where s.search @@ v_tq
     and coalesce(s.runtime_index_eligible, true)
   order by ts_rank(s.search, v_tq) desc
   limit v_wide;

  -- category_specs / category_quote_specs — 56 and 141 rows, no index of any kind. Small enough to
  -- vectorise the tsquery on the fly, and they answer the single most common portal question there
  -- is: what does this category actually require.
  insert into _sa_cand
  select 'category_specs', cs.category, cs.label,
         left('Supplier requirements: ' || coalesce(cs.supplier_requirements::text, 'none recorded')
           || E'\nCompliance checklist: ' || coalesce(cs.compliance_checklist::text, 'none recorded')
           || E'\nQuote fields: ' || coalesce(cs.fields::text, 'none recorded'), 4000),
         'category spec · ' || cs.category, null::numeric,
         ts_rank(to_tsvector('english', coalesce(cs.category,'') || ' ' || coalesce(cs.label,'') || ' '
                 || coalesce(cs.supplier_requirements::text,'') || ' ' || coalesce(cs.compliance_checklist::text,'')), v_tq)::numeric,
         false, 0
    from category_specs cs
   where to_tsvector('english', coalesce(cs.category,'') || ' ' || coalesce(cs.label,'') || ' '
         || coalesce(cs.supplier_requirements::text,'') || ' ' || coalesce(cs.compliance_checklist::text,'')) @@ v_tq
   limit v_wide;

  insert into _sa_cand
  select 'category_quote_specs', q.id::text, q.label,
         left('Aspect: ' || coalesce(q.aspect, '—') || E'\nMandatory: ' || coalesce(q.mandatory::text, 'unknown')
           || E'\n' || coalesce(q.note, ''), 4000),
         'quote spec · ' || coalesce(q.spec_group, ''), null::numeric,
         ts_rank(to_tsvector('english', coalesce(q.spec_group,'') || ' ' || coalesce(q.aspect,'') || ' '
                 || coalesce(q.label,'') || ' ' || coalesce(q.note,'')), v_tq)::numeric,
         false, 0
    from category_quote_specs q
   where to_tsvector('english', coalesce(q.spec_group,'') || ' ' || coalesce(q.aspect,'') || ' '
         || coalesce(q.label,'') || ' ' || coalesce(q.note,'')) @@ v_tq
   limit v_wide;

  -- company_faq — 508 approved rows, 466 embedded, 22 carrying Arabic (measured 18 Sep 2026).
  -- THE CORPUS THIS ROUTINE COULD NOT SEE, AND THE ONE THE COMPANY WRITES ITS ANSWERS INTO.
  --
  -- Measured, 18 Sep 2026, against the 13 recorded rows of sales_knowledge_gap: two of them
  -- ("does a Dubai supplier cover Abu Dhabi as well" and "what documents does a supplier need for
  -- verification") are answered by an approved FAQ whose question is almost the asked sentence —
  -- lexical rank 0.9888 and 0.9640. An aborted probe of the deployed routine on the same day
  -- returned answered=false, refusal=no_candidates for the first of them while FAQ 624, titled
  -- "Does a Dubai supplier cover Abu Dhabi as well?", sat approved and published.
  --
  -- The sharper half of that measurement: both FAQs were WRITTEN IN RESPONSE to those two gaps
  -- (created 2026-09-09 21:14, after the questions were refused). So the remediation loop closes
  -- into a table this routine cannot read — a gap answered for the support seat stays open for the
  -- sales seat, and the same question asked by a signed-in customer refuses again. The task text
  -- this routine writes says DONE MEANS "the knowledge exists in a searchable corpus"; company_faq
  -- was not one of them.
  --
  -- WHY THE FAQ IS ADDED HERE RATHER THAN DELEGATED TO fn_support_corpus_search. That routine
  -- already owns FAQ retrieval for the support seat, and delegating was the first instinct. It
  -- reads v_support_corpus, which is company_faq UNION support_knowledge UNION ops_knowledge —
  -- two corpora this routine already reads on its own terms — and it ranks on a different scale
  -- (ts_rank plus a flat +1.0 bonus for the asker's language). Calling it would put two admission
  -- rules behind one answer, double-count two corpora, and leave sales_decision_log unable to say
  -- which rule admitted a row. The subject this routine was missing is not "FAQ retrieval", it is
  -- "the FAQ table", so the table is what it reads — under the one admission rule it already has,
  -- with the same status = 'approved' predicate v_support_corpus applies, so "published" means the
  -- same thing to both readers and there is still exactly one definition of it.
  --
  -- NOT COVERED HERE, said plainly: ops_knowledge holds 173 Arabic-bearing rows whose tsv column
  -- is built with the english configuration, so an Arabic question still cannot reach those
  -- lexically. Rebuilding that column is a change to a different subject and is not in this file.
  -- Both routes read the SAME haystack expression through one subquery, so each row's english and
  -- arabic tsvectors are built once per statement instead of once per clause. `ar_rank` is the
  -- strict Arabic rank, `ar_loose` the best-terms fallback at half weight; the lexical rank a row
  -- carries into admission is the best of the three, so a strict hit in either language always
  -- beats a loose one and English is scored exactly as it was before this change.
  if p_embedding is not null then
    insert into _sa_cand
    select 'company_faq', h.id::text, h.title, left(h.body, 4000), h.provenance,
           (1 - (h.embedding_gte <=> p_embedding))::numeric,
           greatest(case when h.te @@ v_tq then ts_rank(h.te, v_tq) else 0 end,
                    case when v_tq_ar is not null and h.ta @@ v_tq_ar then ts_rank(h.ta, v_tq_ar) else 0 end,
                    case when v_tq_ar_or is not null and h.ta @@ v_tq_ar_or then ts_rank(h.ta, v_tq_ar_or) * 0.5 else 0 end)::numeric,
           true,
           (select count(*) from unnest(h.te) u where u.lexeme = any (v_lex))
      from (select f.id, coalesce(f.question, '') as title, coalesce(f.answer, '') as body,
                   f.embedding_gte,
                   'FAQ' || case when f.section is null then '' else ' · ' || f.section end
                         || ' · ' || coalesce(f.language, 'en') as provenance,
                   to_tsvector('english', coalesce(f.question, '') || ' ' || coalesce(f.answer, '')) as te,
                   to_tsvector('arabic', public.fn_ar_norm(coalesce(f.question, '') || ' ' || coalesce(f.answer, ''))) as ta
              from company_faq f
             where f.embedding_gte is not null
               and f.status = 'approved'
             order by f.embedding_gte <=> p_embedding
             limit v_wide) h;
  end if;
  insert into _sa_cand
  select 'company_faq', h.id::text, h.title, left(h.body, 4000), h.provenance,
         null::numeric, h.lex_rank, false, 0
    -- The outer select reads the alias g. It read f (the inner table's alias) until 21 Sep 2026 —
    -- the dry run passed and the routine failed on its first call with 42P01 "missing FROM-clause
    -- entry for table f", measured by running it inside an aborted transaction.
    from (select g.id, coalesce(g.question, '') as title, coalesce(g.answer, '') as body,
                 'FAQ' || case when g.section is null then '' else ' · ' || g.section end
                       || ' · ' || coalesce(g.language, 'en') as provenance,
                 greatest(case when g.te @@ v_tq then ts_rank(g.te, v_tq) else 0 end,
                          case when v_tq_ar is not null and g.ta @@ v_tq_ar then ts_rank(g.ta, v_tq_ar) else 0 end,
                          case when v_tq_ar_or is not null and g.ta @@ v_tq_ar_or then ts_rank(g.ta, v_tq_ar_or) * 0.5 else 0 end)::numeric as lex_rank
            from (select f.*,
                         to_tsvector('english', coalesce(f.question, '') || ' ' || coalesce(f.answer, '')) as te,
                         to_tsvector('arabic', public.fn_ar_norm(coalesce(f.question, '') || ' ' || coalesce(f.answer, ''))) as ta
                    from company_faq f
                   where f.embedding_gte is null
                     and f.status = 'approved') g
           where (g.te @@ v_tq
               or (v_tq_ar is not null and g.ta @@ v_tq_ar)
               or (v_tq_ar_or is not null and g.ta @@ v_tq_ar_or))
           order by lex_rank desc
           limit v_wide) h;

  -- ADMISSION. A vector-bearing row must clear the cosine floor AND corroborate lexically. A row
  -- with no vector must clear the stricter lexical-only bar. Nothing else is admitted.
  with judged as (
    select c.*,
           (c.has_vector and c.similarity >= p_min_similarity and c.lexical_rank >= p_min_rank) as ok_vector,
           ((not c.has_vector) and c.lexical_rank >= c_lex_only)                                as ok_lexical
      from _sa_cand c
  ), ranked as (
    select j.*, (j.ok_vector or j.ok_lexical) as cited,
           row_number() over (
             order by (case when j.ok_vector or j.ok_lexical then 0 else 1 end),
                      (case when j.has_vector then 0 else 1 end),
                      j.similarity desc nulls last, j.lexical_rank desc) as rn
      from judged j
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'corpus', r.corpus, 'record_id', r.record_id,
      'similarity', round(r.similarity, 4), 'lexical_rank', round(r.lexical_rank, 4),
      'route', case when r.has_vector then 'vector+lexical' else 'lexical_only' end,
      'cleared_floor', coalesce(r.has_vector and r.similarity >= p_min_similarity, false),
      -- Diagnostic only, deliberately NOT an admission criterion. See the header note.
      'lex_hits', r.lex_hits, 'lex_overlap_would_admit', (v_need > 0 and r.lex_hits >= v_need),
      'corroborated', r.lexical_rank >= (case when r.has_vector then p_min_rank else c_lex_only end),
      'cited', r.cited) order by r.rn) filter (where r.rn <= 40), '[]'::jsonb),
    coalesce(array_agg(r.corpus || ':' || r.record_id order by r.rn)
             filter (where r.cited and r.rn <= v_k), '{}'),
    coalesce(jsonb_agg(jsonb_build_object(
      'corpus', r.corpus, 'record_id', r.record_id, 'title', r.title,
      'provenance', r.provenance,
      'similarity', round(r.similarity, 4), 'lexical_rank', round(r.lexical_rank, 4),
      'route', case when r.has_vector then 'vector+lexical' else 'lexical_only' end,
      'content', r.content) order by r.rn) filter (where r.cited and r.rn <= v_k), '[]'::jsonb)
    into v_cands, v_cited, v_answer
    from ranked r;

  select max(similarity), max(lexical_rank) into v_best_sim, v_best_rank from _sa_cand;
  select corpus into v_best_corp from _sa_cand
   order by similarity desc nulls last, lexical_rank desc limit 1;

  if cardinality(v_cited) = 0 then
    v_refusal := case
      when (select count(*) from _sa_cand) = 0 then 'no_candidates'
      when coalesce(v_best_sim, 0) < p_min_similarity and coalesce(v_best_rank, 0) < c_lex_only
        then 'below_similarity_floor_and_lexical_bar'
      when coalesce(v_best_sim, 0) < p_min_similarity then 'below_similarity_floor'
      else 'not_corroborated_lexically' end;

    -- ── THE FALLBACK IS AN ACTION, NOT A SENTENCE ────────────────────────────────────────────
    -- The founder's objection was never to the honesty of "I do not have that". It was to nothing
    -- happening afterwards. Something happens now: the question is kept, counted, and owned.
    v_norm := left(lower(regexp_replace(btrim(p_text), '\s+', ' ', 'g')), 400);

    select * into v_gap from sales_knowledge_gap where question_norm = v_norm;

    -- A REHEARSAL FILES NOTHING (27 Oct 2026, customer_support). One bank session (22 scenarios, about 270
    -- turns) opened 97 gaps and 97 org_tasks that nobody confirmed, and would have done it again daily. A
    -- question asked by a harness run is not demand: no gap, no task, and an existing gap's count and its
    -- task's priority are not raised by it. The reply is the same, so the run measures what a customer sees.
    if v_rehearsal is not null then
      v_task := null;
    elsif not found then
      insert into org_tasks (title, detail, status, tier, action_class, assigned_agent,
                             priority, requires_evidence, needs_founder)
      values (
        left('Answer an unanswered portal question: ' || btrim(p_text), 160),
        'A customer or supplier asked this in the portal and the Sales Engineer could not source an '
          || 'answer from any corpus it searches (sales_knowledge, ops_knowledge, kb_chunks, '
          || 'agent_knowledge, support_knowledge, company_faq, category_specs, category_quote_specs).' || E'\n\n'
          || 'QUESTION: ' || btrim(p_text) || E'\n'
          || 'REFUSAL: ' || v_refusal || E'\n'
          || 'CLOSEST THE ESTATE GOT: corpus ' || coalesce(v_best_corp, 'none')
          || ', cosine ' || coalesce(round(v_best_sim, 4)::text, 'n/a')
          || ', lexical rank ' || coalesce(round(v_best_rank, 4)::text, 'n/a')
          || ' (floors: cosine ' || p_min_similarity || ', lexical corroboration ' || p_min_rank
          || ', lexical-only ' || c_lex_only || ').' || E'\n\n'
          || 'DONE MEANS: the knowledge exists in a searchable corpus and this question returns it. '
          || 'Then set sales_knowledge_gap.status to knowledge_added.',
        'assigned', 'advisory', 'knowledge_gap', 'sales_engineer', 3, true, false)
      returning id into v_task;

      insert into sales_knowledge_gap
        (question_norm, question, refusal, best_similarity, best_lexical_rank, nearest_corpus, task_id)
      values (v_norm, left(btrim(p_text), 2000), v_refusal,
              round(v_best_sim, 4), round(v_best_rank, 4), v_best_corp, v_task);
    else
      v_task := v_gap.task_id;
      update sales_knowledge_gap
         set asks = asks + 1, last_asked_at = now(), refusal = v_refusal,
             best_similarity = greatest(coalesce(best_similarity, 0), coalesce(round(v_best_sim, 4), 0)),
             best_lexical_rank = greatest(coalesce(best_lexical_rank, 0), coalesce(round(v_best_rank, 4), 0))
       where id = v_gap.id;
      -- Asked repeatedly is the definition of urgent. The task's priority follows the demand.
      update org_tasks set priority = least(9, greatest(priority, 3 + v_gap.asks)), updated_at = now()
       where id = v_task and status not in ('done', 'cancelled');
    end if;

    v_handoff :=
      'I have not got a sourced answer to that yet, and I will not guess at a procurement question. '
      || 'I have recorded it' || case when v_rehearsal is null then ' and opened task #' || coalesce(v_task::text, '?') else '' end
      || ', owned by the Sales Engineer, with your question kept word for word. '
      || 'It is being looked into and you will get an answer on it.';
  end if;

  insert into sales_decision_log
    (actor, action, query, min_similarity, min_rank, k, candidates, cited, answered, refusal)
  values
    (coalesce(p_actor, 'sales_engineer'), 'assist', left(p_text, 2000), p_min_similarity,
     p_min_rank, v_k, v_cands, v_cited, cardinality(v_cited) > 0, v_refusal);

  return jsonb_build_object(
    -- THE COMPANY BLOCK. Pinned, never retrieved and never rankable: it is here on every answer,
    -- including the refusals, because a seat with no retrieval hit is exactly the seat most likely
    -- to improvise a fee or a policy. Founder ruling, 9 Sep 2026.
    'company', public.fn_company_context(),
    
    'ok', true,
    'answered', cardinality(v_cited) > 0,
    'records', v_answer,
    'cited', v_cited,
    'candidates', v_cands,
    'corpora', jsonb_build_array('sales_knowledge','ops_knowledge','kb_chunks','agent_knowledge',
                                 'support_knowledge','company_faq','category_specs','category_quote_specs'),
    'floor', jsonb_build_object(
      'min_similarity', p_min_similarity, 'min_rank', p_min_rank, 'lexical_only', c_lex_only,
      'lexemes_in_question', coalesce(cardinality(v_lex), 0), 'lexeme_overlap_needed', v_need, 'k', v_k,
      'rule', 'a row with an embedding must clear the cosine floor AND match the all-terms lexical query at ts_rank >= min_rank. A row with no embedding cannot be put to the vector floor at all and must clear the stricter lexical-only bar instead. lexeme_overlap_needed is reported as a diagnostic only: admitting on partial overlap was measured and returned a topically wrong passage, so it does not admit. A nearest neighbour is always found; a lexical match is not.'),
    'refusal', v_refusal,
    'gap_recorded', cardinality(v_cited) = 0 and v_rehearsal is null,
    'rehearsal', v_rehearsal,
    'task_id', v_task,
    'handoff', v_handoff);
end
$function$;

-- CREATE OR REPLACE keeps fn_sales_assist's ACL (postgres, service_role).

create or replace function public.fn_support_knowledge_gap(p_question text, p_refusal text, p_surface text DEFAULT 'website_widget'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_norm text;
  v_gap  public.sales_knowledge_gap%rowtype;
  v_task bigint;
  v_asks int;
  v_rehearsal text := public.fn_e2e_rehearsal_tag();
begin
  if coalesce(btrim(p_question), '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'empty_question');
  end if;

  -- THE QUESTION ARRIVED WITH ITS SCRIPT STRIPPED, so there is nothing here to answer and
  -- nothing to file. org_tasks 578945 is what happens without this branch: a task that sat in
  -- the work queue for nine days titled in question marks, asked four times, with no reading of
  -- it possible by anyone.
  --
  -- BOTH KEYS CARRY BOTH LANGUAGES. site_assistant picks between reply_en and reply_ar with
  -- `/[؀-ۿ]/.test(message) || uiLang === 'ar'` — it reads the script of the message, and on this
  -- branch the script is exactly what was destroyed, so a stripped Arabic message is pure ASCII
  -- and that test says "English" for the one visitor who needs the Arabic. The language cannot be
  -- known here, so it is not guessed: whichever key the caller reads, the person gets both
  -- paragraphs. This is the fix for the defect the comment above would otherwise only describe.
  if public.fn_text_lost_its_script(p_question) then
    return jsonb_build_object(
      'ok', false, 'reason', 'text_lost_its_script',
      'reply_en', public.fn_text_did_not_survive_reply('en') || E'\n\n'
                  || public.fn_text_did_not_survive_reply('ar'),
      'reply_ar', public.fn_text_did_not_survive_reply('ar') || E'\n\n'
                  || public.fn_text_did_not_survive_reply('en'));
  end if;

  v_norm := left(lower(regexp_replace(btrim(p_question), '\s+', ' ', 'g')), 400);
  select * into v_gap from public.sales_knowledge_gap where question_norm = v_norm;

  -- A REHEARSAL FILES NOTHING (27 Oct 2026): the same rule as fn_sales_assist. Same reply, no gap, no task.
  if v_rehearsal is not null then
    v_task := null;
    v_asks := 0;
  elsif not found then
    insert into public.org_tasks (title, detail, status, tier, action_class, assigned_agent,
                                  priority, requires_evidence, needs_founder)
    values (
      left('Answer an unanswered support question: ' || btrim(p_question), 160),
      'Someone who was NOT signed in asked this on the ' || coalesce(nullif(btrim(p_surface), ''), 'website_widget')
        || ' and Customer Support could not source an answer from company knowledge.' || E'\n\n'
        || 'QUESTION: ' || btrim(p_question) || E'\n'
        || 'REFUSAL: ' || coalesce(nullif(btrim(p_refusal), ''), 'no_grounded_answer') || E'\n\n'
        || 'THERE IS NO ESCALATION TO A HUMAN -- founder ruling, 9 Sep 2026. This task IS what '
        || 'happens instead, and it is the only thing that happens.' || E'\n\n'
        || 'DONE MEANS: the answer exists in a corpus fn_support_corpus_search reads (company_faq, '
        || 'support_knowledge, ops_knowledge) and this question returns it. Then set '
        || 'sales_knowledge_gap.status to knowledge_added.',
      'assigned', 'advisory', 'knowledge_gap', 'customer_support', 3, true, false)
    returning id into v_task;

    insert into public.sales_knowledge_gap (question_norm, question, refusal, nearest_corpus, task_id)
    values (v_norm, left(btrim(p_question), 2000),
            coalesce(nullif(btrim(p_refusal), ''), 'no_grounded_answer'),
            'support_corpus', v_task);
    v_asks := 1;
  else
    v_task := v_gap.task_id;
    v_asks := v_gap.asks + 1;
    update public.sales_knowledge_gap
       set asks = asks + 1, last_asked_at = now(),
           refusal = coalesce(nullif(btrim(p_refusal), ''), refusal)
     where id = v_gap.id;
    -- Asked repeatedly is the definition of urgent, exactly as on the sales side.
    update public.org_tasks
       set priority = least(9, greatest(priority, 3 + v_gap.asks)), updated_at = now()
     where id = v_task and status not in ('done', 'cancelled');
  end if;

  return jsonb_build_object(
    'ok', true, 'task_id', v_task, 'asks', v_asks, 'rehearsal', v_rehearsal,
    'reply_en', 'I do not have a sourced answer to that yet, and I will not guess at it. I have '
      || 'recorded your question exactly as you asked it so it gets answered properly. If you need '
      || 'it now, call or WhatsApp +971 50 931 9355 (Mon-Fri, 9am-6pm GST) or email '
      || 'management@quotesdone.com.',
    'reply_ar', 'لا تتوفر لديّ إجابة موثّقة عن ذلك حتى الآن، ولا أودّ التخمين. سجّلتُ سؤالكم كما كتبتموه '
      || 'تمامًا ليُجاب عنه إجابة دقيقة. وإن احتجتم إلى الإجابة الآن، يمكنكم الاتصال أو المراسلة عبر '
      || 'واتساب:' || E'\n' || '+971 50 931 9355' || E'\n' || 'أو البريد الإلكتروني:' || E'\n'
      || 'management@quotesdone.com');
end
$function$;

-- CREATE OR REPLACE keeps fn_support_knowledge_gap's ACL (postgres, service_role).
