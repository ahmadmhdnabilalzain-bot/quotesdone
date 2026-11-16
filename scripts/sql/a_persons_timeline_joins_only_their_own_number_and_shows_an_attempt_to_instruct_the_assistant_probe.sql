-- PROBE for a_persons_timeline_joins_only_their_own_number_and_shows_an_attempt_to_instruct_the_assistant.sql (16 Nov 2026).
-- PURE: run after the file in the same query; it always raises CHK<<...>>, so every row it writes rolls back. Its people are
-- ZZ DEMO with @example.invalid addresses; the UAE number is a reserved fixture (+971 50 000 00xx) and its twin carries country
-- code 999, which no country has (the pattern of a_phone_tail_never_joins_two_people_probe.sql). Proves:
--   1. two customers whose phones share the last nine digits in two countries read two timelines, each only their own;
--   2. a number written in a local form names no country and still finds both (the fn_whatsapp_owner rule), and an e-mail
--      reads only its own person;
--   3. an attempt to instruct the assistant recorded on A is an event of A's timeline and not of B's.
do $probe$
declare v_a uuid; v_b uuid; t jsonb; v_fail text := '';
begin
  update public.decision_policy set value = 'true'::jsonb where key = 'demo_rehearsal_active';
  insert into public.customers (full_name, email, phone, phone_verified, whatsapp_opt)
  values ('ZZ DEMO timeline A', 'zz-tl-a@example.invalid', '+971500000093', true, 'same') returning id into v_a;
  insert into public.customers (full_name, email, phone, phone_verified, whatsapp_opt)
  values ('ZZ DEMO timeline B', 'zz-tl-b@example.invalid', '+999500000093', true, 'same') returning id into v_b;
  -- 1.
  t := public.fn_contact_timeline('+971500000093');
  if not (t->'customer_ids' @> to_jsonb(array[v_a]) and not (t->'customer_ids' @> to_jsonb(array[v_b]))) then v_fail := v_fail || ' A''s number reads ' || (t->'customer_ids')::text || ';'; end if;
  t := public.fn_contact_timeline('whatsapp:+999500000093');
  if not (t->'customer_ids' @> to_jsonb(array[v_b]) and not (t->'customer_ids' @> to_jsonb(array[v_a]))) then v_fail := v_fail || ' B''s number reads ' || (t->'customer_ids')::text || ';'; end if;
  -- 2.
  t := public.fn_contact_timeline('0500000093');
  if not (t->'customer_ids' @> to_jsonb(array[v_a, v_b])) then v_fail := v_fail || ' a local-form number lost a match: ' || (t->'customer_ids')::text || ';'; end if;
  t := public.fn_contact_timeline('zz-tl-b@example.invalid');
  if t->'customer_ids' <> to_jsonb(array[v_b]) then v_fail := v_fail || ' the e-mail reads ' || (t->'customer_ids')::text || ';'; end if;
  -- 3.
  perform public.fn_injection_attempt_record(jsonb_build_object('channel', 'whatsapp', 'surface', 'wa_inbound.intent_table',
    'message_ref', 'whatsapp:SMzzprobe93', 'customer_id', v_a, 'phone', '+971500000093', 'reading', 'tells the assistant to drop its rules'));
  t := public.fn_contact_timeline('+971500000093');
  if not exists (select 1 from jsonb_array_elements(t->'events') e where e->>'kind' = 'injection_attempt' and e->>'summary' like 'tried to instruct the assistant%')
    then v_fail := v_fail || ' A''s timeline does not show the attempt;'; end if;
  if coalesce((t->'counts'->>'injection_attempt')::int, 0) <> 1 then v_fail := v_fail || ' the attempt is not counted on A;'; end if;
  t := public.fn_contact_timeline('+999500000093');
  if exists (select 1 from jsonb_array_elements(t->'events') e where e->>'kind' = 'injection_attempt') then v_fail := v_fail || ' B''s timeline shows A''s attempt;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK two people on one tail read two timelines; the attempt is on its sender' else 'PROBE FAILED:' || v_fail end;
end $probe$;
