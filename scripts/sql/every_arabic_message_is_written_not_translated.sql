-- EVERY ARABIC MESSAGE IS WRITTEN, NOT TRANSLATED — the database half. Seat: customer_support.
-- Founder instruction 586, 21 Sep 2026: "the Arabic email feels like a pure translation. It should
-- feel much more professional".
--
-- MEASURED on htdblwldjkcgjvmqkbeh, 22 Sep 2026: 34 public routines carry Arabic in their source, and
-- public.notification_copy had 13 rows with subject_ar/body_ar; every Arabic literal in them was read. (It now
-- has 14: licence_renewal, added by #808 after this was measured, is already native and is left as is.)
--   - 15 routines compose text a customer or supplier reads (mail, WhatsApp, chat replies, portal
--     payload); 14 of them carried literal-translation artefacts and are redefined here, plus
--     fn_supplier_notice, whose Arabic fallback name has to fit the new formal greeting.
--   - Every notification_copy row addressed the reader in the singular masculine (ka), which is wrong
--     for a business; all 13 of them (13 of the 14 rows now) are rewritten in the formal plural (kum) and start without a greeting
--     because the email frame supplies it.
-- WHAT WAS WRONG (named artefacts): the "has been done" passive chain (tamma + masdar) in subjects and
-- bodies; the emphatic "we" before a verb in the collaboration warning; "on the basis of" stacked like
-- English; singular "you" to suppliers and customers in formal mail; the letters opening with a chatty
-- "dear" and closing "with thanks" instead of the Gulf business formula (the formal addressee line,
-- the greeting "tahiyya tayyiba wa-ba'd", and the respect-and-regards close); "verified" written as a
-- passive relative clause; a malformed imperative of "to win" in the tier ladder; "gap(s)" rendered
-- with a parenthesised plural; "buyers" where the glossary says customer; "the licence gate" calque.
-- WHAT THIS CHANGES: Arabic string literals ONLY. No logic, no signature, no English text, no grant:
-- each body is the live pg_get_functiondef text with Arabic fragments swapped, and a mechanical diff
-- with every Arabic-bearing line removed was identical to live for all 15. Placeholders ({company},
-- {ref}, concatenated amounts, dates, day counts) are kept exactly; amounts, deadlines and the
-- supplier-agreement consequences are unchanged in meaning.
-- REVIEWED, KEPT (vocabulary or matching, not messages): fn_spec_offer_whatsapp_reply,
-- fn_supplier_document_home, fn_price_guidance, fn_faq_answer, fn_wa_attach_document, fn_sales_assist,
-- fn_language_mismatch, fn_org_task_consume_tick, fn_notifications_speak_the_recipients_language,
-- fn_notifications_supplier_invite_is_whole, fn_support_corpus_search; and fn_sales_engineer_writes,
-- whose only Arabic is the sales-engineer signature line, already native.
-- NOT TOUCHED BY DESIGN: the supplier invitation body and its templates (approved under instruction
-- 634); the registration reminders fn_supplier_registration_reminder_compose (already rewritten); the
-- vocabulary routines fn_ar_norm, kb_norm, fn_norm_trades, fn_document_classify, fn_wa_route,
-- fn_supplier_invite_candidates; every PDF document.
-- This file is the anchor of scripts/checks/every_arabic_message_is_written_not_translated.test.mjs:
-- it and every SQL file appended after it in MANIFEST are scanned for translation artefacts, which is
-- why the verdict below names the replaced phrases in hex rather than in Arabic.

-- 1. Concurrency guard: every routine below is redefined from the body measured on 22 Sep 2026.
--    If another seat has changed one since, the whole file (one transaction) aborts untouched.
do $guard$
begin
  if md5((select prosrc from pg_proc where oid = 'public.fn_sales_engineer_acts_on_handoff(bigint)'::regprocedure)) is distinct from '5cb7a79fcceb784813bf7cf61391868b' then
    raise exception 'CHK<<stale: fn_sales_engineer_acts_on_handoff changed since this file was written; re-derive>>';
  end if;
  if md5((select prosrc from pg_proc where oid = 'public.fn_refund_open_from_customer(uuid,text,text)'::regprocedure)) is distinct from '4fffb6b9cea794bf8239d507da3f0854' then
    raise exception 'CHK<<stale: fn_refund_open_from_customer changed since this file was written; re-derive>>';
  end if;
  if md5((select prosrc from pg_proc where oid = 'public.fn_supplier_advisor(bigint)'::regprocedure)) is distinct from '957c1bc8441e0fc5679e6c24dd1ffbd9' then
    raise exception 'CHK<<stale: fn_supplier_advisor changed since this file was written; re-derive>>';
  end if;
  if md5((select prosrc from pg_proc where oid = 'public.fn_sales_engineer_supplier_documents_tick()'::regprocedure)) is distinct from '410e50c1bcce85c5cba8994d840ebcf4' then
    raise exception 'CHK<<stale: fn_sales_engineer_supplier_documents_tick changed since this file was written; re-derive>>';
  end if;
  if md5((select prosrc from pg_proc where oid = 'public.fn_sales_engineer_ladder_step(uuid,text,bigint,bigint)'::regprocedure)) is distinct from '93c1bd8469307f22f177f571ee1c937e' then
    raise exception 'CHK<<stale: fn_sales_engineer_ladder_step changed since this file was written; re-derive>>';
  end if;
  if md5((select prosrc from pg_proc where oid = 'public.fn_sales_engineer_writes_money_notice(bigint)'::regprocedure)) is distinct from 'ad10d4c624300d9bc4fb9a724426d9d0' then
    raise exception 'CHK<<stale: fn_sales_engineer_writes_money_notice changed since this file was written; re-derive>>';
  end if;
  if md5((select prosrc from pg_proc where oid = 'public.fn_supplier_certifications(bigint)'::regprocedure)) is distinct from '4db063ffd0b2dc9a39e27385299e3c9e' then
    raise exception 'CHK<<stale: fn_supplier_certifications changed since this file was written; re-derive>>';
  end if;
  if md5((select prosrc from pg_proc where oid = 'public.fn_supplier_tier(bigint)'::regprocedure)) is distinct from '471bf3089804d96893ad5f2acb11a544' then
    raise exception 'CHK<<stale: fn_supplier_tier changed since this file was written; re-derive>>';
  end if;
  if md5((select prosrc from pg_proc where oid = 'public.fn_support_knowledge_gap(text,text,text)'::regprocedure)) is distinct from 'b49735f5e3e3412726d30cab53e5f288' then
    raise exception 'CHK<<stale: fn_support_knowledge_gap changed since this file was written; re-derive>>';
  end if;
  if md5((select prosrc from pg_proc where oid = 'public.fn_text_did_not_survive_reply(text)'::regprocedure)) is distinct from '1cbe4bba036f871f9ff00ac3749c5a96' then
    raise exception 'CHK<<stale: fn_text_did_not_survive_reply changed since this file was written; re-derive>>';
  end if;
  if md5((select prosrc from pg_proc where oid = 'public.fn_supplier_collaboration_incident(bigint,uuid,uuid,bigint)'::regprocedure)) is distinct from '059144e01fd9282e24e61c55aa39e31d' then
    raise exception 'CHK<<stale: fn_supplier_collaboration_incident changed since this file was written; re-derive>>';
  end if;
  if md5((select prosrc from pg_proc where oid = 'public.fn_supplier_collaboration_hold_lift(bigint,bigint,text)'::regprocedure)) is distinct from '982773558cdaaec033bc4bd2462d454d' then
    raise exception 'CHK<<stale: fn_supplier_collaboration_hold_lift changed since this file was written; re-derive>>';
  end if;
  if md5((select prosrc from pg_proc where oid = 'public.fn_notify_supplier(uuid,text)'::regprocedure)) is distinct from 'c02a2e32d87882aa597952175621d041' then
    raise exception 'CHK<<stale: fn_notify_supplier changed since this file was written; re-derive>>';
  end if;
  if md5((select prosrc from pg_proc where oid = 'public.fn_sales_engineer_tells_customer_invoice_ready()'::regprocedure)) is distinct from '2a8103c5993c07be94febd13899d6789' then
    raise exception 'CHK<<stale: fn_sales_engineer_tells_customer_invoice_ready changed since this file was written; re-derive>>';
  end if;
  if md5((select prosrc from pg_proc where oid = 'public.fn_supplier_notice(bigint,text,text,text,text,text,uuid,uuid)'::regprocedure)) is distinct from '91f38603e7aefe813e6dcc5455fa17bb' then
    raise exception 'CHK<<stale: fn_supplier_notice changed since this file was written; re-derive>>';
  end if;
  -- notification_copy: all 13 rows must still hold the body measured on 22 Sep, or nothing changes.
  if (select count(*) from public.notification_copy c
        join (values ('*', '78c1f63ffbd7d8240dd40a323d2d9bf4'), ('billing_answer', '10d471b75e6591867f455244324feefb'), ('cancel_warning', 'a5be12b3f7f12fe5c3eeb2cbb9f64fe0'), ('doc_final_notice', '492498367ec26964fe2a856b515dc3d7'), ('doc_received', '615035b8d9e57fd576c9c35e9e9fc776'), ('doc_suspended', '5527a0918ac0e4b4df60a9e8a0489c26'), ('job_awarded_other', '3ca91033de6b4ca62007bcb36aca9d2b'), ('new_inquiry', '32f4bc8b74905d7970a01db887a07124'), ('new_message', '0cfb3faeea5af2767a17102ece6a8e44'), ('new_quote', '265cbdb9f0c3489cf564a097425478b6'), ('quote_coaching', 'e7f1e2306275b59e3d30e16044655980'), ('quote_requirements_changed', 'c89578fc05b0b94a91e00344f60dc152'), ('rfq_addendum', '3510278336b9210178922d810181f9e8')) v(type, old_md5)
          on v.type = c.type and md5(c.body_ar) = v.old_md5) <> 13 then
    raise exception 'CHK<<stale: notification_copy changed since this file was written (rows: %); re-derive>>',
      (select string_agg(v.type, ', ') from (values ('*', '78c1f63ffbd7d8240dd40a323d2d9bf4'), ('billing_answer', '10d471b75e6591867f455244324feefb'), ('cancel_warning', 'a5be12b3f7f12fe5c3eeb2cbb9f64fe0'), ('doc_final_notice', '492498367ec26964fe2a856b515dc3d7'), ('doc_received', '615035b8d9e57fd576c9c35e9e9fc776'), ('doc_suspended', '5527a0918ac0e4b4df60a9e8a0489c26'), ('job_awarded_other', '3ca91033de6b4ca62007bcb36aca9d2b'), ('new_inquiry', '32f4bc8b74905d7970a01db887a07124'), ('new_message', '0cfb3faeea5af2767a17102ece6a8e44'), ('new_quote', '265cbdb9f0c3489cf564a097425478b6'), ('quote_coaching', 'e7f1e2306275b59e3d30e16044655980'), ('quote_requirements_changed', 'c89578fc05b0b94a91e00344f60dc152'), ('rfq_addendum', '3510278336b9210178922d810181f9e8')) v(type, old_md5)
        where not exists (select 1 from public.notification_copy c where c.type = v.type and md5(c.body_ar) = v.old_md5));
  end if;
end $guard$;

-- 1b. public.fn_ar_days(int): an Arabic day count with the number agreeing (0 = today, 1, 2, 3-10,
--     11+). "N days" had been glued as one fixed noun after the number, wrong for 1, 2 and 3-10
--     (review of #818). The SQL twin of arDays() in src/lib/durationLabel.ts and
--     supabase/functions/_shared/ar_days.ts; every_arabic_message_is_written_not_translated.test.mjs
--     keeps the three equal. Two routines below call it; both are security definer, so no caller
--     needs EXECUTE of its own.
create or replace function public.fn_ar_days(p_n integer)
returns text
language sql
immutable
returns null on null input
set search_path to 'public', 'pg_temp'
as $fn$
  select case
    when abs(p_n) = 0 then 'اليوم'
    when abs(p_n) = 1 then 'يوم واحد'
    when abs(p_n) = 2 then 'يومان'
    when abs(p_n) <= 10 then abs(p_n)::text || ' أيام'
    else abs(p_n)::text || ' يومًا'
  end
$fn$;

revoke execute on function public.fn_ar_days(integer) from public, anon, authenticated;

-- 2. The routines. Each body is the live pg_get_functiondef text with only Arabic literals rewritten;
--    every routine was closed to anon/authenticated when measured, and the revoke is restated.

-- fn_sales_engineer_acts_on_handoff: 29 Arabic fragment(s) rewritten.
CREATE OR REPLACE FUNCTION public.fn_sales_engineer_acts_on_handoff(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  a public.agent_actions; d jsonb; t text;
  v_cust record; v_sup record; v_inq text; v_window int; v_chase int; v_min int; v_max int;
  v_tx public.transactions; v_amt text; v_req bigint; v_lines text; v_orig public.notifications;
  v_revealed text; v_rid text;
begin
  select * into a from public.agent_actions where id = p_id;
  d := a.detail; t := d->>'type';
  select refund_window_working_days, chase_after_working_days, bank_settlement_working_days_min, bank_settlement_working_days_max
    into v_window, v_chase, v_min, v_max from public.pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3); v_min := coalesce(v_min, 7); v_max := coalesce(v_max, 14);

  select null::uuid as id, null::text as email, null::text as full_name into v_cust;
  select null::bigint as id, null::text as company_name, null::text as email into v_sup;
  if (d->>'customer_id') is not null then
    select id, email, full_name into v_cust from public.customers where id = (d->>'customer_id')::uuid;
  end if;
  if (d->>'supplier_id') is not null then
    select id, company_name, coalesce(claimed_by, email) as email into v_sup from public.leads where id = (d->>'supplier_id')::bigint;
  end if;
  if (d->>'inquiry_id') is not null then
    select summary into v_inq from public.inquiries where id = (d->>'inquiry_id')::uuid;
  end if;
  v_revealed := coalesce(to_char((d->>'revealed_at')::timestamptz at time zone 'Asia/Dubai', 'DD Mon YYYY'), 'the reveal date');
  v_rid := left(coalesce(d->>'transaction_id', d->>'subject_id', ''), 8);

  if t = 'reveal.paid' then
    -- The words trg_reveal_receipt used to write itself, unchanged, now composed by the seat whose
    -- voice the portal is and carried by the seat that owns the pipe.
    if v_cust.email is not null then
      v_req := public.fn_sales_engineer_writes('reveal_receipt', 'customer', v_cust.email, null, v_cust.id,
        (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'Reveal confirmed — ' || coalesce(v_sup.company_name, 'supplier'),
        'You have unlocked ' || coalesce(v_sup.company_name, 'the supplier') || '''s contact details'
          || coalesce(' for: ' || left(v_inq, 80), '')
          || '. You can now message them directly in the app. We track this reveal from the moment you paid: if the supplier has not responded within '
          || v_chase::text || ' working days we chase them for you and copy you; if there is still no response by working day '
          || v_window::text || ' the case is decided by our chief executive, and if the supplier never responded everything you paid is refunded in full. '
          || 'Banks usually take ' || v_min || '-' || v_max || ' working days to show a refund. You can also open the request and Report an issue at any time.',
        'اكتمل الكشف — ' || coalesce(v_sup.company_name, 'المورّد'),
        'أصبحت بيانات التواصل مع ' || coalesce(v_sup.company_name, 'المورّد') || ' متاحة لكم الآن، ويمكنكم مراسلته مباشرة من التطبيق. '
          || 'نتابع هذا الكشف منذ لحظة الدفع: إن لم يردّ المورّد خلال ' || v_chase::text || ' أيام عمل فسنتواصل معه نيابةً عنكم مع نسخة إليكم، '
          || 'وإن لم يردّ حتى يوم العمل ' || v_window::text || ' فسيبتّ رئيسنا التنفيذي في الحالة، وإن لم يردّ المورّد إطلاقًا فسنردّ إليكم كامل المبلغ المدفوع.',
        '{}', 'reveal_receipt:' || (d->>'subject_id'), null, jsonb_build_object('transaction_id', d->>'subject_id'));
    end if;
    if coalesce(v_sup.email, '') like '%@%' then
      perform public.fn_sales_engineer_writes('quote_accepted', 'supplier', v_sup.email, v_sup.id, null,
        (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'A customer revealed your quote on QuotesDone',
        'A customer paid to reveal your contact for: ' || coalesce(v_inq, '')
          || '. Please respond promptly — under the Supplier Agreement you must respond within ' || v_window::text
          || ' working days of the reveal. If you have not responded after ' || v_chase::text
          || ' working days we chase you with the customer copied; if there is still no response on working day ' || v_window::text
          || ' our chief executive decides the case, the customer is refunded, and the amount refunded plus an AED 250 administrative fee and 9% p.a. interest is recovered from your account.',
        'كشف أحد العملاء عن عرضكم على QuotesDone',
        'سدّد أحد العملاء رسوم الكشف عن بيانات التواصل معكم بشأن: ' || coalesce(v_inq, '') || '. نرجو المبادرة بالرد، إذ تُلزم اتفاقية المورّد بالرد خلال '
          || v_window::text || ' أيام عمل من تاريخ الكشف، وإلا فسيُردّ إلى العميل كامل ما دفعه، ويُسترد المبلغ من حسابكم مع رسوم إدارية قدرها 250 درهمًا وفائدة 9% سنويًا.',
        '{}', 'quote_accepted:' || (d->>'subject_id'), null, jsonb_build_object('transaction_id', d->>'subject_id'));
    end if;
    return jsonb_build_object('customer_reachable', v_cust.email is not null,
                              'supplier_reachable', coalesce(v_sup.email, '') like '%@%',
                              'delivery_request', v_req);

  elsif t = 'payment.failed' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('reveal_payment_incomplete', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your reveal payment did not complete',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'Your payment to unlock the supplier''s contact details did not go through, and nothing was charged to your card.' || E'\n\n'
        || 'You can try again at any time: open the request in your QuotesDone portal and choose Reveal on the quote you picked. If the card was declined, your bank can tell you why, and a different card also works.',
      'لم يكتمل دفع رسوم الكشف',
      'تعذّر إتمام دفع رسوم الكشف عن بيانات المورّد، ولم يُخصم أي مبلغ من بطاقتكم. يمكنكم إعادة المحاولة في أي وقت من بوابتكم على QuotesDone.',
      '{}', 'payment_failed:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'payment.received' then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes(coalesce(d->>'msg_type', 'dues_paid'), 'supplier', v_sup.email, v_sup.id, null, null, null,
      case when d->>'kind' = 'supplier_registration' then 'Registration confirmed - thank you' else 'Payment received - thank you' end,
      case when d->>'kind' = 'supplier_registration'
           then 'We have received your registration payment of AED ' || (d->>'amount_aed') || '. Your QuotesDone supplier account is registered for the next 12 months.'
           else 'We have received your payment of AED ' || (d->>'amount_aed') || ' settling ' || coalesce(d->>'items', '1') || ' outstanding charge(s). Your account is now up to date.' end,
      'استلمنا دفعتكم', 'استلمنا دفعتكم البالغة ' || (d->>'amount_aed') || ' درهم، ونشكركم على ذلك.',
      '{}', 'payment_received:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'refund.request_checked' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_amt := case when (d->>'money_ok')::boolean then ' — AED ' || (d->>'amount_aed') else '' end;
    v_req := public.fn_sales_engineer_writes('refund_request_received', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'We have your refund request',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'We have received your refund request for the reveal on ' || coalesce('"' || left(v_inq, 80) || '"', 'your request') || '.' || E'\n\n'
        || 'What happens next: we check whether the supplier ever replied to you, our chief executive decides on that record, and if the refund is due you get back everything you paid'
        || v_amt || ', the reveal fee and the card processing part together, to the card you paid with. Banks usually take ' || v_min || '–' || v_max || ' working days to show it.' || E'\n\n'
        || 'If you have an email thread with the supplier, keep it: it is the proof we rely on.',
      'استلمنا طلب الاسترداد',
      'استلمنا طلبكم استرداد رسوم الكشف. نتحقق أولًا من ردّ المورّد، ثم يبتّ رئيسنا التنفيذي في الطلب، فإن ثبت استحقاق الاسترداد فسيُعاد إليكم كامل المبلغ المدفوع إلى البطاقة نفسها خلال '
        || v_min || '–' || v_max || ' يوم عمل بحسب البنك.',
      '{}', 'refund_request_received:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req, 'money_ok', d->'money_ok');

  elsif t = 'refund.paid' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('refund_issued', 'customer', v_cust.email, (d->>'supplier_id')::bigint, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your QuotesDone refund of AED ' || (d->>'amount_aed') || ' has been issued',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'We have issued a refund of AED ' || (d->>'amount_aed') || ' — everything you paid on ' || v_revealed
        || ', the reveal fee and the card processing part together — to your original payment method, because the supplier did not respond within '
        || v_window::text || ' working days. Nothing is deducted.' || E'\n\n'
        || 'Banks and card issuers usually take ' || v_min || '–' || v_max || ' working days to show it on your statement. If it has not appeared after '
        || v_max || ' working days, reply to this email and we will trace it with the payment processor.' || E'\n\n'
        || 'You are welcome to post the request again; we will introduce you to another supplier.',
      'أصدرنا استردادًا بقيمة ' || (d->>'amount_aed') || ' درهم',
      'أصدرنا لكم استردادًا بقيمة ' || (d->>'amount_aed') || ' درهم، أي كامل المبلغ المدفوع، إلى وسيلة الدفع الأصلية، إذ لم يردّ المورّد خلال '
        || v_window::text || ' أيام عمل. وقد يستغرق ظهوره في كشف حسابكم ' || v_min || '–' || v_max || ' يوم عمل.',
      '{}', 'refund_issued:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req, 'amount_aed', d->'amount_aed');

  elsif t = 'refund.declined' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('refund_declined', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'About your refund request',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'We looked at your refund request for the reveal on ' || coalesce('"' || left(v_inq, 80) || '"', 'your request') || ' and it was not approved.' || E'\n\n'
        || 'The reason: ' || coalesce(nullif(btrim(d->>'note'), ''), 'the record shows the supplier did respond.') || E'\n\n'
        || 'If you think we have missed something, reply to this email with what you have — an email thread with the supplier, dates, anything — and we will look again.',
      'بشأن طلب الاسترداد',
      'راجعنا طلب الاسترداد وتعذّرت الموافقة عليه. السبب: ' || coalesce(nullif(btrim(d->>'note'), ''), 'يُظهر السجل أن المورّد قد ردّ.')
        || ' وإن كان لديكم ما يثبت خلاف ذلك، فيسعدنا أن تردّوا على هذه الرسالة لنعيد النظر في الطلب.',
      '{}', 'refund_declined:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'refund.in_progress' then
    if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('refund_in_progress', 'customer', v_cust.email, null, v_cust.id,
      (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
      'Your refund is being processed',
      'Hello ' || coalesce(nullif(btrim(v_cust.full_name), ''), 'there') || E',\n\n'
        || 'Your refund of AED ' || coalesce(d->>'amount_aed', '') || ' has been approved and is being processed with the payment provider. It has not reached your card yet; we will write again the moment it has.',
      'استردادكم قيد المعالجة',
      'وافقنا على استردادكم، وهو الآن قيد المعالجة لدى مزوّد الدفع ولم يصل إلى بطاقتكم بعد. وسنُعلمكم فور وصوله.',
      '{}', 'refund_in_progress:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t in ('nonresponse.charge_raised', 'charge.corrected') then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_lines := '  Amount refunded to the customer: AED ' || (d->>'refunded_aed') || E'\n'
            || '  Administration fee: AED ' || (d->>'admin_fee_aed') || E'\n'
            || '  Interest: ' || round((d->>'interest_apr')::numeric * 100, 2) || '% a year, simple, on AED '
            || round((d->>'refunded_aed')::numeric + (d->>'admin_fee_aed')::numeric, 2) || ' from ' || (d->>'due_date') || ' until paid' || E'\n'
            || '  Due by: ' || (d->>'due_date');
    if t = 'nonresponse.charge_raised' then
      v_req := public.fn_sales_engineer_writes('nonresponse_charge', 'supplier', v_sup.email, v_sup.id, null,
        (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'Charge under the Supplier Agreement — reveal #' || left(coalesce(d->>'transaction_id', ''), 8),
        'Hello ' || coalesce(v_sup.company_name, '') || E',\n\n'
          || 'A customer paid to reveal your contact details and did not hear from you within ' || v_window::text
          || ' working days, despite the reminders we sent. Under the Supplier Agreement the customer has been refunded in full, and that refund is recovered from your account:' || E'\n\n'
          || v_lines || E'\n\n'
          || 'Matching is paused until this is settled. You can pay it from the Billing section of your supplier portal. If you believe it is wrong, use "Dispute this charge" there or reply to this email and we will check the figures against the payment record.',
        'رسوم بموجب اتفاقية المورّد',
        'سدّد أحد العملاء رسوم الكشف عن بيانات التواصل معكم ولم يتلقَّ ردًّا خلال ' || v_window::text || ' أيام عمل رغم التذكيرات، فرُدّ إليه كامل ما دفعه بموجب اتفاقية المورّد، ويُسترد من حسابكم ما يلي: المبلغ المسترد '
          || (d->>'refunded_aed') || ' درهم، ورسوم إدارية ' || (d->>'admin_fee_aed') || ' درهم، وفائدة بسيطة ' || round((d->>'interest_apr')::numeric * 100, 2)
          || '% سنويًا من ' || (d->>'due_date') || ' حتى السداد. ويمكنكم السداد أو الاعتراض من قسم الفواتير في بوابتكم.',
        '{}', 'nonresponse_charge:' || (d->>'subject_id'));
    else
      -- THE CORRECTION MUST REACH WHOEVER GOT THE ORIGINAL: its To and every Cc, not today's address book.
      select * into v_orig from public.notifications where id = (d->>'original_notification_id')::bigint;
      v_req := public.fn_sales_engineer_writes('nonresponse_charge_correction', 'supplier',
        coalesce(v_orig.to_email, v_sup.email), v_sup.id, null, (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid,
        'Correction: ' || coalesce(v_orig.subject, 'your charge under the Supplier Agreement'),
        'This replaces our message of ' || coalesce(to_char(v_orig.created_at at time zone 'Asia/Dubai', 'DD Mon YYYY'), 'earlier')
          || ' about this charge, which carried the wrong figures. Please disregard it. The correct figures are:' || E'\n\n' || v_lines,
        'تصحيح: رسوم بموجب اتفاقية المورّد',
        'هذه الرسالة تحلّ محلّ رسالتنا السابقة التي تضمنت أرقامًا غير صحيحة. الأرقام الصحيحة: المبلغ المسترد ' || (d->>'refunded_aed')
          || ' درهم، ورسوم إدارية ' || (d->>'admin_fee_aed') || ' درهم، مستحقة في ' || (d->>'due_date') || '.',
        coalesce(v_orig.cc_emails, '{}'), 'charge_corrected:' || (d->>'subject_id'));
    end if;
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'subscription.due' then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_req := public.fn_sales_engineer_writes('subscription_due', 'supplier', v_sup.email, v_sup.id, null, null, null,
      'Your QuotesDone annual subscription is due',
      'Dear ' || coalesce(v_sup.company_name, 'there') || E',\n\nYour QuotesDone annual supplier subscription of '
        || coalesce(d->>'currency', 'AED') || ' ' || (d->>'fee') || E' is now due.\n\nYou keep paying no commission on the jobs you win — this is the annual subscription only. You can settle it securely on the supplier portal: https://quotesdone.com/suppliers\n\nIf it is not settled, your profile is paused from receiving new customer requests until it is.\n\nThank you for being part of QuotesDone.',
      'اشتراككم السنوي في QuotesDone مستحق',
      'حان موعد سداد اشتراككم السنوي كمورّد بقيمة ' || (d->>'fee') || ' درهم، ويمكنكم السداد بأمان من بوابة المورّد.',
      '{}', 'subscription_due:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req);

  elsif t = 'billing.answer' then
    v_lines := (select string_agg('  ' || x, E'\n') from jsonb_array_elements_text(d->'facts') x);
    if d->>'party' = 'supplier' then
      if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
      v_req := public.fn_sales_engineer_writes('billing_answer', 'supplier', v_sup.email, v_sup.id, null, null, null,
        'Your question about a charge', E'Here is what our records show:\n\n' || coalesce(v_lines, '  Nothing is recorded against your account.'),
        null, null, '{}', 'billing_answer:' || (d->>'subject_id'));
    else
      if v_cust.email is null then return jsonb_build_object('customer_reachable', false); end if;
      v_req := public.fn_sales_engineer_writes('billing_answer', 'customer', v_cust.email, null, v_cust.id, null, null,
        'Your question about a charge', E'Here is what our records show:\n\n' || coalesce(v_lines, '  No payment is recorded on your account.'),
        null, null, '{}', 'billing_answer:' || (d->>'subject_id'));
    end if;
    return jsonb_build_object('delivery_request', v_req, 'facts', d->'facts');

  elsif t = 'charge.dispute_answer' then
    if coalesce(v_sup.email, '') not like '%@%' then return jsonb_build_object('supplier_reachable', false); end if;
    v_lines := (select string_agg('  ' || x, E'\n') from jsonb_array_elements_text(d->'lines') x);
    v_req := public.fn_sales_engineer_writes('charge_dispute_answer', 'supplier', v_sup.email, v_sup.id, null, null, null,
      'Your query about charge #' || coalesce(d->>'due_id', ''),
      case when (d->>'figures_match')::boolean
           then E'We checked the charge against the payment record and the figures stand:\n\n'
           else E'We checked the charge against the payment record and the figures do not match it. It is on hold while our chief executive reviews it; you do not need to pay it until we write again.\n\n' end
        || coalesce(v_lines, ''),
      null, null, '{}', 'charge_dispute_answer:' || (d->>'subject_id'));
    return jsonb_build_object('delivery_request', v_req, 'figures_match', d->'figures_match');

  elsif t = 'refund.remediate' then
    return public.fn_sales_engineer_remediates(p_id);

  elsif t = 'delivery.result' then
    return public.fn_sales_engineer_attaches_delivery_result(p_id);

  elsif t in ('backup.refile', 'backup.remediate') then
    return public.fn_sales_engineer_refiles_backup(p_id);
  end if;
  raise exception 'sales_engineer has no handler for %', t;
end $function$;

revoke execute on function public.fn_sales_engineer_acts_on_handoff(bigint) from public, anon, authenticated;

-- fn_refund_open_from_customer: 19 Arabic fragment(s) rewritten.
CREATE OR REPLACE FUNCTION public.fn_refund_open_from_customer(p_transaction_id uuid, p_requested_by text, p_reason_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t public.transactions; c record; v_id bigint; v_open bigint; v_locale text; v_code text; v_en text; v_ar text;
  v_later boolean := false; v_paid text; v_decide text; v_req bigint; v_amt numeric;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'no_such_transaction', 'locale', 'en', 'can_claim_later', false,
      'message_en', 'We could not find that reveal on your account.', 'message_ar', 'لم نعثر على عملية الكشف هذه في حسابكم.');
  end if;
  select id, email into c from public.customers where id = t.customer_id;
  v_locale := coalesce(public.fn_registered_locale('customer', t.customer_id, null, c.email), 'en');
  v_amt := round(coalesce(t.total_charged, t.reveal_fee, 0), 2);
  v_paid := to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY');
  v_decide := to_char(t.refund_deadline at time zone 'Asia/Dubai', 'DD Mon YYYY');

  -- ONE CLAIM PER PAYMENT: a second press, or a retry, returns the case already open.
  select id into v_open from public.refunds
   where transaction_id = t.id and status not in ('rejected', 'failed', 'cancelled')
     and lower(coalesce(requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe')
   order by id limit 1;
  if v_open is not null then
    return jsonb_build_object('ok', true, 'duplicate', true, 'refund_id', v_open, 'locale', v_locale, 'decision_after', t.refund_deadline,
      'message_en', 'Your refund case QD-RF-' || v_open || ' is already open. Our chief executive decides it after ' || coalesce(v_decide, 'the fifth working day') || '; you do not need to do anything else.',
      'message_ar', 'حالة الاسترداد QD-RF-' || v_open || ' مفتوحة بالفعل، وسيبتّ فيها رئيسنا التنفيذي بعد ' || coalesce(v_decide, 'يوم العمل الخامس') || '، ولا يلزمكم أي إجراء آخر.');
  end if;

  -- THE REFUSALS, each with the reason and whether a claim can come later.
  if t.revealed_at is null then
    v_code := 'not_revealed'; v_later := true;
    v_en := 'This reveal has not completed yet. You can ask for a refund once the payment has gone through and the supplier''s details are shown to you.';
    v_ar := 'لم تكتمل عملية الكشف بعد. يمكنكم طلب الاسترداد بعد إتمام الدفع وظهور بيانات المورّد لكم.';
  elsif coalesce(btrim(t.payment_ref), '') = '' then
    v_code := 'no_payment'; v_later := true;
    v_en := 'We have no recorded payment for this reveal yet, so there is nothing to refund. If you were charged, reply to your payment receipt and we will match it; you can ask again once it is recorded.';
    v_ar := 'لا يوجد لدينا دفع مسجّل لعملية الكشف هذه حتى الآن، فلا مبلغ يُسترد. وإن خُصم منكم أي مبلغ، فيُرجى الرد على إيصال الدفع لنطابقه، ويمكنكم تقديم الطلب مجددًا بعد تسجيله.';
  elsif coalesce(t.refund_status, '') in ('approved', 'refunded', 'processing', 'succeeded') then
    v_code := 'already_refunded';
    v_en := 'This reveal has already been refunded (AED ' || coalesce(t.refund_amount_aed, v_amt) || '). Banks take 7 to 14 working days to show it.';
    v_ar := 'سبق أن استُردّت رسوم عملية الكشف هذه (' || coalesce(t.refund_amount_aed, v_amt) || ' درهم)، وتستغرق البنوك من 7 إلى 14 يوم عمل لإظهار المبلغ.';
  elsif exists (select 1 from public.refunds r where r.transaction_id = t.id and r.status = 'rejected'
                  and lower(coalesce(r.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe')) then
    v_code := 'already_declined';
    v_en := 'Our chief executive has already decided this case and declined it; the reason is shown on your refund case. Under section 5 of the Terms a decided case is not reopened by a new request. If you think the record is wrong, reply to the decision email.';
    v_ar := 'سبق أن بتّ رئيسنا التنفيذي في هذه الحالة ورفضها، والسبب مبيّن في حالة الاسترداد. ووفق البند 5 من الشروط، لا يُعاد فتح حالة بُتّ فيها بطلب جديد. وإن رأيتم أن السجل غير صحيح، فيُرجى الرد على رسالة القرار.';
  elsif exists (select 1 from public.inquiries i where i.id = t.inquiry_id and i.status in ('completed', 'closed') and i.hired_supplier_id = t.supplier_id) then
    v_code := 'job_completed';
    v_en := 'This job is marked as completed with this supplier, so the supplier responded and the reveal fee is not refundable (Terms, section 5).';
    v_ar := 'هذا العمل مسجّل مكتملًا مع هذا المورّد، ما يعني أنه استجاب، لذا لا تُسترد رسوم الكشف (الشروط، البند 5).';
  elsif exists (select 1 from public.reviews v where v.transaction_id = t.id) then
    v_code := 'supplier_rated';
    v_en := 'You have rated this supplier, which records that you dealt with them, so the reveal fee is not refundable (Terms, section 5).';
    v_ar := 'قيّمتم هذا المورّد، وهو ما يُثبت تعاملكم معه، لذا لا تُسترد رسوم الكشف (الشروط، البند 5).';
  end if;
  if v_code is not null then
    -- Recorded, so a refusal is as visible to the seats as a case: who asked, when, and why not.
    perform public.fn_emit('refund.request_refused', 'transaction', t.id::text, coalesce(p_requested_by, 'customer'),
      jsonb_build_object('transaction_id', t.id, 'customer_id', t.customer_id, 'code', v_code, 'can_claim_later', v_later, 'reason', v_en));
    return jsonb_build_object('ok', false, 'code', v_code, 'can_claim_later', v_later, 'locale', v_locale, 'message_en', v_en, 'message_ar', v_ar);
  end if;

  -- THE CASE. The amount is what the customer paid (total_charged); a00 holds it to that figure and to
  -- the payment's own Stripe reference. trg_emit_refund_requested and z30 put it on the bus and hand
  -- it to the accountant.
  insert into public.refunds
    (transaction_id, quote_id, inquiry_id, customer_id, supplier_lead_id,
     stripe_payment_intent, amount_fils, currency, reason_code, reason_note,
     status, requested_by, requested_at, amount_source)
  values
    (t.id, t.quote_id, t.inquiry_id, t.customer_id, t.supplier_id,
     t.payment_ref, round(coalesce(t.total_charged, t.reveal_fee, 0) * 100)::bigint, 'AED',
     'supplier_unresponsive',
     coalesce(p_reason_note, 'The customer reported that the revealed supplier has not responded.'),
     'requested', coalesce(p_requested_by, 'customer'), now(), 'in_platform_request')
  returning id into v_id;

  -- The sale follows the case, never the other way round. The refunds row already exists, so
  -- trg_emit_refund_requested_tx sees it and does not emit a second refund.requested.
  update public.transactions
     set refund_status = 'requested', refund_requested_at = coalesce(refund_requested_at, now())
   where id = t.id;

  -- The confirmation: the sales engineer writes it, customer support delivers it in the customer's
  -- registered language (fn_sales_engineer_writes -> delivery.request).
  v_req := public.fn_sales_engineer_writes('refund_request_received', 'customer', c.email, null, t.customer_id, t.inquiry_id, t.quote_id,
    'Your refund case QD-RF-' || v_id || ' is open',
    'We have opened refund case QD-RF-' || v_id || ' for the supplier you revealed on ' || coalesce(v_paid, 'your payment date') || '. You do not need to do anything else.' || E'\n\n'
      || 'The supplier has until ' || coalesce(v_decide, 'the fifth working day after your payment') || ' to respond. We chase them on the third working day and copy you. '
      || 'If there is still no response, our chief executive makes a final call and then decides your case on the record. '
      || 'If the refund is due, everything you paid (AED ' || v_amt || ') is returned to your original payment method; banks take 7 to 14 working days to show it.',
    'فتحنا حالة الاسترداد QD-RF-' || v_id,
    'فتحنا حالة الاسترداد QD-RF-' || v_id || ' بشأن المورّد الذي كشفتم عنه في ' || coalesce(v_paid, 'تاريخ الدفع') || '. لا يلزمكم أي إجراء آخر.' || E'\n\n'
      || 'أمام المورّد حتى ' || coalesce(v_decide, 'يوم العمل الخامس بعد الدفع') || ' للرد، وسنتابعه في يوم العمل الثالث مع نسخة إليكم، '
      || 'فإن لم يردّ، فسيوجّه إليه رئيسنا التنفيذي نداءً أخيرًا ثم يبتّ في حالتكم استنادًا إلى السجل. '
      || 'وإن ثبت استحقاق الاسترداد، فسيُردّ إليكم كامل ما دفعتموه (' || v_amt || ' درهم) إلى وسيلة الدفع الأصلية، وتستغرق البنوك من 7 إلى 14 يوم عمل لإظهاره.',
    '{}', 'refund_request_received:' || t.id, null,
    jsonb_build_object('step', 'customer_request', 'transaction_id', t.id, 'refund_id', v_id));

  return jsonb_build_object('ok', true, 'refund_id', v_id, 'status', 'requested', 'locale', v_locale,
    'decision_after', t.refund_deadline, 'delivery_request', v_req,
    'message_en', 'Refund case QD-RF-' || v_id || ' is open. Our chief executive decides it after ' || coalesce(v_decide, 'the fifth working day') || ', and if it is due everything you paid is refunded. We have emailed you the details.',
    'message_ar', 'فتحنا حالة الاسترداد QD-RF-' || v_id || '، وسيبتّ فيها رئيسنا التنفيذي بعد ' || coalesce(v_decide, 'يوم العمل الخامس') || '، وإن ثبت استحقاق الاسترداد فسيُردّ إليكم كامل ما دفعتموه. وقد أرسلنا إليكم التفاصيل بالبريد الإلكتروني.');
end $function$;

revoke execute on function public.fn_refund_open_from_customer(uuid,text,text) from public, anon, authenticated;

-- fn_supplier_advisor: 24 Arabic fragment(s) rewritten.
CREATE OR REPLACE FUNCTION public.fn_supplier_advisor(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with l as (select * from public.leads where id = p_lead_id),
  s as (select * from public.supplier_score where lead_id = p_lead_id),
  q as (
    select count(*)::int submitted,
           greatest(count(*) filter (where status = 'won')::int,
                    (select count(*)::int from public.inquiries where hired_supplier_id = p_lead_id)) won,
           count(*) filter (where status in ('rejected', 'lost', 'declined'))::int rejected
    from public.quotes where supplier_id = p_lead_id
  ),
  rr as (select coalesce((select rv_response_rate from l), (select response_rate from s)) rate),
  home as (select * from public.fn_supplier_document_home(p_lead_id)),
  cap as (select confirmed_at from public.supplier_capabilities where supplier_id = p_lead_id),
  live_inq as (
    select count(*) as n from public.inquiries i
    where coalesce(i.status, '') not in ('closed', 'cancelled', 'expired')
  ),
  gaps as (
    select g.* from (
      select 'trade_licence' as key, 'Upload your trade licence' as action, 'ارفع الرخصة التجارية' as action_ar,
             'You cannot be matched to any opportunity without a current trade licence.' as why,
             'لا يمكن مطابقتكم مع أي فرصة دون رخصة تجارية سارية.' as why_ar,
             'high' as severity, 'documents' as goes_to, 1 as sort
      where (select path from home where key = 'trade_licence') is null
      union all
      select 'licence_expired', 'Replace your expired trade licence', 'استبدل الرخصة التجارية المنتهية',
             'Your trade licence expired on ' || to_char(l.license_expiry, 'DD Mon YYYY') || '.',
             'انتهت صلاحية رخصتكم التجارية في ' || to_char(l.license_expiry, 'DD Mon YYYY') || '.',
             'high', 'documents', 2
      from l where (select path from home where key = 'trade_licence') is not null
                and l.license_expiry is not null and l.license_expiry < current_date
      union all
      select 'iso_certificate', 'Upload an ISO certificate', 'ارفع شهادة ISO',
             'Buyers filter on ISO 9001 and 14001. Adding one opens the projects that require it.',
             'يفرز العملاء المورّدين بحسب شهادتي ISO 9001 و14001، وإضافتها تتيح لكم المشاريع التي تشترطها.',
             'medium', 'documents', 3
      where (select path from home where key = 'iso') is null
      union all
      select 'iso_expired', 'Renew your ISO certificate', 'جدّد شهادة ISO',
             'Your ISO certificate expired on ' || to_char((select expiry from home where key = 'iso'), 'DD Mon YYYY') || '.',
             'انتهت صلاحية شهادة ISO في ' || to_char((select expiry from home where key = 'iso'), 'DD Mon YYYY') || '.',
             'high', 'documents', 4
      where (select expiry from home where key = 'iso') < current_date
      union all
      select 'not_verified', 'Complete verification', 'أكمل التحقق',
             'Unverified suppliers are excluded from matching entirely.',
             'لا يدخل المطابقة إلا المورّدون الموثَّقون.',
             'high', 'profile', 5
      from l where not coalesce(l.verified, false)
      union all
      -- The gate matching actually opens on (fn_match_capability: confirmed_at), pointed at the tab
      -- where it is confirmed. This replaced a "capability summary" gap that named a machine-filled
      -- column the supplier has no field for (audit 21 Sep 2026, finding 20).
      select 'services_unconfirmed', 'Confirm your services', 'أكّد الخدمات المقدَّمة',
             'Requests are matched on the services you confirm. Nothing reaches you until they are confirmed.',
             'تُطابَق الطلبات مع الخدمات التي تؤكّدونها، ولن يصلكم أي طلب قبل تأكيدها.',
             'high', 'services', 6
      where (select confirmed_at from cap) is null
      union all
      select 'no_products', 'Upload a product catalogue', 'ارفع كتالوج المنتجات',
             'Your catalogue is what buyers search. Without it you compete on company name alone.',
             'يبحث العملاء في الكتالوج، ومن دونه تنافسون باسم الشركة وحده.',
             'medium', 'products', 7
      from l where not exists (select 1 from public.supplier_product sp where sp.supplier_id = l.id)
      union all
      select 'no_service_area', 'Set the emirates you serve', 'حدّد الإمارات التي تغطيها',
             'Opportunities are filtered by location before anything else is considered.',
             'تُفرز الفرص بحسب الموقع قبل أي اعتبار آخر.',
             'medium', 'profile', 8
      from l where coalesce(array_length(l.service_emirates, 1), 0) = 0
      union all
      select 'slow_response', 'Improve your response time', 'حسّن سرعة الاستجابة',
             'Your response rate is ' || round((select rate from rr))::text || '%. Buyers see it, and it is 55% of your reliability score.',
             'معدل استجابتكم ' || round((select rate from rr))::text || '%، وهو ظاهر للعملاء ويشكّل 55% من تقييم موثوقيتكم.',
             'medium', 'twin', 9
      where (select rate from rr) is not null and (select rate from rr) < 60
    ) g
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'loss_analysis', jsonb_build_object(
      'quotes_submitted', (select submitted from q),
      'quotes_won',       (select won from q),
      'rejections',       (select rejected from q),
      'response_rate',    (select rate from rr),
      'loss_reasons', case
        when (select submitted from q) = 0 then '[]'::jsonb
        else jsonb_build_array(
          jsonb_build_object('reason', 'Rejected after quoting', 'reason_ar', 'رُفض بعد التسعير', 'count', (select rejected from q),
            'pct', round(100.0 * (select rejected from q) / nullif((select submitted from q), 0)))
        ) end,
      'basis', case when (select submitted from q) = 0 then 'no_completed_opportunities' else 'quotes_submitted' end
    ),
    'recommendations', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'key', g.key, 'action', g.action, 'action_ar', g.action_ar, 'why', g.why, 'why_ar', g.why_ar,
        'severity', g.severity, 'goes_to', g.goes_to,
        'impact_rfqs', (select n from live_inq)
      ) order by g.sort), '[]'::jsonb) from gaps g
    ),
    'gap_count', (select count(*) from gaps),
    'impact_basis', jsonb_build_object(
      'live_inquiries', (select n from live_inq),
      'note', 'impact_rfqs counts live inquiries a closed gap would let this supplier compete for'
    ),
    'headline', (
      select case
        when (select count(*) from gaps) = 0
          then 'Your profile is complete. You are eligible for every opportunity we can match.'
        when (select n from live_inq) = 0
          then 'You have ' || (select count(*) from gaps)::text
               || ' gap(s) blocking you from being matched at all. Start with: '
               || (select g.action from gaps g order by g.sort limit 1)
               || '. There are no live opportunities right now, so there is time to fix them.'
        else 'Your profile can qualify for ' || (select n from live_inq)::text
             || ' more opportunities if you close ' || (select count(*) from gaps)::text
             || ' gap(s), starting with: ' || (select g.action from gaps g order by g.sort limit 1) || '.'
      end
    ),
    'headline_ar', (
      select case
        when (select count(*) from gaps) = 0
          then 'ملفكم مكتمل، وأنتم مؤهَّلون لكل فرصة يمكننا مطابقتها.'
        when (select n from live_inq) = 0
          then 'عدد النواقص التي تحول دون مطابقتكم: ' || (select count(*) from gaps)::text
               || '. الخطوة الأولى: '
               || (select g.action_ar from gaps g order by g.sort limit 1)
               || '. لا توجد فرص مفتوحة حاليًا، فأمامكم متسع من الوقت لاستكمالها.'
        else 'يمكن أن يتأهّل ملفكم لعدد ' || (select n from live_inq)::text
             || ' من الفرص الإضافية إذا استكملتم النواقص (' || (select count(*) from gaps)::text
             || '). الخطوة الأولى: ' || (select g.action_ar from gaps g order by g.sort limit 1) || '.'
      end
    )
  );
$function$;

revoke execute on function public.fn_supplier_advisor(bigint) from public, anon, authenticated;

-- fn_sales_engineer_supplier_documents_tick: 7 Arabic fragment(s) rewritten.
CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supplier_documents_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_reconcile json; v_final json; v_rechecked int := 0; v_closed int := 0; v_kept int := 0; r record; v jsonb;
  v_missing text[]; v_items_en text; v_items_ar text; v_ar boolean; v_to text; v_opened text; v_out jsonb;
  v_label jsonb := jsonb_build_object(
    'reg_name',        jsonb_build_array('company name', 'اسم الشركة'),
    'reg_mobile',      jsonb_build_array('a verified UAE mobile number', 'رقم جوال إماراتي موثَّق'),
    'reg_email',       jsonb_build_array('a verified e-mail address', 'بريد إلكتروني موثَّق'),
    'reg_licence',     jsonb_build_array('trade licence', 'الرخصة التجارية'),
    'reg_profile',     jsonb_build_array('company profile', 'الملف التعريفي للشركة'),
    'reg_terms',       jsonb_build_array('the signed supplier terms', 'الموافقة الموقّعة على شروط المورّد'),
    'licence_expired', jsonb_build_array('a trade licence that is in date', 'رخصة تجارية سارية المفعول'));
begin
  v_reconcile := public.fn_reconcile_doc_blocks(0);
  v_final := public.fn_doc_final_notice(7);

  for r in select l.id from public.leads l
            where l.approval_status = 'approved' and cardinality(public.fn_supplier_mandatory_six(l)) > 0 loop
    perform public.fn_sales_engineer_verifies_supplier(r.id, 'daily_recheck');
    v_rechecked := v_rechecked + 1;
  end loop;

  for r in select l.id, l.company_name, l.claimed_by, l.email, l.locale, l.exception_opened_at
             from public.leads l
            where l.approval_status = 'action_required' and l.exception_closed_at is null
              and l.exception_due_at <= now()
            order by l.id loop
    v := public.fn_sales_engineer_verifies_supplier(r.id, 'deadline');
    if v->>'approval_status' is distinct from 'action_required' then v_kept := v_kept + 1; continue; end if;

    v_missing := array(select jsonb_array_elements_text(v->'missing'));
    if cardinality(v_missing) = 0 then v_missing := array['licence_expired']; end if;
    select string_agg(v_label->k->>0, ', ' order by o), string_agg(v_label->k->>1, '، ' order by o)
      into v_items_en, v_items_ar from unnest(v_missing) with ordinality u(k, o);

    -- trg_leads_exception_invariant closes the window with outcome closed_rejected.
    update public.leads
       set approval_status = 'rejected', verified = false, approval_decided_by = 'sales_engineer',
           rejection_reason = 'registration incomplete after ' || public.fn_supplier_exception_days() || ' days: ' || array_to_string(v_missing, ', ')
     where id = r.id;

    v_ar := r.locale = 'ar';
    v_to := lower(nullif(btrim(coalesce(r.claimed_by, r.email)), ''));
    v_opened := to_char(r.exception_opened_at at time zone 'Asia/Dubai', 'DD Mon YYYY');
    if v_to is not null then
      perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'registration_closed', 'requested_by', 'sales_engineer', 'channel', 'email',
        'to_email', v_to, 'to_role', 'supplier', 'lead_id', r.id, 'lang', case when v_ar then 'ar' else 'en' end,
        'dedupe_key', 'registration_closed:' || r.id || ':' || extract(epoch from r.exception_opened_at)::bigint,
        'subject', case when v_ar then 'إغلاق طلب تسجيلكم كمورّد في QuotesDone'
                        else 'Your QuotesDone supplier registration has closed' end,
        'body', case when v_ar then
            'السادة/ ' || coalesce(r.company_name, 'المورّد') || ' المحترمين،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
            || 'فُتح طلب تسجيلكم كمورّد بتاريخ ' || v_opened || '، ولا يزال ينقصه: ' || v_items_ar || '. '
            || 'أبلغناكم أننا سنبقي الطلب مفتوحًا ' || public.fn_ar_days(public.fn_supplier_exception_days()) || '، وقد انقضت هذه المدة، لذلك أُغلق طلب التسجيل.' || chr(10) || chr(10)
            || 'يمكنكم التسجيل من جديد في أي وقت عبر https://quotesdone.com/portal، ويُفعَّل حسابكم فور اكتمال البنود الستة: '
            || 'اسم الشركة، ورقم جوال موثَّق، وبريد إلكتروني موثَّق، والرخصة التجارية، والملف التعريفي للشركة، والموافقة الموقّعة على شروط المورّد.' || chr(10) || chr(10)
            || 'وإن رأيتم أن في ذلك خطأً، فيسعدنا أن تردّوا على هذه الرسالة.' || chr(10) || chr(10) || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
          else
            'Dear ' || coalesce(r.company_name, 'supplier') || ',' || chr(10) || chr(10)
            || 'Your supplier registration was opened on ' || v_opened || ' and still needs: ' || v_items_en || '. '
            || 'We said we would keep it open for ' || public.fn_supplier_exception_days() || ' days; that time has passed, so the registration is now closed.' || chr(10) || chr(10)
            || 'You are welcome to register again at any time at https://quotesdone.com/portal. Your account activates as soon as the six required items are complete: '
            || 'company name, a verified mobile number, a verified e-mail address, your trade licence, your company profile and the signed supplier terms.' || chr(10) || chr(10)
            || 'If you believe this is wrong, reply to this e-mail.' end)));
    end if;

    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
    values ('sales_engineer', 'supplier_verification', 'auto_done', 'low',
            'Registration closed after the ' || public.fn_supplier_exception_days() || '-day window — ' || left(coalesce(r.company_name, 'supplier #' || r.id), 120),
            'No action required. The supplier was told in their language what was missing and that they may register again.',
            jsonb_build_object('supplier_id', r.id, 'decision', 'rejected', 'missing', v_missing, 'window_opened_at', r.exception_opened_at,
                               'notice', case when v_to is null then 'no e-mail on file' else 'queued through customer_support' end,
                               'source', 'fn_sales_engineer_supplier_documents_tick'),
            'leads', r.id::text);
    v_closed := v_closed + 1;
  end loop;

  v_out := jsonb_build_object('reconcile', v_reconcile, 'final_notice', v_final, 'approved_rechecked', v_rechecked,
                              'registrations_closed', v_closed, 'completed_at_deadline', v_kept);
  perform public.fn_it_duty_ran('supplier_docs', v_out);
  return v_out;
end $function$;

revoke execute on function public.fn_sales_engineer_supplier_documents_tick() from public, anon, authenticated;

-- fn_sales_engineer_ladder_step: 15 Arabic fragment(s) rewritten.
CREATE OR REPLACE FUNCTION public.fn_sales_engineer_ladder_step(p_transaction_id uuid, p_step text, p_refund_id bigint DEFAULT NULL::bigint, p_remediation_id bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t public.transactions; sup record; cust record; st jsonb; v_window int; v_chase int;
  v_final timestamptz; v_watch timestamptz; v_amt numeric; v_key text; v_days int; v_when text; v_extra jsonb;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then raise exception 'no transaction %', p_transaction_id; end if;
  select id, company_name, coalesce(claimed_by, email) as email into sup from public.leads where id = t.supplier_id;
  select id, email, full_name into cust from public.customers where id = t.customer_id;
  select refund_window_working_days, chase_after_working_days into v_window, v_chase from public.pricing_config order by id limit 1;
  v_window := coalesce(v_window, 5); v_chase := coalesce(v_chase, 3);
  st := public.fn_refund_state(t.id);
  v_final := (st->>'founder_call_due_at')::timestamptz;
  v_amt := round(coalesce(t.total_charged, t.reveal_fee, 0), 2);
  v_key := p_step || ':' || t.id || coalesce(':r' || p_remediation_id, '');
  v_days := coalesce((select (d.value #>> '{}')::int from public.decision_policy d where d.key = 'refund_final_call_watch_working_days'), 1);
  v_when := to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY');
  v_extra := jsonb_build_object('step', p_step, 'transaction_id', t.id, 'refund_id', p_refund_id, 'remediation_id', p_remediation_id);

  if p_step = 'chase' then
    v_watch := case when p_remediation_id is not null then public.fn_add_working_days(now(), 1)
                    else coalesce(v_final, public.fn_add_working_days(now(), greatest(v_window - v_chase, 1))) end;
    return public.fn_sales_engineer_writes('supplier_no_response_chase', 'supplier', sup.email, t.supplier_id, null, t.inquiry_id, t.quote_id,
      'Action needed: a customer is waiting for your response — QuotesDone reveal #' || left(t.id::text, 8),
      'Hello ' || coalesce(sup.company_name, '') || E',\n\n'
        || 'A customer paid to reveal your contact details on QuotesDone on ' || v_when || ' and has not heard from you. ' || v_chase
        || ' working days have passed. The customer is copied on this email so you can reply to all and pick it up here.' || E'\n\n'
        || 'Under the Supplier Agreement you must respond within ' || v_window || ' working days of the reveal, that is by '
        || coalesce(to_char(v_final at time zone 'Asia/Dubai', 'DD Mon YYYY'), 'the deadline')
        || '. If there is no response by then, our chief executive decides the case and the customer is refunded everything they paid (AED ' || v_amt
        || '). Under the supplier terms that amount is then recovered from your account with an administrative fee of AED 250 and interest at 9% a year until settled, and matching is paused until it is paid.' || E'\n\n'
        || 'If you have already been in touch with this customer, reply here and we will close this off.',
      'إجراء مطلوب: عميل بانتظار ردّكم — QuotesDone',
      'سدّد أحد العملاء رسوم الكشف عن بيانات التواصل معكم بتاريخ ' || v_when || ' ولم يتلقَّ منكم ردًّا بعد مرور ' || v_chase || ' أيام عمل، والعميل مُدرَج في نسخة هذه الرسالة. '
        || 'وتُلزم اتفاقية المورّد بالرد خلال ' || v_window || ' أيام عمل من تاريخ الكشف، وإلا فسيُردّ إلى العميل كامل ما دفعه (' || v_amt
        || ' درهم)، ويُسترد المبلغ من حسابكم مع رسوم إدارية قدرها 250 درهمًا وفائدة 9% سنويًا حتى السداد. وإن كنتم قد تواصلتم مع العميل، فيُرجى الرد على هذه الرسالة.',
      array_remove(array[cust.email], null), v_key, v_watch, v_extra);

  elsif p_step = 'final_call' then
    v_watch := public.fn_add_working_days(now(), v_days);
    return public.fn_sales_engineer_writes('refund_final_notice', 'supplier', sup.email, t.supplier_id, null, t.inquiry_id, t.quote_id,
      'Final call: a customer is still waiting — QuotesDone reveal #' || left(t.id::text, 8),
      'Hello ' || coalesce(sup.company_name, '') || E',\n\n'
        || 'This is our final call about the customer who paid to reveal your contact details on ' || v_when
        || '. The ' || v_window || ' working days the Supplier Agreement allows have passed with no response from you, to the customer or to our reminder.' || E'\n\n'
        || 'If we do not hear from you by ' || to_char(v_watch at time zone 'Asia/Dubai', 'DD Mon YYYY')
        || ', the customer is refunded everything they paid (AED ' || v_amt || ') and that amount is recovered from your account with an administrative fee of AED 250 and interest at 9% a year. '
        || 'Reply to this email, message the customer in your portal, or answer us on WhatsApp — any of them stops this.',
      'نداء أخير: عميل لا يزال بانتظار ردّكم — QuotesDone',
      'هذا نداؤنا الأخير بشأن العميل الذي كشف عن بيانات التواصل معكم بتاريخ ' || v_when || '، وقد انقضت أيام العمل المحددة دون ردّ منكم. '
        || 'فإن لم يصلنا ردّكم حتى ' || to_char(v_watch at time zone 'Asia/Dubai', 'DD Mon YYYY') || ' فسيُردّ إلى العميل كامل ما دفعه (' || v_amt
        || ' درهم)، ويُسترد المبلغ من حسابكم مع رسوم إدارية قدرها 250 درهمًا وفائدة 9% سنويًا. ويكفي أي ردّ منكم عبر البريد الإلكتروني أو البوابة أو واتساب لإيقاف ذلك.',
      array_remove(array[cust.email], null), v_key, v_watch, v_extra);

  elsif p_step = 'customer_proof' then
    return public.fn_sales_engineer_writes('refund_proof_request', 'customer', cust.email, null, t.customer_id, t.inquiry_id, t.quote_id,
      'Anything you sent the supplier helps your refund case',
      'Hello ' || coalesce(nullif(btrim(cust.full_name), ''), 'there') || E',\n\n'
        || 'If you tried to reach the supplier yourself, forwarding that email to supplier@mail.quotesdone.com (or replying to it with that address in copy) puts it on your case and can help us close it faster. '
        || 'It is optional: it is never a condition of the refund, and you do not need to do anything for your case to be decided.',
      'مراسلاتكم مع المورّد تدعم حالة الاسترداد',
      'إن سبق أن تواصلتم مع المورّد بأنفسكم، فإن إعادة توجيه تلك الرسالة إلى supplier@mail.quotesdone.com (أو الرد عليها مع إضافة هذا العنوان في النسخة) تضمّها إلى حالتكم، وقد تساعدنا على إنهائها أسرع. هذا اختياري وليس شرطًا للاسترداد، ولا يلزمكم أي إجراء ليُبتّ في حالتكم.',
      '{}', v_key, null, v_extra);
  end if;
  raise exception 'no such ladder step %', p_step;
end $function$;

revoke execute on function public.fn_sales_engineer_ladder_step(uuid,text,bigint,bigint) from public, anon, authenticated;

-- fn_sales_engineer_writes_money_notice: 8 Arabic fragment(s) rewritten.
CREATE OR REPLACE FUNCTION public.fn_sales_engineer_writes_money_notice(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  a public.agent_actions; d jsonb; v_notice text; v_sup record; v_tpl jsonb; v_vars jsonb;
  v_sub_en text; v_body_en text; v_sub_ar text; v_body_ar text; v_req bigint; v_msg text;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  -- THE KIND IS THE CONVERSATION'S TYPE (public.seat_handoff_kind, #648): fn_seat_handoff_act dispatches
  -- each of the five rows inserted below to this routine, and the type alone says which notice it is.
  v_notice := case a.detail->>'type'
                when 'nonresponse.charge_reminder'  then 'charge_reminder'
                when 'nonresponse.final_demand'     then 'final_demand'
                when 'subscription.renewal_reminder' then 'subscription_renewal'
                when 'subscription.dunning'         then 'subscription_dunning'
                when 'subscription.payment_failed'  then 'subscription_payment_failed' end;
  if not found or a.agent <> 'sales_engineer' or v_notice is null then
    raise exception 'fn_sales_engineer_writes_money_notice: % is not one of the accountant''s notice kinds', p_id;
  end if;
  d := a.detail;
  select l.id, l.company_name, coalesce(l.claimed_by, l.email) email into v_sup
    from public.leads l where l.id = (d->>'supplier_id')::bigint;
  if coalesce(v_sup.email, '') not like '%@%' then
    return jsonb_build_object('supplier_reachable', false, 'notice', v_notice);
  end if;
  v_vars := d || jsonb_build_object('company', coalesce(v_sup.company_name, ''),
                                   'reveal_ref', left(coalesce(d->>'transaction_id', ''), 8));

  if v_notice in ('charge_reminder', 'final_demand') then
    -- THE WORDING IS THE LEGAL DOCUMENT'S, NOT THIS FILE'S (founder, 14 Sep 2026: "make sure the form
    -- and the wordings is done correctly"). No template row, no send: the handoff fails and says why.
    select value into v_tpl from public.decision_policy
     where key = case v_notice when 'charge_reminder' then 'supplier_charge_reminder_template'
                               else 'supplier_charge_final_demand_template' end;
    if v_tpl is null or coalesce(v_tpl->>'body_en', '') = '' then
      raise exception 'no % template in decision_policy: the wording comes from docs/legal/SUPPLIER_CHARGE_RECOVERY_UAE.md and has not been configured', v_notice;
    end if;
    v_sub_en := public.fn_render_template(v_tpl->>'subject_en', v_vars);
    v_body_en := public.fn_render_template(v_tpl->>'body_en', v_vars);
    v_sub_ar := public.fn_render_template(v_tpl->>'subject_ar', v_vars);
    v_body_ar := public.fn_render_template(v_tpl->>'body_ar', v_vars);
    v_msg := 'nonresponse_' || v_notice;
  elsif v_notice = 'subscription_renewal' then
    v_sub_en := 'Your QuotesDone supplier subscription renews on ' || (d->>'renews_on');
    v_body_en := 'Dear ' || coalesce(v_sup.company_name, 'there') || E',\n\nYour annual QuotesDone supplier subscription is paid until '
      || (d->>'paid_until') || '. The renewal of ' || coalesce(d->>'currency', 'AED') || ' ' || (d->>'fee')
      || ' falls due on ' || (d->>'renews_on') || E'.\n\nYou can renew from the Billing section of your supplier portal: https://quotesdone.com/suppliers. Stripe issues the invoice for the payment.\n\nYou keep paying no commission on the jobs you win.';
    v_sub_ar := 'موعد تجديد اشتراككم كمورّد في QuotesDone: ' || (d->>'renews_on');
    v_body_ar := 'اشتراككم السنوي مدفوع حتى ' || (d->>'paid_until') || '، ويستحق التجديد بقيمة ' || (d->>'fee')
      || ' درهم في ' || (d->>'renews_on') || '. ويمكنكم التجديد من قسم الفواتير في بوابة المورّد.';
    v_msg := 'subscription_renewal_reminder';
  elsif v_notice = 'subscription_dunning' then
    v_sub_en := 'Reminder ' || (d->>'dunning_no') || ': your QuotesDone subscription is unpaid';
    v_body_en := 'Dear ' || coalesce(v_sup.company_name, 'there') || E',\n\nYour annual supplier subscription of '
      || coalesce(d->>'currency', 'AED') || ' ' || (d->>'fee') || ' fell due on ' || (d->>'due_on') || ' and is still unpaid ('
      || (d->>'days_overdue') || E' days).\n\nPlease settle it from the Billing section of your supplier portal: https://quotesdone.com/suppliers. '
      || E'Until it is settled your profile does not receive new customer requests.\n\nIf you have already paid, reply to this email and we will check it against the payment record.';
    v_sub_ar := 'تذكير ' || (d->>'dunning_no') || ': اشتراككم في QuotesDone لم يُسدَّد بعد';
    v_body_ar := 'استحق اشتراككم السنوي كمورّد بقيمة ' || (d->>'fee') || ' درهم في ' || (d->>'due_on') || ' ولم يُسدَّد بعد ('
      || public.fn_ar_days((d->>'days_overdue')::int) || '). يُرجى السداد من قسم الفواتير في بوابة المورّد، علمًا بأن ملفكم لن يتلقى طلبات جديدة حتى السداد.';
    v_msg := 'subscription_dunning';
  elsif v_notice = 'subscription_payment_failed' then
    v_sub_en := 'Your QuotesDone subscription payment did not go through';
    v_body_en := 'Dear ' || coalesce(v_sup.company_name, 'there') || E',\n\nYour payment for the annual supplier subscription did not complete, and nothing was charged. '
      || E'You can try again at any time from the Billing section of your supplier portal: https://quotesdone.com/suppliers. If the card was declined, your bank can tell you why, and a different card also works.';
    v_sub_ar := 'لم يكتمل دفع اشتراككم في QuotesDone';
    v_body_ar := 'تعذّر إتمام دفع الاشتراك السنوي، ولم يُخصم أي مبلغ. يمكنكم إعادة المحاولة من قسم الفواتير في بوابة المورّد.';
    v_msg := 'subscription_payment_failed';
  else
    raise exception 'fn_sales_engineer_writes_money_notice: no words for notice %', v_notice;
  end if;

  if v_body_en ~ '\{\{[a-z_]+\}\}' or coalesce(v_body_ar, '') ~ '\{\{[a-z_]+\}\}' then
    raise exception 'notice % for handoff % still carries an unfilled placeholder; nothing was sent', v_notice, p_id;
  end if;
  -- A RECOVERY DOCUMENT IS SIGNED IN THE FOUNDER'S NAME (founder, 14 Sep 2026: "with stamp and signature
  -- of course"), so every one issued is logged before it leaves: what, which version, its hash, to whom.
  if v_notice in ('charge_reminder', 'final_demand') then
    insert into public.accountant_issued_document (document_kind, template_key, template_version, content_sha256, recipient,
      supplier_id, due_id, handoff_id, signed_as, stamp_required, signature_required)
    values (v_notice, case v_notice when 'charge_reminder' then 'supplier_charge_reminder_template' else 'supplier_charge_final_demand_template' end,
            coalesce(v_tpl->>'version', 'unversioned'),
            encode(sha256(convert_to(coalesce(v_sub_en, '') || E'\n' || v_body_en || E'\n' || coalesce(v_sub_ar, '') || E'\n' || coalesce(v_body_ar, ''), 'UTF8')), 'hex'),
            v_sup.email, v_sup.id, (d->>'due_id')::bigint, p_id, 'founder', true, true);
  end if;
  v_req := public.fn_sales_engineer_writes(v_msg, 'supplier', v_sup.email, v_sup.id, null,
    (d->>'inquiry_id')::uuid, (d->>'quote_id')::uuid, v_sub_en, v_body_en, v_sub_ar, v_body_ar,
    '{}', v_msg || ':' || (d->>'subject_id'), null,
    jsonb_build_object('transaction_id', d->>'transaction_id', 'due_id', d->>'due_id', 'notice', v_notice));
  return jsonb_build_object('notice', v_notice, 'delivery_request', v_req);
end $function$;

revoke execute on function public.fn_sales_engineer_writes_money_notice(bigint) from public, anon, authenticated;

-- fn_supplier_certifications: 6 Arabic fragment(s) rewritten.
CREATE OR REPLACE FUNCTION public.fn_supplier_certifications(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with docs(key, label, label_ar, impact, impact_why, impact_why_ar) as (values
      ('trade_licence',     'Trade licence',              'الرخصة التجارية',           'critical', 'Approval is impossible without it — the licence gate refuses every profile that has none.', 'لا يُعتمد أي حساب من دونها، ويُرفض كل ملف لا يتضمنها.'),
      ('insurance',         'Insurance',                  'التأمين',                   'high',     'Many customers will not award work to an uninsured supplier.', 'كثير من العملاء لا يُرسون الأعمال على مورّد غير مؤمَّن عليه.'),
      ('iso',               'ISO certification',          'شهادة ISO',                 'medium',   'Strengthens your capability score and unlocks quality-gated requests.', 'تعزّز تقييم قدراتكم وتتيح لكم الطلبات المشروطة بمعايير الجودة.'),
      ('manufacturer_auth', 'Manufacturer authorisation', 'تفويض الشركة المصنّعة',     'medium',   'Proves you are authorised for the brands you carry.', 'تُثبت اعتمادكم لدى العلامات التجارية التي تورّدونها.'),
      ('establishment',     'Establishment card (EGR)',   'بطاقة المنشأة (EGR)',       'low',      'Administrative record. Does not gate work.', 'مستند إداري لا يؤثر في استلام الأعمال.')
  ),
  held as (
    select d.*, h.path, h.expiry, h.source
    from docs d left join public.fn_supplier_document_home(p_lead_id) h on h.key = d.key
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'certifications', coalesce((select jsonb_agg(jsonb_build_object(
        'key', h.key, 'label', h.label, 'label_ar', h.label_ar,
        'held', h.path is not null,
        'source', h.source,
        'expiry', h.expiry,
        'days_left', case when h.expiry is null then null else (h.expiry - current_date) end,
        'document_status', case
          when h.path is null then 'missing'
          when h.expiry is null then 'valid'
          when h.expiry < current_date then 'expired'
          when h.expiry < current_date + 60 then 'expiring'
          else 'valid' end,
        'impact_level', h.impact,
        'impact_why', h.impact_why, 'impact_why_ar', h.impact_why_ar)
      order by case h.impact when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end, h.label)
      from held h), '[]'::jsonb),
    'impact_basis', 'impact_level is a stated QuotesDone policy about what each document gates — not a number derived from your history',
    'impact_basis_ar', 'يعكس مستوى الأثر سياسة QuotesDone المعلنة بشأن ما يتيحه كل مستند، وليس رقمًا مستخلصًا من سجلكم',
    'summary', jsonb_build_object(
      'held', (select count(*) from held where path is not null),
      'total', (select count(*) from held),
      'expired', (select count(*) from held where path is not null and expiry is not null and expiry < current_date),
      'expiring', (select count(*) from held where path is not null and expiry is not null
                     and expiry >= current_date and expiry < current_date + 60),
      'blocking_missing', (select count(*) from held where path is null and impact = 'critical'))
  );
$function$;

revoke execute on function public.fn_supplier_certifications(bigint) from public, anon, authenticated;

-- fn_supplier_tier: 9 Arabic fragment(s) rewritten.
CREATE OR REPLACE FUNCTION public.fn_supplier_tier(p_lead_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with l as (
    select coalesce(verified, false) verified, rv_response_rate
      from public.leads where id = p_lead_id
  ),
  q as (
    select count(*)::int submitted,
           count(*) filter (where status = 'won')::int won_by_status
      from public.quotes where supplier_id = p_lead_id
  ),
  h as (
    select count(*)::int hired from public.inquiries where hired_supplier_id = p_lead_id
  ),
  s as (
    select (select submitted from q) submitted,
           greatest((select won_by_status from q), (select hired from h)) won,
           (select rv_response_rate from l) response_rate,
           -- NULL until a verified supplier has been reviewed: an unrated supplier is unrated.
           case when (select verified from l)
                then (select round(avg(rating)::numeric * 20, 1) from public.reviews where supplier_id = p_lead_id)
                else null end quality_rating
  ),
  -- ACTIVITY IS THE GATE. A supplier who has never quoted has no performance to measure.
  a as (select coalesce((select submitted from s), 0) > 0 active),
  t as (
    select case
      when not (select active from a) then 'unranked'
      when (select won from s) >= 10 and coalesce((select quality_rating from s), 0) >= 85 then 'platinum'
      when (select won from s) >= 5  and coalesce((select quality_rating from s), 0) >= 70 then 'gold'
      when (select won from s) >= 1                                                        then 'silver'
      else 'bronze'
    end tier
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'tier', (select tier from t),
    -- available:false is the difference between "we ranked you low" and "we cannot rank you yet".
    'available', (select active from a),
    'basis', case when (select active from a)
                  then 'quotes won and quality rating, from your quotes and reviews on QuotesDone'
                  else 'no quote has been submitted yet, so there is nothing to rank — this is not a low score' end,
    'basis_ar', case when (select active from a)
                  then 'الأعمال التي فزتم بها وتقييم الجودة، استنادًا إلى عروضكم وتقييماتكم على QuotesDone'
                  else 'لم تُقدَّم أي عروض أسعار بعد، فلا يوجد ما يُصنَّف، وهذا لا يعني تقييمًا منخفضًا' end,
    'ladder', jsonb_build_array(
      jsonb_build_object('tier','bronze',  'needs','submit your first quote',                              'needs_ar','قدّم أول عرض سعر'),
      jsonb_build_object('tier','silver',  'needs','win 1 job',                                            'needs_ar','فُز بعمل واحد'),
      jsonb_build_object('tier','gold',    'needs','win 5 jobs and hold a 70% quality rating',             'needs_ar','فُز بخمسة أعمال مع الحفاظ على تقييم جودة 70%'),
      jsonb_build_object('tier','platinum','needs','win 10 jobs and hold an 85% quality rating',           'needs_ar','فُز بعشرة أعمال مع الحفاظ على تقييم جودة 85%')
    ),
    'progress', jsonb_build_object(
      'quotes_submitted', (select submitted from s),
      'quotes_won', (select won from s),
      'quality_rating', (select quality_rating from s),
      'response_rate', (select response_rate from s)
    ),
    -- THE TIER DOES NOT AFFECT MATCHING. Founder, 2026-08-08: "a tier shouldnt effect a match."
    'benefits_active', false,
    'affects_matching', false,
    'benefits_note', 'Your tier never affects which work you are matched to, how you rank in search, '
      || 'or whether you are shown as preferred. Every supplier is matched on fit alone. '
      || 'This is a record of your track record, not a queue position.',
    'benefits_note_ar', 'لا يؤثر تصنيفكم إطلاقًا في الأعمال التي تُطابَقون معها، ولا في ترتيبكم في نتائج البحث، '
      || 'ولا في إبرازكم مورّدًا مفضّلًا؛ فكل مورّد يُطابَق وفق مدى الملاءمة وحدها. '
      || 'إنه سجلّ لأدائكم، لا ترتيب في طابور.'
  );
$function$;

revoke execute on function public.fn_supplier_tier(bigint) from public, anon, authenticated;

-- fn_support_knowledge_gap: 2 Arabic fragment(s) rewritten.
CREATE OR REPLACE FUNCTION public.fn_support_knowledge_gap(p_question text, p_refusal text, p_surface text DEFAULT 'website_widget'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_norm text;
  v_gap  public.sales_knowledge_gap%rowtype;
  v_task bigint;
  v_asks int;
begin
  if coalesce(btrim(p_question), '') = '' then
    return jsonb_build_object('ok', false, 'reason', 'empty_question');
  end if;

  -- THE QUESTION ARRIVED WITH ITS SCRIPT STRIPPED, so there is nothing here to answer and
  -- nothing to file. org_tasks 578945 is what happens without this branch: a task that sat in
  -- the work queue for nine days titled in question marks, asked four times, with no reading of
  -- it possible by anyone.
  --
  -- BOTH KEYS CARRY BOTH LANGUAGES. site_assistant picks between reply_en and reply_ar with
  -- `/[؀-ۿ]/.test(message) || uiLang === 'ar'` — it reads the script of the message, and on this
  -- branch the script is exactly what was destroyed, so a stripped Arabic message is pure ASCII
  -- and that test says "English" for the one visitor who needs the Arabic. The language cannot be
  -- known here, so it is not guessed: whichever key the caller reads, the person gets both
  -- paragraphs. This is the fix for the defect the comment above would otherwise only describe.
  if public.fn_text_lost_its_script(p_question) then
    return jsonb_build_object(
      'ok', false, 'reason', 'text_lost_its_script',
      'reply_en', public.fn_text_did_not_survive_reply('en') || E'\n\n'
                  || public.fn_text_did_not_survive_reply('ar'),
      'reply_ar', public.fn_text_did_not_survive_reply('ar') || E'\n\n'
                  || public.fn_text_did_not_survive_reply('en'));
  end if;

  v_norm := left(lower(regexp_replace(btrim(p_question), '\s+', ' ', 'g')), 400);
  select * into v_gap from public.sales_knowledge_gap where question_norm = v_norm;

  if not found then
    insert into public.org_tasks (title, detail, status, tier, action_class, assigned_agent,
                                  priority, requires_evidence, needs_founder)
    values (
      left('Answer an unanswered support question: ' || btrim(p_question), 160),
      'Someone who was NOT signed in asked this on the ' || coalesce(nullif(btrim(p_surface), ''), 'website_widget')
        || ' and Customer Support could not source an answer from company knowledge.' || E'\n\n'
        || 'QUESTION: ' || btrim(p_question) || E'\n'
        || 'REFUSAL: ' || coalesce(nullif(btrim(p_refusal), ''), 'no_grounded_answer') || E'\n\n'
        || 'THERE IS NO ESCALATION TO A HUMAN -- founder ruling, 9 Sep 2026. This task IS what '
        || 'happens instead, and it is the only thing that happens.' || E'\n\n'
        || 'DONE MEANS: the answer exists in a corpus fn_support_corpus_search reads (company_faq, '
        || 'support_knowledge, ops_knowledge) and this question returns it. Then set '
        || 'sales_knowledge_gap.status to knowledge_added.',
      'assigned', 'advisory', 'knowledge_gap', 'customer_support', 3, true, false)
    returning id into v_task;

    insert into public.sales_knowledge_gap (question_norm, question, refusal, nearest_corpus, task_id)
    values (v_norm, left(btrim(p_question), 2000),
            coalesce(nullif(btrim(p_refusal), ''), 'no_grounded_answer'),
            'support_corpus', v_task);
    v_asks := 1;
  else
    v_task := v_gap.task_id;
    v_asks := v_gap.asks + 1;
    update public.sales_knowledge_gap
       set asks = asks + 1, last_asked_at = now(),
           refusal = coalesce(nullif(btrim(p_refusal), ''), refusal)
     where id = v_gap.id;
    -- Asked repeatedly is the definition of urgent, exactly as on the sales side.
    update public.org_tasks
       set priority = least(9, greatest(priority, 3 + v_gap.asks)), updated_at = now()
     where id = v_task and status not in ('done', 'cancelled');
  end if;

  return jsonb_build_object(
    'ok', true, 'task_id', v_task, 'asks', v_asks,
    'reply_en', 'I do not have a sourced answer to that yet, and I will not guess at it. I have '
      || 'recorded your question exactly as you asked it so it gets answered properly. If you need '
      || 'it now, call or WhatsApp +971 50 931 9355 (Sun-Thu, 9am-6pm GST) or email '
      || 'management@quotesdone.com.',
    'reply_ar', 'لا تتوفر لديّ إجابة موثّقة عن ذلك حتى الآن، ولا أودّ التخمين. سجّلتُ سؤالكم كما كتبتموه '
      || 'تمامًا ليُجاب عنه إجابة دقيقة. وإن احتجتم إلى الإجابة الآن، يمكنكم الاتصال أو المراسلة عبر '
      || 'واتساب:' || E'\n' || '+971 50 931 9355' || E'\n' || 'أو البريد الإلكتروني:' || E'\n'
      || 'management@quotesdone.com');
end
$function$;

revoke execute on function public.fn_support_knowledge_gap(text,text,text) from public, anon, authenticated;

-- fn_text_did_not_survive_reply: 3 Arabic fragment(s) rewritten.
CREATE OR REPLACE FUNCTION public.fn_text_did_not_survive_reply(p_lang text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when lower(coalesce(p_lang, 'en')) = 'ar' then
      'وصلتني رسالتكم وقد تحوّلت حروفها إلى علامات استفهام، فتعذّرت عليّ قراءة سؤالكم. '
      || 'لا خطأ في سؤالكم، وإنما لم يصل النص سليمًا عبر الاتصال. يُرجى إعادة إرسال الرسالة. '
      || 'وإن تكرر ذلك، يمكنكم الاتصال أو المراسلة عبر واتساب:' || E'\n'
      || E'‎' || '+971 50 931 9355' || E'\n'
      || '(من الأحد إلى الخميس، من 9 صباحًا حتى 6 مساءً بتوقيت الإمارات)' || E'\n'
      || 'أو البريد الإلكتروني:' || E'\n' || 'management@quotesdone.com'
    else
      'Your message reached me with its characters replaced by question marks, so I cannot read '
      || 'what you asked. Nothing is wrong with your question — it did not survive the connection. '
      || 'Please send it again. If it keeps happening, call or WhatsApp +971 50 931 9355 '
      || '(Sun-Thu, 9am-6pm GST) or email management@quotesdone.com.'
  end;
$function$;

revoke execute on function public.fn_text_did_not_survive_reply(text) from public, anon, authenticated;

-- fn_supplier_collaboration_incident: 10 Arabic fragment(s) rewritten.
CREATE OR REPLACE FUNCTION public.fn_supplier_collaboration_incident(p_lead bigint, p_inquiry uuid, p_quote uuid, p_hold bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_n int; v_held timestamptz; v_warn int := 0; v_hold int := 0;
        v_ref text := upper(left(coalesce(p_inquiry::text, ''), 8));
begin
  insert into public.supplier_collaboration (lead_id) values (p_lead) on conflict (lead_id) do nothing;
  update public.supplier_collaboration
     set consecutive_ignored = consecutive_ignored + 1, total_ignored = total_ignored + 1, last_incident_at = now(), updated_at = now()
   where lead_id = p_lead returning consecutive_ignored into v_n;
  insert into public.supplier_collaboration_event (lead_id, kind, inquiry_id, quote_id, hold_id, consecutive_after, actor, detail)
  values (p_lead, 'ignored_hold', p_inquiry, p_quote, p_hold, v_n, 'sales_engineer', jsonb_build_object('rfq', v_ref));

  if v_n = 2 then
    insert into public.support_case (case_ref, party_kind, party_id, inquiry_ref, subject, owner_role_id)
    values ('SE-COLLAB-' || p_lead || '-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'), 'supplier', p_lead::text, p_inquiry::text,
            'From the sales engineer: this supplier has left 2 held quotes unanswered in a row (the customer decided before the missing details came). The warning was sent on email and WhatsApp; a third in a row puts them on matching hold.',
            'customer_support');
    v_warn := public.fn_supplier_notice(p_lead, 'supplier_collaboration_warning',
      'A note about your recent quotes on QuotesDone',
      $en$Dear {company},

Thank you for quoting on QuotesDone. We value the time you put into every request.

On your last two requests, your quotation was placed on hold because some details the customer needs to compare quotes fairly were missing (for example the exact material specification, the delivery date, installation or warranty), and the customer made their decision before those details arrived. Complete details help customers choose with confidence, and they give your offer the best chance of being selected.

Whenever a quote is on hold, you can fill in the missing details directly on your supplier portal (we then prepare the standardised quotation for your approval), or upload a revised quotation. It only takes a few minutes.

To keep matching fair for customers, if a third consecutive quotation is still on hold when the customer decides, we will pause new requests to your company until we have spoken with you. We would much rather keep working together, so please reach out if anything is making it difficult to respond.

With thanks,
QuotesDone sales engineer$en$,
      'ملاحظة بشأن عروضكم الأخيرة على QuotesDone',
      $ar$السادة/ {company} المحترمين،
تحية طيبة وبعد،

نشكركم على تقديم عروض الأسعار عبر QuotesDone، ونقدّر الوقت الذي تخصصونه لكل طلب.

في آخر طلبين، عُلّق عرضكم لنقص بعض التفاصيل التي يحتاجها العميل ليقارن العروض بإنصاف (مثل المواصفات الدقيقة للمواد أو موعد التسليم أو التركيب أو الضمان)، واتخذ العميل قراره قبل وصول هذه التفاصيل. فاكتمال التفاصيل يساعد العملاء على الاختيار بثقة، ويمنح عرضكم أفضل فرصة للفوز.

وعند تعليق أي عرض، يمكنكم استكمال التفاصيل الناقصة مباشرة من بوابة المورّدين (ونُعدّ لكم العرض بالصيغة الموحّدة لاعتماده)، أو رفع عرض معدّل، ولا يستغرق ذلك سوى دقائق.

وحرصًا على عدالة المطابقة للعملاء، إذا بقي عرض ثالث على التوالي معلّقًا عند اتخاذ العميل قراره، فسنوقف مؤقتًا إرسال الطلبات الجديدة إلى شركتكم إلى حين التحدث معكم. ونحرص كثيرًا على استمرار تعاوننا، فلا تترددوا في التواصل معنا إن كان هناك ما يصعّب عليكم الرد.

وتفضلوا بقبول فائق الاحترام والتقدير،
مهندس المبيعات في QuotesDone$ar$,
      p_inquiry, p_quote);
    update public.supplier_collaboration set warned_at = now(), updated_at = now() where lead_id = p_lead;
    insert into public.supplier_collaboration_event (lead_id, kind, inquiry_id, quote_id, hold_id, consecutive_after, actor, detail)
    values (p_lead, 'warning_sent', p_inquiry, p_quote, p_hold, v_n, 'sales_engineer', jsonb_build_object('delivery_requests', v_warn));

  elsif v_n >= 3 then
    select collaboration_hold_at into v_held from public.leads where id = p_lead;
    if v_held is null then
      update public.leads set collaboration_hold_at = now(), matching_blocked = true, matching_block_reason = 'collaboration_hold' where id = p_lead;
      update public.supplier_collaboration set held_at = now(), updated_at = now() where lead_id = p_lead;
      insert into public.support_case (case_ref, party_kind, party_id, inquiry_ref, subject, owner_role_id)
      values ('SE-HOLD-' || p_lead || '-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'), 'supplier', p_lead::text, p_inquiry::text,
              'From the sales engineer: supplier put on matching hold after 3 held quotes in a row were left unanswered. New requests are no longer matched to them. Lifting it is the founder''s decision after he calls the supplier (founder_instruction #160).',
              'customer_support');
      v_hold := public.fn_supplier_notice(p_lead, 'supplier_matching_hold',
        'New requests to your company are paused on QuotesDone',
        $en$Dear {company},

Thank you for your time on QuotesDone. On your last three consecutive requests, your quotation was still on hold for missing details when the customer made their decision. As we mentioned in our earlier message, we have therefore paused new requests to your company for now. Your account, your existing quotations and any revealed jobs are not affected.

Our team will be in touch to understand what happened and how we can make responding easier. You are welcome to reply to this message at any time.

With thanks,
QuotesDone sales engineer$en$,
        'إيقاف مؤقت لإرسال الطلبات الجديدة إلى شركتكم على QuotesDone',
        $ar$السادة/ {company} المحترمين،
تحية طيبة وبعد،

نشكركم على وقتكم في QuotesDone. في آخر ثلاثة طلبات متتالية، كان عرضكم لا يزال معلّقًا لنقص في التفاصيل عندما اتخذ العميل قراره؛ لذلك، وكما أشرنا في رسالتنا السابقة، أوقفنا مؤقتًا إرسال الطلبات الجديدة إلى شركتكم. ولا يتأثر بذلك حسابكم ولا عروضكم الحالية ولا الأعمال التي كُشف عنها.

سيتواصل معكم فريقنا للوقوف على ما حدث وبحث سبل تيسير ردّكم على الطلبات، ويسعدنا أن تردّوا على هذه الرسالة في أي وقت.

وتفضلوا بقبول فائق الاحترام والتقدير،
مهندس المبيعات في QuotesDone$ar$,
        p_inquiry, p_quote);
      insert into public.supplier_collaboration_event (lead_id, kind, inquiry_id, quote_id, hold_id, consecutive_after, actor, detail)
      values (p_lead, 'matching_hold', p_inquiry, p_quote, p_hold, v_n, 'sales_engineer', jsonb_build_object('delivery_requests', v_hold));
    end if;
  end if;
  return jsonb_build_object('lead_id', p_lead, 'consecutive', v_n, 'warning_requests', v_warn, 'hold_requests', v_hold);
end $function$;

revoke execute on function public.fn_supplier_collaboration_incident(bigint,uuid,uuid,bigint) from public, anon, authenticated;

-- fn_supplier_collaboration_hold_lift: 3 Arabic fragment(s) rewritten.
CREATE OR REPLACE FUNCTION public.fn_supplier_collaboration_hold_lift(p_lead bigint, p_founder_instruction bigint, p_why text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare fi record; l record; v_text text; v_n int;
begin
  if coalesce(btrim(p_why), '') = '' then raise exception 'lifting a matching hold needs the reason the founder gave'; end if;
  select id, instruction, coalesce(subject, '') as subject, coalesce(note, '') as note into fi from public.founder_instruction where id = p_founder_instruction;
  if not found then raise exception 'no founder_instruction %: only the founder lifts a matching hold (#160)', p_founder_instruction; end if;
  select id, company_name, collaboration_hold_at, matching_block_reason into l from public.leads where id = p_lead;
  if not found then raise exception 'no supplier %', p_lead; end if;
  v_text := lower(fi.instruction || ' ' || fi.subject || ' ' || fi.note);
  if not (v_text ~ ('(^|[^0-9])' || p_lead::text || '([^0-9]|$)')
          or (length(btrim(coalesce(l.company_name, ''))) >= 3 and position(lower(btrim(l.company_name)) in v_text) > 0)) then
    raise exception 'founder_instruction % does not name supplier % (%): the founder''s instruction must name who is lifted', p_founder_instruction, p_lead, l.company_name;
  end if;
  if l.collaboration_hold_at is null then raise exception 'supplier % is not on a collaboration matching hold', p_lead; end if;

  perform set_config('app.collaboration_hold_lift', 'founder', true);
  update public.leads
     set collaboration_hold_at = null,
         matching_blocked = case when matching_block_reason = 'collaboration_hold' then false else matching_blocked end,
         matching_block_reason = case when matching_block_reason = 'collaboration_hold' then null else matching_block_reason end
   where id = p_lead;
  perform set_config('app.collaboration_hold_lift', '', true);

  update public.supplier_collaboration set consecutive_ignored = 0, lifted_at = now(), updated_at = now() where lead_id = p_lead;
  select coalesce(max(consecutive_ignored), 0) into v_n from public.supplier_collaboration where lead_id = p_lead;
  insert into public.supplier_collaboration_event (lead_id, kind, consecutive_after, founder_instruction_id, actor, detail)
  values (p_lead, 'hold_lifted', v_n, p_founder_instruction, 'founder',
          jsonb_build_object('why', p_why, 'executed_by', session_user, 'at', now()));
  perform public.fn_supplier_notice(p_lead, 'supplier_matching_hold_lifted',
    'Welcome back to QuotesDone',
    $en$Dear {company},

Thank you for speaking with us. We have resumed new requests to your company, and matching requests will start reaching you again. Whenever a quote needs more detail, you can complete it on your supplier portal in a few minutes.

We look forward to working with you.

With thanks,
QuotesDone sales engineer$en$,
    'مرحبًا بعودتكم إلى QuotesDone',
    $ar$السادة/ {company} المحترمين،
تحية طيبة وبعد،

نشكركم على تواصلكم معنا. وقد استأنفنا إرسال الطلبات الجديدة إلى شركتكم، وستصلكم الطلبات المطابقة مجددًا. وعندما يحتاج أي عرض إلى تفاصيل إضافية، يمكنكم استكمالها من بوابة المورّدين خلال دقائق.

نتطلع إلى العمل معكم.

وتفضلوا بقبول فائق الاحترام والتقدير،
مهندس المبيعات في QuotesDone$ar$);
  return jsonb_build_object('ok', true, 'lead_id', p_lead, 'founder_instruction', p_founder_instruction, 'consecutive_ignored', v_n);
end $function$;

revoke execute on function public.fn_supplier_collaboration_hold_lift(bigint,bigint,text) from public, anon, authenticated;

-- fn_notify_supplier: 4 Arabic fragment(s) rewritten.
CREATE OR REPLACE FUNCTION public.fn_notify_supplier(p_transaction uuid, p_actor text DEFAULT 'customer'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t record; st jsonb; sup record; cust_email text; v_window int; v_final_at timestamptz; v_amt numeric; v_req bigint;
begin
  st := public.fn_refund_state(p_transaction);
  if st ? 'error' then return st; end if;
  if (st->>'can_notify') <> 'true' then
    return jsonb_build_object('ok', false, 'error', 'not_available', 'state', st->>'state', 'notify_available_at', st->>'notify_available_at');
  end if;
  select * into t from public.transactions where id = p_transaction;
  select company_name, coalesce(claimed_by, email) as email into sup from public.leads where id = t.supplier_id;
  select email into cust_email from public.customers where id = t.customer_id;
  v_window   := coalesce((st->>'refund_window_working_days')::int, 5);
  v_final_at := (st->>'founder_call_due_at')::timestamptz;
  v_amt      := round(coalesce(t.total_charged, t.reveal_fee, 0), 2);

  -- The customer's own formal notice, in the sales engineer's voice, delivered by support. It does
  -- NOT move the ladder: the window is fixed from payment (founder, 6 Sep 2026).
  v_req := public.fn_sales_engineer_writes('reveal_no_response_notice', 'supplier', sup.email, t.supplier_id, null, t.inquiry_id, t.quote_id,
    'Awaiting your response — QuotesDone reveal #' || left(t.id::text, 8),
    'Hello,' || E'\n\n'
      || 'A customer paid to reveal your contact details on QuotesDone on ' || to_char(t.revealed_at at time zone 'Asia/Dubai', 'DD Mon YYYY')
      || ' and has not yet heard from you. The customer is copied on this email so you can simply reply to all and pick it up here.' || E'\n\n'
      || 'Under the Supplier Agreement you must respond within ' || v_window || ' working days of the reveal, that is by '
      || to_char(v_final_at at time zone 'Asia/Dubai', 'DD Mon YYYY') || '. If we have not seen a response by then, our chief executive decides the case and the customer is refunded everything they paid (AED '
      || v_amt || '). Under the supplier terms that amount is then recovered from your account, with an administrative fee of AED 250 and interest at 9% per annum until it is settled, and matching is paused until it is paid.' || E'\n\n'
      || 'If you have already been in touch with this customer, reply here and we will close this off.',
    'بانتظار ردّكم — QuotesDone',
    'سدّد أحد العملاء رسوم الكشف عن بيانات التواصل معكم ولم يتلقَّ ردًّا بعد، والعميل مُدرَج في نسخة هذه الرسالة. ويتعيّن الرد خلال ' || v_window
      || ' أيام عمل من تاريخ الكشف، وإلا فسيُردّ إلى العميل كامل ما دفعه (' || v_amt || ' درهم)، ويُسترد المبلغ من حسابكم مع رسوم إدارية قدرها 250 درهمًا وفائدة 9% سنويًا.',
    array_remove(array[cust_email], null), 'customer_notice:' || t.id, null,
    jsonb_build_object('step', 'customer_notice', 'transaction_id', t.id));

  update public.transactions
     set customer_notified_at = now(), refund_deadline = coalesce(refund_deadline, v_final_at)
   where id = p_transaction;

  return jsonb_build_object('ok', true, 'notified_at', now(), 'recipients', jsonb_build_array(sup.email, cust_email),
                            'founder_call_due_at', v_final_at, 'delivery_request', v_req,
                            'state', public.fn_refund_state(p_transaction));
end $function$;

revoke execute on function public.fn_notify_supplier(uuid,text) from public, anon, authenticated;

-- fn_sales_engineer_tells_customer_invoice_ready: 2 Arabic fragment(s) rewritten.
CREATE OR REPLACE FUNCTION public.fn_sales_engineer_tells_customer_invoice_ready()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c record;
  v_ar boolean;
begin
  if new.kind <> 'handoff' or coalesce(new.detail->>'subject', '') <> 'reveal_invoice' then return new; end if;
  select id, email into c from public.customers where id = (new.detail->>'customer_id')::uuid;
  if c.email is not null and c.email ~ '@' then
    v_ar := public.fn_registered_locale('customer', c.id) = 'ar';
    insert into public.notifications (type, to_email, to_role, inquiry_id, quote_id, subject, body, lang)
    values ('invoice_ready', c.email, 'customer',
            (new.detail->>'inquiry_id')::uuid, (new.detail->>'quote_id')::uuid,
            case when v_ar then 'فاتورتكم جاهزة' else 'Your invoice is ready' end,
            case when v_ar
              then 'أصبحت فاتورة رسوم الكشف التي سددتموها متاحة في حسابكم على QuotesDone، ويمكنكم فتحها في أي وقت من زر «الفاتورة» على العرض الذي كشفتموه، أو من «المستندات» ضمن «الفواتير».'
              else 'The invoice for the reveal fee you paid is now in your QuotesDone account. Open it any time from the "Invoice (PDF)" button on the quote you revealed, or under Invoices in Documents.'
            end,
            case when v_ar then 'ar' else 'en' end);
  end if;
  update public.agent_actions
     set status = 'done', decided_at = now(), decided_by = 'sales_engineer'
   where id = new.id;
  return new;
end
$function$;

revoke execute on function public.fn_sales_engineer_tells_customer_invoice_ready() from public, anon, authenticated;

-- fn_supplier_notice: 1 Arabic fragment(s) rewritten.
CREATE OR REPLACE FUNCTION public.fn_supplier_notice(p_lead bigint, p_type text, p_subject_en text, p_body_en text, p_subject_ar text, p_body_ar text, p_inquiry uuid DEFAULT NULL::uuid, p_quote uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare l record; v_ar boolean; v_subject text; v_body text; n int := 0;
begin
  select id, company_name,
         coalesce(nullif(btrim(claimed_by), ''), nullif(btrim(email), '')) as mail,
         coalesce(nullif(btrim(whatsapp), ''), nullif(btrim(phone), ''))  as tel
    into l from public.leads where id = p_lead;
  if not found then return 0; end if;
  v_ar := public.fn_registered_locale('supplier', null, p_lead) = 'ar';
  v_subject := case when v_ar then p_subject_ar else p_subject_en end;
  v_body := replace(case when v_ar then p_body_ar else p_body_en end, '{company}',
                    coalesce(nullif(btrim(l.company_name), ''), case when v_ar then 'الشركاء' else 'partner' end));
  if l.mail is not null then
    insert into public.notifications (type, kind, to_email, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status, requested_by, sender, lang)
    values (p_type, 'sales_engineer_' || p_type, l.mail, 'supplier', p_lead, p_inquiry, p_quote, 'email', v_subject, v_body, 'queued', 'sales_engineer', 'customer_support',
            case when v_ar then 'ar' else 'en' end);
    n := n + 1;
  end if;
  -- trg_wa_fanout has already made a WhatsApp twin for a supplier who opted in; otherwise queue one.
  if l.tel is not null and not exists (select 1 from public.notifications
                                        where channel = 'whatsapp' and lead_id = p_lead and type = p_type and created_at = now()) then
    insert into public.notifications (type, kind, to_email, to_phone, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status, requested_by, sender, lang)
    values (p_type, 'sales_engineer_' || p_type, l.mail, l.tel, 'supplier', p_lead, p_inquiry, p_quote, 'whatsapp', v_subject, v_body, 'queued', 'sales_engineer', 'customer_support',
            case when v_ar then 'ar' else 'en' end);
    n := n + 1;
  end if;
  return n;
end $function$;

revoke execute on function public.fn_supplier_notice(bigint,text,text,text,text,text,uuid,uuid) from public, anon, authenticated;

-- 3. public.notification_copy: 13 rows, all rewritten to the formal plural. Each update is guarded on
--    the md5 of the body it replaces, so a newer edit is never overwritten.

update public.notification_copy
   set subject_ar = 'تحديث جديد على QuotesDone',
       body_ar = 'لديكم تحديث جديد على QuotesDone {ref}. يُرجى تسجيل الدخول إلى بوابتكم للاطلاع على التفاصيل.',
       updated_at = now()
 where type = '*' and md5(body_ar) = '78c1f63ffbd7d8240dd40a323d2d9bf4';

update public.notification_copy
   set subject_ar = 'بشأن استفساركم عن الرسوم',
       body_ar = 'راجعنا سجلاتنا، وتجدون التفاصيل الكاملة لكل مبلغ في قسم الفواتير ببوابتكم على QuotesDone. ويسعدنا الإجابة عن أي استفسار عبر الرد على هذه الرسالة.',
       updated_at = now()
 where type = 'billing_answer' and md5(body_ar) = '10d471b75e6591867f455244324feefb';

update public.notification_copy
   set subject_ar = 'ملاحظة سريعة بشأن الطلبات الملغاة',
       body_ar = 'لاحظنا إلغاء عدد من طلباتكم الأخيرة، ولا حرج في ذلك، غير أن المورّدين يخصّصون وقتًا فعليًا لتسعير كل طلب، لذا نرجو نشر الطلبات التي تعتزمون المضي فيها. وإن رغبتم في المساعدة على تحديد نطاق العمل قبل النشر، فيسعدنا ذلك.',
       updated_at = now()
 where type = 'cancel_warning' and md5(body_ar) = 'a5be12b3f7f12fe5c3eeb2cbb9f64fe0';

update public.notification_copy
   set subject_ar = 'تذكير أخير: أحد مستنداتكم على وشك الانتهاء',
       body_ar = 'تقترب صلاحية أحد مستنداتكم المسجّلة لدى QuotesDone من الانتهاء. يُرجى رفع النسخة المجدّدة من تبويب المستندات في بوابة المورّد، أو الرد على هذه الرسالة مع إرفاقها.',
       updated_at = now()
 where type = 'doc_final_notice' and md5(body_ar) = '492498367ec26964fe2a856b515dc3d7';

update public.notification_copy
   set subject_ar = 'استلمنا مستندكم',
       body_ar = 'شكرًا لكم، استلمنا مستندكم وحدّثنا سجلاتكم.',
       updated_at = now()
 where type = 'doc_received' and md5(body_ar) = '615035b8d9e57fd576c9c35e9e9fc776';

update public.notification_copy
   set subject_ar = 'إيقاف مؤقت لحسابكم في QuotesDone — انتهت صلاحية أحد المستندات',
       body_ar = 'انتهت صلاحية أحد مستنداتكم المسجّلة، فأُوقف حسابكم مؤقتًا ولن تصلكم طلبات جديدة حتى تجديده. يُرجى رفع النسخة المجدّدة من تبويب المستندات في بوابة المورّد، أو الرد على هذه الرسالة مع إرفاقها، ويُعاد تفعيل حسابكم تلقائيًا ودون أي رسوم.',
       updated_at = now()
 where type = 'doc_suspended' and md5(body_ar) = '5527a0918ac0e4b4df60a9e8a0489c26';

update public.notification_copy
   set subject_ar = 'تحديث بشأن عمل قدّمتم عرضًا له',
       body_ar = 'نشكركم على تقديم عرضكم على {ref}. وقد اختار العميل هذه المرة مورّدًا آخر. تصلكم فرص جديدة مطابقة عبر QuotesDone باستمرار، فنرجو متابعة صندوق الوارد في بوابتكم.',
       updated_at = now()
 where type = 'job_awarded_other' and md5(body_ar) = '3ca91033de6b4ca62007bcb36aca9d2b';

update public.notification_copy
   set subject_ar = 'طلب عمل جديد على QuotesDone',
       body_ar = 'يطلب أحد العملاء عروض أسعار لعمل يطابق نشاطكم {ref}. يُرجى تسجيل الدخول إلى بوابة المورّد في QuotesDone لتقديم عرضكم.',
       updated_at = now()
 where type = 'new_inquiry' and md5(body_ar) = '32f4bc8b74905d7970a01db887a07124';

update public.notification_copy
   set subject_ar = 'رسالة جديدة على QuotesDone',
       body_ar = 'لديكم رسالة جديدة في محادثة مشروعكم {ref}. يُرجى تسجيل الدخول للرد.',
       updated_at = now()
 where type = 'new_message' and md5(body_ar) = '0cfb3faeea5af2767a17102ece6a8e44';

update public.notification_copy
   set subject_ar = 'عرض سعر جديد على QuotesDone',
       body_ar = 'قدّم أحد المورّدين عرض سعر لطلبكم {ref}. يُرجى تسجيل الدخول للاطلاع على العرض كاملًا ومقارنته.',
       updated_at = now()
 where type = 'new_quote' and md5(body_ar) = '265cbdb9f0c3489cf564a097425478b6';

update public.notification_copy
   set subject_ar = 'عرضكم يحتاج إلى بعض التفاصيل قبل إرساله',
       body_ar = 'نشكركم على عرضكم {ref}. ولإرساله إلى العميل، يُرجى استكمال التفاصيل الناقصة الظاهرة في بوابة المورّد؛ فالعروض المفصّلة بالعلامات التجارية والمواصفات وتفصيل البنود تحظى بفرص فوز أعلى بكثير.',
       updated_at = now()
 where type = 'quote_coaching' and md5(body_ar) = 'e7f1e2306275b59e3d30e16044655980';

update public.notification_copy
   set subject_ar = 'عدّل العميل هذا الطلب — يُرجى إعادة التسعير',
       body_ar = 'عدّل العميل متطلبات طلب سبق أن سعّرتموه {ref}، فأُعيد عرضكم إلى المسودة. يُرجى فتح الطلب في بوابة المورّد ومراجعة ما تغيّر، ثم تقديم عرض محدّث. ولم يُحذف أي شيء.',
       updated_at = now()
 where type = 'quote_requirements_changed' and md5(body_ar) = 'c89578fc05b0b94a91e00344f60dc152';

update public.notification_copy
   set subject_ar = 'أضاف العميل تفاصيل إلى طلب دُعيتم لتسعيره',
       body_ar = 'أضاف العميل تفاصيل إلى الطلب {ref} الذي دُعيتم لتسعيره. يُرجى تسجيل الدخول إلى بوابة المورّد في QuotesDone للاطلاع على الطلب كاملًا وتقديم عرضكم.',
       updated_at = now()
 where type = 'rfq_addendum' and md5(body_ar) = '3510278336b9210178922d810181f9e8';

-- 4. Read-only verdict: each routine no longer carries a sampled phrase it replaced, and all 13
--    notification_copy bodies are the new text.
select case when true
      and public.fn_ar_days(0) = 'اليوم' and public.fn_ar_days(1) = 'يوم واحد' and public.fn_ar_days(2) = 'يومان'
      and public.fn_ar_days(10) = '10 أيام' and public.fn_ar_days(11) = '11 يومًا'
      and position(convert_from(decode('d8aad98520d8aad8a3d983d98ad8af20d8a7d984d983d8b4d98120e2809420', 'hex'), 'UTF8') in (select prosrc from pg_proc where oid = 'public.fn_sales_engineer_acts_on_handoff(bigint)'::regprocedure)) = 0
      and position(convert_from(decode('d984d98520d986d8acd8af20d8b9d985d984d98ad8a920d8a7d984d983d8b4d98120d987d8b0d98720d981d98a20d8add8b3d8a7d8a8d9832e', 'hex'), 'UTF8') in (select prosrc from pg_proc where oid = 'public.fn_refund_open_from_customer(uuid,text,text)'::regprocedure)) = 0
      and position(convert_from(decode('d8a7d8b1d981d8b920d8b1d8aed8b5d8aad98320d8a7d984d8aad8acd8a7d8b1d98ad8a9', 'hex'), 'UTF8') in (select prosrc from pg_proc where oid = 'public.fn_supplier_advisor(bigint)'::regprocedure)) = 0
      and position(convert_from(decode('d8b1d982d98520d8acd988d8a7d98420d8a5d985d8a7d8b1d8a7d8aad98a20d8aad98520d8a7d984d8aad8add982d98220d985d986d987', 'hex'), 'UTF8') in (select prosrc from pg_proc where oid = 'public.fn_sales_engineer_supplier_documents_tick()'::regprocedure)) = 0
      and position(convert_from(decode('d985d8b7d984d988d8a820d8a5d8acd8b1d8a7d8a13a20d8b9d985d98ad98420d98ad986d8aad8b8d8b120d8b1d8afd991d98320e280942051756f746573446f6e65', 'hex'), 'UTF8') in (select prosrc from pg_proc where oid = 'public.fn_sales_engineer_ladder_step(uuid,text,bigint,bigint)'::regprocedure)) = 0
      and position(convert_from(decode('d98ad8aad8acd8afd8af20d8a7d8b4d8aad8b1d8a7d983d98320d983d985d988d8b1d991d8af20d981d98a2051756f746573446f6e6520d981d98a20', 'hex'), 'UTF8') in (select prosrc from pg_proc where oid = 'public.fn_sales_engineer_writes_money_notice(bigint)'::regprocedure)) = 0
      and position(convert_from(decode('d984d8a720d98ad985d983d98620d8a7d8b9d8aad985d8a7d8af20d8a7d984d8add8b3d8a7d8a820d8a8d8afd988d986d987d8a720e2809420d8a8d988d8a7d8a8d8a920d8a7d984d8b1d8aed8b5d8a920d8aad8b1d981d8b620d983d98420d985d984d98120d984d8a720d98ad8add985d984d987d8a72e', 'hex'), 'UTF8') in (select prosrc from pg_proc where oid = 'public.fn_supplier_certifications(bigint)'::regprocedure)) = 0
      and position(convert_from(decode('d8a7d984d8a3d8b9d985d8a7d98420d8a7d984d981d8a7d8a6d8b2d8a920d988d8aad982d98ad98ad98520d8a7d984d8acd988d8afd8a9d88c20d985d98620d8b9d8b1d988d8b6d98320d988d8aad982d98ad98ad985d8a7d8aad98320d8b9d984d9892051756f746573446f6e65', 'hex'), 'UTF8') in (select prosrc from pg_proc where oid = 'public.fn_supplier_tier(bigint)'::regprocedure)) = 0
      and position(convert_from(decode('d984d98ad8b320d984d8afd98a20d8a5d8acd8a7d8a8d8a920d985d988d8abd982d8a920d8b9d984d98920d8b0d984d98320d8add8aad98920d8a7d984d8a2d986d88c20d988d984d98620d8a3d8aed985d991d9862e20d984d982d8af20d8b3d8acd991d984d8aa20d8b3d8a4d8a7d984d98320d983d985d8a720d983d8aad8a8d8aad98720', 'hex'), 'UTF8') in (select prosrc from pg_proc where oid = 'public.fn_support_knowledge_gap(text,text,text)'::regprocedure)) = 0
      and position(convert_from(decode('d988d8b5d984d8aad986d98a20d8b1d8b3d8a7d984d8aad98320d988d982d8af20d8aad8add988d991d984d8aa20d8add8b1d988d981d987d8a720d8a5d984d98920d8b9d984d8a7d985d8a7d8aa20d8a7d8b3d8aad981d987d8a7d985d88c20d988d984d8a720d8a3d8b3d8aad8b7d98ad8b920d982d8b1d8a7d8a1d8a920d985d8a720d8b3d8a3d984d8aa20d8b9d986d9872e20', 'hex'), 'UTF8') in (select prosrc from pg_proc where oid = 'public.fn_text_did_not_survive_reply(text)'::regprocedure)) = 0
      and position(convert_from(decode('d985d984d8a7d8add8b8d8a920d8add988d98420d8b9d8b1d988d8b6d98320d8a7d984d8a3d8aed98ad8b1d8a920d8b9d984d9892051756f746573446f6e65', 'hex'), 'UTF8') in (select prosrc from pg_proc where oid = 'public.fn_supplier_collaboration_incident(bigint,uuid,uuid,bigint)'::regprocedure)) = 0
      and position(convert_from(decode('d8b4d983d8b1d98bd8a720d984d8add8afd98ad8abd983d98520d985d8b9d986d8a72e20d8a7d8b3d8aad8a3d986d981d986d8a720d8a5d8b1d8b3d8a7d98420d8a7d984d8b7d984d8a8d8a7d8aa20d8a7d984d8acd8afd98ad8afd8a920d8a5d984d98920d8b4d8b1d983d8aad983d985d88c20d988d8b3d8aad8a8d8afd8a320d8b7d984d8a8d8a7d8aa20d8a7d984d985d8b7d8a7d8a8d982d8a920d8a8d8a7d984d988d8b5d988d98420d8a5d984d98ad983d98520d985d8acd8afd8afd98bd8a72e20d988d8b9d986d8afd985d8a720d98ad8add8aad8a7d8ac20d8a3d98a20d8b9d8b1d8b620d8a5d984d98920d8aad981d8a7d8b5d98ad98420d8a5d8b6d8a7d981d98ad8a9d88c20d98ad985d983d986d983d98520d8a5d983d985d8a7d984d987d8a720d985d98620d8a8d988d8a7d8a8d8a920d8a7d984d985d988d8b1d991d8afd98ad98620d8aed984d8a7d98420d8afd982d8a7d8a6d9822e', 'hex'), 'UTF8') in (select prosrc from pg_proc where oid = 'public.fn_supplier_collaboration_hold_lift(bigint,bigint,text)'::regprocedure)) = 0
      and position(convert_from(decode('d8a8d8a7d986d8aad8b8d8a7d8b120d8b1d8afd991d98320e280942051756f746573446f6e65', 'hex'), 'UTF8') in (select prosrc from pg_proc where oid = 'public.fn_notify_supplier(uuid,text)'::regprocedure)) = 0
      and position(convert_from(decode('d981d8a7d8aad988d8b1d8aad98320d8acd8a7d987d8b2d8a9', 'hex'), 'UTF8') in (select prosrc from pg_proc where oid = 'public.fn_sales_engineer_tells_customer_invoice_ready()'::regprocedure)) = 0
      and position(convert_from(decode('d8b4d8b1d98ad983d986d8a7', 'hex'), 'UTF8') in (select prosrc from pg_proc where oid = 'public.fn_supplier_notice(bigint,text,text,text,text,text,uuid,uuid)'::regprocedure)) = 0
      and (select count(*) from public.notification_copy c join (values
    ('*', '78c1f63ffbd7d8240dd40a323d2d9bf4', '4d82815baf9b0ea4619449efaa971887'),
    ('billing_answer', '10d471b75e6591867f455244324feefb', '62af313c46c83e0baa204884a68d097f'),
    ('cancel_warning', 'a5be12b3f7f12fe5c3eeb2cbb9f64fe0', 'ff5d9a84a7d107e40c90d3261403e4fc'),
    ('doc_final_notice', '492498367ec26964fe2a856b515dc3d7', 'e48a74674e72573143e902e3454dbbf0'),
    ('doc_received', '615035b8d9e57fd576c9c35e9e9fc776', 'e4ff1d97b38c512d349b916ea2242c35'),
    ('doc_suspended', '5527a0918ac0e4b4df60a9e8a0489c26', 'bfe7674f8d74bf3dc6ae93416d8e44de'),
    ('job_awarded_other', '3ca91033de6b4ca62007bcb36aca9d2b', 'f534e4cb45ee3bb4a01f9f950bea81f3'),
    ('new_inquiry', '32f4bc8b74905d7970a01db887a07124', '9061f35b14fe645374ad4300e3834809'),
    ('new_message', '0cfb3faeea5af2767a17102ece6a8e44', '14fba5ad8bb230a2806ac4ecbee8551a'),
    ('new_quote', '265cbdb9f0c3489cf564a097425478b6', '597fa5c221b2dcef12ff1b51ef311120'),
    ('quote_coaching', 'e7f1e2306275b59e3d30e16044655980', '6ebc5c1e435923ccac222f95a68196fb'),
    ('quote_requirements_changed', 'c89578fc05b0b94a91e00344f60dc152', '5fc32ac6e1d4ae12c183761f6f1e7509'),
    ('rfq_addendum', '3510278336b9210178922d810181f9e8', '3c129a8bc19e93bc266c4e6dc4aa7bb6')) v(type, old_md5, new_md5) on v.type = c.type and md5(c.body_ar) = v.new_md5) = 13
  then 'PROBE OK' else 'PROBE FAILED' end as verdict,
  (select string_agg(v.type, ', ') from (values
    ('*', '78c1f63ffbd7d8240dd40a323d2d9bf4', '4d82815baf9b0ea4619449efaa971887'),
    ('billing_answer', '10d471b75e6591867f455244324feefb', '62af313c46c83e0baa204884a68d097f'),
    ('cancel_warning', 'a5be12b3f7f12fe5c3eeb2cbb9f64fe0', 'ff5d9a84a7d107e40c90d3261403e4fc'),
    ('doc_final_notice', '492498367ec26964fe2a856b515dc3d7', 'e48a74674e72573143e902e3454dbbf0'),
    ('doc_received', '615035b8d9e57fd576c9c35e9e9fc776', 'e4ff1d97b38c512d349b916ea2242c35'),
    ('doc_suspended', '5527a0918ac0e4b4df60a9e8a0489c26', 'bfe7674f8d74bf3dc6ae93416d8e44de'),
    ('job_awarded_other', '3ca91033de6b4ca62007bcb36aca9d2b', 'f534e4cb45ee3bb4a01f9f950bea81f3'),
    ('new_inquiry', '32f4bc8b74905d7970a01db887a07124', '9061f35b14fe645374ad4300e3834809'),
    ('new_message', '0cfb3faeea5af2767a17102ece6a8e44', '14fba5ad8bb230a2806ac4ecbee8551a'),
    ('new_quote', '265cbdb9f0c3489cf564a097425478b6', '597fa5c221b2dcef12ff1b51ef311120'),
    ('quote_coaching', 'e7f1e2306275b59e3d30e16044655980', '6ebc5c1e435923ccac222f95a68196fb'),
    ('quote_requirements_changed', 'c89578fc05b0b94a91e00344f60dc152', '5fc32ac6e1d4ae12c183761f6f1e7509'),
    ('rfq_addendum', '3510278336b9210178922d810181f9e8', '3c129a8bc19e93bc266c4e6dc4aa7bb6')) v(type, old_md5, new_md5)
    where not exists (select 1 from public.notification_copy c where c.type = v.type and md5(c.body_ar) = v.new_md5)) as notification_copy_not_rewritten;
