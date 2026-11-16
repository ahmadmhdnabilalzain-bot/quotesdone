-- the_ceo_refund_checklist_reads_the_customers_word_the_dispute_and_every_channel_probe.sql (customer_support builder, after-reveal
-- review fixes, 16 Nov 2026). A pure probe: run AFTER a_paid_reveal_asks_the_customer_and_every_money_problem_reaches_a_case.sql,
-- every_door_and_the_ceo_read_the_same_case.sql and the_ceo_refund_checklist_reads_the_customers_word_the_dispute_and_every_channel.sql,
-- in the SAME transaction, which this probe always aborts (raise 'CHK<<...>>'): nothing it does survives. Local Postgres 16 only, never
-- production. Every subject is created here, ZZ DEMO, with @example.invalid addresses; the duty fixtures switch is on. The CEO's
-- answers come through the real apply (fn_reason_apply_ceo__sales_escalation) on held questions written as the reasoning queue writes
-- them. 9 scenarios, each named in its failure (review AFTERREVEAL attacks C, C2, D and F, and item 6 of the checklist).
do $probe$
declare
  v_cust uuid; v_l1 bigint; v_l2 bigint; v_l3 bigint; v_l4 bigint; v_l5 bigint; v_inq uuid; v_q1 uuid; v_q2 uuid; v_q3 uuid; v_q4 uuid; v_q5 uuid;
  v_tx1 uuid; v_tx2 uuid; v_tx3 uuid; v_tx4 uuid; v_tx5 uuid; v_d bigint; v_hand bigint; v_h bigint; v_rid bigint;
  r jsonb; ck jsonb; i4 jsonb; i5 jsonb; i6 jsonb;
  v_rev timestamptz := public.fn_add_working_days(now(), -8);
