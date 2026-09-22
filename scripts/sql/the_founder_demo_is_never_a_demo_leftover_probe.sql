-- PROBE: THE FOUNDER'S STANDING DEMO IS NEVER A DEMO LEFTOVER, AND A REAL LEFTOVER NAMES ITS ROWS.
--
-- Assigned: customer_support, with it_engineer's duty. 22 Sep 2026. Pure probe: no DDL, nothing survives
-- it. Run AFTER the_founder_demo_is_never_a_demo_leftover.sql, as ONE query through the Management API;
-- it is never applied.
--
-- WHAT IT RUNS, inside a block that always raises so every write is rolled back:
--   every open rehearsal window is marked ended (so the duty cannot be excused by a run in progress);
--   one ordinary ZZ DEMO customer, qd-zzprobe-cust@example.invalid, is planted with created_at 7 h ago;
--   fn_it_duties('{}') runs once and the open duty:demo:customers / duty:demo:leads findings are read.
-- VERDICT: PROBE OK only if
--   1. duty:demo:customers is open and its evidence ids contain the planted id and NO qd-founderdemo id;
--   2. duty:demo:leads is closed (the only lead older than six hours is the founder's lead 126512);
--   3. the founder's rows (qd-founderdemo-*; 2 customers + 1 lead on 22 Sep) number the same before and after.
-- It touches no founder row: it only counts them. Nothing is sent: the planted row is on the reserved
-- domain and the demo capture trigger holds any notification it could cause, and all of it rolls back.
create temp table zz_probe_verdict (verdict text, detail text) on commit drop;
do $probe$
declare
  v_id uuid; v_fd_before int; v_fd_after int; v_cust jsonb; v_leads_open boolean; v_fd_ids int; v_listed boolean; v_err text;
begin
  select (select count(*) from public.customers where email like 'qd-founderdemo-%')
       + (select count(*) from public.leads where email like 'qd-founderdemo-%') into v_fd_before;
  begin
    update public.rehearsal_window set ended_at = now() where ended_at is null;
    -- is_demo is derived from the reserved address (a non-default value is refused), so the address makes it demo.
    insert into public.customers (email, created_at)
    values ('qd-zzprobe-cust@example.invalid', now() - interval '7 hours') returning id into v_id;

    perform public.fn_it_duties('{}'::jsonb);

    select evidence into v_cust from public.it_engineer_finding
     where issue_key = 'duty:demo:customers' and closed_at is null;
    select exists (select 1 from public.it_engineer_finding where issue_key = 'duty:demo:leads' and closed_at is null)
      into v_leads_open;
    select count(*) into v_fd_ids from jsonb_array_elements_text(coalesce(v_cust->'ids', '[]'::jsonb)) i
     join public.customers c on c.id::text = i where c.email like 'qd-founderdemo-%';
    select (select count(*) from public.customers where email like 'qd-founderdemo-%')
         + (select count(*) from public.leads where email like 'qd-founderdemo-%') into v_fd_after;

    v_listed := coalesce(v_cust->'ids' ? v_id::text, false);
    raise exception 'ZZPROBE rollback';          -- plpgsql variables survive the rollback; the rows do not
  exception when others then
    v_err := sqlerrm;
  end;
  insert into zz_probe_verdict
  select case when v_err = 'ZZPROBE rollback' and v_listed and v_fd_ids = 0 and not v_leads_open
                   and v_fd_before > 0 and v_fd_after = v_fd_before
              then 'PROBE OK' else 'PROBE FAILED' end,
         format('planted id listed=%s (want true), founder ids listed=%s (want 0), leads finding open=%s (want false), '
                || 'founder rows before=%s after=%s (want equal, >0), block ended with: %s',
                v_listed, v_fd_ids, v_leads_open, v_fd_before, v_fd_after, v_err);
end $probe$;
select * from zz_probe_verdict;
