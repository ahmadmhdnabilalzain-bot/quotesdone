-- a_reserved_fixture_number_is_a_fixture_to_the_gateway_and_to_case_teardown_probe.sql — a PURE probe: it always raises
-- CHK<<...>>, so every row it writes rolls back. Seat: customer_support. Its number is a reserved ZZ DEMO fixture.
-- Proves: a reserved number is a fixture to the gateway in every key a caller uses, a real-looking one is not; a case of a
-- fixture number with no account is demo, a real-looking one is not, nor a real foreign number sharing a reserved tail; both routines are service_role only.
do $probe$
declare v_case bigint; v_real bigint; v_foreign bigint;
begin
  if not (public.fn_ai_subject_is_fixture('{"channel":"whatsapp","phone":"whatsapp:+971500000004","message_sid":"SMx"}') ->> 'fixture')::boolean
     or not (public.fn_ai_subject_is_fixture('{"to_phone":"+971500000099"}') ->> 'fixture')::boolean then
    raise exception 'CHK<<PROBE FAILED: a reserved number is not a fixture to the gateway>>';
  end if;
  if (public.fn_ai_subject_is_fixture('{"phone":"whatsapp:+971501234567"}') ->> 'fixture')::boolean then
    raise exception 'CHK<<PROBE FAILED: a real-looking number is treated as a fixture>>';
  end if;
  perform public.fn_support_touch('whatsapp', 'in', 'unknown', null, null, 'whatsapp:+971500000095', 'ZZ DEMO probe', null, 'en');
  select c.case_id into v_case from public.support_case c join public.support_customer_profile p on p.id = c.customer_profile_id
   where p.phone_tail = '500000095' order by c.case_id desc limit 1;
  perform public.fn_support_touch('whatsapp', 'in', 'unknown', null, null, 'whatsapp:+971501230098', 'ZZ DEMO probe real-looking', null, 'en');
  select c.case_id into v_real from public.support_case c join public.support_customer_profile p on p.id = c.customer_profile_id
   where p.phone_tail = '501230098' order by c.case_id desc limit 1;
  if v_case is null or not public.fn_support_case_is_demo(v_case) then raise exception 'CHK<<PROBE FAILED: the fixture number''s case is not demo>>'; end if;
  -- a REAL-shaped foreign number whose last nine digits are a reserved tail (+91 50000 0093) must never be demo
  perform public.fn_support_touch('whatsapp', 'in', 'unknown', null, null, 'whatsapp:+91500000093', 'ZZ DEMO probe foreign', null, 'en');
  select c.case_id into v_foreign from public.support_case c join public.support_customer_profile p on p.id = c.customer_profile_id
   where p.phone_tail = '500000093' order by c.case_id desc limit 1;
  if v_foreign is null or public.fn_support_case_is_demo(v_foreign) then
    raise exception 'CHK<<PROBE FAILED: a real foreign number that shares a reserved tail is classed demo (case %)>>', v_foreign;
  end if;
  if v_real is null or public.fn_support_case_is_demo(v_real) then raise exception 'CHK<<PROBE FAILED: a real-looking number''s case is demo>>'; end if;
  if has_function_privilege('anon', 'public.fn_ai_subject_is_fixture(jsonb)', 'execute') or has_function_privilege('anon', 'public.fn_support_case_is_demo(bigint)', 'execute') then
    raise exception 'CHK<<PROBE FAILED: executable by anon>>';
  end if;
  raise exception 'CHK<<PROBE OK: reserved numbers are fixtures to the gateway and demo to the case purge>>';
end
$probe$;
