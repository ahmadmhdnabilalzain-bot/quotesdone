-- PROBE for every_seat_reads_one_pool_and_every_hand_over_comes_back.sql. Seat: ceo. It always raises CHK<<...>>, so every
-- row it writes is rolled back. It writes rows only: no handler runs, nothing is queued for a channel, so it cannot reach a
-- person. Its subjects are ids no real row can have ('pool-probe-...'); one event is ZZ DEMO on purpose (the demo scope).
-- It proves, on production's own routines:
--   (ii)  a subject three seats touched (the sales engineer's verification, marketing's reply hand-over, support's question
--         to the sales engineer) shows every other seat's last action in EACH seat's context;
--   (iii) the founder's example: after supplier.approved, the it_engineer's context for that supplier says the sales
--         engineer verified him, and the it_engineer's company-today block counts it (real scope; the ZZ DEMO one is not);
--   (iv)  a hand-over past its window is escalated once to the sender's superior, and the sender's context says
--         "no answer yet from <seat>";
--   (v)   every seat's block is at most 1,300 characters (about 300 tokens), measured and printed;
--   (vi)  the dispatcher records a 'handover' subscription once; a demo event is not filed (ruling 1199).
do $probe$
declare
  v_sup text := 'pool-probe-' || substr(md5(clock_timestamp()::text), 1, 10);
  v_demo text := 'pool-probe-demo-' || substr(md5(clock_timestamp()::text || 'd'), 1, 10);
  v_subject jsonb; v_ctx jsonb; v_block text; v_seat text; v_sizes text := ''; v_h bigint; v_e bigint;
  v_digest jsonb; v_n int; v_fail text := '';
