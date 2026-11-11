-- PROBE for the_ceo_measures_every_seat_against_its_senior_standard_every_week.sql (ceo, 27 Oct 2026). A pure probe: it
-- always raises CHK<<...>>, so every row it writes is rolled back. It reads production as it is and asserts:
--   a. one verdict per active seat for this week, each with both stages and a level;
--   b. no seat is called senior while its exam is under 95 %, or mid without a judged exam (no measurement = not met);
--   c. every shortfall carries its number;
--   d. a level that FALLS opens one CEO improvement (simulated: last week's row for it_engineer set to 'senior').
-- The PROBE OK line carries every seat's level and measures, so the run is also the week's reading.
do $probe$
declare
  v_r jsonb; v_rows jsonb; v_fail text := ''; v_seats int; v_week date := date_trunc('week', now() at time zone 'Asia/Dubai')::date;
  v_imp bigint;
begin
  v_seats := (select count(*) from public.org_role where status = 'active');
  -- d. a previous week's verdict to fall from. Since the weekly duty has run (measured 11 Nov 2026: a real 2 Nov row
  -- exists), last week's row is usually already there, so the probe sets it to 'senior' rather than inserting a
  -- duplicate (a plain insert raised 23505 seat_senior_verdict_pkey). All of it rolls back with the probe.
  insert into public.seat_senior_verdict (week, seat, stage1, stage2, level, shortfalls)
  values (v_week - 7, 'it_engineer', '{}'::jsonb, '{}'::jsonb, 'senior', '{}')
  on conflict (week, seat) do update set level = 'senior';

  v_r := public.fn_ceo_seat_senior_verdict(now());

  if (select count(*) from public.seat_senior_verdict where week = v_week) <> v_seats then v_fail := v_fail || ' a(rows)'; end if;
  if exists (select 1 from public.seat_senior_verdict where week = v_week and (stage1 = '{}'::jsonb or stage2 = '{}'::jsonb)) then v_fail := v_fail || ' a(stage)'; end if;
  if exists (select 1 from public.seat_senior_verdict where week = v_week and level = 'senior'
              and coalesce((stage1->>'exam_rate')::numeric, 0) < 0.95) then v_fail := v_fail || ' b(senior under bar)'; end if;
  if exists (select 1 from public.seat_senior_verdict where week = v_week and level <> 'junior' and stage1->>'exam_rate' is null) then
    v_fail := v_fail || ' b(level without exam)';
  end if;
  if exists (select 1 from public.seat_senior_verdict v, unnest(v.shortfalls) x where v.week = v_week and x !~ '[0-9]' and x not like '%no judged exam%' and x not like '%no senior contributions%') then
    v_fail := v_fail || ' c(shortfall without a number)';
  end if;
  select improvement_id into v_imp from public.seat_senior_verdict where week = v_week and seat = 'it_engineer';
  if (select level from public.seat_senior_verdict where week = v_week and seat = 'it_engineer') <> 'senior' and v_imp is null then
    v_fail := v_fail || ' d(no improvement on a fall)';
  end if;

  select jsonb_agg(jsonb_build_object('seat', seat, 'level', level, 'shortfalls', shortfalls,
           'exam', stage1->'exam_rate', 'judged', jsonb_build_array(stage1->'judged_outcomes_90d', stage1->'judged_correct_rate'),
           'contrib', jsonb_build_array(stage2->'contributions_live', stage2->'contributions'),
           'clock', jsonb_build_array(stage2->'duties_on_clock', stage2->'duties'),
           'in_window', jsonb_build_array(stage2->'answered_in_window_30d', stage2->'windowed_handoffs_answered_30d'),
           'late_now', stage2->'handoffs_unanswered_past_window_now', 'owed', stage2->'closes_owed_past_window_now', 'own', stage2->'own_actions_30d', 'sent', stage2->'handoffs_sent_30d',
           'recall', stage1->'recall', 'not_live', stage2->'contributions_not_live') order by seat)
    into v_rows from public.seat_senior_verdict where week = v_week;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK ' || v_r::text || ' ROWS ' || v_rows::text
                                    else 'PROBE FAILED:' || v_fail || ' ' || coalesce(v_r::text, 'null') end;
end $probe$;
