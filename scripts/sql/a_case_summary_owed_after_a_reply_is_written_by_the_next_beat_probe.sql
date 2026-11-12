-- a_case_summary_owed_after_a_reply_is_written_by_the_next_beat_probe.sql — a PURE probe: it always raises CHK<<...>>, so every
-- row it writes rolls back. Seat: customer_support. Its number is a reserved ZZ DEMO fixture (+971 50 000 00xx): nothing is sent.
-- Proves: an answered WhatsApp case whose summary is older than its last message is owed; once its summary is written it is not;
-- the routine is service_role only and the step has its owner.
do $probe$
declare
  v_from text := 'whatsapp:+971500000098';
  v_ref text; v_owed jsonb; v_after jsonb;
begin
  insert into public.wa_messages (wa_from, wa_to, profile_name, inbound, reply, lang, escalated, sent, created_at, meta)
  values (v_from, 'whatsapp:+12183166814', 'ZZ DEMO', 'ZZ DEMO I need 12 windows', 'ZZ DEMO Thank you, what sizes?', 'en', false, false,
          now() - interval '10 minutes', '{"stage":"handled","probe":true}');
  select c.case_ref into v_ref from public.support_case c join public.support_customer_profile p on p.id = c.customer_profile_id
   where p.phone_tail = '500000098' and c.state <> 'closed' order by c.last_activity_at desc limit 1;
  if v_ref is null then raise exception 'CHK<<PROBE FAILED: the arrival did not open a case>>'; end if;
  update public.support_case set last_inbound_at = now() - interval '10 minutes', last_channel = 'whatsapp' where case_ref = v_ref;
  v_owed := public.fn_support_case_summaries_owed(20);
  if not exists (select 1 from jsonb_array_elements(v_owed) e where e ->> 'case_ref' = v_ref) then
    raise exception 'CHK<<PROBE FAILED: the answered case without a summary is not owed: %>>', v_owed;
  end if;
  perform public.fn_support_case_summary_write(v_ref, 0, '{"asked":"windows","said_or_did":"asked sizes","promised":[],"open":[]}',
    'ASKED: windows', 'ZZ DEMO windows', 'customer_support', 'probe');
  v_after := public.fn_support_case_summaries_owed(20);
  if exists (select 1 from jsonb_array_elements(v_after) e where e ->> 'case_ref' = v_ref) then
    raise exception 'CHK<<PROBE FAILED: still owed after its summary was written>>';
  end if;
  if has_function_privilege('anon', 'public.fn_support_case_summaries_owed(integer)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_support_case_summaries_owed(integer)', 'execute') then
    raise exception 'CHK<<PROBE FAILED: the owed list is executable by anon or authenticated>>';
  end if;
  if not exists (select 1 from public.resilience_step where step = 'caseCatchup' and owner_seat = 'customer_support') then
    raise exception 'CHK<<PROBE FAILED: the caseCatchup step has no row or no owner>>';
  end if;
  raise exception 'CHK<<PROBE OK: % owed after its answered message, not owed once summarised>>', v_ref;
end
$probe$;
