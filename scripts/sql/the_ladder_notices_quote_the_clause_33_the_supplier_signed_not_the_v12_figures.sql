-- THE LADDER NOTICES QUOTE THE CLAUSE 33 THE SUPPLIER SIGNED, NOT THE v12 FIGURES.
--
-- Assigned: accountant (money terms). 6 Oct 2026. Founder ledger 1122 ("nothing that could lead into us being sued").
--
-- MEASURED (legal audit, 6 Oct 2026): fn_sales_engineer_ladder_step, canonical in
-- every_arabic_message_is_written_not_translated.sql (MANIFEST 1567), tells a silent supplier in its 'chase' and
-- 'final_call' notices, in English and Arabic, that the refund is recovered "with an administrative fee of AED 250
-- and interest at 9% a year". For a supplier who accepted Supplier Agreement v13 or later before the reveal the fee
-- is AED 500 (decision_policy.supplier_nonresponse_admin_fee_from_v13_aed), and for v14 the agreed rate is 12% plus
-- the unrecoverable processor fee (fn_accountant_nonresponse_charge). A written notice that understates what we then
-- claim is a notice the claim can be challenged on. The reveal notice (fn_sales_engineer_acts_on_handoff) was already
-- moved to "the amounts set out in clause 33 of the Supplier Agreement you accepted" by
-- the_nonresponse_charge_is_the_maximum_uae_law_safely_allows.sql; this gives the two ladder notices the same words.
-- The itemised charge notice (nonresponse.charge_raised) already prints the computed fee and rate per supplier.
--
-- WHAT THIS CHANGES: four sentences (two EN, two AR) of the 'chase' and 'final_call' bodies. Nothing else in the
-- routine. WHAT IT DOES NOT CHANGE: the amounts charged.
--   node scripts/apply_sql.mjs scripts/sql/the_ladder_notices_quote_the_clause_33_the_supplier_signed_not_the_v12_figures.sql --apply --ddl --seat accountant

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
        || '). Under the Supplier Agreement you accepted, that amount is then recovered from your account with the administrative fee, interest and other amounts set out in its clause 33, and matching is paused until it is paid.' || E'\n\n'
        || 'If you have already been in touch with this customer, reply here and we will close this off.',
      'إجراء مطلوب: عميل بانتظار ردّكم — QuotesDone',
      'سدّد أحد العملاء رسوم الكشف عن بيانات التواصل معكم بتاريخ ' || v_when || ' ولم يتلقَّ منكم ردًّا بعد مرور ' || v_chase || ' أيام عمل، والعميل مُدرَج في نسخة هذه الرسالة. '
        || 'وتُلزم اتفاقية المورّد بالرد خلال ' || v_window || ' أيام عمل من تاريخ الكشف، وإلا فسيُردّ إلى العميل كامل ما دفعه (' || v_amt
        || ' درهم)، ويُسترد من حسابكم المبلغ المردود مع الرسم الإداري والفائدة وسائر المبالغ المبيّنة في البند 33 من اتفاقية المورّد التي قبلتموها، ويُعلَّق إسناد الطلبات إليكم حتى السداد. وإن كنتم قد تواصلتم مع العميل، فيُرجى الرد على هذه الرسالة.',
      array_remove(array[cust.email], null), v_key, v_watch, v_extra);

  elsif p_step = 'final_call' then
    v_watch := public.fn_add_working_days(now(), v_days);
    return public.fn_sales_engineer_writes('refund_final_notice', 'supplier', sup.email, t.supplier_id, null, t.inquiry_id, t.quote_id,
      'Final call: a customer is still waiting — QuotesDone reveal #' || left(t.id::text, 8),
      'Hello ' || coalesce(sup.company_name, '') || E',\n\n'
        || 'This is our final call about the customer who paid to reveal your contact details on ' || v_when
        || '. The ' || v_window || ' working days the Supplier Agreement allows have passed with no response from you, to the customer or to our reminder.' || E'\n\n'
        || 'If we do not hear from you by ' || to_char(v_watch at time zone 'Asia/Dubai', 'DD Mon YYYY')
        || ', the customer is refunded everything they paid (AED ' || v_amt || ') and that amount is recovered from your account with the administrative fee, interest and other amounts set out in clause 33 of the Supplier Agreement you accepted. '
        || 'Reply to this email, message the customer in your portal, or answer us on WhatsApp — any of them stops this.',
      'نداء أخير: عميل لا يزال بانتظار ردّكم — QuotesDone',
      'هذا نداؤنا الأخير بشأن العميل الذي كشف عن بيانات التواصل معكم بتاريخ ' || v_when || '، وقد انقضت أيام العمل المحددة دون ردّ منكم. '
        || 'فإن لم يصلنا ردّكم حتى ' || to_char(v_watch at time zone 'Asia/Dubai', 'DD Mon YYYY') || ' فسيُردّ إلى العميل كامل ما دفعه (' || v_amt
        || ' درهم)، ويُسترد من حسابكم المبلغ المردود مع الرسم الإداري والفائدة وسائر المبالغ المبيّنة في البند 33 من اتفاقية المورّد التي قبلتموها. ويكفي أي ردّ منكم عبر البريد الإلكتروني أو البوابة أو واتساب لإيقاف ذلك.',
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

select case when pg_get_functiondef('public.fn_sales_engineer_ladder_step(uuid,text,bigint,bigint)'::regprocedure) ~ '(AED 250|250 درهم|9% a year|9% سنوي)'
            then 'PROBE FAILED: a ladder notice still quotes AED 250 / 9%'
            else 'PROBE OK: the ladder notices point to clause 33 of the signed agreement' end as verdict;
