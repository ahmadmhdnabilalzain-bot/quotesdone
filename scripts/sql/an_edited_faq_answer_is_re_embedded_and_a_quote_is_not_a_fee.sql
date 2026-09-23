-- AN EDITED FAQ ANSWER IS RE-EMBEDDED, AND A QUOTE IS NOT A FEE — customer_support, 23 Sep 2026.
--
-- 1. STALE VECTORS. public.company_faq.embedding_gte is the vector fn_faq_answer's semantic step reads
--    (WhatsApp, site assistant). Nothing invalidated it when question/answer changed: every earlier
--    rewrite cleared it by hand (the_faq_and_the_signed_texts_carry_the_ladder..., the_licence_we_name...,
--    an_unmatched_question_gets_a_proper_answer), and the two drawing files of #872 did not, so ids 16,
--    20, 116, 126 and 289 kept the vector of their OLD text. MEASURED 23 Sep 2026 before this file:
--    stored vs gte-small(question || E'\n' || answer) of the current text = 0.9749, 0.9529, 0.9914,
--    0.9862, 0.9728 (the recipe reproduces an unchanged row at 1.0000, embed_sales_knowledge.mjs).
--    FIX: a BEFORE UPDATE trigger nulls embedding_gte whenever question or answer changes, unless the
--    same statement also writes a new vector (the embedder does: it sets embedding_gte only). The
--    re-embed is then `node scripts/kb/embed_sales_knowledge.mjs --table=company_faq`, which takes
--    every row whose embedding_gte is null — free in-region gte-small, never OpenRouter.
--    The five rows are cleared below so that same run rebuilds them.
--
-- 2. "ما هي رسومكم" (what are your fees) WAS ANSWERED WITH A QUOTATION FAQ. fn_faq_concepts folds سعر /
--    اسعار (price) to the concept 'fee', but in Arabic عرض سعر / عروض الأسعار is "a quotation", not a
--    charge. 21 of the 30 approved Arabic FAQ questions that carried 'fee' carried it only from that
--    phrase, so an Arabic fee question (one concept, 'fee') was "corroborated" by any quote FAQ. MEASURED
--    23 Sep 2026: "ما هي رسومكم" -> "هل يمكنني رفض جميع عروض الأسعار؟" at 0.917, corroborated 1/1.
--    FIX: the price word right after عرض / عروض is dropped before the concepts are read, so a quotation
--    is concept عرض, and سعر on its own (the price of a job) is still 'fee'.
--
--   node scripts/apply_sql.mjs scripts/sql/an_edited_faq_answer_is_re_embedded_and_a_quote_is_not_a_fee.sql --apply --ddl
--   node scripts/kb/embed_sales_knowledge.mjs --table=company_faq
--   node --test scripts/checks/an_edited_faq_answer_is_re_embedded.test.mjs

create or replace function public.fn_company_faq_text_change_clears_embedding()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if (new.question is distinct from old.question or new.answer is distinct from old.answer)
     and new.embedding_gte is not distinct from old.embedding_gte then
    new.embedding_gte := null;
  end if;
  return new;
end $fn$;

revoke execute on function public.fn_company_faq_text_change_clears_embedding() from public, anon, authenticated;

drop trigger if exists trg_company_faq_text_change_clears_embedding on public.company_faq;
create trigger trg_company_faq_text_change_clears_embedding
  before update of question, answer on public.company_faq
  for each row execute function public.fn_company_faq_text_change_clears_embedding();

create or replace function public.fn_faq_concepts(p_text text, p_ar boolean)
 returns text[]
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  with fold(lexeme, concept) as (values
      ('fee','fee'),('charg','fee'),('cost','fee'),('price','fee'),('pay','fee'),('paid','fee'),('payment','fee'),
      ('much','fee'),('commiss','fee'),('free','fee'),('subscript','fee'),('expens','fee'),('cheap','fee'),
      ('رسوم','fee'),('رسم','fee'),('تكلف','fee'),('تكلفه','fee'),('سعر','fee'),('اسعار','fee'),('عمول','fee'),
      ('مجا','fee'),('دفع','fee'),('اشتر','fee'),
      ('supplier','supplier'),('vendor','supplier'),('contractor','supplier'),('مورد','supplier'),('موردين','supplier'))
  select coalesce(array_agg(distinct coalesce(f.concept, l)), '{}')
    from unnest(tsvector_to_array(case when p_ar then to_tsvector('arabic',
                    -- عرض سعر / عروض الأسعار is a quotation: its price word is not a fee.
                    regexp_replace(public.fn_ar_norm(coalesce(p_text, '')), '(عرض|عروض)\s+(ال)?(سعر|اسعار)', '\1', 'g'))
                                       else to_tsvector('english', coalesce(p_text, '')) end)) l
    left join fold f on f.lexeme = l
   where not (p_ar and l = any (array['كم','هل','ما','هي','هو','كيف','مع','في','من','على','عن','الي','او','لا','متي','ماذا','لماذا','اين','انا','نحن','انتم','لكم','لي']))
