-- A MONTH AN APPROVED CALENDAR ALREADY COVERS IS NOT A LATE PLAN (marketing + ceo, 28 Sep 2026).
--
-- MEASURED (production, 28 Sep 2026 12:40 UTC):
--   * fn_ceo_marketing_plan_watch_now() -> {plan_month 2026-10-01, deadline 2026-09-23, status none, late true};
--     ceo_improvement 4412 (marketing_plan_late, 2026-10-01) open since 24 Sep 17:15, assigned to marketing.
--   * marketing_month_plan has no rows. fn_marketing_steps_due queued 'evaluate' for 2026-10-01 and
--     marketing_model_run holds one evaluate/held_not_run (23 Sep): the model path is waiting on the model hold.
--   * BUT October is already planned: campaign 7 (2026-month1-supplier-recruitment), not demo, approved by the
--     founder 24 Sep 18:01 UTC, 60 posts 24 Sep .. 21 Oct 16:30 UTC. The coded monthly loop
--     (fn_marketing_month_plan_tick) deliberately starts with November 2026 for exactly this reason.
--   So the "late" was the watch not knowing about the approved calendar, and the queued evaluate would, once
--   the model is released, draft a SECOND October plan beside the approved one.
--
-- WHAT THIS CHANGES:
--   fn_marketing_month_covered_by_approved_calendar(month)  true when a non-demo campaign with an approved
--       calendar has a live (not cancelled) post scheduled inside that month. Evidence FOR coverage, not a date.
--   fn_ceo_marketing_plan_watch   a covered month is never late; an open marketing_plan_late for a covered
--       month is closed saying which campaign covers it.
--   fn_marketing_steps_due        no evaluate/plan/plan_defend for a covered month (no duplicate plan).
--   November is NOT covered by campaign 7 (last post 21 Oct), so November's plan is still held to its date.
--
-- Prevented by: scripts/checks/an_approved_calendar_month_is_not_a_late_plan.test.mjs (mirror), and the
-- verdict-row probe at the end of this file.
--
--   node scripts/apply_sql.mjs scripts/sql/a_month_an_approved_calendar_already_covers_is_not_a_late_plan.sql --apply --ddl

begin;

create or replace function public.fn_marketing_month_covered_by_approved_calendar(p_month date)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select exists (
    select 1 from public.marketing_campaign c join public.marketing_post p on p.campaign_id = c.id
     where not c.is_demo and c.approved_hash is not null and p.status <> 'cancelled'
       and (p.scheduled_at at time zone 'Asia/Dubai')::date >= date_trunc('month', p_month)::date
       and (p.scheduled_at at time zone 'Asia/Dubai')::date <  (date_trunc('month', p_month) + interval '1 month')::date)
$fn$;
revoke execute on function public.fn_marketing_month_covered_by_approved_calendar(date) from public, anon, authenticated;

