-- THE BOQ PIPELINE HAD NO WAY TO BE WRONG.
--
-- drawing_boq is a full UAE quantity-surveyor vision pipeline, wired into five functions and proven
-- by a successful call on 29 Jul. Nothing has ever checked whether what it produces is CORRECT.
-- KPI 103 (boq_analyst, "BOQ lines extracted correctly", target 95%) says "extraction accuracy
-- against the fixture set" and there was no fixture set, so the employee carried a target nobody
-- could score - and a capability the founder has explicitly protected from rebuilding could degrade
-- silently.
--
-- THE GROUND TRUTH IS ARITHMETIC, NOT MY OPINION. Each drawing states its own schedule in its own
-- title block and legend, so the fixture asks "did the pipeline extract what the drawing SAYS",
-- which needs no quantity-surveying judgement from me:
--
--   documents 10  villa_floorplan.png
--     LIVING/DINING 5.0x4.5=22.5 · BEDROOM1 4.0x3.5=14 · KITCHEN 3.5x3.0=10.5
--     BEDROOM2 4.0x3.0=12 · BATHROOM 2.5x2.0=5      -> 64.0 sqm of rooms
--     "Total plot built-up area: 78 sqm"             -> 78 sqm stated
--     "DOOR SCHEDULE: D1 x5"                         -> 5 doors
--     "WINDOW SCHEDULE: W1 x4"                       -> 4 windows
--   documents 4   floorplan.jpg
--     LIVING/DINING 5.0x6.0=30 · BEDROOM 3x3=9 · BATH 3x3=9   -> 48.0 sqm of rooms
--     no door or window schedule is printed on it    -> those expectations are NULL, not zero
--
-- A NULL EXPECTATION IS NOT SCORED. Drawing 4 prints no door schedule, so "how many doors did it
-- find" is not a question that drawing can answer and counting it as a miss would punish the
-- pipeline for the drawing's silence. Only non-null expectations enter the denominator.
--
-- BOTH FILES WERE VERIFIED PRESENT in storage.objects before this was written, not assumed.

create table if not exists public.boq_fixture (
  id               bigserial primary key,
  document_id      bigint not null references public.documents(id) on delete cascade,
  label            text   not null,
  -- Every expectation below is transcribed from text the drawing itself prints. NULL means the
  -- drawing does not state it, and NULL is excluded from scoring.
  expect_doors     int,
  expect_windows   int,
  expect_rooms_sqm numeric,
  expect_total_sqm numeric,
  tolerance_pct    numeric not null default 10,
  source_note      text   not null,
  active           boolean not null default true,
  created_at       timestamptz not null default now(),
  unique (document_id)
);

create table if not exists public.boq_fixture_run (
  id          bigserial primary key,
  fixture_id  bigint not null references public.boq_fixture(id) on delete cascade,
  ran_at      timestamptz not null default now(),
  ok          boolean not null,
  checked     int     not null default 0,   -- non-null expectations actually scored
  matched     int     not null default 0,
  score_pct   numeric,
  actual      jsonb,
  detail      jsonb,
  error       text
);
create index if not exists boq_fixture_run_recent_idx on public.boq_fixture_run (fixture_id, ran_at desc);

alter table public.boq_fixture     enable row level security;
alter table public.boq_fixture_run enable row level security;
-- No policy: service_role bypasses RLS and nothing else has any business reading a fixture answer
-- key. A visible expected-answer set is a way to grade a model on answers it can see.

insert into public.boq_fixture (document_id, label, expect_doors, expect_windows,
                                expect_rooms_sqm, expect_total_sqm, source_note)
select 10, 'Residential villa ground floor, full schedule', 5, 4, 64.0, 78.0,
       'Transcribed from the drawing''s own printed text: room dimensions 5.0x4.5, 4.0x3.5, '
       || '3.5x3.0, 4.0x3.0, 2.5x2.0 (sum 64.0 sqm); "Total plot built-up area: 78 sqm"; '
       || '"DOOR SCHEDULE: D1 x5"; "WINDOW SCHEDULE: W1 x4".'
where exists (select 1 from public.documents where id = 10 and kind = 'drawing')
on conflict (document_id) do nothing;

insert into public.boq_fixture (document_id, label, expect_doors, expect_windows,
                                expect_rooms_sqm, expect_total_sqm, source_note)
select 4, 'Proposed fit-out ground floor plan, areas only', null, null, 48.0, null,
       'Transcribed from the drawing''s own printed text: LIVING/DINING 5.0x6.0=30 sqm, '
       || 'BEDROOM 3x3=9 sqm, BATH 3x3=9 sqm (sum 48.0 sqm). This drawing prints NO door or '
       || 'window schedule, so those expectations are NULL and are not scored.'
