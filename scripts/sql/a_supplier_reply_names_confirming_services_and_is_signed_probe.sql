-- Pure probe: raises so everything rolls back; it reads the routine and sends nothing. Replay it AFTER
-- a_supplier_reply_names_confirming_services_and_is_signed.sql (scripts/ci/rehearse_sql.mjs does). Its message starts PROBE OK or PROBE FAILED.
-- Known-bad controls: the two texts that went out before (the real subsidiary text of 2 Nov and the old interested text, unsigned, no
-- services) must FAIL the same predicate the live texts must pass.
do $probe$
declare
  v_link text := 'https://quotesdone.com/en/portal';
  v_old_sub text := 'It needs its licensed name, a UAE mobile number verified with a code, the verified work e-mail, the trade licence, the company profile and acceptance of the supplier terms.';
  v_old_int text := 'To be verified we need your licensed company name, a UAE mobile number verified with a code, the verified work e-mail, the trade licence, the company profile and your acceptance of the supplier terms. Only you can verify and accept these.';
  v_ok text[] := '{}'; v_bad text[] := '{}'; v_intent text; v_t text; v_why text;
begin
  -- the predicate: signed, English only, the link once, and (when it lists requirements) the services step
  -- control 1 and 2 must fail it
  foreach v_t in array array[v_old_sub, v_old_int] loop
    if v_t like '%Kind regards,' || E'\n' || 'The QuotesDone Team' and v_t ~* 'confirm[^.]*services' then
      raise exception 'PROBE FAILED: the known-bad control passes the predicate: %', v_t;
    end if;
  end loop;
  foreach v_intent in array array['subsidiary', 'later', 'interested'] loop
    v_t := public.fn_supplier_reply_answer(v_intent, v_link);
    v_why := null;
    if right(v_t, length(E'\n\nKind regards,\nThe QuotesDone Team')) <> E'\n\nKind regards,\nThe QuotesDone Team' then v_why := 'not signed'; end if;
    if v_t !~ '^[\x01-\x7f]*$' then v_why := 'not English only'; end if;
    if position(v_link in v_t) = 0 then v_why := 'no registration link'; end if;
    if v_intent <> 'later' and v_t !~ 'confirm[^.]*services[^.]*Services tab' then v_why := 'does not name confirming the services'; end if;
    if v_intent <> 'later' and v_t !~ 'held until' then v_why := 'does not say it is held until then'; end if;
    if v_intent = 'subsidiary' and v_t not like '%different e-mail address: one e-mail address manages one company%' then v_why := 'lost the separate-company rule'; end if;
    if v_why is not null then v_bad := v_bad || (v_intent || ': ' || v_why); else v_ok := v_ok || v_intent; end if;
  end loop;
  if array_length(v_bad, 1) is not null then raise exception 'PROBE FAILED: %', array_to_string(v_bad, '; '); end if;
  raise exception 'PROBE OK: % answers are signed, English, linked and name confirming the services; the two old texts fail the same predicate', array_to_string(v_ok, ', ');
end $probe$;
