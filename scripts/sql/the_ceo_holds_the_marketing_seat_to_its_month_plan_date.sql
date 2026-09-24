-- THE CEO HOLDS THE MARKETING SEAT TO ITS MONTH-PLAN DATE, AND WATCHES ITS OWN SIDE OF THE DEBATE.
--
-- Assigned: ceo. 24 Sep 2026. Seat audit GAPS.md, CEO gap 5 (ledger 983; founder instructions 866 and 873: marketing
-- sends next month's plan at least a week before month end, the CEO challenges it, they agree through reasoning).
-- Approved job description, monthly: "Debate the marketing seat's plan for next month."
--
-- ══ MEASURED, 24 Sep 2026 ═════════════════════════════════════════════════════════════════════════════
--   * The debate is built (the_marketing_seat_watches_its_videos_studies_the_market_and_argues_its_month_with_the_ceo.sql):
--     marketing's plan_loop duty (supabase/functions/marketing/duties.ts) writes the plan; the CEO's review runs on the
--     seat_deliberation review machine, advanced by resilience_ping; fn_marketing_takes_the_ceo_review reads it back.
--   * public.marketing_month_plan holds 0 rows. The October plan is due by fn_marketing_plan_calendar's deadline
--     (month end minus 7 days, moved to a working day: 23 Oct 2026). No CEO duty looks at it: if the plan never
--     arrives, or the CEO's review never happens, nobody on the CEO's side knows, and the month starts unplanned.
--
-- ══ WHAT THIS ADDS ════════════════════════════════════════════════════════════════════════════════════
--   ceo.marketing_plan, daily (fn_ceo_marketing_plan_watch), code only, reading marketing's own calendar:
--     * past the deadline with no plan sent (no row, or still 'draft'): the CEO opens an improvement for marketing
--       (fn_ceo_improvement_open, source 'marketing_plan_late': a CEO task and a ceo.improvement handoff the seat
--       acts on) and closes it itself the day the plan reaches it (status past 'draft');
--     * a plan 'with_ceo' for more than 2 days with no recorded CEO turn after it was sent: the CEO's own review is
--       stalled, recorded as a finding owned by the CEO (the review machine's advance is where it is stuck), closed
--       when a CEO turn is recorded.
--   The debate itself is untouched: the CEO still reasons on the review machine, on another model family.
--
-- NOT CHANGED: the marketing routines, the review machine, the calendar. Nothing here calls a model.
--
-- Pending: scripts/sql/pending/the_ceo_holds_the_marketing_seat_to_its_month_plan_date.txt. Applies AFTER
-- the_ceo_turns_the_binding_constraint_into_an_improvement_every_week.sql (the source kind it opens).

create or replace function public.fn_ceo_marketing_plan_watch(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare cal jsonb := public.fn_marketing_plan_calendar(p_at); v_month date; v_deadline date; v_today date;
  p public.marketing_month_plan; v_late boolean; v_stalled boolean := false; v_id bigint; r record; n_closed int := 0;
begin
  v_month := (cal->>'plan_month')::date; v_deadline := (cal->>'deadline')::date; v_today := (cal->>'today')::date;
  select * into p from public.marketing_month_plan where month = v_month;
  v_late := v_today > v_deadline and (p.month is null or p.status = 'draft');

  if v_late then
    v_id := public.fn_ceo_improvement_open('marketing_plan_late', v_month::text, 'marketing',
      format('The marketing plan for %s was due to the CEO by %s (a week before month end, instruction 866) and has not arrived (%s). '
             || 'Send it today with its evidence; the CEO reviews it on the review machine and the month does not start unplanned.',
             to_char(v_month, 'FMMonth YYYY'), to_char(v_deadline, 'DD Mon'), coalesce('status ' || p.status, 'no plan row')),
      jsonb_build_object('plan_month', v_month, 'deadline', v_deadline, 'status', p.status, 'due_on', v_today + 1));
  end if;

  -- closed by the CEO the day the plan reaches it
  for r in select i.id, (i.evidence->>'plan_month')::date as m from public.ceo_improvement i
            where i.source_kind = 'marketing_plan_late' and i.status in ('open', 'assigned') loop
    if exists (select 1 from public.marketing_month_plan mp where mp.month = r.m and mp.status <> 'draft') then
      perform public.fn_ceo_improvement_close(r.id, format('The %s plan reached the CEO (%s).', to_char(r.m, 'FMMonth YYYY'),
        (select status from public.marketing_month_plan where month = r.m)));
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
    'late', v_late, 'improvement', v_id, 'review_stalled', v_stalled, 'closed', n_closed);
end $fn$;
revoke execute on function public.fn_ceo_marketing_plan_watch(timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ceo_marketing_plan_watch(timestamptz) to service_role;

create or replace function public.fn_ceo_marketing_plan_watch_now()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_ceo_marketing_plan_watch(now()) $fn$;
revoke execute on function public.fn_ceo_marketing_plan_watch_now() from public, anon, authenticated;
grant execute on function public.fn_ceo_marketing_plan_watch_now() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.marketing_plan', 'ceo', interval '1 day', 'fn_ceo_marketing_plan_watch_now',
   'Every day, the CEO checks that next month''s marketing plan reached it by its deadline and that its own review of it is not stalled; a late plan is chased with an improvement the CEO closes when the plan arrives.',
   'scripts/sql/the_ceo_holds_the_marketing_seat_to_its_month_plan_date.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
