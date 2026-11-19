-- PROBE of an_unanswered_mail_is_handed_to_its_seat_with_its_facts.sql. LOCAL only (scripts/db/local_pg16.mjs), after the file is
-- applied there. Always raises CHK<<...>>, so every row it writes rolls back (0 rows left) and nothing reaches a person: the hand-over
-- row is written directly (fn_seat_handoff shadow-records ZZ DEMO work) and acted on through fn_seat_handoff_act, the real door.
do $probe$
declare v_p text[] := '{}'; v_id bigint; a public.agent_actions; v jsonb; k public.seat_handoff_kind;
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
  raise exception 'CHK<<%>>', case when cardinality(v_p) = 0 then 'PROBE OK: ' || (a.detail->>'awaiting') else 'PROBE FAILED: ' || array_to_string(v_p, '; ') end;
end $probe$;
