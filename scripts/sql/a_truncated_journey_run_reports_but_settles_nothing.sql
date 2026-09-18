-- A truncated journey run reports, but settles nothing.
-- Seat: it_engineer. Found by independent review of the nightly-journey deadline fix, 17 Sep 2026.
--
-- THE HAZARD, read out of production rather than assumed. fn_it_journey_ingest ends with
--
--     v_res := public.fn_it_duty_settle('journey', v_items);
--
-- and fn_it_duty_settle closes EVERY open finding whose key is not in this run's failing set:
--
--     for v_open in select issue_key from public.it_engineer_finding
--                    where closed_at is null and issue_key like 'duty:' || p_duty || ':%'
--                      and not (issue_key = any (v_keys)) loop
--       perform public.fn_it_engineer_finding_close(v_open, 'the ' || p_duty || ' duty no longer finds it');
--
-- That is right for a run that looked at everything: a step that no longer fails is a step that is
-- fixed. It is WRONG for a run that stopped early. scripts/e2e/run.mjs now carries a wall-clock
-- deadline (so the nightly job can no longer be cancelled mid-crawl, which is what left
-- duty:journey_heartbeat:no_run open for three days), and a run that hits it records the steps it
-- did not reach as SKIP. A SKIP step is absent from v_items exactly as a PASS step is — so without
-- this change, the first truncated night would have closed the four open
-- duty:journey:f crawl:* findings and both duty:journey:d payment:* findings with the note "the
-- journey duty no longer finds it", having never looked at them.
--
-- "Could not look" would have read as "all clear". The duty engine's own header says the opposite
-- is the rule, and this is the routine that would have broken it.
--
-- THE CHANGE: the report now carries `complete` (scripts/e2e/report_to_it_engineer.mjs, from
-- run.json's own flag — false when the deadline cut the run short OR when --journey asked for only
-- part of the funnel). An incomplete run still raises every failure it DID see and still writes its
-- agent_runs heartbeat — the heartbeat is the whole point of the deadline — but it closes nothing.
--
-- WHY NOT A FLAG ON fn_it_duty_settle: every other duty (demo, backup_gap, renewal, usage_*, smoke,
-- sender) calls it with two arguments. Adding a third with a default would need the two-argument
-- form DROPped to avoid an ambiguous call, and a DROP + CREATE grants EXECUTE to PUBLIC again on a
-- routine that closes findings. The journey duty is the only one with a partial reading, so the
-- knowledge of what a partial reading means stays in the journey's own ingest.
--
-- CREATE OR REPLACE, same signature: the ACL is preserved, so there is no revoke here (a revoke
-- would be required if this DROPped and CREATEd). search_path stays pinned to 'public','pg_temp'.

