-- A JOURNEY OR SMOKE RUN SETTLES ONLY THE JOURNEYS IT RAN TO THEIR END.
--
-- Seat: it_engineer. 19 Oct 2026. Coordinator's ruling on the journey/smoke investigation (completeness).
--
-- MEASURED, 19 Oct 2026: ~40 duty:journey:% and duty:smoke:% findings sat open and escalated to the CEO.
-- scripts/e2e/run.mjs called a run COMPLETE only when it ran every journey in ORDER, so a post-deploy smoke
-- that asked for a subset (--journey) was always INCOMPLETE and closed nothing; and a COMPLETE run closed
-- every open key of the duty, including keys of a journey that crashed before reaching them.
--
-- NOW: run.mjs calls a run complete when every journey it ASKED FOR was attempted (scripts/e2e/run_scope.mjs)
-- and writes `journeys` = the journeys that finished. Both ingests below, on a complete run, hand every
-- open key whose journey letter (a..h, the key's first token: 'a customer', 'f-drawings/...') is NOT in
-- `journeys` to fn_it_duty_settle as a CARRIED item, which that routine holds exactly as it stands. Keys
-- with no journey letter ('fixtures', 'run', 'safety') are the harness itself and are settled by any
-- complete run, as before. A report without `journeys` (an older run.json) settles everything, as before.
--
-- Prevented by: scripts/checks/a_journey_run_settles_only_the_journeys_it_ran.test.mjs, and the verdict
-- probe at the end of this file.
--
--   node scripts/apply_sql.mjs scripts/sql/a_journey_run_settles_only_the_journeys_it_ran.sql --apply --ddl

-- The carried items for one duty: every open key of that duty whose journey letter this run did not finish.
create or replace function public.fn_it_journey_scope_carried(p_duty text, p_report jsonb)
returns jsonb
language sql stable
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', substring(f.issue_key from length('duty:' || p_duty || ':') + 1),
           'title', f.title, 'carried', true)), '[]'::jsonb)
    from public.it_engineer_finding f
   where jsonb_typeof(p_report->'journeys') = 'array'
     and f.closed_at is null
     and f.issue_key like 'duty:' || p_duty || ':%'
     and substring(f.issue_key from '^duty:' || p_duty || ':([a-h])[ -]') is not null
     and not exists (select 1 from jsonb_array_elements_text(p_report->'journeys') j
                      where j = substring(f.issue_key from '^duty:' || p_duty || ':([a-h])[ -]'))
$fn$;
revoke execute on function public.fn_it_journey_scope_carried(text, jsonb) from public, anon, authenticated;

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
    -- Raise what fails, close what no longer does, and carry the journeys this run did not finish.
    v_res := public.fn_it_duty_settle('journey', v_items || public.fn_it_journey_scope_carried('journey', p_report));
  else
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
                                'note', 'the run stopped before it attempted every journey it asked for, so nothing was closed on its silence');
  end if;
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer',
          case when jsonb_array_length(v_items) = 0 and v_complete then 'ok' else 'warn' end, now(), now(),
          jsonb_build_object('job', 'journey', 'tag', p_report->>'tag', 'failed', jsonb_array_length(v_items),
                             'steps', jsonb_array_length(p_report->'steps'), 'leftovers', p_report->'leftovers',
                             'complete', v_complete, 'journeys', p_report->'journeys'),
          case when v_complete then null
               else 'the journey run stopped before attempting every journey it asked for; failures were raised, nothing was closed' end);
  return v_res;
end $function$;

