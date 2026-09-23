-- THE IT ENGINEER WATCHES SUPPLIER LICENCES AND EVERY SEAT'S KNOWLEDGE: EXAMS, THE PASS RATE, THE QUARTERLY REFRESH.
-- Seat: it_engineer. 23 Sep 2026, founder_instruction 898 (no new agents) and the seat-duties plan (rulings 886-898):
-- "LICENCE-EXPIRY WATCH (auto-remove from matching, notify supplier via support); knowledge pass-rate monitor;
-- quarterly refresh scheduler" and, for every seat, "per-seat knowledge pass-rate monitored (it_engineer raises
-- drops); quarterly knowledge refresh (each seat owns its pack; it_engineer schedules and verifies)".
-- Needs every_seat_duty_has_an_owner_a_clock_and_a_check.sql (public.seat_duty, fn_seat_duty_reason).
--
-- WHAT WAS MEASURED (production, 23 Sep 2026)
--   * Licences: fn_reconcile_doc_blocks pauses an approved supplier whose licence or insurance has expired and tells
--     him (run daily inside fn_sales_engineer_supplier_documents_tick). But fn_licence_expiry_sweep — the 30/14/7-day
--     renewal ask, email plus the WhatsApp twin — has NO caller: no supplier was ever asked BEFORE the pause. And
--     nothing re-checks the invariant "no expired supplier is matchable" independently of the routine that sets it.
--   * Knowledge: knowledge_exam_results holds 0 rows and canon_eval_runs 0; canon_eval_questions' 100 questions are
--     keyed to 16 retired role names, not to the six seats. No seat's knowledge has ever been examined, so a pass
--     rate did not exist to monitor. The packs (support 408, sales 1,192, accountant 113, it_engineer 79, ceo 508,
--     marketing 51+ in agent_knowledge) carry updated_at / imported_at and nothing schedules their refresh.
--
-- WHAT THIS ADDS — three duties, each with an owner, a clock and a check:
--   it_engineer.licence_expiry_watch (1 day): runs the renewal asks (fn_licence_expiry_sweep, deduped by
--     licence_renewal_ask's unique key), then MEASURES the invariant; an expired approved supplier still matchable is
--     paused on the spot through fn_reconcile_doc_blocks (which also tells him), re-measured, and any that remain
--     are a finding. Deterministic: dates, no judgement.
--   it_engineer.knowledge_exam (1 day): two items per seat not examined in 90 days are asked of the seat as a
--     think() question in the seat's own queue; the answer is graded by the it_engineer as a high-stakes think()
--     DECISION (correct / partial / wrong / not_covered) against the item — so a model of another family verifies
--     every grade. Nothing is graded by word overlap.
--   it_engineer.knowledge_pass_rate (1 day): per seat, the pass rate of the last 30 days against the 30 before. A
--     rate under 70 % or a drop of 10 points (on at least 5 graded answers) is raised: a finding, an it.finding
--     handoff to the seat, and the seat ACTS — every item it answered wrong or partially is filed for re-research
--     in its own queue. An exam that nobody could grade for a week while the model gate is open is a finding too.
--   it_engineer.knowledge_refresh (1 day): at the start of each quarter every seat's five stalest items are filed
--     in that seat's queue as research questions (think() reads the authoritative web and writes what changed back
--     as a pending knowledge candidate). The it_engineer verifies: a quarter's refresh not complete 45 days in is a
--     finding.
--
-- WHAT THIS DOES NOT DO: it does not rewrite a knowledge item. A refresh proposes (reasoning_knowledge_candidate,
-- pending review) and the seat's review adopts it, as for any researched fact. It does not change the pause/notice
-- wording of fn_reconcile_doc_blocks or fn_licence_expiry_sweep.

