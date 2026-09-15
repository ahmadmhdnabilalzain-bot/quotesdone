-- PROBE — the demo guard holds on insert AND on re-queue, and the release lets only real rows go.
-- Owner: customer_support. Run AFTER the_demo_guard_holds_a_row_moved_back_to_the_queue_and_its_release_exists.sql
-- is applied:
--     node scripts/qsql.mjs scripts/checks/the_demo_guard_holds_and_releases.probe.sql
--
-- PURE PROBE, NO DDL: it ends in raise exception, so the whole transaction rolls back and nothing it
-- wrote survives. That includes the switch flip, which no other session can see while uncommitted.
-- It is incapable of reaching a person as well as careful to clean up. Its one recipient is on
-- the RFC 2606 .invalid top-level domain, which can never be delivered. It is deliberately NOT
-- @example.invalid, because the guard lets that through, and the point is to be held.
do $$
declare
  v_addr constant text := 'zz-demo-guard-probe@guard-probe.invalid';
  v_id bigint; s1 text; s2 text; s3 text; v_refused boolean := false; r jsonb;
begin
  update public.decision_policy set value = 'true'::jsonb where key = 'demo_rehearsal_active';

  insert into public.notifications (type, kind, to_email, to_role, channel, subject, body, status, requested_by, sender)
  values ('probe', 'probe', v_addr, 'admin', 'email', 'ZZ DEMO guard probe', 'ZZ DEMO guard probe', 'queued', 'customer_support', 'customer_support')
  returning id, status into v_id, s1;

  update public.notifications set status = 'queued' where id = v_id;          -- the path the guard used to miss
  select status into s2 from public.notifications where id = v_id;

  begin perform public.fn_notifications_release_held(); exception when others then v_refused := true; end;

  update public.decision_policy set value = 'false'::jsonb where key = 'demo_rehearsal_active';
  r := public.fn_notifications_release_held();
  select status into s3 from public.notifications where id = v_id;

  raise exception 'CHK<<insert=% requeue=% refused_while_on=% after_release=% release=% PASS=%>>',
    s1, s2, v_refused, s3, r,
    (s1 = 'held' and s2 = 'held' and v_refused and s3 in ('queued', 'suppressed')
     and (not public.fn_is_demo_email(v_addr) or s3 = 'suppressed'));
end $$;