create or replace function public.fn_ceo_marketing_plan_watch(p_at timestamp with time zone default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare cal jsonb := public.fn_marketing_plan_calendar(p_at); v_month date; v_deadline date; v_today date;
  p public.marketing_month_plan; v_late boolean; v_stalled boolean := false; v_id bigint; r record; n_closed int := 0;
  v_covered boolean;
begin
  v_month := (cal->>'plan_month')::date; v_deadline := (cal->>'deadline')::date; v_today := (cal->>'today')::date;
  select * into p from public.marketing_month_plan where month = v_month;
  v_covered := public.fn_marketing_month_covered_by_approved_calendar(v_month);
  v_late := v_today > v_deadline and (p.month is null or p.status = 'draft') and not v_covered;

  if v_late then
    v_id := public.fn_ceo_improvement_open('marketing_plan_late', v_month::text, 'marketing',
      format('The marketing plan for %s was due to the CEO by %s (a week before month end, instruction 866) and has not arrived (%s). '
             || 'Send it today with its evidence; the CEO reviews it on the review machine and the month does not start unplanned.',
             to_char(v_month, 'FMMonth YYYY'), to_char(v_deadline, 'DD Mon'), coalesce('status ' || p.status, 'no plan row')),
      jsonb_build_object('plan_month', v_month, 'deadline', v_deadline, 'status', p.status, 'due_on', v_today + 1));
  end if;

  -- closed the day the plan reaches the CEO, or when an approved calendar already covers the month
  for r in select i.id, (i.evidence->>'plan_month')::date as m from public.ceo_improvement i
            where i.source_kind = 'marketing_plan_late' and i.status in ('open', 'assigned') loop
    if exists (select 1 from public.marketing_month_plan mp where mp.month = r.m and mp.status <> 'draft') then
      perform public.fn_ceo_improvement_close(r.id, format('The %s plan reached the CEO (%s).', to_char(r.m, 'FMMonth YYYY'),
        (select status from public.marketing_month_plan where month = r.m)));
      n_closed := n_closed + 1;
    elsif public.fn_marketing_month_covered_by_approved_calendar(r.m) then
      perform public.fn_ceo_improvement_close(r.id, format('%s is already planned: the founder approved campaign %s, which schedules posts in that month; no second plan is drafted.',
        to_char(r.m, 'FMMonth YYYY'),
        (select string_agg(distinct c.campaign_key, ', ') from public.marketing_campaign c join public.marketing_post mp2 on mp2.campaign_id = c.id
          where not c.is_demo and c.approved_hash is not null and mp2.status <> 'cancelled'
            and date_trunc('month', mp2.scheduled_at at time zone 'Asia/Dubai')::date = date_trunc('month', r.m)::date)));
      n_closed := n_closed + 1;
    end if;
  end loop;

  -- the CEO's own side: a plan waiting on the CEO for more than 2 days with no CEO turn since it was sent
  if p.status = 'with_ceo' and p.plan_sent_at < p_at - interval '2 days'
     and not exists (select 1 from public.marketing_plan_review_turn t where t.month = p.month and t.seat = 'ceo'
                       and t.created_at >= p.plan_sent_at) then
    v_stalled := true;
    perform public.fn_it_engineer_finding_upsert('ceo:marketing_plan_review_stalled:' || v_month,
      'The CEO has not reviewed the marketing plan for ' || to_char(v_month, 'FMMonth YYYY') || ' sent ' || to_char(p.plan_sent_at at time zone 'Asia/Dubai', 'DD Mon'),
      'public.marketing_month_plan / seat_deliberation ' || coalesce(p.deliberation_id::text, 'none'), 'agent_facing', 1,
      jsonb_build_object('month', v_month, 'deliberation_id', p.deliberation_id, 'owner_seat', 'ceo'),
      '{}'::text[], array['where the review machine stopped advancing the CEO''s turn'], 'ceo');
  end if;
  update public.it_engineer_finding set closed_at = now(), close_note = 'the CEO''s turn on the marketing plan is recorded, or the plan left the CEO'
   where issue_key like 'ceo:marketing\_plan\_review\_stalled:%' and closed_at is null
     and not (v_stalled and issue_key = 'ceo:marketing_plan_review_stalled:' || v_month);

  return jsonb_build_object('plan_month', v_month, 'deadline', v_deadline, 'status', coalesce(p.status, 'none'),
    'late', v_late, 'covered_by_approved_calendar', v_covered, 'improvement', v_id, 'review_stalled', v_stalled, 'closed', n_closed);
end $function$;

create or replace function public.fn_marketing_steps_due(p_at timestamp with time zone default now())
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $function$
declare out jsonb := '[]'::jsonb; cal jsonb := public.fn_marketing_plan_calendar(p_at);
        v_day date := (p_at at time zone 'Asia/Dubai')::date; v_week date; p public.marketing_month_plan;
        t public.marketing_plan_review_turn; x record;
begin
  -- watch: every measured asset without a perception by the current prompt version
  if (select count(*) from public.marketing_model_run where step = 'watch' and outcome = 'written' and run_day = v_day) < 6 then
    for x in select distinct on (f.file_sha256) f.file_sha256 from public.marketing_asset_feature f
              where not exists (select 1 from public.marketing_asset_perception q
                                 where q.file_sha256 = f.file_sha256 and q.prompt_version = 'watch-v1')
                and public.fn_marketing_subject_blocked('watch', f.file_sha256, p_at) is null
              order by f.file_sha256 limit 3 loop
      out := out || jsonb_build_object('step', 'watch', 'subject', x.file_sha256, 'seat', 'marketing');
    end loop;
  end if;
  -- quality_review: a perception with no review, or a review older than 30 days when results exist
  if (select count(*) from public.marketing_model_run where step = 'quality_review' and outcome = 'written' and run_day = v_day) < 6 then
    for x in select q.file_sha256 from public.marketing_asset_perception q
              where q.prompt_version = 'watch-v1'
                and not exists (select 1 from public.marketing_asset_review r where r.file_sha256 = q.file_sha256
                                   and r.created_at > p_at - interval '30 days')
                and public.fn_marketing_subject_blocked('quality_review', q.file_sha256, p_at) is null
              order by q.id limit 3 loop
      out := out || jsonb_build_object('step', 'quality_review', 'subject', x.file_sha256, 'seat', 'marketing');
    end loop;
  end if;
  -- research: the last complete week, once, when there is anything to read
  v_week := (date_trunc('week', v_day) - interval '7 days')::date;
  if not exists (select 1 from public.marketing_insight_note where week_start = v_week)
     and public.fn_marketing_subject_blocked('research', v_week::text, p_at) is null
     and exists (select 1 from public.market_intel where platform is not null
                   and coalesce(posted_at, created_at) >= v_week and coalesce(posted_at, created_at) < v_week + 7) then
    out := out || jsonb_build_object('step', 'research', 'subject', v_week::text, 'seat', 'marketing');
  end if;
  -- the month: evaluate -> plan -> (the CEO's review on seat_deliberation <-> plan_defend).
  -- A month an approved calendar already covers is planned: no second plan is drafted for it.
  if (cal->>'in_window')::boolean
     and not public.fn_marketing_month_covered_by_approved_calendar((cal->>'plan_month')::date) then
    select * into p from public.marketing_month_plan where month = (cal->>'plan_month')::date;
    if public.fn_marketing_subject_blocked(case when p.month is null or p.verdict is null then 'evaluate'
                                              when p.plan is null then 'plan' else 'plan_defend' end,
                                         cal->>'plan_month', p_at) is not null then
      null;   -- capped or quarantined today: the other steps above still run
    elsif p.month is null or p.verdict is null then
      out := out || jsonb_build_object('step', 'evaluate', 'subject', cal->>'plan_month', 'seat', 'marketing');
    elsif p.plan is null then
      out := out || jsonb_build_object('step', 'plan', 'subject', cal->>'plan_month', 'seat', 'marketing');
    elsif p.status = 'with_ceo' then
      select * into t from public.marketing_plan_review_turn where month = p.month order by round desc, (seat = 'ceo') desc limit 1;
      if t.seat = 'ceo' and t.move in ('request_changes','reject') and t.round < 3 then
        out := out || jsonb_build_object('step', 'plan_defend', 'subject', p.month::text, 'seat', 'marketing');
      end if;
    end if;
  end if;
  return out;
end $function$;

commit;

-- PROBE (reads only; the DDL above is committed): October is covered by the approved campaign, November is not,
-- and the model queue no longer offers a month step for October.
select case
  when not public.fn_marketing_month_covered_by_approved_calendar(date '2026-10-01')
    then 'PROBE FAILED: October is not seen as covered by the approved campaign'
  when public.fn_marketing_month_covered_by_approved_calendar(date '2026-11-01')
    then 'PROBE FAILED: November is seen as covered, but no approved post is scheduled in it'
  when exists (select 1 from jsonb_array_elements(public.fn_marketing_steps_due(timestamptz '2026-09-28 12:00+00')) e
                where e->>'step' in ('evaluate','plan','plan_defend') and e->>'subject' = '2026-10-01')
    then 'PROBE FAILED: the queue still offers an October plan step'
  else 'PROBE OK' end as verdict;
