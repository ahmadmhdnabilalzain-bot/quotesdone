-- PROBE (rolled back, never applied) for every_open_case_of_a_person_reaches_the_reply_with_its_open_promises.sql
-- (it_engineer, 16 Nov 2026). A pure probe: it always raises CHK<<...>>, so every row it writes rolls back. Run it on a LOCAL
-- Postgres 16 built from the mirror, in the same transaction as the file:
--   QD_LOCAL_DB_URL=... node scripts/ci/rehearse_sql.mjs scripts/sql/<file>.sql scripts/sql/<file>_probe.sql
-- Its person is a ZZ DEMO address at the reserved .invalid domain, so nothing can reach anyone.
-- Proves, through the real writer (fn_support_case_summary_write records the promises in the ledger): a person with TWO open
-- cases gets both from fn_support_open_cases, newest first, each with its OPEN promises (what, due_text, due_at, owner_seat);
-- a promise marked kept is no longer returned; a case with no promise returns an empty list, never null.
do $probe$
declare
  v_email text := 'zz-demo-open-promises-probe-' || txid_current() || '@example.invalid';
  v_prof bigint; v_a jsonb; v_b jsonb; v_w jsonb; v_open jsonb; v_kept bigint; v_mark jsonb;
begin
  v_prof := (public.fn_support_open_cases('unknown', null, v_email, null) ->> 'profile')::bigint;
  v_a := public.fn_support_case_route(v_prof, 'new', null, 'whatsapp', 'ZZ DEMO my tiles delivery', 'en');
  v_w := public.fn_support_case_summary_write(v_a ->> 'case_ref', 0,
    '{"asked":"when the tiles arrive","said_or_did":"asked the supplier","promised":[{"what":"ZZ DEMO an update on the delivery","by":"Thursday","kind":"other","due_at":"2030-01-03T14:00:00Z"},{"what":"ZZ DEMO send the delivery note","by":null,"kind":"other","due_at":null}],"open":["delivery date"]}',
    'ASKED: when the tiles arrive', 'ZZ DEMO tiles delivery', 'customer_support', 'probe');
  if coalesce((v_w ->> 'ok')::boolean, false) is not true then raise exception 'CHK<<PROBE FAILED: case A summary not written: %>>', v_w; end if;
  v_b := public.fn_support_case_route(v_prof, 'new', null, 'widget', 'ZZ DEMO the reveal invoice', 'en');
  v_w := public.fn_support_case_summary_write(v_b ->> 'case_ref', 0,
    '{"asked":"a copy of the invoice","said_or_did":"sent it","promised":[],"open":[]}', 'ASKED: a copy of the invoice', 'ZZ DEMO invoice', 'customer_support', 'probe');
  if coalesce((v_w ->> 'ok')::boolean, false) is not true then raise exception 'CHK<<PROBE FAILED: case B summary not written: %>>', v_w; end if;
  -- case B is the newer one
  update public.support_case set last_activity_at = clock_timestamp() + interval '1 second' where case_ref = v_b ->> 'case_ref';

  v_open := public.fn_support_open_cases('unknown', null, v_email, null);
  if jsonb_array_length(v_open -> 'cases') is distinct from 2 or v_open -> 'cases' -> 0 ->> 'case_ref' is distinct from v_b ->> 'case_ref' then
    raise exception 'CHK<<PROBE FAILED: not both open cases newest first: %>>', v_open;
  end if;
  if jsonb_typeof(v_open -> 'cases' -> 0 -> 'promises') is distinct from 'array' or jsonb_array_length(v_open -> 'cases' -> 0 -> 'promises') is distinct from 0 then
    raise exception 'CHK<<PROBE FAILED: a case with no promise must return an empty list: %>>', v_open -> 'cases' -> 0;
  end if;
  -- soonest due first: the undated promise is due in support_promise_undated_hours (48 h, 'assumed'), before the 2030 one
  -- every comparison is null-safe (is distinct from): a read with no 'promises' key must fail here, not pass as null
  if jsonb_array_length(v_open -> 'cases' -> 1 -> 'promises') is distinct from 2
     or v_open -> 'cases' -> 1 -> 'promises' -> 0 ->> 'what' is distinct from 'ZZ DEMO send the delivery note'
     or v_open -> 'cases' -> 1 -> 'promises' -> 1 ->> 'what' is distinct from 'ZZ DEMO an update on the delivery'
     or v_open -> 'cases' -> 1 -> 'promises' -> 1 ->> 'due_text' is distinct from 'Thursday'
     or v_open -> 'cases' -> 1 -> 'promises' -> 1 ->> 'owner_seat' is distinct from 'customer_support'
     or (v_open -> 'cases' -> 1 -> 'promises' -> 1 ->> 'due_at')::timestamptz is distinct from '2030-01-03T14:00:00Z'::timestamptz then
    raise exception 'CHK<<PROBE FAILED: the older case does not carry its open promises, soonest due first: %>>', v_open -> 'cases' -> 1;
  end if;

  select id into v_kept from public.support_case_promise
   where case_ref = v_a ->> 'case_ref' and what = 'ZZ DEMO an update on the delivery';
  v_mark := public.fn_support_case_promise_mark(v_kept, 'kept', 'customer_support', 'ZZ DEMO probe: the update was sent');
  if coalesce((v_mark ->> 'ok')::boolean, false) is not true then raise exception 'CHK<<PROBE FAILED: could not mark the promise kept: %>>', v_mark; end if;
  v_open := public.fn_support_open_cases('unknown', null, v_email, null);
  if jsonb_array_length(v_open -> 'cases' -> 1 -> 'promises') is distinct from 1
     or v_open -> 'cases' -> 1 -> 'promises' -> 0 ->> 'what' is distinct from 'ZZ DEMO send the delivery note' then
    raise exception 'CHK<<PROBE FAILED: a kept promise is still returned as open: %>>', v_open -> 'cases' -> 1;
  end if;

  raise exception 'CHK<<PROBE OK: two open cases, newest first, each with its open promises; a kept promise is no longer returned>>';
end $probe$;
