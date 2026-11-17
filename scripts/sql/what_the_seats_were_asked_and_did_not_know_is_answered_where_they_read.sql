-- WHAT THE SEATS WERE ASKED AND DID NOT KNOW IS ANSWERED WHERE THEY READ (17 Nov 2026).
-- Seat: sales_engineer (the knowledge gap ledger's knowledge owner; the FAQ rows are company knowledge every seat reads).
-- Founder ledger 889, 893, 894, 899, 1003, 1013, 1209, 1609: every seat's knowledge to professional standard, and every
-- question a seat could not answer closed with an entry (customer_support_closes_every_knowledge_request_by_a_deadline.sql).
--
-- MEASURED (production, read-only SELECTs, 17 Nov 2026): public.sales_knowledge_gap holds 130 rows: 107 not_a_gap,
-- 10 knowledge_added, 13 open. The 13 open, ranked by what they cost a real person:
--   #781-784  a REAL supplier on WhatsApp (wa_messages 1731-1734, 7 Nov) registering a second company (a Sharjah free-zone
--             FZE) under the e-mail and mobile his first company uses. The reply had to say "our published rules don't say"
--             and send him to management: the rule exists (one e-mail manages one company: leads_claimed_by_lower_uidx,
--             email_triage/account_facts.ts SEPARATE_COMPANY_FACT; a WhatsApp number two companies confirmed opens job requests
--             for neither: fn_supplier_job_request_whatsapp) but no corpus the WhatsApp seat reads stated it. A supplier blocked
--             at registration, so first.
--   #770-775  the 1 Nov live seat conversations (run 35568a84) recorded what the interview never asked in six trades. The
--             knowledge belongs in the trades' verified packs, which this file does not write: knowledge/packs/{security_systems,
--             gypsum,flooring,fire_fighting,joinery,facilities_management}.json carry it on this branch, and
--             scripts/kb/load_trade_spec_checklists.mjs loads them into public.trade_spec_checklist, the table the interview
--             reads (_shared/inquiry_trades.ts tradeContext). Gypsum is the only trade with live inquiries in 60 days (2).
--   #195/#237 "I am not sure, what do you recommend?" (45 asks, widget) and its Gulf Arabic twin (34 asks, portal). The
--             answer is the expert-advice rule of 10 Nov (_shared/solution_catalogue.ts ADVISE_RULE, ledger 1572), which no
--             FAQ said; FAQ #66 and its mirror #691 still said "it will not push technical choices on you", against that rule.
--   #861      "كيف تعمل المنصة؟" (14 asks). FAQ #602 answers it but never says "المنصة", so the strict Arabic search missed it.
--
-- THIS FILE (data only; no routine, no table):
--   1. four approved public company_faq rows: a second company (EN, AR) and "not sure what I need" (EN, AR);
--   2. the answers of #66 and #691 follow the 10 Nov advice rule; #602 names the platform (question, its unique key, unchanged);
--   3. each gap is closed 'knowledge_added' (the convention of scripts/e2e/knowledge_gap_audit.mjs close: closed_at, and
--      source_ref gains 'ingest <this file>') ONLY when its evidence is live: an FAQ gap when the public search the widget
--      calls (fn_support_corpus_search(q, true, 3)) returns the answering row first; a trade gap when its trade's checklist
--      row in trade_spec_checklist carries the new spec or guide words.
--   4. a verdict row: PROBE OK, or PROBE FAILED naming every gap left open and why.
-- APPLY ORDER: node scripts/kb/load_trade_spec_checklists.mjs knowledge/packs --apply  (after this branch is merged),
--   then this file. Applied before the loader, the six trade gaps stay open and the verdict says so; re-applying is safe.
-- The FTS ranking of every gap question against these rows was measured on 17 Nov with built-in text search over the live
-- approved public FAQ (a SELECT; no routine called): each gap's first hit is its answering row.
-- DOES NOT: write the trade packs' sales_knowledge rows (scripts/kb/load_verified_packs.mjs, embeddings); embed the new FAQ
-- rows (company_faq_embed_inflight does that; fn_reason_retrieve reads them once embedded); close the org_tasks behind
-- #195/#237/#861 (fn_org_task_consume_tick closes a knowledge_gap task only from the sales engineer's reasoning or a
-- not_a_gap judgement; the knowledge.request handoffs close on the daily customer_support tick once the gap is not open).
-- Prevented by: the verdict row below (re-run reads the live search and the live checklist rows).

set local lock_timeout = '3s';