-- ── the seat's own knowledge, one shape for all six packs ────────────────────────────────────────────────
create or replace function public.fn_seat_knowledge_items(p_seat text)
returns table(item_key text, title text, content text, updated_at timestamptz)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select 'support_knowledge:' || record_id, title, body, imported_at from public.support_knowledge
   where p_seat = 'customer_support' and coalesce(runtime_index_eligible, true) and nullif(btrim(body), '') is not null
  union all
  select 'sales_knowledge:' || record_id, title, content, coalesce(updated_at, ingested_at) from public.sales_knowledge
   where p_seat = 'sales_engineer' and coalesce(runtime_index_eligible, true) and nullif(btrim(content), '') is not null
  union all
  select 'accountant_knowledge:' || record_id, title, content, coalesce(updated_at, ingested_at) from public.accountant_knowledge
   where p_seat = 'accountant' and coalesce(runtime_index_eligible, true) and nullif(btrim(content), '') is not null
  union all
  select 'it_engineer_knowledge:' || record_id, title, content, coalesce(updated_at, ingested_at) from public.it_engineer_knowledge
   where p_seat = 'it_engineer' and coalesce(runtime_index_eligible, true) and nullif(btrim(content), '') is not null
  union all
  select 'ceo_knowledge:' || record_id, title, body, imported_at from public.ceo_knowledge
   where p_seat = 'ceo' and coalesce(runtime_index_eligible, true) and nullif(btrim(body), '') is not null
  union all
  select 'agent_knowledge:' || id, topic, content, coalesce(updated_at, created_at) from public.agent_knowledge
   where p_seat = 'marketing' and agent_key like 'marketing%' and nullif(btrim(content), '') is not null;
$fn$;
revoke execute on function public.fn_seat_knowledge_items(text) from public, anon, authenticated;
grant execute on function public.fn_seat_knowledge_items(text) to service_role;

create table if not exists public.seat_knowledge_exam (
  id            bigserial primary key,
  seat          text not null references public.org_role (role_id),
  item_key      text not null,
  question      text not null check (btrim(question) <> ''),
  reference     text not null,
  asked_held_id bigint,
  answer        text,
  answer_model  text,
  grade_held_id bigint,
  verdict       text check (verdict in ('correct', 'partial', 'wrong', 'not_covered')),
  grade_reason  text,
  asked_at      timestamptz not null default now(),
  answered_at   timestamptz,
  graded_at     timestamptz,
  refiled_at    timestamptz
);
create index if not exists seat_knowledge_exam_seat_graded on public.seat_knowledge_exam (seat, graded_at);
create index if not exists seat_knowledge_exam_item on public.seat_knowledge_exam (seat, item_key, asked_at);
alter table public.seat_knowledge_exam enable row level security;
drop policy if exists seat_knowledge_exam_service_role_only on public.seat_knowledge_exam;
create policy seat_knowledge_exam_service_role_only on public.seat_knowledge_exam as permissive for all to public using (false) with check (false);
revoke all on public.seat_knowledge_exam from anon, authenticated;

create table if not exists public.seat_knowledge_refresh (
  seat         text not null references public.org_role (role_id),
  quarter      date not null check (quarter = date_trunc('quarter', quarter)::date),
  items        jsonb not null default '[]'::jsonb,   -- [{item_key, title, held_id, done_at}]
  opened_at    timestamptz not null default now(),
  verified_at  timestamptz,
  primary key (seat, quarter)
);
alter table public.seat_knowledge_refresh enable row level security;
drop policy if exists seat_knowledge_refresh_service_role_only on public.seat_knowledge_refresh;
create policy seat_knowledge_refresh_service_role_only on public.seat_knowledge_refresh as permissive for all to public using (false) with check (false);
revoke all on public.seat_knowledge_refresh from anon, authenticated;

-- ── 1. the licence-expiry watch ──────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_engineer_licence_expiry_watch()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_asks jsonb; v_before int; v_after int; v_fix json; v_ids jsonb;
  v_today date := (now() at time zone 'Asia/Dubai')::date;
