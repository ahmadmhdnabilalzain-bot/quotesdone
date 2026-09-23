-- EVERY SEAT DUTY HAS AN OWNER, A CLOCK AND A CHECK THAT FAILS WHEN IT BREAKS.
-- Seat: it_engineer (shared platform). 23 Sep 2026, founder_instruction 898 ("no new agents": the extra duties go
-- to the six seats that exist) and the seat-duties plan of the same day (rulings 886-898).
--
-- WHAT WAS MEASURED (23 Sep 2026, production):
--   * cron.job holds ONE row (wa_flush). Every seat's periodic work runs as a resilience_ping step
--     (public.resilience_step, 35 rows) or as an it_duty_schedule row (12, all owner_seat = it_engineer, one of them
--     a sales_engineer duty filed under it_engineer). There is no place where a duty of the accountant, the CEO,
--     customer support, the sales engineer or marketing is registered WITH ITS OWNER and its interval, so "which
--     seat does this and when did it last succeed" had no answer in the database.
--   * fn_licence_expiry_sweep has no caller at all; fn_supplier_score_refresh has none either. Both were written and
--     never put on a clock. A routine without a clock is the failure this file exists to make visible.
--
-- WHAT THIS ADDS
--   1. public.seat_duty — the register: duty key '<seat>.<name>', owner seat (an active org_role), interval, the
--      routine that performs it (fn_*() returns jsonb), the file that owns it, and the run record (last start,
--      last success, last result, consecutive failures).
--   2. fn_seat_duties_tick() — the clock. resilience_ping runs it (step 'seatDuties', every 15 minutes). Each due
--      duty runs in its own sub-transaction: one duty's error rolls back that duty only, is recorded on its row,
--      and never stops the others.
--   3. fn_seat_duty_health() — the check. A duty that is overdue (no success within twice its interval, plus a
--      tick), failing three times running, whose routine does not exist or whose owner is not an active seat is a
--      problem. The tick files each as an it_engineer finding 'seat_duty:<duty>' and closes it when it recovers;
--      scripts/checks/seat_duties_run_on_their_clock.test.mjs fails CI on any problem in production.
--   4. fn_seat_duty_reason() — how a duty asks for a JUDGEMENT. Never a keyword, never a word list (founder_instruction
--      890): the question is filed in the owning seat's reasoning queue (fn_reason_hold) as a think() decision with
--      stakes 'high', so a model of another family verifies it (think.ts step f). Under the model hold it waits and
--      is reasoned the moment the hold lifts; fn_reason_held_resolve then applies it through
--      fn_reason_apply_<seat>__<name>. The deterministic part of a duty never waits on it.
--   5. fn_seat_duty_cross_review() — every SEAT-TO-SEAT judgement is reviewed by the other seat on a model of
--      another family: it opens a seat_deliberation (a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql)
--      authored on the model that reasoned it. A refusal (an unregistered pair, an unproven author model) is
--      returned and recorded, never raised into the caller.
--
-- WHAT THIS DOES NOT DO: it registers no duty. Each seat's duties are registered by the file that builds them
-- (seat_duty.owner_file), so an auditor reads a duty and its routine in one place.

create table if not exists public.seat_duty (
  duty             text primary key check (duty ~ '^[a-z_]+\.[a-z_]+$'),
  owner_seat       text not null references public.org_role (role_id),
  every            interval not null check (every >= interval '5 minutes'),
  routine          text not null check (routine ~ '^fn_[a-z0-9_]+$'),
  what             text not null check (btrim(what) <> ''),
  owner_file       text not null check (owner_file ~ '^scripts/sql/[a-z0-9_]+\.sql$'),
  enabled          boolean not null default true,
  last_started_at  timestamptz,
  last_ok_at       timestamptz,
  last_result      jsonb,
  last_error       text,
  failures         integer not null default 0,
  created_at       timestamptz not null default now(),
  check (split_part(duty, '.', 1) = owner_seat)
);
alter table public.seat_duty enable row level security;
drop policy if exists seat_duty_service_role_only on public.seat_duty;
create policy seat_duty_service_role_only on public.seat_duty as permissive for all to public using (false) with check (false);
revoke all on public.seat_duty from anon, authenticated;