-- ── 1. the new rows ──────────────────────────────────────────────────────────────────────────────────────────────────
insert into public.company_faq
  (section, sort, question, answer, audience, status, public, language, source_note, tags, approved_at, approved_by)
values
  ('Supplier', 1000,
   'Can I register a second company with the same email and mobile number?',
   'Each company registers separately, and one email address manages exactly one company. A second company with its own trade licence (a sister company or a subsidiary, including one licensed in a UAE free zone such as a Sharjah free zone) registers as a new company at quotesdone.com/portal with "Create account", using a different work email that has no account with QuotesDone yet. It needs the same six things as every supplier: the licensed company name, a UAE mobile number verified with a code, the verified work email, the trade licence, the company profile and acceptance of the supplier terms.' || E'\n\n' || 'A free-zone licence is a UAE trade licence. It is checked with the free zone that issued it, on the same standard as a mainland licence.' || E'\n\n' || 'Job requests on WhatsApp go only to a number that one company alone has confirmed. If the second company should receive its job requests on WhatsApp, give it its own mobile number; otherwise its requests arrive by email.' || E'\n\n' || 'We cannot register the company for you: only you can verify the email and mobile, upload the documents and accept the terms.',
   'supplier', 'approved', true, 'en',
   'Answers sales_knowledge_gap #781, #782, #783, #784. Facts: one e-mail manages one company (leads_claimed_by_lower_uidx; supplier_api/create_company.ts company_exists; email_triage/account_facts.ts SEPARATE_COMPANY_FACT); the six items (fn_supplier_mandatory_six); a free-zone licence is checked with its zone (knowledge/seats/customer_support.json customer_support:free-zone-licences); a WhatsApp number two companies confirmed opens job requests for neither (fn_supplier_job_request_whatsapp). Written 17 Nov 2026 (what_the_seats_were_asked_and_did_not_know_is_answered_where_they_read.sql).',
   array['registration', 'second company', 'subsidiary', 'sister company', 'email', 'mobile', 'free zone', 'supplier'], now(), 'sales_engineer'),
  ('Arabic', 1040,
   'هل يمكنني تسجيل شركة ثانية بنفس البريد الإلكتروني ورقم الجوال؟',
   'تُسجَّل كل شركة على حدة، ولا يدير البريد الإلكتروني الواحد إلا شركة واحدة. فالشركة الثانية التي لها رخصتها التجارية الخاصة (شركة شقيقة أو تابعة، ومنها الشركة المرخّصة في منطقة حرة إماراتية مثل المناطق الحرة في الشارقة) تُسجَّل شركةً جديدة من quotesdone.com/portal عبر «Create account»، ببريد عمل مختلف ليس له حساب لدى QuotesDone. وتحتاج الأمور الستة نفسها المطلوبة من كل مورّد: اسم الشركة كما في الرخصة، ورقم جوال إماراتي يُتحقَّق منه برمز، وبريد العمل بعد التحقق منه، والرخصة التجارية، والملف التعريفي للشركة، والموافقة على شروط الموردين.' || E'\n\n' || 'رخصة المنطقة الحرة رخصة تجارية إماراتية، ويُتحقَّق منها لدى المنطقة الحرة التي أصدرتها وفق المعيار نفسه المطبَّق على رخص البر الرئيسي.' || E'\n\n' || 'لا تصل طلبات العمل عبر واتساب إلا إلى رقم أكّدته شركة واحدة وحدها. فإن أردتم أن تصل طلبات الشركة الثانية على واتساب فخصّصوا لها رقم جوال خاصًا بها، وإلا وصلتها طلباتها بالبريد الإلكتروني.' || E'\n\n' || 'لا نستطيع تسجيل الشركة نيابةً عنكم، فالتحقق من البريد والجوال ورفع المستندات والموافقة على الشروط خطوات لا يقوم بها غيركم.',
   'supplier', 'approved', true, 'ar',
   'Arabic mirror of the row "Can I register a second company with the same email and mobile number?". Facts as the English row. Written 17 Nov 2026 (what_the_seats_were_asked_and_did_not_know_is_answered_where_they_read.sql).',
   array['registration', 'second company', 'free zone', 'supplier', 'arabic'], now(), 'sales_engineer'),
  ('Customer', 26,
   'I am not sure what I need. What do you recommend?',
   'Tell us the problem rather than the product: what it is, where it is (the emirate, and whether it is a villa, a flat, an office or a shop), its present condition, what it is used for, and anything that limits the choice, such as a wet area, a children''s room, heat, access or a budget. A photo helps.' || E'\n\n' || 'We then set out two or three options that suit your case, each with why it fits and its honest trade-off, and say which one we would choose for your case and why. Once you choose, we ask only the details a supplier needs to price it, such as sizes, finish and timing. Anything you still do not know goes to the suppliers as "supplier to advise", and where a job cannot be priced without seeing it, we tell you that a site visit comes first.' || E'\n\n' || 'We never push a brand or a supplier, and we do not price the work ourselves: the suppliers'' quotations do that, and you compare them before you decide.',
   'customer', 'approved', true, 'en',
   'Answers sales_knowledge_gap #195. The advice rule of 10 Nov 2026 (founder ledger 1572/1586; _shared/solution_catalogue.ts ADVISE_RULE): options with trade-offs, then the details that price it; unknowns go to suppliers as "supplier to advise". Written 17 Nov 2026 (what_the_seats_were_asked_and_did_not_know_is_answered_where_they_read.sql).',
   array['advice', 'options', 'not sure', 'recommend', 'customer'], now(), 'sales_engineer'),
  ('Arabic', 1041,
   'لست متأكدًا مما أحتاجه، فبماذا تنصحونني؟',
   'أخبرونا بالمشكلة لا بالمنتج: ما هي، وأين هي (الإمارة، وهل هي فيلا أو شقة أو مكتب أو محل)، وحالتها الآن، وفيمَ تُستخدم، وأي أمر يحدّ من الاختيار مثل منطقة رطبة أو غرفة أطفال أو الحرارة أو صعوبة الوصول أو الميزانية. وتساعد الصورة كثيرًا.' || E'\n\n' || 'ثم نعرض عليكم خيارين أو ثلاثة تناسب حالتكم، ولكل خيار سبب ملاءمته وعيبه بصراحة، ونقول أيّها نختار لحالتكم ولماذا. وبعد أن تختاروا لا نسألكم إلا عن التفاصيل التي يحتاجها المورّد ليسعّر العمل، مثل المقاسات والتشطيب والموعد. وما لا تعرفونه بعدُ يذهب إلى الموردين على أنه «على المورّد أن ينصح»، وإن كان العمل لا يُسعَّر دون معاينة أخبرناكم أن زيارة الموقع تأتي أولًا.' || E'\n\n' || 'لا نروّج لعلامة تجارية ولا لمورّد، ولا نسعّر العمل بأنفسنا: عروض أسعار الموردين هي التي تفعل ذلك، وتقارنون بينها قبل أن تقرروا.',
   'customer', 'approved', true, 'ar',
   'Answers sales_knowledge_gap #237. Arabic mirror of the row "I am not sure what I need. What do you recommend?". The advice rule as the English row. Written 17 Nov 2026 (what_the_seats_were_asked_and_did_not_know_is_answered_where_they_read.sql).',
   array['advice', 'not sure', 'recommend', 'arabic'], now(), 'sales_engineer')