create or replace function public.fn_it_smoke_ingest(p_report jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_owner text; v_owners jsonb; x jsonb; v_items jsonb := '[]'::jsonb; v_res jsonb;
  v_complete boolean := coalesce((p_report->>'complete')::boolean, true);
begin
  if jsonb_typeof(p_report->'steps') is distinct from 'array' or coalesce(btrim(p_report->>'sha'), '') = '' then
    raise exception 'fn_it_smoke_ingest takes {sha, changed_files, steps} from scripts/e2e/report_to_it_engineer.mjs --smoke';
  end if;
  with files as (
    select f from jsonb_array_elements_text(coalesce(p_report->'changed_files', '[]'::jsonb)) f),
  owned as (
    select case when o.owner in (select t.to_seat from public.fn_seat_handoff_types() t where t.type = 'it.finding')
                then o.owner else 'ceo' end seat
      from files
      left join public.function_owner o on o.function_slug = substring(files.f from '^supabase/functions/([^/_][^/]*)/'))
  select coalesce(jsonb_object_agg(seat, n), '{}'::jsonb) into v_owners
    from (select seat, count(*) n from owned group by seat) z;
  select key into v_owner from jsonb_each_text(v_owners) order by value::int desc, key limit 1;
  for x in select e from jsonb_array_elements(p_report->'steps') e where e->>'status' = 'FAIL' loop
    v_items := v_items || jsonb_build_object(
      'item', coalesce(x->>'journey', '?') || ':' || left(regexp_replace(coalesce(x->>'name', '?'), '[^a-zA-Z0-9]+', '_', 'g'), 80),
      'owner_seat', coalesce(v_owner, 'ceo'), 'subject', 'merge ' || left(p_report->>'sha', 7),
      'title', 'After merge ' || left(p_report->>'sha', 7) || ', the smoke test failed: [' || coalesce(x->>'journey', '?') || '] ' || coalesce(x->>'name', '?'),
      'blast', 'customer_facing', 'affected', 0, 'demo', coalesce((p_report->>'demo')::boolean, false),
      'evidence', jsonb_build_object('sha', p_report->>'sha', 'owners', v_owners, 'changed_files', p_report->'changed_files',
                                     'tag', p_report->>'tag', 'detail', left(x->>'detail', 600)));
  end loop;
  if v_complete then
    v_res := public.fn_it_duty_settle('smoke', v_items || public.fn_it_journey_scope_carried('smoke', p_report));
  else
    for x in select e from jsonb_array_elements(v_items) e loop
      perform public.fn_it_engineer_finding_upsert(
        'duty:smoke:' || (x->>'item'), x->>'title', 'IT engineer duty: smoke',
        coalesce(x->>'blast', 'customer_facing'), coalesce((x->>'affected')::int, 0),
        coalesce(x->'evidence', '{}'::jsonb) || jsonb_build_object(
          'duty', 'smoke', 'owner_seat', x->>'owner_seat', 'subject', x->>'subject',
          'demo', coalesce((x->>'demo')::boolean, false), 'run_complete', false),
        '{}'::text[], '{}'::text[], 'it_engineer.smoke');
    end loop;
    v_res := jsonb_build_object('duty', 'smoke', 'failing', jsonb_array_length(v_items), 'closed', 0, 'complete', false,
                                'note', 'the run stopped before it attempted every journey it asked for, so nothing was closed on its silence');
  end if;
  perform public.fn_it_duty_ran('smoke', v_res || jsonb_build_object('sha', p_report->>'sha'));
  return v_res;
end $function$;

-- ── PROBE ─────────────────────────────────────────────────────────────────────────────────────────
-- Runs the routine. The experiment is a subtransaction ended by an unconditional raise, so its finding,
-- heartbeat rows and any settlement are discarded while the definitions above stand (a complete run
-- would otherwise close the real open journey findings). The verdict comes out as one row.
create temp table _qd_verdict (verdict text) on commit drop;
do $probe$
declare v_before int; v_after int; v_msg text;
begin
  select count(*) into v_before from public.it_engineer_finding where closed_at is null and issue_key like 'duty:journey:%';
  begin
    declare
      k_b text := 'duty:journey:b zzprobe:' || replace(gen_random_uuid()::text, '-', '');
      k_a text := 'duty:journey:a zzprobe:' || replace(gen_random_uuid()::text, '-', '');
      v_fail text; v_open_b boolean; v_open_a boolean;
      pass jsonb := jsonb_build_array(jsonb_build_object('journey', 'a zzprobe', 'name', 'probe step', 'status', 'PASS', 'detail', ''));
    begin
      perform public.fn_it_engineer_finding_upsert(k_a, 'PROBE a', 'IT engineer duty: journey', 'agent_facing', 0,
        jsonb_build_object('duty', 'journey', 'probe', true, 'demo', true), '{}'::text[], '{}'::text[], 'it_engineer.journey');
      perform public.fn_it_engineer_finding_upsert(k_b, 'PROBE b', 'IT engineer duty: journey', 'agent_facing', 0,
        jsonb_build_object('duty', 'journey', 'probe', true, 'demo', true), '{}'::text[], '{}'::text[], 'it_engineer.journey');
      -- A complete run of journey a only: closes a's stale key, carries b's.
      perform public.fn_it_journey_ingest(jsonb_build_object('tag', 'zzprobe', 'complete', true,
        'journeys', jsonb_build_array('a'), 'steps', pass));
      select closed_at is null into v_open_a from public.it_engineer_finding where issue_key = k_a;
      select closed_at is null into v_open_b from public.it_engineer_finding where issue_key = k_b;
      if v_open_a then v_fail := 'a complete run of journey a left a stale a-key open';
      elsif not v_open_b then v_fail := 'a run of journey a closed a key of journey b it never ran';
      end if;
      -- A report without journeys (older run.json) still settles everything.
      if v_fail is null then
        perform public.fn_it_journey_ingest(jsonb_build_object('tag', 'zzprobe', 'complete', true, 'steps', pass));
        select closed_at is null into v_open_b from public.it_engineer_finding where issue_key = k_b;
        if v_open_b then v_fail := 'a full run (no journeys field) left a stale key open'; end if;
      end if;
      raise exception 'QDPROBE:%', coalesce(v_fail, 'OK');
    end;
  exception when others then v_msg := sqlerrm;
  end;
  select count(*) into v_after from public.it_engineer_finding where closed_at is null and issue_key like 'duty:journey:%';
  insert into _qd_verdict values (case
    when v_msg = 'QDPROBE:OK' and v_after = v_before then 'PROBE OK'
    else 'PROBE FAILED: ' || coalesce(v_msg, '(no verdict)') || format(' (open journey keys %s before, %s after)', v_before, v_after) end);
end
$probe$;
select verdict from _qd_verdict;
