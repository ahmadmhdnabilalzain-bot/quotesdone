-- customer_support, 12 Oct 2026. Found while measuring the widget (sandbox run f4294be8, S13 follow-up).
--
-- WHAT WAS WRONG. Nine approved, PUBLIC Arabic FAQ rows (the mirrors of English rows 9, 28, 32, 89, 143, 153, 160,
-- 167, 169) still told a buyer that "رسوم معالجة البطاقة" (a card processing fee) is added to the 3% reveal fee.
-- No buyer has paid a card fee since 24 Sep 2026 (Cabinet Res. 66/2023 Art. 5(3); ledger 1087). The English rows were
-- corrected on 14 Sep; the Arabic mirrors were not. fn_support_corpus_search returns row 610 first for
-- "كم رسوم كشف بيانات المورد؟", and on 12 Oct the live widget answered that question with "تُضاف رسوم معالجة البطاقة".
-- Three of the rows (616, 681, 707) also still gave the old non-response charge (AED 250, 9%), not v14's.
-- scripts/legal/sync_company_facts.mjs --probe did not see them: its card-fee wordings are English only.
--
-- WHAT THIS DOES. Each Arabic row is rewritten to say what its English source says today, guarded by the md5 of the
-- row as read on 12 Oct (a row edited since is left alone), and its embedding is cleared so it is re-embedded.
-- English row 89 said two sentences twice; the repeat is removed (same md5 guard).
-- It ends with a probe that raises if any public approved Arabic row still adds a card fee.

update public.company_faq set answer = 'The 3% fee is the customer reveal fee: 3% of the value of the quote you choose, with no cap. A customer pays it once to unlock the identity and contact details of their chosen supplier. It is the platform''s main charge and it is paid by the customer — suppliers pay no commission. Nothing is added for paying by card, and the amount is shown in full before payment. No VAT is charged on the reveal fee.', embedding_gte = null, updated_at = now()
 where id = 89 and md5(answer) = '867030a14d33cc10b632d3842615a587';

update public.company_faq set answer = 'رسوم الـ 3٪ هي رسوم الاطلاع التي يدفعها العميل: 3٪ من قيمة عرض السعر الذي تختاره، دون حد أقصى. يدفعها العميل مرة واحدة لكشف هوية المورد الذي اختاره وبيانات التواصل معه. وهي الرسوم الأساسية للمنصة ويتحملها العميل، والموردون لا يدفعون أي عمولة. لا يُضاف أي مبلغ عند الدفع بالبطاقة، ويظهر المبلغ كاملًا قبل الدفع. لا تُفرض ضريبة القيمة المضافة على رسوم الاطلاع.', embedding_gte = null, updated_at = now()
 where id = 610 and md5(answer) = '18663b42cb3e68b2cd853d1e654e8327';

update public.company_faq set answer = 'تُعاد المبالغ إلى وسيلة الدفع الأصلية للعميل عبر Stripe، ويقرر كل استرداد شخص لدينا ولا شيء منها آلي. يبدأ التسلسل من تاريخ دفع العميل: إذا لم يرد المورد المكشوف عنه بحلول يوم العمل الثالث، يتابعه مدير نجاح العملاء لدينا مع نسخة إلى العميل؛ وإذا بقي صامتًا في يوم العمل الخامس يُرفع الأمر إلينا للقرار النهائي؛ وإذا لم يرد على ذلك يُردّ إلى العميل كل ما دفعه (رسوم الاطلاع البالغة 3٪)، وتستغرق البنوك من 7 إلى 14 يوم عمل لإظهارها. ويصبح المورد غير المستجيب مدينًا بالمبلغ المردود بالضبط، ورسوم معالج الدفع التي لم تستردها QuotesDone (ابتداءً من اتفاقية المورد الإصدار 14)، إضافة إلى رسوم إدارية قدرها 500 درهم وفائدة بسيطة قدرها 12٪ سنويًا من تاريخ الاستحقاق (وهي النسبة المتفق عليها في اتفاقية المورد الإصدار 14؛ و9٪ في الإصدار 13 أو ما قبله)، إلا حيث لا يجيز القانون الإماراتي فرض ذلك، ويُوقف عن المطابقات الجديدة حتى السداد. أيام العمل هي من الاثنين إلى الجمعة باستثناء العطل الرسمية في الدولة. وتُراجع طلبات الاسترداد الأخرى المقدمة خلال مهلة أيام العمل الخمسة وتُسترد بالطريقة نفسها إن كانت صحيحة.', embedding_gte = null, updated_at = now()
 where id = 616 and md5(answer) = '810b5bb671e19e4e5a9f100cacc9a309';

update public.company_faq set answer = 'أربعة فوارق: (1) السرّية — لا يتبادل المشترون والموردون بيانات التواصل حتى يختار المشتري ويسدّد رسوم الاطلاع، فلا رسائل مزعجة ولا التفاف على المنصة. (2) مطابقة دقيقة عبر المحرّك الذكي — يقرأ المحرّك تفاصيل العمل فعليًا ويوجّهه إلى الموردين القادرين عليه وحدهم، بدل إرسال كل طلب إلى الجميع. (3) عروض أسعار منظَّمة وقابلة للمقارنة ومراجَعة الجودة، لا نصوصًا حرّة مبعثرة. (4) اقتصاديات منصفة للمورّد — لا عمولة على الأعمال المكتسبة والبداية مجانية؛ ولا يدفع المشتري إلا على العرض الذي يختاره فعلًا: رسوم اطلاع 3٪.', embedding_gte = null, updated_at = now()
 where id = 662 and md5(answer) = '9ffd89d66a3d64f0c4e96cde3a832405';

