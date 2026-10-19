-- A SUPPLIER MAY REFRESH A QUOTATION BEFORE REVEAL, AS THE AGREEMENT SAYS (customer_support, 19 Oct 2026).
--
-- SEAT: customer_support. Data only: 4 company_faq rows and 1 agent_knowledge row corrected in place.
-- No routine, no column, no grant. A correction, not a deletion: every row keeps its id, question and
-- approval; only the wrong sentence is replaced. Knowledge is never trimmed.
--
-- THE SOURCE. Supplier Agreement v15 §12, read from production public.legal_documents
-- (slug 'supplier-agreement') on 19 Oct 2026:
--   EN: "A quotation is valid for 30 days from submission unless the Supplier refreshes or withdraws it
--        before Reveal, and the Supplier is bound by a quotation that is revealed within that validity
--        period. The contract for the work itself is solely between the Supplier and the Customer, on
--        terms they agree; QuotesDone is not a party to it ..."
--   AR: "ويكون عرض السعر ساريًا لمدة 30 يومًا من تاريخ تقديمه ما لم يُحدّثه المورّد أو يسحبه قبل الكشف،
--        ويكون المورّد ملزَمًا بعرض السعر الذي يُكشف عنه خلال مدة السريان تلك. أما عقد تنفيذ العمل ذاته
--        فيكون حصريًا بين المورّد والعميل وبالشروط التي يتفقان عليها؛ وQuotesDone ليست طرفًا فيه"
--
-- MEASURED on production 19 Oct 2026, the rows that answered "No — it is final" against §12:
--   company_faq 46 (en, supplier "Can I revise quotations?"), 78 (en, "Can suppliers revise quotations?"),
--   688 (ar, "هل يمكنني تعديل عرض السعر بعد إرساله؟"), 693 (ar, "هل يستطيع الموردون تعديل عروض الأسعار؟"),
--   agent_knowledge 1047 (_global "Company FAQ (canonical answers)", carries both English answers).
-- The new answers are §12's own sentences in the reader's person; nothing is added that §12 does not say.
--
-- RE-EMBED. trg_company_faq_text_change_clears_embedding nulls embedding_gte on the 4 FAQ rows; rebuild
-- them with the free in-region gte-small path (never OpenRouter):
--   node scripts/kb/embed_sales_knowledge.mjs --table=company_faq
-- agent_knowledge 1047 carries no embedding_gte (measured: null); z_ml_vectors_stale marks its ML vector.


update public.company_faq set answer =
  'Yes, before Reveal. Under Supplier Agreement §12, a quotation is valid for 30 days from submission unless you refresh or withdraw it before Reveal, and you are bound by a quotation that is revealed within that validity period. After Reveal, the contract for the work is solely between you and the customer, on terms you agree; QuotesDone is not a party to it.',
  updated_at = now()
 where id = 46 and answer like 'No — once you submit a quotation it is final%';

update public.company_faq set answer =
  'Yes, before Reveal. Under Supplier Agreement §12, a quotation is valid for 30 days from submission unless the supplier refreshes or withdraws it before Reveal, and the supplier is bound by a quotation that is revealed within that validity period. After Reveal, the contract for the work is solely between the supplier and the customer, on terms they agree; QuotesDone is not a party to it.',
  updated_at = now()
 where id = 78 and answer like 'No — once a supplier submits a quotation it is final%';

update public.company_faq set answer =
  'نعم، قبل الكشف. بموجب البند 12 من اتفاقية المورّد، يكون عرض السعر ساريًا لمدة 30 يومًا من تاريخ تقديمه ما لم تُحدّثوه أو تسحبوه قبل الكشف، وتكونون ملزَمين بعرض السعر الذي يُكشف عنه خلال مدة السريان تلك. وبعد الكشف، يكون عقد تنفيذ العمل حصريًا بينكم وبين العميل وبالشروط التي تتفقون عليها، وQuotesDone ليست طرفًا فيه.',
  updated_at = now()
 where id = 688 and answer like 'لا، فعرض السعر نهائي%';

update public.company_faq set answer =
  'نعم، قبل الكشف. بموجب البند 12 من اتفاقية المورّد، يكون عرض السعر ساريًا لمدة 30 يومًا من تاريخ تقديمه ما لم يُحدّثه المورّد أو يسحبه قبل الكشف، ويكون المورّد ملزَمًا بعرض السعر الذي يُكشف عنه خلال مدة السريان تلك. وبعد الكشف، يكون عقد تنفيذ العمل حصريًا بين المورّد والعميل وبالشروط التي يتفقان عليها، وQuotesDone ليست طرفًا فيه.',
  updated_at = now()
 where id = 693 and answer like 'لا، فعرض السعر نهائي%';

update public.agent_knowledge set content = replace(replace(content,
  'No — once a supplier submits a quotation it is final, so it should be reviewed carefully before sending. After a customer reveals a supplier, any changes are arranged directly between them, off the comparison.',
  (select answer from public.company_faq where id = 78)),
  'No — once you submit a quotation it is final, so review it carefully before sending. After a customer reveals you, you are free to adjust anything directly with them — by that point the platform''''s job is done.',  -- the live row stores a doubled apostrophe (measured)
  (select answer from public.company_faq where id = 46)),
  updated_at = now()
 where id = 1047;

-- PROBE: no knowledge row still tells a supplier a submitted quotation is final.
do $$ declare n int; begin
  select count(*) into n from (
    select 1 from public.company_faq where id in (46, 78, 688, 693)
      and (answer like '%it is final%' or answer like '%نهائي بمجرد%' or answer not like '%12%')
    union all
    select 1 from public.agent_knowledge where content like '%quotation it is final%' or content like '%نهائي بمجرد%') x;
  if n > 0 then raise exception 'PROBE FAIL: % knowledge rows still say a quotation is final', n; end if;
  raise notice 'PROBE OK';
end $$;

