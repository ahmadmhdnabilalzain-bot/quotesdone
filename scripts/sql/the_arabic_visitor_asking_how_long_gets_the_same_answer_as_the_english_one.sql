-- THE ARABIC VISITOR ASKING "HOW LONG" GETS THE SAME ANSWER AS THE ENGLISH ONE.
--
-- SEAT: customer_support (the public website widget). Data only — no routine, no table.
--
-- MEASURED 21 Sep 2026 on production, from the customer-portal audit (finding 13): the public
-- widget answered an Arabic timeline question with a price guide, and "لكل each" leaked into the
-- sentence. site_assistant now routes count / cost / timeline questions by lexemes straight to the
-- approved FAQ whose QUESTION is that question, in the asker's language. The 172 public approved
-- FAQs hold an Arabic row for the count question (604 "كم عدد الموردين الذين يستلمون طلبي؟") and for
-- the cost question (609 "ما هي رسوم المنصة؟"), and NO Arabic row for the timeline question — the
-- only Arabic "كم يستغرق" row (619) is about supplier verification, which is a different question.
-- Routed to nothing, the Arabic asker would get the honest "I do not have that yet" while the
-- English asker gets FAQ 26. That is Arabic served second, which the founder has ruled out.
--
-- CHANGES: one approved, public, Arabic FAQ row, the same content as FAQ 26 ("How long does the
-- process take?"), inserted only if no approved Arabic row already asks it.
-- NOT CHANGED: FAQ 26 itself, every other row, and the routing code (site_assistant/index.ts).

insert into public.company_faq
  (section, sort, question, answer, audience, status, public, language, source_note, tags, approved_at, approved_by)
select
  'Arabic', 903,
  'كم يستغرق الحصول على عروض الأسعار؟',
  'يعتمد ذلك على طبيعة العمل، لكن من الواقعي أن تصلك عروض الأسعار خلال 3 إلى 5 أيام عمل، ويتم إشعارك '
  || 'عند وصول كل عرض. وبعد أن تكشف عن مورّد، يكون أمامه 5 أيام عمل من تاريخ دفعك للرد: نتابعه نيابة عنك '
  || 'بعد 3 أيام عمل، ونتخذ القرار النهائي في اليوم الخامس، وإذا بقي صامتاً يُردّ إليك كل ما دفعته '
  || '(تستغرق البنوك من 7 إلى 14 يوم عمل لإظهار المبلغ).',
  'customer', 'approved', true, 'ar',
  'Arabic twin of FAQ 26 (How long does the process take?), added 21 Sep 2026 so the widget''s '
  || 'timeline route answers Arabic askers from an Arabic row instead of refusing.',
  array['timeline','quotes','customer','arabic'],
  now(), 'customer_support'
where not exists (
  select 1 from public.company_faq
   where status = 'approved' and language = 'ar'
     and question = 'كم يستغرق الحصول على عروض الأسعار؟');

-- The verdict as a ROW: the Arabic row exists, approved and public, exactly once.
select case when (select count(*) from public.company_faq
                   where status = 'approved' and public and language = 'ar'
                     and question = 'كم يستغرق الحصول على عروض الأسعار؟') = 1
            then 'PROBE OK — one approved public Arabic timeline FAQ'
            else 'PROBE FAILED — the Arabic timeline FAQ is missing or duplicated' end as probe_verdict;
