-- every_calendar_entry_has_a_live_seat_that_plans_it_thirty_sixty_and_ninety_days_ahead_probe.sql (ceo, OPS_LOOPS, 16 Nov 2026)
-- A pure probe, run AFTER the file in the SAME transaction on a LOCAL Postgres 16 (scripts/db/local_pg16.mjs); it always
-- aborts (raise 'CHK<<...>>'), so nothing it writes survives. Its calendar rows are ZZ DEMO; the model's answers are stubs
-- handed to fn_reason_held_resolve; nothing is sent to anyone. Run twice on 16 Nov 2026: PROBE OK.
do $probe$
declare
  v_ev bigint; v_far bigint; v_owner_q bigint; v_q bigint; v_res jsonb; r jsonb; v_plan bigint; v_dir bigint; v_n int; v_ok boolean;
begin
  delete from public.reasoning_held_question where surface = 'ceo.calendar_owner';   -- the local cluster holds none; a clean start
  insert into public.company_calendar (event_name, kind, starts_on, recurrence, action, owner_dept, affects)
  values ('ZZ DEMO trade show', 'industry_event', current_date + 7, 'annual',
          'ZZ DEMO: recruit suppliers in the week before the show; no digital push during it.', 'Growth', 'suppliers') returning id into v_ev;
  insert into public.company_calendar (event_name, kind, starts_on, recurrence, action, owner_dept, affects)
  values ('ZZ DEMO far holiday', 'public_holiday', current_date + 75, 'annual', 'ZZ DEMO: freeze outbound that week.', 'Ops', 'everyone') returning id into v_far;
  insert into public.company_calendar_brief (calendar_id, seat, brief, set_by)
  values (v_ev, 'sales_engineer', 'ZZ DEMO brief: build the target list from the exhibitor directory; outreach only through the pipeline.', 'probe');
  update public.company_calendar set owner_seat = 'ceo', owner_set_by = 'probe' where owner_seat is null and id not in (v_ev, v_far);

  -- 1. first run: the CEO's model is asked who owns the two rows; until it answers, the CEO plans the near one (30-day
  --    horizon only, never 60 and 90 as well) and the far one at its 90-day horizon
  r := public.fn_ceo_calendar_horizon();
  select max(id) into v_owner_q from public.reasoning_held_question where surface = 'ceo.calendar_owner' and status = 'held' and subject->'calendar_ids' @> to_jsonb(v_ev);
  if v_owner_q is null then raise exception 'CHK<<PROBE FAILED: the owner question was not filed: %>>', r; end if;
  if (select request->'decision'->'fields' from public.reasoning_held_question where id = v_owner_q)::text not like '%row_' || v_ev || '%' then
    raise exception 'CHK<<PROBE FAILED: the owner question does not ask about the row>>'; end if;
  if (select count(*) from public.company_calendar_plan where calendar_id = v_ev) <> 1
     or not exists (select 1 from public.company_calendar_plan where calendar_id = v_ev and seat = 'ceo' and horizon_days = 30) then
    raise exception 'CHK<<PROBE FAILED: the unowned near entry is not the CEO''s at the 30-day horizon only>>'; end if;
  if not exists (select 1 from public.company_calendar_plan where calendar_id = v_far and seat = 'ceo' and horizon_days = 90) then
    raise exception 'CHK<<PROBE FAILED: the far entry was not given at its 90-day horizon>>'; end if;
  select directive_id, held_id into v_dir, v_q from public.company_calendar_plan where calendar_id = v_ev and seat = 'ceo';
  if v_dir is null or v_q is null then raise exception 'CHK<<PROBE FAILED: the plan has no order or no question>>'; end if;
  if (select seat from public.ceo_directive where id = v_dir) is distinct from 'ceo' then raise exception 'CHK<<PROBE FAILED: the order is not addressed to the seat>>'; end if;

  -- 2. the model names a department that does not exist: refused, asked again; then it names live seats
  v_res := public.fn_reason_apply_ceo__calendar_owner(v_owner_q, jsonb_build_object('status', 'answered', 'decision', jsonb_build_object('fields',
             jsonb_build_object('row_' || v_ev, jsonb_build_object('value', 'Growth; also: none; next: none')))));
  if (v_res->>'refused')::int < 1 or (select owner_seat from public.company_calendar where id = v_ev) is not null then
    raise exception 'CHK<<PROBE FAILED: a department was accepted as an owner: %>>', v_res; end if;
  if (select owner_held_id from public.company_calendar where id = v_ev) is not null then
    raise exception 'CHK<<PROBE FAILED: a refused row is not asked again>>'; end if;
  v_res := public.fn_reason_held_resolve(v_owner_q, jsonb_build_object('status', 'answered', 'model', 'stub', 'answer', 'owners',
             'decision', jsonb_build_object('fields', jsonb_build_object(
               'row_' || v_ev, jsonb_build_object('value', 'marketing; also: sales_engineer; next: none', 'evidence', 'stub'),
               'row_' || v_far, jsonb_build_object('value', 'customer_support; also: none; next: none', 'evidence', 'stub')))));
  if (select owner_seat from public.company_calendar where id = v_ev) is distinct from 'marketing'
     or (select also_seats from public.company_calendar where id = v_ev) is distinct from array['sales_engineer'] then
    raise exception 'CHK<<PROBE FAILED: the model''s owners were not recorded: %>>', v_res; end if;

  -- 3. the next run gives the entry to its owner and the other seat, each once, with the brief in the seat's question
  r := public.fn_ceo_calendar_horizon();
  if not exists (select 1 from public.company_calendar_plan where calendar_id = v_ev and seat = 'marketing' and horizon_days = 30)
     or not exists (select 1 from public.company_calendar_plan where calendar_id = v_ev and seat = 'sales_engineer' and horizon_days = 30) then
    raise exception 'CHK<<PROBE FAILED: the owner and the other seat were not given the entry: %>>', r; end if;
  select id, held_id into v_plan, v_q from public.company_calendar_plan where calendar_id = v_ev and seat = 'sales_engineer';
  if (select surface from public.reasoning_held_question where id = v_q) is distinct from 'sales_engineer.calendar_plan'
     or (select request->'context'->'case'->>'your_brief' from public.reasoning_held_question where id = v_q) not like 'ZZ DEMO brief%'
     or (select request->'context'->'case'->'facts'->>'rules' from public.reasoning_held_question where id = v_q) not like '%consent%' then
    raise exception 'CHK<<PROBE FAILED: the seat''s question lacks its surface, its brief or the consent rules>>'; end if;
  r := public.fn_ceo_calendar_horizon();
  select count(*) into v_n from public.company_calendar_plan where calendar_id = v_ev;
  if v_n <> 3 then raise exception 'CHK<<PROBE FAILED: a re-run filed again (% plans)>>', v_n; end if;

  -- 4. the seat's model answers: the plan is recorded and the order's own check now reads met
  v_res := public.fn_reason_held_resolve(v_q, jsonb_build_object('status', 'answered', 'model', 'stub',
             'answer', 'ZZ DEMO plan: list 40 exhibitors in our open gaps by Wednesday; invite through the pipeline Thursday.',
             'decision', jsonb_build_object('choice', 'plan')));
  if (v_res->>'status') is distinct from 'applied' or (select status from public.company_calendar_plan where id = v_plan) is distinct from 'planned' then
    raise exception 'CHK<<PROBE FAILED: the plan was not recorded: %>>', v_res; end if;
  select directive_id into v_dir from public.company_calendar_plan where id = v_plan;
  execute 'select coalesce((' || (select done_sql from public.ceo_directive where id = v_dir) || ')::boolean, false)' into v_ok;
  if not v_ok then raise exception 'CHK<<PROBE FAILED: the order does not read met once the plan is recorded>>'; end if;

  -- 5. an answer that is not plan / no_action is not recorded
  select held_id into v_q from public.company_calendar_plan where calendar_id = v_ev and seat = 'marketing';
  v_res := public.fn_calendar_plan_apply(v_q, jsonb_build_object('answer', 'x', 'decision', jsonb_build_object('choice', 'maybe')));
  if v_res is not null then raise exception 'CHK<<PROBE FAILED: an invented choice was recorded>>'; end if;

  raise exception 'CHK<<PROBE OK>>';
end $probe$;
