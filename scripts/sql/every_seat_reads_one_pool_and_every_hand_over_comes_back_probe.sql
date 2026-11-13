-- PROBE for every_seat_reads_one_pool_and_every_hand_over_comes_back.sql. Seat: ceo. It always raises CHK<<...>>, so every row
-- it writes is rolled back; it writes rows only. Its people are ZZ DEMO with @example.invalid addresses, and every id it
-- names is its own; nothing is sent (an outbox or pg_net row written inside it dies with the rollback, unsent).
-- Run LOCALLY (docs/runbooks/apply-the-shared-pool.md) during work; on production only at release, by the release session.
-- It proves:
--   A. the founder's test: (1) a supplier approved by code is seen by IT as "the platform (automatic)", never as a seat that
--      may not have acted, and IT's company-today counts it; (2) a paid reveal keyed by its transaction (no inquiry_id) is on
--      the REQUEST's timeline for the sales engineer, and the CEO's day says it in words with the amount; (3) a complaint
--      filed on a support case is on the CUSTOMER's timeline for the sales engineer;
--   B. the CEO judges: a finding is filed as a held question under the daily cap; a faithful answer writes the decision and
--      files the it_engineer's next step; an invalid answer and no answer decide nothing;
--   C. an overdue hand-over is escalated once, to a superior who decides it (a CEO question);
--   D. a supplier's block holds only his own matter in neutral words: not a rival's quotation on the same request;
--   E. the important line survives the cap; the block is at most 1,200 characters; the context never builds the digest.
do $probe$
declare
  v_tag text := substr(md5(clock_timestamp()::text), 1, 8);
  v_appr bigint := -(abs(hashtext(v_tag)) % 1000000000) - 2;  v_sup bigint; v_rival bigint;
  v_cust uuid; v_inq uuid; v_tx uuid; v_q1 uuid; v_q2 uuid; v_case text := 'QD-S-PROBE' || upper(v_tag);
  v_h bigint; v_f bigint; v_f2 bigint; v_o bigint; v_q bigint; v_b text; v_fail text := ''; v_n int; v_r jsonb; v_seat text; v_sizes text := '';
  v_sum jsonb := jsonb_build_object('known', '{}'::jsonb, 'tried', '{}'::jsonb, 'needed', '{}'::jsonb, 'evidence', '[]'::jsonb,
                                    'context', 'probe', 'decision', 'probe', 'open_asks', '[]'::jsonb, 'deadline', 'none');
