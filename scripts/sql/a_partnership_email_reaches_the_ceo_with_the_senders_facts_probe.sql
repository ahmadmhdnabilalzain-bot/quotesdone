-- a_partnership_email_reaches_the_ceo_with_the_senders_facts_probe.sql (ceo, OPS_LOOPS, 16 Nov 2026)
-- A pure probe, run AFTER the file in the SAME transaction on a LOCAL Postgres 16 (scripts/db/local_pg16.mjs); it always
-- aborts (raise 'CHK<<...>>'), so nothing it writes survives. The sender is ZZ DEMO at example.invalid; the model's answers
-- are stubs; nothing is sent. Run twice on 16 Nov 2026: PROBE OK.
do $probe$
declare v_h bigint; v_h2 bigint; v_q bigint; v_q2 bigint; v_res jsonb; v_task bigint;
begin
  perform set_config('qd.probe_files_demo_handoff', 'on', true);   -- a ZZ DEMO handoff is filed in this transaction only
  -- the reference rows production holds (ceo_task_state); a local cluster built from the schema mirror has no rows
  insert into public.ceo_task_state (state, is_terminal, meaning) values ('open', false, 'created, not started'), ('done', true, 'finished, with evidence')
  on conflict do nothing;
  v_h := public.fn_seat_handoff('customer_support', 'ceo', 'partnership.proposed', 'inbound_messages', '990001',
    jsonb_build_object('inbound_message_id', 990001, 'from_email', 'zz-demo@partner.example.invalid', 'sender_domain', 'partner.example.invalid',
      'subject', 'ZZ DEMO partnership', 'summary', 'ZZ DEMO a fit-out association proposes listing QuotesDone for its members.',
      'proposal_untrusted', 'ZZ DEMO we have 400 member contractors in Dubai.', 'sender_facts', 'Known lead: no.'));
  if v_h is null or (select status from public.agent_actions where id = v_h) is distinct from 'pending' then
    raise exception 'CHK<<PROBE FAILED: the handoff was not filed and waiting: %>>', (select to_jsonb(a) from public.agent_actions a where id = v_h); end if;
  select id into v_q from public.reasoning_held_question where dedupe_key = 'partnership:' || v_h;
  if v_q is null or (select seat || '/' || surface from public.reasoning_held_question where id = v_q) is distinct from 'ceo/ceo.partnership' then
    raise exception 'CHK<<PROBE FAILED: the CEO seat''s model was not asked>>'; end if;
  if (select request->'context'->'case'->>'proposal_untrusted' from public.reasoning_held_question where id = v_q) not like '%400 member contractors%'
     or (select request->'context'->'case'->>'sender_facts' from public.reasoning_held_question where id = v_q) is distinct from 'Known lead: no.' then
    raise exception 'CHK<<PROBE FAILED: the question lacks the proposal or the sender''s facts>>'; end if;

  -- an answer outside pursue / decline leaves the handoff waiting
  v_res := public.fn_reason_apply_ceo__partnership(v_q, jsonb_build_object('answer', 'x', 'decision', jsonb_build_object('choice', 'maybe')));
  if v_res is not null or (select status from public.agent_actions where id = v_h) <> 'pending' then
    raise exception 'CHK<<PROBE FAILED: an invented choice closed the handoff>>'; end if;

  -- pursue: the handoff closes with the decision as its evidence, and the next step is a CEO task
  v_res := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'model', 'stub',
             'answer', 'ZZ DEMO pursue: 400 contractors is supply in our open trades; ask for their member trade list by Thursday.',
             'decision', jsonb_build_object('choice', 'pursue')));
  if (select status from public.agent_actions where id = v_h) is distinct from 'done'
     or (select evidence->>'decision' from public.agent_actions where id = v_h) is distinct from 'pursue' then
    raise exception 'CHK<<PROBE FAILED: the decision did not close the handoff: %>>', v_res; end if;
  v_task := nullif(v_res->'effect'->>'ceo_task', '')::bigint;
  if v_task is null or (select state from public.ceo_task where task_id = v_task) is distinct from 'open' then
    raise exception 'CHK<<PROBE FAILED: a pursue opened no CEO task>>'; end if;

  -- decline: closed with its reason, no task
  v_h2 := public.fn_seat_handoff('customer_support', 'ceo', 'partnership.proposed', 'inbound_messages', '990002',
    jsonb_build_object('inbound_message_id', 990002, 'sender_domain', 'other.example.invalid', 'subject', 'ZZ DEMO reseller', 'summary', 'ZZ DEMO a reseller.'));
  select id into v_q2 from public.reasoning_held_question where dedupe_key = 'partnership:' || v_h2;
  v_res := public.fn_reason_held_resolve(v_q2, jsonb_build_object('status', 'answered', 'model', 'stub', 'answer', 'ZZ DEMO decline: outside the UAE.',
             'decision', jsonb_build_object('choice', 'decline')));
  if (select status from public.agent_actions where id = v_h2) is distinct from 'done' or v_res->'effect'->>'ceo_task' is not null then
    raise exception 'CHK<<PROBE FAILED: a decline did not close cleanly: %>>', v_res; end if;

  -- the same message is handed once
  if public.fn_seat_handoff('customer_support', 'ceo', 'partnership.proposed', 'inbound_messages', '990001', '{}'::jsonb) <> v_h then
    raise exception 'CHK<<PROBE FAILED: the same message was handed twice>>'; end if;

  raise exception 'CHK<<PROBE OK>>';
end $probe$;