where exists (select 1 from public.documents where id = 4 and kind = 'drawing')
on conflict (document_id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- THE SCORER. Called by the runner with the pipeline's raw output; it does the comparison in SQL so
-- the grading rule is one auditable place rather than a rule buried in an edge function.
--
-- Doors and windows are matched by scanning the BOQ lines for a door/window item and comparing its
-- quantity EXACTLY - a door schedule is a count, and "about five doors" is not a take-off. Areas
-- are matched within tolerance_pct because the pipeline computes them from a scale bar.
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_boq_fixture_score(p_fixture_id bigint, p_actual jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare f public.boq_fixture%rowtype; d jsonb := '[]'::jsonb;
  v_checked int := 0; v_matched int := 0;
  v_doors numeric; v_windows numeric; v_total numeric;
begin
  select * into f from public.boq_fixture where id = p_fixture_id;
  if not found then return jsonb_build_object('error','no such fixture'); end if;

  -- Largest matching line wins: a plan can list "D1 flush wooden doors" and a separate
  -- "door frames" line, and the schedule quantity is the one being checked.
  select max((l->>'qty')::numeric) into v_doors
    from jsonb_array_elements(coalesce(p_actual->'boq','[]'::jsonb)) l
   where (l->>'description') ~* '\ydoor' and (l->>'qty') ~ '^[0-9.]+$'
     and coalesce(l->>'unit','') ~* 'no|ea|pc';
  select max((l->>'qty')::numeric) into v_windows
    from jsonb_array_elements(coalesce(p_actual->'boq','[]'::jsonb)) l
   where (l->>'description') ~* '\ywindow' and (l->>'qty') ~ '^[0-9.]+$'
     and coalesce(l->>'unit','') ~* 'no|ea|pc';
  v_total := nullif(p_actual->>'total_area_sqm','')::numeric;

  if f.expect_doors is not null then
    v_checked := v_checked + 1;
    if v_doors = f.expect_doors then v_matched := v_matched + 1; end if;
    d := d || jsonb_build_array(jsonb_build_object('field','doors','expected',f.expect_doors,
           'actual',v_doors,'match', v_doors = f.expect_doors));
  end if;

  if f.expect_windows is not null then
    v_checked := v_checked + 1;
    if v_windows = f.expect_windows then v_matched := v_matched + 1; end if;
    d := d || jsonb_build_array(jsonb_build_object('field','windows','expected',f.expect_windows,
           'actual',v_windows,'match', v_windows = f.expect_windows));
  end if;

  -- The stated built-up area is preferred; where the drawing prints none, the room sum is the
  -- only figure it states and is what the pipeline's total is compared against.
  if coalesce(f.expect_total_sqm, f.expect_rooms_sqm) is not null then
    declare v_exp numeric := coalesce(f.expect_total_sqm, f.expect_rooms_sqm); v_hit boolean;
    begin
      v_hit := v_total is not null
               and abs(v_total - v_exp) <= v_exp * (f.tolerance_pct / 100.0);
      v_checked := v_checked + 1;
      if v_hit then v_matched := v_matched + 1; end if;
      d := d || jsonb_build_array(jsonb_build_object('field','total_area_sqm','expected',v_exp,
             'actual',v_total,'tolerance_pct',f.tolerance_pct,'match',v_hit));
    end;
  end if;

  return jsonb_build_object('checked', v_checked, 'matched', v_matched,
    'score_pct', case when v_checked > 0 then round(100.0*v_matched/v_checked, 2) else null end,
    'detail', d, 'boq_lines', jsonb_array_length(coalesce(p_actual->'boq','[]'::jsonb)));
end
$function$;
REVOKE ALL ON FUNCTION public.fn_boq_fixture_score(bigint, jsonb) FROM PUBLIC;

-- ---------------------------------------------------------------------------------------------
-- KPI 103 CAN NOW BE SCORED. It reads the newest run per fixture, so a re-run replaces rather than
-- dilutes, and it averages the per-fixture score. NULL until the runner has produced something -
-- deliberately, because a fixture set with no run is not 0% accuracy, it is no measurement.
-- ---------------------------------------------------------------------------------------------
update public.employee_kpi
   set measure_sql = $q$select round(avg(r.score_pct),2) from (select distinct on (fixture_id) fixture_id, score_pct, ok from public.boq_fixture_run order by fixture_id, ran_at desc) r where r.ok$q$,
       no_measure_reason = null
 where id = 103;
