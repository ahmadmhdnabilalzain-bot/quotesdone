-- THE CEO ISSUES DIRECTIVES WITH A DONE-CONDITION, AND CLOSES EACH ONE ONLY WHEN THE CONDITION IS TRUE.
--
-- Assigned: ceo. 28 Sep 2026. CEO seat audit (ceo.md), gap 3 and table 2 rows 5-8: "directive engine live, and the
-- improvement backlog triaged ... Chase the late October marketing plan."
--
-- ══ MEASURED, 28 Sep 2026 13:40 UTC, htdblwldjkcgjvmqkbeh ═════════════════════════════════════════════════════════
--   * ceo_seat_directive: 0 rows. It is the MONTHLY target contract, primary key (month, seat), written and graded
--     by ceo.month_plan and read by five month routines (fn_ceo_month_plan, the seat audit's missed-month count,
--     the board pack). One row per seat per month cannot hold one directive per signal, so the signal directives
--     live in their own table, ceo_directive, below. ceo_seat_directive is not changed.
--   * ceo_day.priorities for 28 Sep: every seat's first line read "Move improvement #N forward." (#4412, #1177,
--     #790, #828, #1141): a pointer, not an instruction, with no done-condition and no date.
--   * ceo_improvement: 121 assigned (it_engineer 97, sales_engineer 7, ceo 8, customer_support 6, accountant 2,
--     marketing 1), 275 dropped. The duplicate lessons (367 on it_engineer) were already superseded and the
--     lesson close re-verifies on each sweep: that is PR #971 (applied), which this file does not repeat.
--     0 exact (seat, proposal) duplicates remain among the open set.
--   * the late October marketing plan: improvement #4412 (marketing_plan_late, assigned 24 Sep); marketing_month_plan
--     has 0 rows. It was flagged but nothing carried a date or was re-checked against the plan arriving.
--   * seat audit, quarter 2026-07-01: accountant, customer_support, sales_engineer below the bar (1, 9 and 11
--     handoffs past their reply window). fn_ceo_year_plan_status metrics: [] today (the target tracker is another PR).
--
-- ══ WHAT THIS ADDS (code only; no model) ══════════════════════════════════════════════════════════════════════════
--   ceo_directive: seat, instruction, done_when (plain words) + done_sql (a boolean SQL predicate the loop runs),
--   deadline, source_kind + source_ref (the signal), status open | met | escalated | missed. At most ONE directive per
--   (seat, source_kind, source_ref) that is not 'met' (unique index + the issuer's own check): a signal that is being
--   worked, escalated or missed is never issued twice. A signal that recurs after being met gets a new directive.
--
--   fn_ceo_directive_run(p_at), duty ceo.directive (hourly), also called by the daily run before the priorities:
--   ISSUE from four signals —
--     target_miss       a year-plan metric with status 'miss'   → owner seat, 7 days, done when the metric is not 'miss';
--     late_deliverable  an open marketing_plan_late improvement → marketing, due_on, done when the month plan left draft
--                       (or the improvement was closed by its own path, e.g. a month an approved calendar covers);
--     stuck_handoff     a handoff pending past twice its reply window → receiving seat, 1 day, done when answered;
--     seat_audit        the latest quarter's below-bar seats    → that seat, 14 days, done when 0 handoffs are past
--                       their window and 0 of its duties are failing or overdue.
--   CLOSE: every open directive's done_sql is run; true → 'met' with the evidence (predicate, result, time).
--   ESCALATE ONCE: past the deadline and unmet, a first-issue directive becomes 'escalated', a re-issue is written with
--     a new deadline of the same length, and one ceo_decision_log row (key 'directive_escalation') records it.
--     A re-issue that is past ITS deadline is closed 'missed' and opens a ceo_task: never re-issued again, never silent.
--
--   Backlog cap: fn_ceo_improvement_open opens no NEW 'lesson' or 'recurring_finding' improvement for a seat that
--   already holds 20 open ones. Nothing is closed to meet the cap; the weekly sweep re-proposes the signal when the
--   seat has room (the source key is unchanged, so it is proposed once). Other kinds are never capped.
--
--   fn_ceo_daily_run: the seat's first priority is its earliest-due open directive, in words, with its done-condition.
--   With no directive it names the oldest assigned improvement's proposal text, never "Move improvement #N forward".
--   Also fixed there (found by the probe): a SECOND run on the same day with no matters either time failed with
--   "null value in column matters" (array_agg over nothing is NULL); the merge is now coalesced to '{}'.
--
-- NOT CHANGED: ceo_seat_directive and the month plan; the target tracker and target_verdict (other PRs); the improvement
-- sweep and its close paths (#971); the marketing plan watch. The predicates only read.
-- Prevented by: scripts/checks/a_ceo_directive_closes_on_its_own_condition.test.mjs

create table if not exists public.ceo_directive (
  id             bigint generated always as identity primary key,
  seat           text not null references public.org_role(role_id),
  source_kind    text not null check (source_kind in ('target_miss', 'late_deliverable', 'stuck_handoff', 'seat_audit')),
  source_ref     text not null,
  instruction    text not null check (btrim(instruction) <> ''),
  done_when      text not null check (btrim(done_when) <> ''),
  done_sql       text not null check (btrim(done_sql) <> ''),
  deadline       timestamptz not null,
  status         text not null default 'open' check (status in ('open', 'met', 'escalated', 'missed')),
  escalated_from bigint references public.ceo_directive(id),
  evidence       jsonb not null default '{}'::jsonb,
  issued_at      timestamptz not null default now(),
  closed_at      timestamptz
);
create unique index if not exists ceo_directive_one_live_per_signal
  on public.ceo_directive (seat, source_kind, source_ref) where status = 'open';
alter table public.ceo_directive enable row level security;
drop policy if exists ceo_directive_service_role_only on public.ceo_directive;
create policy ceo_directive_service_role_only on public.ceo_directive as permissive for all to public using (false) with check (false);
revoke all on public.ceo_directive from anon, authenticated;

insert into public.ceo_decision (decision_key, domain, decision, trigger_condition, measure, measure_sql, authority, evidence_required, cadence)
values ('directive_escalation', 'Operations',
  'A seat directive passed its deadline unmet: it is re-issued once with a new deadline of the same length. A re-issue that also passes its deadline is closed missed and becomes a CEO task.',
  'An open ceo_directive past its deadline whose done-condition is still false.',
  'Open directives past their deadline (should be 0 after each run).',
  'select count(*)::text from public.ceo_directive where status = ''open'' and deadline < now()',
  'ceo_alone', 'The directive, its done-condition, the predicate result at the deadline, and the re-issue id.', 'hourly')
on conflict (decision_key) do nothing;

-- issue one directive unless the signal already has one that is not met
create or replace function public.fn_ceo_directive_issue(p_seat text, p_kind text, p_ref text, p_instruction text,
  p_done_when text, p_done_sql text, p_deadline timestamptz, p_evidence jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint;
begin
  if exists (select 1 from public.ceo_directive where seat = p_seat and source_kind = p_kind and source_ref = p_ref and status <> 'met')
     or not exists (select 1 from public.org_role where role_id = p_seat and status = 'active') then
    return null;
  end if;
  insert into public.ceo_directive (seat, source_kind, source_ref, instruction, done_when, done_sql, deadline, evidence)
  values (p_seat, p_kind, p_ref, p_instruction, p_done_when, p_done_sql, p_deadline, coalesce(p_evidence, '{}'::jsonb))
  returning id into v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_ceo_directive_issue(text, text, text, text, text, text, timestamptz, jsonb) from public, anon, authenticated;
grant execute on function public.fn_ceo_directive_issue(text, text, text, text, text, text, timestamptz, jsonb) to service_role;

create or replace function public.fn_ceo_directive_run(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; d public.ceo_directive; v bigint; v_ok boolean; v_err text; v_new bigint; v_dec bigint; v_task bigint;
  n_issued int := 0; n_met int := 0; n_esc int := 0; n_missed int := 0; v_q date;
  v_late text := $q$exists (select 1 from public.agent_actions a
      join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
     where a.kind = 'handoff' and a.agent = %1$L and a.status = 'pending' and a.created_at < now() - k.reply_within)$q$;
begin
  -- 1. target misses on the year-one plan
  for r in select e->>'metric' as metric, e->>'owner_seat' as seat, e->>'actual' as actual, e->>'expected' as expected
             from jsonb_array_elements(coalesce(public.fn_ceo_year_plan_status(p_at)->'metrics', '[]'::jsonb)) e
            where e->>'status' = 'miss' and e->>'owner_seat' is not null loop
    v := public.fn_ceo_directive_issue(r.seat, 'target_miss', r.metric || ':' || to_char(p_at at time zone 'Asia/Dubai', 'YYYY-MM'),
      format('Bring %s back to its path: it reads %s against %s. Name the step that is not converting and change that step.', r.metric, coalesce(r.actual, '?'), r.expected),
      format('%s is no longer a miss on the year-one plan.', r.metric),
      format($q$not exists (select 1 from jsonb_array_elements(coalesce(public.fn_ceo_year_plan_status(now())->'metrics', '[]'::jsonb)) e where e->>'metric' = %L and e->>'status' = 'miss')$q$, r.metric),
      p_at + interval '7 days', jsonb_build_object('metric', r.metric, 'actual', r.actual, 'expected', r.expected));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- 2. late deliverables: the month marketing plan
  for r in select i.id, (i.evidence->>'plan_month')::date as m, (i.evidence->>'deadline')::date as due_was, (i.evidence->>'due_on')::date as due_on
             from public.ceo_improvement i where i.source_kind = 'marketing_plan_late' and i.status in ('open', 'assigned') loop
    v := public.fn_ceo_directive_issue('marketing', 'late_deliverable', 'marketing_month_plan:' || r.m,
      format('Send the CEO the marketing plan for %s. It was due on %s; the month does not start unplanned.', to_char(r.m, 'FMMonth YYYY'), to_char(r.due_was, 'DD Mon')),
      format('marketing_month_plan for %s exists and has left draft, or improvement #%s is closed.', r.m, r.id),
      format($q$exists (select 1 from public.marketing_month_plan p where p.month = %L::date and p.status <> 'draft') or exists (select 1 from public.ceo_improvement i where i.id = %s and i.status = 'done')$q$, r.m, r.id),
      greatest(coalesce(r.due_on::timestamp at time zone 'Asia/Dubai', p_at), p_at) + interval '1 day',
      jsonb_build_object('improvement_id', r.id, 'plan_month', r.m, 'due_was', r.due_was));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- 3. stuck handoffs: pending past twice the kind's reply window (a day when none is set), as the daily run reads them
  for r in select a.id, a.agent as seat, a.detail->>'type' as type, a.detail->>'from' as from_seat, a.created_at
             from public.agent_actions a
             left join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'replied_at' is null
              and a.created_at < p_at - coalesce(k.reply_within * 2, interval '1 day') loop
    v := public.fn_ceo_directive_issue(r.seat, 'stuck_handoff', 'agent_actions:' || r.id,
      format('Answer handoff #%s (%s from %s), waiting since %s.', r.id, r.type, r.from_seat, to_char(r.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI')),
      format('handoff #%s is answered (replied_at set) or no longer pending.', r.id),
      format($q$exists (select 1 from public.agent_actions a where a.id = %s and (a.status <> 'pending' or a.detail ? 'replied_at'))$q$, r.id),
      p_at + interval '1 day', jsonb_build_object('handoff_id', r.id, 'type', r.type, 'from', r.from_seat, 'since', r.created_at));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- 4. the latest seat audit's below-bar seats
  select max(quarter) into v_q from public.ceo_seat_audit;
  for r in select a.seat, a.shortfalls, a.improvement_id from public.ceo_seat_audit a where a.quarter = v_q and a.below_bar loop
    v := public.fn_ceo_directive_issue(r.seat, 'seat_audit', v_q || ':' || r.seat,
      format('Get back to the senior bar found short in the audit of the quarter starting %s: %s.', to_char(v_q, 'DD Mon YYYY'), array_to_string(r.shortfalls, '; ')),
      'no handoff to the seat is open past its reply window, and none of its duties is failing or overdue.',
      format('not ' || v_late || $q$ and not exists (select 1 from jsonb_array_elements(public.fn_seat_duty_health()) h where h->>'owner_seat' = %1$L)$q$, r.seat),
      p_at + interval '14 days', jsonb_build_object('quarter', v_q, 'improvement_id', r.improvement_id, 'shortfalls', r.shortfalls));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- the close loop: each open directive is re-checked on its own predicate
  for d in select * from public.ceo_directive where status = 'open' order by id loop
    v_err := null;
    begin
      execute 'select coalesce((' || d.done_sql || ')::boolean, false)' into v_ok;
    exception when others then v_ok := false; v_err := left(sqlerrm, 300);
    end;
    if v_ok then
      update public.ceo_directive set status = 'met', closed_at = p_at,
             evidence = evidence || jsonb_build_object('closed', jsonb_build_object('checked_at', p_at, 'predicate', d.done_sql, 'result', true))
       where id = d.id;
      n_met := n_met + 1;
    elsif p_at > d.deadline and d.escalated_from is null then
      update public.ceo_directive set status = 'escalated', closed_at = p_at,
             evidence = evidence || jsonb_build_object('escalated', jsonb_build_object('checked_at', p_at, 'result', false, 'error', v_err))
       where id = d.id;
      insert into public.ceo_directive (seat, source_kind, source_ref, instruction, done_when, done_sql, deadline, escalated_from, evidence)
      values (d.seat, d.source_kind, d.source_ref, 'RE-ISSUED after the deadline of ' || to_char(d.deadline at time zone 'Asia/Dubai', 'DD Mon') || ' passed: ' || d.instruction,
              d.done_when, d.done_sql, p_at + (d.deadline - d.issued_at), d.id, d.evidence)
      returning id into v_new;
      insert into public.ceo_decision_log (decision_key, the_decision, evidence, reading_before, outcome, dedupe_key)
      values ('directive_escalation',
              format('Directive #%s to %s passed its deadline unmet; re-issued once as #%s, due %s.', d.id, d.seat, v_new,
                     to_char((p_at + (d.deadline - d.issued_at)) at time zone 'Asia/Dubai', 'DD Mon')),
              jsonb_build_object('directive_id', d.id, 'reissue_id', v_new, 'seat', d.seat, 'done_when', d.done_when, 'deadline', d.deadline, 'predicate_error', v_err),
              'done-condition false at ' || p_at, 'decided', 'ceo_directive_escalation:' || d.id)
      on conflict do nothing returning id into v_dec;
      update public.ceo_directive set evidence = evidence || jsonb_build_object('decision_log_id', v_dec) where id = d.id;
      n_esc := n_esc + 1;
    elsif p_at > d.deadline then
      v_task := public.fn_ceo_task_open(format('Directive #%s to %s missed after re-issue', d.id, d.seat),
        format(E'%s\nDone when: %s\nFirst issued as #%s. The CEO decides the next step itself; it is not re-issued again.', d.instruction, d.done_when, d.escalated_from));
      update public.ceo_directive set status = 'missed', closed_at = p_at,
             evidence = evidence || jsonb_build_object('missed', jsonb_build_object('checked_at', p_at, 'result', false, 'error', v_err, 'task_id', v_task))
       where id = d.id;
      n_missed := n_missed + 1;
    end if;
  end loop;

  return jsonb_build_object('issued', n_issued, 'met', n_met, 'escalated', n_esc, 'missed', n_missed,
    'open', (select count(*) from public.ceo_directive where status = 'open'));
end $fn$;
revoke execute on function public.fn_ceo_directive_run(timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ceo_directive_run(timestamptz) to service_role;

create or replace function public.fn_ceo_directive_run_now()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_ceo_directive_run(now()) $fn$;
revoke execute on function public.fn_ceo_directive_run_now() from public, anon, authenticated;
grant execute on function public.fn_ceo_directive_run_now() to service_role;

-- the backlog cap: a seat holding 20 open lesson/finding improvements gets no new one until it has room
create or replace function public.fn_ceo_improvement_open(p_kind text, p_ref text, p_seat text, p_proposal text, p_evidence jsonb)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_id bigint; v_task bigint; v_hid bigint;
begin
  if p_kind in ('lesson', 'recurring_finding')
     and (select count(*) from public.ceo_improvement where seat = p_seat and status in ('open', 'assigned')) >= 20 then
    return null;   -- capped: re-proposed by the next sweep once the seat has room; nothing is closed to make room
  end if;
  insert into public.ceo_improvement (source_kind, source_ref, seat, proposal, evidence)
  values (p_kind, p_ref, p_seat, p_proposal, coalesce(p_evidence, '{}'::jsonb))
  on conflict (source_kind, source_ref) do nothing returning id into v_id;
  if v_id is null then return null; end if;   -- proposed already
  v_task := public.fn_ceo_task_open(format('Improvement #%s for %s: %s', v_id, p_seat, left(p_proposal, 200)),
                                    format(E'%s\nSource: %s %s.\nEvidence: %s', p_proposal, p_kind, p_ref, coalesce(p_evidence, '{}'::jsonb)));
  if p_seat <> 'ceo' then
    v_hid := public.fn_seat_handoff('ceo', p_seat, 'ceo.improvement', 'ceo_improvement', v_id::text,
      jsonb_build_object('improvement_id', v_id, 'task_id', v_task, 'proposal', p_proposal, 'source', p_kind, 'evidence', p_evidence));
  end if;
  update public.ceo_improvement set status = 'assigned', task_id = v_task, handoff_id = v_hid where id = v_id;
  return v_id;
end $function$;

-- the daily run: the seat's first priority is its top open directive (copied from the live definition, 28 Sep 2026)
CREATE OR REPLACE FUNCTION public.fn_ceo_daily_run(p_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_day date := (p_at at time zone 'Asia/Dubai')::date; v_m0 date := date_trunc('month', p_at at time zone 'Asia/Dubai')::date;
  v_from timestamptz := v_m0::timestamp at time zone 'Asia/Dubai';
  v_verdict jsonb; v_status jsonb; h record; n_stuck_new int := 0; v_stuck jsonb := '[]'::jsonb; v_prio jsonb := '{}'::jsonb;
  v_signals jsonb; v_matters text[] := '{}'; v_note bigint; s text; v_m jsonb; v_first text; v_task bigint; v_body text; v_dir jsonb; v_d public.ceo_directive;
begin
  -- the morning read: every path metric against today (idempotent: the verdict opens a task once per miss)
  v_verdict := public.fn_ceo_target_daily_verdict(p_at);
  v_status := public.fn_ceo_year_plan_status(p_at);

  -- unblocking: a handoff the receiving seat never answered within twice its reply time (a day when none is set)
  for h in select a.id, a.agent, a.detail->>'type' as type, a.detail->>'from' as from_seat, a.created_at
             from public.agent_actions a
             left join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'replied_at' is null
              and a.created_at < p_at - coalesce(k.reply_within * 2, interval '1 day') loop
    v_stuck := v_stuck || jsonb_build_object('handoff_id', h.id, 'seat', h.agent, 'type', h.type, 'from', h.from_seat, 'since', h.created_at);
    if not exists (select 1 from public.ceo_task where title = format('Stuck handoff #%s', h.id)) then
      v_task := public.fn_ceo_task_open(format('Stuck handoff #%s', h.id),
        format(E'%s from %s to %s has waited since %s with no answer. The CEO re-runs it (fn_seat_handoff_act) and, if it fails again, the failure is on this task.',
               h.type, h.from_seat, h.agent, h.created_at));
      begin
        perform public.fn_seat_handoff_act(h.id);                    -- the unblock: the receiving seat acts now
        update public.ceo_task set state = 'done', closed_at = now(), evidence = 'Re-run on ' || v_day || ': the seat answered.'
         where task_id = v_task and exists (select 1 from public.agent_actions where id = h.id and (status = 'done' or detail ? 'replied_at'));
      exception when others then
        update public.ceo_task set state = 'blocked', blocked_reason = left('Re-run failed: ' || sqlerrm, 1000) where task_id = v_task;
      end;
      n_stuck_new := n_stuck_new + 1;
    end if;
  end loop;

  -- the experience, cash and incident signals
  v_signals := jsonb_build_object(
    'stranded_registrations', public.fn_ceo_plan_measure('stranded_submissions', p_at - interval '1 day', p_at),
    'bounce_pct_7d', public.fn_ceo_plan_measure('bounce_pct_7d', p_at - interval '7 days', p_at),
    'requests_unquoted_3d', (select count(*) from public.inquiries i join public.customers c on c.id = i.customer_id
                               where i.parent_inquiry_id is null and i.created_at < p_at - interval '3 days' and i.created_at > p_at - interval '30 days'
                                 and not exists (select 1 from public.quotes q where q.inquiry_id = i.id)
                                 and coalesce(i.provenance->>'source', '') not in ('demo_factory', 'e2e')
                                 and not (coalesce(c.is_demo, false) or coalesce(c.full_name, '') ilike 'ZZ DEMO%' or coalesce(c.email, '') ilike '%@example.invalid')),
    'findings_open', (select count(*) from public.it_engineer_finding where closed_at is null),
    'findings_new_today', (select count(*) from public.it_engineer_finding where closed_at is null and started_at > p_at - interval '1 day'),
    'fee_month_aed', public.fn_ambition_measure('fee_aed', v_from, p_at),
    'costs_month_aed', public.fn_ambition_measure('costs_aed', v_from, p_at),
    'cost_ceiling_month_aed', (select cost_ceiling_aed from public.ceo_year_plan where month = v_m0),
    'stale_tasks', (select count(*) from public.ceo_task where state in ('open', 'working', 'blocked') and created_at < p_at - interval '14 days'));

  -- the directives: issued from the signals above and re-checked on their own done-condition before the priorities
  v_dir := public.fn_ceo_directive_run(p_at);

  -- the day's priorities per seat: its earliest-due open directive, in words; else its oldest improvement's proposal
  foreach s in array array['sales_engineer', 'customer_support', 'marketing', 'accountant', 'it_engineer'] loop
    select e into v_m from jsonb_array_elements(v_status->'metrics') e
     where e->>'owner_seat' = s and e->>'status' in ('miss', 'within_tolerance')
     order by (e->>'status' = 'miss') desc, abs(coalesce((e->>'gap_pct')::numeric, 0)) desc limit 1;
    v_d := null;
    select * into v_d from public.ceo_directive d where d.seat = s and d.status = 'open' order by d.deadline, d.id limit 1;
    v_first := case
      when v_d.id is not null then format('Directive #%s, due %s: %s Done when %s', v_d.id,
        to_char(v_d.deadline at time zone 'Asia/Dubai', 'DD Mon HH24:MI'), v_d.instruction, v_d.done_when)
      when v_m is not null then format('Recover %s: %s against %s today (%s).', v_m->>'metric', coalesce(v_m->>'actual', '?'), v_m->>'expected', v_m->>'status')
      when exists (select 1 from jsonb_array_elements(v_stuck) e where e->>'seat' = s) then 'Answer the handoffs waiting past their reply time.'
      when exists (select 1 from public.ceo_improvement i where i.seat = s and i.status = 'assigned') then
        (select format('Improvement #%s: %s', i.id, left(i.proposal, 300)) from public.ceo_improvement i
          where i.seat = s and i.status = 'assigned' order by i.id limit 1)
      else 'Hold the path: every target of the month is on track.' end;
    v_prio := v_prio || jsonb_build_object(s, jsonb_build_object('first', v_first,
      'misses', (select coalesce(jsonb_agg(e->>'metric'), '[]'::jsonb) from jsonb_array_elements(v_status->'metrics') e where e->>'owner_seat' = s and e->>'status' = 'miss'),
      'directive_id', v_d.id,
      'stuck_handoffs', (select count(*) from jsonb_array_elements(v_stuck) e where e->>'seat' = s),
      'improvements_open', (select count(*) from public.ceo_improvement i where i.seat = s and i.status in ('open', 'assigned'))));
  end loop;

  -- what matters enough for the founder's daily note (otherwise he gets nothing today)
  if coalesce((v_verdict->>'tasks_opened')::int, 0) > 0 then v_matters := v_matters || format('%s target(s) fell behind the path today', v_verdict->>'tasks_opened'); end if;
  if n_stuck_new > 0 then v_matters := v_matters || format('%s handoff(s) were stuck and re-run', n_stuck_new); end if;
  if coalesce((v_signals->>'stranded_registrations')::numeric, 0) > 0 then v_matters := v_matters || format('%s supplier registration(s) waited over 24 hours', v_signals->>'stranded_registrations'); end if;
  if coalesce((v_signals->>'bounce_pct_7d')::numeric, 0) >= 5 then v_matters := v_matters || format('email bounces at %s %% over 7 days', v_signals->>'bounce_pct_7d'); end if;
  if coalesce((v_signals->>'requests_unquoted_3d')::int, 0) > 0 then v_matters := v_matters || format('%s request(s) have no quote after 3 days', v_signals->>'requests_unquoted_3d'); end if;
  if coalesce((v_signals->>'costs_month_aed')::numeric, 0) > coalesce((v_signals->>'cost_ceiling_month_aed')::numeric, 1e12) then
    v_matters := v_matters || format('costs this month AED %s are over the ceiling of AED %s', round((v_signals->>'costs_month_aed')::numeric), v_signals->>'cost_ceiling_month_aed');
  end if;

  insert into public.ceo_day (day, facts, priorities, matters)
  values (v_day, jsonb_build_object('verdict', v_verdict, 'plan', v_status, 'signals', v_signals, 'stuck', v_stuck), v_prio, v_matters)
  on conflict (day) do update set facts = excluded.facts, priorities = excluded.priorities,
    matters = coalesce((select array_agg(distinct m) from unnest(ceo_day.matters || excluded.matters) m), '{}'), updated_at = now();

  select note_handoff_id into v_note from public.ceo_day where day = v_day;
  if cardinality(v_matters) > 0 and v_note is null then
    v_body := 'Today, ' || to_char(v_day, 'Dy DD Mon') || E':\n- ' || array_to_string(v_matters, E'\n- ')
      || E'\n\nWhat the seats do about it:\n' || (select string_agg(format('- %s: %s', k, v->>'first'), E'\n' order by k) from jsonb_each(v_prio) x(k, v));
    v_note := public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'ceo_day', v_day::text,
      jsonb_build_object('recipient_role', 'founder', 'event', 'CEO daily note: ' || to_char(v_day, 'Dy DD Mon'), 'detail', left(v_body, 4000),
                         'level', 'info', 'kind', 'founder_brief', 'dedupe_key', 'ceo_day:' || v_day));
    update public.ceo_day set note_handoff_id = v_note where day = v_day;
  end if;
  return jsonb_build_object('day', v_day, 'misses', v_verdict->'misses', 'stuck_new', n_stuck_new, 'matters', to_jsonb(v_matters),
                            'note_handoff_id', v_note, 'priorities', v_prio, 'directives', v_dir);
end $function$;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.directive', 'ceo', interval '1 hour', 'fn_ceo_directive_run_now',
   'Directives from target misses, late deliverables, stuck handoffs and below-bar audits, each with a done-condition and a deadline; re-checked every hour, closed met with evidence, escalated once when late, then closed missed as a CEO task.',
   'scripts/sql/the_ceo_issues_directives_and_closes_them_on_their_own_condition.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
