-- A SMOKE RUN THAT STOPPED EARLY CLOSES NOTHING
-- it_engineer, 28 Sep 2026 (end-to-end sweep, founder ledger 760).
--
-- MEASURED: post-deploy smoke run 36466336819 (merge f4a9453) ran journey a, then hit its 20-minute deadline;
-- journeys b (supplier portal) and c (comparison) were SKIPPED, and report_to_it_engineer.mjs sent
-- complete:false. fn_it_smoke_ingest never read that field: it called fn_it_duty_settle, which closes every open
-- duty:smoke finding the run did not re-raise, and answered closed:4 - including the three Arabic comparison
-- findings (duty:smoke:c comparison:*), which journey c never looked at. fn_it_journey_ingest has kept this rule
-- since the deadline was added; the smoke ingest now keeps the same one. Body = the live definition plus the branch.
-- prevented by: scripts/checks/a_truncated_smoke_run_closes_nothing.test.mjs

CREATE OR REPLACE FUNCTION public.fn_it_smoke_ingest(p_report jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_owner text; v_owners jsonb; x jsonb; v_items jsonb := '[]'::jsonb; v_res jsonb;
  -- Absent means complete, exactly as fn_it_journey_ingest reads it.
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
    v_res := public.fn_it_duty_settle('smoke', v_items);
  else
    -- Looked at part of it: raise what fails, close NOTHING (the rule fn_it_journey_ingest already keeps).
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
                                'note', 'the run stopped before it saw every journey, so nothing was closed on its silence');
  end if;
  perform public.fn_it_duty_ran('smoke', v_res || jsonb_build_object('sha', p_report->>'sha'));
  return v_res;
end $function$;
