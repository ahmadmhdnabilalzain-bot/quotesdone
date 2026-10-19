-- THE CEO CLOSES THE LOOPS A SENIOR CHIEF EXECUTIVE CLOSES (ceo, founder ledger 1003 stage 2, 19 Oct 2026).
--
-- Assigned: ceo. Stage 1 of ledger 1003 measured the CEO seat against a 20-year senior bar
-- (knowledge/standards/ceo.json in the seat-audit branch). Eight contributions were partial or missing. Each becomes a
-- seat_duty here that ACTS -- writes a directive to a seat, a row, a verdict, or closes something -- in code, no model.
--
-- ══ MEASURED, 19 Oct 2026, htdblwldjkcgjvmqkbeh ═══════════════════════════════════════════════════════════════════
--   C03  ceo_directive: 24 rows; 1 met, 11 open, 11 escalated, 1 missed. fn_ceo_directive_run closes met hourly and
--        re-issues once; a re-issue that also misses becomes a ceo_task "the CEO decides the next step itself" -- and
--        nothing decides it (#196, it_findings_open, missed 15 Oct, never looked at again).
--   C04  ceo.month_plan for 2026-10-01: closed 0, reported null. fn_ceo_month_plan closes a month and writes the
--        report only when target_path has rows for that month; September has none, so September was never closed
--        and ceo_month_report has 0 rows.
--   C05  ceo_review target_forecast 2026-10-12: AT_RISK, binding_stage null, what_must_change names two stages with
--        no declared capacity (registrations_submitted, registrations_verified). No directive carries it to a seat.
--   C06  ceo.improvement: 88 open vs 9 closed. Nothing compares the rate opened with the rate closed.
--   C08  ceo.pricing_monitor: quoted_requests_90d 0; the evidence lives only inside one weekly ceo_review row.
--   C09  ceo_experiment: 3 rows, all 'proposed' since 24 Sep, none approved. fn_ceo_experiment_review starts only an
--        APPROVED one and measures running ones; nothing approves or starts one.
--   C13  refund_case: 0 rows; no duty measures refund decisions.
--   C14  risk_register 19 rows (18 closed, 1 open on ceo), compliance_sources 17 active ALL unchecked for 30+ days,
--        v_company_subscriptions 4 renewals already past their date. No duty reviews any of them.
--
-- ══ WHAT THIS ADDS (one duty per contribution) ════════════════════════════════════════════════════════════════════
--   ceo_directive.source_kind also takes 'forecast_at_risk', 'improvement_backlog', 'experiment', 'register_review':
--   the four duties that hand work to a seat do it through fn_ceo_directive_issue, so the hourly ceo.directive loop
--   closes them on their own done_sql, escalates once and closes missed -- one engine, not five.
--   C03  ceo.directive_review   daily   every open directive gets its measured reading; every missed directive gets
--                                      a decision: met since, already live again, or RE-ISSUED with the measured reason
--                                      (at most 4 directives per signal, then the ceo_task stands).
--   C04  ceo.month_close        daily   from the 2nd: each seat's last month closed into ceo_month_close (duties,
--                                      handoffs, directives, improvements); month directives the plan could not grade
--                                      closed not_measurable with their handoff; the monthly report written INTERNAL
--                                      (no handoff, nothing to the founder) when fn_ceo_month_plan could not write it.
--   C05  ceo.forecast_counter_action  weekly  each non-ON_TRACK verdict: its binding stage (or every stage with no
--                                      declared capacity) gets a 7-day directive to the seat that owns that stage.
--   C06  ceo.improvement_burn_down    weekly  opened > closed in 7 days: the oldest (opened - closed, max 10) open
--                                      improvements get a due date and a 7-day directive to their seat.
--   C08  ceo.pricing_evidence   weekly  one ceo_pricing_evidence row per ISO week: requests, quoted, reveals,
--                                      conversion, fee as share of quote, refunds; ready when 20+ quoted requests.
--   C09  ceo.experiment_month   daily   none approved/running and none started this Dubai month: the CEO approves and
--                                      starts the oldest proposal, or starts a supplier-recruitment experiment (hypothesis,
--                                      metric, baseline, target, end date), and directs its owner; past its end date: a
--                                      code verdict, kept or killed.
--   C13  ceo.refund_decision_metric  weekly  ceo_refund_decision_metric per ISO week: decisions, approval rate,
--                                      median hours to decision, overturn rate; a case awaiting the CEO 2+ days opens
--                                      one ceo_task.
--   C14  ceo.register_review    daily, acts monthly  risk_register rows open past review_due, compliance sources
--                                      unchecked 35+ days, subscriptions past renewal or renewing within 14 days,
--                                      compliance calendar entries unverified for a year: a directive to the owner.
--
-- NOT CHANGED: fn_ceo_directive_run, fn_ceo_month_plan (still writes and sends the report when the plan grades the
-- month), fn_ceo_target_forecast, fn_ceo_improvement_sweep, fn_ceo_pricing_monitor, fn_ceo_experiment_review. No price
-- moves (pricing is the founder's). Nothing here notifies the founder.
-- Prevented by: scripts/checks/the_ceo_senior_duties_are_registered_and_act.test.mjs, and the aborted-transaction
-- probe the_ceo_closes_the_loops_a_senior_chief_executive_closes_probe.sql (0 founder notifications).
--
--   node scripts/apply_sql.mjs scripts/sql/the_ceo_closes_the_loops_a_senior_chief_executive_closes.sql --apply --ddl

alter table public.ceo_directive drop constraint if exists ceo_directive_source_kind_check;
alter table public.ceo_directive add constraint ceo_directive_source_kind_check check (source_kind in
  ('target_miss', 'late_deliverable', 'stuck_handoff', 'seat_audit',
   'forecast_at_risk', 'improvement_backlog', 'experiment', 'register_review'));

-- ── C03 ───────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_directive_review()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d public.ceo_directive; v_metrics jsonb := coalesce(public.fn_ceo_year_plan_status(now())->'metrics', '[]'::jsonb);
  v_ok boolean; v_m jsonb; v_reason text; v_new bigint; v_n int; n_measured int := 0; n_reissued int := 0; n_decided int := 0;
begin
  -- every open directive carries the reading it was measured at today
  for d in select * from public.ceo_directive where status = 'open' loop
    select e into v_m from jsonb_array_elements(v_metrics) e where e->>'metric' = split_part(d.source_ref, ':', 1) and d.source_kind = 'target_miss';
    update public.ceo_directive set evidence = evidence || jsonb_build_object('measured', jsonb_build_object('at', now(),
             'actual', v_m->'actual', 'expected', v_m->'expected', 'status', v_m->'status', 'deadline_in_days', round(extract(epoch from deadline - now()) / 86400, 1)))
     where id = d.id;
    n_measured := n_measured + 1;
  end loop;

  -- every missed directive gets the CEO's decision, once
  for d in select * from public.ceo_directive where status = 'missed' and not evidence ? 'review' order by id loop
    begin
      execute 'select coalesce((' || d.done_sql || ')::boolean, false)' into v_ok;
    exception when others then v_ok := false;
    end;
    select e into v_m from jsonb_array_elements(v_metrics) e where e->>'metric' = split_part(d.source_ref, ':', 1) and d.source_kind = 'target_miss';
    v_reason := case when v_m is not null
      then format('%s reads %s against %s (gap %s%%) on %s.', v_m->>'metric', coalesce(v_m->>'actual', 'nothing measurable'), v_m->>'expected',
                  coalesce(v_m->>'gap_pct', '?'), to_char(now() at time zone 'Asia/Dubai', 'DD Mon'))
      else format('Still not true on %s: %s', to_char(now() at time zone 'Asia/Dubai', 'DD Mon'), d.done_when) end;
    select count(*) into v_n from public.ceo_directive where seat = d.seat and source_kind = d.source_kind and source_ref = d.source_ref;
    v_new := null;
    if not v_ok and v_n < 4 and not exists (select 1 from public.ceo_directive where seat = d.seat and source_kind = d.source_kind
                                                and source_ref = d.source_ref and status = 'open') then
      insert into public.ceo_directive (seat, source_kind, source_ref, instruction, done_when, done_sql, deadline, escalated_from, evidence)
      values (d.seat, d.source_kind, d.source_ref,
              'RE-ISSUED by the CEO after #' || d.id || ' was missed. Why: ' || v_reason || ' ' || regexp_replace(d.instruction, '^RE-ISSUED[^:]*: ', ''),
              d.done_when, d.done_sql, now() + greatest(d.deadline - d.issued_at, interval '1 day'), d.id,
              d.evidence - 'missed' - 'escalated' - 'closed' - 'measured' || jsonb_build_object('reissued_from', d.id, 'reason', v_reason))
      returning id into v_new;
      n_reissued := n_reissued + 1;
    end if;
    update public.ceo_directive set evidence = evidence || jsonb_build_object('review', jsonb_build_object('at', now(), 'reason', v_reason,
             'decision', case when v_ok then 'met_since' when v_new is not null then 'reissued' when v_n >= 4 then 'left_with_task' else 'already_live' end,
             'reissue_id', v_new))
     where id = d.id;
    n_decided := n_decided + 1;
  end loop;
  return jsonb_build_object('measured', n_measured, 'missed_decided', n_decided, 'reissued', n_reissued,
    'open', (select count(*) from public.ceo_directive where status = 'open'),
    'met_7d', (select count(*) from public.ceo_directive where status = 'met' and closed_at > now() - interval '7 days'));
end $fn$;
revoke execute on function public.fn_ceo_directive_review() from public, anon, authenticated;
grant execute on function public.fn_ceo_directive_review() to service_role;

-- ── C04 ───────────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.ceo_month_close (
  month     date not null,
  seat      text not null references public.org_role(role_id),
  facts     jsonb not null,
  verdict   text not null check (verdict in ('clean', 'gaps')),
  closed_at timestamptz not null default now(),
  primary key (month, seat)
);
alter table public.ceo_month_close enable row level security;
drop policy if exists ceo_month_close_service_role_only on public.ceo_month_close;
create policy ceo_month_close_service_role_only on public.ceo_month_close as permissive for all to public using (false) with check (false);
revoke all on public.ceo_month_close from anon, authenticated;

create or replace function public.fn_ceo_month_close()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_today date := (now() at time zone 'Asia/Dubai')::date; v_m0 date := date_trunc('month', v_today)::date;
  v_pm date := (v_m0 - interval '1 month')::date; v_from timestamptz; v_to timestamptz; s text; v_f jsonb;
  d public.ceo_seat_directive; n_seats int := 0; n_dir int := 0; v_report boolean := false; v_body text;
begin
  if extract(day from v_today) < 2 then   -- the 1st belongs to fn_ceo_month_plan, which grades a month it has a plan for
    return jsonb_build_object('month', v_pm, 'waiting_for', 'the 2nd');
  end if;
  v_from := v_pm::timestamp at time zone 'Asia/Dubai'; v_to := v_m0::timestamp at time zone 'Asia/Dubai';

  for s in select role_id from public.org_role where status = 'active' and role_id <> 'ceo' order by role_id loop
    continue when exists (select 1 from public.ceo_month_close where month = v_pm and seat = s);
    v_f := jsonb_build_object(
      'duties', (select count(*) from public.seat_duty where owner_seat = s and enabled),
      'duties_unhealthy_now', (select count(*) from jsonb_array_elements(public.fn_seat_duty_health()) h where h->>'owner_seat' = s),
      'handoffs_received', (select count(*) from public.agent_actions a where a.kind = 'handoff' and a.agent = s and a.created_at >= v_from and a.created_at < v_to),
      'handoffs_still_late', (select count(*) from public.agent_actions a
                                join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
                               where a.kind = 'handoff' and a.agent = s and a.status = 'pending' and a.created_at >= v_from and a.created_at < v_to
                                 and a.created_at < now() - k.reply_within),
      'directives_issued', (select count(*) from public.ceo_directive where seat = s and issued_at >= v_from and issued_at < v_to),
      'directives_met', (select count(*) from public.ceo_directive where seat = s and status = 'met' and closed_at >= v_from and closed_at < v_to),
      'directives_missed', (select count(*) from public.ceo_directive where seat = s and status in ('missed', 'escalated') and closed_at >= v_from and closed_at < v_to),
      'improvements_opened', (select count(*) from public.ceo_improvement where seat = s and created_at >= v_from and created_at < v_to),
      'improvements_closed', (select count(*) from public.ceo_improvement where seat = s and closed_at >= v_from and closed_at < v_to),
      'month_directive', (select status from public.ceo_seat_directive where month = v_pm and seat = s));
    insert into public.ceo_month_close (month, seat, facts, verdict)
    values (v_pm, s, v_f, case when (v_f->>'handoffs_still_late')::int = 0 and (v_f->>'directives_missed')::int = 0
                                    and (v_f->>'duties_unhealthy_now')::int = 0 then 'clean' else 'gaps' end);
    n_seats := n_seats + 1;
  end loop;

  -- a month directive the plan could not grade (no target_path for the month) is closed, with its handoff
  if not exists (select 1 from public.target_path where month = v_pm) then
    for d in select * from public.ceo_seat_directive where month = v_pm and status = 'issued' loop
      update public.ceo_seat_directive set status = 'not_measurable', closed_at = now(),
             outcome = (select to_jsonb(c) from public.ceo_month_close c where c.month = v_pm and c.seat = d.seat)
       where month = d.month and seat = d.seat;
      if d.handoff_id is not null and exists (select 1 from public.agent_actions where id = d.handoff_id and status = 'pending') then
        perform set_config('qd.handoff_closer', 'ceo', true);
        perform public.fn_seat_handoff_complete(d.handoff_id, jsonb_build_object('verified_by', 'ceo', 'month', v_pm, 'result', 'not_measurable',
          'receipt', 'Closed by the CEO month close: no plan line existed for this month, so it is closed on the seat''s month record.'));
        perform set_config('qd.handoff_closer', '', true);
      end if;
      n_dir := n_dir + 1;
    end loop;
  end if;

  -- the monthly report: fn_ceo_month_plan writes (and sends) it when it has a plan; otherwise the CEO keeps it internal
  if not exists (select 1 from public.ceo_month_report where month = v_pm) then
    v_body := format(E'Month close, %s (internal).\n', to_char(v_pm, 'FMMonth YYYY'))
      || coalesce((select string_agg(format('- %s: %s. %s directives met, %s missed; %s handoffs still late; %s improvements opened, %s closed.',
                     seat, verdict, facts->>'directives_met', facts->>'directives_missed', facts->>'handoffs_still_late',
                     facts->>'improvements_opened', facts->>'improvements_closed'), E'\n' order by seat)
                   from public.ceo_month_close where month = v_pm), '- no seat was closed');
    insert into public.ceo_month_report (month, facts, body, handoff_id)
    values (v_pm, jsonb_build_object('month', v_pm, 'internal', true, 'seats',
              (select coalesce(jsonb_object_agg(seat, facts || jsonb_build_object('verdict', verdict)), '{}'::jsonb) from public.ceo_month_close where month = v_pm)),
            v_body, null);
    v_report := true;
  end if;
  return jsonb_build_object('month', v_pm, 'seats_closed', n_seats, 'month_directives_closed', n_dir, 'report_written', v_report,
    'seats_with_gaps', (select count(*) from public.ceo_month_close where month = v_pm and verdict = 'gaps'));
end $fn$;
revoke execute on function public.fn_ceo_month_close() from public, anon, authenticated;
grant execute on function public.fn_ceo_month_close() to service_role;

-- ── C05 ───────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_forecast_counter_action()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; v_feas jsonb; v_stage text; v_seat text; v_id bigint; n_issued int := 0; n_unowned int := 0;
begin
  for r in select c.id, c.contract_key from public.target_contract c where c.status = 'active' and c.measure_sql is not null order by c.priority, c.id loop
    v_feas := public.fn_target_feasibility(r.id, true);
    continue when coalesce(v_feas->>'verdict', 'ON_TRACK') = 'ON_TRACK';
    for v_stage in select x from (select v_feas->>'binding_stage' x where v_feas->>'binding_stage' is not null
                                  union select e->>'stage' from jsonb_array_elements(coalesce(v_feas->'chain', '[]'::jsonb)) e
                                   where v_feas->>'binding_stage' is null and e->>'capacity_per_day' is null) q loop
      select p.owner_seat into v_seat from public.target_path p
       where p.contract_id = r.id and (p.metric_key = v_stage or p.metric_key like v_stage || '\_%')
       order by (p.metric_key = v_stage) desc, p.month desc limit 1;
      if v_seat is null then n_unowned := n_unowned + 1; continue; end if;
      v_id := public.fn_ceo_directive_issue(v_seat, 'forecast_at_risk', r.contract_key || ':' || v_stage,
        format('The forecast for %s reads %s. Counter-action on %s, which you own: %s',
               r.contract_key, v_feas->>'verdict', v_stage,
               coalesce((select string_agg(x, ' ') from jsonb_array_elements_text(coalesce(v_feas->'what_must_change', '[]'::jsonb)) x), v_feas->>'verdict_reason')),
        format('the %s forecast is ON_TRACK, or stage %s has a declared capacity per day and is not the binding stage.', r.contract_key, v_stage),
        format($q$(public.fn_target_feasibility(%1$s, true)->>'verdict') = 'ON_TRACK' or exists (select 1 from jsonb_array_elements(public.fn_target_feasibility(%1$s, true)->'chain') e where e->>'stage' = %2$L and e->>'capacity_per_day' is not null and coalesce(public.fn_target_feasibility(%1$s, true)->>'binding_stage', '') <> %2$L)$q$, r.id, v_stage),
        now() + interval '7 days',
        jsonb_build_object('contract', r.contract_key, 'verdict', v_feas->>'verdict', 'stage', v_stage, 'verdict_reason', v_feas->>'verdict_reason'));
      n_issued := n_issued + (v_id is not null)::int;
    end loop;
  end loop;
  return jsonb_build_object('issued', n_issued, 'stages_without_owner', n_unowned,
    'open', (select count(*) from public.ceo_directive where source_kind = 'forecast_at_risk' and status = 'open'));
end $fn$;
revoke execute on function public.fn_ceo_forecast_counter_action() from public, anon, authenticated;
grant execute on function public.fn_ceo_forecast_counter_action() to service_role;

-- ── C06 ───────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_improvement_burn_down()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_opened int; v_closed int; i record; v_id bigint; n_handed int := 0;
begin
  select count(*) filter (where created_at > now() - interval '7 days'), count(*) filter (where closed_at > now() - interval '7 days')
    into v_opened, v_closed from public.ceo_improvement;
  if v_opened > v_closed then
    for i in select * from public.ceo_improvement
              where status in ('open', 'assigned') and seat <> 'ceo'
                and not exists (select 1 from public.ceo_directive d where d.source_kind = 'improvement_backlog' and d.source_ref = 'ceo_improvement:' || ceo_improvement.id and d.status <> 'met')
              order by created_at, id limit least(10, v_opened - v_closed) loop
      update public.ceo_improvement set due_on = (now() at time zone 'Asia/Dubai')::date + 7 where id = i.id and (due_on is null or due_on < (now() at time zone 'Asia/Dubai')::date);
      v_id := public.fn_ceo_directive_issue(i.seat, 'improvement_backlog', 'ceo_improvement:' || i.id,
        format('Close improvement #%s, open since %s: %s', i.id, to_char(i.created_at at time zone 'Asia/Dubai', 'DD Mon'), left(i.proposal, 400)),
        format('improvement #%s is done or dropped.', i.id),
        format($q$exists (select 1 from public.ceo_improvement where id = %s and status in ('done', 'dropped'))$q$, i.id),
        now() + interval '7 days', jsonb_build_object('improvement_id', i.id, 'opened_7d', v_opened, 'closed_7d', v_closed));
      n_handed := n_handed + (v_id is not null)::int;
    end loop;
  end if;
  return jsonb_build_object('opened_7d', v_opened, 'closed_7d', v_closed, 'handed_to_owners', n_handed,
    'open', (select count(*) from public.ceo_improvement where status in ('open', 'assigned')));
end $fn$;
revoke execute on function public.fn_ceo_improvement_burn_down() from public, anon, authenticated;
grant execute on function public.fn_ceo_improvement_burn_down() to service_role;

-- ── C08 ───────────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.ceo_pricing_evidence (
  week                 date primary key,     -- ISO week's Monday, Dubai
  requests_90d         int not null,
  quoted_requests_90d  int not null,
  quotes_90d           int not null,
  reveals_90d          int not null,
  reveal_conversion_pct numeric,             -- reveals / quoted requests; null while nothing was quoted
  avg_quote_aed        numeric,
  avg_reveal_fee_aed   numeric,
  fee_pct_of_quote     numeric,              -- realised reveal fee as a share of the quote it revealed
  refunds_90d          int not null,
  refund_rate_pct      numeric,
  supplier_fee_paying  int not null,
  ready                boolean not null,     -- 20+ quoted requests: enough to bring the founder a proposal
  recorded_at          timestamptz not null default now()
);
alter table public.ceo_pricing_evidence enable row level security;
drop policy if exists ceo_pricing_evidence_service_role_only on public.ceo_pricing_evidence;
create policy ceo_pricing_evidence_service_role_only on public.ceo_pricing_evidence as permissive for all to public using (false) with check (false);
revoke all on public.ceo_pricing_evidence from anon, authenticated;

create or replace function public.fn_ceo_pricing_evidence()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_week date := date_trunc('week', now() at time zone 'Asia/Dubai')::date; v public.ceo_pricing_evidence;
begin
  with q as (select i.id, (select count(*) from public.quotes x where x.inquiry_id = i.id) n from public.inquiries i where i.created_at > now() - interval '90 days'),
       t as (select * from public.transactions where revealed_at > now() - interval '90 days')
  select v_week, (select count(*) from q), (select count(*) from q where n > 0), (select coalesce(sum(n), 0) from q), (select count(*) from t),
         round(100.0 * (select count(*) from t) / nullif((select count(*) from q where n > 0), 0), 1),
         (select round(avg(quote_amount), 2) from public.quotes where created_at > now() - interval '90 days' and quote_amount > 0),
         (select round(avg(reveal_fee), 2) from t),
         (select round(100.0 * sum(reveal_fee) / nullif(sum(quote_amount), 0), 2) from t where quote_amount > 0),
         (select count(*) from t where refund_requested_at is not null),
         round(100.0 * (select count(*) from t where refund_requested_at is not null) / nullif((select count(*) from t), 0), 1),
         (select count(*) from public.leads where registration_paid_at is not null),
         (select count(*) from q where n > 0) >= 20, now()
    into v;
  insert into public.ceo_pricing_evidence select v.*
  on conflict (week) do update set requests_90d = excluded.requests_90d, quoted_requests_90d = excluded.quoted_requests_90d,
    quotes_90d = excluded.quotes_90d, reveals_90d = excluded.reveals_90d, reveal_conversion_pct = excluded.reveal_conversion_pct,
    avg_quote_aed = excluded.avg_quote_aed, avg_reveal_fee_aed = excluded.avg_reveal_fee_aed, fee_pct_of_quote = excluded.fee_pct_of_quote,
    refunds_90d = excluded.refunds_90d, refund_rate_pct = excluded.refund_rate_pct, supplier_fee_paying = excluded.supplier_fee_paying,
    ready = excluded.ready, recorded_at = excluded.recorded_at;
  return to_jsonb(v) - 'recorded_at';
end $fn$;
revoke execute on function public.fn_ceo_pricing_evidence() from public, anon, authenticated;
grant execute on function public.fn_ceo_pricing_evidence() to service_role;

-- ── C09 ───────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_experiment_month()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_today date := (now() at time zone 'Asia/Dubai')::date; v_m0 date := date_trunc('month', v_today)::date;
  v_metric text := 'registrations_submitted'; v_base numeric; v_target numeric; e public.ceo_experiment; v_read numeric; v_met boolean;
  v_started bigint; n_verdicts int := 0; v_dir bigint;
begin
  -- an experiment past its end date gets a verdict in code: the reading over its window against its target
  for e in select * from public.ceo_experiment where status = 'running' and ends_on < v_today order by id loop
    v_read := public.fn_ambition_measure(e.metric_key, e.starts_on::timestamp at time zone 'Asia/Dubai', e.ends_on::timestamp at time zone 'Asia/Dubai');
    v_met := v_read is not null and case when e.direction = 'max' then v_read <= e.target else v_read >= e.target end;
    insert into public.ceo_experiment_verdict (experiment_id, week, iteration, reading, reading_from, reading_to, decision, fields, reasoning, model, decided_at)
    values (e.id, date_trunc('week', v_today)::date, e.iteration, v_read, e.starts_on::timestamp at time zone 'Asia/Dubai', e.ends_on::timestamp at time zone 'Asia/Dubai',
            case when v_met then 'kept' else 'killed' end, jsonb_build_object('final', true, 'target', e.target, 'baseline', e.baseline),
            format('Ended %s: %s read %s against a target of %s (baseline %s).', e.ends_on, e.metric_key, coalesce(v_read::text, 'nothing measurable'), e.target, e.baseline),
            'code', now())
    on conflict (experiment_id, week) do update set reading = excluded.reading, reading_to = excluded.reading_to, decision = excluded.decision,
      fields = excluded.fields, reasoning = excluded.reasoning, model = excluded.model, decided_at = excluded.decided_at
      where ceo_experiment_verdict.decided_at is null;
    update public.ceo_experiment set status = case when v_met then 'kept' else 'killed' end, closed_at = now(), updated_at = now() where id = e.id;
    n_verdicts := n_verdicts + 1;
  end loop;

  -- one experiment a month: none approved or running and none started this month -> the CEO approves and starts the
  -- oldest proposal (three sat 'proposed' since 24 Sep with nobody to approve them), or the supplier-recruitment one
  if not exists (select 1 from public.ceo_experiment where status in ('approved', 'running'))
     and not exists (select 1 from public.ceo_experiment where status <> 'proposed' and starts_on >= v_m0) then
    update public.ceo_experiment set status = 'running', starts_on = v_today, ends_on = v_today + days, updated_at = now(),
           approval = coalesce(approval, '{}'::jsonb) || jsonb_build_object('approved_by', 'ceo', 'at', now(), 'basis', 'every approval is the CEO''s (founder ruling, 8 Sep 2026)')
     where id = (select id from public.ceo_experiment where status = 'proposed' order by created_at, id limit 1)
    returning * into e;
    if e.id is null then
      v_base := coalesce(public.fn_ambition_measure(v_metric, now() - interval '28 days', now()), 0);
      v_target := greatest(round(v_base * 1.2), v_base + 1);
      insert into public.ceo_experiment (key, proposed_by, owner_seat, hypothesis, metric_key, metric_definition, baseline, baseline_note, target,
                                         direction, approach, starts_on, days, ends_on, status, approval)
      values ('supplier_recruitment_' || to_char(v_m0, 'YYYY_MM'), 'ceo', 'marketing',
              'Supplier invitations that open with the buyer demand already waiting in the supplier''s own trade convert more invited suppliers into submitted registrations than the generic invitation.',
              v_metric, 'supplier registrations submitted in the window (fn_ambition_measure)', v_base,
              'registrations submitted in the 28 days before the start', v_target, 'min',
              'For 28 days every supplier invitation leads with the count of open buyer requests in the supplier''s trade and emirate; nothing else in the sequence changes.',
              v_today, 28, v_today + 28, 'running',
              jsonb_build_object('approved_by', 'ceo', 'at', now(), 'basis', 'every approval is the CEO''s (founder ruling, 8 Sep 2026)'))
      returning * into e;
    end if;
    v_started := e.id;
    v_dir := public.fn_ceo_directive_issue(coalesce(e.owner_seat, 'ceo'), 'experiment', 'ceo_experiment:' || e.id,
      format('Run experiment #%s (%s) until %s: %s Target: %s on %s (baseline %s).', e.id, e.key, to_char(e.ends_on, 'DD Mon'),
             e.approach, e.target, e.metric_key, coalesce(e.baseline::text, 'not measured')),
      format('experiment #%s has a verdict (kept or killed).', e.id),
      format($q$exists (select 1 from public.ceo_experiment where id = %s and status in ('kept', 'killed', 'rejected'))$q$, e.id),
      (e.ends_on + 1)::timestamp at time zone 'Asia/Dubai', jsonb_build_object('experiment_id', e.id));
  end if;
  return jsonb_build_object('started', v_started, 'directive', v_dir, 'verdicts', n_verdicts,
    'running', (select count(*) from public.ceo_experiment where status = 'running'));
end $fn$;
revoke execute on function public.fn_ceo_experiment_month() from public, anon, authenticated;
grant execute on function public.fn_ceo_experiment_month() to service_role;

-- ── C13 ───────────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.ceo_refund_decision_metric (
  week                  date primary key,    -- ISO week's Monday, Dubai: decisions made in that week
  decisions             int not null,
  approved              int not null,
  approval_rate_pct     numeric,
  median_hours_to_decide numeric,
  overturned            int not null,        -- a refund the CEO reviewed more than once with a different outcome
  overturn_rate_pct     numeric,
  awaiting_ceo_over_2d  int not null,
  recorded_at           timestamptz not null default now()
);
alter table public.ceo_refund_decision_metric enable row level security;
drop policy if exists ceo_refund_decision_metric_service_role_only on public.ceo_refund_decision_metric;
create policy ceo_refund_decision_metric_service_role_only on public.ceo_refund_decision_metric as permissive for all to public using (false) with check (false);
revoke all on public.ceo_refund_decision_metric from anon, authenticated;

create or replace function public.fn_ceo_refund_decision_metric()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_week date := date_trunc('week', now() at time zone 'Asia/Dubai')::date; v_from timestamptz := v_week::timestamp at time zone 'Asia/Dubai';
  v public.ceo_refund_decision_metric; c record; n_tasks int := 0;
begin
  with dec as (select * from public.refund_case where decided_at >= v_from and decided_at < v_from + interval '7 days'),
       ov as (select refund_id from public.refund_ceo_review where refund_id in (select refund_id from dec)
               group by refund_id having count(distinct outcome) > 1)
  select v_week, (select count(*) from dec),
         (select count(*) from dec where state not in ('ceo_declined', 'ineligible', 'canceled')),
         round(100.0 * (select count(*) from dec where state not in ('ceo_declined', 'ineligible', 'canceled')) / nullif((select count(*) from dec), 0), 1),
         (select round((percentile_cont(0.5) within group (order by extract(epoch from decided_at - created_at) / 3600))::numeric, 1) from dec),
         (select count(*) from ov),
         round(100.0 * (select count(*) from ov) / nullif((select count(*) from dec), 0), 1),
         (select count(*) from public.refund_case where decided_at is null and state in ('eligible', 'ineligible') and updated_at < now() - interval '2 days'),
         now()
    into v;
  insert into public.ceo_refund_decision_metric select v.*
  on conflict (week) do update set decisions = excluded.decisions, approved = excluded.approved, approval_rate_pct = excluded.approval_rate_pct,
    median_hours_to_decide = excluded.median_hours_to_decide, overturned = excluded.overturned, overturn_rate_pct = excluded.overturn_rate_pct,
    awaiting_ceo_over_2d = excluded.awaiting_ceo_over_2d, recorded_at = excluded.recorded_at;

  -- a refund waiting on the CEO's decision for 2+ days is the CEO's own task, opened once per case
  for c in select refund_id, state, amount_aed from public.refund_case
            where decided_at is null and state in ('eligible', 'ineligible') and updated_at < now() - interval '2 days' loop
    continue when exists (select 1 from public.ceo_task where title = format('Decide refund case #%s', c.refund_id) and state <> 'done');
    perform public.fn_ceo_task_open(format('Decide refund case #%s', c.refund_id),
      format('Refund case #%s (%s, AED %s) has waited 2+ days for the CEO''s decision.', c.refund_id, c.state, c.amount_aed));
    n_tasks := n_tasks + 1;
  end loop;
  return to_jsonb(v) - 'recorded_at' || jsonb_build_object('tasks_opened', n_tasks);
end $fn$;
revoke execute on function public.fn_ceo_refund_decision_metric() from public, anon, authenticated;
grant execute on function public.fn_ceo_refund_decision_metric() to service_role;

-- ── C14 ───────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_ceo_register_review()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_m text := to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM'); r record; v_seat text; v_id bigint;
  n_risk int := 0; n_comp int := 0; n_vendor int := 0; n_cal int := 0;
begin
  -- monthly: the review is done once its rows exist for this month (each signal's ref carries the month)
  for r in select id, risk, owner_agent, review_due from public.risk_register
            where status = 'open' and coalesce(review_due, current_date - 1) < current_date loop
    v_seat := case when exists (select 1 from public.org_role where role_id = r.owner_agent and status = 'active') then r.owner_agent else 'ceo' end;
    v_id := public.fn_ceo_directive_issue(v_seat, 'register_review', 'risk_register:' || r.id || ':' || v_m,
      format('Review risk #%s (%s): it was due for review on %s. Re-score it, update the mitigation and set the next review date, or close it.',
             r.id, left(r.risk, 200), coalesce(r.review_due::text, 'no date')),
      format('risk #%s is closed or its review_due is today or later.', r.id),
      format($q$exists (select 1 from public.risk_register where id = %s and (status <> 'open' or review_due >= current_date))$q$, r.id),
      now() + interval '14 days', jsonb_build_object('register', 'risk_register', 'id', r.id));
    n_risk := n_risk + (v_id is not null)::int;
  end loop;

  for r in select id, authority, topic, last_checked_at from public.compliance_sources
            where active and coalesce(last_checked_at, 'epoch') < now() - interval '35 days' loop
    v_id := public.fn_ceo_directive_issue('it_engineer', 'register_review', 'compliance_sources:' || r.id || ':' || v_m,
      format('Re-check compliance source #%s (%s, %s): last checked %s. Fetch it, record what changed, and route any change to the seat it affects.',
             r.id, r.authority, left(r.topic, 120), coalesce(to_char(r.last_checked_at, 'DD Mon YYYY'), 'never')),
      format('compliance source #%s was checked in the last 35 days or is inactive.', r.id),
      format($q$exists (select 1 from public.compliance_sources where id = %s and (not active or last_checked_at >= now() - interval '35 days'))$q$, r.id),
      now() + interval '14 days', jsonb_build_object('register', 'compliance_sources', 'id', r.id));
    n_comp := n_comp + (v_id is not null)::int;
  end loop;

  for r in select kind, item, renews_on, coalesce(owner_seat, 'accountant') seat from public.v_company_subscriptions
            where renews_on is not null and renews_on < current_date + 14 loop
    v_id := public.fn_ceo_directive_issue(r.seat, 'register_review', 'vendor:' || r.kind || ':' || r.item || ':' || v_m,
      format('Vendor register: %s %s renews on %s. Confirm the renewal was charged and recorded (or that it was cancelled) so the register shows the next date.',
             r.kind, r.item, to_char(r.renews_on, 'DD Mon YYYY')),
      format('%s %s shows a renewal date at least 14 days ahead, or is no longer on the register.', r.kind, r.item),
      format($q$not exists (select 1 from public.v_company_subscriptions where kind = %L and item = %L and renews_on < current_date + 14)$q$, r.kind, r.item),
      now() + interval '7 days', jsonb_build_object('register', 'v_company_subscriptions', 'kind', r.kind, 'item', r.item, 'renews_on', r.renews_on));
    n_vendor := n_vendor + (v_id is not null)::int;
  end loop;

  for r in select id, event_name, verified_at from public.company_calendar
            where kind = 'compliance' and coalesce(verified_at, '1970-01-01') < current_date - 365 loop
    v_id := public.fn_ceo_directive_issue('ceo', 'register_review', 'company_calendar:' || r.id || ':' || v_m,
      format('Re-verify compliance calendar entry #%s (%s) against its source; last verified %s.', r.id, r.event_name, coalesce(r.verified_at::text, 'never')),
      format('calendar entry #%s was verified in the last year.', r.id),
      format($q$exists (select 1 from public.company_calendar where id = %s and verified_at >= current_date - 365)$q$, r.id),
      now() + interval '14 days', jsonb_build_object('register', 'company_calendar', 'id', r.id));
    n_cal := n_cal + (v_id is not null)::int;
  end loop;
  return jsonb_build_object('month', v_m, 'risks', n_risk, 'compliance_sources', n_comp, 'vendors', n_vendor, 'calendar', n_cal,
    'open', (select count(*) from public.ceo_directive where source_kind = 'register_review' and status = 'open'));
end $fn$;
revoke execute on function public.fn_ceo_register_review() from public, anon, authenticated;
grant execute on function public.fn_ceo_register_review() to service_role;

-- ── the duties ────────────────────────────────────────────────────────────────────────────────────────────────────
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.directive_review', 'ceo', interval '1 day', 'fn_ceo_directive_review',
   'C03: every open directive carries its measured reading; every missed directive gets the CEO''s decision -- met since, already live, or re-issued with the measured reason (at most 4 per signal).',
   'scripts/sql/the_ceo_closes_the_loops_a_senior_chief_executive_closes.sql'),
  ('ceo.month_close', 'ceo', interval '1 day', 'fn_ceo_month_close',
   'C04: from the 2nd, each seat''s last month is closed into ceo_month_close; month directives the plan could not grade are closed with their handoff; the monthly report is written internal when the plan could not write it.',
   'scripts/sql/the_ceo_closes_the_loops_a_senior_chief_executive_closes.sql'),
  ('ceo.forecast_counter_action', 'ceo', interval '7 days', 'fn_ceo_forecast_counter_action',
   'C05: every target forecast that is not ON_TRACK opens a dated counter-action directive to the seat that owns its binding stage.',
   'scripts/sql/the_ceo_closes_the_loops_a_senior_chief_executive_closes.sql'),
  ('ceo.improvement_burn_down', 'ceo', interval '7 days', 'fn_ceo_improvement_burn_down',
   'C06: when more improvements were opened than closed in the week, the oldest are handed to their seats with a due date and a directive.',
   'scripts/sql/the_ceo_closes_the_loops_a_senior_chief_executive_closes.sql'),
  ('ceo.pricing_evidence', 'ceo', interval '7 days', 'fn_ceo_pricing_evidence',
   'C08: one ceo_pricing_evidence row per week -- requests, quotes, reveals, conversion, fee share of quote, refunds -- ready for a pricing proposal at 20 quoted requests.',
   'scripts/sql/the_ceo_closes_the_loops_a_senior_chief_executive_closes.sql'),
  ('ceo.experiment_month', 'ceo', interval '1 day', 'fn_ceo_experiment_month',
   'C09: one growth experiment a month -- the oldest proposal approved and started, or a new one started with hypothesis, metric, baseline, target and end date when none is in flight; a code verdict, kept or killed, after its end date.',
   'scripts/sql/the_ceo_closes_the_loops_a_senior_chief_executive_closes.sql'),
  ('ceo.refund_decision_metric', 'ceo', interval '7 days', 'fn_ceo_refund_decision_metric',
   'C13: refund decisions per week -- count, approval rate, median hours to decide, overturn rate; a case waiting 2+ days on the CEO opens a CEO task.',
   'scripts/sql/the_ceo_closes_the_loops_a_senior_chief_executive_closes.sql'),
  ('ceo.register_review', 'ceo', interval '1 day', 'fn_ceo_register_review',
   'C14: monthly review of the risk register, compliance sources and calendar, and the vendor register -- each stale or expiring entry handed to its owner with a deadline.',
   'scripts/sql/the_ceo_closes_the_loops_a_senior_chief_executive_closes.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