begin
  v_subject := jsonb_build_object('supplier_id', v_sup);
  -- the sales engineer's verification, written as production writes it (actor 'system', entity 'lead')
  insert into public.company_event (event_type, entity_type, entity_id, actor, payload)
  values ('supplier.approved', 'lead', v_sup, 'system', jsonb_build_object('company', 'Pool Probe Trading', 'verified', true, 'lifecycle_stage', 'approved'));
  insert into public.company_event (event_type, entity_type, entity_id, actor, payload)
  values ('supplier.approved', 'lead', v_demo, 'system', jsonb_build_object('company', 'ZZ DEMO Pool Probe Supplier', 'verified', true));
  -- marketing handed the supplier's mailbox reply to customer support, answered
  insert into public.agent_actions (agent, kind, status, title, detail, target_table, target_id, evidence, decided_at, decided_by)
  values ('customer_support', 'handoff', 'done', 'mailbox.supplier_reply from marketing about leads ' || v_sup,
          jsonb_build_object('type', 'mailbox.supplier_reply', 'from', 'marketing', 'to', 'customer_support', 'subject_table', 'leads', 'subject_id', v_sup),
          'leads', 'mailbox.supplier_reply:' || v_sup, jsonb_build_object('verdict', 'answered the supplier''s question on the portal', 'not_cited', jsonb_build_object('reason', 'a probe row, closed as written', 'by', 'every_seat_reads_one_pool probe')), now(), 'customer_support');
  -- customer support asked the sales engineer 10 days ago (window 7 days) and nobody answered
  insert into public.agent_actions (agent, kind, status, title, detail, target_table, target_id, created_at)
  values ('sales_engineer', 'handoff', 'pending', 'knowledge.request from customer_support about leads ' || v_sup,
          jsonb_build_object('type', 'knowledge.request', 'from', 'customer_support', 'to', 'sales_engineer', 'subject_table', 'leads', 'subject_id', v_sup),
          'leads', 'knowledge.request:' || v_sup, now() - interval '10 days')
  returning id into v_h;

  -- (ii) each of the three seats, and the it_engineer and the CEO, sees the others' last actions on the subject
  foreach v_seat in array array['sales_engineer', 'marketing', 'customer_support', 'it_engineer', 'ceo'] loop
    v_block := public.fn_seat_pool_context(v_seat, v_subject, 'internal')->>'block';
    if v_block not like '%sales_engineer: supplier.approved%' then v_fail := v_fail || v_seat || ' does not see the verification; '; end if;
    if v_block not like '%marketing: mailbox.supplier_reply to customer_support -- answered%' then v_fail := v_fail || v_seat || ' does not see marketing''s answered hand-over; '; end if;
    if v_block not like '%customer_support: knowledge.request to sales_engineer -- NO ANSWER YET from sales_engineer%' then v_fail := v_fail || v_seat || ' does not see support''s unanswered question; '; end if;
  end loop;

  -- an external audience reads kinds and states only: no name, no payload text
  v_block := public.fn_seat_pool_context('customer_support', v_subject, 'supplier')->>'block';
  if v_block like '%Pool Probe Trading%' or v_block like '%THE COMPANY TODAY%' then v_fail := v_fail || 'an external block carries a name or the digest; '; end if;
  if v_block not like '%supplier.approved (%' then v_fail := v_fail || 'the external block lost the timeline; '; end if;

  -- (iii) the founder's example: the it_engineer's company-today block counts it, the demo one stays out of it
  perform public.fn_seat_pool_digest_build(null);
  select counts into v_digest from public.seat_pool_digest where seat = 'it_engineer' and scope = 'real';
  if coalesce((v_digest->'heard'->>'supplier.approved')::int, 0) < 1 then v_fail := v_fail || 'it_engineer''s real digest does not count supplier.approved; '; end if;
  if (select body from public.seat_pool_digest where seat = 'it_engineer' and scope = 'real') like '%ZZ DEMO%' then v_fail := v_fail || 'demo traffic in a real digest; '; end if;
  if (select body from public.seat_pool_digest where seat = 'it_engineer' and scope = 'demo') not like '%ZZ DEMO Pool Probe Supplier%' then v_fail := v_fail || 'the demo digest lost the demo event; '; end if;
  if (select body from public.seat_pool_digest where seat = 'it_engineer' and scope = 'demo') like '%Pool Probe Trading %' then v_fail := v_fail || 'real traffic in a demo digest; '; end if;
  v_block := public.fn_seat_pool_context('it_engineer', v_subject, 'internal')->>'block';
  if v_block not like '%THE COMPANY TODAY%supplier.approved%' then v_fail := v_fail || 'the it_engineer''s block has no company-today count of supplier.approved; '; end if;

  -- (iv) escalated once, to the sender's superior (customer_support -> ceo), and the sender is not blind
  perform public.fn_handoff_overdue_escalate();
  perform public.fn_handoff_overdue_escalate();
  if (select detail->'silence'->>'escalated_to' from public.agent_actions where id = v_h) is distinct from 'ceo' then v_fail := v_fail || 'not escalated to the ceo; '; end if;
  if (select detail->'silence'->>'silent_seat' from public.agent_actions where id = v_h) is distinct from 'sales_engineer' then v_fail := v_fail || 'the silent seat is not the receiver; '; end if;
  select count(*) into v_n from public.company_event where event_type = 'handoff.overdue.escalated' and entity_id = v_h::text;
  if v_n <> 1 then v_fail := v_fail || 'escalated ' || v_n || ' times, not once; '; end if;
  v_block := public.fn_seat_pool_context('customer_support', '{}'::jsonb, 'internal')->>'block';
  if v_block not like '%no answer yet from sales_engineer since%knowledge.request #' || v_h || '%escalated to ceo%' then v_fail := v_fail || 'the sender''s context does not say no answer yet; '; end if;

  -- (v) the budget, measured for every seat on the probe subject
  foreach v_seat in array array['customer_support', 'sales_engineer', 'marketing', 'it_engineer', 'ceo', 'accountant'] loop
    v_ctx := public.fn_seat_pool_context(v_seat, v_subject, 'internal');
    v_sizes := v_sizes || v_seat || '=' || (v_ctx->>'chars') || ' ';
    if (v_ctx->>'chars')::int > 1300 then v_fail := v_fail || v_seat || ' block over 1300 chars; '; end if;
  end loop;

  -- (vi) a 'handover' subscription is delivered once; a demo event is recorded, not filed
  insert into public.event_subscription (event_type, agent_key, owns, delivery, action_class, reason)
  values ('probe.pool_handover', 'sales_engineer', true, 'none', null, 'probe owner'),
         ('probe.pool_handover', 'it_engineer', false, 'handover', 'probe.pool_handover', 'probe: must answer');
  insert into public.company_event (event_type, entity_type, entity_id, actor, payload)
  values ('probe.pool_handover', 'lead', v_demo, 'system', jsonb_build_object('company', 'ZZ DEMO Pool Probe Supplier')) returning id into v_e;
  perform public.fn_event_dispatch(0);
  perform public.fn_event_dispatch(0);
  select count(*) into v_n from public.event_delivery where event_id = v_e;
  if v_n <> 1 then v_fail := v_fail || 'dispatch recorded ' || v_n || ' deliveries, not 1; '; end if;
  if (select result from public.event_delivery where event_id = v_e) is distinct from 'not filed: a demo event (ruling 1199)' then
    v_fail := v_fail || 'a demo event was filed: ' || coalesce((select coalesce(result, unroutable_reason) from public.event_delivery where event_id = v_e), 'nothing') || '; ';
  end if;

  if v_fail <> '' then raise exception 'CHK<<PROBE FAILED: %>>', v_fail; end if;
  raise exception 'CHK<<PROBE OK: sizes % >>', v_sizes;
end $probe$;