-- ── the clock ────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_seat_duties_tick(p_limit integer default 8)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare d public.seat_duty; v_res jsonb; v_out jsonb := '[]'::jsonb; v_health jsonb; p jsonb;
begin
  for d in
    select * from public.seat_duty
     where enabled
       -- two minutes of tolerance, the same reasoning as fn_resilience_tick_plan: a tick is never exactly on the beat
       and (last_started_at is null or now() - last_started_at >= every - interval '2 minutes')
     order by last_started_at nulls first, duty
     limit greatest(1, least(coalesce(p_limit, 8), 30))
     for update skip locked
  loop
    update public.seat_duty set last_started_at = now() where duty = d.duty;
    begin
      if to_regprocedure(format('public.%I()', d.routine)) is null then
        raise exception 'routine public.%() does not exist', d.routine;
      end if;
      execute format('select public.%I()', d.routine) into v_res;
      update public.seat_duty set last_ok_at = now(), last_result = v_res, last_error = null, failures = 0 where duty = d.duty;
      v_out := v_out || jsonb_build_object('duty', d.duty, 'ok', true);
    exception when others then
      update public.seat_duty set last_error = left(sqlerrm, 1000), failures = failures + 1 where duty = d.duty;
      v_out := v_out || jsonb_build_object('duty', d.duty, 'ok', false, 'error', left(sqlerrm, 300));
    end;
  end loop;

  -- The check, every tick: each problem is a finding; a duty that recovered closes its own.
  v_health := public.fn_seat_duty_health();
  for p in select * from jsonb_array_elements(v_health) loop
    perform public.fn_it_engineer_finding_upsert(
      'seat_duty:' || (p->>'duty'),
      'Seat duty ' || (p->>'duty') || ' is not being done: ' || (p->>'problem'),
      'public.seat_duty / ' || coalesce(p->>'routine', '?'), 'agent_facing', 1, p,
      '{}'::text[], array['why the routine fails or is not reached'], 'it_engineer');
  end loop;
  update public.it_engineer_finding f
     set closed_at = now(), close_note = 'the duty is no longer overdue or failing: it ran on its clock again, or it was disabled (fn_seat_duties_tick)'
   where f.issue_key like 'seat_duty:%' and f.closed_at is null
     and not exists (select 1 from jsonb_array_elements(v_health) h where 'seat_duty:' || (h->>'duty') = f.issue_key);
  return jsonb_build_object('ran', v_out, 'problems', jsonb_array_length(v_health));
end $fn$;
revoke execute on function public.fn_seat_duties_tick(integer) from public, anon, authenticated;
grant execute on function public.fn_seat_duties_tick(integer) to service_role;

-- ── the check ────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_seat_duty_health()
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('duty', d.duty, 'owner_seat', d.owner_seat, 'routine', d.routine,
           'problem', x.problem, 'last_ok_at', d.last_ok_at, 'failures', d.failures, 'last_error', d.last_error)
           order by d.duty), '[]'::jsonb)
    from public.seat_duty d
    cross join lateral (select case
        when to_regprocedure(format('public.%I()', d.routine)) is null then 'its routine public.' || d.routine || '() does not exist'
        when not exists (select 1 from public.org_role r where r.role_id = d.owner_seat and r.status = 'active')
          then 'its owner ' || d.owner_seat || ' is not an active seat'
        when d.failures >= 3 then 'failed ' || d.failures || ' times running: ' || coalesce(left(d.last_error, 200), '?')
        -- overdue: no success within twice the interval plus one 15-minute tick (a new row gets the same grace)
        when coalesce(d.last_ok_at, d.created_at) < now() - (2 * d.every) - interval '15 minutes'
          then 'no successful run since ' || coalesce(to_char(d.last_ok_at, 'YYYY-MM-DD HH24:MI'), 'it was registered')
      end as problem) x
   where d.enabled and x.problem is not null;
$fn$;
revoke execute on function public.fn_seat_duty_health() from public, anon, authenticated;
grant execute on function public.fn_seat_duty_health() to service_role;