on conflict (question) do update
  set answer = excluded.answer, public = excluded.public, status = excluded.status, audience = excluded.audience,
      language = excluded.language, source_note = excluded.source_note, tags = excluded.tags, updated_at = now();

-- ── 2. answers that change (each guarded by its question, so a renumbered id changes nothing) ──────────────────────────
update public.company_faq
   set answer = 'Yes, when you are deciding. Describe the problem and it sets out two or three suitable options, each with the honest trade-off, and says which suits your case and why. It never pushes a brand or a supplier, and the supplier still proposes and prices the exact specification: anything you do not know goes to the suppliers as "supplier to advise". It also uses the trade''s checklist and UAE codes so the request captures what matters and flags the approvals the job needs.',
       source_note = coalesce(source_note || ' | ', '') || '17 Nov 2026 (what_the_seats_were_asked_and_did_not_know_is_answered_where_they_read.sql): answer follows the 10 Nov advice rule (founder ledger 1572; ADVISE_RULE); before: "It will not push technical choices on you."', updated_at = now()
 where id = 66 and question = 'Can the Smart Engine recommend specifications?' and answer is distinct from 'Yes, when you are deciding. Describe the problem and it sets out two or three suitable options, each with the honest trade-off, and says which suits your case and why. It never pushes a brand or a supplier, and the supplier still proposes and prices the exact specification: anything you do not know goes to the suppliers as "supplier to advise". It also uses the trade''s checklist and UAE codes so the request captures what matters and flags the approvals the job needs.';

