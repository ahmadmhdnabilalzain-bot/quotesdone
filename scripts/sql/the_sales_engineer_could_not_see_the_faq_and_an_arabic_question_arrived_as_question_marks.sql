-- =================================================================================================
-- THE SALES ENGINEER COULD NOT SEE THE FAQ, AND AN ARABIC QUESTION ARRIVED AS QUESTION MARKS
--
-- SEAT: sales_engineer (the answering surfaces), with customer_support where the support corpus is
-- concerned. Two customer-facing defects, both measured against production on 18 Sep 2026.
--
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- DEFECT 1 — fn_sales_assist searched seven corpora and company_faq was not one of them.
--
-- MEASURED. Of the 13 rows in sales_knowledge_gap, two are answered by an approved, published FAQ
-- whose question is almost the sentence that was asked:
--
--   gap 6  "does a Dubai supplier cover Abu Dhabi as well"          FAQ 624, lexical rank 0.9888
--   gap 9  "what documents does a supplier need for verification"   FAQ 623, lexical rank 0.9640
--
-- (Method and boundary: english + arabic tsquery over question || answer of the 508 approved
-- company_faq rows, run against all 13 gap questions. The vector route was not simulated because
-- sales_knowledge_gap stores no embedding of the question, so this count is a floor, not a
-- ceiling. One further gap, id 1, is the string "-s" and matches at rank 0.0000.)
--
-- An aborted-transaction probe of the DEPLOYED routine on the same day, with no embedding:
--   gap 6 -> answered=false, refusal=no_candidates    <- still refused today
--   gap 9 -> answered=true                            <- reached through support_knowledge
--
-- THE SESSION BRIEF'S CAUSE WAS ONE STEP OFF, and the truth is worse. The brief read this as "the
-- answer was already published when the customer asked". It was not: FAQ 623 and 624 were created
-- 2026-09-09 21:14, about half an hour AFTER those two questions were refused. They were written
-- in response to the gaps — the remediation loop working exactly as designed. The defect is that
-- the loop closes into a table this routine cannot read. A gap answered for the support seat stays
-- open for the sales seat, and a signed-in customer asking the same question is refused again while
-- the company's own published answer sits one table away. fn_sales_assist's own task text says
-- DONE MEANS "the knowledge exists in a searchable corpus and this question returns it"; the
-- corpus the company actually writes its answers into was not one it searched.
--
-- THE FIX, and why this one: company_faq is added as an eighth corpus to fn_sales_assist, read
-- directly from the table under the routine's existing admission rule, with the same
-- status = 'approved' predicate v_support_corpus already applies. The alternative — delegating to
-- fn_support_corpus_search, which already owns FAQ retrieval for the support seat — was rejected
-- with reasons, recorded in full beside the new corpus block below.
--
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- DEFECT 3 (added 21 Sep 2026, seat sales_engineer) — the FAQ arm answered questions it did not
-- match. MEASURED on production: the customer's English portal question about a scaffolding
-- exclusion cited FAQs 624, 167, 30, 623 and 26 at lexical_rank up to 0.7640 while `@@` was FALSE
-- for every one of them — ts_rank scores partial term hits, and the 'arabic' configuration (no
-- stopwords) made 'the', 'does', 'that', 'are' into query terms that every English FAQ contains.
-- CHANGES: the Arabic arms are built only for a question carrying Arabic script, and every FAQ rank
-- (english, arabic strict, arabic loose) is zero unless the row matches that query. NOT CHANGED:
-- the floors, the other seven corpora, the gap/task fallback. Probe (c3) asserts the case.
--
-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- DEFECT 2 — an Arabic question was destroyed before it reached the database.
--
-- org_tasks 578945 / sales_knowledge_gap 14 held a question made entirely of question marks. The
-- write path, traced end to end:
--
--   website widget (path '/')  ->  supabase/functions/site_assistant/index.ts
--   -> admin.rpc('fn_support_knowledge_gap', { p_question: message, ... })
--   -> org_tasks + sales_knowledge_gap
--
-- and NOTHING ON THAT PATH TOUCHED THE TEXT. The proof is in assistant_logs, which records the
-- message as it arrived, together with the user agent:
--
--   id 141-144, 2026-09-09 20:42-20:52, user_agent 'curl/8.21.0'
--       message '?? ????? ????? ?????? ???????? ????? ?????? ?? ???'      <- destroyed
--   id 145-149, 2026-09-09 20:53-20:55, user_agent 'node'
--       message 'كم تكلفة السقف الجبسي المستعار للمتر المربع في دبي'       <- intact
--
-- Same endpoint, same function, same table, thirteen minutes apart. The only variable is the
-- client. The loss is a CLIENT-SIDE ENCODE: a curl.exe invocation from a Windows shell whose JSON
-- body was encoded in the console/ANSI codepage rather than UTF-8, so every Arabic codepoint had
-- already become 0x3F before the request left the machine. There is no connection charset, no
-- convert_to/encode call, no gateway transliteration and no log-and-copy step involved — the edge
-- function, PostgREST and Postgres each stored exactly the bytes they were handed.
--
-- SAID PLAINLY, because it changes what the row is: those four requests came from a probe harness,
-- not from a member of the public. The company is pre-launch and every row in that window is a
-- session probe (the same run asked "how much does it cost to charter a helicopter to the moon").
-- Nobody was failed. What was real is that the estate accepted an unreadable question, opened a
-- task on it, and left that task in the work queue for nine days with a title nobody could act on.
--
-- THE FIX. No code of ours can un-corrupt text that arrived corrupt, so the fix is at the trust
-- boundary: fn_text_lost_its_script names the fingerprint once, and both routines that keep a
-- visitor's words — fn_support_knowledge_gap and fn_sales_assist — refuse to file a question that
-- carries it, and say so to the asker in English and in full Arabic instead of opening a task
-- nobody can work. scripts/checks/arabic_bearing_columns_keep_their_script.mjs is the backstop: it
-- fails if any answer-bearing column holds text with its script stripped, so a writer added later
-- and wired past these two routines is caught rather than assumed away.
--
-- RECOVERY OF THE ONE ROW. The original text is recovered — not guessed. The corrupted string is
-- nine whitespace-separated tokens of lengths [2,5,5,6,8,5,6,2,3]. Exactly one Arabic message in
-- assistant_logs before 2026-09-10 has that fingerprint, and it was sent by the same probe run
-- eleven minutes later over a UTF-8-clean client (ids 145/146):
--
--     كم تكلفة السقف الجبسي المستعار للمتر المربع في دبي
--     "how much does a gypsum false ceiling cost per square metre in Dubai"
--
-- The Arabic is the ASKER'S wording and is restored verbatim, not improved. A UAE tradesperson
-- would more often say الجبس بورد; that is not what was typed, the length fingerprint only holds
-- for this exact string, and a recovered customer sentence is evidence, not copy.
--
-- The other four Arabic messages of that day score [2,2,4,5,2,7], [2,5,5,4], [2,6,7,7] and
-- [2,2,3,6,5,6] — none of them a match. The same probe run had asked the English form of that
-- sentence three times through the same curl client minutes earlier (assistant_logs 134/135/137).
-- Section 5 restores the gap row and its task from that, and records in the task detail where the
-- text came from so the next reader is not asked to trust it.
--
-- assistant_logs is deliberately NOT rewritten. It is the arrival record, and a corrupted arrival
-- is a true record of a corrupted arrival; overwriting it would delete the only evidence that
-- names the failing client. The check in this change therefore covers the answer-bearing columns
-- and states that exclusion out loud rather than omitting it quietly.
-- =================================================================================================

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 1. ONE DEFINITION OF "THIS TEXT LOST ITS SCRIPT".
--
-- The fingerprint of a codepage-stripped string. One precondition and three arms, and a question
-- in which ANY non-ASCII survived is never flagged at all, because partial survival means the
-- transport was not the ANSI codepage.
--
--   PRECONDITION  not a single non-ASCII character left anywhere in the text.
--   ARM A         the WHOLE field was the lost text: two or more separate runs of consecutive
--                 question marks, and question marks at 30% or more of the non-whitespace
--                 characters. The measured row scores 9 runs and 100%.
--   ARM B         the lost text is EMBEDDED in a longer readable field: three or more runs of
--                 four-or-more consecutive question marks. Arm A alone missed this and it was the
--                 check that said so — org_tasks 578945's title tripped arm A, its detail did not,
--                 because the destroyed sentence sits inside two paragraphs of English and scores
--                 only 20%. That detail is every bit as unreadable as the title. Arm B scores it
--                 at 6 runs. English prose does not contain four consecutive question marks once,
--                 let alone three times.
--   ARM C         one unbroken run of eight or more. Arms A and B both COUNT runs, and a single
--                 word destroyed with no whitespace in it is one run however long — so a
--                 review of this file found that arms A and B together could not detect a
--                 corrupted string that happened to contain no spaces at all. Nobody types eight
--                 consecutive question marks.
--
-- The corner this cuts, named rather than hidden: a message written as "why??? how???" would trip
-- arm A. The consequence of tripping is that the asker is told their text did not survive and is
-- asked to send it again — a mild, recoverable outcome — where the consequence of NOT tripping is
-- a destroyed question filed as an unanswerable task. The asymmetry is why the bar sits here.
--
-- Also not covered, and said rather than implied: a field mixing intact Arabic with destroyed
-- Arabic fails the precondition and is not flagged. Nothing observed produces that shape — the
-- codepage conversion takes every non-ASCII character or none.
-- ponytail: 30%, two runs and three long runs are thresholds, not a theory. If a real message is
-- ever refused by this, raise a threshold rather than removing the guard.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_text_lost_its_script(p_text text)
returns boolean
language sql
immutable
parallel safe
set search_path to 'public', 'pg_temp'
as $function$
  select coalesce(
       p_text !~ '[^\x00-\x7F]'
   and (
         (    (select count(*) from regexp_matches(p_text, '[?][?]+', 'g')) >= 2
          and length(regexp_replace(p_text, '[^?]', '', 'g'))::numeric
                >= 0.30 * greatest(length(regexp_replace(p_text, '\s', '', 'g')), 1))
      or (select count(*) from regexp_matches(p_text, '[?]{4,}', 'g')) >= 3
      or p_text ~ '[?]{8,}'
       ),
  false);
