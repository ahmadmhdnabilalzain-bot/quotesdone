-- PROBE for a_fixture_supplier_registration_files_no_task_handoff_or_notice.sql (13 Oct 2026, seat: customer_support).
-- A pure probe: it always raises CHK<<...>>, so every row it writes is rolled back. Never applied.
-- It queues a supplier_registered admin notice for (a) the newest fixture supplier and (b) the newest real supplier,
-- each with a unique subject, and counts the org_tasks the trigger files for each. Expect fixture 0, real 1.
-- It reads leads only; no lead row is written. Nothing reaches a person: the notices are rolled back with the rest.
do $$
declare
  v_fix bigint; v_real bigint; v_tok text := translate(md5(clock_timestamp()::text), '0123456789', 'ghijklmnop');
  v_fix_tasks int; v_real_tasks int; v_fix_notes int;
begin
  select l.id into v_fix from public.leads l
   where public.fn_seat_clock_lead_is_fixture(l) order by l.id desc limit 1;
  select l.id into v_real from public.leads l
   where not public.fn_seat_clock_lead_is_fixture(l)
     and not exists (select 1 from unnest(coalesce(l.tags, '{}'::text[])) t where t like 'qd\_run:%')
   order by l.id desc limit 1;
  if v_fix is null or v_real is null then raise exception 'CHK<<PROBE FAILED: no fixture (%) or real (%) lead to test>>', v_fix, v_real; end if;

  insert into public.notifications (type, to_email, to_role, lead_id, subject, body, channel, status)
  values ('supplier_registered', 'management@quotesdone.com', 'admin', v_fix,  'Probe fixture ' || v_tok, 'probe', 'email', 'queued'),
         ('supplier_registered', 'management@quotesdone.com', 'admin', v_real, 'Probe real '    || v_tok, 'probe', 'email', 'queued');

  select count(*) into v_fix_tasks  from public.org_tasks where title = 'Probe fixture ' || v_tok;
  select count(*) into v_real_tasks from public.org_tasks where title = 'Probe real '    || v_tok;
  select count(*) into v_fix_notes  from public.notifications where subject = 'Probe fixture ' || v_tok;

  if v_fix_tasks = 0 and v_fix_notes = 0 and v_real_tasks = 1 then
    raise exception 'CHK<<PROBE OK: fixture lead % -> 0 tasks, 0 notices; real lead % -> % task (rolled back)>>', v_fix, v_real, v_real_tasks;
  end if;
  raise exception 'CHK<<PROBE FAILED: fixture lead % -> % tasks, % notices; real lead % -> % tasks>>',
    v_fix, v_fix_tasks, v_fix_notes, v_real, v_real_tasks;
end $$;