create or replace function public.fn_it_journey_ingest(p_report jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_items jsonb := '[]'::jsonb; x jsonb; v_owner text; v_letter text; v_res jsonb;
  -- Absent means complete: reports written before the harness had a deadline could not be truncated.
  v_complete boolean := coalesce((p_report->>'complete')::boolean, true);
begin
  if jsonb_typeof(p_report->'steps') is distinct from 'array' or coalesce(btrim(p_report->>'tag'), '') = '' then
    raise exception 'fn_it_journey_ingest takes {tag, steps:[...]} from scripts/e2e/report_to_it_engineer.mjs';
  end if;
  for x in select e from jsonb_array_elements(p_report->'steps') e where e->>'status' = 'FAIL' loop
    v_letter := left(coalesce(x->>'journey', ''), 1);
    -- a/b/c/f drive the portals, the intake, the quotes and the comparison — the sales engineer's
    -- (function_owner: customer_portal, supplier_portal, inquiry_intake, quote_compare). d/e are the
    -- payment and the invoice — the accountant's (stripe_checkout, reveal_invoice). Fixtures, safety
    -- and cleanup are the harness itself, which the ceo owns.
    v_owner := case when v_letter in ('a', 'b', 'c', 'f') then 'sales_engineer'
                    when v_letter in ('d', 'e') then 'accountant' else 'ceo' end;
    v_items := v_items || jsonb_build_object(
      'item', coalesce(x->>'journey', '?') || ':' || left(regexp_replace(coalesce(x->>'name', '?'), '[^a-zA-Z0-9]+', '_', 'g'), 80),
      'owner_seat', v_owner, 'subject', 'journey ' || coalesce(x->>'journey', '?'),
      'title', 'Nightly journey failed: [' || coalesce(x->>'journey', '?') || '] ' || coalesce(x->>'name', '?'),
      'blast', 'customer_facing', 'affected', 0,
      'demo', coalesce((p_report->>'demo')::boolean, false),
      'evidence', jsonb_build_object('tag', p_report->>'tag', 'detail', left(x->>'detail', 600)));
  end loop;
  if v_complete then
    -- Looked at everything: raise what fails and close what no longer does.
    v_res := public.fn_it_duty_settle('journey', v_items);
  else
    -- Looked at part of it: raise what fails, close NOTHING. A step this run never reached says
    -- nothing about whether the defect it would have found is still there.
    for x in select e from jsonb_array_elements(v_items) e loop
      perform public.fn_it_engineer_finding_upsert(
        'duty:journey:' || (x->>'item'), x->>'title', 'IT engineer duty: journey',
        coalesce(x->>'blast', 'agent_facing'), coalesce((x->>'affected')::int, 1),
        coalesce(x->'evidence', '{}'::jsonb) || jsonb_build_object(
          'duty', 'journey', 'owner_seat', x->>'owner_seat', 'subject', x->>'subject',
          'demo', coalesce((x->>'demo')::boolean, false), 'run_complete', false),
        '{}'::text[], '{}'::text[], 'it_engineer.journey');
    end loop;
    v_res := jsonb_build_object('duty', 'journey', 'failing', jsonb_array_length(v_items),
                                'closed', 0, 'complete', false,
                                'note', 'the run stopped before it saw every journey, so nothing was closed on its silence');
  end if;
  -- THE HEARTBEAT, WRITTEN ON EVERY PATH. duty:journey_heartbeat:no_run reads this row; a run that
  -- was cut short has still reported, and must not be counted as a missing run.
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer',
          case when jsonb_array_length(v_items) = 0 and v_complete then 'ok' else 'warn' end, now(), now(),
          jsonb_build_object('job', 'journey', 'tag', p_report->>'tag', 'failed', jsonb_array_length(v_items),
                             'steps', jsonb_array_length(p_report->'steps'), 'leftovers', p_report->'leftovers',
                             'complete', v_complete),
          case when v_complete then null
               else 'the journey run stopped at its deadline before seeing every journey; failures were raised, nothing was closed' end);
  return v_res;
end $function$;

-- ── PROBE ────────────────────────────────────────────────────────────────────────────────────
-- This file defines a routine, so the probe must CLEAN UP AFTER ITSELF and end in `raise notice` —
-- a raise exception on the SUCCESS path would roll the function definition back with it while the
-- apply still reported success.
--
-- It proves the property by DOING it, and that is precisely why it cannot simply delete its rows
-- afterwards: calling fn_it_journey_ingest with a COMPLETE report — which step 2 must do, or it
-- would not prove settlement still works — makes fn_it_duty_settle close every open
-- duty:journey:% finding in the estate, six of which are real and unfixed. A DELETE cannot re-open
-- them.
--
-- So the whole experiment runs inside a nested block, which is a SUBTRANSACTION, and ends by
-- raising unconditionally. The raise is caught by that block's own handler, which discards every
-- row the experiment wrote or changed — the probe's finding, the two heartbeat rows, and the
-- settlement's closures — while the CREATE OR REPLACE above it, in the outer transaction, stands.
-- The verdict travels out in the message text. Nothing is left to clean up because nothing is left.
do $probe$
declare
  v_real_before int;
  v_real_after  int;
  v_verdict     text;
