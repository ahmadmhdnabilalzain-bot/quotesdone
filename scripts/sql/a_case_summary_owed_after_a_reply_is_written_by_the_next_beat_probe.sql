-- a_case_summary_owed_after_a_reply_is_written_by_the_next_beat_probe.sql — a PURE probe: it always raises CHK<<...>>, so every
-- row it writes rolls back (the rehearsal flag it turns on included). Seat: customer_support. Its numbers are reserved ZZ DEMO
-- fixtures (+971 50 000 00xx): nothing is sent.
-- Proves: (1) an answered (fixture-captured) case whose summary is older than its last message is owed while a rehearsal window
-- is open, and (2) not owed with the window closed (each catch-up is a paid call); (3) a reply that was not sent makes nothing
-- owed; (4) once its summary is written it is not owed; (5) the review round-2 case: two open cases, the message attached to the
-- newest but recorded on the other, so the newest is NOT owed; the routine is service_role only and the step has its owner.
do $probe$
declare
  v_cap text := 'captured: reserved fixture mobile (+971 50 000 00xx) - recorded for the rehearsal, never handed to Twilio';
  v_ref text; v_unsent text; v_prof bigint; v_a text; v_b text; v_owed jsonb;
begin
  update public.decision_policy set value = 'true'::jsonb where key = 'demo_rehearsal_active';
  -- (1) answered and captured
  insert into public.wa_messages (wa_from, wa_to, profile_name, inbound, reply, lang, escalated, sent, created_at, meta)
  values ('whatsapp:+971500000098', 'whatsapp:+12183166814', 'ZZ DEMO', 'ZZ DEMO I need 12 windows', 'ZZ DEMO what sizes?', 'en', false, false,
          now() - interval '10 minutes', jsonb_build_object('stage', 'handled', 'probe', true, 'send_error', v_cap));
  select c.case_ref into v_ref from public.support_case c join public.support_customer_profile p on p.id = c.customer_profile_id
   where p.phone_tail = '500000098' and c.state <> 'closed' order by c.last_activity_at desc limit 1;
  -- (3) a reply that was never sent (no send, no capture)
  insert into public.wa_messages (wa_from, wa_to, profile_name, inbound, reply, lang, escalated, sent, created_at, meta)
  values ('whatsapp:+971500000096', 'whatsapp:+12183166814', 'ZZ DEMO', 'ZZ DEMO hello', 'ZZ DEMO a reply that did not go', 'en', false, false,
          now() - interval '10 minutes', '{"stage":"handled","probe":true,"send_error":"twilio refused"}');
  select c.case_ref into v_unsent from public.support_case c join public.support_customer_profile p on p.id = c.customer_profile_id
   where p.phone_tail = '500000096' and c.state <> 'closed' order by c.last_activity_at desc limit 1;
  if v_ref is null or v_unsent is null then raise exception 'CHK<<PROBE FAILED: the arrivals did not open cases>>'; end if;
  update public.support_case set last_inbound_at = now() - interval '10 minutes', last_channel = 'whatsapp' where case_ref in (v_ref, v_unsent);
  v_owed := public.fn_support_case_summaries_owed(20);
  if not exists (select 1 from jsonb_array_elements(v_owed) e where e ->> 'case_ref' = v_ref) then
    raise exception 'CHK<<PROBE FAILED (1): the answered case without a summary is not owed in a rehearsal: %>>', v_owed;
  end if;
  if exists (select 1 from jsonb_array_elements(v_owed) e where e ->> 'case_ref' = v_unsent) then
    raise exception 'CHK<<PROBE FAILED (3): a case whose reply was never sent is owed>>';
  end if;
  update public.decision_policy set value = 'false'::jsonb where key = 'demo_rehearsal_active';
  if exists (select 1 from jsonb_array_elements(public.fn_support_case_summaries_owed(20)) e where e ->> 'case_ref' = v_ref) then
    raise exception 'CHK<<PROBE FAILED (2): a ZZ DEMO case is owed (a paid catch-up) with no rehearsal window open>>';
  end if;
  update public.decision_policy set value = 'true'::jsonb where key = 'demo_rehearsal_active';
  perform public.fn_support_case_summary_write(v_ref, 0, '{"asked":"windows","said_or_did":"asked sizes","promised":[],"open":[]}',
    'ASKED: windows', 'ZZ DEMO windows', 'customer_support', 'probe');
  if exists (select 1 from jsonb_array_elements(public.fn_support_case_summaries_owed(20)) e where e ->> 'case_ref' = v_ref) then
    raise exception 'CHK<<PROBE FAILED (4): still owed after its summary was written>>';
  end if;
  -- (5) the reviewer's scenario (owed_wrong_case_probe.sql): windows case A, cleaning case B (newest); a windows message attaches to
  -- B on arrival and is recorded on A after the reply
  insert into public.wa_messages (wa_from, wa_to, profile_name, inbound, reply, lang, escalated, sent, created_at, meta)
  values ('whatsapp:+971500000097', 'whatsapp:+12183166814', 'ZZ DEMO', 'ZZ DEMO I need 12 windows', 'ZZ DEMO what sizes?', 'en', false, false,
          now() - interval '30 minutes', jsonb_build_object('stage', 'handled', 'probe', true, 'send_error', v_cap));
  select c.case_ref, c.customer_profile_id into v_a, v_prof from public.support_case c join public.support_customer_profile p on p.id = c.customer_profile_id
   where p.phone_tail = '500000097' and c.state <> 'closed' order by c.last_activity_at desc limit 1;
  perform public.fn_support_case_summary_write(v_a, 0, '{"asked":"windows","said_or_did":"asked sizes","promised":[],"open":[]}', 'ASKED: windows', 'ZZ DEMO windows', 'customer_support', 'probe');
  v_b := public.fn_support_case_route(v_prof, 'new', null, 'whatsapp', 'ZZ DEMO my cousin cleaning company', 'en') ->> 'case_ref';
  perform public.fn_support_case_summary_write(v_b, 0, '{"asked":"cleaning","said_or_did":"sent link","promised":[],"open":[]}', 'ASKED: cleaning', 'ZZ DEMO cleaning', 'customer_support', 'probe');
  update public.support_case set last_activity_at = now() - interval '20 minutes' where case_ref = v_a;
  update public.support_case set last_activity_at = now() - interval '15 minutes' where case_ref = v_b;
  insert into public.wa_messages (wa_from, wa_to, profile_name, inbound, reply, lang, escalated, sent, created_at, meta)
  values ('whatsapp:+971500000097', 'whatsapp:+12183166814', 'ZZ DEMO', 'ZZ DEMO how many quotes for my windows?', 'ZZ DEMO three are levelled', 'en', false, false,
          now() - interval '10 minutes', jsonb_build_object('stage', 'handled', 'probe', true, 'send_error', v_cap));
  perform public.fn_support_case_route(v_prof, 'continue', v_a, 'whatsapp', 'ZZ DEMO how many quotes for my windows?', 'en');
  perform public.fn_support_case_summary_write(v_a, 1, '{"asked":"windows, how many quotes","said_or_did":"three levelled","promised":[],"open":[]}', 'ASKED: windows quotes', 'ZZ DEMO windows', 'customer_support', 'probe');
  update public.support_case set last_inbound_at = last_inbound_at - interval '10 minutes', summary_updated_at = summary_updated_at - interval '9 minutes' where case_ref = v_a;
  update public.support_case set last_inbound_at = last_inbound_at - interval '10 minutes', summary_updated_at = summary_updated_at - interval '14 minutes' where case_ref = v_b;
  if exists (select 1 from jsonb_array_elements(public.fn_support_case_summaries_owed(20)) e where e ->> 'case_ref' in (v_a, v_b)) then
    raise exception 'CHK<<PROBE FAILED (5): the exchange recorded on % leaves % owed (it would be written into the wrong case)>>', v_a, v_b;
  end if;
  if has_function_privilege('anon', 'public.fn_support_case_summaries_owed(integer)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_support_case_summaries_owed(integer)', 'execute') then
    raise exception 'CHK<<PROBE FAILED: the owed list is executable by anon or authenticated>>';
  end if;
  if not exists (select 1 from public.resilience_step where step = 'caseCatchup' and owner_seat = 'customer_support') then
    raise exception 'CHK<<PROBE FAILED: the caseCatchup step has no row or no owner>>';
  end if;
  raise exception 'CHK<<PROBE OK: % owed in a rehearsal only, not after its summary; an unsent reply owes nothing; % recorded, % not owed>>', v_ref, v_a, v_b;
end
$probe$;
