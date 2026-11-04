-- A REFUND REQUEST AFTER A PARTIAL STRIPE REFUND IS ANSWERED, NOT A 500.
--
-- Assigned: accountant. 3 Nov 2026. Gap #8 of docs/release/qualification_matrix.md, case R4 (review of PR #1835).
--
-- MEASURED (ZZ DEMO, Stripe TEST mode, run acpay01): AED 10.00 of a AED 30.00 reveal was refunded in the Stripe
-- dashboard. stripe_webhook recorded it once (refund 78198, requested_by stripe_webhook, no transaction_id). The
-- customer then asked for a refund: fn_refund_open_from_customer inserted a case for the whole AED 30.00, which
-- fn_refund_amount_is_the_fee_paid requires (a platform refund equals what was paid, whole or not at all), and
-- fn_refunds_never_return_more_than_was_paid refused it with 23514 refund_exceeds_what_was_paid. customer_api
-- turned the raised error into HTTP 500 refund_request_failed and an IT finding: correct money, no answer.
--
-- THE FIX. One refusal more, before the insert: if any money on this payment has already been refunded or is on its
-- way (any requester, matched by the sale or by its Stripe payment), the customer is told how much, in their
-- language, and the refusal is emitted like every other one. Nothing else in the routine changes; the body is the
-- canonical one from scripts/sql/every_arabic_message_is_written_not_translated.sql with this branch added.
-- The rest of a partly refunded payment stays the CEO's: fn_ceo_refund_verify opens the under_refund incident.
--
-- prevented by: scripts/sql/a_refund_request_after_a_partial_stripe_refund_is_answered_not_a_500_probe.sql
CREATE OR REPLACE FUNCTION public.fn_refund_open_from_customer(p_transaction_id uuid, p_requested_by text, p_reason_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t public.transactions; c record; v_id bigint; v_open bigint; v_locale text; v_code text; v_en text; v_ar text;
  v_later boolean := false; v_paid text; v_decide text; v_req bigint; v_amt numeric; v_out bigint;
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
  -- MONEY ALREADY RETURNED ON THIS PAYMENT (3 Nov 2026, accountant, gap #8 R4). A refund issued in the Stripe dashboard
  -- is recorded by fn_refund_settle (requested_by stripe_webhook) and leaves the sale's refund_status empty, so this
  -- fell through to the insert below, which must equal everything paid; a01 then refused it as more than the payment
  -- still holds, and customer_api answered the customer HTTP 500. Measured on ZZ DEMO run acpay01: AED 10 of 30 refunded
  -- outside the platform, request -> 23514 refund_exceeds_what_was_paid. The answer is now a refusal in words; the rest
  -- of the payment is the CEO's refund_incident (under_refund -> refund_difference), opened when the refund settled.
  elsif (select coalesce(sum(r.amount_fils), 0) from public.refunds r
          where (r.transaction_id = t.id or r.stripe_payment_intent = t.payment_ref)
            and r.status not in ('rejected', 'failed', 'cancelled')) > 0 then
    v_out := (select coalesce(sum(r.amount_fils), 0) from public.refunds r
               where (r.transaction_id = t.id or r.stripe_payment_intent = t.payment_ref)
                 and r.status not in ('rejected', 'failed', 'cancelled'));
    v_code := 'already_refunded';
    v_en := 'AED ' || round(v_out / 100.0, 2) || ' of this payment has already been refunded to your original payment method, so a new refund case cannot be opened for it. Banks take 7 to 14 working days to show it. If you think more is owed, write to us from your portal and we will check the record.';
    v_ar := 'سبق أن استُردّ ' || round(v_out / 100.0, 2) || ' درهم من هذه الدفعة إلى وسيلة الدفع الأصلية، لذا لا يمكن فتح حالة استرداد جديدة لها. وتستغرق البنوك من 7 إلى 14 يوم عمل لإظهار المبلغ. وإن رأيتم أن هناك مبلغًا آخر مستحقًا، فيُرجى مراسلتنا من بوابتكم لنراجع السجل.';
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

-- CREATE OR REPLACE keeps the ACL; restated so the file says who may run it.
revoke execute on function public.fn_refund_open_from_customer(uuid,text,text) from public, anon, authenticated;