update public.company_faq
   set answer = 'نعم، حين تكونون في مرحلة الاختيار. صِفوا المشكلة فيعرض عليكم خيارين أو ثلاثة مناسبة، لكل منها عيبه بصراحة، ويقول أيّها يناسب حالتكم ولماذا. ولا يروّج لعلامة تجارية ولا لمورّد، ويبقى المورّد هو من يقترح المواصفات الدقيقة ويسعّرها، فما لا تعرفونه يذهب إلى الموردين على أنه «على المورّد أن ينصح». ويستعين كذلك بقائمة متطلبات التخصص وبالأكواد الإماراتية ليضمن أن يشمل الطلب ما يهم، وينبّه إلى الموافقات التي يحتاجها العمل.',
       source_note = coalesce(source_note || ' | ', '') || '17 Nov 2026 (what_the_seats_were_asked_and_did_not_know_is_answered_where_they_read.sql): Arabic mirror of #66, same change.', updated_at = now()
 where id = 691 and question = 'هل يقترح المحرّك الذكي المواصفات؟' and answer is distinct from 'نعم، حين تكونون في مرحلة الاختيار. صِفوا المشكلة فيعرض عليكم خيارين أو ثلاثة مناسبة، لكل منها عيبه بصراحة، ويقول أيّها يناسب حالتكم ولماذا. ولا يروّج لعلامة تجارية ولا لمورّد، ويبقى المورّد هو من يقترح المواصفات الدقيقة ويسعّرها، فما لا تعرفونه يذهب إلى الموردين على أنه «على المورّد أن ينصح». ويستعين كذلك بقائمة متطلبات التخصص وبالأكواد الإماراتية ليضمن أن يشمل الطلب ما يهم، وينبّه إلى الموافقات التي يحتاجها العمل.';

update public.company_faq
   set answer = 'QuotesDone منصة تجمع طلبك بعروض أسعار من موردين في الإمارات، وتعمل المنصة هكذا: تصف ما تحتاجه بالكلمات أو بالصوت أو بصورة أو مخطط. يحوّل المحرك الذكي وصفك إلى طلب واضح ويطابقه مع الموردين القادرين فعلياً على تنفيذ العمل، فيرسلون عروض أسعار دون الكشف عن هويتهم. تقارن العروض، وعندما تختار عرضاً تدفع رسوم كشف بنسبة 3٪ لكشف هوية ذلك المورد وبيانات التواصل معه.',
       source_note = coalesce(source_note || ' | ', '') || '17 Nov 2026 (what_the_seats_were_asked_and_did_not_know_is_answered_where_they_read.sql): answer names the platform ("منصة"), so "كيف تعمل المنصة؟" (sales_knowledge_gap #861) finds it.', updated_at = now()
 where id = 602 and question = 'كيف يعمل QuotesDone؟' and answer is distinct from 'QuotesDone منصة تجمع طلبك بعروض أسعار من موردين في الإمارات، وتعمل المنصة هكذا: تصف ما تحتاجه بالكلمات أو بالصوت أو بصورة أو مخطط. يحوّل المحرك الذكي وصفك إلى طلب واضح ويطابقه مع الموردين القادرين فعلياً على تنفيذ العمل، فيرسلون عروض أسعار دون الكشف عن هويتهم. تقارن العروض، وعندما تختار عرضاً تدفع رسوم كشف بنسبة 3٪ لكشف هوية ذلك المورد وبيانات التواصل معه.';