begin
  perform set_config('qd.duty_fixtures', 'on', true);
  -- the rows production holds (data, not schema)
  insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
  values ('sales.escalation', 'sales_engineer', 'ceo', 'probe copy of the production row', 'fn_ceo_takes_sales_escalation', interval '1 day', false, 'scripts/sql/the_sales_engineer_can_escalate_a_decision_to_the_ceo.sql')
  on conflict (type, from_seat, to_seat) do nothing;
  insert into public.ceo_task_state (state, is_terminal, meaning) values ('open', false, 'probe copy') on conflict do nothing;
  insert into public.ceo_identity (identity, note) values ('ceo', 'probe copy') on conflict do nothing;

  insert into public.customers (full_name, email, locale) values ('ZZ DEMO ceochk customer', 'zz-ceochk-customer@example.invalid', 'en') returning id into v_cust;
  insert into public.leads (company_name, email) values ('ZZ DEMO ceochk one', 'zz-ceochk-1@example.invalid') returning id into v_l1;
  insert into public.leads (company_name, email) values ('ZZ DEMO ceochk two', 'zz-ceochk-2@example.invalid') returning id into v_l2;
  insert into public.leads (company_name, email) values ('ZZ DEMO ceochk three', 'zz-ceochk-3@example.invalid') returning id into v_l3;
  insert into public.leads (company_name, email) values ('ZZ DEMO ceochk four', 'zz-ceochk-4@example.invalid') returning id into v_l4;
  insert into public.leads (company_name, email) values ('ZZ DEMO ceochk five', 'zz-ceochk-5@example.invalid') returning id into v_l5;
  insert into public.inquiries (customer_id, summary, status, rfq_no) values (v_cust, 'ZZ DEMO ceochk', 'revealed', 990851) returning id into v_inq;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status) values (v_inq, v_l1, 18000, 'revealed') returning id into v_q1;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status) values (v_inq, v_l2, 18100, 'revealed') returning id into v_q2;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status) values (v_inq, v_l3, 18200, 'revealed') returning id into v_q3;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status) values (v_inq, v_l4, 18300, 'revealed') returning id into v_q4;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status) values (v_inq, v_l5, 18400, 'revealed') returning id into v_q5;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, total_charged, payment_ref, fee_status, revealed_at) values
    (v_q1, v_inq, v_l1, v_cust, 18000, 540, 540, 'pi_zzdemo_ceochk_1', 'paid', v_rev) returning id into v_tx1;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, total_charged, payment_ref, fee_status, revealed_at) values
    (v_q2, v_inq, v_l2, v_cust, 18100, 543, 543, 'pi_zzdemo_ceochk_2', 'paid', v_rev) returning id into v_tx2;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, total_charged, payment_ref, fee_status, revealed_at) values
    (v_q3, v_inq, v_l3, v_cust, 18200, 546, 546, 'pi_zzdemo_ceochk_3', 'paid', v_rev) returning id into v_tx3;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, total_charged, payment_ref, fee_status, revealed_at) values
    (v_q4, v_inq, v_l4, v_cust, 18300, 549, 549, 'pi_zzdemo_ceochk_4', 'paid', v_rev) returning id into v_tx4;
  insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, reveal_fee, total_charged, payment_ref, fee_status, revealed_at) values
    (v_q5, v_inq, v_l5, v_cust, 18400, 552, 552, 'pi_zzdemo_ceochk_5', 'paid', v_rev) returning id into v_tx5;

  -- 1 (attack C). The supplier clicks, the customer then presses Refund (a denial after the claim), the chase and the final call get
  -- no answer: item 4 waits for the CEO as needs_reasoning; the checklist is not ok on the customer's word alone.
  perform public.fn_supplier_ack_record(v_tx1);
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  r := public.fn_refund_open_from_customer(v_tx1, 'customer', null, 'portal');
  perform set_config('qd.probe_files_demo_handoff', '', true);
  insert into public.refund_ladder_evidence (transaction_id, refund_id, step, result, delivered) values
    (v_tx1, (r->>'refund_id')::bigint, 'chase', 'no_response_confirmation', true),
    (v_tx1, (r->>'refund_id')::bigint, 'final_call', 'no_response_confirmation', true);
  ck := public.fn_ceo_refund_checklist(v_tx1, 'approve', false);
  select i into i4 from jsonb_array_elements(ck->'items') i where i->>'item' = 'supplier_never_responded';
  if coalesce((ck->>'ok')::boolean, true) or coalesce((i4->>'passed')::boolean, true) or i4->>'kind' <> 'needs_reasoning' or i4->>'owner' <> 'ceo'
     or not (i4->'evidence' ? 'customer_contact') then
    raise exception 'CHK<<PROBE FAILED 1: a contested word was read as silence: %>>', i4; end if;

  -- 2 (attack C2). The CEO answers the disputed reveal 'refund_review' THROUGH THE REAL APPLY: item 4 then passes.
  select a.id into v_hand from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'sales.escalation'
     and a.detail->>'transaction_id' = v_tx1::text order by a.id desc limit 1;
  if v_hand is null then raise exception 'CHK<<PROBE FAILED 2: the conflict filed no escalation>>'; end if;
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, qhash, expires_at)
  values ('ceo', 'ceo.sales_escalation', 'ZZ DEMO probe', jsonb_build_object('decision', jsonb_build_object('options',
            '[{"id":"uphold_reveal"},{"id":"refund_review"},{"id":"investigate"}]'::jsonb)), '{}'::jsonb,
          jsonb_build_object('handoff_id', v_hand, 'escalation', 'disputed_reveal'), 'probe', 'probe:ceochk:2', md5('ceochk2'), now() + interval '1 day')
  returning id into v_h;
  r := public.fn_reason_apply_ceo__sales_escalation(v_h, jsonb_build_object('decision', jsonb_build_object('choice', 'refund_review'),
         'answer', 'ZZ DEMO the supplier gave no call log and the customer denied contact twice, so the refund review runs'));
  select i into i4 from jsonb_array_elements(public.fn_ceo_refund_checklist(v_tx1, 'approve', false)->'items') i where i->>'item' = 'supplier_never_responded';
  if not coalesce((i4->>'passed')::boolean, false) or i4->'evidence'->>'contact_conflict_ceo_choice' <> 'refund_review' then
    raise exception 'CHK<<PROBE FAILED 2: the CEO''s refund_review answer did not reach item 4: % / handoff %>>', i4,
      (select jsonb_build_object('status', status, 'evidence', evidence) from public.agent_actions where id = v_hand); end if;

  -- 3 (attack C2). 'uphold_reveal' declines it: item 4 fails and is not remediable.
  perform public.fn_supplier_ack_record(v_tx2);
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  r := public.fn_refund_open_from_customer(v_tx2, 'customer', null, 'portal');
  perform set_config('qd.probe_files_demo_handoff', '', true);
  insert into public.refund_ladder_evidence (transaction_id, refund_id, step, result, delivered) values
    (v_tx2, (r->>'refund_id')::bigint, 'chase', 'no_response_confirmation', true),
    (v_tx2, (r->>'refund_id')::bigint, 'final_call', 'no_response_confirmation', true);
  select a.id into v_hand from public.agent_actions a where a.kind = 'handoff' and a.detail->>'type' = 'sales.escalation'
     and a.detail->>'transaction_id' = v_tx2::text order by a.id desc limit 1;
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, qhash, expires_at)
  values ('ceo', 'ceo.sales_escalation', 'ZZ DEMO probe', jsonb_build_object('decision', jsonb_build_object('options',
            '[{"id":"uphold_reveal"},{"id":"refund_review"},{"id":"investigate"}]'::jsonb)), '{}'::jsonb,
          jsonb_build_object('handoff_id', v_hand, 'escalation', 'disputed_reveal'), 'probe', 'probe:ceochk:3', md5('ceochk3'), now() + interval '1 day')
  returning id into v_h;
  r := public.fn_reason_apply_ceo__sales_escalation(v_h, jsonb_build_object('decision', jsonb_build_object('choice', 'uphold_reveal'),
         'answer', 'ZZ DEMO the supplier''s call log shows a four minute call to the customer on the day after the reveal'));
  select i into i4 from jsonb_array_elements(public.fn_ceo_refund_checklist(v_tx2, 'approve', false)->'items') i where i->>'item' = 'supplier_never_responded';
  if coalesce((i4->>'passed')::boolean, true) or coalesce((i4->>'remediable')::boolean, true) then
    raise exception 'CHK<<PROBE FAILED 3: uphold_reveal did not decline item 4: %>>', i4; end if;

  -- 4 (attack D). THE CEO'S OWN DISPUTE REFUND on a job where the supplier did contact him is APPROVED by the review, not declined.
  perform public.fn_reveal_contact_record(v_tx3, 'yes', 'portal', 'ZZ DEMO he came, then raised the price', 'probe');
  insert into public.post_reveal_dispute (transaction_id, inquiry_id, customer_id, supplier_id, raised_by, statement, stage, evidence_due, decision_due)
  values (v_tx3, v_inq, v_cust, v_l3, 'customer', 'ZZ DEMO he raised the price above the quotation', 'ceo_decision', now(), now()) returning id into v_d;
  r := public.fn_ceo_decides_post_reveal_dispute(v_d, 'customer_upheld', 'ZZ DEMO upheld', 'refund_reveal_fee', 'none');
  select id into v_rid from public.refunds where transaction_id = v_tx3 and reason_code = 'fraud_or_dispute' order by id desc limit 1;
  ck := public.fn_ceo_refund_checklist(v_tx3, 'approve', false);
  if jsonb_array_length(coalesce(ck->'failed', '[]'::jsonb)) <> 0 then
    raise exception 'CHK<<PROBE FAILED 4: the CEO''s dispute refund fails the checklist: %>>', ck->'failed'; end if;
  r := public.fn_ceo_refund_review(v_rid, 'probe');
  if r->>'outcome' = 'declined' then raise exception 'CHK<<PROBE FAILED 4: the review declined the CEO''s own dispute refund: %>>', r; end if;

  -- 5 (checklist d). An overcharge returned on the payment: the customer's non-response case is the case read (not the return),
  -- and item 6 expects total_charged less the return.
  set local session_replication_role = replica;   -- the fixture row only: an accountant's overcharge return already on the payment
  insert into public.refunds (transaction_id, quote_id, inquiry_id, customer_id, supplier_lead_id, stripe_payment_intent, amount_fils, currency,
                              reason_code, reason_note, status, requested_by, requested_at, amount_source)
  values (v_tx4, v_q4, v_inq, v_cust, v_l4, 'pi_zzdemo_ceochk_4', 4000, 'AED', 'overcharge_return', 'ZZ DEMO overcharge', 'requested', 'accountant', now(), 'in_platform_request');
  set local session_replication_role = origin;
  r := public.fn_refund_open_from_customer(v_tx4, 'customer', null, 'portal');
  if not coalesce((r->>'ok')::boolean, false) then raise exception 'CHK<<PROBE FAILED 5: the overcharge return was read as an open case: %>>', r; end if;
  select i into i6 from jsonb_array_elements(public.fn_ceo_refund_checklist(v_tx4, 'approve', false)->'items') i where i->>'item' = 'amount_equals_total_charged';
  if not coalesce((i6->>'passed')::boolean, false) or (i6->'evidence'->>'refund_id')::bigint <> (r->>'refund_id')::bigint then
    raise exception 'CHK<<PROBE FAILED 5: item 6 reads the overcharge return or expects the full total: %>>', i6; end if;

  -- 6. a rating given while saying "never contacted" is not an exclusion; a rating after contact is.
  insert into public.reviews (supplier_id, customer_id, inquiry_id, transaction_id, rating) values (v_l5, v_cust, v_inq, v_tx5, 1);
  perform public.fn_reveal_contact_record(v_tx5, 'no', 'portal', 'ZZ DEMO one star because he never called', 'probe');
  select i into i5 from jsonb_array_elements(public.fn_ceo_refund_checklist(v_tx5, 'approve', false)->'items') i where i->>'item' = 'no_refund_exclusion_applies';
  if coalesce((i5->'evidence'->>'supplier_rated')::boolean, true) then raise exception 'CHK<<PROBE FAILED 6: a rating for silence excludes the refund: %>>', i5; end if;
  perform public.fn_reveal_contact_record(v_tx5, 'yes', 'portal', 'ZZ DEMO actually he did call', 'probe');
  select i into i5 from jsonb_array_elements(public.fn_ceo_refund_checklist(v_tx5, 'approve', false)->'items') i where i->>'item' = 'no_refund_exclusion_applies';
  if not coalesce((i5->'evidence'->>'supplier_rated')::boolean, false) then raise exception 'CHK<<PROBE FAILED 6: a rating after contact no longer excludes: %>>', i5; end if;

  -- 7. item 1b (every_door) is in the checklist: what every seat told and promised him.
  if (public.fn_ceo_refund_checklist(v_tx1, 'approve', false))::text not like '%what_he_was_told_and_promised_on_every_channel%' then
    raise exception 'CHK<<PROBE FAILED 7: item 1b is missing (this file must be applied AFTER every_door_and_the_ceo_read_the_same_case.sql)>>'; end if;

  -- 8 (attack F). A timeline read that fails records nothing and never makes the checklist unavailable.
  create or replace function public.fn_contact_timeline(p_contact text, p_limit integer default 60) returns jsonb language plpgsql as $b$begin raise exception 'ZZ DEMO boom'; end$b$;
  ck := public.fn_ceo_refund_checklist(v_tx1, 'approve', false);
  if not (ck ? 'items') or jsonb_array_length(ck->'items') < 7 then raise exception 'CHK<<PROBE FAILED 8: a failed timeline read broke the checklist: %>>', ck; end if;

  -- 9. the routine stays closed and pinned
  if has_function_privilege('anon', 'public.fn_ceo_refund_checklist(uuid, text, boolean)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_ceo_refund_checklist(uuid, text, boolean)', 'execute')
     or not (select prosecdef and proconfig @> array['search_path=public, pg_temp'] from pg_proc where oid = 'public.fn_ceo_refund_checklist(uuid, text, boolean)'::regprocedure) then
    raise exception 'CHK<<PROBE FAILED 9: the checklist is open to a public role or unpinned>>'; end if;

  raise exception 'CHK<<PROBE OK %>>', jsonb_build_object('scenarios', 9);
end $probe$;
