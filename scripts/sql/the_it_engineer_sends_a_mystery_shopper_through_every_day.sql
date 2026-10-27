-- THE IT ENGINEER SENDS A MYSTERY SHOPPER THROUGH EVERY DAY (founder ruling 1209, 13 Oct 2026).
-- Assigned: it_engineer. No model is called here; the run's comparison step uses the real model (ruling 1260).
--
-- Once a day .github/workflows/mystery-shopper.yml runs scripts/e2e/mystery_shopper.mjs: one ZZ DEMO customer on
-- @example.invalid signs up, makes a request, is matched to ZZ DEMO suppliers only, gets two quotes and the
-- comparison report written by the model, and the run tears itself down and counts 0 leftovers. It reuses the stage-2
-- harness pieces (demo_factory makeCustomer/makeSupplier/makeInquiry/makeQuote, fixtures openRun/closeRun/leftovers,
-- the demo-guard preflight) and the duty ledger (fn_it_duty_settle) rather than building a second of either.
--
-- This file is the database half:
--   fn_it_engineer_mystery_shopper_ingest(report)  every FAIL step becomes the finding duty:mystery_shopper:<step>, its
--       title naming the step and the error; a PASS closes that step's finding; a SKIP (not reached because an earlier
--       step broke) is CARRIED, so its open finding is held as it stands, never closed on silence. Writes the heartbeat.
--   fn_it_engineer_mystery_shopper_heartbeat()     the duty it_engineer.mystery_shopper_heartbeat: no run reported in 26
--       hours is itself a finding (a workflow that stopped running is not a quiet shop).
--
-- prevented by: scripts/checks/the_it_engineer_sends_a_mystery_shopper_through_every_day.test.mjs
-- probe: scripts/sql/the_it_engineer_sends_a_mystery_shopper_through_every_day_probe.sql (aborted transaction)

create or replace function public.fn_it_engineer_mystery_shopper_ingest(p_report jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare x jsonb; v_items jsonb := '[]'::jsonb; v_res jsonb; v_failed int := 0;
  -- the step's owner: the funnel is the sales engineer's, the comparison report too; the harness itself is IT's
  v_owner constant jsonb := jsonb_build_object('preflight', 'it_engineer', 'signup', 'customer_support', 'suppliers', 'sales_engineer',
    'intake', 'sales_engineer', 'matching', 'sales_engineer', 'quote', 'sales_engineer', 'comparison', 'sales_engineer', 'cleanup', 'it_engineer');
begin
  if jsonb_typeof(p_report->'steps') is distinct from 'array' or coalesce(btrim(p_report->>'tag'), '') = '' then
    raise exception 'fn_it_engineer_mystery_shopper_ingest takes {tag, steps:[{step, status, error}]} from scripts/e2e/mystery_shopper.mjs';
  end if;
  for x in select e from jsonb_array_elements(p_report->'steps') e loop
    continue when x->>'status' not in ('FAIL', 'SKIP') or not (v_owner ? (x->>'step'));
    if x->>'status' = 'FAIL' then v_failed := v_failed + 1; end if;
    v_items := v_items || jsonb_build_object(
      'item', x->>'step', 'carried', x->>'status' = 'SKIP',
      'owner_seat', v_owner->>(x->>'step'), 'subject', 'mystery shopper ' || (x->>'step'),
      'title', left('Mystery shopper: step ' || (x->>'step') || ' broke: ' || coalesce(nullif(btrim(x->>'error'), ''), 'no error text'), 300),
      'blast', 'customer_facing', 'affected', 0, 'demo', true,
      'evidence', jsonb_build_object('tag', p_report->>'tag', 'step', x->>'step', 'error', left(x->>'error', 600)));
  end loop;
  -- a SKIP is carried: held if open, never raised on its own (fn_it_duty_settle raises a carried item that has no open
  -- finding, so a skip with nothing open is left out rather than filed as a break it did not observe)
  select coalesce(jsonb_agg(e), '[]'::jsonb) into v_items from jsonb_array_elements(v_items) e
   where not (e->>'carried')::boolean
      or exists (select 1 from public.it_engineer_finding f where f.issue_key = 'duty:mystery_shopper:' || (e->>'item') and f.closed_at is null);
  v_res := public.fn_it_duty_settle('mystery_shopper', v_items);
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', case when v_failed = 0 then 'ok' else 'warn' end, now(), now(),
          jsonb_build_object('job', 'mystery_shopper', 'tag', p_report->>'tag', 'failed', v_failed,
                             'steps', jsonb_array_length(p_report->'steps')), null);
  return v_res || jsonb_build_object('failed_steps', v_failed);
end $fn$;
revoke execute on function public.fn_it_engineer_mystery_shopper_ingest(jsonb) from public, anon, authenticated;

create or replace function public.fn_it_engineer_mystery_shopper_heartbeat()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_last timestamptz; v_since timestamptz;
begin
  select max(finished_at) into v_last from public.agent_runs
   where agent = 'it_engineer' and counts->>'job' = 'mystery_shopper';
  -- before the first run the clock starts when the duty was installed, so a fresh install is not a finding
  v_since := coalesce(v_last, (select created_at from public.seat_duty where duty = 'it_engineer.mystery_shopper_heartbeat'), now());
  return jsonb_build_object('last_run', v_last, 'settled', public.fn_it_duty_settle('mystery_shopper_heartbeat',
    case when v_since < now() - interval '26 hours' then jsonb_build_array(jsonb_build_object(
      'item', 'no_run', 'owner_seat', 'it_engineer', 'subject', '.github/workflows/mystery-shopper.yml',
      'title', 'The daily mystery shopper has not reported since ' || coalesce(to_char(v_last at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' (Dubai)', 'it was installed'),
      'blast', 'agent_facing', 'affected', 1, 'evidence', jsonb_build_object('last_run', v_last)))
    else '[]'::jsonb end));
end $fn$;
revoke execute on function public.fn_it_engineer_mystery_shopper_heartbeat() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('it_engineer.mystery_shopper_heartbeat', 'it_engineer', interval '1 hour', 'fn_it_engineer_mystery_shopper_heartbeat',
   'The daily ZZ DEMO mystery shopper (sign-up, intake, matching, quote, comparison, cleanup to 0) reported within 26 hours; a silent workflow is a finding. Ruling 1209.',
   'scripts/sql/the_it_engineer_sends_a_mystery_shopper_through_every_day.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- verdict (reads only: this file defines routines, so it must not raise)
select case when exists (select 1 from public.seat_duty where duty = 'it_engineer.mystery_shopper_heartbeat')
             and not has_function_privilege('anon', 'public.fn_it_engineer_mystery_shopper_ingest(jsonb)', 'execute')
            then 'PROBE OK: ingest closed to anon, heartbeat duty scheduled'
            else 'PROBE FAILED: the heartbeat duty is missing or the ingest is open' end as verdict;
