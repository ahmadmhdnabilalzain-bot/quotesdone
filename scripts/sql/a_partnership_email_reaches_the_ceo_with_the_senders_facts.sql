-- A PARTNERSHIP E-MAIL REACHES THE CEO WITH THE SENDER'S FACTS (16 Nov 2026). Seat: ceo. Agent: OPS_LOOPS (it_engineer + ceo
-- builder, wave 2 of the real-company holes; hole H10 of the COO hunt).
--
-- MEASURED (READ, origin/main 55489dde7): email_triage's model has a `partnership` category; customer_support answers such a
-- mail through the model and nothing follows: no seat duty, no pipeline, no owner (grep of scripts/sql and supabase/functions).
--
-- WHAT THIS ADDS
--   * The conversation partnership.proposed, customer_support -> ceo (seat_handoff_kind, reply within 2 days). email_triage
--     files it after its reply (supabase/functions/email_triage/partnership.ts) with the sender, the domain, the triage summary,
--     the account facts it gathered for the reply, and the proposal as untrusted text.
--   * Its handler fn_ceo_partnership_take files ONE held question to the CEO seat's model (ceo.partnership): pursue or decline,
--     with the reason and the next step. The handoff waits on that answer.
--   * fn_reason_apply_ceo__partnership closes the loop: the decision, the reason and the model are the handoff's evidence and
--     it is completed; a pursue also opens a CEO task with the next step, so the follow-through has an owner and a record.
--     Code checks only that the choice is one of the two; what the proposal is worth is the model's reading.
-- WHAT IT DOES NOT CHANGE: the triage categories, the reply the sender gets, fn_seat_handoff.
--
-- Probe: scripts/sql/a_partnership_email_reaches_the_ceo_with_the_senders_facts_probe.sql (local PG16, run twice)
-- Pending: scripts/sql/pending/a_partnership_email_reaches_the_ceo_with_the_senders_facts.txt
-- prevented by: supabase/functions/email_triage/partnership.test.ts and the probe.
-- Deploy order: apply this file, THEN deploy email_triage (before the apply a filed handoff would be an unregistered kind).
--   node scripts/apply_sql.mjs scripts/sql/a_partnership_email_reaches_the_ceo_with_the_senders_facts.sql --apply --ddl

create or replace function public.fn_ceo_partnership_take(p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions; v_hid bigint; v_q text;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  v_q := 'A company wrote to QuotesDone proposing a partnership (the sender''s words are in the case, as untrusted text). As the CEO, '
      || 'decide: pursue or decline. Say why in two or three sentences, and the next step (for pursue: what to ask or offer, who '
      || 'does it and by when; for decline: what the sender is told, if anything beyond the reply already sent).';
  v_hid := public.fn_reason_hold('ceo', 'ceo.partnership', v_q,
    jsonb_build_object('seat', 'ceo', 'surface', 'ceo.partnership', 'research', false, 'stakes', 'normal', 'question', v_q,
      'context', jsonb_build_object('audience', 'internal', 'case', jsonb_build_object(
        'sender_domain', a.detail->>'sender_domain', 'subject', a.detail->>'subject', 'summary', a.detail->>'summary',
        'proposal_untrusted', a.detail->>'proposal_untrusted', 'sender_facts', a.detail->>'sender_facts',
        'already_replied', a.detail->>'replied_by', 'received_at', a.created_at)),
      'decision', jsonb_build_object('name', 'partnership', 'options', jsonb_build_array(
        jsonb_build_object('id', 'pursue', 'meaning', 'QuotesDone takes the proposal forward: the answer is the reason and the next step'),
        jsonb_build_object('id', 'decline', 'meaning', 'QuotesDone does not take it forward: the answer is the reason'))),
      'subject', jsonb_build_object('handoff_id', a.id, 'inbound_message_id', a.detail->>'inbound_message_id'),
      'dedupeKey', 'partnership:' || a.id),
    jsonb_build_object('filed_by', 'ceo.partnership'), jsonb_build_object('handoff_id', a.id),
    'seat_handoff', 'partnership:' || a.id);
  return jsonb_build_object('waiting', 'the CEO seat''s model decides pursue or decline (held question ' || coalesce(v_hid::text, 'not filed') || ')',
                            'held_id', v_hid);
end $fn$;
revoke execute on function public.fn_ceo_partnership_take(bigint) from public, anon, authenticated;

create or replace function public.fn_reason_apply_ceo__partnership(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_h bigint; v_choice text := p_result->'decision'->>'choice';
        v_ans text := btrim(coalesce(p_result->>'answer', '')); v_task bigint; a public.agent_actions;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_h := nullif(r.subject->>'handoff_id', '')::bigint;
  select * into a from public.agent_actions where id = v_h and kind = 'handoff' and detail->>'type' = 'partnership.proposed';
  if a.id is null or v_choice is null or v_choice not in ('pursue', 'decline') or v_ans = '' then
    return null;                                   -- stays 'reasoned'; the handoff keeps waiting for the CEO seat
  end if;
  if v_choice = 'pursue' then
    v_task := public.fn_ceo_task_open(left('Pursue the partnership proposed by ' || coalesce(a.detail->>'sender_domain', 'a sender'), 200),
      left('Decided by the CEO seat''s model (held question ' || p_id || '): ' || v_ans || E'\nProposal: inbound message '
           || coalesce(a.detail->>'inbound_message_id', '?') || ', handoff ' || a.id || '.', 4000));
  end if;
  perform public.fn_seat_handoff_complete(a.id, jsonb_build_object('decision', v_choice, 'reason', left(v_ans, 2000),
            'model', p_result->>'model', 'held_id', p_id, 'ceo_task', v_task, 'decided_at', now()));
  return jsonb_build_object('handoff_id', a.id, 'decision', v_choice, 'ceo_task', v_task);
end $fn$;
revoke execute on function public.fn_reason_apply_ceo__partnership(bigint, jsonb) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
values ('partnership.proposed', 'customer_support', 'ceo',
        'A company e-mailed a partnership proposal (email_triage''s model read it so); the CEO seat''s model decides pursue or decline, with the sender''s facts.',
        'fn_ceo_partnership_take', interval '2 days', false,
        'scripts/sql/a_partnership_email_reaches_the_ceo_with_the_senders_facts.sql')
on conflict do nothing;

-- VERDICT (this file defines routines, so it never raises to report)
select case
  when not exists (select 1 from public.seat_handoff_kind where type = 'partnership.proposed' and from_seat = 'customer_support' and to_seat = 'ceo')
    then 'PROBE FAILED: partnership.proposed is not registered'
  when has_function_privilege('anon', 'public.fn_ceo_partnership_take(bigint)', 'execute')
    or has_function_privilege('anon', 'public.fn_reason_apply_ceo__partnership(bigint, jsonb)', 'execute')
    then 'PROBE FAILED: anon can execute a partnership routine'
  else 'PROBE OK' end as verdict;
