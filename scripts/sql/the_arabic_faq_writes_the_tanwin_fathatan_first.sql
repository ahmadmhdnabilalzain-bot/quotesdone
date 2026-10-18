-- customer_support, 12 Oct 2026. Follow-up to the_arabic_faq_adds_no_card_fee_and_states_the_v14_charge.sql (#1323).
-- That file wrote the accusative tanwin alif-first (U+0627 U+064B) in rows 610 and 616; the reviewed corpus writes it
-- fathatan-first (U+064B U+0627), and every_arabic_message_is_written_not_translated.test.mjs refuses the other order.
-- The text of the earlier file is corrected in the same PR; this file corrects the two live rows, md5-guarded against
-- the text that file wrote (a row edited since is left alone), and clears their embedding.

update public.company_faq set answer = replace(answer, U&'\0627\064B', U&'\064B\0627'), embedding_gte = null, updated_at = now()
 where id = 610 and md5(answer) = '4b6bb8ca3206433404fb68676d014a7c';

update public.company_faq set answer = replace(answer, U&'\0627\064B', U&'\064B\0627'), embedding_gte = null, updated_at = now()
 where id = 616 and md5(answer) = '16a75a56afcd4339dde6dde9387a2969';

select case when n = 0 then 'PROBE OK' else 'PROBE FAILED: ' || n || ' public Arabic FAQ row(s) of 610/616 still write the tanwin alif-first' end as verdict
  from (select count(*) n from public.company_faq where id in (610, 616) and strpos(answer, U&'\0627\064B') > 0) s;
