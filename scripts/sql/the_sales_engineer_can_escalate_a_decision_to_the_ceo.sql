-- THE SALES ENGINEER CAN ESCALATE A DECISION TO THE CEO: THIN SUPPLY FOR A REQUEST, OR A DISPUTED REVEAL.
--
-- Assigned: ceo (the door and the decision); the sales_engineer sends. 24 Sep 2026. Seat audit GAPS.md, CEO gap 8
-- (ledger 983). Approved job description: "Every seat reports to the CEO. It sends directives through the handoff
-- kinds"; the CEO "decides alone ... directives to seats, priorities".
--
-- ══ MEASURED, 24 Sep 2026 ═════════════════════════════════════════════════════════════════════════════
--   select type, from_seat, to_seat from public.seat_handoff_kind where to_seat = 'ceo';
--     deliberation.review (from every seat), delivery.result (customer_support), it.finding (it_engineer),
--     marketing.report (marketing). Between the sales engineer and the CEO only deliberation.review exists, which
--     is a cross-family challenge of a decision already made — not a way to hand the CEO a decision. fn_seat_handoff
--     refuses an unregistered kind (the row is written 'failed' and a finding is raised), so the sales engineer had
--     no door to the CEO at all.
--
-- ══ WHAT THIS ADDS ════════════════════════════════════════════════════════════════════════════════════
--   The kind sales.escalation (sales_engineer -> ceo), handler fn_ceo_takes_sales_escalation. The payload names
--   'escalation' = 'thin_supply' | 'disputed_reveal' and a 'case' object with the facts. Both are judgements (they
--   weigh a customer against the supply and the rules), so the CEO reasons them through the existing think() path
--   (fn_seat_duty_reason, surface ceo.sales_escalation, stakes high) with a fixed option set per escalation, and the
--   handoff waits ('waiting') until the answer is applied. fn_reason_apply_ceo__sales_escalation completes the handoff
--   with the choice and the reasoning, which is the sales engineer's answer. A choice outside the options raises and
--   is reasoned again (the fn_ceo_review_applies convention). An escalation of any other name is refused by raising,
--   so the handoff is recorded 'failed' and visible, never silently accepted.
--   The options state the founder's rules as ruled: exact trade match or none; ANY number of suppliers may quote.
--
-- NOT CHANGED: the sales engineer's routines (they start sending when the sales engineer's build calls
-- fn_seat_handoff('sales_engineer', 'ceo', 'sales.escalation', ...)), the refund loop, fn_ceo_decides_post_reveal_dispute.
--
-- Pending: scripts/sql/pending/the_sales_engineer_can_escalate_a_decision_to_the_ceo.txt.

create or replace function public.fn_ceo_takes_sales_escalation(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; v_kind text; v_options jsonb; v_question text; v_held bigint;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  v_kind := a.detail->>'escalation';
  if v_kind = 'thin_supply' then
    v_question := 'The sales engineer escalates a customer request whose exact trade has fewer matchable suppliers than it needs. '
      || 'Our rules: a request goes only to suppliers of the exact trade (no nearest trade), and any number of suppliers may quote; '
      || 'the comparison report recommends the top three by value. Decide what happens to this request.';
    v_options := '[{"id":"send_to_matched","meaning":"send it now to every exact-trade supplier that matches, however few"},'
              || '{"id":"recruit_then_send","meaning":"the sales engineer recruits suppliers for this exact trade first and sends when enough match, telling the customer the date"},'
              || '{"id":"tell_customer_no_supply","meaning":"no supplier of this exact trade can serve it; the customer is told plainly and nothing is charged"}]';
  elsif v_kind = 'disputed_reveal' then
    v_question := 'The sales engineer escalates a reveal the customer or the supplier disputes. Decide the company''s answer; '
      || 'a refund is decided by the CEO''s refund checklist, never here.';
    v_options := '[{"id":"uphold_reveal","meaning":"the reveal was delivered as the terms say; the fee stands and the parties are told why"},'
              || '{"id":"refund_review","meaning":"open the refund review: the CEO''s refund checklist decides it against the Stripe record"},'
              || '{"id":"investigate","meaning":"the facts are not enough; the sales engineer gathers the named facts and escalates again"}]';
  else
    raise exception 'sales.escalation: unknown escalation %, expected thin_supply or disputed_reveal', coalesce(v_kind, '(none)');
  end if;
  v_held := public.fn_seat_duty_reason('ceo', 'ceo.sales_escalation', v_question, v_options::jsonb,
    coalesce(a.detail->'case', '{}'::jsonb) || jsonb_build_object('escalation', v_kind, 'subject', a.detail->>'subject_table', 'subject_id', a.detail->>'subject_id'),
    jsonb_build_object('handoff_id', a.id, 'escalation', v_kind), 'sales_escalation:' || a.id);
  return jsonb_build_object('accepted', true, 'escalation', v_kind, 'held_question', v_held,
    'waiting', 'the CEO decides this by reasoning (held question ' || v_held || ') and answers on this handoff');
end $fn$;
revoke execute on function public.fn_ceo_takes_sales_escalation(bigint) from public, anon, authenticated;

create or replace function public.fn_reason_apply_ceo__sales_escalation(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; v_hid bigint;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if v_choice is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v_choice) then
    raise exception 'CHOICE_NOT_AN_OPTION: % is not an option of % (held question %)', coalesce(v_choice, 'no choice'), r.surface, p_id;
  end if;
  v_hid := (r.subject->>'handoff_id')::bigint;
  perform set_config('qd.handoff_closer', 'ceo', true);
  perform public.fn_seat_handoff_complete(v_hid, jsonb_build_object('decided_by', 'ceo', 'escalation', r.subject->>'escalation',
    'choice', v_choice, 'reasoning', left(coalesce(p_result->>'answer', ''), 3000), 'model', p_result->>'model', 'held_question', p_id));
  perform set_config('qd.handoff_closer', '', true);
  return jsonb_build_object('applied', true, 'handoff_id', v_hid, 'choice', v_choice);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__sales_escalation(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_ceo__sales_escalation(bigint, jsonb) to service_role;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
values ('sales.escalation', 'sales_engineer', 'ceo',
        'The sales engineer hands the CEO a decision it does not own: a request whose exact trade has too few suppliers, or a disputed reveal. The CEO reasons it and answers on the handoff.',
        'fn_ceo_takes_sales_escalation', interval '1 day', false,
        'scripts/sql/the_sales_engineer_can_escalate_a_decision_to_the_ceo.sql')
on conflict (type, from_seat, to_seat) do update set meaning = excluded.meaning, handler = excluded.handler,
  reply_within = excluded.reply_within, originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;
