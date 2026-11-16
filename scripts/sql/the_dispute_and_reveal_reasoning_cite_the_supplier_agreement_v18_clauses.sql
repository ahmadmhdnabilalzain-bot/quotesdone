-- THE DISPUTE AND REVEAL REASONING CITE THE SUPPLIER AGREEMENT v18 CLAUSES.
--
-- Assigned: ceo (disputes) + customer_support (the dispute file). Agent: simplify_build_D, 16 Nov 2026. Founder ledgers
-- 1714/1715. Audit: scratchpad audit_simplify/STALE.md S8.
--
-- READ (16 Nov 2026): the live agreement is v18 (supabase/functions/_shared/supplier_agreement.ts, "v18 · Last updated 15
-- November 2026"); its numbering is the same as v17's (git 05d7cbd85): 8 Payment terms, 9 Late payment, 11 Supplier
-- obligations & conduct ("honour every quotation it submits and any agreed timeline"), 12 Quotations & the supplier-customer
-- contract ("the Supplier is bound by a quotation that is revealed within that validity period"), 19 Suspension &
-- termination, 33 Response obligation and non-response charge. The production bodies cited "v17 clause 9" for the binding
-- quotation and "clause 8" for honouring it, i.e. Late payment and Payment terms, wrong under v17 too:
--   fn_reveal_job_facts (md5 a327c5a0047f85446a5d5817a4178bb1)              'v17 clause 9 ... clause 8'
--   fn_ceo_post_reveal_dispute_tick (md5 77f70f2b5aa55f52c8a876ec00bdbd58)  'v17 clause 8 ..., clause 9 ..., clause 19'
--   fn_ceo_decides_post_reveal_dispute (md5 6161af7a22dfc1555f784c3f02d71553) 'v17 clauses 8 and 19', and the formal
--     warning e-mail it writes to the SUPPLIER: "a formal warning under clauses 8 and 19 of the Supplier Agreement"
--   fn_reveal_contact_record (md5 0789c85e75d99b73aba1b090e25a41d9)          'v17 clause 33' (number right, version old)
--   fn_customer_support_dispute_open (md5 e07c322317016e1fe419f53d66fcdafe)  a comment, 'v17 clause 9'
-- These texts go to the CEO's dispute reasoning and the reveal's job facts. Each now cites v18: 12 (bound), 11 (honour), 19,
-- 33. Nothing else in the bodies changes. Version-specific history (v13 clause 33(b), v16 clause 13 in
-- fn_accountant_nonresponse_charge and fn_sales_engineer_verifies_supplier) is correct as history and is not touched.
-- prevented by: the verdict row at the end of this file.
set local lock_timeout = '3s';

create or replace function public.fn_reveal_job_facts(p_transaction uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select jsonb_strip_nulls(jsonb_build_object(
           'transaction_id', t.id, 'rfq_no', i.rfq_no, 'trade', coalesce(i.category, i.trades[1]),
           'revealed_at', t.revealed_at, 'supplier', l.company_name, 'reveal_fee_paid_aed', round(coalesce(t.total_charged, t.reveal_fee, 0), 2),
           'quote', jsonb_strip_nulls(jsonb_build_object(
              'quote_id', q.id, 'amount_aed', q.quote_amount, 'price_ex_vat_aed', q.price_ex_vat, 'vat_aed', q.vat_amount,
              'discount_aed', q.discount_amount, 'scope', left(q.scope, 1500), 'exclusions', left(q.exclusions, 800),
              'conditions', left(q.conditions, 800), 'warranty', left(q.warranty, 400), 'lead_time', left(q.lead_time, 200),
              'validity', left(q.validity, 200), 'payment_terms', left(q.payment_terms, 400), 'submitted_at', q.created_at)),
           'binding_rule', 'Supplier Agreement v18 clause 12: the supplier is bound by a quotation revealed within its validity; clause 11: honour every quotation and any agreed timeline'))
    from public.transactions t
    left join public.quotes q on q.id = t.quote_id
    left join public.inquiries i on i.id = t.inquiry_id
    left join public.leads l on l.id = t.supplier_id
   where t.id = p_transaction
$function$
;

create or replace function public.fn_ceo_post_reveal_dispute_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on'; d record; v_q bigint; v_asked int := 0;
begin
  for d in select p.*, (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) as demo, 'QD-D-' || lpad(p.id::text, 5, '0') as ref
             from public.post_reveal_dispute p left join public.customers c on c.id = p.customer_id
            where p.stage = 'ceo_decision' and p.decision_question_id is null
              and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
            order by p.id for update of p skip locked loop
    v_q := public.fn_seat_duty_reason('ceo', 'ceo.post_reveal_dispute',
      case when d.demo then 'ZZ DEMO ' else '' end
      || 'A customer and a supplier disagree about a job after the supplier''s details were revealed. The sales engineer has made a finding and it has been reviewed. '
      || 'Decide the outcome, what the customer receives and what happens to the supplier. Say why, on the evidence of both parties.',
      public.fn_ceo_post_reveal_dispute_options(),
      jsonb_build_object('dispute', d.ref, 'raised_by', d.raised_by, 'opened_at', d.opened_at, 'statement', d.statement,
        'customer_evidence', d.customer_evidence, 'supplier_evidence', d.supplier_evidence, 'job_on_record', d.job_facts,
        'sales_engineer_finding', d.finding, 'finding_reasoning', left(d.finding_reasoning, 3000), 'cross_review', d.review,
        'customer_contact', public.fn_reveal_contact_word(d.transaction_id),
        'supplier_standing', jsonb_build_object(
          'upheld_complaints_before', (select count(*) from public.supplier_strike_event e where e.lead_id = d.supplier_id and e.kind = 'dispute_upheld'),
          'matching_blocked', (select coalesce(l.matching_blocked, false) from public.leads l where l.id = d.supplier_id),
          'blocked_for', (select l.matching_block_reason from public.leads l where l.id = d.supplier_id)),
        'decision_due', d.decision_due,
        'rules', 'Supplier Agreement v18 clause 11 (honour every quotation and agreed timeline), clause 12 (bound by a revealed quotation), clause 19 (suspension for breach); Complaints Policy v1.4 section 4 (quality and conduct are between the parties; our role is facilitation); Terms v11 clause 5'),
      jsonb_build_object('dispute_id', d.id, 'customer_id', d.customer_id), 'post_reveal_dispute_decision:' || d.id);
    update public.post_reveal_dispute set decision_question_id = v_q where id = d.id and v_q is not null;
    v_asked := v_asked + 1;
  end loop;
  return jsonb_build_object('asked', v_asked, 'fixture', v_fx);
end $function$
;

create or replace function public.fn_ceo_decides_post_reveal_dispute(p_id bigint, p_outcome text, p_note text, p_remedy text DEFAULT 'none'::text, p_supplier_action text DEFAULT 'none'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d public.post_reveal_dispute; t public.transactions; c record; s record; v_ref text; v_en text; v_ar text; v_effect jsonb := '{}'::jsonb;
  v_rem_en text := ''; v_rem_ar text := ''; v_sup_en text := ''; v_upheld boolean; v_rf jsonb; v_strikes int; v_paused int := 0;
  v_over bigint := 0; v_blocked_before boolean; v_block_reason text;
begin
  if p_outcome is null or p_outcome not in ('customer_upheld', 'supplier_upheld', 'shared', 'no_fault') then
    raise exception 'the outcome is customer_upheld, supplier_upheld, shared or no_fault, not %', p_outcome;
  end if;
  if coalesce(p_remedy, 'none') not in ('none', 'refund_reveal_fee', 'next_reveal_free') then
    raise exception 'the remedy is none, refund_reveal_fee or next_reveal_free, not %', p_remedy;
  end if;
  if coalesce(p_supplier_action, 'none') not in ('none', 'warning', 'pause_matching') then
    raise exception 'the supplier action is none, warning or pause_matching, not %', p_supplier_action;
  end if;
  v_upheld := p_outcome in ('customer_upheld', 'shared');
  if not v_upheld and (coalesce(p_remedy, 'none') <> 'none' or coalesce(p_supplier_action, 'none') <> 'none') then
    raise exception 'a remedy or a supplier action follows only a complaint that is upheld or shared, not %', p_outcome;
  end if;
  update public.post_reveal_dispute set stage = 'decided', outcome = p_outcome, outcome_note = p_note,
         decided_by = 'ceo', decided_at = now(), remedy = coalesce(p_remedy, 'none'), supplier_action = coalesce(p_supplier_action, 'none')
   where id = p_id and stage in ('review', 'ceo_decision') returning * into d;
  if not found then raise exception 'dispute % is not awaiting a decision', p_id; end if;
  update public.it_engineer_finding set closed_at = now(), close_note = 'the CEO decided the dispute'
   where issue_key = 'dispute_decision_overdue:' || p_id and closed_at is null;
  select * into t from public.transactions where id = d.transaction_id;
  v_ref := 'QD-D-' || lpad(d.id::text, 5, '0');

  -- SUPPLIER STANDING: an upheld (or shared) complaint is on the supplier's record, append-only; the count of chat strikes (the
  -- no-quote rule) is not changed by it.
  if v_upheld then
    select coalesce(l.chat_strikes, 0) into v_strikes from public.leads l where l.id = d.supplier_id;
    insert into public.supplier_strike_event (lead_id, inquiry_id, kind, strikes_after, detail)
    values (d.supplier_id, d.inquiry_id, 'dispute_upheld', coalesce(v_strikes, 0),
            jsonb_build_object('dispute_id', d.id, 'ref', v_ref, 'outcome', p_outcome, 'supplier_action', coalesce(p_supplier_action, 'none'),
                               'rule', 'Supplier Agreement v18 clauses 11 and 19'));
    v_effect := v_effect || jsonb_build_object('strike_event', true);
  end if;
  if p_supplier_action = 'pause_matching' then
    -- THE PAUSE HAS AN END (review AFTERREVEAL item 6): pause_until from decision_policy (working days); fn_ceo_lifts_dispute_pause
    -- lifts it on the CEO's decision or at that date (duty ceo.dispute_pause). A supplier ALREADY blocked for another reason (a
    -- licence, an unpaid charge) is not overwritten: the skip is recorded with that reason, and the pause is applied by the duty
    -- once the other block lifts, while pause_until has not passed.
    select coalesce(l.matching_blocked, false), l.matching_block_reason into v_blocked_before, v_block_reason from public.leads l where l.id = d.supplier_id;
    update public.post_reveal_dispute
       set pause_until = public.fn_add_working_days(now(), coalesce((select (value::text)::int from public.decision_policy where key = 'dispute_pause_matching_working_days'), 20))
     where id = d.id;
    update public.leads set matching_blocked = true, matching_block_reason = 'dispute_upheld'
     where id = d.supplier_id and not coalesce(matching_blocked, false);
    get diagnostics v_paused = row_count;
    v_effect := v_effect || jsonb_build_object('matching_paused', v_paused > 0,
      'pause_until', (select pause_until from public.post_reveal_dispute where id = d.id))
      || case when v_paused = 0 then jsonb_build_object('pause_skipped', 'already blocked', 'blocked_for', coalesce(v_block_reason, 'no reason recorded'))
              else '{}'::jsonb end;
    v_sup_en := ' Under clause 19 of the Supplier Agreement your account is paused from new requests until '
      || to_char((select pause_until from public.post_reveal_dispute where id = d.id) at time zone 'Asia/Dubai', 'DD Mon YYYY')
      || ', or earlier once we have reviewed it with you; reply to this e-mail to arrange that.';
  elsif p_supplier_action = 'warning' then
    v_sup_en := ' This is a formal warning under clauses 11 and 19 of the Supplier Agreement: a supplier must honour every quotation it submits and any agreed timeline, and a further breach may lead to suspension.';
  end if;

  -- THE CUSTOMER'S REMEDY
  if p_remedy = 'refund_reveal_fee' then
    -- an accountant's overcharge return on this payment is not a refund case (review AFTERREVEAL item 2, as fn_refund_open_from_customer
    -- reads it since 15 Nov): the CEO's refund is still filed, for what remains of the payment after that return (what a00 expects)
    v_over := (select coalesce(sum(o.amount_fils), 0) from public.refunds o
                where o.reason_code = 'overcharge_return' and o.status not in ('failed', 'rejected', 'cancelled')
                  and (o.transaction_id = t.id or (coalesce(btrim(t.payment_ref), '') <> '' and o.stripe_payment_intent = t.payment_ref)));
    if v_over >= round(coalesce(t.total_charged, t.reveal_fee, 0) * 100) then
      -- the whole payment was already returned: nothing is filed (fn_refund_request refuses an amount of zero)
      v_effect := v_effect || jsonb_build_object('refund', 'nothing_left');
    elsif exists (select 1 from public.refunds r
                   where (r.transaction_id = t.id or (coalesce(btrim(t.payment_ref), '') <> '' and r.stripe_payment_intent = t.payment_ref))
                     and r.status not in ('rejected', 'failed', 'cancelled')
                     and r.reason_code is distinct from 'overcharge_return') then
      -- as fn_refund_open_from_customer reads it: a refund on this payment, ours or Stripe's, keyed by either reference
      v_effect := v_effect || jsonb_build_object('refund', 'already_open');
    else
      v_rf := public.fn_refund_request(round(coalesce(t.total_charged, t.reveal_fee, 0) * 100)::bigint - v_over, 'fraud_or_dispute', 'ceo_dispute_decision',
        t.inquiry_id, t.customer_id, t.supplier_id, t.quote_id, t.payment_ref, null,
        'Dispute ' || v_ref || ' decided ' || p_outcome || ' by the CEO, who chose to refund the reveal fee. ' || coalesce(left(p_note, 1500), ''), t.id);
      v_effect := v_effect || jsonb_build_object('refund', v_rf);
    end if;
    update public.post_reveal_dispute set remedy_transaction_id = t.id, remedy_done_at = now() where id = d.id;
    if v_effect->>'refund' = 'nothing_left' then
      v_rem_en := ' Everything you paid for this reveal has already been returned to your original payment method.';
      v_rem_ar := ' وقد سبق أن رددنا إليكم كامل ما دفعتموه مقابل هذا الكشف إلى وسيلة الدفع الأصلية.';
    elsif v_over > 0 then
      v_rem_en := ' As a result, everything still owed to you for this reveal (AED ' || round((round(coalesce(t.total_charged, t.reveal_fee, 0) * 100) - v_over) / 100.0, 2)
        || '; the other AED ' || round(v_over / 100.0, 2) || ' was already returned to you) is refunded to your original payment method; banks take 7 to 14 working days to show it.';
      v_rem_ar := ' وبناءً عليه، يُردّ إليكم كامل المبلغ المستحق لكم عن هذا الكشف (' || round((round(coalesce(t.total_charged, t.reveal_fee, 0) * 100) - v_over) / 100.0, 2)
        || ' درهم، إذ سبق أن رددنا إليكم ' || round(v_over / 100.0, 2) || ' درهم) إلى وسيلة الدفع الأصلية، وتستغرق البنوك من 7 إلى 14 يوم عمل لإظهاره.';
    else
      v_rem_en := ' As a result, everything you paid for this reveal is refunded to your original payment method; banks take 7 to 14 working days to show it.';
      v_rem_ar := ' وبناءً عليه، يُردّ إليكم كامل ما دفعتموه مقابل هذا الكشف إلى وسيلة الدفع الأصلية، وتستغرق البنوك من 7 إلى 14 يوم عمل لإظهاره.';
    end if;
  elsif p_remedy = 'next_reveal_free' then
    v_rem_en := ' As a result, if you reveal another supplier''s quotation on this request, everything you pay for that reveal is refunded in full; the refund is filed as soon as you pay.';
    v_rem_ar := ' وبناءً عليه، إن كشفتم عرض مورّد آخر على هذا الطلب، فسيُردّ إليكم كامل ما تدفعونه مقابل ذلك الكشف، ويُقدَّم طلب الاسترداد فور الدفع.';
  end if;
  update public.post_reveal_dispute set effect = v_effect where id = d.id;

  v_en := case p_outcome when 'customer_upheld' then 'the customer''s complaint is upheld'
    when 'supplier_upheld' then 'the supplier''s position is upheld' when 'shared' then 'responsibility is shared by both parties'
    else 'no fault was found on either side' end;
  v_ar := case p_outcome when 'customer_upheld' then 'قُبلت شكوى العميل'
    when 'supplier_upheld' then 'ثبت موقف المورّد' when 'shared' then 'المسؤولية مشتركة بين الطرفين'
    else 'لم يثبت تقصير على أي من الطرفين' end;
  select c2.email, c2.locale into c from public.customers c2 where c2.id = d.customer_id;
  select coalesce(l.claimed_by, l.email) as email into s from public.leads l where l.id = d.supplier_id;
  perform public.fn_customer_support_duty_send('dispute.decided', d.id || ':' || role, role, email,
      case when locale = 'ar' then 'ar' else 'en' end,
      case when locale = 'ar' then 'القرار في القضية ' || v_ref else 'Dispute ' || v_ref || ': the decision' end,
      case when locale = 'ar' then
        'السادة المحترمين،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'راجعنا القضية ' || v_ref || ' بعد الاطلاع على أقوال الطرفين ومستنداتهما، وانتهت المراجعة إلى أنه ' || v_ar || '.' || v_rem_ar || ' '
        || 'وإن كان لديكم اعتراض على القرار، فيسعدنا أن تردّوا على هذه الرسالة خلال عشرة أيام عمل.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Hello,' || chr(10) || chr(10)
        || 'We have reviewed dispute ' || v_ref || ' on the statements and evidence of both parties. The outcome: ' || v_en || '.'
        || case when role = 'customer' then v_rem_en else v_sup_en end || ' '
        || 'If you disagree with the decision, reply to this e-mail within 10 working days.' end,
      case when role = 'customer' then d.customer_id end, case when role = 'supplier' then d.supplier_id end, d.inquiry_id)
    from (values ('customer', c.email, coalesce(public.fn_inquiry_locale(d.inquiry_id), c.locale)),   -- the customer: the inquiry's language (28 Sep 2026)
          ('supplier', s.email, 'en')   -- suppliers are always written in English (founder, 28 Sep 2026)
         ) p(role, email, locale);
  return jsonb_build_object('dispute_id', d.id, 'outcome', p_outcome, 'remedy', coalesce(p_remedy, 'none'),
                            'supplier_action', coalesce(p_supplier_action, 'none'), 'effect', v_effect);