$function$;

revoke execute on function public.fn_text_lost_its_script(text) from public, anon, authenticated;

comment on function public.fn_text_lost_its_script(text) is
  'True when a string carries the fingerprint of a codepage-stripped encode: nothing non-ASCII surviving, and either the whole field made of question-mark runs (two or more runs, at 30% or more of the non-whitespace characters) or a destroyed sentence embedded in a readable one (three or more runs of four or more). Written 18 Sep 2026 after org_tasks 578945 held an Arabic question whose every letter had become a question mark in a curl.exe client before the request left the machine. Used by fn_support_knowledge_gap and fn_sales_assist to refuse an unreadable question instead of filing it as a task.';

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 1b. ONE SENTENCE FOR "YOUR TEXT DID NOT SURVIVE", IN BOTH LANGUAGES.
--
-- Two routines refuse this and both have to say the same thing. Written once rather than twice,
-- because a sentence copied into two functions is a sentence that will be corrected in one.
--
-- Four things about the Arabic, each of them a review finding rather than a preference:
--
--   * تحوّلت حروفها إلى, not استُبدلت حروفها بـ. In prescriptive MSA, استبدل س بـ ص means taking س
--     IN EXCHANGE FOR ص — the reverse of what happened. Modern usage is loose enough that nobody
--     would misread it, and that is exactly why it is not worth leaving.
--   * يرجى إرسال رسالتك, not يرجى إرساله. The pronoun would resolve to النص rather than رسالتك and
--     reads one beat past the reader.
--   * The opening hours are in the Arabic. The English twin carries them; an Arabic reply that
--     gives the number without the hours is less than its English half, not a translation of it.
--   * A LEFT-TO-RIGHT MARK before the phone number. The + is a bidi neutral with no strong LTR
--     character before it, so inside an RTL paragraph it inherits the paragraph direction and
--     renders on the WRONG SIDE: 971 50 931 9355+. One character fixes it.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_text_did_not_survive_reply(p_lang text)
returns text
language sql
immutable
parallel safe
set search_path to 'public', 'pg_temp'
as $function$
  select case when lower(coalesce(p_lang, 'en')) = 'ar' then
      'وصلتني رسالتك وقد تحوّلت حروفها إلى علامات استفهام، ولا أستطيع قراءة ما سألت عنه. '
      || 'لا يوجد خطأ في سؤالك — النص لم يصل سليمًا عبر الاتصال. يرجى إرسال رسالتك مرة أخرى. '
      || 'وإذا تكرر ذلك، يمكنك الاتصال أو المراسلة عبر واتساب:' || E'\n'
      || E'‎' || '+971 50 931 9355' || E'\n'
      || '(من الأحد إلى الخميس، من 9 صباحًا حتى 6 مساءً بتوقيت الإمارات)' || E'\n'
      || 'أو البريد الإلكتروني:' || E'\n' || 'management@quotesdone.com'
    else
      'Your message reached me with its characters replaced by question marks, so I cannot read '
      || 'what you asked. Nothing is wrong with your question — it did not survive the connection. '
      || 'Please send it again. If it keeps happening, call or WhatsApp +971 50 931 9355 '
      || '(Sun-Thu, 9am-6pm GST) or email management@quotesdone.com.'
  end;
