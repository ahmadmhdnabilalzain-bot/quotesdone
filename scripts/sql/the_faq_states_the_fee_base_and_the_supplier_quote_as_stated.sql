-- THE FAQ STATES THE FEE BASE AND THE SUPPLIER'S QUOTE AS STATED — founder rulings 1207 and 1208, 13 Oct 2026.
-- Seat: sales_engineer (the quotation and its wording); the fee basis is the accountant's.
--
-- WHAT WAS WRONG. Six approved public FAQ rows (English 29, 30, 89 and their Arabic mirrors 608, 609, 610) said the
-- reveal fee is "3% of the value of the quote you choose". Ruling 1208: it is 3% of the supplier's FINAL quoted price
-- BEFORE VAT, after any discount the supplier states (2,000 → after discount 1,700, + VAT → fee 3% × 1,700 = 51).
-- Ruling 1207: the supplier's quotation is shown exactly as stated (its discount, its VAT) and QuotesDone is not
-- responsible for the supplier's quotation details; "no card fee / no VAT" applies to OUR fee only. These rows are
-- what the company brief and the support corpus answer from, so they must say the same as the documents (#1364).
--
-- Each row is rewritten guarded by the md5 of its answer as read on 13 Oct 2026 (a row edited since is left alone),
-- and its embedding is cleared so it is re-embedded. Rows 91/613/673 (QuotesDone's own VAT status) and 665/725
-- (supplier registration documents) already say what is true and are not touched.

update public.company_faq set answer = 'You pay the reveal fee in one payment, securely by card or Apple Pay through our checkout. The fee is 3% of the final price the supplier quotes before VAT, after any discount the supplier states. It is shown in full before you pay, no card fee and no VAT are added to it, and nothing is charged until you choose to reveal a supplier.', embedding_gte = null, updated_at = now()
 where id = 29 and md5(answer) = '3f32239ce343e37696309d8e845f9f35';

update public.company_faq set answer = 'As a customer you pay only when you reveal a supplier: a 3% reveal fee on the final price of the quote you choose, before VAT and after any discount the supplier states (no cap). For example, a quote of AED 2,000, after discount AED 1,700 plus VAT, has a fee of 3% of 1,700 = AED 51. The fee is shown in full before you pay; no card fee and no VAT are charged on it. Each quote is shown exactly as the supplier stated it, including its discount and its VAT, and QuotesDone is not responsible for the supplier''s quotation details. There are no other charges to you. Suppliers pay no commission on won jobs.', embedding_gte = null, updated_at = now()
 where id = 30 and md5(answer) = '7895011b43a2ce9e02c159135258ab54';

update public.company_faq set answer = 'The 3% fee is the customer reveal fee: 3% of the final price of the quote you choose, before VAT and after any discount the supplier states, with no cap (a quote of AED 2,000, after discount AED 1,700 plus VAT, has a fee of AED 51). A customer pays it once to unlock the identity and contact details of their chosen supplier. It is the platform''s main charge and it is paid by the customer — suppliers pay no commission. Nothing is added for paying by card, and the amount is shown in full before payment. No VAT is charged on the reveal fee; the supplier''s own VAT is shown exactly as the supplier stated it.', embedding_gte = null, updated_at = now()
 where id = 89 and md5(answer) = 'e41c2714fc42e5f9c253802342712c91';

update public.company_faq set answer = 'تدفع رسوم الكشف في دفعة واحدة، بأمان بالبطاقة المصرفية أو عبر Apple Pay من خلال صفحة الدفع لدينا. وتبلغ الرسوم 3٪ من السعر النهائي الذي يذكره المورّد قبل ضريبة القيمة المضافة، وبعد أي خصم يذكره. ويظهر لك المبلغ كاملًا قبل الدفع، ولا تُضاف إليه رسوم بطاقة ولا ضريبة قيمة مضافة، ولا يُحصَّل شيء إلا عندما تختار الكشف عن مورد.', embedding_gte = null, updated_at = now()
 where id = 608 and md5(answer) = '94f88a1f176ecf30ad31126a67d9bfdc';

update public.company_faq set answer = 'بصفتك عميلًا تدفع رسمًا واحدًا فقط عند الكشف عن مورد: رسوم كشف بنسبة 3٪ من السعر النهائي للعرض الذي تختاره، قبل ضريبة القيمة المضافة وبعد أي خصم يذكره المورّد، دون حد أقصى. فالعرض البالغ 2,000 درهم، وبعد الخصم 1,700 درهم مع الضريبة، تكون رسومه 3٪ من 1,700 أي 51 درهمًا. ويظهر المبلغ كاملًا قبل الدفع، ولا تُضاف إليه رسوم بطاقة ولا ضريبة قيمة مضافة. ونعرض كل عرض كما ذكره المورّد تمامًا، بما فيه الخصم وضريبة القيمة المضافة، ولا تتحمّل QuotesDone أي مسؤولية عن تفاصيل عرض المورّد. لا توجد أي رسوم أخرى عليك، والموردون لا يدفعون أي عمولة على الأعمال التي يفوزون بها.', embedding_gte = null, updated_at = now()
 where id = 609 and md5(answer) = '3552e11c37171df93061de794d302463';

update public.company_faq set answer = 'رسوم الـ 3٪ هي رسوم الكشف التي يدفعها العميل: 3٪ من السعر النهائي للعرض الذي تختاره، قبل ضريبة القيمة المضافة وبعد أي خصم يذكره المورّد، دون حد أقصى (فالعرض البالغ 2,000 درهم، وبعد الخصم 1,700 درهم مع الضريبة، رسومه 51 درهمًا). يدفعها العميل مرة واحدة لكشف هوية المورد الذي اختاره وبيانات التواصل معه. وهي الرسوم الأساسية للمنصة ويتحملها العميل، والموردون لا يدفعون أي عمولة. لا يُضاف أي مبلغ عند الدفع بالبطاقة، ويظهر المبلغ كاملًا قبل الدفع. لا تُفرض ضريبة القيمة المضافة على رسوم الكشف، أما ضريبة المورّد نفسه فتظهر كما ذكرها تمامًا.', embedding_gte = null, updated_at = now()
 where id = 610 and md5(answer) = '7eb032be1f1481bcf27e4bbab5b005eb';

-- The verdict: no approved public row still takes the fee on "the value of the quote", in either language.
select case when exists (
  select 1 from public.company_faq
   where public and status = 'approved'
     and (answer ~* '3% (?:reveal fee )?(?:on|of) the value of the quote' or answer like '%3٪ من قيمة عرض السعر%' or answer like '%3٪ من عرض السعر الذي تختاره%'))
  then 'PROBE FAILED: a public FAQ row still takes the 3% on the quote value (ruling 1208)'
  when exists (select 1 from public.company_faq where id in (609, 610) and position('رسوم الاطلاع' in answer) > 0)
  then 'PROBE FAILED: FAQ 609 or 610 still names the reveal fee رسوم الاطلاع' else 'PROBE OK' end as verdict;