end $function$
;

create or replace function public.fn_reveal_contact_record(p_transaction uuid, p_said text, p_channel text, p_words text DEFAULT NULL::text, p_source_ref text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t public.transactions; v_prev public.reveal_contact_statement; v_id bigint; v_word jsonb; v_h bigint; v_words text;
begin
  if p_said is null or p_said not in ('yes', 'no', 'not_yet') then
    raise exception 'the customer''s word on contact is yes, no or not_yet, not %', coalesce(p_said, 'nothing') using errcode = '22023';
  end if;
  if p_channel is null or p_channel not in ('followup_page', 'whatsapp', 'widget', 'portal', 'email') then
    raise exception 'a contact statement names its door (followup_page, whatsapp, widget, portal, email), not %', coalesce(p_channel, 'nothing') using errcode = '22023';
  end if;
  select * into t from public.transactions where id = p_transaction;
  if not found or t.revealed_at is null then
    raise exception 'a contact statement is about a revealed job; % is not one', p_transaction using errcode = '22023';
  end if;
  v_words := nullif(left(btrim(coalesce(p_words, '')), 2000), '');
  -- the same word through the same door within ten minutes is one statement (a double tap, a retry, the refund door after the intake)
  select * into v_prev from public.reveal_contact_statement where transaction_id = t.id order by id desc limit 1;
  -- ... unless the supplier claimed contact since that statement: then the same word again is a denial AFTER the claim (review AFTERREVEAL)
  if v_prev.id is not null and v_prev.said = p_said and v_prev.channel = p_channel and v_prev.said_at > now() - interval '10 minutes'
     and coalesce(t.supplier_ack_at, '-infinity'::timestamptz) <= v_prev.said_at
     and not exists (select 1 from public.messages m where m.inquiry_id = t.inquiry_id and m.supplier_id = t.supplier_id and m.sender = 'supplier'
                       and coalesce(m.blocked, false) = false and m.created_at > v_prev.said_at) then
    return jsonb_build_object('recorded', false, 'duplicate', true, 'statement_id', v_prev.id, 'word', public.fn_reveal_contact_word(t.id));
  end if;
  insert into public.reveal_contact_statement (transaction_id, said, channel, words, source_ref)
  values (t.id, p_said, p_channel, v_words, p_source_ref) returning id into v_id;
  v_word := public.fn_reveal_contact_word(t.id);
  if p_said = 'no' and coalesce((v_word->>'conflict')::boolean, false) then
    -- THE CEO GETS BOTH STATEMENTS, through the conversation that already exists for a disputed reveal (fn_ceo_takes_sales_escalation).
    -- The ladder belongs to the sales engineer, so the escalation is its; nothing here decides who is right.
    v_h := public.fn_seat_handoff('sales_engineer', 'ceo', 'sales.escalation', 'transactions', t.id || ':contact_conflict:' || v_id,
      jsonb_build_object('escalation', 'disputed_reveal', 'transaction_id', t.id, 'customer_id', t.customer_id, 'supplier_id', t.supplier_id,
        'inquiry_id', t.inquiry_id,
        'case', jsonb_build_object(
          'what', 'The customer says the revealed supplier has not contacted him; the supplier says it has. The refund ladder keeps running on the customer''s word until you decide.',
          'customer_statement', jsonb_build_object('said', p_said, 'channel', p_channel, 'words', left(v_words, 1000), 'at', now()),
          'supplier_statement', jsonb_build_object('acknowledged_at', t.supplier_ack_at, 'platform_message_at', v_word->'supplier_message_at'),
          'ladder', public.fn_refund_state(t.id),
          'rule', 'Terms v11 clause 5: a supplier responded if it replied by any reasonable means; no refund is due where the supplier has responded. Supplier Agreement v18 clause 33.')));
  end if;
  return jsonb_build_object('recorded', true, 'statement_id', v_id, 'word', v_word, 'conflict_handoff', v_h);
end $function$
;

create or replace function public.fn_customer_support_dispute_open(p_transaction_id uuid, p_raised_by text, p_statement text, p_intake_question_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare t public.transactions; d public.post_reveal_dispute; c record; s record; v_ref text; v_rfq text; v_due text; v_job jsonb;
  v_quote_en text; v_quote_ar text; v_channel text;
begin
  select * into t from public.transactions where id = p_transaction_id;
  if not found or t.revealed_at is null then raise exception 'a dispute is about a revealed job; % is not one', p_transaction_id; end if;
  select * into d from public.post_reveal_dispute where transaction_id = t.id and stage <> 'decided';
  if found then return jsonb_build_object('dispute_id', d.id, 'opened', false, 'reason', 'a case is already open on this job'); end if;
  v_job := public.fn_reveal_job_facts(t.id);
  v_channel := (select h.subject->>'channel' from public.reasoning_held_question h where h.id = p_intake_question_id);
  insert into public.post_reveal_dispute (transaction_id, inquiry_id, customer_id, supplier_id, raised_by, statement,
                                          evidence_due, intake_question_id, job_facts, channel)
  values (t.id, t.inquiry_id, t.customer_id, t.supplier_id, p_raised_by, left(p_statement, 4000),
          public.fn_add_working_days(now(), 5), p_intake_question_id, v_job, v_channel)
  returning * into d;
  if p_raised_by = 'customer' then d.customer_evidence := jsonb_build_object('statement', d.statement, 'at', now());
  else d.supplier_evidence := jsonb_build_object('statement', d.statement, 'at', now()); end if;
  update public.post_reveal_dispute set customer_evidence = d.customer_evidence, supplier_evidence = d.supplier_evidence where id = d.id;

  v_ref := 'QD-D-' || lpad(d.id::text, 5, '0');
  select coalesce(i.rfq_no::text, left(i.id::text, 8)) into v_rfq from public.inquiries i where i.id = t.inquiry_id;
  v_due := to_char(d.evidence_due at time zone 'Asia/Dubai', 'DD/MM/YYYY HH24:MI');
  -- THE QUOTATION ON RECORD, in one sentence each side reads (the supplier is bound by it: Supplier Agreement v18 clause 12)
  v_quote_en := 'The quotation on record: AED ' || coalesce(v_job->'quote'->>'amount_aed', '-')
    || coalesce('; warranty: ' || (v_job->'quote'->>'warranty'), '') || coalesce('; lead time: ' || (v_job->'quote'->>'lead_time'), '')
    || coalesce('; validity: ' || (v_job->'quote'->>'validity'), '') || '. ';
  v_quote_ar := 'عرض السعر المسجّل لدينا: ' || coalesce(v_job->'quote'->>'amount_aed', '-') || ' درهم'
    || coalesce('، الضمان: ' || (v_job->'quote'->>'warranty'), '') || coalesce('، مدة التنفيذ: ' || (v_job->'quote'->>'lead_time'), '')
    || coalesce('، الصلاحية: ' || (v_job->'quote'->>'validity'), '') || '. ';
  select c2.email, c2.locale into c from public.customers c2 where c2.id = t.customer_id;
  select coalesce(l.claimed_by, l.email) as email into s from public.leads l where l.id = t.supplier_id;
  perform public.fn_customer_support_duty_send('dispute.opened', d.id || ':' || role, role, email,
      case when locale = 'ar' then 'ar' else 'en' end,
      case when locale = 'ar' then 'فُتحت القضية ' || v_ref || ' بشأن مشروعكم على QuotesDone'
           else 'Dispute ' || v_ref || ' opened on your QuotesDone job' end,
      case when locale = 'ar' then
        'السادة المحترمين،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
        || 'فُتحت القضية ' || v_ref || ' بشأن المشروع المرتبط بالطلب رقم ' || coalesce(v_rfq, '') || '، ولن يُتخذ أي قرار قبل الاستماع إلى الطرفين. '
        || v_quote_ar
        || 'نرجو الرد على هذه الرسالة بروايتكم لما حدث، مع ما يدعمها من مستندات أو صور أو مراسلات، في موعد أقصاه ' || v_due || ' بتوقيت دبي. '
        || 'وإن لم يصلنا شيء حتى ذلك الموعد، فستُراجَع القضية بناءً على ما لدينا.' || chr(10) || chr(10)
        || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
      else
        'Hello,' || chr(10) || chr(10)
        || 'Dispute ' || v_ref || ' has been opened about the job for request ' || coalesce(v_rfq, '') || '. Nothing will be decided before both sides are heard. '
        || v_quote_en
        || 'Please reply to this e-mail with your account of what happened and any documents, photos or messages that support it by ' || v_due || ' Dubai time. '
        || 'If nothing arrives by then, the case is reviewed on what we already have.' end,
      case when role = 'customer' then t.customer_id end, case when role = 'supplier' then t.supplier_id end, t.inquiry_id)
    from (values ('customer', c.email, coalesce(public.fn_inquiry_locale(t.inquiry_id), c.locale)),   -- the customer: the inquiry's language (28 Sep 2026)
          ('supplier', s.email, 'en')   -- suppliers are always written in English (founder, 28 Sep 2026)
         ) p(role, email, locale);
  return jsonb_build_object('dispute_id', d.id, 'ref', v_ref, 'opened', true, 'evidence_due', d.evidence_due);
end $function$
;

select case when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                          where n.nspname = 'public' and p.proname in ('fn_reveal_job_facts', 'fn_ceo_post_reveal_dispute_tick',
                                'fn_ceo_decides_post_reveal_dispute', 'fn_reveal_contact_record', 'fn_customer_support_dispute_open')
                            and p.prosrc ~ 'v17 clause|clause 9: the supplier is bound|clause 8 \(honour|clauses 8 and 19')
            then 'PROBE FAILED: a dispute or reveal routine still cites the v17 numbers'
            else 'PROBE OK: the dispute and reveal reasoning cite Supplier Agreement v18 clauses 11, 12, 19 and 33' end as verdict;