begin
  v_asks := public.fn_licence_expiry_sweep(false);

  -- THE INVARIANT, measured here and not trusted to the routine that sets it: an approved supplier whose licence
  -- or insurance is past its date is not matchable (fn_is_matchable reads matching_blocked).
  select count(*) into v_before from public.leads l
   where l.approval_status = 'approved' and not coalesce(l.banned, false) and not coalesce(l.matching_blocked, false)
     and (l.license_expiry < v_today or l.insurance_expiry < v_today);
  if v_before > 0 then v_fix := public.fn_reconcile_doc_blocks(0); end if;   -- pauses them AND tells each supplier
  select count(*), coalesce(jsonb_agg(l.id order by l.id), '[]'::jsonb) into v_after, v_ids from public.leads l
   where l.approval_status = 'approved' and not coalesce(l.banned, false) and not coalesce(l.matching_blocked, false)
     and (l.license_expiry < v_today or l.insurance_expiry < v_today);

  if v_after > 0 then
    perform public.fn_it_engineer_finding_upsert('licence_expiry:matchable_after_expiry',
      v_after || ' approved supplier(s) with an expired licence or insurance are still matchable after the pause ran',
      'public.leads / fn_reconcile_doc_blocks', 'customer_facing', v_after, jsonb_build_object('lead_ids', v_ids, 'owner_seat', 'sales_engineer'),
      '{}'::text[], array['why fn_reconcile_doc_blocks skipped them (a manual block reason it will not overwrite?)'], 'it_engineer');
  else
    update public.it_engineer_finding set closed_at = now(), close_note = 'no expired supplier is matchable (licence_expiry_watch)'
     where issue_key = 'licence_expiry:matchable_after_expiry' and closed_at is null;
  end if;
  return jsonb_build_object('renewal_asks', v_asks - 'sample', 'expired_matchable_before', v_before,
                            'paused', v_fix, 'expired_matchable_after', v_after);
end $fn$;
revoke execute on function public.fn_it_engineer_licence_expiry_watch() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_licence_expiry_watch() to service_role;

-- ── 2. the exam ──────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_engineer_knowledge_exam(p_per_seat integer default 2)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare s text; i record; v_id bigint; v_q text; v_held bigint; v_n int := 0;
begin
  foreach s in array array['customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing', 'ceo'] loop
    for i in
      select k.item_key, k.title, k.content from public.fn_seat_knowledge_items(s) k
       where not exists (select 1 from public.seat_knowledge_exam e
                          where e.seat = s and e.item_key = k.item_key and e.asked_at > now() - interval '90 days')
       order by md5(k.item_key || current_date::text)          -- a different sample each day, reproducible within it
       limit greatest(1, least(coalesce(p_per_seat, 2), 5))
    loop
      v_q := 'Knowledge check for the ' || replace(s, '_', ' ') || ' seat. As the senior member of staff in this role, '
          || 'explain what we know and apply about: ' || coalesce(nullif(btrim(i.title), ''), left(i.content, 160));
      insert into public.seat_knowledge_exam (seat, item_key, question, reference)
      values (s, i.item_key, v_q, left(i.content, 6000)) returning id into v_id;
      -- Asked in the SEAT'S OWN queue, answered by think() from its own knowledge (no research: this measures what
      -- the seat already knows). Replayed the moment the model hold lifts.
      v_held := public.fn_reason_hold(s, s || '.knowledge_exam', v_q,
        jsonb_build_object('seat', s, 'surface', s || '.knowledge_exam', 'question', v_q,
          'context', jsonb_build_object('audience', 'internal'), 'research', false, 'stakes', 'normal',
          'subject', jsonb_build_object('exam_id', v_id), 'dedupeKey', 'kexam:' || v_id),
        jsonb_build_object('filed_by', 'it_engineer.knowledge_exam'), jsonb_build_object('exam_id', v_id), 'seat_duty', 'kexam:' || v_id);
      update public.seat_knowledge_exam set asked_held_id = v_held where id = v_id;
      v_n := v_n + 1;
    end loop;
  end loop;
  return jsonb_build_object('asked', v_n);
end $fn$;
revoke execute on function public.fn_it_engineer_knowledge_exam(integer) from public, anon, authenticated;
grant execute on function public.fn_it_engineer_knowledge_exam(integer) to service_role;

create or replace function public.fn_it_engineer_duty_knowledge_exam()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_it_engineer_knowledge_exam(2) $fn$;
revoke execute on function public.fn_it_engineer_duty_knowledge_exam() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_duty_knowledge_exam() to service_role;