$function$;

revoke execute on function public.fn_text_did_not_survive_reply(text) from public, anon, authenticated;

comment on function public.fn_text_did_not_survive_reply(text) is
  'The one sentence the estate says when a message arrives with its script stripped, in English and in full Arabic. Used by fn_support_knowledge_gap and fn_sales_assist so the two surfaces cannot drift apart. Both are returned together on that branch because every language detector in the estate reads the script of the message, and the script is what was destroyed.';

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 2. fn_sales_assist GAINS company_faq, AND REFUSES A QUESTION THAT LOST ITS SCRIPT.
--
-- The body below is the routine exactly as deployed, plus: the company_faq corpus (with its own
-- Arabic lexical arm), the v_tq_ar tsquery it needs, the script-stripped refusal, and 'company_faq'
-- added to the corpus list the routine reports and to the text of the task it opens.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_sales_assist(p_text text, p_embedding vector, p_min_similarity numeric DEFAULT 0.86, p_min_rank numeric DEFAULT 0.05, p_k integer DEFAULT 5, p_actor text DEFAULT 'sales_engineer'::text)
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

    if not found then
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
      || 'I have recorded it and opened task #' || coalesce(v_task::text, '?')
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
    'gap_recorded', case when cardinality(v_cited) = 0 then true else false end,
    'task_id', v_task,
    'handoff', v_handoff);
