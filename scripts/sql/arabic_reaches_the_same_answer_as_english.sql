-- ARABIC WAS PRESENTATION ONLY. The widget rendered RTL, two WhatsApp templates existed, and the
-- prompt told the model to answer in Arabic - but nothing in the RETRIEVAL layer could read a word
-- of it. Measured 9 Sep 2026:
--   * fn_support_corpus_search built its tsquery with 'english' and 'simple' only.
--   * All 484 company_faq rows and all 408 support_knowledge rows were English.
--   * site_assistant's tokeniser was /[a-z0-9]{3,}/ - Arabic scored ZERO tokens, every time.
--   * The one Arabic question ever asked (8 Sep 02:20) got a canned English deflection.
--
-- WHAT THE MEASUREMENT CHANGED ABOUT THE PLAN. The brief assumed Postgres has no 'arabic' text
-- search configuration. It does - `select cfgname from pg_ts_config` lists it, and the snowball
-- stemmer already strips the definite article (المورد -> مورد) and folds the alef variants
-- (إمارات and امارات both -> امارا). What it does NOT fold is the two orthographic splits that
-- actually break UAE writing:
--
--   الشركة -> 'شرك'   but  الشركه -> 'شركه'      (ta-marbuta)
--   على    -> 'علي'   but  علي    -> 'عل'        (alef-maqsura)
--
-- A buyer who types الشركه and a record that says الشركة would never meet. fn_ar_norm below folds
-- those two, strips tashkeel and tatweel, and maps Arabic-Indic digits to Western ones - and BOTH
-- sides of every comparison run through it, which is the only thing that makes a fold worth having.
--
-- NO NEW PARAMETER, DELIBERATELY. fn_support_corpus_search keeps its exact (text, boolean, integer)
-- signature. The asker's language is a property of the text they typed, not of a flag a caller
-- remembers to pass - so it is detected here, once, and every existing call site gets Arabic
-- retrieval with no redeploy and no chance of a caller forgetting. It also means an Arabic speaker
-- reading the English site is still answered in Arabic, which a UI-language flag would get wrong.
--
-- ENGLISH IS THE POSITIVE CONTROL. Every English row is language='en' and an English question gets
-- the same +1.0 language bonus every English row gets, so the ordering among them is byte-identical
-- to what it was. A change that broke English would not be a fix.

-- ---------------------------------------------------------------------------------------------
-- 1. The normaliser. IMMUTABLE so it can sit inside an index later if the corpus ever grows.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_ar_norm(p_text text)
returns text
language sql
immutable
parallel safe
as $function$
  select case when p_text is null then null else
    translate(
      -- tashkeel (fathatan..sukun), the combining hamza/madda marks, superscript alef, tatweel,
      -- and the Quranic annotation marks. Written as \u escapes because a combining mark pasted
      -- literally into a file is invisible in every diff that will ever be taken of it.
      regexp_replace(p_text, '[\u064B-\u0655\u0670\u0640\u06D6-\u06ED]', '', 'g'),
      --  أ إ آ ٱ  ى  ة  ؤ  ئ   ٠١٢٣٤٥٦٧٨٩
      'أإآٱىةؤئ٠١٢٣٤٥٦٧٨٩',
      'اااايهوي0123456789'
    )
  end
$function$;

comment on function public.fn_ar_norm(text) is
  'Arabic orthographic fold for retrieval: strips tashkeel/tatweel, folds alef variants to ا, alef-maqsura ى to ي, ta-marbuta ة to ه, hamza carriers ؤ/ئ to و/ي, and Arabic-Indic digits to Western. Apply to BOTH the query and the document or it buys nothing.';

-- ---------------------------------------------------------------------------------------------
-- 2. company_faq gets a language. Default 'en' so all 484 existing rows keep their meaning without
--    a backfill, and so an unqualified insert stays English rather than becoming untyped.
-- ---------------------------------------------------------------------------------------------
alter table public.company_faq
  add column if not exists language text not null default 'en';

