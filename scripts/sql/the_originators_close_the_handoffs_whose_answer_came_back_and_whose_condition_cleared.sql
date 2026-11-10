-- THE ORIGINATORS CLOSE THE HANDOFFS WHOSE ANSWER CAME BACK AND WHOSE CONDITION IS MEASURED CLEARED.
-- Seat: ceo (the organisation; fn_ceo_closes_answered_handoffs is the CEO's own sweeper). The it_engineer owns
-- fn_it_close_cleared_handoffs (run by its safe-fix playbook, the_it_engineer_runs_the_safe_fix_playbooks_itself.sql).
-- customer_support's part is the_knowledge_request_duty_names_itself_when_it_closes_a_handoff.sql, scheduled in
-- MANIFEST.txt just before this file. 10 Nov 2026, founder ruling 1574 ("every seat must ACT, not just report").
--
-- MEASURED BEFORE WRITING (production htdblwldjkcgjvmqkbeh, read-only, 10 Nov 2026 02:20-03:30Z):
--   * it.finding handoffs pending with a reply: 226 to the ceo, 43 sales_engineer, 34 marketing, 33 customer_support,
--     30 accountant. 53 of them track an occurrence that is OVER (the finding closed, or it reopened as a later
--     occurrence with its own handoff): ceo 43, marketing 4, customer_support 3, sales_engineer 2, accountant 1. All 53
--     carry detail.awaiting_learning: fn_it_loop_reverify parks a cleared NEW BUG until its incident has a cause, a
--     fix, a regression check and a playbook class or not-automatable reason (trigger z62), and 53 of 53 incidents
--     lack the fix and the regression check (the model step that writes them did not). The design report's diagnosis
--     (the 1-second walk) is not what holds them: every one of them is walked and waits on z62 each tick.
--   * The CEO's own handoffs, answered and pending: 14 ceo.revise, 11 ceo.root_cause, 6 deliberation.review (to the
--     accountant), 5 ceo.month_directive (November, still running). Of the 11 root-cause asks 7 name a ceo_task that is
--     done; 2 more name a task of a month that has ended (29 Sep, 1 Oct). Of the 6 reviews, all 'reviewed' with a
--     recorded compare turn; 4 are about an experiment iteration that a later iteration replaced, 1 about an
--     experiment that left 'proposed' (running), 1 about a weekly forecast (target_forecast:2026-11-02).
--   * customer_support's 52 knowledge.request handoffs: 50 name a gap judged not_a_gap, 2 a gap still open. Every one
--     is stuck behind the duty's P0001 (8 failed runs since 1 Nov), fixed by the file before this one.
--
-- WHAT THIS FILE DOES (no business data is touched; every close records the reading it closed on):
--   1. public.originator_close_record: one row per handoff an originator closed by sweep, with the rule and reading.
--   2. fn_it_close_cleared_handoffs(p_limit): an it.finding whose occurrence is over and that has waited a full day
--      for its learning gets the learning the record supports, never invented: the cause already written (or "not
--      established"), "no seat applied a fix; the condition cleared: <the finding's close note>", the detector that
--      raised it as the regression check, and the matching it_playbook class or the plain statement that nothing ran.
--      fn_it_attach_learning then closes it (its own rule: the occurrence must be over).
--   3. fn_ceo_closes_answered_handoffs(): the CEO closes its own answered handoffs on a measured predicate only:
--        ceo.root_cause       the ceo_task is done/closed, or the month the miss belonged to has ended;
--        deliberation.review  (CEO-authored) the review is recorded AND its subject moved on: a later experiment
--                             iteration, an experiment that left 'proposed', or a later weekly forecast;
--        ceo.revise           the decision round moved on: a later round or generation was decided, or the item's
--                             last decision is approved / withdrawn / replaced;
--        ceo.month_directive  the month has ended (none today: November is running).
--      Never on age alone; a handoff whose predicate fails stays open with its reading.
--   4. Duty ceo.close_answered_handoffs (hourly).
-- New routines are revoked from public, anon and authenticated with a pinned search_path; the new table has RLS on
-- and a service-role-only policy, and is in the daily export registry.
--
-- Prevented by: scripts/checks/the_originators_close_the_handoffs_whose_answer_came_back.test.mjs (static rules plus
-- a rolled-back production replay: the sweep closes only measured-cleared handoffs and records each one).
--   node scripts/apply_sql.mjs scripts/sql/the_originators_close_the_handoffs_whose_answer_came_back_and_whose_condition_cleared.sql --apply --ddl --seat ceo

create table if not exists public.originator_close_record (
  id bigint generated always as identity primary key,
  seat text not null references public.org_role(role_id),
  handoff_id bigint not null,
  handoff_type text not null,
  rule text not null check (btrim(rule) <> ''),
  reading jsonb not null default '{}'::jsonb,
  closed_at timestamptz not null default now()
);
create index if not exists originator_close_record_handoff_idx on public.originator_close_record (handoff_id);
alter table public.originator_close_record enable row level security;
drop policy if exists originator_close_record_service_role_only on public.originator_close_record;
create policy originator_close_record_service_role_only on public.originator_close_record
  as permissive for all to public using (false) with check (false);
revoke all on public.originator_close_record from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('originator_close_record', true, 'decision',
   'one row per handoff an originating seat closed by sweep, with the rule and the reading it closed on (ruling 1574)', 'ceo')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason;

-- ── 2. THE IT ENGINEER CLOSES THE it.finding HANDOFFS WHOSE OCCURRENCE IS OVER ─────────────────────────────────
create or replace function public.fn_it_close_cleared_handoffs(p_limit integer default 200)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  h public.agent_actions; f public.it_engineer_finding; i public.it_incident; v_class text; v_cause text; v_fix text;
  v_rc text; v_nar text; v_r jsonb; n_closed int := 0; n_kept int := 0; n_err int := 0; v_errors jsonb := '[]'::jsonb;
begin
  for h in select a.* from public.agent_actions a
             left join public.it_engineer_finding f0 on f0.issue_key = a.detail->>'issue_key'
            where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.detail->>'from' = 'it_engineer'
              and a.status = 'pending' and a.detail ? 'replied_at'
              and (f0.issue_key is null or f0.closed_at is not null
                   or f0.started_at > (a.detail->>'occurrence_started_at')::timestamptz)
              -- the learning step had a full day to write it; this only writes what the record already holds
              and (a.detail->>'awaiting_learning')::timestamptz < now() - interval '24 hours'
              and coalesce(a.detail->>'issue_key', '') not ilike '%demo%'
            order by a.id limit greatest(1, least(coalesce(p_limit, 200), 500)) loop
    begin
      select * into f from public.it_engineer_finding where issue_key = h.detail->>'issue_key';
      select * into i from public.it_incident where handoff_id = h.id;
      if i.id is null then n_kept := n_kept + 1; continue; end if;     -- fn_it_loop_reverify closes a handoff with no incident
      select p.failure_class into v_class from public.it_playbook p
       where p.issue_prefix is not null and (h.detail->>'issue_key') like p.issue_prefix || '%'
       order by length(p.issue_prefix) desc limit 1;
      v_cause := coalesce(nullif(btrim(i.cause), ''),
        'Not established: the finding cleared before a cause was recorded. What was seen: ' || coalesce(f.title, h.detail->>'title', h.detail->>'issue_key') || '.');
      v_fix := coalesce(nullif(btrim(i.fix), ''),
        case when f.issue_key is not null and f.closed_at is null
             then 'No seat applied a fix to this occurrence. It ended when the finding reopened as a later occurrence (started '
                  || to_char(f.started_at, 'YYYY-MM-DD HH24:MI') || 'Z), which has its own handoff.'
             else 'No seat applied a fix. The condition cleared: ' || coalesce(f.close_note, 'the finding row no longer exists')
                  || coalesce(' (' || to_char(f.closed_at, 'YYYY-MM-DD HH24:MI') || 'Z).', '.') end);
      v_rc := coalesce(nullif(btrim(i.regression_check), ''),
        'The detector that raised it (' || coalesce(f.raised_by, f.where_it_is, 'its duty') || ') re-checks on its own clock and reopens '
          || (h.detail->>'issue_key') || ' if the condition returns.');
      v_nar := case when v_class is null and i.playbook_class is null then coalesce(nullif(btrim(i.not_automatable_reason), ''),
        'Nothing ran for this occurrence: it cleared on its own, so there was no remedy to automate. A recurrence is a new occurrence with its own handoff.') end;
      v_r := public.fn_it_attach_learning(h.id, v_cause, v_fix, v_rc, coalesce(i.playbook_class, v_class), v_nar, 'it_engineer');
      if coalesce((v_r->>'closed')::boolean, false) then
        insert into public.originator_close_record (seat, handoff_id, handoff_type, rule, reading)
        values ('it_engineer', h.id, 'it.finding', 'occurrence over; learning recorded from the record',
                jsonb_build_object('issue_key', h.detail->>'issue_key', 'finding_closed_at', f.closed_at, 'close_note', f.close_note,
                                   'finding_started_at', f.started_at, 'occurrence_started_at', h.detail->>'occurrence_started_at',
                                   'incident_id', i.id, 'playbook_class', coalesce(i.playbook_class, v_class),
                                   'wrote', jsonb_build_object('cause', i.cause is null or btrim(i.cause) = '', 'fix', i.fix is null or btrim(i.fix) = '',
                                                               'regression_check', i.regression_check is null or btrim(i.regression_check) = '')));
        update public.support_ceo_report
           set status = 'completed', completed_at = now(),
               completion_note = 'IT engineer re-verified: the occurrence is over and its learning is recorded (handoff ' || h.id || ').'
         where idempotency_key = 'it_loop:' || h.id and status = 'accepted';
        n_closed := n_closed + 1;
      else
        n_kept := n_kept + 1;
      end if;
    exception when others then
      n_err := n_err + 1;
      v_errors := v_errors || jsonb_build_object('handoff_id', h.id, 'error', left(sqlerrm, 300));
    end;
  end loop;
  return jsonb_build_object('closed', n_closed, 'kept', n_kept, 'errors', n_err, 'error_detail', v_errors);
end $fn$;
revoke execute on function public.fn_it_close_cleared_handoffs(integer) from public, anon, authenticated;

-- ── 3. THE CEO CLOSES ITS OWN ANSWERED HANDOFFS ON A MEASURED PREDICATE ─────────────────────────────────────────
create or replace function public.fn_ceo_closes_answered_handoffs()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  h public.agent_actions; t public.ceo_task; d public.seat_deliberation; e public.ceo_experiment; c public.seat_deliberation_turn;
  v_rule text; v_reading jsonb; v_month date := date_trunc('month', now() at time zone 'Asia/Dubai')::date;
  v_iter int; v_exp bigint; v_item text; v_gen int; v_round int; v_last record; v_kind text; v_period text;
  n_closed int := 0; n_kept int := 0; n_err int := 0; v_by jsonb := '{}'::jsonb; v_errors jsonb := '[]'::jsonb;
begin
  for h in select a.* from public.agent_actions a
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'from' = 'ceo' and a.detail ? 'replied_at'
              and a.detail->>'type' in ('ceo.root_cause', 'deliberation.review', 'ceo.revise', 'ceo.month_directive')
              and not coalesce((a.detail->>'demo')::boolean, false)
            order by a.id loop
    v_rule := null; v_reading := '{}'::jsonb;
    begin
      if h.detail->>'type' = 'ceo.root_cause' then
        select * into t from public.ceo_task where task_id = (case when h.detail->>'subject_id' ~ '^[0-9]+$' then (h.detail->>'subject_id')::bigint end);
        if t.task_id is not null and t.state in ('done', 'closed', 'cancelled') then
          v_rule := 'the target-miss task is ' || t.state;
          v_reading := jsonb_build_object('task_id', t.task_id, 'state', t.state, 'closed_at', t.closed_at);
        elsif coalesce(h.detail->>'day', '') ~ '^\d{4}-\d{2}-\d{2}$' and date_trunc('month', (h.detail->>'day')::date)::date < v_month then
          v_rule := 'the month the miss belonged to has ended';
          v_reading := jsonb_build_object('task_id', t.task_id, 'state', t.state, 'miss_day', h.detail->>'day', 'metric', h.detail->>'metric',
                                          'actual', h.detail->'actual', 'expected', h.detail->'expected', 'month_target', h.detail->'month_target');
        end if;
        if v_rule is not null then
          perform set_config('qd.handoff_closer', 'ceo', true);
          perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
            'kind', 'ceo.root_cause', 'verified_by', 'ceo', 'verified_at', now(), 'verdict', v_rule, 'reading', v_reading));
          perform set_config('qd.handoff_closer', '', true);
        end if;

      elsif h.detail->>'type' = 'deliberation.review' then
        select * into d from public.seat_deliberation
         where id = (case when h.detail->>'subject_id' ~ '^[0-9]+$' then (h.detail->>'subject_id')::bigint end);
        if d.id is not null and d.author_seat = 'ceo' and d.status in ('reviewed', 'no_independent_reviewer') then
          select * into c from public.seat_deliberation_turn x
           where x.deliberation_id = d.id and x.phase = 'compare' and x.status = 'recorded' order by x.round desc limit 1;
          if d.subject_table = 'ceo_experiment' and coalesce(d.subject_id, '') ~ '^[0-9]+:[0-9]+$' then
            v_exp := split_part(d.subject_id, ':', 1)::bigint; v_iter := split_part(d.subject_id, ':', 2)::int;
            select * into e from public.ceo_experiment where id = v_exp;
            if e.id is not null and (coalesce(e.iteration, 0) > v_iter or e.status <> 'proposed') then
              v_rule := case when coalesce(e.iteration, 0) > v_iter then 'the reviewed iteration was replaced by iteration ' || e.iteration
                             else 'the experiment left proposed: it is ' || e.status end;
              v_reading := jsonb_build_object('experiment_id', e.id, 'reviewed_iteration', v_iter, 'iteration', e.iteration, 'status', e.status);
            end if;
          elsif d.subject_table = 'ceo_review' and coalesce(d.subject_id, '') ~ '^[a-z_]+:\d{4}-\d{2}-\d{2}$' then
            v_kind := split_part(d.subject_id, ':', 1); v_period := split_part(d.subject_id, ':', 2);
            if exists (select 1 from public.ceo_review r where r.kind = v_kind and r.period::text > v_period) then
              v_rule := 'a later ' || v_kind || ' superseded the reviewed one';
              v_reading := jsonb_build_object('kind', v_kind, 'reviewed_period', v_period,
                'latest_period', (select max(r.period)::text from public.ceo_review r where r.kind = v_kind));
            end if;
          end if;
          if v_rule is not null then
            v_reading := v_reading || jsonb_build_object('deliberation_id', d.id, 'review_verdict', c.verdict, 'reviewer_model', c.model);
            perform public.fn_seat_deliberation_close(d.id, 'ceo',
              left('Review read: ' || coalesce(d.reviewer_seat, 'the reviewer') || ' answered "' || coalesce(c.verdict, 'no verdict') || '"'
                   || coalesce(' on ' || c.model, '') || '. Closed because ' || v_rule || '.', 2000));
            perform set_config('qd.handoff_closer', '', true);
          end if;
        end if;

      elsif h.detail->>'type' = 'ceo.revise' then
        v_item := h.detail->>'item_key'; v_gen := coalesce((h.detail->>'generation')::int, 1); v_round := coalesce((h.detail->>'round')::int, 1);
        select r.* into v_last from public.ceo_decision_round r where r.item_key = v_item order by r.generation desc, r.round desc limit 1;
        if v_last.id is not null and (v_last.generation > v_gen or (v_last.generation = v_gen and v_last.round > v_round)) then
          v_rule := 'the CEO decided a later round (generation ' || v_last.generation || ', round ' || v_last.round || ': ' || v_last.decision || ')';
        elsif v_last.id is not null and v_last.decision in ('approved', 'withdrawn', 'replaced') then
          v_rule := 'the item''s last decision is ' || v_last.decision;
        end if;
        if v_rule is not null then
          v_reading := jsonb_build_object('item_key', v_item, 'revise_generation', v_gen, 'revise_round', v_round,
                                          'last_round_id', v_last.id, 'last_decision', v_last.decision, 'decided_at', v_last.decided_at);
          perform set_config('qd.handoff_closer', 'ceo', true);
          perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
            'kind', 'ceo.revise', 'verified_by', 'ceo', 'verified_at', now(), 'verdict', v_rule, 'reading', v_reading));
          perform set_config('qd.handoff_closer', '', true);
        end if;

      elsif h.detail->>'type' = 'ceo.month_directive' then
        if coalesce(h.detail->>'month', '') ~ '^\d{4}-\d{2}-\d{2}$' and (h.detail->>'month')::date < v_month then
          v_rule := 'the month has ended';
          v_reading := jsonb_build_object('month', h.detail->>'month', 'targets', h.detail->'targets');
          perform set_config('qd.handoff_closer', 'ceo', true);
          perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
            'kind', 'ceo.month_directive', 'verified_by', 'ceo', 'verified_at', now(), 'verdict', v_rule, 'reading', v_reading));
          perform set_config('qd.handoff_closer', '', true);
        end if;
      end if;

      if v_rule is not null then
        insert into public.originator_close_record (seat, handoff_id, handoff_type, rule, reading)
        values ('ceo', h.id, h.detail->>'type', v_rule, v_reading);
        n_closed := n_closed + 1;
        v_by := jsonb_set(v_by, array[h.detail->>'type'], to_jsonb(coalesce((v_by->>(h.detail->>'type'))::int, 0) + 1));
      else
        n_kept := n_kept + 1;
      end if;
    exception when others then
      n_err := n_err + 1;
      v_errors := v_errors || jsonb_build_object('handoff_id', h.id, 'type', h.detail->>'type', 'error', left(sqlerrm, 300));
    end;
  end loop;
  return jsonb_build_object('closed', n_closed, 'closed_by_type', v_by, 'kept_open', n_kept, 'errors', n_err, 'error_detail', v_errors);
