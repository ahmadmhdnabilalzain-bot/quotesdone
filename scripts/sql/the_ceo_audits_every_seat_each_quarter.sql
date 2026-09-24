-- THE CEO AUDITS EVERY SEAT EACH QUARTER, AND ACTS ON WHAT IT FINDS.
--
-- Assigned: ceo. 24 Sep 2026. Seat audit GAPS.md, CEO gap 7 (ledger 983; founder instructions 13 and 888: a senior
-- standard for every seat). Approved job description, quarterly: "Audit the seats. Check that each seat is still
-- working at senior level and that its knowledge still passes (IT measures this; the CEO acts on it)."
--
-- ══ MEASURED, 24 Sep 2026 ═════════════════════════════════════════════════════════════════════════════
--   The measurements exist and belong to their owners: seat_knowledge_exam (graded by IT's knowledge duty,
--   fn_it_engineer_knowledge_pass_rate, which files a seat's missed items for re-research), seat_duty and
--   fn_seat_duty_health (each seat's duties on their clock), agent_actions handoffs with seat_handoff_kind.reply_within,
--   and ceo_seat_directive (each seat's month, met or missed). Nothing reads them together as a verdict on a seat,
--   and nothing turns a seat that fell below the bar into work for that seat.
--
-- ══ WHAT THIS ADDS ════════════════════════════════════════════════════════════════════════════════════
--   ceo.seat_audit (weekly clock; it audits once per calendar quarter, the first time it runs in the quarter):
--   one ceo_seat_audit row per active seat and quarter, code only —
--     knowledge   graded exam items in the last 90 days and the share answered correct (under 5 graded = not measured);
--     duties      registered, and failing or overdue now (fn_seat_duty_health);
--     handoffs    handoffs to the seat still open past their kind's reply window;
--     directives  the seat's month directives closed 'missed' in the last 90 days.
--   BELOW THE BAR when any holds: knowledge under 80 % on 5+ graded items, a duty failing, a handoff open past its
--   window, or two or more missed months. A seat below the bar gets ONE improvement from the CEO
--   (fn_ceo_improvement_open, source 'seat_audit'): each shortfall named with its number and what to do — retrain on
--   the missed items (IT has already refiled them), repair the failing duty, answer the late handoffs, fix the step
--   behind the missed months. The next quarter's audit closes it when the seat is back at the bar.
--   The seat's monthly targets are re-set every month by ceo.month_plan (a shortfall carries into the next month);
--   this audit does not rewrite the plan table.
--
-- NOT CHANGED: IT's exams and grading, the duties, the plan. Nothing here calls a model or reads text.
--
-- Pending: scripts/sql/pending/the_ceo_audits_every_seat_each_quarter.txt. Applies AFTER
-- the_ceo_turns_the_binding_constraint_into_an_improvement_every_week.sql (the 'seat_audit' source kind).

create table if not exists public.ceo_seat_audit (
  quarter        date not null,                 -- the quarter's first day, Dubai
  seat           text not null references public.org_role (role_id),
  measures       jsonb not null,
  shortfalls     text[] not null default '{}',
  below_bar      boolean not null,
  improvement_id bigint,
  created_at     timestamptz not null default now(),
  primary key (quarter, seat)
);
alter table public.ceo_seat_audit enable row level security;
drop policy if exists ceo_seat_audit_service_role_only on public.ceo_seat_audit;
create policy ceo_seat_audit_service_role_only on public.ceo_seat_audit as permissive for all to public using (false) with check (false);
revoke all on public.ceo_seat_audit from anon, authenticated;

create or replace function public.fn_ceo_seat_audit(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_q date := date_trunc('quarter', p_at at time zone 'Asia/Dubai')::date; v_health jsonb := public.fn_seat_duty_health();
  s record; v_n int; v_ok int; v_rate numeric; v_duties int; v_failing int; v_late int; v_missed int;
  v_short text[]; v_m jsonb; v_id bigint; n_below int := 0; n_closed int := 0; r record;
begin
  if exists (select 1 from public.ceo_seat_audit where quarter = v_q) then
    return jsonb_build_object('quarter', v_q, 'already', true);
  end if;

  for s in select role_id from public.org_role where status = 'active' and role_id <> 'ceo' order by role_id loop
    select count(*), count(*) filter (where verdict = 'correct') into v_n, v_ok
      from public.seat_knowledge_exam where seat = s.role_id and graded_at > p_at - interval '90 days';
    v_rate := case when v_n >= 5 then round(v_ok::numeric / v_n, 3) end;
    select count(*) into v_duties from public.seat_duty where owner_seat = s.role_id and enabled;
    select count(*) into v_failing from jsonb_array_elements(v_health) h where h->>'owner_seat' = s.role_id;
    select count(*) into v_late from public.agent_actions a
      join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
     where a.kind = 'handoff' and a.agent = s.role_id and a.status = 'pending' and a.created_at < p_at - k.reply_within;
    select count(*) into v_missed from public.ceo_seat_directive
     where seat = s.role_id and status = 'missed' and month >= (v_q - interval '3 months')::date;

    v_short := '{}';
    if v_rate is not null and v_rate < 0.80 then
      v_short := v_short || format('knowledge %s%% correct on %s graded items in 90 days: retrain on the items missed (IT refiled each one for re-research) until the rate is back over 80%%', round(v_rate * 100), v_n);
    end if;
    if v_failing > 0 then
      v_short := v_short || format('%s of %s duties failing or overdue now: repair each until it runs on its clock', v_failing, v_duties);
    end if;
    if v_late > 0 then
      v_short := v_short || format('%s handoffs open past their reply window: answer each, and say why it was late', v_late);
    end if;
    if v_missed >= 2 then
      v_short := v_short || format('%s monthly targets missed in the last quarter: name the step that did not convert and change it', v_missed);
    end if;
    v_m := jsonb_build_object('knowledge_graded_90d', v_n, 'knowledge_correct_90d', v_ok, 'knowledge_rate', v_rate,
      'duties', v_duties, 'duties_failing', v_failing, 'handoffs_late', v_late, 'months_missed', v_missed);

    v_id := null;
    if cardinality(v_short) > 0 then
      v_id := public.fn_ceo_improvement_open('seat_audit', v_q || ':' || s.role_id, s.role_id,
        format('Quarterly audit of %s for the quarter starting %s: below the senior bar. ', s.role_id, to_char(v_q, 'DD Mon YYYY'))
          || array_to_string(v_short, '; ') || '. Due before the next quarterly audit.',
        v_m || jsonb_build_object('quarter', v_q));
      n_below := n_below + 1;
    end if;
    insert into public.ceo_seat_audit (quarter, seat, measures, shortfalls, below_bar, improvement_id)
    values (v_q, s.role_id, v_m, v_short, cardinality(v_short) > 0, v_id);
  end loop;

  -- last quarter's audit improvements close when the seat is back at the bar this quarter
  for r in select i.id, i.seat from public.ceo_improvement i
            where i.source_kind = 'seat_audit' and i.status in ('open', 'assigned') and (i.evidence->>'quarter')::date < v_q loop
    if exists (select 1 from public.ceo_seat_audit a where a.quarter = v_q and a.seat = r.seat and not a.below_bar) then
      perform public.fn_ceo_improvement_close(r.id, format('%s is back at the bar in the audit of the quarter starting %s.', r.seat, v_q));
      n_closed := n_closed + 1;
    end if;
  end loop;
  return jsonb_build_object('quarter', v_q, 'seats', (select count(*) from public.ceo_seat_audit where quarter = v_q),
                            'below_bar', n_below, 'closed', n_closed);
end $fn$;
revoke execute on function public.fn_ceo_seat_audit(timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ceo_seat_audit(timestamptz) to service_role;

create or replace function public.fn_ceo_seat_audit_now()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_ceo_seat_audit(now()) $fn$;
revoke execute on function public.fn_ceo_seat_audit_now() from public, anon, authenticated;
grant execute on function public.fn_ceo_seat_audit_now() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.seat_audit', 'ceo', interval '7 days', 'fn_ceo_seat_audit_now',
   'Once a quarter, every seat is audited on its knowledge pass rate, its duties, its late handoffs and its missed months; a seat below the bar gets one improvement the next audit closes.',
   'scripts/sql/the_ceo_audits_every_seat_each_quarter.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