-- ---------------------------------------------------------------------------------------------
-- 3. The corpus view carries the language through. Appended LAST so CREATE OR REPLACE is legal and
--    no existing positional consumer shifts.
-- ---------------------------------------------------------------------------------------------
create or replace view public.v_support_corpus as
 SELECT 'faq'::text AS src,
    f.id::text AS src_id,
    f.question AS title,
    f.answer AS content,
    f.embedding_gte,
    COALESCE(o.is_public, f.public, false) AS is_public,
    f.audience,
    'FAQ: '::text || f.question AS citation,
    f.updated_at AS as_of,
    COALESCE(f.language, 'en'::text) AS lang
   FROM company_faq f
     LEFT JOIN support_public_override o ON o.src = 'faq'::text AND o.src_id = f.id::text
  WHERE f.status = 'approved'::text
UNION ALL
 SELECT 'supportkb'::text AS src,
    s.record_id AS src_id,
    s.title,
    s.body AS content,
    NULL::vector(384) AS embedding_gte,
    COALESCE(o.is_public, false) AS is_public,
    'all'::text AS audience,
    'Support pack: '::text || s.title AS citation,
    s.imported_at AS as_of,
    COALESCE(s.language, 'en'::text) AS lang
   FROM support_knowledge s
     LEFT JOIN support_public_override o ON o.src = 'supportkb'::text AND o.src_id = s.record_id
  WHERE s.runtime_index_eligible
UNION ALL
 SELECT 'ops'::text AS src,
    k.record_id AS src_id,
    k.title,
    k.content,
    k.embedding_gte,
    COALESCE(o.is_public, false) AS is_public,
    'all'::text AS audience,
    'Operations: '::text || k.title AS citation,
    NULL::timestamp with time zone AS as_of,
    'en'::text AS lang
   FROM ops_knowledge k
     LEFT JOIN support_public_override o ON o.src = 'ops'::text AND o.src_id = k.record_id;

-- ---------------------------------------------------------------------------------------------
-- 4. The retrieval arm. Third tsquery, plus a language preference that is a RANK BONUS rather than
--    a filter - so an Arabic question with no Arabic record still gets the English one back
--    (a thinner answer beats no answer) instead of returning nothing at all.
--
--    The bonus is 1.0 against ts_rank values that live in 0.0-0.7, so any record in the asker's own
--    language outranks every record that is not. That is the intended shape: fall back, never lead.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_support_corpus_search(p_query text, p_public boolean, p_limit integer DEFAULT 8)
 RETURNS TABLE(src text, src_id text, title text, content text, citation text, rank real)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with q as (
    select websearch_to_tsquery('english', coalesce(p_query, '')) as qe,
           websearch_to_tsquery('simple',  coalesce(p_query, '')) as qs,
           websearch_to_tsquery('arabic',  public.fn_ar_norm(coalesce(p_query, ''))) as qa,
           -- The asker's language is the script they typed in, not a flag anyone passed.
           case when coalesce(p_query, '') ~ '[\u0600-\u06FF]' then 'ar' else 'en' end as ask_lang
  ),
  hay as (
    select c.src, c.src_id, c.title, c.content, c.citation, c.is_public, c.lang,
           to_tsvector('english', coalesce(c.title,'') || ' ' || coalesce(c.content,'')) as te,
           to_tsvector('simple',  coalesce(c.title,'') || ' ' || coalesce(c.content,'')) as ts,
           to_tsvector('arabic',  public.fn_ar_norm(coalesce(c.title,'') || ' ' || coalesce(c.content,''))) as ta
      from public.v_support_corpus c
     where (case when p_public then c.is_public else true end)
  )
  select h.src, h.src_id, h.title, h.content, h.citation,
         (greatest(ts_rank(h.te, q.qe), ts_rank(h.ts, q.qs), ts_rank(h.ta, q.qa))
          + case when h.lang = q.ask_lang then 1.0 else 0.0 end)::real as rank
    from hay h, q
   where h.te @@ q.qe or h.ts @@ q.qs or h.ta @@ q.qa
   order by rank desc
   limit greatest(1, least(coalesce(p_limit, 8), 25))
$function$;