-- ── 3. close each gap whose evidence is live; 4. the verdict ─────────────────────────────────────────────────────────
-- One statement. An FAQ gap's evidence is the widget's own public search returning the answering row FIRST; a trade
-- gap's is its loaded checklist row. Nothing else closes a row, and a row already closed is left as it is.
with faq_evidence (gap_id, ask, answer_question) as (values
  (781, 'register a separate company under my email and mobile', 'Can I register a second company with the same email and mobile number?'),
  (782, 'can the same email and mobile be used for two companies', 'Can I register a second company with the same email and mobile number?'),
  (783, 'how do I register another company', 'Can I register a second company with the same email and mobile number?'),
  (784, 'is a Sharjah free zone licence accepted', 'Can I register a second company with the same email and mobile number?'),
  (195, 'I am not sure, what do you recommend?', 'I am not sure what I need. What do you recommend?'),
  (237, 'مو متأكد، شو تنصحني؟', 'لست متأكدًا مما أحتاجه، فبماذا تنصحونني؟'),
  (861, 'كيف تعمل المنصة؟', 'كيف يعمل QuotesDone؟')
), faq_live as (
  select e.gap_id, coalesce((select s.title from public.fn_support_corpus_search(e.ask, true, 3) s order by s.rank desc limit 1) = e.answer_question, false) as ok,
         'first public search hit for "' || e.ask || '" is not "' || e.answer_question || '"' as why
    from faq_evidence e
), trade_live as (
  select 770 as gap_id, exists (select 1 from public.trade_spec_checklist c where c.trade_code = 'security_systems' and c.specs @> '[{"code": "spec_building_or_mall_management_rules"}]') as ok, 'trade_spec_checklist has no CCTV: building or mall management rules row for security_systems (run scripts/kb/load_trade_spec_checklists.mjs knowledge/packs --apply first)' as why
  union all
  select 771 as gap_id, exists (select 1 from public.trade_spec_checklist c where c.trade_code = 'gypsum' and c.spec_guide::text like '%Civil Defence registered fire contractor%') as ok, 'trade_spec_checklist has no ceiling: sprinklers, detectors, spotlights and AC grilles row for gypsum (run scripts/kb/load_trade_spec_checklists.mjs knowledge/packs --apply first)' as why
  union all
  select 772 as gap_id, exists (select 1 from public.trade_spec_checklist c where c.trade_code = 'flooring' and c.specs @> '[{"code": "spec_carpet_construction"}]') as ok, 'trade_spec_checklist has no carpet construction, fibre, backing and class row for flooring (run scripts/kb/load_trade_spec_checklists.mjs knowledge/packs --apply first)' as why
  union all
  select 773 as gap_id, exists (select 1 from public.trade_spec_checklist c where c.trade_code = 'facilities_management' and c.specs @> '[{"code": "spec_comprehensive_or_non_comprehensive"}]' and c.specs @> '[{"code": "spec_fire_and_life_safety_systems_in_scope"}]') as ok, 'trade_spec_checklist has no AMC: comprehensive or not; Civil Defence fire maintenance row for facilities_management (run scripts/kb/load_trade_spec_checklists.mjs knowledge/packs --apply first)' as why
  union all
  select 774 as gap_id, exists (select 1 from public.trade_spec_checklist c where c.trade_code = 'fire_fighting' and c.specs @> '[{"code": "spec_special_risk_rooms"}]' and c.specs @> '[{"code": "spec_base_building_panel_to_connect_to"}]') as ok, 'trade_spec_checklist has no fire alarm: server room, base-building panel row for fire_fighting (run scripts/kb/load_trade_spec_checklists.mjs knowledge/packs --apply first)' as why
  union all
  select 775 as gap_id, exists (select 1 from public.trade_spec_checklist c where c.trade_code = 'joinery' and c.spec_guide::text like '%handle-less push-to-open%') as ok, 'trade_spec_checklist has no wardrobe handles when the door type changes row for joinery (run scripts/kb/load_trade_spec_checklists.mjs knowledge/packs --apply first)' as why
), evidence as (select gap_id, ok, why from faq_live union all select gap_id, ok, why from trade_live
), closed as (
  update public.sales_knowledge_gap g
     set status = 'knowledge_added', closed_at = now(),
         source_ref = coalesce(g.source_ref || ' | ', '') || 'ingest scripts/sql/what_the_seats_were_asked_and_did_not_know_is_answered_where_they_read.sql'
            || case when g.id between 770 and 775 then ' + knowledge/packs (load_trade_spec_checklists.mjs)' else '' end
    from evidence e
   where g.id = e.gap_id and e.ok and g.status = 'open'
  returning g.id
), state as (
  select e.gap_id, e.ok, e.why, coalesce(g.status, '(no such gap)') status,
         exists (select 1 from closed c where c.id = e.gap_id) closed_now
    from evidence e left join public.sales_knowledge_gap g on g.id = e.gap_id
)
select case
  when (select count(*) from public.company_faq f where f.status = 'approved' and f.public and f.question in ('Can I register a second company with the same email and mobile number?', 'هل يمكنني تسجيل شركة ثانية بنفس البريد الإلكتروني ورقم الجوال؟', 'I am not sure what I need. What do you recommend?', 'لست متأكدًا مما أحتاجه، فبماذا تنصحونني؟')) <> 4
    then 'PROBE FAILED: the 4 new FAQ rows are not all approved and public'
  when exists (select 1 from state where not ok or (status = 'open' and not closed_now))
    then 'PROBE FAILED: ' || (select string_agg('gap #' || gap_id || ' left ' || status || ': ' || why, '; ' order by gap_id) from state where not ok or (status = 'open' and not closed_now))
  else 'PROBE OK: ' || (select count(*) from state where closed_now) || ' gaps closed now, '
       || (select count(*) from state) || ' answered where the seats read (FAQ search and trade checklists); open gaps left: '
       || (select count(*) from public.sales_knowledge_gap where status = 'open' and id not in (select id from closed))
  end as verdict
  from (select 1) one;
