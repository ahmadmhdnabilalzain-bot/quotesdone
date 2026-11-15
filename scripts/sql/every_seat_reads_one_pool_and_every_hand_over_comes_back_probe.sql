-- PROBE for every_seat_reads_one_pool_and_every_hand_over_comes_back.sql. Seat: ceo. It always raises CHK<<...>>, so every row
-- it writes is rolled back; it writes rows only. Its people are ZZ DEMO with @example.invalid addresses, and every id it
-- names is its own; nothing is sent (an outbox or pg_net row written inside it dies with the rollback, unsent).
-- Run LOCALLY (docs/runbooks/apply-the-shared-pool.md) during work; on production only at release, by the release session.
-- It proves:
--   A. the founder's test: (1) a supplier approved by code is seen by IT as "the platform (automatic)", never as a seat that
--      may not have acted, and IT's company-today counts it; (2) a paid reveal keyed by its transaction (no inquiry_id) is on
--      the REQUEST's timeline for the sales engineer, and the CEO's day says it in words with the amount; (3) a complaint
--      filed on a support case is on the CUSTOMER's timeline for the sales engineer;
--   (a) a customer verified where kyc verifies him, and a supplier the sales engineer verified: one event each, saying who,
--      read by every other seat from the pool (timeline and day) without a hand-over to anyone;
--   (b) the accountant's day says the paid reveal with its amount; the sender of a hand-over reads the ANSWER itself;
--   B. the CEO judges inside the daily cap, with room made whatever was asked today: a supplier fault offers the seats whose
--      duties cover it, a critical security fault offers no accept_risk and no other seat; no answer, an invalid answer and a
--      choice not offered decide nothing; fix_now opens an ORDER that stays open in the seat's queue, nothing bounces back
--      to the CEO, and the seat's report closes the order, lands on the decision and tells IT to re-verify; a re-armed
--      question is counted today;
--   C. a hand-over nobody answers: a "waiting" reply is not an answer (the receiver owes it), the silent seat is told it is
--      late, the sender reads who owes it, the SILENT seat's superior is asked once (marketing silent -> the CEO; the CEO
--      silent -> the founder); the CEO's chase is an order that closes when the late hand-over is answered;
--   (d) a seat refused for lack of authority asks the CEO: allow_once is honoured once, for that subject only (tested on
--      another subject BEFORE the grant is spent), not after it expires; refuse is read by the seat; a malformed answer
--      grants nothing and is asked again; the daily cap holds; authority takes at most half of the room;
--   R2 (round 4, ledger 1696: nothing goes to the founder; hard limits in code): no choice names the founder; a money action
--      with no amount, above the per-action limit, or above what is left today is refused unasked; a grant with an amount is
--      honoured only within it and commits it; a grant the day has outgrown is not honoured; an allow_once the limit refuses
--      by the time it lands writes no grant (whatever the options said); an action that weakens a message gate, or a named
--      recipient a gate refuses, is refused unasked; a deploy is never asked; the IT engineer asks the CEO; the CEO acts on
--      his own authority with a reason; the CEO's own late hand-over is his (answer), not the founder's;
--   R3 a fix order closes when its finding's hand-over is done; a late ORDER is never chased (wait or withdraw), and the
--      seat's report on a chase is written back on the CEO's decision;
--   DATA: the room is made from what is queued (every pending question counted), so a production backlog cannot starve it.
--   D. a supplier's block holds only his own matter in neutral words: not a rival's quotation on the same request;
--   E. the important line survives the cap; the block is at most 1,200 characters; the context never builds the digest.
do $probe$
declare
  v_tag text := substr(md5(clock_timestamp()::text), 1, 8);
  v_appr bigint := -(abs(hashtext(v_tag)) % 1000000000) - 2;  v_sup bigint; v_rival bigint;
  v_cust uuid; v_inq uuid; v_tx uuid; v_q1 uuid; v_q2 uuid; v_case text := 'QD-S-PROBE' || upper(v_tag);
  v_h bigint; v_f bigint; v_f2 bigint; v_o bigint; v_o2 bigint; v_m bigint; v_c bigint; v_q bigint; v_hq2 bigint; v_opts text;
  v_per numeric; v_day numeric; v_amt numeric;
  v_t0 timestamptz := now(); v_b text; v_fail text := ''; v_n int; v_r jsonb; v_seat text; v_sizes text := '';
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

  -- (a) the customer finishes verifying where the code verifies him (kyc: his code, then his terms): ONE event, saying what
  -- verified him and which seat told him; every other seat reads it from the pool, and nobody is addressed (no hand-over)
  select count(*) into v_n from public.agent_actions where kind = 'handoff' and created_at >= v_t0;
  update public.customers set email_verified = true, tos_accepted_at = now(), tos_version = 'probe' where id = v_cust;
  if (select count(*) from public.company_event where event_type = 'customer.verified' and entity_id = v_cust::text) <> 1 then v_fail := v_fail || '(a): no single customer.verified event; '; end if;
  if (select payload->>'told_by' from public.company_event where event_type = 'customer.verified' and entity_id = v_cust::text) is distinct from 'customer_support'
    then v_fail := v_fail || '(a): the event does not say which seat told him; '; end if;
  update public.customers set tos_accepted_at = null where id = v_cust;
  update public.customers set tos_accepted_at = now() where id = v_cust;
  if (select count(*) from public.company_event where event_type = 'customer.verified' and entity_id = v_cust::text) <> 1 then v_fail := v_fail || '(a): verified twice; '; end if;
  v_b := public.fn_seat_pool_timeline('it_engineer', jsonb_build_object('customer_id', v_cust), 'internal', 20);
  if coalesce(v_b, '') not like '%a customer finished verifying (the platform: kyc checked his e-mail code%customer_support told him%' then v_fail := v_fail || '(a): IT does not read the customer verified: ' || coalesce(v_b, '-') || '; '; end if;
  -- the supplier: the sales engineer verifies him (approval_decided_by, as fn_sales_engineer_verifies_supplier writes it)
  -- (his six mandatory items first, as a registered supplier has them: the gate refuses an approval without them)
  insert into storage.objects (bucket_id, name) values ('supplier-docs', 'zz-demo-pool-probe/' || v_tag || '/licence.pdf'), ('supplier-docs', 'zz-demo-pool-probe/' || v_tag || '/profile.pdf');
  update public.leads set phone = '+971500000000', owner_phone_verified = true, owner_email_verified = true, signed_terms_path = 'zz-demo-pool-probe/' || v_tag || '/terms.pdf',
         license_doc_path = 'zz-demo-pool-probe/' || v_tag || '/licence.pdf', company_profile_doc_path = 'zz-demo-pool-probe/' || v_tag || '/profile.pdf' where id = v_sup;
  update public.leads set approval_status = 'approved', verified = true, approval_decided_by = 'sales_engineer' where id = v_sup;
  if (select payload->>'approved_by' from public.company_event where event_type = 'supplier.approved' and entity_id = v_sup::text) is distinct from 'sales_engineer'
    then v_fail := v_fail || '(a): the supplier event does not say which seat verified him; '; end if;
  foreach v_seat in array array['it_engineer', 'marketing', 'accountant', 'customer_support', 'ceo'] loop
    v_b := public.fn_seat_pool_timeline(v_seat, jsonb_build_object('supplier_id', v_sup), 'internal', 20);
    if coalesce(v_b, '') not like '%sales_engineer: a supplier was approved: ZZ DEMO Pool Probe Supplier A%' then v_fail := v_fail || '(a): ' || v_seat || ' does not read who verified the supplier; '; end if;
  end loop;
  if exists (select 1 from public.agent_actions where kind = 'handoff' and created_at >= v_t0 and id > 0
              and detail->>'event_type' in ('customer.verified', 'supplier.approved')) then v_fail := v_fail || '(a): a seat was addressed instead of reading the pool; '; end if;
  perform public.fn_seat_pool_digest_build(null);
  foreach v_seat in array array['it_engineer', 'marketing', 'accountant', 'customer_support', 'ceo'] loop
    if coalesce((select (counts->'heard'->>'customer.verified')::int from public.seat_pool_digest where seat = v_seat and scope = 'demo'), 0) < 1
       or coalesce((select (counts->'heard'->>'supplier.approved')::int from public.seat_pool_digest where seat = v_seat and scope = 'demo'), 0) < 1
      then v_fail := v_fail || '(a): ' || v_seat || '''s day does not count the verifications; '; end if;
  end loop;

  -- (b) the accountant's day SAYS the payment; the sender of a hand-over reads the ANSWER, not only "answered"
  if coalesce((select body from public.seat_pool_digest where seat = 'accountant' and scope = 'demo'), '') not like '%a customer paid the reveal fee of AED 135.00 on request%'
    then v_fail := v_fail || '(b): the accountant''s day does not say the payment: ' || coalesce((select body from public.seat_pool_digest where seat = 'accountant' and scope = 'demo'), '-') || '; '; end if;
  insert into public.agent_actions (agent, kind, status, title, detail, target_table, target_id, evidence)
  values ('accountant', 'handoff', 'pending', 'reveal.reconcile from sales_engineer about transactions ' || v_tx,
          jsonb_build_object('type', 'reveal.reconcile', 'from', 'sales_engineer', 'to', 'accountant', 'subject_table', 'transactions',
                             'subject_id', v_tx::text, 'summary', v_sum, 'replied_at', now(), 'awaiting', 'sales_engineer re-verification'),
          'transactions', 'reveal.reconcile:' || v_tx,
          jsonb_build_object('reply', 'reconciled and booked: probe receipt ' || v_tag, 'not_cited', jsonb_build_object('reason', 'probe row', 'by', 'probe')));
  v_b := public.fn_seat_pool_timeline('sales_engineer', jsonb_build_object('inquiry_id', v_inq), 'internal', 20);
  if coalesce(v_b, '') not like '%reveal.reconcile to accountant -- answered: reconciled and booked: probe receipt ' || v_tag || '%' then v_fail := v_fail || '(b): the sender does not read the answer: ' || coalesce(v_b, '-') || '; '; end if;

  -- B. the CEO judges an IT finding: with ROOM made for it, whatever was asked today (review item 9: the probe failed on a
  -- day with 30 questions already asked)
  -- the room is made from the WHOLE queue (review 3, item 9: 30 asked today plus 10 findings and 10 authority questions
  -- starved the probe's own question): authority takes half, so twice everything pending, plus the probe's own
  select count(*) into v_n from public.agent_actions a
   where a.kind = 'handoff' and a.status = 'pending'
     and (a.agent = 'ceo' and a.detail->>'type' in ('ceo.authority', 'it.finding') or a.detail->'silence'->>'escalated_to' = 'ceo');
  update public.decision_policy set value = value || jsonb_build_object('items', (public.fn_ceo_judgement_room()->>'asked_today')::int + 2 * (v_n + 100), 'aed', 100000, 'per_tick', 2 * (v_n + 100))
   where key = 'ceo_daily_judgements';
  insert into public.agent_actions (agent, kind, status, title, detail, target_table, target_id, created_at)
  values ('ceo', 'handoff', 'pending', 'it.finding from it_engineer about it_engineer_finding probe:pool:' || v_tag,
          jsonb_build_object('type', 'it.finding', 'from', 'it_engineer', 'to', 'ceo', 'subject_table', 'it_engineer_finding', 'subject_id', 'probe:pool:' || v_tag,
                             'issue_key', 'probe:pool:' || v_tag, 'title', 'Probe: the supplier catalogue sync failed ' || v_tag, 'severity', 'high',
                             'awaiting', 'ceo judgement', 'replied_at', now(), 'summary', v_sum),
          'it_engineer_finding', 'it.finding:probe:pool:' || v_tag, now() - interval '2 days') returning id into v_f;
  insert into public.agent_actions (agent, kind, status, title, detail, target_table, target_id, created_at)
  values ('ceo', 'handoff', 'pending', 'it.finding from it_engineer about it_engineer_finding probe:pool2:' || v_tag,
          jsonb_build_object('type', 'it.finding', 'from', 'it_engineer', 'to', 'ceo', 'subject_table', 'it_engineer_finding', 'subject_id', 'probe:pool2:' || v_tag,
                             'issue_key', 'probe:pool2:' || v_tag, 'title', 'Probe: a security token leaked in a log ' || v_tag, 'severity', 'critical', 'blast', 'security',
                             'awaiting', 'ceo judgement', 'replied_at', now(), 'summary', v_sum),
          'it_engineer_finding', 'it.finding:probe:pool2:' || v_tag, now() - interval '1 days') returning id into v_f2;
  v_r := public.fn_ceo_files_judgements();
  select id into v_q from public.reasoning_held_question where dedupe_key = 'ceo.it_finding:' || v_f || ':1';
  select id into v_hq2 from public.reasoning_held_question where dedupe_key = 'ceo.it_finding:' || v_f2 || ':1';
  if v_q is null or v_hq2 is null then v_fail := v_fail || 'B: the findings were not filed for the CEO (' || v_r::text || '); ';
  else
    v_opts := (select (request->'decision'->'options')::text from public.reasoning_held_question where id = v_q);
    if v_opts not like '%fix_now:it_engineer%' or v_opts not like '%fix_now:sales_engineer%' or v_opts not like '%accept_risk%' or v_opts ~* 'founder'
      then v_fail := v_fail || 'B: the choices for a supplier fault are wrong (or name the founder): ' || v_opts || '; '; end if;
    v_opts := (select (request->'decision'->'options')::text from public.reasoning_held_question where id = v_hq2);
    if v_opts like '%accept_risk%' or v_opts ~ 'fix_now:(marketing|sales_engineer|customer_support|accountant)' or v_opts not like '%fix_now:it_engineer%'
      then v_fail := v_fail || 'B: a critical security finding offers accept_risk or a seat whose duties do not cover it: ' || v_opts || '; '; end if;
    perform public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'held', 'reason', 'model_failed: no reply'));
    if (select evidence ? 'ceo_decision' from public.agent_actions where id = v_f) then v_fail := v_fail || 'B: no answer decided something; '; end if;
    perform public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'ok', 'decision', jsonb_build_object('choice', 'fix_now')));
    perform public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'Marketing should take this one on.', 'decision', jsonb_build_object('choice', 'fix_now:marketing')));
    perform public.fn_reason_held_resolve(v_hq2, jsonb_build_object('status', 'answered', 'answer', 'It is only a log line; accept it for now.', 'decision', jsonb_build_object('choice', 'accept_risk')));
    if (select evidence ? 'ceo_decision' from public.agent_actions where id = v_f) or (select evidence ? 'ceo_decision' from public.agent_actions where id = v_f2)
      then v_fail := v_fail || 'B: an invalid or not-offered answer was taken as a decision; '; end if;
    if not (select detail ? 'ceo_judgement_refused' from public.agent_actions where id = v_f) then v_fail := v_fail || 'B: an invalid answer was not recorded as refused; '; end if;
    perform public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'model', 'stub/model',
      'answer', 'The supplier catalogue is the sales engineer''s data; he fixes it this week.', 'decision', jsonb_build_object('choice', 'fix_now:sales_engineer')));
    if (select evidence->'ceo_decision'->>'choice' from public.agent_actions where id = v_f) is distinct from 'fix_now:sales_engineer' then v_fail := v_fail || 'B: the decision is not written on the finding; '; end if;
    -- 3. the decision makes someone act: an ORDER stays open in the sales engineer's queue until he reports it done
    select id into v_o2 from public.agent_actions where kind = 'handoff' and agent = 'sales_engineer' and detail->>'type' = 'ceo.order'
                                                       and detail->>'finding_handoff_id' = v_f::text and status = 'pending';
    if v_o2 is null then v_fail := v_fail || 'B: fix_now opened no order to the seat (or it closed at once); '; end if;
    if exists (select 1 from public.agent_actions where kind = 'handoff' and agent = 'it_engineer' and detail->>'type' = 'ceo.decision_closed'
                and detail->>'finding_handoff_id' = v_f::text) then v_fail := v_fail || 'B: IT told to re-verify before the fix was reported; '; end if;
    if (select public.fn_handoff_owing_seat(detail->>'awaiting', agent) from public.agent_actions where id = v_o2) is distinct from 'sales_engineer'
       or coalesce(public.fn_seat_pool_context('sales_engineer', null, 'internal')->>'block', '') not like '%Waiting on you: %'
      then v_fail := v_fail || 'B: the order is not owed by the seat in its Waiting on you; '; end if;
    -- no bounce: 15 minutes later nothing escalates the decided finding or asks the CEO again
    perform public.fn_handoff_overdue_escalate();
    perform public.fn_ceo_files_judgements();
    if (select detail ? 'silence' from public.agent_actions where id = v_f) or exists (select 1 from public.reasoning_held_question where dedupe_key = 'ceo.it_finding:' || v_f || ':2')
      then v_fail := v_fail || 'B: the decided finding bounced back to the CEO; '; end if;
    -- the seat reports: the order closes, the report is on the CEO's decision, the finding's sender (IT) is filed its next step
    v_r := public.fn_seat_reports_done(v_o2, 'sales_engineer', 'Re-ran the catalogue sync for the probe supplier; it now completes.');
    if (select status from public.agent_actions where id = v_o2) <> 'done' then v_fail := v_fail || 'B: the report did not close the order: ' || v_r::text || '; '; end if;
    if (select evidence->'ceo_decision'->>'reported_done' from public.agent_actions where id = v_f) not like 'sales_engineer reported it done%'
      then v_fail := v_fail || 'B: the report is not on the CEO''s decision; '; end if;
    if not exists (select 1 from public.agent_actions where kind = 'handoff' and agent = 'it_engineer' and detail->>'type' = 'ceo.decision_closed'
                    and detail->>'finding_handoff_id' = v_f::text and detail->>'report' like 'Re-ran the catalogue sync%')
      then v_fail := v_fail || 'B: the finding''s sender was not told the fix was reported; '; end if;
  end if;
  -- R3: a FIX order closes itself once its finding's hand-over is done (review 3, item 3: order #71 stayed open after #69)
  if v_hq2 is not null then
    perform public.fn_reason_held_resolve((select id from public.reasoning_held_question where dedupe_key = 'ceo.it_finding:' || v_f2 || ':1'),
      jsonb_build_object('status', 'answered', 'model', 'stub/model', 'answer', 'A leaked token is the IT engineer''s to rotate this week.', 'decision', jsonb_build_object('choice', 'fix_now:it_engineer')));
    select id into v_o from public.agent_actions where kind = 'handoff' and agent = 'it_engineer' and detail->>'type' = 'ceo.order' and detail->>'finding_handoff_id' = v_f2::text;
    if v_o is null then v_fail := v_fail || 'R3: no fix order to the IT engineer; ';
    else
      perform public.fn_ceo_orders_reported();
      if (select status from public.agent_actions where id = v_o) <> 'pending' then v_fail := v_fail || 'R3: the fix order closed before its finding; '; end if;
      update public.agent_actions set status = 'done', decided_at = now(),   -- IT closes the finding: the fault cleared
             evidence = coalesce(evidence, '{}'::jsonb) || jsonb_build_object('not_cited', jsonb_build_object('reason', 'probe row', 'by', 'probe')) where id = v_f2;
      perform public.fn_ceo_orders_reported();
      if (select status from public.agent_actions where id = v_o) is distinct from 'done' then v_fail := v_fail || 'R3: the fix order stayed open after its finding closed; '; end if;
      -- a late ORDER: the CEO is asked wait or withdraw, never chase; withdraw closes it with his reason
      update public.agent_actions set status = 'pending', decided_at = null, created_at = now() - interval '20 days',
             detail = (detail - 'reported_at' - 'reported_to') || jsonb_build_object('due_at', (now() - interval '10 days')::text, 'finding_handoff_id', null) where id = v_o;
      perform public.fn_handoff_overdue_escalate();
      perform public.fn_ceo_files_judgements();
      select id into v_q from public.reasoning_held_question where dedupe_key = 'ceo.overdue_handoff:' || v_o || ':1';
      v_opts := coalesce((select (request->'decision'->'options')::text from public.reasoning_held_question where id = v_q), '-');
      if v_opts like '%"chase"%' or v_opts not like '%"withdraw"%' or v_opts not like '%"wait"%' then v_fail := v_fail || 'R3: a late order offers ' || v_opts || '; '; end if;
      perform public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'model', 'stub/model',
        'answer', 'The token was rotated another way; this order is no longer needed.', 'decision', jsonb_build_object('choice', 'withdraw')));
      if (select status || ' ' || coalesce(evidence->>'outcome', '') from public.agent_actions where id = v_o) is distinct from 'done withdrawn'
        then v_fail := v_fail || 'R3: withdraw did not close the order; '; end if;
    end if;
  end if;

  -- the cap is data and counts a RE-ARMED question today (review item 5)
  v_n := (public.fn_ceo_judgement_room()->>'asked_today')::int;
  update public.reasoning_held_question set created_at = now() - interval '25 hours', last_attempt_at = now() - interval '25 hours' where id = v_hq2;
  if public.fn_ceo_ask('ceo.it_finding', v_f2, 1, 'probe re-ask', '{}'::jsonb, (select request->'decision'->'options' from public.reasoning_held_question where id = v_hq2)) is null
    then v_fail := v_fail || 'cap: a refused question was not re-armed after a day; ';
  elsif (public.fn_ceo_judgement_room()->>'asked_today')::int <> v_n then v_fail := v_fail || 'cap: a re-armed question is not counted today; '; end if;

  -- C. a hand-over nobody answers: the seat that owes it is told it is late, the sender reads who owes it, the SILENT
  -- seat's superior is asked once; the founder only when the CEO himself is silent
  insert into public.agent_actions (agent, kind, status, title, detail, target_table, target_id, created_at, evidence)
  values ('sales_engineer', 'handoff', 'pending', 'knowledge.request from customer_support about customers ' || v_cust,
          jsonb_build_object('type', 'knowledge.request', 'from', 'customer_support', 'to', 'sales_engineer', 'subject_table', 'customers',
                             'subject_id', v_cust::text, 'summary', v_sum || jsonb_build_object('deadline', (now() + interval '1 day')::text),
                             'replied_at', now() - interval '59 days', 'awaiting', 'a knowledge entry is written'),
          'customers', 'knowledge.request:' || v_cust, now() - interval '59 days',
          jsonb_build_object('waiting', 'a knowledge entry is written')) returning id into v_o;
  insert into public.agent_actions (agent, kind, status, title, detail, target_table, target_id, created_at)
  values ('marketing', 'handoff', 'pending', 'ceo.revise from ceo about ceo_task probe' || v_tag,
          jsonb_build_object('type', 'ceo.revise', 'from', 'ceo', 'to', 'marketing', 'subject_table', 'ceo_task', 'subject_id', 'probe' || v_tag, 'summary', v_sum),
          'ceo_task', 'ceo.revise:probe' || v_tag, now() - interval '59 days') returning id into v_m;
  insert into public.agent_actions (agent, kind, status, title, detail, target_table, target_id, created_at)
  values ('ceo', 'handoff', 'pending', 'knowledge.request from customer_support about probe ' || v_tag,
          jsonb_build_object('type', 'knowledge.request', 'from', 'customer_support', 'to', 'ceo', 'subject_table', 'customers', 'subject_id', v_cust::text,
                             'summary', v_sum, 'awaiting', 'the CEO seat to answer'),
          'customers', 'knowledge.request:ceo:' || v_tag, now() - interval '59 days') returning id into v_c;
  perform public.fn_handoff_overdue_escalate();
  if (select detail->'silence'->>'silent_seat' from public.agent_actions where id = v_o) is distinct from 'sales_engineer' then v_fail := v_fail || 'C: a "waiting" reply was taken as an answer (the sender blamed); '; end if;
  if (select detail->'silence'->>'escalated_to' from public.agent_actions where id = v_o) is distinct from 'ceo' then v_fail := v_fail || 'C: not escalated to the silent seat''s superior; '; end if;
  if (select detail->'silence'->>'escalated_to' from public.agent_actions where id = v_m) is distinct from 'ceo' then v_fail := v_fail || 'C: marketing silent was escalated to ' || coalesce((select detail->'silence'->>'escalated_to' from public.agent_actions where id = v_m), 'nobody') || ', not the CEO; '; end if;
  if (select detail->'silence'->>'silent_seat' || '>' || (detail->'silence'->>'escalated_to') from public.agent_actions where id = v_c) is distinct from 'ceo>ceo'
    then v_fail := v_fail || 'R1: the CEO silent did not go to his own queue (case-insensitive "the CEO seat"): '
                 || coalesce((select detail->>'silence' from public.agent_actions where id = v_c), '-') || '; '; end if;
  -- the digest line of the escalation names the silent seat (review item 8: "? owes the next move" was printed)
  v_b := public.fn_pool_say('handoff.overdue.escalated', 'agent_actions', v_o::text,
           (select payload from public.company_event where dedupe_key = 'handoff.overdue.escalated:' || v_o));
  if coalesce(v_b, '') not like '%sales_engineer owes the next move%' or v_b like '%?%' then v_fail := v_fail || 'C: the digest does not say who owes it: ' || coalesce(v_b, '-') || '; '; end if;
  if public.fn_pool_say('handoff.overdue.escalated', 'company_event', '0', '{}'::jsonb) not like '%no seat has taken it%' then v_fail := v_fail || 'C: an unknown seat is not said plainly; '; end if;
  v_r := public.fn_handoff_overdue_escalate();
  if coalesce(v_r->'ids', '[]'::jsonb) @> jsonb_build_array(v_o) then v_fail := v_fail || 'C: escalated again on the second pass; '; end if;
  perform public.fn_ceo_files_judgements();
  if not exists (select 1 from public.reasoning_held_question where dedupe_key = 'ceo.overdue_handoff:' || v_o || ':1') then v_fail := v_fail || 'C: the superior was not asked; '; end if;
  perform public.fn_ceo_files_judgements();
  if (select count(*) from public.reasoning_held_question where dedupe_key like 'ceo.overdue_handoff:' || v_o || ':%') <> 1 then v_fail := v_fail || 'C: the superior was asked more than once; '; end if;
  v_b := coalesce(public.fn_seat_pool_context('customer_support', null, 'internal')->>'block', '');
  if v_b not like 'YOUR HAND-OVERS: NO ANSWER YET: %sales_engineer owes knowledge.request #' || v_o || ' since %(escalated to ceo)%' then v_fail := v_fail || 'C: the sender does not read who owes it: ' || left(v_b, 300) || '; '; end if;
  v_b := coalesce(public.fn_seat_pool_context('sales_engineer', null, 'internal')->>'block', '');
  if v_b !~ ('YOU ARE LATE: [^.]*knowledge\.request #' || v_o || ' from customer_support was due') then v_fail := v_fail || 'C: the silent seat is not told it is late: ' || left(v_b, 400) || '; '; end if;
  -- the CEO's chase is an order the silent seat owes; it closes itself when the late hand-over is answered
  select id into v_q from public.reasoning_held_question where dedupe_key = 'ceo.overdue_handoff:' || v_o || ':1';
  perform public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'model', 'stub/model',
    'answer', 'The sales engineer owes this answer; two days to write the knowledge entry.', 'decision', jsonb_build_object('choice', 'chase')));
  select id into v_o2 from public.agent_actions where kind = 'handoff' and detail->>'type' = 'ceo.order' and detail->>'overdue_handoff_id' = v_o::text and status = 'pending';
  if v_o2 is null then v_fail := v_fail || 'C: chase opened no order; '; end if;
  perform set_config('qd.handoff_closer', 'customer_support', true);   -- knowledge.request is closed by its originator
  perform public.fn_seat_handoff_complete(v_o, jsonb_build_object('reply', 'knowledge entry written', 'not_cited', jsonb_build_object('reason', 'probe row', 'by', 'probe')));
  perform set_config('qd.handoff_closer', '', true);
  perform public.fn_ceo_orders_reported();
  if (select status from public.agent_actions where id = v_o2) is distinct from 'done' then v_fail := v_fail || 'C: the chase order stayed open after the answer; '; end if;
  perform public.fn_ceo_orders_reported();   -- the next tick writes the closed order's report back on the CEO's decision
  if coalesce((select detail->'silence'->'ceo_decision'->>'reported_done' from public.agent_actions where id = v_o), '') not like 'sales_engineer: %'
    then v_fail := v_fail || 'R3: the chase''s report is not written back on the CEO''s decision; '; end if;
  -- R1: the CEO's own late hand-over is his: answer or wait, never the founder
  select id into v_q from public.reasoning_held_question where dedupe_key = 'ceo.overdue_handoff:' || v_c || ':1';
  if v_q is null then v_fail := v_fail || 'R1: the CEO was not asked about his own late hand-over; ';
  else
    v_opts := (select (request->'decision'->'options')::text from public.reasoning_held_question where id = v_q);
    if v_opts not like '%"answer"%' or v_opts not like '%"wait"%' or v_opts ~* '(founder|chase)' then v_fail := v_fail || 'R1: the CEO''s own late item offers ' || v_opts || '; '; end if;
    perform public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'model', 'stub/model',
      'answer', 'The probe customer is answered: the knowledge entry exists.', 'decision', jsonb_build_object('choice', 'answer')));
    if (select evidence->>'reply' from public.agent_actions where id = v_c) not like 'The CEO answers: The probe customer is answered%'
       or not (select detail ? 'replied_at' from public.agent_actions where id = v_c)
      then v_fail := v_fail || 'R1: the CEO''s answer is not his reply on the hand-over; '; end if;
  end if;

  -- (d) "approvals from 1 to 2": a seat refused for lack of authority asks the CEO through the same judged path
  v_r := public.fn_agent_may_act('sales_engineer', 'probe.fasttrack_' || v_tag, null, 'probe:' || v_tag || ':1',
           jsonb_build_object('what', 'skip the matching wait for request ' || v_tag, 'why', 'the customer is on site today', 'facts', jsonb_build_object('quotes', 3)));
  v_h := (v_r->>'handoff_id')::bigint;
  if coalesce((v_r->>'may_act')::boolean, true) or not coalesce((v_r->>'asked')::boolean, false) or v_h is null then v_fail := v_fail || '(d): the refusal filed nothing: ' || v_r::text || '; '; end if;
  perform public.fn_ceo_files_judgements();
  select id into v_q from public.reasoning_held_question where dedupe_key = 'ceo.authority:' || v_h || ':1';
  if v_q is null then v_fail := v_fail || '(d): the CEO was not asked; ';
  else
    v_opts := (select (request->'decision'->'options')::text from public.reasoning_held_question where id = v_q);
    if (select question from public.reasoning_held_question where id = v_q) not like 'The sales_engineer asks: skip the matching wait%Why: the customer is on site today%'
       or v_opts not like '%allow_once%refuse%' or v_opts ~* 'founder'
      then v_fail := v_fail || '(d): the question does not carry who, what, why and the two answers (or names the founder): ' || v_opts || '; '; end if;
    -- a malformed answer grants nothing and is asked again (a day later)
    perform public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'yes go ahead, sure thing', 'decision', jsonb_build_object('choice', 'approve_forever')));
    if exists (select 1 from public.ceo_grant_once where handoff_id = v_h) then v_fail := v_fail || '(d): a malformed answer granted something; '; end if;
    perform public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'answer', 'Ask the founder about this one please.', 'decision', jsonb_build_object('choice', 'ask_founder')));
    if exists (select 1 from public.ceo_grant_once where handoff_id = v_h) or (select status from public.agent_actions where id = v_h) <> 'pending'
      then v_fail := v_fail || 'R1: ask_founder was taken as an answer; '; end if;
    update public.reasoning_held_question set created_at = now() - interval '25 hours', last_attempt_at = null where id = v_q;
    perform public.fn_ceo_files_judgements();
    if (select status from public.agent_actions where id = v_h) <> 'pending' or (select status from public.reasoning_held_question where id = v_q) <> 'held'
      then v_fail := v_fail || '(d): a malformed answer was not asked again; '; end if;
    perform public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'model', 'stub/model',
      'answer', 'One request, a customer on site, three quotes in: let it through once.', 'decision', jsonb_build_object('choice', 'allow_once')));
    v_b := coalesce(public.fn_seat_pool_context('sales_engineer', null, 'internal')->>'block', '');
    if v_b not like '%ANSWERED FOR YOU: ceo.authority #' || v_h || ': The CEO allows it ONCE%' then v_fail := v_fail || '(d): the asking seat does not read the answer: ' || right(v_b, 300) || '; '; end if;
    -- another subject FIRST, while the grant is unspent (review 3, item 8: tested after the grant was used, "any subject" survived)
    if coalesce((public.fn_agent_may_act('sales_engineer', 'probe.fasttrack_' || v_tag, null, 'probe:' || v_tag || ':other')->>'may_act')::boolean, false)
      then v_fail := v_fail || '(d): allow_once was honoured on another subject; '; end if;
    if coalesce((public.fn_agent_may_act('marketing', 'probe.fasttrack_' || v_tag, null, 'probe:' || v_tag || ':1')->>'may_act')::boolean, false)
      then v_fail := v_fail || '(d): allow_once was honoured for another seat; '; end if;
    if not coalesce((public.fn_agent_may_act('sales_engineer', 'probe.fasttrack_' || v_tag, null, 'probe:' || v_tag || ':1')->>'may_act')::boolean, false)
      then v_fail := v_fail || '(d): allow_once was not honoured; '; end if;
    if coalesce((public.fn_agent_may_act('sales_engineer', 'probe.fasttrack_' || v_tag, null, 'probe:' || v_tag || ':1')->>'may_act')::boolean, false)
      then v_fail := v_fail || '(d): allow_once was honoured twice; '; end if;
  end if;
  -- expiry: an unused grant past its time is not honoured
  insert into public.ceo_grant_once (seat, action_class, subject, reason, granted_at, expires_at)
  values ('sales_engineer', 'probe.fasttrack_' || v_tag, 'probe:' || v_tag || ':late', 'probe expiry', now() - interval '2 hours', now() - interval '1 hour');
  if coalesce((public.fn_agent_may_act('sales_engineer', 'probe.fasttrack_' || v_tag, null, 'probe:' || v_tag || ':late')->>'may_act')::boolean, false)
    then v_fail := v_fail || '(d): an expired grant was honoured; '; end if;
  -- refuse: the seat reads the reason
  v_h := (public.fn_agent_may_act('accountant', 'probe.reclassify_' || v_tag, null, 'probe:' || v_tag || ':r', jsonb_build_object('what', 'reclassify a probe balance'))->>'handoff_id')::bigint;
  perform public.fn_ceo_files_judgements();
  perform public.fn_reason_held_resolve((select id from public.reasoning_held_question where dedupe_key = 'ceo.authority:' || v_h || ':1'),
    jsonb_build_object('status', 'answered', 'model', 'stub/model', 'answer', 'No reclassification without the customer''s statement in hand.', 'decision', jsonb_build_object('choice', 'refuse')));
  if (select status || ' ' || (evidence->>'reply') from public.agent_actions where id = v_h) not like 'done The CEO refuses: No reclassification%' then v_fail := v_fail || '(d): refuse is not written where the seat reads it; '; end if;

  -- R2. THE HARD LIMITS (company_limit_change, fn_company_spend_*). The probe's day is its own: today's commitments are removed
  -- inside this rolled-back transaction, so a production day already spent does not decide the outcome (review 3, item 9).
  delete from public.company_spend_commitment where dubai_day = (now() at time zone 'Asia/Dubai')::date;
  v_per := public.fn_company_limit('per_action_aed'); v_day := public.fn_company_limit('daily_spend_aed');
  if v_per is null or v_day is null then v_fail := v_fail || 'R2: the company limits are not set; '; end if;
  v_amt := least(v_per, v_day);
  -- a money action with no amount: refused, nothing asked (review 3, item 1)
  v_r := public.fn_agent_may_act('marketing', 'probe.ad_spend_' || v_tag, null, 'campaign:probe' || v_tag);
  if coalesce((v_r->>'may_act')::boolean, true) or coalesce((v_r->>'asked')::boolean, true) or v_r->>'route' <> 'hard_limit'
    then v_fail := v_fail || 'R2: money with no amount was not refused unasked: ' || v_r::text || '; '; end if;
  -- above the per-action limit: refused, nothing asked
  v_r := public.fn_agent_may_act('marketing', 'probe.ad_spend_' || v_tag, v_per + 1, 'campaign:probe' || v_tag);
  if coalesce((v_r->>'may_act')::boolean, true) or coalesce((v_r->>'asked')::boolean, true) or v_r::text not like '%per-action limit%'
    then v_fail := v_fail || 'R2: money above the per-action limit was not refused unasked: ' || v_r::text || '; '; end if;
  if v_amt >= 2 then
    -- within the limits: asked; allow_once; the grant is honoured only within its amount, and commits it
    v_r := public.fn_agent_may_act('marketing', 'probe.ad_spend_' || v_tag, v_amt, 'campaign:probe' || v_tag || ':m', jsonb_build_object('what', 'boost the probe post', 'why', 'a probe within the limit'));
    v_h := (v_r->>'handoff_id')::bigint;
    perform public.fn_ceo_files_judgements();
    perform public.fn_reason_held_resolve((select id from public.reasoning_held_question where dedupe_key = 'ceo.authority:' || v_h || ':1'),
      jsonb_build_object('status', 'answered', 'model', 'stub/model', 'answer', 'A small spend inside the limit on a probe post is fine.', 'decision', jsonb_build_object('choice', 'allow_once')));
    if (select amount_aed from public.ceo_grant_once where handoff_id = v_h) is distinct from v_amt then v_fail := v_fail || 'R2: the grant does not carry the amount asked; '; end if;
    if coalesce((public.fn_agent_may_act('marketing', 'probe.ad_spend_' || v_tag, v_amt + 1, 'campaign:probe' || v_tag || ':m')->>'may_act')::boolean, false)
      then v_fail := v_fail || 'R2: a grant was honoured above its amount; '; end if;
    -- the day fills before the grant is used: it is not honoured, and stays unspent
    insert into public.company_spend_commitment (seat, action_class, subject, amount_aed, route) values ('marketing', 'probe.fill', 'probe', v_day, 'probe');
    v_r := public.fn_agent_may_act('marketing', 'probe.ad_spend_' || v_tag, v_amt, 'campaign:probe' || v_tag || ':m');
    if coalesce((v_r->>'may_act')::boolean, true) or (select used_at from public.ceo_grant_once where handoff_id = v_h) is not null
      then v_fail := v_fail || 'R2: a grant was honoured past today''s company limit: ' || v_r::text || '; '; end if;
    delete from public.company_spend_commitment where subject = 'probe' and route = 'probe';
    v_r := public.fn_agent_may_act('marketing', 'probe.ad_spend_' || v_tag, v_amt, 'campaign:probe' || v_tag || ':m');
    if not coalesce((v_r->>'may_act')::boolean, false) or not exists (select 1 from public.company_spend_commitment where grant_once_id = (v_r->>'grant_once')::bigint and amount_aed = v_amt)
      then v_fail := v_fail || 'R2: a grant within its amount was not honoured and committed: ' || v_r::text || '; '; end if;
    delete from public.company_spend_commitment where dubai_day = (now() at time zone 'Asia/Dubai')::date;
    -- an allow_once that the limit refuses by the time it lands writes no grant, even when the options were altered to offer it
    v_r := public.fn_agent_may_act('marketing', 'probe.ad_spend_' || v_tag, v_amt, 'campaign:probe' || v_tag || ':late', jsonb_build_object('what', 'boost again'));
    v_h := (v_r->>'handoff_id')::bigint;
    perform public.fn_ceo_files_judgements();
    insert into public.company_spend_commitment (seat, action_class, subject, amount_aed, route) values ('marketing', 'probe.fill', 'probe', v_day, 'probe');
    perform public.fn_reason_held_resolve((select id from public.reasoning_held_question where dedupe_key = 'ceo.authority:' || v_h || ':1'),
      jsonb_build_object('status', 'answered', 'model', 'stub/model', 'answer', 'Spend it, the post is doing well today.', 'decision', jsonb_build_object('choice', 'allow_once')));
    if exists (select 1 from public.ceo_grant_once where handoff_id = v_h)
       or (select status || ' ' || coalesce(evidence->>'outcome', '') from public.agent_actions where id = v_h) is distinct from 'done refused_by_limit'
      then v_fail := v_fail || 'R2: an allow_once past the limit at landing wrote a grant or was not closed by the limit; '; end if;
    delete from public.company_spend_commitment where dubai_day = (now() at time zone 'Asia/Dubai')::date;
    -- a standing grant with money still binds to the company limit (the accountant's meta_ads_spend is 0, so a probe grant)
    insert into public.ceo_standing_grant (grant_key, grantee_role_id, action_class, scope_note, max_amount_aed, issued_by)
    values ('probe.standing_spend_' || v_tag, 'marketing', 'probe.standing_spend_' || v_tag, 'probe', null, 'ceo');
    if coalesce((public.fn_agent_may_act('marketing', 'probe.standing_spend_' || v_tag, v_per + 1, 'probe:' || v_tag)->>'may_act')::boolean, false)
      then v_fail := v_fail || 'R2: an unlimited standing grant passed the per-action limit; '; end if;
    v_r := public.fn_agent_may_act('marketing', 'probe.standing_spend_' || v_tag, v_amt, 'probe:' || v_tag);
    if not coalesce((v_r->>'may_act')::boolean, false)
       or not exists (select 1 from public.company_spend_commitment where action_class = 'probe.standing_spend_' || v_tag and route = 'standing_grant')
      then v_fail := v_fail || 'R2: a standing grant within the limits was not committed: ' || v_r::text || '; '; end if;
  else
    -- the CEO has stopped spending (a limit under AED 2): even AED 1 is refused
    if coalesce((public.fn_agent_may_act('marketing', 'probe.ad_spend_' || v_tag, 1, 'campaign:probe' || v_tag || ':z')->>'may_act')::boolean, false)
      then v_fail := v_fail || 'R2: a spend passed a limit under AED 2; '; end if;
  end if;
  -- a message gate: weakening one, or a named recipient the suppression list holds, is refused unasked
  v_r := public.fn_agent_may_act('customer_support', 'probe.unsuppress_' || v_tag, null, 'probe:' || v_tag || ':g');
  if coalesce((v_r->>'may_act')::boolean, true) or coalesce((v_r->>'asked')::boolean, true) then v_fail := v_fail || 'R2: un-suppressing was not refused unasked; '; end if;
  insert into public.email_suppressions (email, reason, source) values ('pool-probe-sup-' || v_tag || '@example.invalid', 'unsubscribe', 'probe');
  v_r := public.fn_agent_may_act('sales_engineer', 'probe.outreach_reply_' || v_tag, null, 'probe:' || v_tag || ':s',
           jsonb_build_object('what', 'write to an unsubscribed address', 'email', 'pool-probe-sup-' || v_tag || '@example.invalid'));
  if coalesce((v_r->>'may_act')::boolean, true) or coalesce((v_r->>'asked')::boolean, true) or v_r::text not like '%message gate: suppression%'
    then v_fail := v_fail || 'R2: a recipient the suppression list holds was not refused unasked: ' || v_r::text || '; '; end if;
  -- a deploy is never asked, by anyone; the IT engineer's other questions go to the CEO
  v_r := public.fn_agent_may_act('it_engineer', 'deploy', null, 'probe:' || v_tag || ':d', jsonb_build_object('what', 'deploy the fix'));
  if coalesce((v_r->>'may_act')::boolean, true) or coalesce((v_r->>'asked')::boolean, true) or v_r->>'route' <> 'release_path'
    then v_fail := v_fail || 'R2: a deploy went through the authority check: ' || v_r::text || '; '; end if;
  v_r := public.fn_agent_may_act('it_engineer', 'probe.rerun_' || v_tag, null, 'probe:' || v_tag || ':i', jsonb_build_object('what', 'rerun the probe job'));
  if not coalesce((v_r->>'asked')::boolean, false) then v_fail := v_fail || 'R1: the IT engineer could not ask the CEO: ' || v_r::text || '; '; end if;
  -- the CEO acts on his own authority with a reason, on the record; without a reason he does not
  if coalesce((public.fn_agent_may_act('ceo', 'probe.own_' || v_tag, null, 'probe:' || v_tag || ':c')->>'may_act')::boolean, false)
    then v_fail := v_fail || 'R1: the CEO acted with no reason; '; end if;
  v_r := public.fn_agent_may_act('ceo', 'probe.own_' || v_tag, null, 'probe:' || v_tag || ':c', jsonb_build_object('why', 'The probe proves the CEO decides alone.'));
  if not coalesce((v_r->>'may_act')::boolean, false) or v_r->>'route' <> 'ceo_own_authority'
     or not exists (select 1 from public.ceo_grant_once where seat = 'ceo' and action_class = 'probe.own_' || v_tag and used_at is not null)
    then v_fail := v_fail || 'R1: the CEO''s own decision is not allowed and recorded: ' || v_r::text || '; '; end if;

  -- the cap: with no room left today, a new question waits; and authority takes at most half of the room (R4)
  update public.decision_policy set value = value || jsonb_build_object('items', (public.fn_ceo_judgement_room()->>'asked_today')::int) where key = 'ceo_daily_judgements';
  v_h := (public.fn_agent_may_act('marketing', 'probe.post_' || v_tag, null, 'probe:' || v_tag || ':cap')->>'handoff_id')::bigint;
  perform public.fn_ceo_files_judgements();
  if exists (select 1 from public.reasoning_held_question where dedupe_key = 'ceo.authority:' || v_h || ':1') then v_fail := v_fail || '(d): the daily cap did not hold; '; end if;
  for v_n in 1..3 loop
    perform public.fn_agent_may_act('marketing', 'probe.post_' || v_tag, null, 'probe:' || v_tag || ':half' || v_n);
  end loop;
  update public.decision_policy set value = value || jsonb_build_object('items', (public.fn_ceo_judgement_room()->>'asked_today')::int + 4, 'per_tick', 4) where key = 'ceo_daily_judgements';
  v_r := public.fn_ceo_files_judgements();
  if coalesce((v_r->>'filed_authority')::int, 99) > 2 then v_fail := v_fail || 'R4: authority took more than half of the room: ' || v_r::text || '; '; end if;
  update public.decision_policy set value = value || '{"items": 100000, "per_tick": 500, "aed": 10000}'::jsonb where key = 'ceo_daily_judgements';

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
