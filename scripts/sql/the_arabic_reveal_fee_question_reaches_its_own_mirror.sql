-- customer_support, 12 Oct 2026. Data fix found by scripts/checks/arabic_reaches_the_same_answer_as_english.test.mjs.
--
-- WHAT WAS WRONG. "what is the 3% reveal fee" reaches English FAQ 89; its Arabic pair "ما هي رسوم الكشف؟" reached
-- FAQ 609 (the mirror of FAQ 30, the general platform-fees answer) instead of 610 (the mirror of 89). 610's question
-- read "ما هي رسوم الـ 3٪؟" and never names the fee as the asker does ("رسوم الكشف"), so 609 outranked it. And 609
-- itself had drifted from its source: FAQ 30 says the fee is shown in full before payment and carries no VAT; 609 did
-- not say either. Both rows now say what the signed terms say: a 3% reveal fee, no cap, shown in full before
-- payment, no card fee, no VAT on the reveal fee.
--
-- MEASURED BEFORE WRITING (aborted transaction, 12 Oct 2026): with 610's question renamed, fn_support_corpus_search
-- ranks faq:610 at 1.779 above faq:609 at 1.471 for "ما هي رسوم الكشف؟" (before: faq:609 first, 610 absent).
--
-- Guarded by the md5 of each row as read on 12 Oct: a row edited since is left alone. Embeddings are cleared so the
-- rows are re-embedded. Ends with a verdict row (a raise would roll the update back).
update public.company_faq
   set question = 'ما هي رسوم الكشف البالغة 3٪؟', embedding_gte = null, updated_at = now()
 where id = 610 and md5(question) = '139b712435ce6165d4efb5a1c7cade10';

update public.company_faq
   set answer = 'بصفتك عميلًا تدفع رسمًا واحدًا فقط: رسوم كشف بنسبة 3٪ من قيمة عرض السعر الذي تختاره، دون حد أقصى، وعلى ذلك العرض المختار وحده. يظهر المبلغ كاملًا قبل الدفع، ولا يُضاف أي مبلغ عند الدفع بالبطاقة، ولا تُفرض ضريبة القيمة المضافة على رسوم الكشف. لا توجد أي رسوم أخرى عليك. والموردون لا يدفعون أي عمولة على الأعمال التي يفوزون بها.',
       embedding_gte = null, updated_at = now()
 where id = 609 and md5(answer) = 'f3d27a9ca9aa40c70674003674748cf3';

select case
  when (select question from public.company_faq where id = 610) <> 'ما هي رسوم الكشف البالغة 3٪؟' then 'PROBE FAILED: 610 question not updated (edited since 12 Oct?)'
  when (select answer from public.company_faq where id = 609) !~ 'ضريبة القيمة المضافة' then 'PROBE FAILED: 609 answer not updated (edited since 12 Oct?)'
  when (select s.src || ':' || s.src_id from public.fn_support_corpus_search('ما هي رسوم الكشف؟', true, 1) s limit 1) <> 'faq:610'
    then 'PROBE FAILED: the Arabic reveal-fee question does not reach faq:610'
  else 'PROBE OK'
end as verdict;