$function$;

revoke execute on function public.fn_faq_concepts(text, boolean) from public, anon, authenticated;

-- 3. THE ARABIC MIRRORS STILL PROMISED AUTOMATIC REDACTION. #872 corrected ids 16, 20, 116 and 126 in
--    English only; their Arabic mirrors 605, 663, 718 and 741 (source_note "Arabic mirror of company_faq
--    id N") still said identifying details are removed automatically, so an Arabic drawing question got
--    the claim the English was withdrawn for. Same meaning as the English text, guarded on the old
--    sentence; the trigger above clears their vectors as they change.
update public.company_faq set answer = replace(answer,
         'كما تُحجب تلقائياً أي بيانات تعريفية من المخططات التي ترفعها.',
         'ولا يُشارَك مخططك مع الموردين إلا بعد تغطية بياناتك عليه (خانة العنوان واسمك وهاتفك وبريدك الإلكتروني)، وإذا تعذّرت تغطيتها لا يُشارَك المخطط، ويسعّر الموردون حينها على أساس نطاق العمل والكميات.'),
       updated_at = now()
 where id = 605 and answer like '%تُحجب تلقائياً أي بيانات تعريفية%';
update public.company_faq set answer = replace(answer,
         'وتُنقّى المخططات تلقائيًا من أي تفاصيل تكشف الهوية قبل أن يطّلع عليها الموردون.',
         'ولا يُشارَك المخطط مع الموردين إلا بعد تغطية بياناتكم عليه (خانة العنوان واسمكم وهاتفكم وبريدكم الإلكتروني)؛ والمخطط الذي تتعذّر تغطيته لا يُشارَك، ويسعّر الموردون حينها على أساس نطاق العمل والكميات.'),
       updated_at = now()
 where id = 663 and answer like '%تُنقّى المخططات تلقائيًا%';
update public.company_faq set answer = replace(answer,
         'كما تُحجب تلقائيًا التفاصيل التعريفية من مخططات العميل قبل أن يراها أي مورّد.',
         'ولا يُشارَك مخطط العميل مع الموردين إلا بعد تغطية التفاصيل التعريفية عليه، والمخطط الذي تتعذّر تغطيته لا يُشارَك.'),
       updated_at = now()
 where id = 718 and answer like '%تُحجب تلقائيًا التفاصيل التعريفية%';
update public.company_faq set answer = replace(answer,
         'ويحجب تلقائيًا التفاصيل التي تكشف هويّتكم قبل أن يراه أي مورّد، فتبقون مجهولين.',
         'ولا يصل المخطط إلى الموردين إلا بعد تغطية بياناتكم عليه (خانة العنوان واسمكم وهاتفكم وبريدكم الإلكتروني)، فتبقون مجهولين؛ والمخطط الذي تتعذّر تغطيته لا يُشارَك.'),
       updated_at = now()
 where id = 741 and answer like '%ويحجب تلقائيًا التفاصيل%';

-- The five rows #872 rewrote without clearing their vectors. Guarded: only while the vector is set, so a
-- re-run after the re-embed would clear them again — run the embedder after every apply of this file.
update public.company_faq set embedding_gte = null
 where id in (16, 20, 116, 126, 289) and embedding_gte is not null;

-- PROOF (writes nothing — this file carries DDL, so it returns a verdict row instead of raising). The
-- trigger's behaviour on a real edit is proved by scripts/checks/an_edited_faq_answer_is_re_embedded.test.mjs
-- inside a transaction it never commits.
select case
  when not exists (select 1 from pg_trigger where tgname = 'trg_company_faq_text_change_clears_embedding' and tgenabled = 'O')
    then 'PROBE FAILED: trigger missing or disabled'
  when 'fee' = any (public.fn_faq_concepts('هل يمكنني رفض جميع عروض الأسعار؟', true))
    then 'PROBE FAILED: a quotation still reads as a fee'
  when not ('fee' = any (public.fn_faq_concepts('ما هي رسومكم', true)))
    then 'PROBE FAILED: a fee question lost its fee concept'
  when exists (select 1 from public.company_faq where id in (605, 663, 718, 741) and answer ~ 'تلقائي')
    then 'PROBE FAILED: an Arabic mirror still promises automatic redaction'
  when exists (select 1 from public.company_faq where id in (16, 20, 116, 126, 289) and embedding_gte is not null)
    then 'PROBE FAILED: a rewritten row kept its old vector'
  else 'PROBE OK' end as verdict;
