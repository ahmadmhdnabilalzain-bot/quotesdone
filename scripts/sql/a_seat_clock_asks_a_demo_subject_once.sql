-- A SEAT CLOCK ASKS A DEMO SUBJECT ONCE (it_engineer, 19 Oct 2026).
--
-- Ruling 1199 (demo_activity_files_no_seat_task_or_handoff.sql) files no handoff for demo work, and #1497
-- (a_demo_delivery_request_is_captured_not_refused.sql) writes a demo delivery straight to notifications as
-- 'suppressed'. fn_seat_clock_asked only looked for the delivery.request handoff, which a demo message no
-- longer has, so every tick re-queued the same demo message. Measured in a rolled-back replay of #1497 with
-- the seat-clock probe: "a second sweep wrote 3 more message(s) about the same request; the customer was not
-- told exactly once; the 7-day outcome check was not asked exactly once".
--
-- The clock now also counts a notification already written under the same dedupe key. That needs #1497's
-- suppressed insert to carry dedupe_key (it must list the column); apply #1497 first.
-- Prevented by: scripts/checks/every_duty_has_an_owner_and_a_clock.test.mjs (the rehearsal ticks twice).
create or replace function public.fn_seat_clock_asked(p_dedupe_key text)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $function$
  select exists (select 1 from public.agent_actions a
                  where a.kind = 'handoff' and a.agent = 'customer_support'
                    and a.target_id = 'delivery.request:' || p_dedupe_key and a.status <> 'failed')
      or exists (select 1 from public.notifications n where n.dedupe_key = p_dedupe_key)
$function$;
revoke execute on function public.fn_seat_clock_asked(text) from public, anon, authenticated;