-- ---------------------------------------------------------------------------------------------
-- 5. fn_faq_answer - the LEVEL-0 path, and under the OpenRouter hold the only path that actually
--    produces a reply. try_faq lets a stored answer reach a visitor with NO MODEL AT ALL. It read
--    'english' only, so an Arabic question fell through to a gateway that cannot spend, and the
--    visitor got the canned deflection. The Arabic arm runs FIRST when the text is Arabic, so an
--    Arabic question is never handed an English record that happened to rank.
--
--    The greeting template also learns مرحبا / السلام عليكم / شكرا. Those were only matched in
--    Latin transliteration ('salam', 'marhaba', 'shukran'), which is not how anyone types them.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_faq_answer(p_text text, p_min_rank numeric DEFAULT 0.15, p_embedding vector DEFAULT NULL::vector, p_min_similarity numeric DEFAULT 0.86)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_q tsquery; v_tpl record; v_sim numeric; v_ar boolean;
begin
  if p_text is null or length(btrim(p_text)) < 2 then
    return jsonb_build_object('answered', false, 'reason', 'input too short');
  end if;

  v_ar := p_text ~ '[\u0600-\u06FF]';

  -- 1. Fixed intents. No retrieval, no model.
  select * into v_tpl from response_template
   where active and (
     (intent='greeting' and (p_text ~* '^\s*(hi|hey|hello|salam|marhaba|good (morning|afternoon|evening))\W*$'
                             or public.fn_ar_norm(p_text) ~ '^\s*(مرحبا|اهلا|السلام عليكم|صباح الخير|مساء الخير)\s*[؟!.]*\s*$')) or
     (intent='thanks'   and (p_text ~* '^\s*(thanks|thank you|thx|shukran|much appreciated)\W*$'
                             or public.fn_ar_norm(p_text) ~ '^\s*(شكرا|شكرا لك|شكرا جزيلا|مشكور)\s*[؟!.]*\s*$'))
   ) limit 1;
  if found then
    update response_template set used_count = used_count + 1 where key = v_tpl.key;
    return jsonb_build_object('answered', true, 'source', 'template', 'key', v_tpl.key,
                              'answer', v_tpl.body, 'confidence', 1.0);
  end if;

  -- 2a. Arabic keyword match. Only for an Arabic question, and only against Arabic records.
  if v_ar then
    v_q := websearch_to_tsquery('arabic', public.fn_ar_norm(p_text));
    if v_q is not null then
      select f.question, f.answer,
             ts_rank(to_tsvector('arabic', public.fn_ar_norm(coalesce(f.question,'')||' '||coalesce(f.answer,''))), v_q) as rank
        into r
        from company_faq f
       where f.public and f.status='approved' and f.language = 'ar'
         and to_tsvector('arabic', public.fn_ar_norm(coalesce(f.question,'')||' '||coalesce(f.answer,''))) @@ v_q
       order by rank desc limit 1;
      if found and r.rank >= p_min_rank then
        return jsonb_build_object('answered', true, 'source', 'faq_keyword_ar', 'question', r.question,
                                  'answer', r.answer, 'confidence', round(r.rank::numeric, 4));
      end if;
    end if;
  end if;

  -- 2b. Keyword match. Cheap and precise when the wording lines up.
  --     Restricted to English records so an Arabic corpus row can never answer an English question.
  v_q := websearch_to_tsquery('english', p_text);
  if v_q is not null then
    select f.question, f.answer,
           ts_rank(to_tsvector('english', coalesce(f.question,'')||' '||coalesce(f.answer,'')), v_q) as rank
      into r
      from company_faq f
     where f.public and f.status='approved' and f.language = 'en'
       and to_tsvector('english', coalesce(f.question,'')||' '||coalesce(f.answer,'')) @@ v_q
     order by rank desc limit 1;
    if found and r.rank >= p_min_rank then
      return jsonb_build_object('answered', true, 'source', 'faq_keyword', 'question', r.question,
                                'answer', r.answer, 'confidence', round(r.rank::numeric, 4));
    end if;
  end if;

  -- 3. Semantic match. Catches the same question asked in different words.
  --    Scoped to the asker's language: gte-small puts Arabic and English text in the same space
  --    closely enough that a 0.86 neighbour in the WRONG language is a real risk, and answering an
  --    Arabic buyer in English is the failure this whole file exists to end.
  if p_embedding is not null then
    select f.question, f.answer, 1 - (f.embedding_gte <=> p_embedding) as sim into r
      from company_faq f
     where f.public and f.status='approved' and f.embedding_gte is not null
       and f.language = case when v_ar then 'ar' else 'en' end
     order by f.embedding_gte <=> p_embedding limit 1;
    if found then
      v_sim := round((r.sim)::numeric, 4);
      if v_sim >= p_min_similarity then
        return jsonb_build_object('answered', true, 'source', 'faq_semantic', 'question', r.question,
                                  'answer', r.answer, 'confidence', v_sim);
      end if;
      return jsonb_build_object('answered', false, 'reason', 'no confident FAQ match',
                                'best_similarity', v_sim);
    end if;
  end if;

  return jsonb_build_object('answered', false, 'reason', 'no confident FAQ match');