update public.company_faq set answer = 'يسجّل العملاء بالتحقق من رقم الهاتف والبريد الإلكتروني ويقبلون الشروط والأحكام. ونشر الطلبات وتلقّي عروض الأسعار ومقارنتها مجاني؛ ولا يدفع العميل سوى رسوم الاطلاع 3٪ على العرض الذي يختار فتحه. ويبقى العملاء مجهولين لدى الموردين حتى لحظة الاطلاع.', embedding_gte = null, updated_at = now()
 where id = 680 and md5(answer) = 'c5ef440846b058567e869c839bfed904';

update public.company_faq set answer = 'لا تتقاضى QuotesDone أي عمولة من الموردين على الأعمال المكتسبة — إذ يحتفظ المورّد بـ100٪ من قيمة العمل. والمبالغ الوحيدة المحصَّلة من الموردين هي الاشتراك السنوي (1,000 درهم إماراتي سنويًا، ولا يسري إطلاقًا على أول 1,000 مورّد سجّلوا، ويطبَّق ابتداءً من التسجيل رقم 1,001 من دون تاريخ بدء محدَّد)، ورسوم عدم الاستجابة (وهي المبلغ المسترد للعميل بالضبط، أي رسوم الاطلاع 3٪، ورسوم معالج الدفع التي لم تستردها QuotesDone (ابتداءً من اتفاقية المورد الإصدار 14)، زائد رسوم إدارية قدرها 500 درهم إماراتي وفائدة 12٪ سنويًا من تاريخ الاستحقاق) إذا تجاهل المورّد عميلًا سدّد رسوم الاطلاع عليه، وتُطبَّق إلا حيث لا يجيزها القانون الإماراتي. أما العميل فيدفع بصورة منفصلة رسوم اطلاع 3٪، وذلك فقط عند اختياره الاطلاع على بيانات تواصل المورّد.', embedding_gte = null, updated_at = now()
 where id = 681 and md5(answer) = '642ad83eecf59eda3452944f326cc3c1';

update public.company_faq set answer = 'تسدّدون رسوم الاطلاع البالغة 3٪، فتنكشف لكم هوية ذلك المورّد وبيانات التواصل معه. وتُنشأ معاملة، ويُخطَر المورّد ليردّ عليكم، وتواصلون العمل معه عبر المنصة.', embedding_gte = null, updated_at = now()
 where id = 686 and md5(answer) = '7fada16e64132f98e9a5986fd7c1a03e';

update public.company_faq set answer = 'تمر المدفوعات عبر Stripe، وهي تغطي المسارين الماليين: دفعة الاطلاع من العميل (رسوم الاطلاع 3٪ لكشف بيانات التواصل مع المورّد) والاشتراك السنوي للمورّد (1,000 درهم إماراتي سنويًا). وتُطابَق إشعارات Stripe بحيث لا يُمنح الوصول إلا بعد تأكيد الدفع. ولا تتوفر بوابات أخرى في الوقت الحالي.', embedding_gte = null, updated_at = now()
 where id = 701 and md5(answer) = '4bff03d06a14fd2f3cbebd700a65716c';

update public.company_faq set answer = 'إذا لم يردّ المورّد الذي اطّلعتم على بياناته خلال 5 أيام عمل من سدادكم (نتابعه بعد 3 أيام عمل، ونتخذ القرار النهائي في اليوم الخامس)، يُردّ إليكم كل ما دفعتموه. ويصبح ذلك المورّد مدينًا بالمبلغ المردود نفسه (رسوم الاطلاع 3٪)، ورسوم معالج الدفع التي لم تستردها QuotesDone (ابتداءً من اتفاقية المورد الإصدار 14)، ورسوم إدارية قدرها 500 درهم إماراتي، وفائدة بسيطة بنسبة 12٪ سنويًا (أو الحد الأقصى المسموح به قانونًا) من تاريخ الاستحقاق، ويُحجب عن المطابقات الجديدة حتى السداد.', embedding_gte = null, updated_at = now()
 where id = 707 and md5(answer) = '983fadbac466a124d1edc9c2bfb2ea72';

update public.company_faq set answer = 'تمرّ المدفوعات عبر Stripe. إذا فشل سداد العميل لرسوم الاطلاع (3٪ لكشف بيانات التواصل مع المورّد)، فلا تُكشف البيانات ويمكن إعادة المحاولة — دون أي خصم ودون كشف أي هوية. وإذا فشل سداد الاشتراك السنوي للمورّد (1,000 درهم إماراتي سنويًا)، لا يُفعَّل تسجيله أو ينتهي سريانه، فتتوقف المطابقات الجديدة حتى السداد. والدفع الفاشل لا يمنح صلاحية وصول بصمت أبدًا؛ وتُطابَق أحداث Stripe مع السجلات لتبقى دقيقة.', embedding_gte = null, updated_at = now()
 where id = 721 and md5(answer) = 'aed770a39cbdaceb0ac5ea1e35487f5e';

do $$
declare n int;
begin
  select count(*) into n from public.company_faq
   where language = 'ar' and public and status = 'approved' and answer like '%معالجة البطاقة%';
  if n > 0 then raise exception 'PROBE FAILED: % public Arabic FAQ row(s) still add a card processing fee', n; end if;
end $$;
