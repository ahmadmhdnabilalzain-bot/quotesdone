-- PROBE of an_unanswered_mail_is_handed_to_its_seat_with_its_facts.sql. LOCAL only (scripts/db/local_pg16.mjs), after the file is
-- applied there. Always raises CHK<<...>>, so every row it writes rolls back (0 rows left) and nothing reaches a person: the hand-over
-- row is written directly (fn_seat_handoff shadow-records ZZ DEMO work) and acted on through fn_seat_handoff_act, the real door.
-- 23 Nov 2026: and the drive (fn_customer_support_unanswered_inbound_tick) hands an e-mail past its SLA over as mail.unanswered
-- with the facts, never review.requested to the CEO (qd.probe_files_demo_handoff on: the probe's own switch for ZZ DEMO hand-overs).
do $probe$
declare v_p text[] := '{}'; v_id bigint; a public.agent_actions; v jsonb; k public.seat_handoff_kind;
  v_m bigint; v_tag text := md5(random()::text); r jsonb; dr public.customer_support_inbound_drive; h public.agent_actions;
begin
  select * into k from public.seat_handoff_kind where type = 'mail.unanswered' and from_seat = 'customer_support' and to_seat = 'customer_support';
  if k.type is null then v_p := v_p || 'the kind is not registered'::text;
  elsif k.reply_within <> interval '24 hours' or k.originator_closes or k.handler <> 'fn_customer_support_holds_an_unanswered_mail' then
    v_p := v_p || ('the kind is registered wrong: ' || to_jsonb(k)::text); end if;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('customer_support', 'handoff', 'pending', 'low', 'mail.unanswered from customer_support about inbound_messages 999999001',
          jsonb_build_object('type', 'mail.unanswered', 'from', 'customer_support', 'to', 'customer_support', 'subject_table', 'inbound_messages',
            'subject_id', '999999001', 'inbound_message_id', 999999001, 'from_email', 'zz-demo-supplier@example.invalid', 'subject', 'ZZ DEMO Re: invitation',
            'received_at', '2026-11-12T06:30:33Z', 'error', 'fn_inbox_send: refused: this mail was read as unclear', 'draft', 'ZZ DEMO draft',
            'what', 'Answer or close, with the reason, the e-mail inbound_messages #999999001'),
          'inbound_messages', 'mail.unanswered:999999001')
  returning id into v_id;
  v := public.fn_seat_handoff_act(v_id);
  select * into a from public.agent_actions where id = v_id;
  if a.status <> 'pending' then v_p := v_p || ('the hand-over did not stay with its seat: ' || a.status); end if;
  if coalesce(a.detail->>'awaiting', '') !~ '#999999001 from zz-demo-supplier@example.invalid' or a.detail->>'awaiting' !~ 'read as unclear' or a.detail->>'awaiting' !~ 'a draft exists' then
    v_p := v_p || ('awaiting does not name the mail, the sender, the reason and the draft: ' || coalesce(a.detail->>'awaiting', 'null')); end if;
  if a.detail->>'awaiting' ~* 'review request|decision' then v_p := v_p || 'it still reads as a review of a decision'::text; end if;
  if coalesce(a.detail->>'what', '') = '' then v_p := v_p || 'no `what` for the CEO''s overdue question'::text; end if;
  -- the drive: an e-mail read 'unclear', its second reading spent, 30 h old
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  insert into public.inbound_messages (from_email, to_email, subject, body, needs_review, triaged_at, owner_role, ai_category, ai_draft_reply, created_at)
  values ('zz-demo-moa-' || v_tag || '@example.invalid', 'info@quotesdone.com', 'ZZ DEMO MOA', 'ZZ DEMO a meeting invitation', true, now(), 'customer_support',
          'no_auto_reply', 'ZZ DEMO draft reply', now() - interval '30 hours')
  returning id into v_m;
  insert into public.mailbox_reply_decision (inbound_message_id, reading, why, method, decided_by, decided_at)
  values (v_m, 'unclear', 'the model gateway failed 4 readings in a row (last: gateway_http_502:all_models_failed)', 'no_model', 'customer_support', now());
  insert into public.customer_support_inbound_drive (channel, message_id, outcome, acted_at, fixture, reread_requested_at)
  values ('email', v_m, 'read unclear: a second reading by the model was asked', now() - interval '28 hours', false, now() - interval '27 hours');
  r := public.fn_customer_support_unanswered_inbound_tick();
  select * into dr from public.customer_support_inbound_drive where channel = 'email' and message_id = v_m;
  select * into h from public.agent_actions where id = dr.escalation_handoff_id;
  if dr.escalated_at is null or h.id is null then v_p := v_p || ('the drive did not escalate the e-mail past its SLA: ' || coalesce(r::text, 'null'));
  else
    if h.detail->>'type' <> 'mail.unanswered' or h.agent <> 'customer_support' then
      v_p := v_p || ('the drive filed ' || coalesce(h.detail->>'type', '?') || ' to ' || h.agent || ', not mail.unanswered to customer_support'); end if;
    if coalesce(h.detail->>'what', '') !~ ('#' || v_m || ' from zz-demo-moa-') or h.detail->>'draft' <> 'ZZ DEMO draft reply'
       or (h.detail->>'waited_hours')::numeric < 29 or h.detail->>'owner_seat' <> 'customer_support' or h.detail->>'due_at' is null then
      v_p := v_p || ('the drive hand-over lacks the facts: ' || left(h.detail::text, 400)); end if;
  end if;
  if exists (select 1 from public.agent_actions where target_id = 'review.requested:' || v_m) then v_p := v_p || 'a review.requested was still filed'::text; end if;

  raise exception 'CHK<<%>>', case when cardinality(v_p) = 0 then 'PROBE OK: ' || (a.detail->>'awaiting') else 'PROBE FAILED: ' || array_to_string(v_p, '; ') end;
end $probe$;