begin
  -- ── fixtures: ZZ DEMO people, own ids ──
  insert into public.customers (full_name, email) values ('ZZ DEMO Pool Probe Customer', 'pool-probe-' || v_tag || '@example.invalid') returning id into v_cust;
  insert into public.leads (company_name, email) values ('ZZ DEMO Pool Probe Supplier A', 'pool-probe-a-' || v_tag || '@example.invalid') returning id into v_sup;
  insert into public.leads (company_name, email) values ('ZZ DEMO Pool Probe Supplier B', 'pool-probe-b-' || v_tag || '@example.invalid') returning id into v_rival;
  insert into public.inquiries (customer_id, category, emirate, summary, status) values (v_cust, 'painting', 'Dubai', 'ZZ DEMO pool probe', 'draft') returning id into v_inq;
  insert into public.transactions (inquiry_id, customer_id, supplier_id, quote_amount, reveal_fee, fee_status) values (v_inq, v_cust, v_sup, 4500, 135.00, 'pending') returning id into v_tx;

  -- A1. a supplier approved by code (actor 'system', as fn_emit_supplier_approved writes it). Its id is one no lead can
  -- have (negative), so it is real scope without a real supplier.
  insert into public.company_event (event_type, entity_type, entity_id, actor, payload)
  values ('supplier.approved', 'lead', v_appr::text, 'system', jsonb_build_object('company', 'Pool Probe Steel', 'verified', true));
  v_b := public.fn_seat_pool_context('it_engineer', jsonb_build_object('supplier_id', v_appr), 'internal')->>'block';
  if coalesce(v_b, '') not like '%the platform (automatic): a supplier was approved%' then v_fail := v_fail || 'A1: IT does not see the approval as automatic: ' || coalesce(v_b, '-') || '; '; end if;
  if v_b ~ 'sales_engineer: a supplier was approved' then v_fail := v_fail || 'A1: an author was invented; '; end if;

  -- A2. a paid reveal: the accountant's hand-over is keyed by the transaction, with no inquiry_id in it
  insert into public.agent_actions (agent, kind, status, title, detail, target_table, target_id, evidence, decided_at, decided_by)
  values ('sales_engineer', 'handoff', 'done', 'reveal.paid from accountant about transactions ' || v_tx,
          jsonb_build_object('type', 'reveal.paid', 'from', 'accountant', 'to', 'sales_engineer', 'subject_table', 'transactions',
                             'subject_id', v_tx::text, 'summary', v_sum),
          'transactions', 'reveal.paid:' || v_tx,
          jsonb_build_object('verdict', 'customer receipt sent, chosen supplier told', 'not_cited', jsonb_build_object('reason', 'probe row', 'by', 'probe')),
          now(), 'sales_engineer') returning id into v_h;
  insert into public.company_event (event_type, entity_type, entity_id, actor, payload)
  values ('handoff.reveal.paid.sent', 'agent_actions', v_h::text, 'accountant', jsonb_build_object('handoff_id', v_h, 'subject_table', 'transactions', 'subject_id', v_tx));
  v_b := public.fn_seat_pool_context('sales_engineer', jsonb_build_object('inquiry_id', v_inq), 'internal')->>'block';
  if coalesce(v_b, '') not like '%accountant: reveal.paid to % -- answered: customer receipt sent%' then v_fail := v_fail || 'A2: the sales engineer does not see the paid reveal on the request; '; end if;

  -- A3. a complaint filed on a support case reaches the customer's timeline
  insert into public.support_case (case_ref, party_kind, party_id, subject) values (v_case, 'customer', v_cust::text, 'ZZ DEMO probe complaint');
  insert into public.agent_actions (agent, kind, status, title, detail, target_table, target_id)
  values ('customer_support', 'handoff', 'pending', 'complaint.due from customer_support about support_case ' || v_case,
          jsonb_build_object('type', 'complaint.due', 'from', 'customer_support', 'to', 'customer_support', 'subject_table', 'support_case',
                             'subject_id', v_case, 'summary', v_sum),
          'support_case', 'complaint.due:' || v_case);
  v_b := public.fn_seat_pool_context('sales_engineer', jsonb_build_object('customer_id', v_cust), 'internal')->>'block';
  if coalesce(v_b, '') not like '%customer_support: complaint.due to %' then v_fail := v_fail || 'A3: the complaint is not on the customer''s timeline; '; end if;

  -- the digest, built by the duty (the context never builds it)
  select count(*) into v_n from public.seat_pool_digest;
  perform public.fn_seat_pool_context('ceo', null, 'internal');
  if (select count(*) from public.seat_pool_digest) <> v_n then v_fail := v_fail || 'E: the context built the digest; '; end if;
  perform public.fn_seat_pool_digest_build(null);
  if coalesce((select (counts->'heard'->>'supplier.approved')::int from public.seat_pool_digest where seat = 'it_engineer' and scope = 'real'), 0) < 1
    then v_fail := v_fail || 'A1: IT''s company today does not count the approval; '; end if;
  if coalesce((select body from public.seat_pool_digest where seat = 'ceo' and scope = 'demo'), '') not like '%a customer paid the reveal fee of AED 135.00 on request%(painting, Dubai)%'
    then v_fail := v_fail || 'A2: the CEO''s day does not say the reveal in words: ' || coalesce((select body from public.seat_pool_digest where seat = 'ceo' and scope = 'demo'), '-') || '; '; end if;
  if coalesce((select body from public.seat_pool_digest where seat = 'ceo' and scope = 'real'), '') like '%135.00%' then v_fail := v_fail || 'M1: demo money in a real digest; '; end if;

  -- D. two suppliers quote on one request: a supplier's own block holds only his own matter, in neutral words
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status) values (v_inq, v_sup, 4500, 'submitted') returning id into v_q1;
  insert into public.quotes (inquiry_id, supplier_id, quote_amount, status) values (v_inq, v_rival, 3900, 'submitted') returning id into v_q2;
  insert into public.company_event (event_type, entity_type, entity_id, actor, payload) values ('quote.received', 'quote', v_q1::text, 'system', jsonb_build_object('quote_amount', 4500));
  insert into public.company_event (event_type, entity_type, entity_id, actor, payload) values ('quote.received', 'quote', v_q2::text, 'system', jsonb_build_object('quote_amount', 3900));
  v_b := coalesce(public.fn_seat_pool_context('customer_support', jsonb_build_object('supplier_id', v_sup, 'inquiry_id', v_inq), 'supplier')->>'block', '');
  -- his own quotation's events (the platform may write its own quote.received too), and none of the rival's
  select count(*) into v_n from regexp_matches(v_b, 'a quotation was received', 'g');
  if v_n <> (select count(*) from public.company_event where event_type = 'quote.received' and entity_id = v_q1::text) then
    v_fail := v_fail || 'D: the supplier sees ' || v_n || ' quotations, not his own: ' || v_b || '; '; end if;
  if exists (select 1 from public.subject_link l join public.company_event e on l.src = 'event' and e.id = l.src_id
              where l.key = 'supplier:' || v_sup and e.entity_id = v_q2::text) then v_fail := v_fail || 'D: the rival''s quotation is linked to him; '; end if;
  if v_b ~ '(sales_engineer|accountant|customer_support|handoff|reveal|3,?900|4,?500|THE COMPANY TODAY|YOUR HAND-OVERS)' then v_fail := v_fail || 'D: internal words, amounts or another party in a supplier block: ' || v_b || '; '; end if;
  if coalesce(public.fn_seat_pool_context('customer_support', jsonb_build_object('inquiry_id', v_inq), 'supplier')->>'block', '') <> '' then v_fail := v_fail || 'D: a supplier block without his own id is not empty; '; end if;

  -- B. the CEO judges an IT finding
  update public.decision_policy set value = value || '{"items": 30, "aed": 0.5, "per_tick": 5}'::jsonb where key = 'ceo_daily_judgements';
  insert into public.agent_actions (agent, kind, status, title, detail, target_table, target_id, created_at)
  values ('ceo', 'handoff', 'pending', 'it.finding from it_engineer about it_engineer_finding probe:pool:' || v_tag,
          jsonb_build_object('type', 'it.finding', 'from', 'it_engineer', 'to', 'ceo', 'subject_table', 'it_engineer_finding', 'subject_id', 'probe:pool:' || v_tag,
                             'issue_key', 'probe:pool:' || v_tag, 'severity', 'critical', 'awaiting', 'ceo judgement', 'replied_at', now(), 'summary', v_sum),
          'it_engineer_finding', 'it.finding:probe:pool:' || v_tag, now() - interval '2 days') returning id into v_f;
  insert into public.agent_actions (agent, kind, status, title, detail, target_table, target_id, created_at)
  values ('ceo', 'handoff', 'pending', 'it.finding from it_engineer about it_engineer_finding probe:pool2:' || v_tag,
          jsonb_build_object('type', 'it.finding', 'from', 'it_engineer', 'to', 'ceo', 'subject_table', 'it_engineer_finding', 'subject_id', 'probe:pool2:' || v_tag,
                             'issue_key', 'probe:pool2:' || v_tag, 'severity', 'critical', 'awaiting', 'ceo judgement', 'replied_at', now(), 'summary', v_sum),
          'it_engineer_finding', 'it.finding:probe:pool2:' || v_tag, now() - interval '1 days') returning id into v_f2;
  v_r := public.fn_ceo_files_judgements();
  select id into v_q from public.reasoning_held_question where dedupe_key = 'ceo.it_finding:' || v_f || ':1';
  if v_q is null then v_fail := v_fail || 'B: the finding was not filed for the CEO (' || v_r::text || '); ';
  else
    if (select (request->'decision'->'options')::text from public.reasoning_held_question where id = v_q) not like '%fix_now:%accept_risk%needs_founder:money%'
      then v_fail := v_fail || 'B: the choices are not the four; '; end if;
    perform public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'held', 'reason', 'model_failed: no reply'));
    if (select evidence ? 'ceo_decision' from public.agent_actions where id = v_f) then v_fail := v_fail || 'B: no answer decided something; '; end if;
    perform public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ok', 'decision', jsonb_build_object('choice', 'fix_now')));
    if (select evidence ? 'ceo_decision' from public.agent_actions where id = v_f) then v_fail := v_fail || 'B: an invalid answer was taken as a decision; '; end if;
    if not (select detail ? 'ceo_judgement_refused' from public.agent_actions where id = v_f) then v_fail := v_fail || 'B: an invalid answer was not recorded as refused; '; end if;
    perform public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'model', 'stub/model',
      'answer', 'The fault only touches a probe surface; accept it for two weeks and look again.', 'decision', jsonb_build_object('choice', 'accept_risk')));
    if (select evidence->'ceo_decision'->>'choice' from public.agent_actions where id = v_f) is distinct from 'accept_risk' then v_fail := v_fail || 'B: the decision is not written on the finding; '; end if;
    if not exists (select 1 from public.agent_actions where kind = 'handoff' and agent = 'it_engineer' and detail->>'type' = 'ceo.decision_closed'
                    and detail->>'finding_handoff_id' = v_f::text) then v_fail := v_fail || 'B: the it_engineer''s next step was not filed; '; end if;
  end if;
  -- the cap is data: with no room left today, the next finding waits
  delete from public.reasoning_held_question where dedupe_key = 'ceo.it_finding:' || v_f2 || ':1';
  update public.decision_policy set value = value || jsonb_build_object('items', (public.fn_ceo_judgement_room()->>'asked_today')::int) where key = 'ceo_daily_judgements';
  v_r := public.fn_ceo_files_judgements();
  if exists (select 1 from public.reasoning_held_question where dedupe_key = 'ceo.it_finding:' || v_f2 || ':1') then v_fail := v_fail || 'B: the daily cap did not hold (' || v_r::text || '); '; end if;

  -- C. overdue, escalated once, to someone who decides it
  update public.decision_policy set value = value || '{"items": 1000, "per_tick": 500, "aed": 100}'::jsonb where key = 'ceo_daily_judgements';
  insert into public.agent_actions (agent, kind, status, title, detail, target_table, target_id, created_at)
  values ('sales_engineer', 'handoff', 'pending', 'knowledge.request from customer_support about customers ' || v_cust,
          jsonb_build_object('type', 'knowledge.request', 'from', 'customer_support', 'to', 'sales_engineer', 'subject_table', 'customers',
                             'subject_id', v_cust::text, 'summary', v_sum),
          'customers', 'knowledge.request:' || v_cust, now() - interval '10 days') returning id into v_o;
  perform public.fn_handoff_overdue_escalate();
  if (select detail->'silence'->>'escalated_to' from public.agent_actions where id = v_o) is distinct from 'ceo' then v_fail := v_fail || 'C: not escalated to the ceo; '; end if;
  if (select detail->'silence'->>'silent_seat' from public.agent_actions where id = v_o) is distinct from 'sales_engineer' then v_fail := v_fail || 'C: the silent seat is not the one that owes the answer; '; end if;
  v_r := public.fn_handoff_overdue_escalate();
  if coalesce(v_r->'ids', '[]'::jsonb) @> jsonb_build_array(v_o) then v_fail := v_fail || 'C: escalated again on the second pass; '; end if;
  -- ONCE, measured where a mutant would show it: rows the guards admit on a second pass
  select count(*) into v_n from public.agent_actions a where a.id = v_o and not coalesce(a.escalated, false) and not (a.detail ? 'silence');
  if v_n <> 0 then v_fail := v_fail || 'C: the escalated row is not marked; '; end if;
  perform public.fn_ceo_files_judgements();
  if not exists (select 1 from public.reasoning_held_question where dedupe_key = 'ceo.overdue_handoff:' || v_o || ':1') then v_fail := v_fail || 'C: the escalation reached nobody who decides; '; end if;
  v_b := coalesce(public.fn_seat_pool_context('customer_support', null, 'internal')->>'block', '');
  if v_b not like 'YOUR HAND-OVERS: NO ANSWER YET: sales_engineer on knowledge.request #' || v_o || '%escalated to ceo%' then v_fail := v_fail || 'C: the sender is not told first: ' || left(v_b, 200) || '; '; end if;

  -- E. the cap keeps the important line: twelve answered hand-overs on one subject fill the timeline
  for v_n in 1..12 loop
    insert into public.agent_actions (agent, kind, status, title, detail, target_table, target_id, evidence, decided_at, decided_by)
    values ('customer_support', 'handoff', 'done', 'delivery.request ' || v_n, jsonb_build_object('type', 'delivery.request', 'from', 'customer_support', 'to', 'customer_support',
              'subject_table', 'customers', 'subject_id', v_cust::text, 'summary', v_sum),
            'customers', 'delivery.request:' || v_cust || ':' || v_n,
            jsonb_build_object('verdict', repeat('a long answer that fills the line ', 6), 'not_cited', jsonb_build_object('reason', 'probe row', 'by', 'probe')), now(), 'customer_support');
  end loop;
  foreach v_seat in array array['customer_support', 'sales_engineer', 'marketing', 'it_engineer', 'ceo', 'accountant'] loop
    v_r := public.fn_seat_pool_context(v_seat, jsonb_build_object('customer_id', v_cust), 'internal');
    v_sizes := v_sizes || v_seat || '=' || (v_r->>'chars') || ' ';
    if (v_r->>'chars')::int > 1200 then v_fail := v_fail || 'E: ' || v_seat || ' block over 1,200; '; end if;
  end loop;
  v_b := coalesce(public.fn_seat_pool_context('customer_support', jsonb_build_object('customer_id', v_cust), 'internal')->>'block', '');
  if length(v_b) < 1000 then v_fail := v_fail || 'E: the cap was not reached (' || length(v_b) || '), so it was not tested; '; end if;
  if v_b not like 'YOUR HAND-OVERS: NO ANSWER YET%' or v_b not like '%THIS SUBJECT%' then v_fail := v_fail || 'E: the important line was cut: ' || left(v_b, 120) || '; '; end if;

  if v_fail <> '' then raise exception 'CHK<<PROBE FAILED: %>>', v_fail; end if;
  raise exception 'CHK<<PROBE OK: sizes % >>', v_sizes;
end $probe$;