end
$function$;

comment on function public.fn_sales_assist(text, vector, numeric, numeric, integer, text) is
  'The Sales Engineer''s retrieval. Eight corpora as of 18 Sep 2026: sales_knowledge, ops_knowledge, kb_chunks, agent_knowledge, support_knowledge, company_faq, category_specs, category_quote_specs. company_faq was added because the company writes its answers into it and this routine could not read it - two recorded knowledge gaps were answered by an approved FAQ titled almost word for word as the question while the routine returned no_candidates. A question whose script did not survive transport is refused outright rather than filed as a task.';

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 3. fn_support_knowledge_gap REFUSES A QUESTION THAT LOST ITS SCRIPT.
--
-- This is the routine that actually wrote org_tasks 578945, called by site_assistant when the
-- widget cannot ground an answer. The body below is the routine exactly as deployed, plus the one
-- branch. Same guard, same sentence, both languages — one fingerprint, two callers, so a fix on
-- one surface is not a fix the other surface lacks.
--
-- CREATE OR REPLACE preserves the ACL, so the revoke that accompanied the original definition is
-- deliberately not repeated here.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_support_knowledge_gap(p_question text, p_refusal text, p_surface text default 'website_widget')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_norm text;
  v_gap  public.sales_knowledge_gap%rowtype;
  v_task bigint;
  v_asks int;
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

  if not found then
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
    'ok', true, 'task_id', v_task, 'asks', v_asks,
    'reply_en', 'I do not have a sourced answer to that yet, and I will not guess at it. I have '
      || 'recorded your question exactly as you asked it so it gets answered properly. If you need '
      || 'it now, call or WhatsApp +971 50 931 9355 (Sun-Thu, 9am-6pm GST) or email '
      || 'management@quotesdone.com.',
    'reply_ar', 'ليس لدي إجابة موثقة على ذلك حتى الآن، ولن أخمّن. لقد سجّلت سؤالك كما كتبته '
      || 'تماماً ليتم الرد عليه بشكل صحيح. وإذا كنت بحاجة إليه الآن، يمكنك الاتصال أو المراسلة عبر '
      || 'واتساب:' || E'\n' || '+971 50 931 9355' || E'\n' || 'أو البريد الإلكتروني:' || E'\n'
      || 'management@quotesdone.com');
