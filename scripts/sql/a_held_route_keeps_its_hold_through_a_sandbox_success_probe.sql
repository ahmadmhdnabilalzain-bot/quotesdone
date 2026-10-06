-- BEHAVIOURAL PROBE for a_held_route_keeps_its_hold_through_a_sandbox_success.sql. Never applied by the train: it ends in
-- raise exception, so its scratch rows roll back. Expect the error text 'PROBE OK: ...'.
do $probe$
declare
  v_hold timestamptz := now() + interval '100 years';
  v_a timestamptz; v_b timestamptz;
begin
  insert into public.llm_route_health (model_id, open_until, opened_reason)
  values ('zz-probe/held-route', v_hold, 'held with the rest of the fleet'),
         ('zz-probe/breaker-route', now() + interval '5 minutes', 'probe breaker');
  perform public.fn_record_llm_attempt(jsonb_build_object('model_route','zz-probe/held-route','ok',true,'fn','probe'));
  perform public.fn_record_llm_attempt(jsonb_build_object('model_route','zz-probe/breaker-route','ok',true,'fn','probe'));
  select open_until into v_a from public.llm_route_health where model_id = 'zz-probe/held-route';
  select open_until into v_b from public.llm_route_health where model_id = 'zz-probe/breaker-route';
  if v_a is distinct from v_hold then raise exception 'PROBE FAILED: a success lifted the hold (open_until=%)', v_a; end if;
  if v_b is not null then raise exception 'PROBE FAILED: a success left a real breaker open (open_until=%)', v_b; end if;
  raise exception 'PROBE OK: held route kept %, breaker closed', v_a;
end $probe$;
