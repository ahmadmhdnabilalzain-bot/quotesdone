-- PROBE: never applied. Always raises CHK<<PROBE ...>>, so nothing survives. Seat: it_engineer.
-- Two owed notices (ZZ DEMO, escalated in 2000 so they sort first); the first caller (limit 1) claims one, the second
-- caller gets the OTHER, and a third gets neither of them. A claim older than the 30-minute lease comes back.
-- Real rows are counted before and after: the probe's own calls may claim them, and the raise rolls that back.
do $probe$
declare
  v_a bigint; v_b bigint; v1 jsonb; v2 jsonb; v3 jsonb; v4 jsonb; v_ids1 bigint[]; v_ids2 bigint[]; v_ids3 bigint[]; v_ids4 bigint[];
  v_real0 int; v_real1 int;
begin
  select count(*) into v_real0 from public.reasoning_held_question where notice_delivered_at is null and escalated_at is not null;
  insert into public.reasoning_held_question (seat, surface, question, request, reason, status, escalated_at, subject)
  values ('customer_support', 'wa_inbound.needs_a_person', 'ZZ DEMO probe A', '{}'::jsonb, 'probe', 'failed', '2000-01-01', jsonb_build_object('phone', '+971500000001'))
  returning id into v_a;
  insert into public.reasoning_held_question (seat, surface, question, request, reason, status, escalated_at, subject)
  values ('customer_support', 'wa_inbound.needs_a_person', 'ZZ DEMO probe B', '{}'::jsonb, 'probe', 'failed', '2000-01-02', jsonb_build_object('phone', '+971500000002'))
  returning id into v_b;

  v1 := public.fn_reason_held_notice_due(1);
  v2 := public.fn_reason_held_notice_due(1);
  v3 := public.fn_reason_held_notice_due(100);
  select array_agg((e->>'id')::bigint) into v_ids1 from jsonb_array_elements(v1) e;
  select array_agg((e->>'id')::bigint) into v_ids2 from jsonb_array_elements(v2) e;
  select array_agg((e->>'id')::bigint) into v_ids3 from jsonb_array_elements(v3) e;

  -- the lease: a sender that claimed B and crashed 31 minutes ago leaves B owed again
  update public.reasoning_held_question set notice_last_at = now() - interval '31 minutes' where id = v_b;
  v4 := public.fn_reason_held_notice_due(100);
  select array_agg((e->>'id')::bigint) into v_ids4 from jsonb_array_elements(v4) e;
  select count(*) into v_real1 from public.reasoning_held_question where notice_delivered_at is null and escalated_at is not null;

  if v_ids1 = array[v_a] and v_ids2 = array[v_b]
     and not (coalesce(v_ids3, '{}') && array[v_a, v_b])
     and v_b = any(coalesce(v_ids4, '{}')) and not (v_a = any(coalesce(v_ids4, '{}')))
     and v_real1 = v_real0 + 2 then
    raise exception 'CHK<<PROBE OK first=% second=% third_has_neither=true lease_returns=% real_rows=%>>', v_ids1, v_ids2, v_b, v_real0;
  end if;
  raise exception 'CHK<<PROBE FAILED first=% second=% third=% after_lease=% real_before=% real_after=%>>', v_ids1, v_ids2, v_ids3, v_ids4, v_real0, v_real1;
end $probe$;
