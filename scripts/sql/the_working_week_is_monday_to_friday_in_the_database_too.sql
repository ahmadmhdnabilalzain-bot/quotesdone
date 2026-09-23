-- THE WORKING WEEK IS MONDAY TO FRIDAY IN THE DATABASE TOO (customer_support, 23 September 2026).
--
-- WHAT WAS MEASURED. The public website said two different working weeks (website audit WEB-04): the
-- legal documents, /contact and src/components/me/workingDays.ts count Monday to Friday — the
-- founder's definition, and the week every refund and response timeline is counted in — while
-- src/content/company.json, site_assistant and the WhatsApp menu said Sunday to Thursday. PR #855
-- corrected every file. It did NOT correct the database, and the review of that PR found two paths a
-- person can reach today that still said Sunday to Thursday:
--
--   1. public.company_faq ids 620 ("كيف تُدار الشكاوى والنزاعات؟") and 622 ("كيف أتواصل مع شخص
--      حقيقي؟") — status 'approved', so sales_engineer (index.ts, the company_faq branch) prints the
--      answer to the customer verbatim. Row 622 also pointed at /contact/ with a trailing slash,
--      which answers 308 (the same finding as WEB-08, in the data instead of the content files).
--   2. public.fn_support_knowledge_gap (English "Sun-Thu") and public.fn_text_did_not_survive_reply
--      (Arabic "من الأحد إلى الخميس"). site_assistant sends both verbatim to the website chat: the
--      first on every question it cannot ground, the second when a message arrives with its script
--      stripped. Both are live.
--
-- WHAT THIS CHANGES. Those four sentences, and nothing else. The two routine bodies are lifted from
-- their canonical file (scripts/sql/every_arabic_message_is_written_not_translated.sql) unchanged
-- apart from the hours, so this file becoming their canonical definition moves no other word.
--
-- WHAT THIS DOES NOT CHANGE. No table, no grant, no schedule, no other FAQ row, and no legal
-- document: the legal texts already say Monday to Friday and are hashed in the registry.
--
-- WHAT IS STILL OPEN. scripts/checks/faq_matches_policies.mjs passes green on this because it reads
-- faq.json, marketing.json and legal.json only — it never looks at company_faq or at a routine body.
-- Extending it to both is proposed in the pull request, not done here.

-- ------------------------------------------------------------------ 1. the two approved FAQ answers
update public.company_faq
   set answer = replace(answer, 'من الأحد إلى الخميس', 'من الاثنين إلى الجمعة'),
       updated_at = now()
 where id in (620, 622)
   and answer like '%من الأحد إلى الخميس%';

-- /contact/ answers 308; the page is served at /contact (website audit WEB-08).
update public.company_faq
   set answer = replace(answer, '/contact/', '/contact'),
       updated_at = now()
 where id = 622
   and answer like '%/contact/%';

-- ------------------------------------------------------- 2. the two replies the chat sends verbatim
CREATE OR REPLACE FUNCTION public.fn_support_knowledge_gap(p_question text, p_refusal text, p_surface text DEFAULT 'website_widget'::text)
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
      || 'it now, call or WhatsApp +971 50 931 9355 (Mon-Fri, 9am-6pm GST) or email '
      || 'management@quotesdone.com.',
    'reply_ar', 'لا تتوفر لديّ إجابة موثّقة عن ذلك حتى الآن، ولا أودّ التخمين. سجّلتُ سؤالكم كما كتبتموه '
      || 'تمامًا ليُجاب عنه إجابة دقيقة. وإن احتجتم إلى الإجابة الآن، يمكنكم الاتصال أو المراسلة عبر '
      || 'واتساب:' || E'\n' || '+971 50 931 9355' || E'\n' || 'أو البريد الإلكتروني:' || E'\n'
      || 'management@quotesdone.com');
end
$function$;

revoke execute on function public.fn_support_knowledge_gap(text,text,text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_text_did_not_survive_reply(p_lang text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when lower(coalesce(p_lang, 'en')) = 'ar' then
      'وصلتني رسالتكم وقد تحوّلت حروفها إلى علامات استفهام، فتعذّرت عليّ قراءة سؤالكم. '
      || 'لا خطأ في سؤالكم، وإنما لم يصل النص سليمًا عبر الاتصال. يُرجى إعادة إرسال الرسالة. '
      || 'وإن تكرر ذلك، يمكنكم الاتصال أو المراسلة عبر واتساب:' || E'\n'
      || E'‎' || '+971 50 931 9355' || E'\n'
      || '(من الاثنين إلى الجمعة، من 9 صباحًا حتى 6 مساءً بتوقيت الإمارات)' || E'\n'
      || 'أو البريد الإلكتروني:' || E'\n' || 'management@quotesdone.com'
    else
      'Your message reached me with its characters replaced by question marks, so I cannot read '
      || 'what you asked. Nothing is wrong with your question — it did not survive the connection. '
      || 'Please send it again. If it keeps happening, call or WhatsApp +971 50 931 9355 '
      || '(Mon-Fri, 9am-6pm GST) or email management@quotesdone.com.'
  end;
$function$;

revoke execute on function public.fn_text_did_not_survive_reply(text) from public, anon, authenticated;

-- ------------------------------------------------------------------------------- 3. what it reports
-- raise NOTICE, never exception: an exception here would roll back the two definitions above with it.
do $$
declare v_faq int; v_slash int; v_gap int; v_lost int;
begin
  select count(*) into v_faq  from public.company_faq  where answer like '%من الأحد إلى الخميس%';
  select count(*) into v_slash from public.company_faq where answer like '%/contact/%';
  select count(*) into v_gap  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_support_knowledge_gap' and p.prosrc like '%Sun-Thu%';
  select count(*) into v_lost from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_text_did_not_survive_reply' and p.prosrc like '%الأحد%';
  raise notice 'company_faq rows still saying Sunday to Thursday: % (expected 0)', v_faq;
  raise notice 'company_faq rows still linking /contact/: % (expected 0)', v_slash;
  raise notice 'fn_support_knowledge_gap bodies still saying Sun-Thu: % (expected 0)', v_gap;
  raise notice 'fn_text_did_not_survive_reply bodies still saying Sunday: % (expected 0)', v_lost;
end $$;
