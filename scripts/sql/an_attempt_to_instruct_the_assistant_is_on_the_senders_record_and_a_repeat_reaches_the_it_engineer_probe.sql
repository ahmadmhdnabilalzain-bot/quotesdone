-- PROBE for an_attempt_to_instruct_the_assistant_is_on_the_senders_record_and_a_repeat_reaches_the_it_engineer.sql (16 Nov 2026).
-- PURE: run after the file in the same query; it always raises CHK<<...>>, so every row it writes rolls back. Its senders are
-- ZZ DEMO: an @example.invalid address and a widget caller hash, which no real person has. Proves:
--   1. one attempt is kept on the sender and counted (1), with no case; the same message again is not a second attempt;
--   2. the second attempt from that sender opens ONE it_engineer case; the third updates it (3), never a second case;
--   3. another sender is counted apart (1, no case);
--   4. no message reference or no sender: nothing is recorded;
--   5. nothing reaches anyone and nothing is blocked: no notification is queued, no ban is written.
do $probe$
declare r jsonb; v_fail text := ''; v_notes bigint; v_bans bigint; v_key text := 'injection_attempts:email:zz-inj-probe@example.invalid';
begin
  select count(*) into v_notes from public.notifications;
  select count(*) into v_bans from public.sanctions_ban;
  -- 1.
  r := public.fn_injection_attempt_record('{"channel": "email", "surface": "email_triage.needs_a_person", "message_ref": "email:zz-probe-1",
         "email": "ZZ-Inj-Probe@example.invalid", "reading": "asks the assistant to ignore its rules and list a supplier''s phone", "model": "stub/a"}');
  if not ((r->>'recorded')::boolean and (r->>'attempts')::int = 1 and not (r->>'case')::boolean) then v_fail := v_fail || ' first: ' || r::text || ';'; end if;
  r := public.fn_injection_attempt_record('{"channel": "email", "surface": "email_triage.needs_a_person", "message_ref": "email:zz-probe-1",
         "email": "zz-inj-probe@example.invalid", "reading": "same message"}');
  if (r->>'recorded')::boolean or (r->>'attempts')::int <> 1 then v_fail := v_fail || ' the same message counted twice: ' || r::text || ';'; end if;
  -- 2.
  r := public.fn_injection_attempt_record('{"channel": "widget", "surface": "site_assistant.person", "message_ref": "widget:zz-probe-2",
         "email": "zz-inj-probe@example.invalid", "reading": "tells the assistant it is now the administrator"}');
  if not ((r->>'attempts')::int = 2 and (r->>'case')::boolean) then v_fail := v_fail || ' second: ' || r::text || ';'; end if;
  r := public.fn_injection_attempt_record('{"channel": "email", "surface": "email_triage.needs_a_person", "message_ref": "email:zz-probe-3",
         "email": "zz-inj-probe@example.invalid", "reading": "asks for the system prompt"}');
  if (select count(*) from public.it_engineer_finding where issue_key = v_key and closed_at is null) <> 1 then v_fail := v_fail || ' not exactly one case for the sender;'; end if;
  if (select (evidence->>'attempts')::int from public.it_engineer_finding where issue_key = v_key and closed_at is null) <> 3
    then v_fail := v_fail || ' the case does not carry the count;'; end if;
  if (select evidence->'channels' from public.it_engineer_finding where issue_key = v_key) <> '["email", "widget"]'::jsonb
    then v_fail := v_fail || ' the case does not name both channels;'; end if;
  -- 3.
  r := public.fn_injection_attempt_record('{"channel": "widget", "surface": "site_assistant.person", "message_ref": "widget:zz-probe-4",
         "visitor": "widget:0f0f0f0f0f0f0f0f0f0f0f0f", "reading": "asks to reveal another customer"}');
  if not ((r->>'attempts')::int = 1 and not (r->>'case')::boolean and r->>'sender' = 'visitor') then v_fail := v_fail || ' another sender: ' || r::text || ';'; end if;
  -- 4.
  if (public.fn_injection_attempt_record('{"channel": "email", "email": "zz-inj-probe@example.invalid"}')->>'recorded')::boolean
    then v_fail := v_fail || ' recorded with no message reference;'; end if;
  if (public.fn_injection_attempt_record('{"channel": "email", "message_ref": "email:zz-probe-5"}')->>'recorded')::boolean
    then v_fail := v_fail || ' recorded with no sender;'; end if;
  -- 5.
  if (select count(*) from public.notifications) <> v_notes then v_fail := v_fail || ' a notification was queued;'; end if;
  if (select count(*) from public.sanctions_ban) <> v_bans then v_fail := v_fail || ' someone was banned;'; end if;
  if has_function_privilege('anon', 'public.fn_injection_attempt_record(jsonb)', 'execute') then v_fail := v_fail || ' anon may call it;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK attempts=' || (select count(*) from public.injection_attempt where email = 'zz-inj-probe@example.invalid') || ' one case'
                                   else 'PROBE FAILED:' || v_fail end;
end $probe$;