-- The seat answered: record it, and file the grade as the it_engineer's high-stakes DECISION.
create or replace function public.fn_it_engineer_knowledge_exam_answered(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; e public.seat_knowledge_exam; v_grade bigint;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  select * into e from public.seat_knowledge_exam where id = (r.subject->>'exam_id')::bigint for update;
  if not found then return jsonb_build_object('applied', false, 'reason', 'no exam row'); end if;
  if e.answered_at is not null then return jsonb_build_object('applied', true, 'already', e.id); end if;
  update public.seat_knowledge_exam set answer = left(coalesce(p_result->>'answer', ''), 6000), answer_model = p_result->>'model',
         answered_at = now() where id = e.id;
  v_grade := public.fn_seat_duty_reason('it_engineer', 'it_engineer.knowledge_grade',
    'Grade a seat''s answer against the reference knowledge item it was examined on. Judge the MEANING: does the '
      || 'answer state what the reference states, without contradicting it? Wording does not matter.',
    ('[{"id":"correct","meaning":"the answer states the substance of the reference and contradicts nothing in it"},'
    || '{"id":"partial","meaning":"the answer is right as far as it goes but misses a material part of the reference"},'
    || '{"id":"wrong","meaning":"the answer contradicts the reference or states something materially false"},'
    || '{"id":"not_covered","meaning":"the answer does not address the subject of the reference, or declines to"}]')::jsonb,
    jsonb_build_object('seat', e.seat, 'question', e.question, 'reference', left(e.reference, 3000),
                       'answer', left(coalesce(p_result->>'answer', ''), 3000)),
    jsonb_build_object('exam_id', e.id), 'kgrade:' || e.id);
  update public.seat_knowledge_exam set grade_held_id = v_grade where id = e.id;
  return jsonb_build_object('applied', true, 'exam_id', e.id, 'grade_held_id', v_grade);
end $fn$;
revoke execute on function public.fn_it_engineer_knowledge_exam_answered(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_it_engineer_knowledge_exam_answered(bigint, jsonb) to service_role;

-- fn_reason_held_resolve dispatches on the surface: one door per seat, all the same exam.
create or replace function public.fn_reason_apply_customer_support__knowledge_exam(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_it_engineer_knowledge_exam_answered(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_customer_support__knowledge_exam(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_sales_engineer__knowledge_exam(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_it_engineer_knowledge_exam_answered(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_sales_engineer__knowledge_exam(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_accountant__knowledge_exam(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_it_engineer_knowledge_exam_answered(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_accountant__knowledge_exam(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_it_engineer__knowledge_exam(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_it_engineer_knowledge_exam_answered(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_it_engineer__knowledge_exam(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_marketing__knowledge_exam(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_it_engineer_knowledge_exam_answered(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_marketing__knowledge_exam(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_ceo__knowledge_exam(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_it_engineer_knowledge_exam_answered(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_ceo__knowledge_exam(bigint, jsonb) from public, anon, authenticated;

-- The grade, reasoned and verified by another family.
create or replace function public.fn_reason_apply_it_engineer__knowledge_grade(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice';
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if v_choice is null or not exists (select 1 from jsonb_array_elements(r.request->'decision'->'options') o where o->>'id' = v_choice) then
    -- fn_reason_held_resolve marks a row applied whenever its apply returns (even null), so an answer that is not one of
    -- the options RAISES: the resolve rolls back and the grade is reasoned again on a later replay.
    raise exception 'CHOICE_NOT_AN_OPTION: % is not a grade (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  update public.seat_knowledge_exam set verdict = v_choice, grade_reason = left(coalesce(p_result->>'answer', ''), 1000), graded_at = now()
   where id = (r.subject->>'exam_id')::bigint and graded_at is null;
  return jsonb_build_object('applied', true, 'exam_id', r.subject->>'exam_id', 'verdict', v_choice);
end $fn$;
revoke execute on function public.fn_reason_apply_it_engineer__knowledge_grade(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_it_engineer__knowledge_grade(bigint, jsonb) to service_role;

-- ── 3. the pass-rate monitor ─────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_engineer_knowledge_pass_rate()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare s record; v_out jsonb := '[]'::jsonb; v_raised int := 0; v_refiled int := 0; e record; v_gate jsonb; v_open boolean;
begin
  v_gate := public.fn_kernel_paid_provider_gate('hold-probe/not-a-model');
  v_open := coalesce(v_gate->>'rule', '') not in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state');
  for s in
    select seat,
           count(*) filter (where graded_at > now() - interval '30 days') as n30,
           count(*) filter (where graded_at > now() - interval '30 days' and verdict = 'correct') as ok30,
           count(*) filter (where graded_at <= now() - interval '30 days' and graded_at > now() - interval '60 days') as nprev,
           count(*) filter (where graded_at <= now() - interval '30 days' and graded_at > now() - interval '60 days' and verdict = 'correct') as okprev,
           count(*) filter (where graded_at is null and asked_at < now() - interval '7 days') as ungraded_week
      from public.seat_knowledge_exam group by seat
  loop
    declare r30 numeric := case when s.n30 > 0 then round(s.ok30::numeric / s.n30, 3) end;
            rprev numeric := case when s.nprev > 0 then round(s.okprev::numeric / s.nprev, 3) end;
            v_bad boolean;
    begin
      v_bad := s.n30 >= 5 and (r30 < 0.70 or (rprev is not null and s.nprev >= 5 and rprev - r30 >= 0.10));
      v_out := v_out || jsonb_build_object('seat', s.seat, 'rate_30d', r30, 'graded_30d', s.n30, 'rate_prev_30d', rprev, 'raised', v_bad);
      if v_bad then
        v_raised := v_raised + 1;
        perform public.fn_it_engineer_finding_upsert('knowledge_pass_rate:' || s.seat,
          'The ' || s.seat || ' seat''s knowledge pass rate is ' || round(r30 * 100) || '% over the last 30 days'
            || case when rprev is not null then ' (was ' || round(rprev * 100) || '%)' else '' end,
          'public.seat_knowledge_exam', 'agent_facing', (s.n30 - s.ok30)::int,
          jsonb_build_object('seat', s.seat, 'rate_30d', r30, 'rate_prev_30d', rprev, 'graded_30d', s.n30, 'owner_seat', s.seat),
          '{}'::text[], array['which items it answered wrong and why'], 'it_engineer');
        perform public.fn_seat_handoff('it_engineer', s.seat, 'it.finding', 'seat_knowledge_exam',
          'knowledge_pass_rate:' || s.seat || ':' || to_char(now(), 'IYYY-IW'),
          jsonb_build_object('duty', 'knowledge_pass_rate', 'issue_key', 'knowledge_pass_rate:' || s.seat, 'subject', s.seat || ' knowledge',
                             'title', 'Your knowledge pass rate dropped to ' || round(r30 * 100) || '%; the items you missed are filed for re-research'));
        -- THE SEAT ACTS: every item it missed in the window is re-researched in its own queue.
        for e in select * from public.seat_knowledge_exam
                  where seat = s.seat and verdict in ('wrong', 'partial', 'not_covered') and graded_at > now() - interval '30 days' and refiled_at is null loop
          perform public.fn_reason_hold(e.seat, e.seat || '.knowledge_refresh',
            'Re-research and correct our knowledge on: ' || e.question || ' — the answer given was graded ' || e.verdict || '.',
            jsonb_build_object('seat', e.seat, 'surface', e.seat || '.knowledge_refresh',
              'question', 'Re-research and correct our knowledge on: ' || e.question, 'research', true, 'stakes', 'high',
              'context', jsonb_build_object('audience', 'internal', 'case', jsonb_build_object('reference', left(e.reference, 2000), 'grade', e.grade_reason)),
              'subject', jsonb_build_object('item_key', e.item_key, 'exam_id', e.id), 'dedupeKey', 'krefile:' || e.id),
            jsonb_build_object('filed_by', 'it_engineer.knowledge_pass_rate'), jsonb_build_object('item_key', e.item_key, 'exam_id', e.id),
            'seat_duty', 'krefile:' || e.id);
          update public.seat_knowledge_exam set refiled_at = now() where id = e.id;
          v_refiled := v_refiled + 1;
        end loop;
      else
        update public.it_engineer_finding set closed_at = now(), close_note = 'pass rate back within bounds (knowledge_pass_rate)'
         where issue_key = 'knowledge_pass_rate:' || s.seat and closed_at is null;
      end if;
      -- An exam nobody could grade for a week WHILE a model can reason is a broken monitor, not a quiet one.
      if v_open and s.ungraded_week > 0 then
        perform public.fn_it_engineer_finding_upsert('knowledge_pass_rate:unmeasured:' || s.seat,
          s.ungraded_week || ' knowledge exam(s) of ' || s.seat || ' asked over a week ago are still ungraded while the model gate is open',
          'public.seat_knowledge_exam / reasoning_held_question', 'agent_facing', s.ungraded_week::int,
          jsonb_build_object('seat', s.seat), '{}'::text[], array['whether the replay or the apply fails'], 'it_engineer');
      else
        update public.it_engineer_finding set closed_at = now(), close_note = 'exams are being graded (or the model hold explains it)'
         where issue_key = 'knowledge_pass_rate:unmeasured:' || s.seat and closed_at is null;
      end if;
    end;
  end loop;
  return jsonb_build_object('seats', v_out, 'raised', v_raised, 'refiled', v_refiled, 'model_gate_open', v_open);
end $fn$;
revoke execute on function public.fn_it_engineer_knowledge_pass_rate() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_knowledge_pass_rate() to service_role;

-- ── 4. the quarterly refresh ─────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_engineer_knowledge_refresh()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare s text; i record; v_q date := date_trunc('quarter', (now() at time zone 'Asia/Dubai'))::date; v_items jsonb; v_held bigint;
  v_opened int := 0; v_verified int := 0; v_overdue int := 0; f record; v_text text;
begin
  foreach s in array array['customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing', 'ceo'] loop
    if not exists (select 1 from public.seat_knowledge_refresh where seat = s and quarter = v_q) then
      v_items := '[]'::jsonb;
      for i in select k.item_key, k.title, k.content from public.fn_seat_knowledge_items(s) k
                order by k.updated_at nulls first, k.item_key limit 5 loop
        v_text := 'Quarterly knowledge refresh (' || to_char(v_q, 'YYYY "Q"Q') || '). Is this still correct and current in the '
               || 'UAE today? Check the authoritative source and state precisely what has changed, if anything. Item: '
               || coalesce(i.title, '') || E'\n' || left(i.content, 1500);
        v_held := public.fn_reason_hold(s, s || '.knowledge_refresh', v_text,
          jsonb_build_object('seat', s, 'surface', s || '.knowledge_refresh', 'question', v_text, 'research', true, 'stakes', 'high',
            'context', jsonb_build_object('audience', 'internal'),
            'subject', jsonb_build_object('item_key', i.item_key, 'quarter', v_q), 'dedupeKey', 'krefresh:' || v_q || ':' || i.item_key),
          jsonb_build_object('filed_by', 'it_engineer.knowledge_refresh'), jsonb_build_object('item_key', i.item_key, 'quarter', v_q),
          'seat_duty', 'krefresh:' || v_q || ':' || i.item_key);
        v_items := v_items || jsonb_build_object('item_key', i.item_key, 'title', left(i.title, 200), 'held_id', v_held, 'done_at', null);
      end loop;
      insert into public.seat_knowledge_refresh (seat, quarter, items) values (s, v_q, v_items);
      v_opened := v_opened + 1;
    end if;
  end loop;

  -- VERIFY: a quarter is refreshed when every item it filed was reasoned (the apply stamps done_at).
  update public.seat_knowledge_refresh r set verified_at = now()
   where verified_at is null and jsonb_array_length(items) > 0
     and not exists (select 1 from jsonb_array_elements(r.items) x where x->>'done_at' is null);
  get diagnostics v_verified = row_count;
  for f in select * from public.seat_knowledge_refresh where verified_at is null and opened_at < now() - interval '45 days' loop
    v_overdue := v_overdue + 1;
    perform public.fn_it_engineer_finding_upsert('knowledge_refresh:' || f.seat || ':' || f.quarter,
      'The ' || f.seat || ' seat''s knowledge refresh for ' || to_char(f.quarter, 'YYYY "Q"Q') || ' is not complete after 45 days',
      'public.seat_knowledge_refresh', 'agent_facing',
      (select count(*)::int from jsonb_array_elements(f.items) x where x->>'done_at' is null),
      jsonb_build_object('seat', f.seat, 'quarter', f.quarter, 'owner_seat', f.seat), '{}'::text[],
      array['whether the model hold or a failing research step keeps the questions held'], 'it_engineer');
  end loop;
  update public.it_engineer_finding fi set closed_at = now(), close_note = 'the quarter''s refresh completed'
   where fi.issue_key like 'knowledge_refresh:%' and fi.closed_at is null
     and exists (select 1 from public.seat_knowledge_refresh r
                  where 'knowledge_refresh:' || r.seat || ':' || r.quarter = fi.issue_key and r.verified_at is not null);
  return jsonb_build_object('quarter', v_q, 'opened', v_opened, 'verified', v_verified, 'overdue', v_overdue);
end $fn$;
revoke execute on function public.fn_it_engineer_knowledge_refresh() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_knowledge_refresh() to service_role;

-- A refresh question was reasoned (its research proposed what changed as a pending candidate): stamp it done.
create or replace function public.fn_it_engineer_knowledge_refreshed(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_n int;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if (r.subject->>'quarter') is null then
    -- a re-research filed by the pass-rate monitor: the exam row carries it
    return jsonb_build_object('applied', true, 'refiled_exam', r.subject->>'exam_id', 'sources', jsonb_array_length(coalesce(p_result->'sources', '[]'::jsonb)));
  end if;
  update public.seat_knowledge_refresh k
     set items = (select jsonb_agg(case when x->>'item_key' = r.subject->>'item_key' and x->>'done_at' is null
                                        then x || jsonb_build_object('done_at', now(), 'sources', jsonb_array_length(coalesce(p_result->'sources', '[]'::jsonb)))
                                        else x end order by o)
                    from jsonb_array_elements(k.items) with ordinality t(x, o))
   where k.seat = r.seat and k.quarter = (r.subject->>'quarter')::date;
  get diagnostics v_n = row_count;
  return jsonb_build_object('applied', v_n > 0, 'item_key', r.subject->>'item_key');
end $fn$;
revoke execute on function public.fn_it_engineer_knowledge_refreshed(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_it_engineer_knowledge_refreshed(bigint, jsonb) to service_role;

create or replace function public.fn_reason_apply_customer_support__knowledge_refresh(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_it_engineer_knowledge_refreshed(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_customer_support__knowledge_refresh(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_sales_engineer__knowledge_refresh(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_it_engineer_knowledge_refreshed(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_sales_engineer__knowledge_refresh(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_accountant__knowledge_refresh(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_it_engineer_knowledge_refreshed(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_accountant__knowledge_refresh(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_it_engineer__knowledge_refresh(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_it_engineer_knowledge_refreshed(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_it_engineer__knowledge_refresh(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_marketing__knowledge_refresh(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_it_engineer_knowledge_refreshed(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_marketing__knowledge_refresh(bigint, jsonb) from public, anon, authenticated;
create or replace function public.fn_reason_apply_ceo__knowledge_refresh(p_id bigint, p_result jsonb)
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_it_engineer_knowledge_refreshed(p_id, p_result) $fn$;
revoke execute on function public.fn_reason_apply_ceo__knowledge_refresh(bigint, jsonb) from public, anon, authenticated;

-- ── the clock ────────────────────────────────────────────────────────────────────────────────────────────
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('it_engineer.licence_expiry_watch', 'it_engineer', interval '1 day', 'fn_it_engineer_licence_expiry_watch',
   'Renewal asks at 30/14/7 days; no expired approved supplier stays matchable (paused and told through fn_reconcile_doc_blocks).',
   'scripts/sql/the_it_engineer_watches_licences_and_every_seats_knowledge.sql'),
  ('it_engineer.knowledge_exam', 'it_engineer', interval '1 day', 'fn_it_engineer_duty_knowledge_exam',
   'Two items per seat asked of the seat by think(); each answer graded by a high-stakes reasoned decision.',
   'scripts/sql/the_it_engineer_watches_licences_and_every_seats_knowledge.sql'),
  ('it_engineer.knowledge_pass_rate', 'it_engineer', interval '1 day', 'fn_it_engineer_knowledge_pass_rate',
   'Per-seat pass rate, 30 days against the 30 before; a drop is raised to the seat, whose missed items are re-researched.',
   'scripts/sql/the_it_engineer_watches_licences_and_every_seats_knowledge.sql'),
  ('it_engineer.knowledge_refresh', 'it_engineer', interval '1 day', 'fn_it_engineer_knowledge_refresh',
   'Each quarter, every seat''s five stalest items are re-researched in its own queue; not complete in 45 days is a finding.',
   'scripts/sql/the_it_engineer_watches_licences_and_every_seats_knowledge.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