-- ── a judgement is reasoned, never matched ───────────────────────────────────────────────────────
-- p_options: [{"id":"...","meaning":"..."}] — think() picks exactly one. p_case: the facts it decides on.
create or replace function public.fn_seat_duty_reason(p_seat text, p_surface text, p_question text, p_options jsonb,
  p_case jsonb, p_subject jsonb, p_dedupe_key text)
returns bigint
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if split_part(p_surface, '.', 1) <> p_seat then
    raise exception 'a duty''s decision point belongs to its seat: % is not %''s', p_surface, p_seat;
  end if;
  if jsonb_typeof(p_options) <> 'array' or jsonb_array_length(p_options) < 2 then
    raise exception 'a decision needs at least two options (%).', p_surface;
  end if;
  if coalesce(btrim(p_dedupe_key), '') = '' then raise exception 'a duty''s question needs a dedupe key (%)', p_surface; end if;
  return public.fn_reason_hold(p_seat, p_surface, p_question,
    jsonb_build_object('seat', p_seat, 'surface', p_surface, 'question', left(p_question, 8000),
      'context', jsonb_build_object('audience', 'internal', 'case', coalesce(p_case, '{}'::jsonb)),
      'decision', jsonb_build_object('name', p_surface, 'options', p_options),
      'stakes', 'high', 'research', false, 'subject', coalesce(p_subject, '{}'::jsonb), 'dedupeKey', p_dedupe_key),
    jsonb_build_object('pending', jsonb_build_array('decompose', 'resolve', 'retrieve', 'decide', 'verify'), 'filed_by', 'seat_duty'),
    coalesce(p_subject, '{}'::jsonb), 'seat_duty', p_dedupe_key);
end $fn$;
revoke execute on function public.fn_seat_duty_reason(text, text, text, jsonb, jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.fn_seat_duty_reason(text, text, text, jsonb, jsonb, jsonb, text) to service_role;

-- ── a seat-to-seat judgement is reviewed across families ─────────────────────────────────────────
-- Called from a fn_reason_apply_* once think() answered: p_result is its ThinkResult, whose `model` wrote the
-- decision on task class agent_reasoning (think.ts taskClassFor), which is what fn_seat_deliberation_open proves.
create or replace function public.fn_seat_duty_cross_review(p_kind text, p_author text, p_reviewer text, p_question text,
  p_evidence jsonb, p_proposal jsonb, p_result jsonb, p_subject_table text, p_subject_id text)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_id bigint; v_demo boolean := coalesce(p_question like 'ZZ DEMO%', false);
begin
  v_id := public.fn_seat_deliberation_open(p_kind, p_author, p_reviewer, p_question, p_evidence, p_proposal,
            coalesce(nullif(p_result->>'model', ''), 'unknown'), 'agent_reasoning', p_subject_table, p_subject_id, v_demo);
  return jsonb_build_object('deliberation_id', v_id, 'reviewer', p_reviewer);
exception when others then
  -- Recorded for the CEO to see, never raised: the decision it reviews has already been applied or held.
  perform public.fn_it_engineer_finding_upsert('cross_review:' || p_kind || ':' || coalesce(p_subject_id, '?'),
    'A cross-family review could not be opened for ' || p_kind, 'public.fn_seat_duty_cross_review', 'agent_facing', 1,
    jsonb_build_object('error', left(sqlerrm, 500), 'author', p_author, 'reviewer', p_reviewer, 'owner_seat', 'ceo'),
    '{}'::text[], array['whether the author model was proven and the pair registered'], p_author);
  return jsonb_build_object('deliberation_id', null, 'error', left(sqlerrm, 300));
end $fn$;
revoke execute on function public.fn_seat_duty_cross_review(text, text, text, text, jsonb, jsonb, jsonb, text, text) from public, anon, authenticated;
grant execute on function public.fn_seat_duty_cross_review(text, text, text, text, jsonb, jsonb, jsonb, text, text) to service_role;

-- ── on resilience_ping's plan ────────────────────────────────────────────────────────────────────
insert into public.resilience_step (step, every, budget_ms, place, note, owner_seat)
values ('seatDuties', interval '15 minutes', 6000, 'plan',
        'every registered seat duty on its own interval (public.seat_duty, fn_seat_duties_tick)', 'it_engineer')
on conflict (step) do update set every = excluded.every, note = excluded.note, owner_seat = excluded.owner_seat;