end
$function$;

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 4. RECOVER THE ONE ROW THAT WAS DESTROYED.
--
-- sales_knowledge_gap 14 / org_tasks 578945. The text is taken from assistant_logs 145, the same
-- probe run's UTF-8-clean re-send of the same sentence, identified by an exact nine-token
-- character-length fingerprint [2,5,5,6,8,5,6,2,3] that no other Arabic message of that day
-- matches. The reasoning is in this file's header; the provenance is written into the task itself
-- so it does not depend on anyone finding this file.
--
-- Every statement here is addressed by the exact corrupted value, so it is idempotent: run twice
-- and the second run matches nothing. Nothing is written if the text is not still corrupt, and
-- nothing is written if a gap already holds the recovered normalised question (question_norm is
-- the idempotency key of that table and a collision would be a second bug, not a recovery).
-- ─────────────────────────────────────────────────────────────────────────────────────────────
update public.sales_knowledge_gap g
   set question      = 'كم تكلفة السقف الجبسي المستعار للمتر المربع في دبي',
       question_norm = left(lower(regexp_replace(btrim('كم تكلفة السقف الجبسي المستعار للمتر المربع في دبي'), '\s+', ' ', 'g')), 400)
 where g.id = 14
   and public.fn_text_lost_its_script(g.question)
   and not exists (
         select 1 from public.sales_knowledge_gap o
          where o.id <> g.id
            and o.question_norm = left(lower(regexp_replace(btrim('كم تكلفة السقف الجبسي المستعار للمتر المربع في دبي'), '\s+', ' ', 'g')), 400));

update public.org_tasks t
   set title  = left('Answer an unanswered support question: كم تكلفة السقف الجبسي المستعار للمتر المربع في دبي', 160),
       detail = replace(t.detail, '?? ????? ????? ?????? ???????? ????? ?????? ?? ???',
                        'كم تكلفة السقف الجبسي المستعار للمتر المربع في دبي')
         || E'\n\nRECOVERED 18 Sep 2026. This question reached the database with every Arabic letter '
         || 'replaced by a question mark, because the client that sent it encoded the request body '
         || 'in a Windows ANSI codepage rather than UTF-8. The text above is recovered from '
         || 'assistant_logs id 145 — the same run''s UTF-8-clean re-send of the same sentence, '
         || 'matched by an exact nine-token character-length fingerprint [2,5,5,6,8,5,6,2,3] that '
         || 'no other Arabic message of that day carries. It is not a reconstruction of the meaning; '
         || 'it is the byte-for-byte original. In English: "what should a gypsum false ceiling cost '
         || 'per square metre in Dubai".'
 where t.id = 578945
   and public.fn_text_lost_its_script(t.title);

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 5. PROBES.
--
-- This file carries DDL, so a probe that raise-exceptions would roll the DDL back with it. These
-- clean up after themselves and end by RETURNING A ROW: raise notice is discarded by the
-- management API, so a notice-only verdict is a probe that cannot report.
--
-- The probes are incapable of reaching a person. fn_text_lost_its_script and
-- fn_support_knowledge_gap are called with literals and write nothing that leaves the database.
-- The fn_sales_assist call is the one that writes, and it is bounded by IDENTITY rather than by a
-- text marker: the maximum sales_decision_log id is taken first and only rows created ABOVE it are
-- deleted, so the probe can only ever remove its own row and never another session's. A ZZ DEMO
-- prefix is deliberately NOT used on the question — websearch_to_tsquery ANDs every term, so
-- prefixing the sentence would make it match nothing and the probe would pass by matching nothing,
-- which is the shape of a gate that cannot fire. org_tasks and sales_knowledge_gap are counted
-- before and after and asserted unchanged; the call is expected to be ANSWERED, so a task opening
-- at all is itself a failure.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
do $probe$
declare
  v_fail text[] := '{}';
  v_hit  jsonb;
  v_max_log     bigint;
  v_before_task bigint;
  v_before_gap  bigint;
  v_max_task    bigint;
  v_max_gap     bigint;
  v_emb         vector;
  v_emb_q       text;
  v_q    text := 'does a Dubai supplier cover Abu Dhabi as well';
