-- a_returning_person_is_asked_about_their_quiet_case_not_given_a_new_one_probe.sql — a PURE probe: it always raises
-- CHK<<...>>, so every row it writes rolls back. Seat: customer_support. Its person is a ZZ DEMO address at the reserved
-- .invalid domain, so no notice can reach anyone.
-- Proves: a case quiet for 8 days stays OPEN when the person writes again, with prior_activity_at kept and returned by
-- fn_support_open_cases; when the step after the reply routes them to a NEW case, the quiet one is closed with no rating
-- request; an active case of theirs is never closed by that.
do $probe$
declare
  v_email text := 'zz-demo-returning-probe-' || txid_current() || '@example.invalid';
  v_prof bigint; v_a jsonb; v_b jsonb; v_t jsonb; v_open jsonb; v_case public.support_case; v_csat int;
begin
  v_prof := (public.fn_support_open_cases('unknown', null, v_email, null) ->> 'profile')::bigint;
  v_a := public.fn_support_case_route(v_prof, 'new', null, 'widget', 'ZZ DEMO my aluminium windows', 'en');
  update public.support_case set last_activity_at = now() - interval '8 days', last_inbound_at = now() - interval '8 days'
   where case_ref = v_a ->> 'case_ref';
  v_t := public.fn_support_touch('widget', 'in', 'unknown', null, v_email, null, 'ZZ DEMO hello again', null, 'en');
  select * into v_case from public.support_case where case_ref = v_a ->> 'case_ref';
  if v_case.state = 'closed' or v_t ->> 'case_ref' is distinct from v_a ->> 'case_ref' then
    raise exception 'CHK<<PROBE FAILED: the quiet case was closed or not continued on arrival: % %>>', v_case.state, v_t;
  end if;
  if v_case.prior_activity_at is null or v_case.prior_activity_at > now() - interval '7 days' then
    raise exception 'CHK<<PROBE FAILED: prior_activity_at is not the quiet time: %>>', v_case.prior_activity_at;
  end if;
  v_open := public.fn_support_open_cases('unknown', null, v_email, null);
  if (v_open -> 'cases' -> 0 ->> 'prior_activity_at') is null then raise exception 'CHK<<PROBE FAILED: open cases do not return prior_activity_at: %>>', v_open; end if;
  v_b := public.fn_support_case_route(v_prof, 'new', null, 'widget', 'ZZ DEMO a new matter: painting', 'en');
  select * into v_case from public.support_case where case_ref = v_a ->> 'case_ref';
  select count(*) into v_csat from public.notifications where type = 'support_csat_request' and to_email = v_email;
  if v_case.state <> 'closed' or v_case.csat_requested_at is null or v_csat <> 0 then
    raise exception 'CHK<<PROBE FAILED: the quiet case on a new matter: state %, csat_requested_at %, rating requests %>>', v_case.state, v_case.csat_requested_at, v_csat;
  end if;
  if (select state from public.support_case where case_ref = v_b ->> 'case_ref') = 'closed' then raise exception 'CHK<<PROBE FAILED: the new case was closed>>'; end if;
  -- a bare "5" now is not the closed case's rating (it was never asked for one)
  v_t := public.fn_support_touch('widget', 'in', 'unknown', null, v_email, null, '5', null, 'en');
  if v_t ? 'rated' then raise exception 'CHK<<PROBE FAILED: a bare 5 was taken as the closed case''s rating: %>>', v_t; end if;
  raise exception 'CHK<<PROBE OK: % stayed open on return (quiet since %), closed without a rating when % opened>>', v_a ->> 'case_ref', v_case.prior_activity_at, v_b ->> 'case_ref';
end
$probe$;
