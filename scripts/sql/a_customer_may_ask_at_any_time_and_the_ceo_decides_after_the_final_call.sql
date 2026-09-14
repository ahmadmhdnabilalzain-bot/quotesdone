-- A CUSTOMER MAY ASK AT ANY TIME, AND THE CEO DECIDES AFTER THE FINAL CALL.
-- Assigned: sales_engineer (the customer's request, the confirmation, the ladder wording) and
-- accountant (the refund row's guard, which decides when money may be approved).
--
-- WHAT THE PUBLISHED TERMS SAY (src/content/legal.json, Terms of Service v7 §5 and Refund Policy v1.5
-- §3 and §5, both last updated 14 Sep 2026), quoted so nobody re-derives it:
--   * "you do not need to do anything for the clock to start: QuotesDone tracks every Reveal from the
--     moment you pay" -- day 3 chase, day 5 the CEO's final call;
--   * "You may also raise a complaint through the Platform at any time";
--   * proof of your own attempts "is never a condition of the refund";
--   * the refund is due when the supplier failed to respond within five working days of payment AND
--     does not respond to the CEO's final call, and "Every refund is decided by QuotesDone's CEO".
-- So the customer may REQUEST at any time, and the five-working-day window governs when the case may
-- be DECIDED. The terms are not ambiguous on this; nothing in them limits a complaint to 7 days.
--
-- WHAT WAS MEASURED (e2e harness run 7 on demo data, and the live definitions on 14 Sep 2026):
--   1. trg_reveal_window sets transactions.refund_deadline = reveal + 5 working days. The refunds
--      guard (fn_refund_amount_is_the_fee_paid) refused ANY refunds row before that instant, while
--      customer_api request_refund refused AFTER it. Same column, opposite sides: there was no moment
--      at which a customer could open a case. customer_api also flipped the sale to 'requested' before
--      the case existed and discarded the refusal, so the sale read "requested" with no case, no
--      handoff to the accountant, and a customer told "received".
--   2. fn_ceo_refund_checklist item complaint_within_7_days_with_proof refused a refund unless the
--      customer complained within 7 days WITH proof -- a condition the terms expressly do not impose,
--      and one that fails every case where the customer did nothing, which is the case the terms
--      promise to refund. fn_sales_engineer_ladder_step 'customer_proof' told customers the same.
--
-- WHAT THIS FILE CHANGES:
--   1. fn_refund_amount_is_the_fee_paid: a refund at 'requested' may be recorded at any time after the
--      reveal; the window refuses only the move to approved/processing/succeeded before
--      refund_deadline. The approval, not the complaint, waits for the ladder.
--   2. fn_refund_open_from_customer: the ONE transaction behind the portal button. It checks the
--      exclusions the terms name, opens the case, marks the sale 'requested', and has the sales
--      engineer confirm to the customer in their registered language (support delivers). A refusal
--      opens nothing, changes nothing on the sale, says why and whether a claim is possible later,
--      in both languages, and is recorded as a refund.request_refused event.
--   3. fn_ceo_refund_checklist item 1 becomes customer_complaint_on_record: informational, never a
--      refusal, carrying the same evidence.
--   4. fn_sales_engineer_ladder_step 'customer_proof' asks for proof as optional help, not a condition.
--   5. ONE REFUND RAIL (PR #640 review): unique index refunds_one_live_platform_refund_per_payment
--      refuses a second live platform refund on one payment for every writer. The second rail it
--      closes, refunds_api 'resolve', is retired in the same PR, and execute_refunds keys Stripe once
--      per transaction (_shared/stripe_refund.ts refundIdempotencyKey).
--   6. THE PLAYBOOK ON THE SAME RAIL (re-review): refunds.topup_of; a01 caps every live platform
--      write so a payment's live refunds never exceed total_charged; fn_accountant_reserves_topup
--      reserves a capped top-up row before Stripe; a00 lets a top-up carry only the part still owed;
--      z05 lets a top-up cite its case's CEO decision (and nothing else may cite another row's).
--
-- WHAT IT DOES NOT CHANGE: the ladder sweep, the CEO's review, the day-3 and day-5 checks, the Stripe
-- reference and amount guards, and who approves (the CEO). The Stripe key a refund uses is fixed in
-- supabase/functions/_shared/stripe_refund.ts, not here.

CREATE OR REPLACE FUNCTION public.fn_refund_amount_is_the_fee_paid()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  t public.transactions%rowtype;
  v_expected bigint;
  -- A refund Stripe already issued is a fact to be recorded, not a request to be approved.
  v_external constant text[] := array['stripe_webhook','stripe_dashboard','stripe'];
begin
  if lower(coalesce(NEW.requested_by,'')) = any(v_external) then
    return NEW;
  end if;

  if NEW.transaction_id is null then
    raise exception 'refunds: a refund must name the transaction it reverses. transaction_id is null, so this row asserts money is owed without saying which payment it came from. (refund_names_no_payment)'
      using errcode = '23514',
            hint = 'Set transaction_id to the public.transactions row whose reveal_fee is being returned. A refund this platform did not issue is recorded through fn_refund_settle with requested_by stripe_webhook, and that path is exempt.';
  end if;

  select * into t from public.transactions where id = NEW.transaction_id;
  if not found then
    raise exception 'refunds: transaction % does not exist. (refund_transaction_absent)',
      NEW.transaction_id using errcode = '23503';
  end if;

  if coalesce(t.total_charged, t.reveal_fee) is null or coalesce(t.total_charged, t.reveal_fee) <= 0 then
    raise exception 'refunds: transaction % records no reveal fee (reveal_fee %), so there is nothing to give back. A refund of an unpaid reveal is a payment, not a refund. (refund_no_fee_was_paid)',
      NEW.transaction_id, coalesce(t.reveal_fee::text,'null') using errcode = '23514';
  end if;

  if t.refund_deadline is null then
    raise exception 'refunds: transaction % has no refund window. trg_reveal_window opens one at reveal, so a transaction without it was never revealed and no refund can be due yet. (refund_window_not_open)',
      NEW.transaction_id using errcode = '23514';
  end if;
  -- THE WINDOW GOVERNS THE DECISION, NOT THE REQUEST (14 Sep 2026). The terms let the customer
  -- complain "at any time"; what waits for the fifth working day and the CEO's final call is the
  -- approval. So a row at 'requested' is recorded whenever it arrives, and only the move to money
  -- (approved, processing, succeeded) is refused before refund_deadline.
  if NEW.status in ('approved', 'processing', 'succeeded') and now() < t.refund_deadline then
    raise exception 'refunds: transaction % may not be approved or paid before % (it is now %). The supplier has five working days from the payment and the CEO''s final call before a refund is decided; the request itself is recorded at any time. (refund_window_not_yet_open)',
      NEW.transaction_id, t.refund_deadline, now() using errcode = '23514';
  end if;

  -- ── THE STRIPE REFERENCE, ADDED 9 SEP 2026 ───────────────────────────────────────────────────
  -- The founder: "it's issued against that exact invoice reference... It has an ID." The reference
  -- Stripe gave us when the customer paid is transactions.payment_ref (stripe_webhook writes the
  -- payment_intent, falling back to the checkout session id). Until now stripe_payment_intent on a
  -- refund was a nullable text column nothing checked, so a refund could name transaction A and
  -- cite the payment of transaction B -- or name no payment at all -- and still move money.
  if coalesce(btrim(t.payment_ref), '') = '' then
    raise exception 'refunds: transaction % carries no Stripe payment reference, so there is no payment of record to reverse. (refund_payment_has_no_reference)',
      NEW.transaction_id using errcode = '23514',
            hint = 'transactions.payment_ref is written by stripe_webhook when the reveal fee settles. A transaction without one was never paid through Stripe, and money must not be returned against a payment nobody can point at.';
  end if;
  if coalesce(btrim(NEW.stripe_payment_intent), '') = '' then
    raise exception 'refunds: this refund names no Stripe payment. Transaction % was paid under reference %, and a refund is issued against that exact reference. (refund_names_no_stripe_reference)',
      NEW.transaction_id, t.payment_ref using errcode = '23514',
            hint = 'Set stripe_payment_intent to the payment_ref of the transaction being reversed. Founder ruling, 9 Sep 2026.';
  end if;
  if btrim(NEW.stripe_payment_intent) <> btrim(t.payment_ref) then
    raise exception 'refunds: this refund cites Stripe payment %, but transaction % was paid under %. A refund is issued against the exact reference of the payment it reverses, never another one. (refund_cites_the_wrong_stripe_payment)',
      NEW.stripe_payment_intent, NEW.transaction_id, t.payment_ref using errcode = '23514';
  end if;

  -- AND THE AMOUNT IS READ OFF THAT PAYMENT. Equality, not a ceiling: the reveal fee is refunded
  -- whole or not at all, so "cannot exceed what the payment took" is enforced by the stricter rule
  -- that it must EQUAL it. A platform refund with no amount is refused outright -- an unstated
  -- figure is not a smaller figure, it is an unbounded one.
  v_expected := round(coalesce(t.total_charged, t.reveal_fee) * 100)::bigint;
  -- A TOP-UP (topup_of set) completes a case on THIS payment and carries only the part still owed, so
  -- it is exempt from equality; a01 caps it, and every live refund on the payment together, at
  -- total_charged (PR #640 re-review, 14 Sep 2026).
  if NEW.topup_of is not null then
    if not exists (select 1 from public.refunds c where c.id = NEW.topup_of and c.transaction_id = NEW.transaction_id and c.topup_of is null) then
      raise exception 'refunds: a top-up must name a refund case on the same payment; % is not one for transaction %. (refund_topup_names_no_case)',
        NEW.topup_of, NEW.transaction_id using errcode = '23514';
    end if;
    if NEW.amount_fils is null or NEW.amount_fils <= 0 then
      raise exception 'refunds: a top-up must state a positive amount. (refund_states_no_amount)' using errcode = '23514';
    end if;
    return NEW;
  end if;
  if NEW.amount_fils is null then
    raise exception 'refunds: a platform refund must state its amount. Transaction % took % fils (AED %), and that is the only figure this refund may carry. (refund_states_no_amount)',
      NEW.transaction_id, v_expected, round(coalesce(t.total_charged, t.reveal_fee),2) using errcode = '23514';
  end if;
  if NEW.amount_fils <> v_expected then
    raise exception 'refunds: the amount must equal what the customer actually paid, the 3%% and the processing part together (total_charged), on transaction % — expected % fils (AED %), got % fils (AED %). A refund figure is read off the payment, never typed. (refund_amount_is_not_the_fee_paid)',
      NEW.transaction_id, v_expected, round(coalesce(t.total_charged, t.reveal_fee),2), NEW.amount_fils, round(NEW.amount_fils/100.0,2)
      using errcode = '23514';
  end if;

  return NEW;
end
$function$;

-- THE ONE DOOR BEHIND THE PORTAL BUTTON. Everything happens in this transaction or nothing does.
-- Answers {ok, code, message_en, message_ar, locale, ...}; customer_api shows the message in the
-- customer's registered language. Refusal codes: no_such_transaction, not_revealed, no_payment,
-- already_refunded, already_declined, job_completed, supplier_rated -- the exclusions in Terms v7 §5.
create or replace function public.fn_refund_open_from_customer(
  p_transaction_id uuid, p_requested_by text, p_reason_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t public.transactions; c record; v_id bigint; v_open bigint; v_locale text; v_code text; v_en text; v_ar text;
  v_later boolean := false; v_paid text; v_decide text; v_req bigint; v_amt numeric;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'no_such_transaction', 'locale', 'en', 'can_claim_later', false,
      'message_en', 'We could not find that reveal on your account.', 'message_ar', 'لم نجد عملية الكشف هذه في حسابك.');
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
      'message_ar', 'حالة الاسترداد QD-RF-' || v_open || ' مفتوحة بالفعل. يقرر رئيسنا التنفيذي بشأنها بعد ' || coalesce(v_decide, 'يوم العمل الخامس') || '، ولا يلزمك أي إجراء آخر.');
  end if;

  -- THE REFUSALS, each with the reason and whether a claim can come later.
  if t.revealed_at is null then
    v_code := 'not_revealed'; v_later := true;
    v_en := 'This reveal has not completed yet. You can ask for a refund once the payment has gone through and the supplier''s details are shown to you.';
    v_ar := 'لم تكتمل عملية الكشف بعد. يمكنك طلب الاسترداد بعد إتمام الدفع وظهور بيانات المورّد لك.';
  elsif coalesce(btrim(t.payment_ref), '') = '' then
    v_code := 'no_payment'; v_later := true;
    v_en := 'We have no recorded payment for this reveal yet, so there is nothing to refund. If you were charged, reply to your payment receipt and we will match it; you can ask again once it is recorded.';
    v_ar := 'لا يوجد لدينا دفع مسجّل لعملية الكشف هذه بعد، لذا لا يوجد ما يُسترد. إن خُصم منك مبلغ فردّ على إيصال الدفع وسنطابقه، ويمكنك الطلب مجددًا بعد تسجيله.';
  elsif coalesce(t.refund_status, '') in ('approved', 'refunded', 'processing', 'succeeded') then
    v_code := 'already_refunded';
    v_en := 'This reveal has already been refunded (AED ' || coalesce(t.refund_amount_aed, v_amt) || '). Banks take 7 to 14 working days to show it.';
    v_ar := 'تم استرداد رسوم عملية الكشف هذه بالفعل (' || coalesce(t.refund_amount_aed, v_amt) || ' درهم). تستغرق البنوك من 7 إلى 14 يوم عمل لإظهاره.';
  elsif exists (select 1 from public.refunds r where r.transaction_id = t.id and r.status = 'rejected'
                  and lower(coalesce(r.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe')) then
    v_code := 'already_declined';
    v_en := 'Our chief executive has already decided this case and declined it; the reason is shown on your refund case. Under section 5 of the Terms a decided case is not reopened by a new request. If you think the record is wrong, reply to the decision email.';
    v_ar := 'سبق أن قرر رئيسنا التنفيذي في هذه الحالة ورفضها، والسبب مبيّن في حالة الاسترداد. وفق البند 5 من الشروط لا تُعاد فتح حالة مقررة بطلب جديد. إن رأيت أن السجل غير صحيح فردّ على رسالة القرار.';
  elsif exists (select 1 from public.inquiries i where i.id = t.inquiry_id and i.status in ('completed', 'closed') and i.hired_supplier_id = t.supplier_id) then
    v_code := 'job_completed';
    v_en := 'This job is marked as completed with this supplier, so the supplier responded and the reveal fee is not refundable (Terms, section 5).';
    v_ar := 'هذا العمل مسجّل كمكتمل مع هذا المورّد، أي أن المورّد استجاب، لذا لا تُسترد رسوم الكشف (الشروط، البند 5).';
  elsif exists (select 1 from public.reviews v where v.transaction_id = t.id) then
    v_code := 'supplier_rated';
    v_en := 'You have rated this supplier, which records that you dealt with them, so the reveal fee is not refundable (Terms, section 5).';
    v_ar := 'لقد قيّمت هذا المورّد، ما يسجّل أنك تعاملت معه، لذا لا تُسترد رسوم الكشف (الشروط، البند 5).';
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
    'فتحنا حالة الاسترداد QD-RF-' || v_id || ' بخصوص المورّد الذي كشفت عنه في ' || coalesce(v_paid, 'تاريخ دفعك') || '. لا يلزمك أي إجراء آخر.' || E'\n\n'
      || 'أمام المورّد حتى ' || coalesce(v_decide, 'يوم العمل الخامس بعد دفعك') || ' للرد. نتابعه في يوم العمل الثالث مع نسخة إليك، '
      || 'وإن لم يردّ يوجّه رئيسنا التنفيذي نداءً أخيرًا ثم يقرر في حالتك بناءً على السجل. '
      || 'إن كان الاسترداد مستحقًا يُردّ إليك كامل ما دفعته (' || v_amt || ' درهم) إلى وسيلة الدفع الأصلية، وتستغرق البنوك من 7 إلى 14 يوم عمل لإظهاره.',
    '{}', 'refund_request_received:' || t.id, null,
    jsonb_build_object('step', 'customer_request', 'transaction_id', t.id, 'refund_id', v_id));

  return jsonb_build_object('ok', true, 'refund_id', v_id, 'status', 'requested', 'locale', v_locale,
    'decision_after', t.refund_deadline, 'delivery_request', v_req,
    'message_en', 'Refund case QD-RF-' || v_id || ' is open. Our chief executive decides it after ' || coalesce(v_decide, 'the fifth working day') || ', and if it is due everything you paid is refunded. We have emailed you the details.',
    'message_ar', 'تم فتح حالة الاسترداد QD-RF-' || v_id || '. يقرر رئيسنا التنفيذي بشأنها بعد ' || coalesce(v_decide, 'يوم العمل الخامس') || '، وإن كان الاسترداد مستحقًا يُردّ إليك كامل ما دفعته. أرسلنا إليك التفاصيل بالبريد.');
end $fn$;
revoke execute on function public.fn_refund_open_from_customer(uuid, text, text) from public, anon, authenticated;

create or replace function public.fn_sales_engineer_ladder_step(
  p_transaction_id uuid, p_step text, p_refund_id bigint default null, p_remediation_id bigint default null)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
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
      'مطلوب إجراء: عميل ينتظر ردّك — QuotesDone',
      'دفع عميل للكشف عن بيانات التواصل معك في ' || v_when || ' ولم يتلقَّ ردًّا منك بعد مرور ' || v_chase || ' أيام عمل، والعميل في نسخة هذه الرسالة. '
        || 'بموجب اتفاقية المورّد يجب الرد خلال ' || v_window || ' أيام عمل من الكشف، وإلا يُردّ للعميل كامل ما دفعه (' || v_amt
        || ' درهم) ويُسترد من حسابك مع رسوم إدارية 250 درهمًا وفائدة 9% سنويًا حتى السداد. إن كنت قد تواصلت مع العميل فردّ على هذه الرسالة.',
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
      'النداء الأخير: عميل ما زال ينتظر — QuotesDone',
      'هذا نداؤنا الأخير بخصوص العميل الذي كشف عن بيانات التواصل معك في ' || v_when || '. انقضت أيام العمل المسموح بها دون ردّ منك. '
        || 'إن لم نسمع منك حتى ' || to_char(v_watch at time zone 'Asia/Dubai', 'DD Mon YYYY') || ' يُردّ للعميل كامل ما دفعه (' || v_amt
        || ' درهم) ويُسترد من حسابك مع رسوم إدارية 250 درهمًا وفائدة 9% سنويًا. أي ردّ منك عبر البريد أو البوابة أو واتساب يوقف ذلك.',
      array_remove(array[cust.email], null), v_key, v_watch, v_extra);

  elsif p_step = 'customer_proof' then
    return public.fn_sales_engineer_writes('refund_proof_request', 'customer', cust.email, null, t.customer_id, t.inquiry_id, t.quote_id,
      'Anything you sent the supplier helps your refund case',
      'Hello ' || coalesce(nullif(btrim(cust.full_name), ''), 'there') || E',\n\n'
        || 'If you tried to reach the supplier yourself, forwarding that email to supplier@mail.quotesdone.com (or replying to it with that address in copy) puts it on your case and can help us close it faster. '
        || 'It is optional: it is never a condition of the refund, and you do not need to do anything for your case to be decided.',
      'ما أرسلته إلى المورّد يساعد في حالة استردادك',
      'إن حاولت التواصل مع المورّد بنفسك فإن إعادة توجيه تلك الرسالة إلى supplier@mail.quotesdone.com (أو الرد عليها مع إضافة هذا العنوان في النسخة) يضيفها إلى حالتك وقد يساعدنا على إغلاقها أسرع. هذا اختياري وليس شرطًا للاسترداد، ولا يلزمك أي إجراء ليُقرَّر في حالتك.',
      '{}', v_key, null, v_extra);
  end if;
  raise exception 'no such ladder step %', p_step;
end $fn$;
revoke execute on function public.fn_sales_engineer_ladder_step(uuid, text, bigint, bigint) from public, anon, authenticated;

-- THE CEO'S CHECKLIST, verbatim from payments_are_the_accountant_and_the_seats_close_every_refund_together.sql
-- except item 1 (see the header).

create or replace function public.fn_ceo_refund_checklist(p_transaction_id uuid, p_phase text, p_record boolean default true)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t public.transactions; r public.refunds; rs public.refunds; ap public.ceo_approval; du public.supplier_dues;
  e_chase public.refund_ladder_evidence; e_final public.refund_ladder_evidence;
  v_items jsonb := '[]'::jsonb; v_failed jsonb; v_ok boolean; v_cust text; v_total numeric; v_reason text; v_unresp boolean;
  v_complaint timestamptz; v_in_time boolean; v_cc boolean; v_attached boolean; v_proofs int; v_live boolean; v_proof_ev jsonb;
  v_prior boolean; v_hired boolean; v_rated boolean; v_offp boolean; v_excl text[] := '{}'; v_exp bigint;
  v_succ int; v_succ_fils bigint; v_extra int; v_actual numeric; v_approved numeric; v_loss numeric; v_charge jsonb; v_sent boolean;
  v_told boolean; v_sup_told boolean; v_kind text; v_rid bigint;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found then
    return jsonb_build_object('ok', false, 'phase', p_phase, 'transaction_id', p_transaction_id,
      'failed', jsonb_build_array(jsonb_build_object('item', 'transaction_exists', 'passed', false, 'reason', 'no such transaction', 'remediable', false)));
  end if;
  select * into r from public.refunds where transaction_id = t.id and status not in ('rejected', 'cancelled', 'failed')
     and lower(coalesce(requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') order by id desc limit 1;
  select lower(email) into v_cust from public.customers where id = t.customer_id;
  v_total := coalesce(t.total_charged, t.reveal_fee);
  v_reason := coalesce(r.reason_code, t.refund_reason, 'supplier_unresponsive');
  v_unresp := v_reason = 'supplier_unresponsive';
  select * into e_chase from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'chase' order by e.id desc limit 1;
  select * into e_final from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'final_call' order by e.id desc limit 1;

  if p_phase = 'approve' then
    v_rid := r.id;
    -- 1. THE CUSTOMER'S COMPLAINT, ON RECORD OR NOT -- NEVER A CONDITION (14 Sep 2026). This item was
    -- complaint_within_7_days_with_proof and refused every refund where the customer did not complain
    -- within 7 days with proof. Terms v7 §5 and Refund Policy v1.5 §3/§5 say the opposite: "you do not
    -- need to do anything for the clock to start", a complaint may come "at any time", and proof "is
    -- never a condition of the refund". So it now records the evidence and always passes; the conditions
    -- the terms DO set are items 2 to 6.
    v_complaint := least(t.customer_notified_at,
                         (select min(x.requested_at) from public.refunds x where x.transaction_id = t.id and lower(coalesce(x.requested_by, '')) = 'customer'));
    v_cc := exists (select 1 from public.inbound_messages im
                     where v_cust is not null and lower(im.from_email) = v_cust and im.created_at > t.revealed_at
                       and (im.to_email ilike 'supplier@%' or im.raw::text ilike '%supplier@mail.quotesdone.com%'));
    v_attached := exists (select 1 from public.refund_ladder_evidence e where e.transaction_id = t.id and e.step = 'customer_proof');
    v_items := v_items || jsonb_build_object('item', 'customer_complaint_on_record',
      'passed', true,
      'evidence', jsonb_build_object('revealed_at', t.revealed_at, 'complaint_at', v_complaint,
        'customer_emailed_supplier_with_supplier_at_in_copy', v_cc, 'formal_notice_through_portal_at', t.customer_notified_at,
        'proof_attached_by_sales_engineer', v_attached,
        'basis', 'Terms v7 section 5, Refund Policy v1.5 sections 3 and 5: no complaint or proof is required; the ladder runs from payment'),
      'reason', null, 'remedy', 'none needed', 'owner', 'sales_engineer', 'remedy_key', 'customer_proof', 'remediable', true, 'kind', 'information');

    -- 2 and 3. The day-3 chase and the day-5 final call, as support reported them.
    v_items := v_items || jsonb_build_object('item', 'day3_chase_happened',
      'passed', e_chase.id is not null and e_chase.delivered,
      'evidence', case when e_chase.id is null then '{}'::jsonb
                       else jsonb_build_object('ladder_evidence_id', e_chase.id, 'result', e_chase.result, 'delivered', e_chase.delivered, 'delivery', e_chase.evidence) end,
      'reason', case when e_chase.id is null then 'support has returned no result for a day-3 chase' else 'the day-3 chase was not delivered' end,
      'remedy', 'the sales engineer has support deliver the chase again and watch every channel for a reply',
      'owner', 'sales_engineer', 'remedy_key', 'chase', 'remediable', true, 'kind', 'process');
    v_items := v_items || jsonb_build_object('item', 'day5_final_call_happened',
      'passed', e_final.id is not null and e_final.delivered,
      'evidence', case when e_final.id is null then '{}'::jsonb
                       else jsonb_build_object('ladder_evidence_id', e_final.id, 'result', e_final.result, 'delivered', e_final.delivered, 'delivery', e_final.evidence) end,
      'reason', case when e_final.id is null then 'support has returned no result for the day-5 final call' else 'the day-5 final call was not delivered' end,
      'remedy', 'the sales engineer has support deliver the final call again and watch every channel for a reply',
      'owner', 'sales_engineer', 'remedy_key', 'final_call', 'remediable', true, 'kind', 'process');

    -- 4. The supplier did not respond to either party, on any channel.
    select count(*), (array_agg(e.evidence order by e.id desc))[1] into v_proofs, v_proof_ev
      from public.refund_ladder_evidence e where e.transaction_id = t.id and e.result = 'proof_of_response';
    v_live := coalesce((public.fn_refund_state(t.id)->>'supplier_responded')::boolean, false)
              or exists (select 1 from public.supplier_response_watch w where w.transaction_id = t.id and w.first_response_at is not null);
    v_items := v_items || jsonb_build_object('item', 'supplier_never_responded',
      'passed', v_proofs = 0 and not v_live
                and coalesce(e_chase.result, '') = 'no_response_confirmation' and coalesce(e_chase.delivered, false)
                and coalesce(e_final.result, '') = 'no_response_confirmation' and coalesce(e_final.delivered, false),
      'evidence', jsonb_build_object('proofs_of_response', v_proofs, 'latest_proof', v_proof_ev, 'responded_by_live_record', v_live,
                                     'chase_result', e_chase.result, 'final_call_result', e_final.result),
      'reason', case when v_proofs > 0 or v_live then 'the supplier responded' || coalesce(': ' || (v_proof_ev->'reply')::text, '')
                     else 'silence is not confirmed on both steps: a result is missing, or the delivery behind it failed' end,
      'remedy', 'the sales engineer has support make the final call again and return proof or a confirmed no-response',
      'owner', 'sales_engineer', 'remedy_key', 'final_call', 'remediable', v_proofs = 0 and not v_live, 'kind', 'process');

    -- 5. None of the exclusions in the signed terms applies.
    v_prior := exists (select 1 from public.transactions x where x.customer_id = t.customer_id and x.supplier_id = t.supplier_id
                         and x.id <> t.id and x.revealed_at < t.revealed_at);
    v_hired := exists (select 1 from public.inquiries i where i.id = t.inquiry_id and i.status in ('completed', 'closed') and i.hired_supplier_id = t.supplier_id);
    v_rated := exists (select 1 from public.reviews v where v.transaction_id = t.id);
    v_offp := coalesce(r.reason_note, '') ~* 'off.?platform'
              or exists (select 1 from public.supplier_response_watch w where w.transaction_id = t.id and coalesce(w.close_reason, '') ~* 'off.?platform');
    if not v_unresp then v_excl := v_excl || ('the reason is ' || v_reason || ', not supplier non-response (price dissatisfaction and a change of mind are not refundable)'); end if;
    if v_prior then v_excl := v_excl || 'the customer revealed this same supplier before'::text; end if;
    if v_hired then v_excl := v_excl || 'the customer completed the job with this supplier'::text; end if;
    if v_rated then v_excl := v_excl || 'the customer already rated this supplier'::text; end if;
    if v_offp then v_excl := v_excl || 'the customer engaged the supplier off the platform'::text; end if;
    v_items := v_items || jsonb_build_object('item', 'no_refund_exclusion_applies',
      'passed', cardinality(v_excl) = 0,
      'evidence', jsonb_build_object('reason_code', v_reason, 'same_supplier_revealed_before', v_prior, 'job_completed_with_supplier', v_hired,
                                     'supplier_rated', v_rated, 'off_platform_engagement_recorded', v_offp,
                                     'supplier_responded', 'checked by supplier_never_responded'),
      'reason', array_to_string(v_excl, '; '), 'remedy', 'none: an exclusion in the signed terms means the refund is declined',
      'owner', 'sales_engineer', 'remedy_key', 'decline', 'remediable', false, 'kind', 'process');

    -- 6. The amount is exactly what the customer paid.
    v_exp := round(coalesce(v_total, 0) * 100)::bigint;
    v_items := v_items || jsonb_build_object('item', 'amount_equals_total_charged',
      'passed', r.id is not null and r.amount_fils = v_exp and v_exp > 0,
      'evidence', jsonb_build_object('refund_id', r.id, 'refund_fils', r.amount_fils, 'total_charged_fils', v_exp,
                                     'total_charged_recorded', t.total_charged is not null, 'stripe_reference', t.payment_ref),
      'reason', case when r.id is null then 'there is no open refund request on this payment' else 'the refund amount is not what the customer paid' end,
      'remedy', 'the accountant sets the refund to the payment''s total_charged',
      'owner', 'accountant', 'remedy_key', 'amount', 'remediable', r.id is not null, 'kind', 'money');

  elsif p_phase = 'verify' then
    select count(*), coalesce(sum(x.amount_fils), 0) into v_succ, v_succ_fils
      from public.refunds x
     where x.status = 'succeeded' and (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref));
    -- A top-up the playbook issued is not a duplicate: its Stripe id is on the incident fix.
    select count(*) into v_extra
      from public.refunds x
     where x.status = 'succeeded' and (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref))
       and not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'incident.fix'
                        and a.evidence->>'stripe_refund_id' = x.stripe_refund_id);
    -- The platform refund the CEO approved, whatever state it reached. An external row Stripe reported
    -- (a top-up, a dashboard refund) is never it.
    select * into rs from public.refunds x where x.transaction_id = t.id
       and lower(coalesce(x.requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe') order by x.id desc limit 1;
    v_rid := rs.id;
    select * into ap from public.ceo_approval a where a.decision_id = rs.refund_decision_id;
    v_actual := case when v_succ > 0 then round(v_succ_fils / 100.0, 2)
                     when t.refund_status in ('refunded', 'succeeded') then t.refund_amount_aed end;
    v_approved := coalesce(ap.amount_aed, v_total);
    v_loss := coalesce((select sum(l.debit) from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
                         where g.source = 'refund_over_loss' and g.source_ref like t.id::text || ':%' and l.account_code = '6900'), 0);

    v_items := v_items || jsonb_build_object('item', 'ceo_approved_this_refund',
      'passed', ap.decision_id is not null and ap.decision = 'approved' and ap.subject_id = v_rid::text and ap.superseded_by is null,
      'evidence', jsonb_build_object('decision_id', ap.decision_id, 'decision', ap.decision, 'subject_id', ap.subject_id, 'refund_id', v_rid),
      'reason', 'money moved without a CEO approval naming this refund', 'kind', 'moved_without_ceo_approval', 'remediable', false);

    v_items := v_items || jsonb_build_object('item', 'stripe_refund_succeeded',
      'passed', (v_succ > 0 and exists (select 1 from public.refunds x
                                         where (x.transaction_id = t.id or (coalesce(t.payment_ref, '') <> '' and x.stripe_payment_intent = t.payment_ref))
                                           and x.status = 'succeeded' and x.stripe_refund_id is not null))
                or (v_succ = 0 and t.refund_stripe_id is not null and t.refund_status in ('refunded', 'succeeded')),
      'evidence', jsonb_build_object('refund_status', rs.status, 'stripe_refund_id', coalesce(rs.stripe_refund_id, t.refund_stripe_id), 'failure_reason', rs.failure_reason),
      'reason', 'Stripe has not settled the refund (' || coalesce(rs.status, t.refund_status, 'unknown') || ')', 'kind', 'stripe_failed_or_pending', 'remediable', true);

    v_kind := case when coalesce(v_actual, 0) = 0 then 'stripe_failed_or_pending'
                   when v_approved is distinct from v_total then 'approved_amount_is_not_total_charged'
                   when v_actual < v_approved then 'under_refund'
                   when v_actual > v_approved then 'over_refund' end;
    v_items := v_items || jsonb_build_object('item', 'money_moved_as_approved',
      'passed', v_actual is not null and v_approved = v_total
                and (v_actual = v_approved or (v_actual > v_approved and v_loss >= v_actual - v_approved)),
      'evidence', jsonb_build_object('approved_aed', v_approved, 'actual_aed', v_actual, 'total_charged_aed', v_total,
                                     'difference_aed', v_actual - v_approved, 'over_refund_loss_booked_aed', v_loss, 'settled_refunds', v_succ),
      'reason', 'approved AED ' || coalesce(v_approved::text, '?') || ', refunded AED ' || coalesce(v_actual::text, 'nothing') || ', total charged AED ' || coalesce(v_total::text, '?'),
      'kind', v_kind, 'remediable', true);

    v_items := v_items || jsonb_build_object('item', 'no_duplicate_refund',
      'passed', v_extra <= 1 or v_loss >= coalesce(v_actual - v_approved, 0),
      'evidence', jsonb_build_object('settled_refunds_not_issued_by_a_fix', v_extra),
      'reason', v_extra || ' refunds settled on one payment', 'kind', 'duplicate_refund', 'remediable', true);

    -- What follows the money (the supplier's charge, the two messages) is checked only once money
    -- actually moved; a refund Stripe has not settled is the retry's business, not a missed message.
    if coalesce(v_actual, 0) > 0 and v_unresp then
      select * into du from public.supplier_dues where transaction_id = t.id and coalesce(status, '') <> 'cancelled' order by id limit 1;
      v_charge := public.fn_accountant_nonresponse_charge(t.id, null);
      v_sent := du.id is not null and exists (
        select 1 from public.agent_actions a join public.notifications n on n.id = (a.evidence->>'notification_id')::bigint
         where a.kind = 'handoff' and a.agent = 'customer_support' and a.target_id = 'delivery.request:nonresponse_charge:' || du.id
           and (n.status = 'sent' or n.sent_at is not null));
      v_items := v_items || jsonb_build_object('item', 'supplier_charge_raised_correctly',
        'passed', du.id is not null and coalesce((v_charge->>'ok')::boolean, false)
                  and du.amount_due = (v_charge->>'refunded_aed')::numeric and du.admin_fee = (v_charge->>'admin_fee_aed')::numeric
                  and du.due_date = (v_charge->>'due_date')::date,
        'evidence', jsonb_build_object('due_id', du.id, 'charged', jsonb_build_object('amount_due', du.amount_due, 'admin_fee', du.admin_fee, 'due_date', du.due_date),
                                       'expected', v_charge, 'charge_message_sent', v_sent),
        'reason', case when du.id is null then 'no supplier charge was raised' else 'the supplier charge does not match the refund record' end,
        'kind', case when du.id is null then 'charge_missing' when v_sent then 'wrong_charge_sent' else 'wrong_charge_unsent' end, 'remediable', true);
    end if;

    if coalesce(v_actual, 0) > 0 then
    v_told := exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                        and a.target_id = 'refund.paid:' || t.id and a.status = 'done')
              and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                            and a.target_id = 'delivery.request:refund_issued:' || t.id and a.status = 'done'
                            and coalesce((a.evidence->>'delivered')::boolean, false));
    v_items := v_items || jsonb_build_object('item', 'customer_told',
      'passed', v_told, 'evidence', jsonb_build_object('handoff', 'refund.paid:' || t.id, 'delivery', 'delivery.request:refund_issued:' || t.id),
      'reason', 'the customer''s refund message was not handed off and delivered', 'kind', 'missed_handoff', 'remediable', true);
    if v_unresp and du.id is not null then
      v_sup_told := exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'sales_engineer'
                              and a.target_id in ('nonresponse.charge_raised:' || du.id, 'charge.corrected:' || du.id) and a.status = 'done')
                    and exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                                  and a.target_id in ('delivery.request:nonresponse_charge:' || du.id, 'delivery.request:charge_corrected:' || du.id)
                                  and a.status = 'done' and coalesce((a.evidence->>'delivered')::boolean, false));
      v_items := v_items || jsonb_build_object('item', 'supplier_told',
        'passed', v_sup_told, 'evidence', jsonb_build_object('handoff', 'nonresponse.charge_raised:' || du.id),
        'reason', 'the supplier''s charge message was not handed off and delivered', 'kind', 'missed_handoff', 'remediable', true);
    end if;
    end if;
  else
    raise exception 'phase is approve or verify, not %', p_phase;
  end if;

  select coalesce(jsonb_agg(i), '[]'::jsonb) into v_failed from jsonb_array_elements(v_items) i where not coalesce((i->>'passed')::boolean, false);
  v_ok := jsonb_array_length(v_failed) = 0;
  if p_record then
    insert into public.refund_ceo_check (transaction_id, refund_id, phase, item, passed, reason, evidence)
    select t.id, v_rid, p_phase, i->>'item', coalesce((i->>'passed')::boolean, false),
           case when coalesce((i->>'passed')::boolean, false) then null else i->>'reason' end, coalesce(i->'evidence', '{}'::jsonb)
      from jsonb_array_elements(v_items) i;
  end if;
  return jsonb_build_object('ok', v_ok, 'phase', p_phase, 'transaction_id', t.id, 'refund_id', v_rid, 'items', v_items, 'failed', v_failed);
end $fn$;
revoke execute on function public.fn_ceo_refund_checklist(uuid, text, boolean) from public, anon, authenticated;

-- ── ONE LIVE PLATFORM REFUND PER PAYMENT, FOR EVERY WRITER ───────────────────────────────────────
-- PR #640 review: the retired refunds_api 'resolve' paid straight off transactions under one Stripe
-- idempotency key while execute_refunds paid the refunds row under another, so one reveal could be
-- refunded twice. 'resolve' is gone; this makes the table itself refuse a second LIVE platform refund
-- on the same payment, whichever routine writes it (fn_refund_open_from_customer, fn_refund_request,
-- or anything added later). A failed, rejected or cancelled case does not count, so a new case can
-- follow one that ended. Refunds Stripe reported (stripe_webhook / stripe_dashboard / stripe) are
-- facts, not requests, and a top-up the mismatch playbook issues is recorded that way, so they are
-- outside it. Measured before adding it: 0 rows in public.refunds, 0 transactions that would violate.
--
-- RE-REVIEW, SAME DAY: the CEO's mismatch playbook also sent money (accountant incident fixes
-- 'refund_difference' and 'retry_refund') straight to Stripe and recorded it afterwards through
-- fn_refund_settle, which files a refund it does not recognise as an external row with NO
-- transaction_id -- outside the index above and outside any per-payment total. A top-up is a
-- legitimate second refund, so it is modelled, not forbidden:
--   * refunds.topup_of names the case a row tops up. The index holds ONE live CASE per payment;
--   * a01 caps every live platform write: what is live on a payment (its rows, and any refund Stripe
--     reported against its payment reference) may never exceed total_charged. It locks the
--     transaction row, so two writers cannot both pass the sum;
--   * fn_accountant_reserves_topup reserves a capped top-up row BEFORE Stripe is called, idempotent per
--     fix, citing the case's CEO decision -- the CEO approved returning what was paid, and a top-up is
--     the rest of that same approved amount (z05 accepts that one citation and no other).
alter table public.refunds add column if not exists topup_of bigint references public.refunds(id);
comment on column public.refunds.topup_of is
  'Set on a top-up: the refund case (id) whose approved amount this row completes. Null on a case. A top-up is reserved by fn_accountant_reserves_topup and capped by a01 at what the customer paid (PR #640, 14 Sep 2026).';