begin
  select count(*) into v_real_before from public.it_engineer_finding
   where closed_at is null and issue_key like 'duty:journey:%';

  begin
    declare
      v_probe_key text := 'duty:journey:zz_probe_' || replace(gen_random_uuid()::text, '-', '');
      v_open      boolean;
      v_res       jsonb;
      v_fail      text := null;
      v_pass_step jsonb := jsonb_build_array(
        jsonb_build_object('journey', 'a', 'name', 'probe step', 'status', 'PASS', 'detail', ''));
    begin
      -- An open journey finding that neither report below mentions.
      perform public.fn_it_engineer_finding_upsert(v_probe_key, 'PROBE: a journey step that is still broken',
        'IT engineer duty: journey', 'agent_facing', 0,
        jsonb_build_object('duty', 'journey', 'owner_seat', 'ceo', 'subject', 'probe', 'demo', true, 'probe', true),
        '{}'::text[], '{}'::text[], 'it_engineer.journey');

      -- 1. AN INCOMPLETE RUN MUST NOT CLOSE IT.
      v_res := public.fn_it_journey_ingest(jsonb_build_object(
        'tag', 'zzprobe', 'complete', false, 'steps', v_pass_step));
      select closed_at is null into v_open from public.it_engineer_finding where issue_key = v_probe_key;
      if not coalesce(v_open, false) then
        v_fail := format('an INCOMPLETE run closed a finding it never looked at (ingest returned %s)', v_res);
      elsif coalesce((v_res->>'closed')::int, -1) <> 0 then
        v_fail := format('an INCOMPLETE run reported closing %s finding(s); it must close none', v_res->>'closed');
      elsif not exists (select 1 from public.agent_runs
                         where agent = 'it_engineer' and counts->>'tag' = 'zzprobe' and counts->>'complete' = 'false') then
        v_fail := 'an INCOMPLETE run wrote no heartbeat row; the heartbeat is the whole reason the deadline exists';
      end if;

      -- 2. A COMPLETE RUN MUST STILL CLOSE IT — the gate must not disable settlement altogether.
      if v_fail is null then
        v_res := public.fn_it_journey_ingest(jsonb_build_object(
          'tag', 'zzprobe', 'complete', true, 'steps', v_pass_step));
        select closed_at is null into v_open from public.it_engineer_finding where issue_key = v_probe_key;
        if coalesce(v_open, true) then
          v_fail := 'a COMPLETE run left the stale finding open; settlement has been disabled, not gated';
        end if;
      end if;

      -- Unconditional: this is what discards everything above, verdict and all.
      raise exception 'QDPROBE:%', coalesce(v_fail, 'OK');
    end;
  exception when others then
    v_verdict := sqlerrm;
  end;

  -- Rolled back to here: the estate must be exactly as it was found.
  select count(*) into v_real_after from public.it_engineer_finding
   where closed_at is null and issue_key like 'duty:journey:%';

  if v_verdict is null or v_verdict not like 'QDPROBE:%' then
    raise exception 'CHK<<the probe did not run to its own verdict; it failed with: %>>', coalesce(v_verdict, '(no error)');
  end if;
  if v_verdict <> 'QDPROBE:OK' then
    raise exception 'CHK<<%>>', substring(v_verdict from 9);
  end if;
  if v_real_after <> v_real_before then
    raise exception 'CHK<<the probe changed the real journey findings: % open before, % after — the subtransaction did not roll back>>',
      v_real_before, v_real_after;
  end if;
  if exists (select 1 from public.agent_runs where counts->>'tag' = 'zzprobe')
     or exists (select 1 from public.it_engineer_finding where issue_key like 'duty:journey:zz_probe_%') then
    raise exception 'CHK<<the probe left rows behind>>';
  end if;

  raise notice 'PROBE OK — an incomplete run raised its failures, wrote its heartbeat and closed 0; a complete run still closed the stale finding; % real journey finding(s) open before and after, and the probe left nothing behind',
    v_real_before;
end
$probe$;
