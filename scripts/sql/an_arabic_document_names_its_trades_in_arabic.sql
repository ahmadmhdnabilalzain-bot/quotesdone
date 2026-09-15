-- AN ARABIC DOCUMENT NAMES ITS TRADES IN ARABIC. Seat: sales_engineer. 15 Sep 2026.
--
-- Founder rule: EN + full AR everywhere. PR #697 made a supplier's profile and catalogue text propose
-- taxonomy_trade codes by code (supabase/functions/_shared/supplier_doc_trades.ts), mirroring
-- public.fn_norm_trades. Both matched English aliases only.
--
-- MEASURED BEFORE THIS FILE (production, 15 Sep 2026):
--   * 40 active taxonomy_trade codes; 0 aliases containing an Arabic letter.
--   * fn_norm_trades('نجارة وألمنيوم') = {} — an Arabic brief resolved to no trade, and an Arabic-only
--     profile proposed none.
--   * taxonomy_trade.label_ar already exists and is filled for all 40 (PR #697); nothing to add there.
--   * On this database (ICU, en_US.UTF-8) '\m' DOES treat Arabic letters as word characters:
--     'بنجارة' ~ '\mنجارة' is false, 'اعمال نجارة' ~ '\mنجارة' is true. So the word-start rule
--     already works for Arabic; what it cannot do alone is read the article: 'النجارة' ~ '\mنجارة'
--     is false, because ال is part of the word.
--   * public.fn_ar_norm already folds Arabic spelling (tashkeel, tatweel, أ إ آ ٱ → ا, ى → ي, ة → ه,
--     ؤ → و, ئ → ي, Arabic-Indic digits). It is reused here, not rewritten.
--
-- WHAT THIS CHANGES
--   1. Arabic aliases for all 40 active codes — common UAE/Gulf trade words, formal and colloquial
--      (نجار, ألمنيوم, تكييف, سباك, كهرب, دهان, عزل, برادي, دواليب …). Appended to taxonomy_trade.aliases,
--      never replacing an English one; idempotent (only aliases not already present are added). The
--      list is the JSON literal in the first DO block below and must equal supabase/functions/_shared/trade_aliases_ar.json
--      (scripts/checks/arabic_trade_words_resolve_the_same_in_sql_and_ts.test.mjs asserts it).
--   2. fn_norm_trades folds both the text and each alias with fn_ar_norm, and an ARABIC alias may carry
--      the definite article and the attached letters before its first word (ال و ف ب ل ك, والـ بالـ …,
--      لل ولل فلل) and ال before each later word. So "مكافحة حريق" matches "لمكافحة الحريق". Aliases
--      are stored without ال; step 1 refuses one that has it. Start of word stays '\m'; the end stays
--      open, as for English, so the stem سباك matches سباكة. An English alias matches exactly as before.
--   3. EXECUTE on fn_norm_trades was held by PUBLIC (anon and authenticated could call it). Its callers
--      are fn_customer_decision_support (SECURITY DEFINER, owner postgres) and the sales_engineer
--      function (service_role); both keep it. PUBLIC, anon and authenticated lose it.
--
-- EXACT OR NONE. Every Arabic alias names one code; step 1 refuses an alias shared by two codes. No
-- stemmer, no similarity, no model. Words deliberately NOT aliases, because the open end would turn a
-- common word into a trade: دكت (دكتور), مرآة (مراهق), باب (بابا), بوابة (بوابة الموردين), لافت (لافت
-- للنظر), عمال (every profile's "our workers"), تجديد (تجديد الرخصة). The fixture holds these negatives.
--
-- WHAT THIS DOES NOT CHANGE: fn_match_capability, supplier_capabilities, the directory derivation,
-- taxonomy_trade.label / label_ar, and the English aliases. The TS twin is trade_words.ts.

do $do$
declare
  v_ar jsonb := $aliases$
{
  "aluminium": ["ألمنيوم", "ألومنيوم", "ألمونيوم", "كلادينج", "تكسية واجهات", "لوفرات"],
  "av_it": ["تيار خفيف", "صوت وصورة", "صوتيات", "أنظمة صوتية", "كابلات بيانات", "إذاعة داخلية"],
  "building_materials": ["مواد بناء", "مواد إنشائية", "إسمنت", "خرسانة جاهزة", "طابوق", "ركام"],
  "chemicals": ["كيماويات", "مواد كيميائية", "مواد لاصقة"],
  "civil_works": ["أعمال مدنية", "مقاولات عامة", "مقاولات بناء", "مقاول بناء", "إنشاءات", "أعمال إنشائية", "خرسان", "أعمال هدم"],
  "cleaning": ["تنظيف", "إدارة مرافق", "مكافحة حشرات", "مكافحة آفات", "صيانة عقارات", "صيانة مباني"],
  "doors": ["أبواب", "نوافذ", "شبابيك"],
  "electrical": ["كهرب", "إنارة", "إنارات", "لوحات توزيع", "لوحة توزيع", "حوامل كابلات"],
  "elevators": ["مصعد", "مصاعد", "سلالم متحركة", "سلم متحرك"],
  "engineering_consultancy": ["استشارات هندسية", "مكتب هندسي", "مكاتب هندسية", "مهندس معماري", "هندسة معمارية", "تصميم معماري", "مهندس إنشائي"],
  "fire_fighting": ["مكافحة حريق", "مكافحة حرائق", "إطفاء حريق", "أنظمة إطفاء", "إنذار حريق", "رشاشات حريق", "مضخات حريق", "مضخة حريق", "حماية من حريق"],
  "flooring": ["أرضيات", "بلاط", "تبليط", "فينيل", "سجاد", "موكيت", "باركيه", "رخام", "سيراميك", "بورسلين", "جرانيت"],
  "glazing": ["زجاج", "مرايا", "سكوريت", "سيكوريت"],
  "gypsum": ["جبس", "أسقف معلقة", "سقف معلق", "أسقف مستعارة", "سقف مستعار", "قواطع جبس", "لياسة"],
  "heavy_equipment": ["معدات ثقيلة", "آليات ثقيلة", "حفارات", "حفارة", "رافعات", "رافعة شوكية", "تأجير معدات"],
  "home_automation": ["منزل ذكي", "منازل ذكية", "بيت ذكي", "أتمتة", "نظام إدارة مباني", "أنظمة إدارة مباني"],
  "hvac": ["تكييف", "مكيف", "تهوية", "مجاري هواء", "تشيلر", "شيلر", "وحدات مناولة هواء"],
  "interior_fitout": ["تشطيبات داخلية", "تشطيب داخلي", "تصميم داخلي", "ديكور", "فيت أوت", "تجهيزات داخلية", "ترميم"],
  "it_services": ["تقنية معلومات", "تكنولوجيا معلومات", "أمن معلومات", "أمن سيبراني", "شبكات حاسوب", "شبكات كمبيوتر"],
  "joinery": ["نجار", "أعمال خشب", "خشبي", "مطابخ", "مطبخ", "خزائن", "خزانة", "دواليب", "دولاب", "كبتات", "سطح عمل", "أسطح عمل"],
  "labour_supply": ["توريد عمالة", "توفير عمالة", "توريد أيدي عاملة", "أيدي عاملة", "خدمات عمالة"],
  "landscaping": ["تنسيق حدائق", "لاندسكيب", "حدائق", "حديقة", "أنظمة ري", "شبكات ري", "مسابح", "مسبح", "حمامات سباحة"],
  "logistics_moving": ["نقل أثاث", "نقل وتخزين", "شحن بضائع", "وكيل شحن", "خدمات لوجستية", "لوجستي"],
  "marine": ["معدات بحرية", "مستلزمات بحرية", "تموين سفن", "خدمات بحرية", "أعمال بحرية"],
  "mep_general": ["كهروميكانيك", "إلكتروميكانيك", "أعمال ميكانيكية وكهربائية"],
  "oilfield": ["حقول نفط", "حقل نفط", "نفط وغاز", "بترول وغاز", "بتروكيماوي"],
  "packaging": ["تغليف", "مطبعة", "مطابع", "كرتون مقوى", "كرتون مضلع"],
  "painting": ["دهان", "طلاء"],
  "plastics_pipes": ["منتجات بلاستيك", "أنابيب بلاستيك", "أنابيب ووصلات", "وصلات أنابيب", "تصنيع بلاستيك"],
  "plumbing": ["سباك", "أدوات صحية", "تمديدات صحية", "صرف صحي", "إمدادات مياه", "تمديدات مياه"],
  "power_generators": ["مولد", "توليد طاقة", "توليد كهرباء"],
  "safety_equipment": ["معدات سلامة", "مستلزمات سلامة", "معدات وقاية", "ملابس واقية", "ملابس سلامة", "حماية من سقوط"],
  "scaffolding": ["سقال", "شدات", "قوالب صب"],
  "security_systems": ["كاميرات مراقبة", "أنظمة مراقبة", "أنظمة أمن", "تحكم بالدخول", "إنذار سرقة", "حراسة أمنية", "خدمات حراسة", "بوابات دوارة"],
  "signage": ["لافتات", "لافتة", "يافطات", "يافطة", "لوحات إعلان", "لوحات إرشاد", "حروف بارزة", "حروف أكريليك"],
  "solar": ["طاقة شمسية", "ألواح شمسية", "ألواح طاقة شمسية", "خلايا شمسية", "سخانات شمسية", "سخان شمسي", "كهروضوئي"],
  "steel": ["حديد", "فولاذ", "ستانلس", "ستانليس", "استانلس", "ستيل", "تشكيل معادن", "هياكل معدنية", "لحام", "درابزين", "حداد"],
  "upholstery": ["تنجيد", "منجد", "ستائر", "ستارة", "برادي", "مفروشات", "كنب"],
  "wallpaper": ["ورق جدران", "ورق حائط", "تكسية جدران", "تكسيات جدران"],
  "waterproofing": ["عزل", "عازل", "عوازل", "ممبرين"]
}
$aliases$::jsonb;
  v_bad text;
begin
  -- exact codes: every key is an active code, and every active code has Arabic aliases
  select string_agg(k, ', ') into v_bad from jsonb_object_keys(v_ar) k
   where not exists (select 1 from public.taxonomy_trade t where t.code = k and t.active);
  if v_bad is not null then raise exception 'Arabic aliases for codes that are not active trades: %', v_bad; end if;
  select string_agg(t.code, ', ') into v_bad from public.taxonomy_trade t where t.active and not v_ar ? t.code;
  if v_bad is not null then raise exception 'active trades with no Arabic alias: %', v_bad; end if;

  -- alias hygiene: plain Arabic words, no article, at least 3 letters, one code per alias
  select string_agg(a, ', ') into v_bad
    from jsonb_each(v_ar) e, jsonb_array_elements_text(e.value) a
   where public.fn_ar_norm(a) !~ '^[ء-ي]+( [ء-ي]+)*$'
      or length(public.fn_ar_norm(a)) < 3
      or exists (select 1 from regexp_split_to_table(a, ' ') w where w like 'ال%');
  if v_bad is not null then raise exception 'Arabic aliases that are not plain article-free words: %', v_bad; end if;
  select string_agg(n, ', ') into v_bad from (
    select public.fn_ar_norm(a) n from jsonb_each(v_ar) e, jsonb_array_elements_text(e.value) a
     group by 1 having count(distinct e.key) > 1) d;
  if v_bad is not null then raise exception 'Arabic aliases naming two codes: %', v_bad; end if;

  update public.taxonomy_trade t
     set aliases = t.aliases || array(
           select a from jsonb_array_elements_text(v_ar -> t.code) with ordinality x(a, o)
            where not a = any(t.aliases) order by o)
   where v_ar ? t.code
     and exists (select 1 from jsonb_array_elements_text(v_ar -> t.code) a where not a = any(t.aliases));
end
$do$;

create or replace function public.fn_norm_trades(p_text text)
returns text[]
language sql
stable
set search_path to 'public', 'pg_temp'
as $fn$
  -- SLUG SEPARATORS ARE WORD SEPARATORS (12 Aug 2026): the INPUT's '-', '_', '/', '.' runs become one
  -- space, so 'building-materials' reaches the alias 'building materials'.
  -- ARABIC (15 Sep 2026): the input and every alias are folded by fn_ar_norm first, and an Arabic
  -- alias may carry ال / و ف ب ل ك / لل before its first word and ال before each later word. '\m'
  -- treats Arabic letters as word characters on this database, so the word-start rule is unchanged.
  -- The TS twin is supabase/functions/_shared/trade_words.ts; the two patterns are kept identical.
  select coalesce(array_agg(distinct t.code order by t.code), '{}')
  from public.taxonomy_trade t
  cross join (select regexp_replace(public.fn_ar_norm(coalesce(p_text, '')), '[-_/.]+', ' ', 'g') as s) x
  where t.active
    and exists (
      select 1
      from unnest(t.aliases || t.code) a
      cross join lateral (select public.fn_ar_norm(a) as na) n
      where length(n.na) >= 3
        and x.s ~* ('\m' || case
              when n.na ~ '^[ء-ي]'
                then '(?:[وفبلك]?ال|[وف]?لل|[وفبلك])?'
                     || replace(regexp_replace(n.na, '([.*+?^${}()|\[\]\\])', '\\\1', 'g'), ' ', ' (?:ال)?')
              else regexp_replace(n.na, '([.*+?^${}()|\[\]\\])', '\\\1', 'g')
            end)
    );
$fn$;

comment on function public.fn_norm_trades(text) is
  'Trade codes a text names: an alias (or the code) of an active taxonomy_trade at a word start, English or Arabic (fn_ar_norm-folded; an Arabic alias may carry the article and attached letters). Exact or none. TS twin: supabase/functions/_shared/trade_words.ts.';

revoke execute on function public.fn_norm_trades(text) from public, anon, authenticated;
grant execute on function public.fn_norm_trades(text) to service_role;

-- SELF-TEST. Asserts only — it writes nothing. A failure raises and the whole file rolls back, which is
-- what should happen: the aliases and the function stand or fall together.
do $t$
declare
  r record;
begin
  for r in select * from (values
    ('أعمال النجارة والديكور',               '{interior_fitout,joinery}'::text[]),
    ('نقوم بتوريد وتركيب الألمنيوم والزجاج',  '{aluminium,glazing}'),
    ('لمكافحة الحريق',                        '{fire_fighting}'),
    ('نِجـــارَة',                             '{joinery}'),
    ('١٠ مولدات ديزل',                        '{power_generators}'),
    ('We supply building-materials',          '{building_materials}'),
    ('Prehvac is not a word here',            '{}'),
    ('تجديد الرخصة التجارية وتحديد المواعيد', '{}'),
    ('خزانات المياه',                         '{}')
  ) v(txt, want) loop
    if public.fn_norm_trades(r.txt) is distinct from r.want then
      raise exception 'fn_norm_trades(%) = %, expected %', r.txt, public.fn_norm_trades(r.txt), r.want;
    end if;
  end loop;
  raise notice 'fn_norm_trades: Arabic and English self-test passed';
end
$t$;