create unique index if not exists refunds_one_live_platform_refund_per_payment
  on public.refunds (transaction_id)
  where transaction_id is not null and topup_of is null
    and status not in ('failed', 'rejected', 'cancelled')
    and lower(coalesce(requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe');
comment on index public.refunds_one_live_platform_refund_per_payment is
  'At most one live platform refund CASE per payment, enforced for every writer (PR #640, 14 Sep 2026). Top-ups (topup_of) are capped by a01_refunds_never_return_more_than_was_paid instead.';

create or replace function public.fn_refunds_never_return_more_than_was_paid()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $fn$
declare t public.transactions; v_cap bigint; v_other bigint;
begin
  -- EVERY WRITER LOCKS THE PAYMENT FIRST (PR #640 re-review, 14 Sep 2026). A reservation, a case, a
  -- retry and a refund Stripe reported (fn_refund_settle writes those with no transaction_id, only the
  -- payment reference) all serialise on the same transactions row, so a webhook row cannot slip in
  -- between a reservation's sum and its insert. The lock is taken BEFORE any exemption.
  if NEW.transaction_id is not null then
    select * into t from public.transactions where id = NEW.transaction_id for update;
  elsif coalesce(btrim(NEW.stripe_payment_intent), '') <> '' then
    select * into t from public.transactions where payment_ref = NEW.stripe_payment_intent
     order by revealed_at desc nulls last limit 1 for update;
  end if;
  -- A refund Stripe already issued is a fact to record, never refused; it is counted below for
  -- every later writer (rows are matched by transaction OR by the payment's Stripe reference).
  if lower(coalesce(NEW.requested_by, '')) in ('stripe_webhook', 'stripe_dashboard', 'stripe') then return NEW; end if;
  if t.id is null or NEW.status in ('failed', 'rejected', 'cancelled') then return NEW; end if;   -- a00 refuses a missing transaction with its own reason
  v_cap := round(coalesce(t.total_charged, t.reveal_fee, 0) * 100)::bigint;
  select coalesce(sum(r.amount_fils), 0) into v_other
    from public.refunds r
   where r.id is distinct from NEW.id and r.status not in ('failed', 'rejected', 'cancelled')
     and (r.transaction_id = t.id or (coalesce(btrim(t.payment_ref), '') <> '' and r.stripe_payment_intent = t.payment_ref));
  if v_other + coalesce(NEW.amount_fils, 0) > v_cap then
    raise exception 'refunds: transaction % took % fils and % fils are already refunded or on their way, so % more would return more than the customer paid. (refund_exceeds_what_was_paid)',
      t.id, v_cap, v_other, coalesce(NEW.amount_fils, 0) using errcode = '23514';
  end if;
  return NEW;
end $fn$;
revoke execute on function public.fn_refunds_never_return_more_than_was_paid() from public, anon, authenticated;
drop trigger if exists a01_refunds_never_return_more_than_was_paid on public.refunds;
create trigger a01_refunds_never_return_more_than_was_paid
  before insert or update on public.refunds
  for each row execute function public.fn_refunds_never_return_more_than_was_paid();

-- THE TOP-UP, RESERVED BEFORE THE MONEY. Called by accountant execute_refunds for the playbook's
-- 'refund_difference'. The amount is capped at what is left of total_charged; the same fix asked
-- twice (a crash between the reservation and Stripe) gets the same row back.
create or replace function public.fn_accountant_reserves_topup(p_transaction_id uuid, p_amount_fils bigint, p_fix_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t public.transactions; c public.refunds; x public.refunds; v_cap bigint; v_live bigint; v_amt bigint; v_marker text;
begin
  v_marker := 'incident.fix #' || p_fix_id;
  select * into t from public.transactions where id = p_transaction_id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no such transaction'); end if;
  select * into x from public.refunds
   where transaction_id = t.id and topup_of is not null and reason_note like v_marker || ':%' order by id limit 1;
  if found then
    return jsonb_build_object('ok', true, 'refund_id', x.id, 'amount_fils', x.amount_fils, 'status', x.status, 'existing', true);
  end if;
  select * into c from public.refunds
   where transaction_id = t.id and topup_of is null and refund_decision_id is not null
     and lower(coalesce(requested_by, '')) not in ('stripe_webhook', 'stripe_dashboard', 'stripe')
   order by id desc limit 1;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no CEO-approved refund case on this payment to top up'); end if;
  v_cap := round(coalesce(t.total_charged, t.reveal_fee, 0) * 100)::bigint;
  select coalesce(sum(r.amount_fils), 0) into v_live
    from public.refunds r
   where r.status not in ('failed', 'rejected', 'cancelled')
     and (r.transaction_id = t.id or (coalesce(btrim(t.payment_ref), '') <> '' and r.stripe_payment_intent = t.payment_ref));
  v_amt := least(coalesce(p_amount_fils, 0), v_cap - v_live);
  if v_amt <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'nothing left to refund: ' || v_live || ' of the ' || v_cap || ' fils paid are already refunded or on their way',
                              'refunded_fils', v_live, 'paid_fils', v_cap);
  end if;
  insert into public.refunds
    (transaction_id, quote_id, inquiry_id, customer_id, supplier_lead_id, stripe_payment_intent, amount_fils, currency,
     reason_code, reason_note, status, requested_by, amount_source, topup_of, refund_decision_id, decided_by, decided_at)
  values
    (t.id, t.quote_id, t.inquiry_id, t.customer_id, t.supplier_id, t.payment_ref, v_amt, 'AED',
     c.reason_code, v_marker || ': the CEO''s mismatch playbook tops refund #' || c.id || ' up towards what the customer paid',
     'requested', 'accountant', 'in_platform_request', c.id, c.refund_decision_id, 'ceo', now())
  returning * into x;
  return jsonb_build_object('ok', true, 'refund_id', x.id, 'amount_fils', v_amt, 'capped', v_amt < coalesce(p_amount_fils, 0), 'case_refund_id', c.id);
end $fn$;
revoke execute on function public.fn_accountant_reserves_topup(uuid, bigint, bigint) from public, anon, authenticated;

-- THE CEO-DECISION GATE (z05), the live definition with one change: a top-up cites its case's decision.
CREATE OR REPLACE FUNCTION public.fn_refund_execution_requires_ceo_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_money_moved constant text[] := array['approved','processing','succeeded'];
  -- A refund Stripe already issued is a FACT to be recorded, not a request to be approved. Refusing
  -- the row would delete our only record of real money leaving, which is worse than admitting it.
  v_external    constant text[] := array['stripe_webhook','stripe_dashboard','stripe'];
  d public.ceo_approval%rowtype;
begin
  if not (new.status = any(v_money_moved)) then return new; end if;
  if tg_op = 'UPDATE' and old.status = any(v_money_moved)
     and new.refund_decision_id is not distinct from old.refund_decision_id then
    return new;   -- already past this boundary and not changing which decision it cites
  end if;
  if lower(coalesce(new.requested_by, '')) = any(v_external) then
    return new;
  end if;

  if new.refund_decision_id is null then
    raise exception 'refunds %: a platform-originated refund may not reach status % without naming the CEO decision that authorised it.',
      coalesce(new.id::text, '(new)'), new.status
      using errcode = '23514',
            hint = 'Record one in public.ceo_approval (subject_kind = ''refund'', subject_id = this '
                || 'refund''s id) and cite its decision_id. Founder ruling, 8 Sep 2026: all '
                || 'approvals are the CEO''s.';
  end if;

  select * into d from public.ceo_approval where decision_id = new.refund_decision_id;
  if not found then
    raise exception 'refunds %: refund_decision_id % names no CEO decision',
      coalesce(new.id::text, '(new)'), new.refund_decision_id using errcode = '23503';
  end if;
  if d.subject_kind <> 'refund' then
    raise exception 'refunds %: decision % is a % decision, not a refund decision',
      coalesce(new.id::text, '(new)'), d.decision_id, d.subject_kind using errcode = '23514';
  end if;

  -- THE BINDING THIS ROUTINE WAS MISSING UNTIL 9 SEP 2026. Everything above this line was already
  -- checked; subject_id was read and never compared, so one approved decision could authorise every
  -- refund in the table. ONE APPROVAL, ONE REFUND, ALWAYS.
  -- A TOP-UP (topup_of) completes the amount the CEO approved for its case, so it cites THAT decision
  -- (PR #640 re-review, 14 Sep 2026). Any other row still needs a decision naming itself.
  if d.subject_id is distinct from new.id::text
     and not (new.topup_of is not null and d.subject_id = new.topup_of::text) then
    raise exception 'refunds %: decision % approved refund %, not this one. One approval authorises one refund.',
      coalesce(new.id::text, '(new)'), d.decision_id, coalesce(d.subject_id, '(nothing)')
      using errcode = '23514',
            hint = 'The CEO decides each refund on its own facts. Reusing another refund''s approval '
                || 'would move money nobody approved. Record a ceo_approval row whose subject_id is '
                || 'this refund''s id, and cite that.';
  end if;

  if d.decision <> 'approved' then
    raise exception 'refunds %: decision % refused this refund; it may not reach %',
      coalesce(new.id::text, '(new)'), d.decision_id, new.status using errcode = '23514';
  end if;
  if d.superseded_by is not null then
    raise exception 'refunds %: decision % was superseded by %; cite the decision that stands',
      coalesce(new.id::text, '(new)'), d.decision_id, d.superseded_by using errcode = '23514';
  end if;
  return new;
end
$function$;


-- ── THE PROBE ────────────────────────────────────────────────────────────────────────────────────
-- Every write happens inside an inner BEGIN ... EXCEPTION block that ALWAYS ends in a raise, so the
-- subtransaction rolls back every row, handoff and queued message it made -- the probe is incapable
-- of committing anything or reaching anyone, not merely careful to clean up. Its subjects are its own
-- ZZ DEMO customer and supplier on @example.invalid. The definitions above survive (they are outside
-- the inner block). A failed assertion fails the whole apply, so a broken definition never ships.
do $probe$
declare v_out text;
begin
  begin
    declare
      v_cust uuid; v_ar uuid; v_lead bigint; v_tx uuid; v_tx2 uuid; v_tx3 uuid; v_tx4 uuid; r jsonb; r2 jsonb; v_rid bigint; v_err text; v_code text; v_n bigint; v_chk jsonb;
    begin
      insert into public.customers (id, email, email_verified, full_name, locale)
      values (gen_random_uuid(), 'zz-demo-refund-ask@example.invalid', true, 'ZZ DEMO refund ask', 'en') returning id into v_cust;
      insert into public.customers (id, email, email_verified, full_name, locale)
      values (gen_random_uuid(), 'zz-demo-refund-ask-ar@example.invalid', true, 'ZZ DEMO refund ask ar', 'ar') returning id into v_ar;
      insert into public.leads (company_name, email) values ('ZZ DEMO refund ask supplier', 'zz-demo-refund-ask-sup@example.invalid')
      returning id into v_lead;

      -- 1. PAID AN HOUR AGO: the window has not run, and the customer may still ask.
      insert into public.transactions (id, customer_id, supplier_id, revealed_at, reveal_fee, total_charged, payment_ref)
      values (gen_random_uuid(), v_cust, v_lead, now() - interval '1 hour', 30, 31.5, 'pi_ZZDEMO_ask_1') returning id into v_tx;
      r := public.fn_refund_open_from_customer(v_tx, 'customer');
      if not coalesce((r->>'ok')::boolean, false) then raise exception 'PROBE FAILED: a request inside the window was refused: %', r; end if;
      v_rid := (r->>'refund_id')::bigint;
      if (select status from public.refunds where id = v_rid) <> 'requested' then raise exception 'PROBE FAILED: case not at requested'; end if;
      if (select amount_fils from public.refunds where id = v_rid) <> 3150 then raise exception 'PROBE FAILED: amount is not total_charged'; end if;
      if (select refund_status from public.transactions where id = v_tx) <> 'requested' then raise exception 'PROBE FAILED: the sale did not follow the case'; end if;
      if not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'accountant' and a.detail->>'refund_id' = v_rid::text) then
        raise exception 'PROBE FAILED: no handoff to the accountant for refund %', v_rid; end if;
      if not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                       and a.detail->>'msg_type' = 'refund_request_received' and a.detail->>'transaction_id' = v_tx::text and a.detail->>'locale' = 'en') then
        raise exception 'PROBE FAILED: the customer confirmation was not handed to support'; end if;

      -- 2. PRESSING TWICE returns the same case.
      r2 := public.fn_refund_open_from_customer(v_tx, 'customer');
      if (r2->>'refund_id')::bigint is distinct from v_rid or not coalesce((r2->>'duplicate')::boolean, false)
         or (select count(*) from public.refunds where transaction_id = v_tx) <> 1 then
        raise exception 'PROBE FAILED: a second press opened another case: %', r2; end if;

      -- 2b. A SECOND REFUND OF THE SAME PAYMENT IS REFUSED ON EVERY OTHER PATH TOO (PR #640 review).
      -- The ladder/CEO path (fn_refund_request, what the day-5 sweep files) and a raw insert both hit
      -- refunds_one_live_platform_refund_per_payment.
      begin
        perform public.fn_refund_request(3150, 'supplier_unresponsive', 'refund_ladder_sweep', null, v_cust, v_lead, null, 'pi_ZZDEMO_ask_1', null, 'ZZ DEMO second refund', v_tx);
        v_err := 'no error';
      exception when others then v_err := sqlerrm;
      end;
      -- a01 (the cap) fires before the unique index is checked, so either refusal proves it.
      if v_err not like '%refund_exceeds_what_was_paid%' and v_err not like '%refunds_one_live_platform_refund_per_payment%' then
        raise exception 'PROBE FAILED: the ladder path opened a second refund on one payment: %', v_err; end if;
      begin
        insert into public.refunds (transaction_id, customer_id, supplier_lead_id, stripe_payment_intent, amount_fils, currency, reason_code, status, requested_by, amount_source)
        values (v_tx, v_cust, v_lead, 'pi_ZZDEMO_ask_1', 3150, 'AED', 'supplier_unresponsive', 'requested', 'accountant', 'manual');
        v_err := 'no error';
      exception when others then v_err := sqlerrm;
      end;
      if v_err not like '%refund_exceeds_what_was_paid%' and v_err not like '%refunds_one_live_platform_refund_per_payment%' then
        raise exception 'PROBE FAILED: a raw insert opened a second refund on one payment: %', v_err; end if;
      if (select count(*) from public.refunds where transaction_id = v_tx) <> 1 then
        raise exception 'PROBE FAILED: more than one refund row on one payment'; end if;

      -- 2c. THE PLAYBOOK'S TOP-UP IS A CAPPED ROW ON THE SAME RAIL (re-review). A refused CEO decision
      -- satisfies the foreign key without the approval trigger and without moving any money status.
      insert into public.ceo_approval (subject_kind, subject_id, decision, decided_by, rationale)
      values ('refund', v_rid::text, 'refused', 'ceo', 'ZZ DEMO probe: a decision row for the top-up test only') returning decision_id into v_n;
      update public.refunds set refund_decision_id = v_n where id = v_rid;
      -- With the case live for everything paid there is nothing left to top up.
      r := public.fn_accountant_reserves_topup(v_tx, 500, 9001);
      if coalesce((r->>'ok')::boolean, true) then raise exception 'PROBE FAILED: a top-up was reserved on a fully refunded payment: %', r; end if;
      begin
        insert into public.refunds (transaction_id, customer_id, supplier_lead_id, stripe_payment_intent, amount_fils, currency, reason_code, status, requested_by, amount_source, topup_of)
        values (v_tx, v_cust, v_lead, 'pi_ZZDEMO_ask_1', 1, 'AED', 'supplier_unresponsive', 'requested', 'accountant', 'in_platform_request', v_rid);
        v_err := 'no error';
      exception when others then v_err := sqlerrm;
      end;
      if v_err not like '%refund_exceeds_what_was_paid%' then raise exception 'PROBE FAILED: a raw top-up went past the cap: %', v_err; end if;
      -- The case fails in Stripe: nothing is live, so a top-up of 5000 is capped at the 3150 paid.
      update public.refunds set status = 'failed' where id = v_rid;
      r := public.fn_accountant_reserves_topup(v_tx, 5000, 9001);
      if not coalesce((r->>'ok')::boolean, false) or (r->>'amount_fils')::bigint <> 3150 or not (r->>'capped')::boolean then
        raise exception 'PROBE FAILED: the top-up was not capped at what was paid: %', r; end if;
      -- The same fix asked again gets the same row; a different fix finds nothing left.
      r2 := public.fn_accountant_reserves_topup(v_tx, 5000, 9001);
      if (r2->>'refund_id') is distinct from (r->>'refund_id') or not coalesce((r2->>'existing')::boolean, false) then
        raise exception 'PROBE FAILED: the same fix reserved a second top-up: %', r2; end if;
      r2 := public.fn_accountant_reserves_topup(v_tx, 1, 9002);
      if coalesce((r2->>'ok')::boolean, true) then raise exception 'PROBE FAILED: a second fix reserved past the cap: %', r2; end if;
      -- A top-up may only complete a case on its own payment.
      insert into public.transactions (id, customer_id, supplier_id, revealed_at, reveal_fee, total_charged, payment_ref)
      values (gen_random_uuid(), v_cust, v_lead, now() - interval '10 days', 30, 31.5, 'pi_ZZDEMO_ask_other') returning id into v_tx2;
      begin
        insert into public.refunds (transaction_id, customer_id, supplier_lead_id, stripe_payment_intent, amount_fils, currency, reason_code, status, requested_by, amount_source, topup_of)
        values (v_tx2, v_cust, v_lead, 'pi_ZZDEMO_ask_other', 1, 'AED', 'supplier_unresponsive', 'requested', 'accountant', 'in_platform_request', v_rid);
        v_err := 'no error';
      exception when others then v_err := sqlerrm;
      end;
      if v_err not like '%refund_topup_names_no_case%' then raise exception 'PROBE FAILED: a top-up of another payment''s case was not refused as such: %', v_err; end if;
      if (select coalesce(sum(amount_fils), 0) from public.refunds where transaction_id = v_tx and status not in ('failed', 'rejected', 'cancelled')) <> 3150 then
        raise exception 'PROBE FAILED: live refunds on one payment are not exactly what was paid'; end if;

      -- 2d. EVERY WRITER LOCKS THE PAYMENT, THE WEBHOOK'S ROW INCLUDED, AND IS COUNTED BY THE NEXT ONE.
      -- (i) Webhook first. fn_refund_settle records a refund Stripe reports with no transaction_id, only
      -- the payment reference; inserting it must lock that payment (xmax set) without updating it (xmin
      -- unchanged).
      insert into public.transactions (id, customer_id, supplier_id, revealed_at, reveal_fee, total_charged, payment_ref)
      values (gen_random_uuid(), v_cust, v_lead, now() - interval '10 days', 30, 31.5, 'pi_ZZDEMO_ask_hook') returning id into v_tx3;
      select xmin::text, xmax::text into v_err, v_code from public.transactions where id = v_tx3;
      if v_code <> '0' then raise exception 'PROBE FAILED: the fresh payment was already locked'; end if;
      insert into public.refunds (stripe_refund_id, stripe_payment_intent, amount_fils, amount_source, reason_code, requested_by, status)
      values ('re_ZZDEMO_hook_1', 'pi_ZZDEMO_ask_hook', 1000, 'webhook_event', 'other', 'stripe_webhook', 'succeeded');
      if (select xmax::text from public.transactions where id = v_tx3) = '0' then raise exception 'PROBE FAILED: the webhook row did not lock the payment'; end if;
      if (select xmin::text from public.transactions where id = v_tx3) <> v_err then raise exception 'PROBE FAILED: recording the webhook row changed the payment'; end if;
      -- ... and the next writer counts it: a full-amount case no longer fits (1000 + 3150 > 3150).
      begin
        perform public.fn_refund_open_from_customer(v_tx3, 'customer');
        v_err := 'no error';
      exception when others then v_err := sqlerrm;
      end;
      if v_err not like '%refund_exceeds_what_was_paid%' then raise exception 'PROBE FAILED: a case ignored the refund Stripe already reported: %', v_err; end if;
      -- (ii) Reservation first. With the top-up live on v_tx, a refund Stripe then reports on the same
      -- payment is still recorded (a fact, never refused), and after it nothing more can be reserved.
      insert into public.refunds (stripe_refund_id, stripe_payment_intent, amount_fils, amount_source, reason_code, requested_by, status)
      values ('re_ZZDEMO_hook_2', 'pi_ZZDEMO_ask_1', 500, 'webhook_event', 'other', 'stripe_webhook', 'succeeded');
      if not exists (select 1 from public.refunds where stripe_refund_id = 're_ZZDEMO_hook_2') then raise exception 'PROBE FAILED: a refund Stripe reported was refused'; end if;
      r2 := public.fn_accountant_reserves_topup(v_tx, 1, 9003);
      if coalesce((r2->>'ok')::boolean, true) then raise exception 'PROBE FAILED: a reservation ignored the webhook row: %', r2; end if;

      -- 3. THE DECISION WAITS: approving before refund_deadline is refused at the table.
      begin
        update public.refunds set status = 'approved', decided_by = 'ceo' where id = v_rid;
        v_err := 'no error';
      exception when others then v_err := sqlerrm;
      end;
      if v_err not like '%refund_window_not_yet_open%' then raise exception 'PROBE FAILED: early approval was not refused by the window: %', v_err; end if;

      -- 4. REFUSALS open nothing and leave the sale untouched: no payment, and a rated supplier.
      insert into public.transactions (id, customer_id, supplier_id, revealed_at, reveal_fee)
      values (gen_random_uuid(), v_cust, v_lead, now() - interval '2 hours', 30) returning id into v_tx2;
      r := public.fn_refund_open_from_customer(v_tx2, 'customer');
      if coalesce((r->>'ok')::boolean, true) or r->>'code' <> 'no_payment' or not (r->>'can_claim_later')::boolean then
        raise exception 'PROBE FAILED: a reveal with no payment was not refused as no_payment: %', r; end if;
      if exists (select 1 from public.refunds where transaction_id = v_tx2)
         or (select refund_status from public.transactions where id = v_tx2) = 'requested' then
        raise exception 'PROBE FAILED: a refusal changed something'; end if;
      if not exists (select 1 from public.company_event e where e.event_type = 'refund.request_refused' and e.entity_id = v_tx2::text) then
        raise exception 'PROBE FAILED: the refusal was not recorded'; end if;
      insert into public.transactions (id, customer_id, supplier_id, revealed_at, reveal_fee, total_charged, payment_ref)
      values (gen_random_uuid(), v_cust, v_lead, now() - interval '3 hours', 30, 31.5, 'pi_ZZDEMO_ask_3') returning id into v_tx3;
      insert into public.reviews (supplier_id, customer_id, transaction_id, rating, comment) values (v_lead, v_cust, v_tx3, 5, 'ZZ DEMO probe review');
      r := public.fn_refund_open_from_customer(v_tx3, 'customer');
      if coalesce((r->>'ok')::boolean, true) or r->>'code' <> 'supplier_rated' then raise exception 'PROBE FAILED: a rated supplier was not refused: %', r; end if;

      -- 5. ARABIC: the customer registered in Arabic is answered and written to in Arabic.
      insert into public.transactions (id, customer_id, supplier_id, revealed_at, reveal_fee, total_charged, payment_ref)
      values (gen_random_uuid(), v_ar, v_lead, now() - interval '10 days', 30, 31.5, 'pi_ZZDEMO_ask_4') returning id into v_tx4;
      r := public.fn_refund_open_from_customer(v_tx4, 'customer');
      if not coalesce((r->>'ok')::boolean, false) or r->>'locale' <> 'ar' or r->>'message_ar' is null then
        raise exception 'PROBE FAILED: the Arabic customer was not answered in Arabic: %', r; end if;
      if not exists (select 1 from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
                       and a.detail->>'msg_type' = 'refund_request_received' and a.detail->>'transaction_id' = v_tx4::text and a.detail->>'locale' = 'ar') then
        raise exception 'PROBE FAILED: the Arabic confirmation was not handed to support in Arabic'; end if;

      -- 6. THE CHECKLIST no longer refuses a customer for not complaining within 7 days with proof.
      v_chk := public.fn_ceo_refund_checklist(v_tx4, 'approve', false);
      if not exists (select 1 from jsonb_array_elements(v_chk->'items') i where i->>'item' = 'customer_complaint_on_record' and (i->>'passed')::boolean) then
        raise exception 'PROBE FAILED: checklist item 1 still refuses: %', v_chk->'failed'; end if;
      if exists (select 1 from jsonb_array_elements(v_chk->'items') i where i->>'item' = 'complaint_within_7_days_with_proof') then
        raise exception 'PROBE FAILED: the 7-day item is still asserted'; end if;

      select count(*) into v_n from public.agent_actions a where a.kind = 'handoff' and a.agent = 'customer_support'
         and a.detail->>'msg_type' = 'refund_request_received' and a.detail->>'to_email' not like '%@example.invalid';
      if v_n > 0 then raise exception 'PROBE FAILED: a confirmation addressed someone outside @example.invalid'; end if;

      raise exception 'PROBE_OK request inside the window opened case % at requested for 3150 fils, sale requested, accountant handoff + support confirmation (en); second press returned the same case; a second refund on the same payment refused on the ladder path (fn_refund_request) and by a raw insert (a01 cap / one-case index); top-up: none reserved while the case is live, a raw top-up refused past the cap, after the case failed a 5000-fils top-up capped at 3150, the same fix returned the same row, a second fix and another payment''s case refused, live total exactly 3150; a webhook row locked its payment (xmax set, xmin unchanged) and the next case counted it and was refused, and a webhook row after a live reservation was recorded and blocked the next reservation; early approval refused (refund_window_not_yet_open); no_payment and supplier_rated refused, recorded, nothing changed; Arabic customer answered and written to in Arabic; checklist item 1 passes with no complaint', v_rid;
    end;
  exception when others then v_out := sqlerrm;
  end;
  if v_out is null or v_out not like 'PROBE_OK%' then raise exception '%', coalesce(v_out, 'PROBE FAILED: no result'); end if;
  perform set_config('qd.probe_out', v_out, false);
  raise notice '%', v_out;
end
$probe$;