end $fn$;
revoke execute on function public.fn_ceo_closes_answered_handoffs() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.close_answered_handoffs', 'ceo', interval '1 hour', 'fn_ceo_closes_answered_handoffs',
   'The CEO closes its own answered handoffs (root cause, review, revise, month directive) once their condition is measured cleared: the task done or its month ended, the reviewed subject replaced, the round decided, the month over. Never on age. Ruling 1574.',
   'scripts/sql/the_originators_close_the_handoffs_whose_answer_came_back_and_whose_condition_cleared.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- ── VERDICT (read-only) ─────────────────────────────────────────────────────────────────────────────────────────
select case when problems is null then 'PROBE OK' else 'PROBE FAILED: ' || problems end as verdict from (
  select string_agg(p, '; ') problems from (
    select 'a routine is open or unpinned: ' || p.oid::regprocedure::text p from pg_proc p
     where p.oid in ('public.fn_it_close_cleared_handoffs(integer)'::regprocedure, 'public.fn_ceo_closes_answered_handoffs()'::regprocedure)
       and (not p.prosecdef or not coalesce(p.proconfig @> array['search_path=public, pg_temp'], false)
            or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
    union all select 'the record table is readable by a client'
     where has_table_privilege('anon', 'public.originator_close_record', 'select') or has_table_privilege('authenticated', 'public.originator_close_record', 'select')
    union all select 'the record table has no RLS policy'
     where not exists (select 1 from pg_policy where polrelid = 'public.originator_close_record'::regclass)
    union all select 'the duty is not registered' where not exists (select 1 from public.seat_duty where duty = 'ceo.close_answered_handoffs' and enabled)
  ) z) y;
