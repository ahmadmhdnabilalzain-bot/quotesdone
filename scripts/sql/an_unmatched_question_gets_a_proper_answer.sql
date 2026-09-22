-- AN UNMATCHED QUESTION GETS A PROPER ANSWER — the FAQ half.
--
-- SEAT: customer_support. Data only: no routine, no table, no grant.
--
-- MEASURED 22 Sep 2026 on production (wa_messages 271): the founder asked "What sectors you cover" on
-- WhatsApp. No FAQ answered it and the reply was an internal error. The WhatsApp half of the fix is in
-- supabase/functions/wa_inbound (coverage from the live trade list, and a courteous fallback). This file
-- is what the SITE ASSISTANT and the FAQ path need, measured with rolled-back probes:
--   * fn_faq_answer('What sectors you cover') keyword rank against FAQ 5 "What industries does QuotesDone
--     support?" is 0.085, under the 0.15 floor: neither "sector" nor "cover" is in the record. Even
--     "what industries do you support" (FAQ 5's own words) ranks 0.085 against its long answer.
--   * The Arabic twin 621 "ما هي القطاعات التي يخدمها QuotesDone؟" does not answer
--     "ما هي القطاعات التي تغطونها": an Arabic question must carry every one of the asker's concepts.
--   * PROVED, in a rolled-back transaction with this file applied and real gte-small vectors (the same
--     question + "\n" + answer recipe the embed script uses): "What sectors you cover" 0.880, "what
--     trades do you cover" 0.881, "what categories do you cover" 0.856, "ما هي القطاعات التي تغطونها"
--     0.940, "ما هي التخصصات التي تغطونها" 0.937 -> the reworded 5 / 621; "هل يدفع المورد رسوم تسجيل"
--     -> the new Arabic fee row (keyword); "what is the weather in paris" -> no answer. Not reached:
--     "which industries do you work in"; "كم رسوم اشتراك المورد" lands on 611 (when fees are charged).
--   * The Arabic FAQ has NO supplier-fee record. English FAQ 500 "Is there a subscription fee for
--     suppliers?" has none of 23 Arabic rows as a twin, so an Arabic supplier asking what registration
--     costs is refused while an English one is answered.
--
-- CHANGES
--   1. FAQ 5 and its Arabic twin 621 keep their subject and their answer; the QUESTION names what people
--      ask about (sectors, trades, categories, cover) and the ANSWER gains the exact-trade sentence
--      (founder, 14 Sep 2026: "either exact match or no match"). One owner for the subject, not a second
--      row: two FAQ rows answering one question drift apart, and then neither is the answer.
--   2. Their embedding_gte is set to NULL so the re-embed below rebuilds it from the new text; a stale
--      vector would keep answering from the old wording.
--   3. One approved, public Arabic row, the twin of FAQ 500, inserted only if it is not there.
-- NOT CHANGED: every other FAQ row, FAQ 500 itself, pricing_config, fn_faq_answer, the site assistant.
--
-- AFTER APPLY (the coordinator): node scripts/kb/embed_sales_knowledge.mjs --table=company_faq
--   — free in-region gte-small, never OpenRouter; it embeds exactly the rows left NULL here.
--
--   node scripts/apply_sql.mjs scripts/sql/an_unmatched_question_gets_a_proper_answer.sql --apply --ddl

update public.company_faq
   set question = 'What sectors, trades and categories does QuotesDone cover?',
       answer = answer || ' '
             || 'Each request is sent only to suppliers of that exact trade, never to a neighbouring one.',
       embedding_gte = null, updated_at = now()
 where id = 5 and question = 'What industries does QuotesDone support?';

update public.company_faq
   set question = 'ما هي القطاعات والتخصصات التي تغطونها؟',
       answer = answer || ' '
             || 'ويُرسل كل طلب إلى موردي التخصص المطلوب نفسه فقط، ولا يُرسل إلى تخصص قريب منه.',
       embedding_gte = null, updated_at = now()
 where id = 621 and question = 'ما هي القطاعات التي يخدمها QuotesDone؟';

insert into public.company_faq
  (section, sort, question, answer, audience, status, public, language, source_note, tags, approved_at, approved_by)
select
  'Arabic', 904,
  'هل يدفع الموردون رسوم اشتراك أو رسوم تسجيل؟',
  'لا يدفع أول 1,000 مورد يسجّلون في المنصة أي رسوم، ويبقون معفيين منها بصفة دائمة، فالتسجيل مجاني لهم. '
  || 'أما كل مورد يسجّل بعدهم فيدفع اشتراكًا سنويًا قدره 1,000 درهم إماراتي، دون تاريخ بدء محدد، إذ يسري '
  || 'ابتداءً من التسجيل رقم 1,001. ولا تُفرض أي عمولة على الأعمال التي يفوز بها المورد.',
  'all', 'approved', true, 'ar',
  'Arabic mirror of company_faq id 500 (Is there a subscription fee for suppliers?), added 22 Sep 2026: '
  || 'the Arabic FAQ had no supplier-fee record, so an Arabic supplier asking what registration costs was refused.',
  array['supplier','fee','subscription','arabic'],
  now(), 'customer_support'
where not exists (
  select 1 from public.company_faq
   where language = 'ar' and source_note like 'Arabic mirror of company_faq id 500 %');

-- The verdict as a ROW: both owners carry the new wording with no stale vector (or were already
-- re-embedded), and the Arabic supplier-fee twin exists, approved and public, exactly once.
select case when (select count(*) from public.company_faq
                   where id in (5, 621) and question in ('What sectors, trades and categories does QuotesDone cover?',
                                                        'ما هي القطاعات والتخصصات التي تغطونها؟')) = 2
             and (select count(*) from public.company_faq
                   where status = 'approved' and public and language = 'ar'
                     and source_note like 'Arabic mirror of company_faq id 500 %') = 1
            then 'PROBE OK — coverage FAQ 5/621 reworded, one Arabic supplier-fee FAQ'
            else 'PROBE FAILED — coverage FAQ not reworded or the Arabic supplier-fee FAQ missing or duplicated' end as probe_verdict;
