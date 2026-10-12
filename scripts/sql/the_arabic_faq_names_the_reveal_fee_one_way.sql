-- customer_support, 12 Oct 2026 (coordinator, follow-up to #1339). Data only.
--
-- ONE ARABIC TERM FOR THE REVEAL FEE. FAQ 609 (mirror of FAQ 30) says "رسوم الكشف"; FAQ 610 (mirror of FAQ 89) still
-- said "رسوم الاطلاع" twice. 610 now says "رسوم الكشف" throughout, with the same facts as FAQ 89 and the signed terms:
-- 3% of the chosen quote, no cap, paid once by the customer, shown in full before payment, no card fee, no VAT on the fee.
--
-- MEASURED BEFORE WRITING (aborted transaction on production, 12 Oct 2026, together with #1339's changes): the Arabic
-- reveal-fee question "ما هي رسوم الكشف؟" still reaches faq:610 first (1.842) above faq:609 (1.568).
--
-- md5-guarded on 610's answer as read on 12 Oct (a row edited since is left alone); the embedding is cleared so the row
-- is re-embedded. Ends with a verdict row (a raise would roll the update back).
update public.company_faq
   set answer = 'رسوم الكشف هي 3٪ من قيمة عرض السعر الذي تختاره، دون حد أقصى. يدفعها العميل مرة واحدة لكشف هوية المورد الذي اختاره وبيانات التواصل معه. وهي الرسوم الأساسية للمنصة ويتحملها العميل، والموردون لا يدفعون أي عمولة. لا يُضاف أي مبلغ عند الدفع بالبطاقة، ويظهر المبلغ كاملًا قبل الدفع. لا تُفرض ضريبة القيمة المضافة على رسوم الكشف.',
       embedding_gte = null, updated_at = now()
 where id = 610 and md5(answer) = '7eb032be1f1481bcf27e4bbab5b005eb';

select case
  when (select count(*) from public.company_faq where id in (609, 610) and answer ~ 'رسوم الاطلاع') > 0
    then 'PROBE FAILED: a reveal-fee row still says رسوم الاطلاع (610 edited since 12 Oct?)'
  when (select answer from public.company_faq where id = 610) !~ 'رسوم الكشف' then 'PROBE FAILED: 610 does not say رسوم الكشف'
  else 'PROBE OK'
end as verdict;