begin
  -- (a) the fingerprint fires on the measured string and on nothing innocent.
  if not public.fn_text_lost_its_script('?? ????? ????? ?????? ???????? ????? ?????? ?? ???') then
    v_fail := v_fail || 'the destroyed question was not detected';
  end if;
  if public.fn_text_lost_its_script('كم تكلفة السقف الجبسي المستعار للمتر المربع في دبي') then
    v_fail := v_fail || 'intact Arabic was wrongly flagged';
  end if;
  if public.fn_text_lost_its_script('what documents does a supplier need for verification?') then
    v_fail := v_fail || 'an ordinary English question was wrongly flagged';
  end if;
  -- arm B: the destroyed sentence buried in a readable field, which is the shape of the detail on
  -- org_tasks 578945 and the shape arm A alone did not see.
  if not public.fn_text_lost_its_script(
       'Someone who was NOT signed in asked this on the website_widget and Customer Support could '
       || 'not source an answer from company knowledge. QUESTION: '
       || '?? ????? ????? ?????? ???????? ????? ?????? ?? ??? REFUSAL: circuit_open') then
    v_fail := v_fail || 'a destroyed sentence embedded in a readable field was not detected';
  end if;
  if public.fn_text_lost_its_script('') or public.fn_text_lost_its_script(null) is distinct from false then
    v_fail := v_fail || 'empty or null text was wrongly flagged';
  end if;

  -- (b) an unreadable question opens NO task. Counted, not assumed.
  select count(*) into v_before_task from public.org_tasks;
  select count(*) into v_before_gap  from public.sales_knowledge_gap;
  v_hit := public.fn_support_knowledge_gap('?? ????? ????? ?????? ???????? ????? ?????? ?? ???',
                                           'probe', 'website_widget');
  if coalesce(v_hit->>'reason', '') <> 'text_lost_its_script' then
    v_fail := v_fail || ('support gap did not refuse: ' || coalesce(v_hit::text, 'null'));
  end if;
  -- an empty-string assertion would pass on English sitting in the Arabic slot. Assert SCRIPT.
  if coalesce(v_hit->>'reply_ar', '') !~ '[؀-ۿ]' or coalesce(v_hit->>'reply_en', '') !~ '[؀-ۿ]' then
    v_fail := v_fail || 'the refusal did not carry Arabic on both keys';
  end if;
  if coalesce(v_hit->>'reply_ar', '') !~ '[A-Za-z]' or coalesce(v_hit->>'reply_en', '') !~ '[A-Za-z]' then
    v_fail := v_fail || 'the refusal did not carry English on both keys';
  end if;
  if (select count(*) from public.org_tasks) <> v_before_task
     or (select count(*) from public.sales_knowledge_gap) <> v_before_gap then
    v_fail := v_fail || 'the refusal still wrote a task or a gap';
  end if;

  -- (b2) the SAME refusal on the sales side. Structurally asserting that a routine mentions the
  -- guard would be satisfied by a comment; this calls it and reads the verdict.
  v_hit := public.fn_sales_assist('?? ????? ????? ?????? ???????? ????? ?????? ?? ???', null::vector);
  if coalesce(v_hit->>'refusal', '') <> 'text_lost_its_script' then
    v_fail := v_fail || ('fn_sales_assist did not refuse an unreadable question: '
                         || coalesce(v_hit->>'refusal', 'no refusal'));
  end if;
  if coalesce(v_hit->>'handoff', '') !~ '[؀-ۿ]' or coalesce(v_hit->>'handoff', '') !~ '[A-Za-z]' then
    v_fail := v_fail || 'fn_sales_assist''s refusal did not reach the asker in both languages';
  end if;
  if (select count(*) from public.org_tasks) <> v_before_task
     or (select count(*) from public.sales_knowledge_gap) <> v_before_gap then
    v_fail := v_fail || 'the sales refusal still wrote a task or a gap';
  end if;

  -- (c) the FAQ is now reachable. The question the deployed routine refused with no_candidates
  --     must come back cited from company_faq. Run on a ZZ DEMO-prefixed string so nothing in the
  --     must come back cited from company_faq.
  select coalesce(max(id), 0) into v_max_log from public.sales_decision_log;
  select count(*) into v_before_task from public.org_tasks;
  select count(*) into v_before_gap  from public.sales_knowledge_gap;

  v_hit := public.fn_sales_assist(v_q, null::vector);

  if not exists (select 1 from jsonb_array_elements(coalesce(v_hit->'records', '[]'::jsonb)) r
                  where r->>'corpus' = 'company_faq') then
    v_fail := v_fail || ('company_faq did not answer the question it publishes: '
                         || coalesce(v_hit->>'refusal', 'no refusal recorded')
                         || ' / cited ' || coalesce((v_hit->'cited')::text, 'null'));
  end if;

  -- (c2) THE VECTOR ROUTE, not just the lexical one. FAQ 623 and 624 happen to carry no embedding,
  --      so (c) above only exercises the lexical-only branch of the new corpus — and a probe that
  --      proves half a corpus while claiming the corpus would be the kind of gate that passes
  --      because it never reached the code. No embedding service is needed to fix that: take an
  --      EMBEDDED approved FAQ and ask its own question with its own vector, where cosine is 1.0
  --      by construction and the lexical corroboration comes from the row's own words.
  select f.question, f.embedding_gte into v_emb_q, v_emb
    from public.company_faq f
   where f.embedding_gte is not null and f.status = 'approved'
     and coalesce(f.question, '') <> ''
   order by f.id
   limit 1;
  if v_emb is null then
    v_fail := v_fail || 'no embedded approved FAQ exists, so the vector route was never exercised';
  else
    v_hit := public.fn_sales_assist(v_emb_q, v_emb);
    if not exists (select 1 from jsonb_array_elements(coalesce(v_hit->'records', '[]'::jsonb)) r
                    where r->>'corpus' = 'company_faq') then
      v_fail := v_fail || ('the vector route did not return an embedded FAQ asked with its own '
                           || 'embedding: ' || coalesce(v_hit->>'refusal', 'no refusal recorded'));
    end if;
  end if;

  -- (c3) 21 SEP 2026 — AN ENGLISH QUESTION NO FAQ ANSWERS MUST NOT BE ANSWERED BY THE FAQ. The
  --      customer's own question from the portal audit: before this change it cited five FAQs
  --      (624, 167, 30, 623, 26) that share no subject with it, because the stopword-less arabic
  --      configuration ranked 'the/does/that/are' against every English row. Nothing may be cited
  --      from company_faq for it now. (The quote-specific answer lives in the edge function, which
  --      reads the customer's own quote; this routine is only asserted not to lie.)
  select coalesce(max(id), 0) into v_max_task from public.org_tasks;
  select coalesce(max(id), 0) into v_max_gap  from public.sales_knowledge_gap;
  v_hit := public.fn_sales_assist('the quote excludes scaffolding above 4 m but my ceilings are 3.2 m, does that exclusion matter', null::vector);
  if exists (select 1 from jsonb_array_elements(coalesce(v_hit->'records', '[]'::jsonb)) r
              where r->>'corpus' = 'company_faq') then
    v_fail := v_fail || ('an unrelated English question was still answered from company_faq: '
                         || coalesce((v_hit->'cited')::text, 'null'));
  end if;
  -- when nothing clears it records a gap and opens a task; both are removed, bounded by the ids
  -- read a moment ago so only the probe's own rows are reachable.
  delete from public.org_tasks where id > v_max_task;
  delete from public.sales_knowledge_gap where id > v_max_gap;

  -- clean up what both calls left, bounded by id so they can only reach their own rows, and prove it.
  delete from public.sales_decision_log where id > v_max_log;
  if (select coalesce(max(id), 0) from public.sales_decision_log) <> v_max_log
     or (select count(*) from public.org_tasks) <> v_before_task
     or (select count(*) from public.sales_knowledge_gap) <> v_before_gap then
    v_fail := v_fail || 'the probe did not clean up after itself';
  end if;

  -- (d) the row that was destroyed is readable again.
  if exists (select 1 from public.sales_knowledge_gap where id = 14 and public.fn_text_lost_its_script(question)) then
    v_fail := v_fail || 'sales_knowledge_gap 14 is still unreadable';
  end if;
  if exists (select 1 from public.org_tasks where id = 578945 and public.fn_text_lost_its_script(title)) then
    v_fail := v_fail || 'org_tasks 578945 is still unreadable';
  end if;

  create temporary table if not exists _verdict (line text) on commit drop;
  truncate table _verdict;
  insert into _verdict (line)
  values (case when cardinality(v_fail) = 0
               then 'PROBE OK — the FAQ answers, an unreadable question opens nothing, and 578945 reads again'
               else 'PROBE FAILED — ' || array_to_string(v_fail, ' | ') end);
end
$probe$;

-- The verdict as a ROW. raise notice is discarded by the management API; this is not.
select line as probe_verdict from _verdict;