end $function$;

-- ---------------------------------------------------------------------------------------------
-- 6. THE CONTENT. Twenty-two customer-facing answers in Modern Standard Arabic, written here rather
--    than machine-translated - OpenRouter is on hold and these are standard UAE construction and
--    commercial terms, not prose that needs a model.
--
--    Each row states the SAME facts as the English record it mirrors: 3% reveal fee with no cap,
--    the 3/5-working-day refund ladder, no VAT registration, up to 3 working days for supplier
--    verification, +971 50 931 9355. source_note names the English id so a future correction to one
--    can find the other - a correction that reaches only half its readers is not a correction.
--
--    ids are given explicitly from 601 so they cannot collide with the sequence (max today 500).
-- ---------------------------------------------------------------------------------------------
insert into public.company_faq (id, section, sort, question, answer, audience, status, source_note, tags, public, language, approved_by, approved_at, created_at, updated_at)
overriding system value
values
 (601, 'Arabic', 1, 'ما هو QuotesDone؟',
  'QuotesDone هو سوق إلكتروني في الإمارات لطلبات عروض الأسعار بين الشركات، ومقره دبي. يصف المشتري ما يحتاجه بالنص أو الصوت أو الصورة أو المخطط، فيحوّله المحرك الذكي إلى طلب واضح قابل للتسعير ويطابقه مع موردين تم التحقق منهم يقدمون عروض أسعار دون الكشف عن هويتهم. يقارن المشتري العروض ويدفع رسوم كشف بنسبة 3٪ على العرض الذي يختاره لكشف هوية ذلك المورد وبيانات التواصل معه. تُشغّل المنصة شركة QuotesDone Technologies، وهي منشأة مرخّصة من دائرة الاقتصاد والسياحة في دبي، رخصة تاجر إلكتروني رقم 1633275.',
  'all', 'approved', 'Arabic mirror of company_faq id 1', '{}', true, 'ar', 'founder', now(), now(), now()),

 (602, 'Arabic', 2, 'كيف يعمل QuotesDone؟',
  'تصف ما تحتاجه بالكلمات أو بالصوت أو بصورة أو مخطط. يحوّل المحرك الذكي وصفك إلى طلب واضح ويطابقه مع الموردين القادرين فعلياً على تنفيذ العمل، فيرسلون عروض أسعار دون الكشف عن هويتهم. تقارن العروض، وعندما تختار عرضاً تدفع رسوم كشف بنسبة 3٪ لكشف هوية ذلك المورد وبيانات التواصل معه.',
  'customer', 'approved', 'Arabic mirror of company_faq id 11', '{}', true, 'ar', 'founder', now(), now(), now()),

 (603, 'Arabic', 3, 'ماذا يحدث بعد إرسال طلبي؟',
  'ينظّم المحرك الذكي طلبك وقد يسألك بضعة أسئلة سريعة لاستكماله، ثم يطابق الطلب ويدعو الموردين القادرين على تنفيذه. نُعلمك فور وصول كل عرض سعر دون هوية، وتتابع كل شيء داخل التطبيق.',
  'customer', 'approved', 'Arabic mirror of company_faq id 12', '{}', true, 'ar', 'founder', now(), now(), now()),

 (604, 'Arabic', 4, 'كم عدد الموردين الذين يستلمون طلبي؟',
  'الموردون القادرون فعلياً على تنفيذ عملك فقط، وعادة عدد محدود وليس إرسالاً جماعياً. العدد محدود عمداً لإبقاء العروض وثيقة الصلة والمنافسة عادلة.',
  'customer', 'approved', 'Arabic mirror of company_faq id 13', '{}', true, 'ar', 'founder', now(), now(), now()),

 (605, 'Arabic', 5, 'هل هويتي مخفية عن الموردين؟',
  'نعم، مخفية بالكامل. لا يرى الموردون اسمك ولا رقم هاتفك ولا بريدك الإلكتروني ولا اسم شركتك ولا عنوانك الدقيق، بل طبيعة العمل والمنطقة أو الإمارة بشكل عام فقط. كما تُحجب تلقائياً أي بيانات تعريفية من المخططات التي ترفعها.',
  'customer', 'approved', 'Arabic mirror of company_faq id 16', '{}', true, 'ar', 'founder', now(), now(), now()),

 (606, 'Arabic', 6, 'متى يتم الكشف عن هويتي؟',
  'لا يتم الكشف عنها قبل أن تختار أنت. تبقى بياناتك وبيانات المورد مخفية حتى تختار عرض سعر وتدفع رسوم الكشف البالغة 3٪ لكشف ذلك المورد وحده.',
  'customer', 'approved', 'Arabic mirror of company_faq id 17', '{}', true, 'ar', 'founder', now(), now(), now()),

 (607, 'Arabic', 7, 'كم تستغرق العملية؟',
  'يعتمد ذلك على طبيعة العمل، لكن من الواقعي أن تستلم عروض الأسعار خلال 3 إلى 5 أيام عمل، ونُعلمك فور وصول كل عرض. بعد أن تكشف عن مورد، أمامه 5 أيام عمل من تاريخ دفعك للرد: نتابعه نيابة عنك بعد 3 أيام عمل، ونتخذ القرار النهائي في اليوم الخامس، وإذا بقي دون رد تُسترد رسوم الكشف كاملة، مع العلم أن البنوك تستغرق عادة من 7 إلى 14 يوم عمل لإظهار المبلغ.',
  'customer', 'approved', 'Arabic mirror of company_faq id 26', '{}', true, 'ar', 'founder', now(), now(), now()),

 (608, 'Arabic', 8, 'كيف أدفع؟',
  'تدفع رسوم الكشف بأمان بالبطاقة المصرفية أو عبر Apple Pay من خلال صفحة الدفع لدينا. ولا تُحصّل الرسوم إلا عندما تختار الكشف عن مورد.',
  'customer', 'approved', 'Arabic mirror of company_faq id 29', '{}', true, 'ar', 'founder', now(), now(), now()),

 (609, 'Arabic', 9, 'ما هي رسوم المنصة؟',
  'بصفتك عميلاً تدفع رسماً واحداً فقط: رسوم كشف بنسبة 3٪ من قيمة عرض السعر الذي تختاره، دون حد أقصى، وعلى ذلك العرض المختار وحده. لا توجد أي رسوم أخرى عليك. والموردون لا يدفعون أي عمولة على الأعمال التي يفوزون بها.',
  'customer', 'approved', 'Arabic mirror of company_faq id 30', '{}', true, 'ar', 'founder', now(), now(), now()),

 (610, 'Arabic', 10, 'ما هي رسوم الـ 3٪؟',
  'رسوم الـ 3٪ هي رسوم الكشف التي يدفعها العميل: 3٪ من قيمة عرض السعر الذي تختاره، دون حد أقصى. يدفعها العميل مرة واحدة لكشف هوية المورد الذي اختاره وبيانات التواصل معه. وهي الرسوم الأساسية للمنصة ويتحملها العميل، والموردون لا يدفعون أي عمولة.',
  'all', 'approved', 'Arabic mirror of company_faq id 89', '{}', true, 'ar', 'founder', now(), now(), now()),

 (611, 'Arabic', 11, 'متى يتم تحصيل الرسوم؟',
  'عند خطوة الكشف فقط، أي حين يختار العميل عرض سعر ويقرر كشف ذلك المورد. لا يُحصّل أي مبلغ مقابل نشر الطلب أو استلام العروض أو مقارنتها، وتدفع فقط عندما تقرر المضي قدماً مع مورد.',
  'all', 'approved', 'Arabic mirror of company_faq id 90', '{}', true, 'ar', 'founder', now(), now(), now()),

 (612, 'Arabic', 12, 'ما هي طرق الدفع المقبولة؟',
  'تتم المدفوعات بأمان بالبطاقة المصرفية أو عبر Apple Pay من خلال صفحة الدفع الخاصة بنا عبر Stripe، وذلك لرسوم الكشف الخاصة بالعميل وللاشتراك السنوي للمورد على حد سواء.',
  'all', 'approved', 'Arabic mirror of company_faq id 92', '{}', true, 'ar', 'founder', now(), now(), now()),

 (613, 'Arabic', 13, 'هل تصدرون فواتير بضريبة القيمة المضافة؟',
  'شركة QuotesDone Technologies غير مسجلة حالياً في ضريبة القيمة المضافة، لذلك تصدر الفواتير دون ضريبة قيمة مضافة ودون رقم تسجيل ضريبي. وإذا سُجّلت الشركة مستقبلاً في ضريبة القيمة المضافة، فستُطبّق الضريبة وتظهر في الفواتير مع رقم التسجيل الضريبي.',
  'all', 'approved', 'Arabic mirror of company_faq id 93', '{}', true, 'ar', 'founder', now(), now(), now()),

 (614, 'Arabic', 14, 'كيف تتم معالجة استرداد المبالغ؟',
  'تُعاد المبالغ إلى وسيلة الدفع الأصلية عبر Stripe، ويعتمد كل استرداد شخص لدينا، ولا شيء منها آلي. أوضح الحالات هي صمت المورد: إذا لم يرد المورد الذي كشفت عنه خلال 5 أيام عمل من تاريخ دفعك، ونحن نتابعه بعد 3 أيام عمل ونتخذ القرار النهائي في اليوم الخامس، تُسترد رسوم الكشف كاملة. وتستغرق البنوك عادة من 7 إلى 14 يوم عمل لإظهار المبلغ المسترد. أما طلبات الاسترداد الأخرى المقدمة ضمن مهلة الاسترداد فتُراجع بالطريقة نفسها.',
  'all', 'approved', 'Arabic mirror of company_faq id 94', '{}', true, 'ar', 'founder', now(), now(), now()),

 (615, 'Arabic', 15, 'هل يمكنني استرداد المبلغ؟',
  'نعم، في حالات محددة، وأبرزها ألا يرد المورد الذي كشفت عنه خلال 5 أيام عمل من تاريخ دفعك. نتابعه بعد 3 أيام عمل مع نسخة إليك، وفي اليوم الخامس نتخذ القرار النهائي، وإذا بقي المورد صامتاً تُسترد رسوم الكشف كاملة إلى وسيلة الدفع الأصلية. كل استرداد يقرره شخص لدينا ولا شيء منها آلي، وتستغرق البنوك من 7 إلى 14 يوم عمل لإظهاره. وتخضع حالات الاسترداد الأخرى لسياسة الاسترداد لدينا.',
  'customer', 'approved', 'Arabic mirror of company_faq id 31', '{}', true, 'ar', 'founder', now(), now(), now()),

 (616, 'Arabic', 16, 'سياسة استرداد الأموال',
  'تُعاد المبالغ إلى وسيلة الدفع الأصلية للعميل عبر Stripe، ويقرر كل استرداد شخص لدينا ولا شيء منها آلي. يبدأ التسلسل من تاريخ دفع العميل: إذا لم يرد المورد المكشوف عنه بحلول يوم العمل الثالث، يتابعه مدير نجاح العملاء لدينا مع نسخة إلى العميل؛ وإذا بقي صامتاً في يوم العمل الخامس يُرفع الأمر إلينا للقرار النهائي؛ وإذا لم يرد على ذلك تُسترد رسوم الكشف البالغة 3٪ كاملة للعميل، وتستغرق البنوك من 7 إلى 14 يوم عمل لإظهارها. ويصبح المورد غير المستجيب مديناً بقيمة الرسوم المستردة إضافة إلى رسوم إدارية قدرها 250 درهماً وفائدة بسيطة قدرها 9٪ سنوياً، وهي الحد الأقصى القانوني في دولة الإمارات، إلا حيث لا يجيز القانون الإماراتي فرض ذلك، ويُوقف عن المطابقات الجديدة حتى السداد. أيام العمل هي من الاثنين إلى الجمعة باستثناء العطل الرسمية في الدولة. وتُراجع طلبات الاسترداد الأخرى المقدمة خلال مهلة أيام العمل الخمسة وتُسترد بالطريقة نفسها إن كانت صحيحة.',
  'all', 'approved', 'Arabic mirror of company_faq id 167', '{}', true, 'ar', 'founder', now(), now(), now()),

 (617, 'Arabic', 17, 'كيف أسجل كمورد؟',
  'سجّل عبر بوابة الموردين في QuotesDone: طالب بملف شركتك أو أنشئه، ثم ارفع مستندات منشأتك، وتشمل الرخصة التجارية والمستندات الأخرى المطلوبة. يراجعها المحرك الذكي، وبعد الاعتماد تبدأ باستلام طلبات عمل مناسبة ودون هوية لتقديم عروض أسعار عليها.',
  'supplier', 'approved', 'Arabic mirror of company_faq id 36', '{}', true, 'ar', 'founder', now(), now(), now()),

 (618, 'Arabic', 18, 'كيف يتم التحقق من شركتي؟',
  'تُقرأ مستنداتك المرفوعة وتُفحص تلقائياً، وتشمل بيانات الرخصة والجهة المُصدرة وتاريخ الانتهاء، ثم تُراجع من حيث صحتها وارتباطها بنشاطك قبل اعتماد حسابك. ونؤكد الاسم القانوني المرخّص لمنشأتك ونشاطها التجاري ليطمئن العملاء لمن يتعاملون معه.',
  'supplier', 'approved', 'Arabic mirror of company_faq id 38', '{}', true, 'ar', 'founder', now(), now(), now()),

 (619, 'Arabic', 19, 'كم يستغرق التحقق من المورد؟',
  'التحقق سريع، وبحد أقصى 3 أيام عمل بمجرد اكتمال مستنداتك. وإذا احتاج أي شيء إلى تصحيح، نخبرك بالضبط بما هو مطلوب.',
  'supplier', 'approved', 'Arabic mirror of company_faq id 39', '{}', true, 'ar', 'founder', now(), now(), now()),

 (620, 'Arabic', 20, 'كيف تُدار الشكاوى والنزاعات؟',
  'تتبع النزاعات مساراً محدداً: ترفع المشكلة، وتُراجع مع السجل الكامل، وتُحل عبر المنصة، بما في ذلك الاسترداد حيثما كان مناسباً، ويُسوّى مقابل المعاملة الأصلية. والهدف نتيجة عادلة للطرفين. وإذا رغبت في التحدث إلى شخص مباشرة، اتصل أو راسلنا عبر واتساب على الرقم التالي.
+971 50 931 9355
من الأحد إلى الخميس، من 9 صباحاً حتى 6 مساءً بتوقيت الخليج، أو راسلنا على
management@quotesdone.com',
  'all', 'approved', 'Arabic mirror of company_faq id 133, with the published contact line', '{}', true, 'ar', 'founder', now(), now(), now()),

 (621, 'Arabic', 21, 'ما هي القطاعات التي يخدمها QuotesDone؟',
  'الإنشاءات وخدمات البيئة المبنية المرتبطة بها: البناء والتشطيبات والتصميم الداخلي، والأعمال الكهروميكانيكية من كهرباء وإطفاء حريق وتكييف وسباكة، والألمنيوم والزجاج، والنجارة والأثاث المفصّل، والأرضيات والبلاط، والأسقف المستعارة والجبس، والدهانات، والعزل المائي، وتنسيق الحدائق وحمامات السباحة، واللوحات الإعلانية، وكاميرات المراقبة وأنظمة الأمن، وأتمتة المنازل الذكية، والطاقة الشمسية، وإدارة المرافق، والتنظيف، ومكافحة الحشرات، وخدمات النقل، وصيانة المكيفات وغيرها، مع إضافة تخصصات جديدة تلقائياً كلما سجّلها الموردون.',
  'all', 'approved', 'Arabic mirror of company_faq id 5', '{}', true, 'ar', 'founder', now(), now(), now()),

 (622, 'Arabic', 22, 'كيف أتواصل مع شخص حقيقي؟',
  'يسعدنا التحدث إليك. اتصل أو راسلنا عبر واتساب على الرقم
+971 50 931 9355
من الأحد إلى الخميس، من 9 صباحاً حتى 6 مساءً بتوقيت الخليج. أو راسلنا بالبريد الإلكتروني على
management@quotesdone.com
كما يمكنك استخدام صفحة الاتصال على
/contact/',
  'all', 'approved', 'Arabic contact answer - the widget deflected every Arabic question to English before 9 Sep 2026', '{}', true, 'ar', 'founder', now(), now(), now())

on conflict (id) do update set
  section = excluded.section, sort = excluded.sort, question = excluded.question,
  answer = excluded.answer, audience = excluded.audience, status = excluded.status,
  source_note = excluded.source_note, public = excluded.public, language = excluded.language,
  approved_by = excluded.approved_by, updated_at = now();

-- The ids above are explicit, and company_faq.id is GENERATED ALWAYS. Move the identity past them
-- or the next ordinary insert collides on a row that was written by hand.
select setval(pg_get_serial_sequence('public.company_faq', 'id'),
              greatest((select max(id) from public.company_faq), 1), true);
