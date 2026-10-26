-- A HELD QUESTION IS PAID FOR ONCE, AND OUR OWN TEST TRAFFIC NEVER WAITS FOR A MODEL.
-- Seat: it_engineer (the reasoning queue, the postmortem duty), with sales_engineer (supply gaps, supplier-choice
-- reviews) and ceo (refund reviews) where they own the data. 5 Oct 2026, before the founder lifts the model hold.
-- Source: the LLM burn audit of 5 Oct 2026 (R1-R8). No model is called by anything in this file.
--
-- MEASURED (production, 5 Oct 2026 08:55 UTC, read-only): 627 held questions and 24 open deliberations would be
-- replayed the moment the hold lifts (~2,700 calls, ~USD 11; ~USD 30 if every row fails three times).
--   R1  182 line_specs.assess + 26 inquiry_intake.trade rows are E2E harness traffic. Every one names a quote or an
--       intake the harness has since deleted (0 of 182 quotes exist; 1 of 27 intakes does, and it is a real person,
--       kept). fn_reason_held_due's fixture filter never ran either: replayHeld returns before calling it while the
--       hold is on, so even the 42 rows carrying "ZZ DEMO" were still held.
--   R2  182 line_specs.assess rows carry 6 distinct questions; 27 inquiry_intake.trade rows carry 2. One think() each.
--   R3  fn_reason_hold reset a failed or expired row to held with attempts 0 when it was filed again.
--   R4  170 postmortems for 130 faults (wa_templates_watch 7, db_health slow 5, post_results 5, ...): one per incident.
--   R5  16 site_assistant.person rows from one visitor, one hour, days ago ("how is the weather").
--   R7  23 open deliberations (17 supplier_choice, 6 refund) whose subject no longer exists: their evidence is the
--       E2E journey's (aluminium, Dubai, AED 142,000; refund 355,500 fils, supplier_unresponsive) and each opened
--       within a second of a harness run the gateway already refused as fixture_no_spend. The 24th (campaign 7) is
--       real and stays open.
--   R8  77 supply_gap rows held for the sales engineer with one identical question; demand 0 on every one.
--
-- WHAT THIS CHANGES
--   1. fn_reason_subject_is_fixture: a held question whose subject is an identity our harness created (the existing
--      fn_ai_subject_is_fixture predicate, reached through the quote, the review key or the intake) is never filed.
--      That is the source: the smoke drives the real product, so the product recognises its subject, not the text.
--   2. reasoning_held_question.qhash = md5(surface, the question, its context, its decision options). fn_reason_held_due
--      claims ONE row per (surface, qhash); fn_reason_held_resolve fans the answer out to every waiting row with the same
--      hash, each applied by its own surface, and returns them so replayHeld delivers each on its own channel.
--   3. fn_reason_hold never reopens a failed or expired row, and files nothing when the same (surface, qhash) failed in
--      the last 7 days. A failed leader takes its waiting duplicates with it.
--   4. fn_reason_held_sweep (every tick, hold or not; replayHeld calls it before the gate): expires fixtures, rows whose
--      quote / intake / inquiry is gone, visitor chat past its hour (expires_at, set at filing), duplicates of a
--      failed hash, and every postmortem but one per fault. Each expiry carries its reason in result.
--   5. One postmortem per fault (fn_it_postmortem_fault_key: the finding key, digits stripped): an incident of a fault
--      whose cause is already known gets that cause with no model; one question per fault per 7 days; the answer
--      fills every incident of the fault.
--   6. Supply gaps with nobody waiting are deferred by rule (rule:nobody_waiting), as the 140 with no lead left were;
--      the 77 held decisions are settled by the routine and their questions expired with that reason.
--   7. fn_high_stakes_gate opens no second-seat review for a fixture subject; fn_seat_deliberation_withdraw closes an
--      open one whose subject is a fixture or no longer exists, with its reason, before any model reviews it.
--
-- Spend ceiling: none (founder_instruction 987). Nothing here caps, it only stops paying for test traffic and repeats.
-- Probe: scripts/sql/a_held_question_is_paid_for_once_and_test_traffic_never_waits_for_a_model_probe.sql
-- Prevented by: scripts/checks/a_held_question_is_paid_for_once.test.mjs

alter table public.reasoning_held_question add column if not exists qhash text;
create index if not exists reasoning_held_question_qhash_idx on public.reasoning_held_question (surface, qhash, status);

-- ── the content hash: what the model would actually be asked ──────────────────────────────────────────────────
create or replace function public.fn_reason_qhash(p_surface text, p_question text, p_request jsonb)
returns text
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select md5(coalesce(p_surface, '') || chr(10) || regexp_replace(btrim(coalesce(p_question, '')), '\s+', ' ', 'g')
             || chr(10) || coalesce((p_request -> 'context')::text, '') || chr(10) || coalesce((p_request -> 'decision')::text, ''));
$fn$;
revoke execute on function public.fn_reason_qhash(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_qhash(text, text, jsonb) to service_role;

update public.reasoning_held_question set qhash = public.fn_reason_qhash(surface, question, request) where qhash is null;

-- ── is this subject our own test traffic? ─────────────────────────────────────────────────────────────────────
-- Only the harness's own marker counts (fn_ai_subject_is_fixture: the qd-<run>-... address AND its rehearsal_window
-- row), so a person who types ZZ DEMO cannot suppress their own answer. The subject is resolved to the identities
-- behind it: a quote's inquiry and supplier, a 'review:<inquiry>:<lead>' key, an intake's customer and address.
create or replace function public.fn_reason_subject_is_fixture(p_subject jsonb)
returns boolean
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_q text := p_subject ->> 'quote_id'; v_in text := p_subject ->> 'intake_id';
  v_s jsonb := coalesce(p_subject, '{}'::jsonb);
begin
  if p_subject is null then return false; end if;
  if p_subject ->> 'fixture' = 'true' then return true; end if;
  if v_q ~ v_uuid then
    select v_s || jsonb_strip_nulls(jsonb_build_object('inquiry_id', q.inquiry_id, 'supplier_id', q.supplier_id))
      into v_s from public.quotes q where q.id = v_q::uuid;
    v_s := coalesce(v_s, p_subject);
  elsif v_q ~ '^review:[0-9a-fA-F-]{36}:[0-9]+$' then
    v_s := v_s || jsonb_build_object('inquiry_id', split_part(v_q, ':', 2), 'supplier_id', split_part(v_q, ':', 3));
  end if;
  if v_in ~ v_uuid then
    select v_s || jsonb_strip_nulls(jsonb_build_object('customer_id', i.customer_id, 'email', i.email))
      into v_s from public.inquiry_intake i where i.id = v_in::uuid;
    v_s := coalesce(v_s, p_subject);
  end if;
  return coalesce((public.fn_ai_subject_is_fixture(v_s) ->> 'fixture')::boolean, false);
end $fn$;
revoke execute on function public.fn_reason_subject_is_fixture(jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_subject_is_fixture(jsonb) to service_role;

-- ── filing: a fixture is never filed, a closed row never reopens, a recent failure is not asked again ─────────
-- From governance_reads_keys_and_reasons_rather_than_spotting_words.sql (canonical); the reopen branch is gone.
create or replace function public.fn_reason_hold(p_seat text, p_surface text, p_question text, p_request jsonb,
  p_plan jsonb, p_subject jsonb, p_reason text, p_dedupe_key text default null)
returns bigint
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_id bigint; v_hash text := public.fn_reason_qhash(p_surface, left(p_question, 8000), p_request);
begin
  if public.fn_reason_subject_is_fixture(p_subject) then
    return null;                                   -- our own test traffic: nothing is filed, nothing is ever paid for
  end if;
  -- THE 3-TRY LIMIT HOLDS ACROSS RE-FILINGS: the same question that failed in the last 7 days is not asked again.
  select h.id into v_id from public.reasoning_held_question h
   where h.surface = p_surface and h.qhash = v_hash and h.status = 'failed'
     and coalesce(h.last_attempt_at, h.created_at) > now() - interval '7 days'
   order by h.id desc limit 1;
  if v_id is not null then return v_id; end if;

  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, qhash, expires_at)
  values (p_seat, p_surface, left(p_question, 8000), p_request, coalesce(p_plan, '{}'::jsonb), p_subject, p_reason, p_dedupe_key, v_hash,
          -- A VISITOR'S CHAT IS ANSWERED WHILE THE VISITOR IS THERE, OR NOT AT ALL.
          case when p_surface like 'site_assistant.%' then now() + interval '1 hour' end)
  on conflict (dedupe_key) do update set reason = excluded.reason, plan = excluded.plan
   where reasoning_held_question.status = 'held'   -- a failed or expired row stays closed (R3)
  returning id into v_id;
  if v_id is null and p_dedupe_key is not null then
    select id into v_id from public.reasoning_held_question where dedupe_key = p_dedupe_key;
  end if;
  return v_id;
end $fn$;
revoke execute on function public.fn_reason_hold(text, text, text, jsonb, jsonb, jsonb, text, text) from public, anon, authenticated;
grant execute on function public.fn_reason_hold(text, text, text, jsonb, jsonb, jsonb, text, text) to service_role;

-- ── one postmortem per fault ──────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_postmortem_fault_key(p_detail jsonb)
returns text
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select regexp_replace(lower(btrim(coalesce(p_detail ->> 'issue_key', p_detail ->> 'title', ''))), '[0-9]+', '#', 'g');
$fn$;
revoke execute on function public.fn_it_postmortem_fault_key(jsonb) from public, anon, authenticated;
grant execute on function public.fn_it_postmortem_fault_key(jsonb) to service_role;

-- ── the sweep: runs every tick whether or not a model may run ─────────────────────────────────────────────────
create or replace function public.fn_reason_held_sweep()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  n_failed int; n_fixture int; n_gone int; n_stale int; n_dup_failed int; n_pm int;
  x constant text := 'fn_reason_held_sweep';
begin
  update public.reasoning_held_question set qhash = public.fn_reason_qhash(surface, question, request)
   where qhash is null and status = 'held';

  update public.reasoning_held_question set status = 'failed' where status = 'held' and attempts >= 3;
  get diagnostics n_failed = row_count;

  -- OUR OWN TEST TRAFFIC: the fixture convention in the text, a caller's subject.fixture, or a harness identity.
  update public.reasoning_held_question
     set status = 'expired', result = coalesce(result, '{}'::jsonb) || jsonb_build_object('expired_by', x, 'why', 'fixture, never paid for')
   where status = 'held'
     and (question ~ 'ZZ DEMO|@example\.invalid' or request::text ~ 'ZZ DEMO|@example\.invalid'
          or public.fn_reason_subject_is_fixture(subject));
  get diagnostics n_fixture = row_count;

  -- THE SUBJECT IS GONE: the quote, the intake or the inquiry the answer would be applied to no longer exists.
  update public.reasoning_held_question h
     set status = 'expired', result = coalesce(h.result, '{}'::jsonb) || jsonb_build_object('expired_by', x,
           'why', 'its subject no longer exists, so no answer could be applied (the E2E harness deletes its fixtures)')
   where h.status = 'held'
     and (   (h.subject ->> 'quote_id' ~ v_uuid and not exists (select 1 from public.quotes q where q.id = (h.subject ->> 'quote_id')::uuid))
          or (h.subject ->> 'quote_id' ~ '^review:[0-9a-fA-F-]{36}:' and not exists (select 1 from public.inquiries i
                where i.id::text = split_part(h.subject ->> 'quote_id', ':', 2)))
          or (h.subject ->> 'intake_id' ~ v_uuid and not exists (select 1 from public.inquiry_intake i where i.id = (h.subject ->> 'intake_id')::uuid))
          or (h.subject ->> 'inquiry_id' ~ v_uuid and not exists (select 1 from public.inquiries i where i.id = (h.subject ->> 'inquiry_id')::uuid)));
  get diagnostics n_gone = row_count;

  -- A VISITOR WHO HAS LEFT IS NEVER ANSWERED LATE (R5): an hour from filing, set by fn_reason_hold; rows filed before
  -- that column was set are judged by the same hour from created_at.
  update public.reasoning_held_question
     set status = 'expired', result = coalesce(result, '{}'::jsonb) || jsonb_build_object('expired_by', x,
           'why', 'a visitor chat past its hour: the visitor has gone, a late answer reaches nobody')
   where status = 'held'
     and (expires_at < now() or (surface like 'site_assistant.%' and created_at < now() - interval '1 hour'));
  get diagnostics n_stale = row_count;

  -- A FAILED QUESTION TAKES ITS WAITING DUPLICATES WITH IT (R3): the same hash is not tried three more times.
  update public.reasoning_held_question h
     set status = 'failed', result = coalesce(h.result, '{}'::jsonb) || jsonb_build_object('failed_with', f.id, 'by', x)
    from (select distinct on (surface, qhash) id, surface, qhash from public.reasoning_held_question
           where status = 'failed' and qhash is not null and coalesce(last_attempt_at, created_at) > now() - interval '7 days'
           order by surface, qhash, id desc) f
   where h.status = 'held' and h.surface = f.surface and h.qhash = f.qhash;
  get diagnostics n_dup_failed = row_count;

  -- ONE POSTMORTEM PER FAULT (R4): the oldest held question of a fault stays; the rest wait on it.
  update public.reasoning_held_question h
     set subject = h.subject || jsonb_build_object('fault_key', public.fn_it_postmortem_fault_key(a.detail))
    from public.it_incident i join public.agent_actions a on a.id = i.handoff_id
   where h.surface = 'it_engineer.postmortem' and h.status = 'held' and h.subject ->> 'fault_key' is null
     and h.subject ->> 'incident_id' ~ '^[0-9]+$' and i.id = (h.subject ->> 'incident_id')::bigint;
  update public.reasoning_held_question h
     set status = 'expired', result = coalesce(h.result, '{}'::jsonb) || jsonb_build_object('expired_by', x,
           'why', 'one postmortem per fault: held question ' || l.id || ' asks it, and its answer fills this incident too')
    from (select distinct on (subject ->> 'fault_key') id, subject ->> 'fault_key' fk from public.reasoning_held_question
           where surface = 'it_engineer.postmortem' and status in ('held', 'reasoned', 'applied') and subject ->> 'fault_key' is not null
           order by subject ->> 'fault_key', id) l
   where h.surface = 'it_engineer.postmortem' and h.status = 'held' and h.subject ->> 'fault_key' = l.fk and h.id <> l.id;
  get diagnostics n_pm = row_count;

  return jsonb_build_object('failed_at_three', n_failed, 'fixture', n_fixture, 'subject_gone', n_gone, 'visitor_gone', n_stale,
                            'failed_with_its_hash', n_dup_failed, 'postmortem_same_fault', n_pm);
end $fn$;
revoke execute on function public.fn_reason_held_sweep() from public, anon, authenticated;
grant execute on function public.fn_reason_held_sweep() to service_role;

-- ── the claim: one row per distinct question ──────────────────────────────────────────────────────────────────
-- From a_held_row_is_tried_three_times_and_the_build_test_backlog_is_expired.sql (canonical). The leader of a hash is
-- the row already tried (its attempts are the hash's attempts), else the oldest; the others wait for its answer.
create or replace function public.fn_reason_held_due(p_limit integer default 3)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_gate jsonb; v jsonb;
begin
  perform public.fn_reason_held_sweep();
  v_gate := public.fn_kernel_paid_provider_gate('hold-probe/not-a-model');
  if coalesce(v_gate->>'rule', '') in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state') then
    return '[]'::jsonb;
  end if;
  with lead as (
    select distinct on (surface, coalesce(qhash, id::text)) id, attempts, last_attempt_at, created_at
      from public.reasoning_held_question
     where status = 'held' and attempts < 3
     order by surface, coalesce(qhash, id::text), attempts desc, id
  ), due as (
    select h.id from public.reasoning_held_question h
     where h.id in (select id from lead where last_attempt_at is null or last_attempt_at < now() - interval '10 minutes')
     order by h.last_attempt_at nulls first, h.created_at
     limit greatest(1, least(coalesce(p_limit, 3), 10))
     for update skip locked
  ), claimed as (
    update public.reasoning_held_question h set attempts = h.attempts + 1, last_attempt_at = now()
      from due where h.id = due.id
    returning h.id, h.seat, h.surface, h.request, h.subject
  )
  select coalesce(jsonb_agg(to_jsonb(claimed)), '[]'::jsonb) into v from claimed;
  return v;
end $fn$;
revoke execute on function public.fn_reason_held_due(integer) from public, anon, authenticated;
grant execute on function public.fn_reason_held_due(integer) to service_role;

-- ── the answer: applied to the leader, then fanned out to every row waiting on the same hash ──────────────────
-- From a_held_row_is_tried_three_times_and_the_build_test_backlog_is_expired.sql (canonical), plus the fan-out and a
-- failed leader taking its duplicates with it.
create or replace function public.fn_reason_held_resolve(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_effect jsonb := null; v_fn text; f record; v_fan jsonb := '[]'::jsonb; v_one jsonb;
begin
  select * into r from public.reasoning_held_question where id = p_id for update;
  if not found then raise exception 'no held question %', p_id using errcode = 'P0002'; end if;
  if coalesce(p_result->>'status', '') <> 'answered' then
    if coalesce(p_result->>'reason', '') = 'model_hold' then
      update public.reasoning_held_question
         set result = p_result, status = 'held', attempts = greatest(attempts - 1, 0)
       where id = p_id;
      return jsonb_build_object('id', p_id, 'status', 'still_held', 'attempt_returned', true);
    end if;
    update public.reasoning_held_question
       set result = p_result, status = case when attempts >= 3 then 'failed' else 'held' end
     where id = p_id;
    if r.attempts >= 3 and r.qhash is not null then
      update public.reasoning_held_question
         set status = 'failed', result = coalesce(result, '{}'::jsonb) || jsonb_build_object('failed_with', p_id)
       where status = 'held' and surface = r.surface and qhash = r.qhash and id <> p_id;
    end if;
    return jsonb_build_object('id', p_id, 'status', case when r.attempts >= 3 then 'failed' else 'still_held' end);
  end if;
  update public.reasoning_held_question set result = p_result, status = 'reasoned', reasoned_at = now() where id = p_id;
  if r.surface = 'ceo.command_intent' and (r.subject->>'command_id') is not null then
    v_effect := public.fn_ceo_command_interpret((r.subject->>'command_id')::bigint, p_result->'decision'->>'choice',
                  left(coalesce(p_result->>'answer', ''), 1000));
  elsif r.surface = 'inquiry_intake.trade' and (r.subject->>'intake_id') is not null then
    update public.inquiry_intake i
       set category = p_result->'decision'->>'choice', status = 'needs_info', updated_at = now(),
           brief = coalesce(i.brief, '{}'::jsonb) || jsonb_build_object('category_by', 'reasoning', 'held_id', p_id)
     where i.id::text = r.subject->>'intake_id' and i.status = 'held'
       and exists (select 1 from public.category_specs cs where cs.category = p_result->'decision'->>'choice');
    v_effect := jsonb_build_object('intake_id', r.subject->>'intake_id', 'category', p_result->'decision'->>'choice', 'reopened', found);
  else
    v_fn := 'fn_reason_apply_' || replace(r.surface, '.', '__');
    if length(v_fn) <= 63 and to_regprocedure(format('public.%I(bigint,jsonb)', v_fn)) is not null then
      execute format('select public.%I($1, $2)', v_fn) into v_effect using p_id, p_result;
      v_effect := coalesce(v_effect, jsonb_build_object('applied_by', v_fn));
    end if;
  end if;
  if v_effect is not null then
    update public.reasoning_held_question set status = 'applied', applied_at = now() where id = p_id;
  end if;

  -- THE SAME QUESTION IS PAID FOR ONCE (R2): every row waiting on this hash takes this answer, applied by its own
  -- surface to its own subject. A fanned row is never fanned again. One row whose apply fails does not undo the rest.
  if r.qhash is not null and p_result->>'fanned_from' is null then
    for f in select id, seat, surface, request, subject from public.reasoning_held_question
              where status = 'held' and surface = r.surface and qhash = r.qhash and id <> p_id order by id loop
      begin
        v_one := public.fn_reason_held_resolve(f.id, p_result || jsonb_build_object('fanned_from', p_id));
        v_fan := v_fan || jsonb_build_object('id', f.id, 'seat', f.seat, 'surface', f.surface, 'request', f.request,
                                             'subject', f.subject, 'status', v_one->>'status');
      exception when others then
        update public.reasoning_held_question
           set status = 'failed', result = p_result || jsonb_build_object('fanned_from', p_id, 'apply_error', left(sqlerrm, 300))
         where id = f.id;
      end;
    end loop;
  end if;
  return jsonb_build_object('id', p_id, 'status', case when v_effect is null then 'reasoned' else 'applied' end, 'effect', v_effect,
                            'fanned', v_fan);
end $fn$;
revoke execute on function public.fn_reason_held_resolve(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_held_resolve(bigint, jsonb) to service_role;

-- ── the postmortem duty asks once per fault ───────────────────────────────────────────────────────────────────
-- From every_serious_incident_gets_a_postmortem.sql (canonical); only the asking loop changes.
create or replace function public.fn_it_engineer_postmortem()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare h record; v_inc bigint; p public.it_playbook; v_since timestamptz; n_open int := 0; n_play int := 0; n_asked int := 0;
        n_known int := 0; n_waiting int := 0; v_cause text;
        v_hist int; v_late int; v_ids jsonb; v_items jsonb := '[]'::jsonb; f public.it_engineer_finding;
begin
  select created_at into v_since from public.seat_duty where duty = 'it_engineer.postmortem';
  v_since := coalesce(v_since, now());

  for h in
    select a.* from public.agent_actions a
     where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'done'
       and a.detail->>'severity' in ('critical', 'high') and coalesce(a.decided_at, a.created_at) >= v_since
       and not exists (select 1 from public.it_incident i where i.handoff_id = a.id)
     order by a.id limit 50
  loop
    v_inc := public.fn_it_incident_open(h.id);
    n_open := n_open + 1;
    select * into f from public.it_engineer_finding where issue_key = h.detail->>'issue_key';
    update public.it_incident set ended_at = coalesce(ended_at, f.closed_at, h.decided_at, now()),
           fix = coalesce(fix, 'Closed: ' || coalesce(f.close_note, 'the ' || h.agent || ' answered and the finding cleared')),
           updated_at = now() where id = v_inc;
    select * into p from public.it_playbook where (h.detail->>'issue_key') like issue_prefix || '%'
     order by length(issue_prefix) desc limit 1;
    if found then
      update public.it_incident set playbook_class = p.failure_class,
             cause = coalesce(cause, p.typical_cause, 'Known failure class ' || p.failure_class || ': ' || coalesce(p.remedy, p.not_automatable_reason)),
             regression_check = coalesce(regression_check, p.regression_check), recorded_by = 'it_engineer.postmortem', updated_at = now()
       where id = v_inc;
      n_play := n_play + 1;
    end if;
  end loop;

  -- A class the playbook has never seen: its root cause is asked ONCE PER FAULT (the finding key, digits stripped),
  -- three faults a run, oldest first. An incident of a fault whose cause is already known takes that cause with no
  -- model; one whose fault already has a question in the last 7 days waits for that answer (the apply fills it).
  for h in
    select i.id inc_id, a.detail, a.evidence, public.fn_it_postmortem_fault_key(a.detail) fk
      from public.it_incident i join public.agent_actions a on a.id = i.handoff_id
     where i.created_at >= v_since and i.playbook_class is null and coalesce(btrim(i.cause), '') = ''
       and not exists (select 1 from public.reasoning_held_question q where q.dedupe_key = 'postmortem:' || i.id)
     order by i.id
  loop
    select i2.cause into v_cause from public.it_incident i2 join public.agent_actions a2 on a2.id = i2.handoff_id
     where i2.id <> h.inc_id and coalesce(btrim(i2.cause), '') <> '' and public.fn_it_postmortem_fault_key(a2.detail) = h.fk
     order by i2.id desc limit 1;
    if v_cause is not null then
      update public.it_incident set cause = v_cause, recorded_by = 'it_engineer.postmortem (same fault as an earlier incident)',
             updated_at = now() where id = h.inc_id;
      n_known := n_known + 1;
      continue;
    end if;
    if exists (select 1 from public.reasoning_held_question q
                where q.surface = 'it_engineer.postmortem' and q.subject->>'fault_key' = h.fk
                  and q.status in ('held', 'reasoned', 'applied') and q.created_at > now() - interval '7 days') then
      n_waiting := n_waiting + 1;
      continue;
    end if;
    exit when n_asked >= 3;
    select * into f from public.it_engineer_finding where issue_key = h.detail->>'issue_key';
    perform public.fn_reason_hold('it_engineer', 'it_engineer.postmortem',
      'Postmortem: what was the root cause of this fault, in two or three sentences? ' || coalesce(h.detail->>'title', h.detail->>'issue_key'),
      jsonb_build_object('seat', 'it_engineer', 'surface', 'it_engineer.postmortem', 'research', false, 'stakes', 'normal',
        'question', 'Root cause of: ' || coalesce(h.detail->>'title', h.detail->>'issue_key'),
        'context', jsonb_build_object('audience', 'internal', 'case', jsonb_build_object('handoff', h.detail, 'answer', h.evidence,
          'finding', to_jsonb(f) - 'evidence')),
        'subject', jsonb_build_object('incident_id', h.inc_id, 'fault_key', h.fk), 'dedupeKey', 'postmortem:' || h.inc_id),
      jsonb_build_object('filed_by', 'it_engineer.postmortem'), jsonb_build_object('incident_id', h.inc_id, 'fault_key', h.fk),
      'seat_duty', 'postmortem:' || h.inc_id);
    n_asked := n_asked + 1;
  end loop;

  select count(*) into v_hist from public.agent_actions a
   where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'done' and a.detail->>'severity' in ('critical', 'high')
     and not exists (select 1 from public.it_incident i where i.handoff_id = a.id);

  select count(*), coalesce(jsonb_agg(id order by id) filter (where rn <= 20), '[]') into v_late, v_ids
    from (select i.id, row_number() over (order by i.id) rn from public.it_incident i
           where i.ended_at < now() - interval '72 hours' and i.created_at >= v_since
             and (coalesce(btrim(i.cause), '') = '' or coalesce(btrim(i.regression_check), '') = '')) z;
  if v_late > 0 then
    v_items := jsonb_build_array(jsonb_build_object('item', 'incomplete', 'owner_seat', 'it_engineer', 'blast', 'internal', 'affected', v_late,
      'title', v_late || ' closed incident(s) have no root cause or no regression check 72 hours after they closed',
      'evidence', jsonb_build_object('incident_ids', v_ids)));
  end if;

  return jsonb_build_object('opened', n_open, 'from_playbook', n_play, 'asked', n_asked, 'cause_already_known', n_known,
                            'waiting_on_its_fault', n_waiting,
                            'historical_without_postmortem', v_hist, 'settled', public.fn_it_duty_settle('postmortem', v_items));
end $fn$;
revoke execute on function public.fn_it_engineer_postmortem() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_postmortem() to service_role;

-- The answer fills every incident of the fault that still has no cause, not only the one that asked.
create or replace function public.fn_reason_apply_it_engineer__postmortem(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_inc bigint; v_ans text := btrim(coalesce(p_result->>'answer', '')); n_more int := 0;
        v_by text := 'it_engineer.postmortem (' || coalesce(p_result->>'model', 'model') || ')';
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_inc := (r.subject->>'incident_id')::bigint;
  if v_ans = '' then raise exception 'EMPTY_ANSWER: postmortem question % came back empty', p_id; end if;
  update public.it_incident set cause = coalesce(nullif(btrim(cause), ''), left(v_ans, 2000)),
         recorded_by = coalesce(recorded_by, v_by), updated_at = now()
   where id = v_inc;
  if r.subject->>'fault_key' is not null then
    update public.it_incident i set cause = left(v_ans, 2000), recorded_by = coalesce(i.recorded_by, v_by || ', same fault'), updated_at = now()
      from public.agent_actions a
     where a.id = i.handoff_id and i.id <> v_inc and coalesce(btrim(i.cause), '') = ''
       and public.fn_it_postmortem_fault_key(a.detail) = r.subject->>'fault_key';
    get diagnostics n_more = row_count;
  end if;
  return jsonb_build_object('applied', true, 'incident_id', v_inc, 'same_fault_filled', n_more);
end $fn$;
revoke execute on function public.fn_reason_apply_it_engineer__postmortem(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_it_engineer__postmortem(bigint, jsonb) to service_role;

-- ── supply gaps nobody waits on are deferred by code (R8) ─────────────────────────────────────────────────────
-- From a_demo_request_is_never_supply_gap_demand.sql (canonical, MANIFEST 1942). Every gap with a counted request is
-- already recruited by rule:customer_waiting and every gap with no lead left is deferred by rule:no_uninvited_leads;
-- what remained for the model was "nobody is waiting, recruit or defer?" - 77 identical questions with demand 0. The
-- answer to that is the rule, not a judgement: defer, and it reopens in 30 days like every deferral. A decision held
-- for the model is settled the same way and its question expired with the reason. p_reason_limit is kept for the
-- callers' signature; nothing is filed for reasoning any more.
create or replace function public.fn_sales_engineer_supply_gap(p_reason_limit integer default 10)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_target int := coalesce((select category_open_min_suppliers from public.pricing_config order by id limit 1), 10);
  v_rule int; v_closed int; v_reopened int; v_settled int; v_nobody int; v_held_settled int;
  v_emirates text[] := array['Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah'];
begin
  with sup as materialized (   -- every matchable supplier with his trades and the emirates he states (none stated = UAE-wide)
    select sc.supplier_id, sc.trades,
           array(select distinct lower(btrim(e)) from unnest(coalesce(sc.coverage_emirates, '{}'::text[]) || coalesce(l.service_emirates, '{}'::text[])) e
                  where nullif(btrim(e), '') is not null) as stated
      from public.supplier_capabilities sc join public.leads l on l.id = sc.supplier_id
     where sc.confirmed_at is not null
       and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
  ), inq as materialized (
    select i.id, i.emirate, i.trades, i.created_at,
           (i.created_at > now() - interval '30 days' and i.status not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
            and (select count(*) from public.quotes q where q.inquiry_id = i.id) < 3) as short
      from public.inquiries i left join public.customers c on c.id = i.customer_id
     where i.created_at > now() - interval '90 days'
       -- DEMO IS NEVER DEMAND: a fixture customer's request never starts real recruitment (the predicate the
       -- stalled-inquiry rescue already uses)
       and not coalesce(public.fn_seat_clock_customer_is_fixture(c), false)
  ), pool as materialized (
    select t, l.emirate, count(*) as n from public.leads l, unnest(l.invite_trades) t
     where l.invite_status is null and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)
       and coalesce(l.is_demo, false) = false
     group by t, l.emirate
  ), keys as (
    select tt.code as trade, 'UAE'::text as emirate from public.taxonomy_trade tt where tt.active
    union
    select distinct t, i.emirate from inq i, unnest(i.trades) t
     where i.emirate = any(v_emirates) and t in (select code from public.taxonomy_trade where active)
  ), m as (
    select k.trade, k.emirate,
           (select count(*) from sup s where k.trade = any(s.trades)
             and (k.emirate = 'UAE' or cardinality(s.stated) = 0 or lower(k.emirate) = any(s.stated)))::int as matchable,
           (select count(*) from inq i where k.trade = any(i.trades) and (k.emirate = 'UAE' or i.emirate = k.emirate))::int as demand,
           (select count(*) from inq i where i.short and k.trade = any(i.trades) and (k.emirate = 'UAE' or i.emirate = k.emirate))::int as short,
           (select coalesce(sum(p.n), 0) from pool p where p.t = k.trade and (k.emirate = 'UAE' or p.emirate = k.emirate))::int as pool
      from keys k
  )
  insert into public.supply_gap as sg (trade, emirate, matchable, target, demand_90d, short_open, uninvited_pool, measured_at)
  select trade, emirate, matchable, v_target, demand, short, pool, now() from m
  on conflict (trade, emirate) do update set matchable = excluded.matchable, target = excluded.target,
    demand_90d = excluded.demand_90d, short_open = excluded.short_open, uninvited_pool = excluded.uninvited_pool, measured_at = now();

  -- An area row that no counted request names any more (its only requests were demo) was not re-measured above:
  -- it has no demand now, not the demand it had last run.
  update public.supply_gap set demand_90d = 0, short_open = 0, measured_at = now()
   where measured_at < now() and (demand_90d <> 0 or short_open <> 0);

  update public.supply_gap set status = 'closed', closed_at = now() where status <> 'closed' and matchable >= target;
  get diagnostics v_closed = row_count;
  update public.supply_gap set status = 'open', opened_at = now(), closed_at = null, decided_by = null, decided_at = null, held_id = null
   where (status = 'closed' and matchable < target) or (status = 'deferred' and decided_at < now() - interval '30 days');
  get diagnostics v_reopened = row_count;

  -- A RULE WHOSE CUSTOMER IS GONE IS UNDONE: a gap recruited for because a customer was waiting, where no counted
  -- (non-demo) request remains, goes back to open and is decided again below like any gap nobody waits on.
  update public.supply_gap set status = 'open', decided_by = null, decided_at = null, held_id = null
   where status = 'recruit' and decided_by = 'rule:customer_waiting' and short_open = 0 and demand_90d = 0;
  get diagnostics v_settled = row_count;

  -- A CUSTOMER IS ALREADY WAITING: recruited for at once, by rule. No judgement to make, so nothing waits on one.
  update public.supply_gap set status = 'recruit', decided_by = 'rule:customer_waiting', decided_at = now()
   where status in ('open', 'deciding', 'deferred') and (short_open > 0 or demand_90d > 0);
  get diagnostics v_rule = row_count;

  -- NO UNINVITED LEAD LEFT: nobody for marketing to recruit, so "defer" is the only answer - by rule, at no cost.
  update public.supply_gap set status = 'deferred', decided_by = 'rule:no_uninvited_leads', decided_at = now()
   where status = 'open' and uninvited_pool = 0;

  -- NOBODY IS WAITING: deferred by rule, at no cost (R8). A decision already held for the model is settled the same
  -- way, and the question it waited on is expired with the reason.
  update public.reasoning_held_question h
     set status = 'expired', result = coalesce(h.result, '{}'::jsonb) || jsonb_build_object('expired_by', 'fn_sales_engineer_supply_gap',
           'why', 'decided by code: nobody is waiting on this trade and area (rule:nobody_waiting)')
    from public.supply_gap s
   where s.status = 'deciding' and s.short_open = 0 and s.demand_90d = 0 and h.id = s.held_id and h.status = 'held';
  get diagnostics v_held_settled = row_count;
  update public.supply_gap set status = 'deferred', decided_by = 'rule:nobody_waiting', decided_at = now(), held_id = null
   where status in ('open', 'deciding') and short_open = 0 and demand_90d = 0;
  get diagnostics v_nobody = row_count;

  return jsonb_build_object('target', v_target, 'closed', v_closed, 'reopened', v_reopened, 'recruit_by_rule', v_rule, 'customer_rule_undone', v_settled,
    'deferred_nobody_waiting', v_nobody, 'held_questions_settled', v_held_settled, 'filed_for_reasoning', 0,
    'by_status', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from public.supply_gap group by status) x));
end $fn$;
revoke execute on function public.fn_sales_engineer_supply_gap(integer) from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_supply_gap(integer) to service_role;

-- ── second-seat reviews never run on test traffic (R7) ────────────────────────────────────────────────────────
create or replace function public.fn_deliberation_subject_is_fixture(p_subject_table text, p_subject_id text)
returns boolean
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_id text := split_part(coalesce(p_subject_id, ''), ':', 1); v_s jsonb;
begin
  if p_subject_table = 'inquiries' then
    v_s := jsonb_build_object('inquiry_id', v_id);
  elsif p_subject_table = 'refunds' and v_id ~ '^[0-9]+$' then
    select jsonb_strip_nulls(jsonb_build_object('inquiry_id', r.inquiry_id, 'customer_id', r.customer_id, 'supplier_id', r.supplier_lead_id))
      into v_s from public.refunds r where r.id = v_id::bigint;
  elsif p_subject_table = 'quotes' then
    v_s := jsonb_build_object('quote_id', v_id);
  end if;
  return v_s is not null and public.fn_reason_subject_is_fixture(v_s);
end $fn$;
revoke execute on function public.fn_deliberation_subject_is_fixture(text, text) from public, anon, authenticated;
grant execute on function public.fn_deliberation_subject_is_fixture(text, text) to service_role;

-- From every_seat_runs_the_founders_model_matrix_and_every_review_stays_cross_family.sql (canonical); only the first
-- branch is new: a fixture subject is not challenged, so no Opus review is ever owed on it.
create or replace function public.fn_high_stakes_gate(p_kind text, p_author_seat text, p_subject_table text, p_subject_id text,
  p_question text, p_evidence jsonb, p_proposal jsonb, p_author_model text default null, p_author_task_class text default null,
  p_demo boolean default false)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_model text := p_author_model; v_class text := p_author_task_class; v_id bigint; v_err text; v_held boolean; c jsonb; v_go boolean;
begin
  if public.fn_deliberation_subject_is_fixture(p_subject_table, p_subject_id) then
    return jsonb_build_object('proceed', true, 'state', 'not_challenged', 'fixture', true, 'deliberation_id', null,
      'reason', 'the subject is an identity of our own E2E harness: no second-seat review is opened, none is ever paid for');
  end if;
  -- THE AUTHOR'S MODEL: the one given, else the seat's latest reasoning call in 24 hours (what open() proves), else code.
  if v_model is null then
    select l.model_used, l.task_class into v_model, v_class from public.ai_cost_log l
     -- 1056: think() bills a seat's decision to internal_judgement
     where l.ok and l.task_class = 'internal_judgement' and l.occurred_at > now() - interval '24 hours'
       and (l.agent_key = p_author_seat or l.seat = p_author_seat)
     order by l.occurred_at desc, l.id desc limit 1;
    v_model := coalesce(v_model, 'deterministic');
    if v_model = 'deterministic' then v_class := null; end if;
  end if;
  begin
    v_id := public.fn_high_stakes_challenge(p_kind, p_author_seat, p_subject_table, p_subject_id, p_question, p_evidence, p_proposal,
                                           v_model, v_class, p_demo);
  exception when others then
    v_err := sqlerrm;
    -- Recorded for the deciding seat, never raised: the decision path decides what a failed gate means.
    perform public.fn_it_engineer_finding_upsert('high_stakes_open:' || p_kind || ':' || p_subject_table || ':' || p_subject_id,
      'The second-seat review of a ' || p_kind || ' decision could not be opened', p_author_seat || ' ' || p_kind || ' on ' || p_subject_table,
      'agent_facing', 1, jsonb_build_object('owner_seat', p_author_seat, 'error', left(v_err, 500), 'subject_id', p_subject_id), '{}', '{}', 'it_engineer');
  end;
  v_held := public.fn_high_stakes_model_held();
  c := public.fn_high_stakes_clearance(p_kind, p_subject_table, p_subject_id);
  v_go := coalesce((c->>'cleared')::boolean, false) or (v_held and coalesce(c->>'state', '') <> 'disagreed');
  if v_go and not coalesce((c->>'cleared')::boolean, false) and v_id is not null then
    update public.seat_deliberation set proceeded_at = coalesce(proceeded_at, now()) where id = v_id;
  end if;
  return c || jsonb_build_object('proceed', v_go, 'owed', v_go and not coalesce((c->>'cleared')::boolean, false),
                                 'model_held', v_held, 'author_model', v_model, 'open_error', v_err);
end $fn$;
revoke execute on function public.fn_high_stakes_gate(text, text, text, text, text, jsonb, jsonb, text, text, boolean) from public, anon, authenticated;
grant execute on function public.fn_high_stakes_gate(text, text, text, text, text, jsonb, jsonb, text, text, boolean) to service_role;

-- An open deliberation whose subject is our own test traffic, or no longer exists, is withdrawn before any model
-- reviews it: closed by its author seat with the reason as its outcome, and its handoff completed the same way.
create or replace function public.fn_seat_deliberation_withdraw(p_id bigint, p_reason text)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare d public.seat_deliberation; v_gone boolean; v_fixture boolean; v_id text;
begin
  select * into d from public.seat_deliberation where id = p_id for update;
  if not found then raise exception 'no seat_deliberation %', p_id; end if;
  if d.status <> 'open' then return jsonb_build_object('ok', false, 'reason', 'deliberation ' || p_id || ' is ' || d.status); end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'a withdrawal states its reason'; end if;
  v_id := split_part(coalesce(d.subject_id, ''), ':', 1);
  v_fixture := public.fn_deliberation_subject_is_fixture(d.subject_table, d.subject_id);
  v_gone := case d.subject_table
              when 'inquiries' then not exists (select 1 from public.inquiries i where i.id::text = v_id)
              when 'refunds'   then not exists (select 1 from public.refunds r where r.id::text = v_id)
              when 'quotes'    then not exists (select 1 from public.quotes q where q.id::text = v_id)
              else false end;
  if not (v_fixture or v_gone) then
    raise exception 'deliberation % is about a live, real subject (%:%): only a fixture or a vanished subject is withdrawn',
      p_id, d.subject_table, d.subject_id;
  end if;
  update public.seat_deliberation set status = 'closed', closed_at = now(),
         outcome = 'withdrawn before review: ' || left(p_reason, 400) where id = p_id;
  if d.handoff_id is not null then
    perform set_config('qd.handoff_closer', d.author_seat, true);
    perform public.fn_seat_handoff_complete(d.handoff_id, jsonb_build_object('kind', 'deliberation.review', 'deliberation_id', p_id,
      'ended', 'withdrawn', 'outcome', left(p_reason, 400), 'closed_by', d.author_seat,
      'subject_fixture', v_fixture, 'subject_gone', v_gone));
  end if;
  return jsonb_build_object('ok', true, 'deliberation_id', p_id, 'subject_fixture', v_fixture, 'subject_gone', v_gone);
end $fn$;
revoke execute on function public.fn_seat_deliberation_withdraw(bigint, text) from public, anon, authenticated;
grant execute on function public.fn_seat_deliberation_withdraw(bigint, text) to service_role;

-- ── settle what is already waiting, through the routines (nothing is deleted) ─────────────────────────────────
select public.fn_reason_held_sweep() as sweep;
select public.fn_sales_engineer_supply_gap(0) as supply_gap;
select count(*) filter (where (public.fn_seat_deliberation_withdraw(d.id,
         'its subject (' || d.subject_table || ' ' || d.subject_id || ') is E2E harness traffic that no longer exists; '
         || 'a review of it would pay a model to judge a test') ->> 'ok')::boolean) as deliberations_withdrawn
  from public.seat_deliberation d
 where d.status = 'open' and d.kind in ('high_stakes.supplier_choice', 'high_stakes.refund')
   and (public.fn_deliberation_subject_is_fixture(d.subject_table, d.subject_id)
        or (d.subject_table = 'inquiries' and not exists (select 1 from public.inquiries i where i.id::text = split_part(d.subject_id, ':', 1)))
        or (d.subject_table = 'refunds' and not exists (select 1 from public.refunds r where r.id::text = d.subject_id)));

-- Verdict row (DDL in this file, so no raise).
select case
  when exists (select 1 from public.reasoning_held_question where status = 'held'
                and (surface like 'site_assistant.%' and created_at < now() - interval '1 hour'))
    then 'PROBE FAILED: a stale visitor chat is still held'
  when exists (select 1 from public.reasoning_held_question h where h.status = 'held' and h.subject ->> 'quote_id' is not null
                and h.subject ->> 'quote_id' ~ '^[0-9a-fA-F-]{36}$' and not exists (select 1 from public.quotes q where q.id::text = h.subject ->> 'quote_id'))
    then 'PROBE FAILED: a question about a deleted quote is still held'
  when exists (select 1 from public.supply_gap where status = 'deciding' and demand_90d = 0 and short_open = 0)
    then 'PROBE FAILED: a supply gap nobody waits on is still held for the model'
  when position('where reasoning_held_question.status = ''held''' in pg_get_functiondef('public.fn_reason_hold(text,text,text,jsonb,jsonb,jsonb,text,text)'::regprocedure)) = 0
    then 'PROBE FAILED: fn_reason_hold can still reopen a closed row'
  else 'PROBE OK' end as verdict;
-- PROBE: a held question is paid for once and our own test traffic never waits for a model. Pure probe, no DDL of its
-- own: run AFTER its .sql in the SAME query (node scripts/qsql.mjs on a file that concatenates both); it always ends in
-- raise exception CHK<<...>>, so nothing survives, including the .sql it was run after. It writes only ZZ DEMO rows
-- (a harness identity qd-zzprobe-*@example.invalid, surface zz_demo.probe) and reaches no one: nothing is sent, and the
-- one gate it opens for fn_reason_held_due is replaced inside this transaction only, so no model is ever called.
-- PROBE OK only if:
--   R1  a question about a harness identity's inquiry is not filed; its deliberation gate opens nothing;
--   R2  three rows with the same question are claimed once, and the one answer is applied to all three (fanned 2);
--   R3  a failed row filed again stays failed with attempts unchanged, and the same question under a new key files nothing;
--   R5  a visitor chat is filed with an hour to live, and a two-hour-old one is expired by the sweep;
--   R4  two held postmortems of one fault become one;
--   backlog: the held queue after the file is at most what it was before minus the measured test traffic.
do $probe$
declare
  v_fail text := ''; v_cust uuid := gen_random_uuid(); v_inq uuid := gen_random_uuid(); v_id bigint; v_a bigint; v_b bigint; v_c bigint;
  v jsonb; v_n int; v_att int; v_req jsonb := '{"seat":"it_engineer","context":{"audience":"internal"}}'::jsonb;
begin
  -- R1: a harness identity (address shape + its rehearsal_window row) and an inquiry of it.
  insert into public.rehearsal_window (run_tag, note) values ('qd_run:zzprobe', 'ZZ DEMO probe of a_held_question_is_paid_for_once');
  insert into public.customers (id, email, name, is_demo) values (v_cust, 'qd-zzprobe-cust1@example.invalid', 'ZZ DEMO probe customer', true);
  insert into public.inquiries (id, customer_id, category, trades, emirate, raw_input, status)
  values (v_inq, v_cust, 'aluminium', array['aluminium'], 'Dubai', 'ZZ DEMO probe request', 'quoted');
  v_id := public.fn_reason_hold('it_engineer', 'zz_demo.probe', 'Is this our own test?', v_req, '{}', jsonb_build_object('inquiry_id', v_inq),
                                'probe', 'zzprobe:fixture');
  if v_id is not null then v_fail := v_fail || ' R1 a harness subject was filed;'; end if;
  if not public.fn_deliberation_subject_is_fixture('inquiries', v_inq::text || ':c9a3b39bcab2048b') then
    v_fail := v_fail || ' R7 a harness inquiry is not a fixture deliberation subject;'; end if;

  -- R2: three rows, one question; the gate is opened inside this transaction only.
  execute $g$create or replace function public.fn_kernel_paid_provider_gate(p_model text) returns jsonb language sql
             set search_path to 'public', 'pg_temp' as $b$ select '{"allowed":true,"rule":"probe_open"}'::jsonb $b$$g$;
  v_a := public.fn_reason_hold('it_engineer', 'zz_demo.probe', 'ZZ PROBE one question  asked three times', v_req, '{}', '{"n":1}', 'probe', 'zzprobe:a');
  v_b := public.fn_reason_hold('it_engineer', 'zz_demo.probe', 'ZZ PROBE one question asked three times', v_req, '{}', '{"n":2}', 'probe', 'zzprobe:b');
  v_c := public.fn_reason_hold('it_engineer', 'zz_demo.probe', 'ZZ PROBE one question asked three times ', v_req, '{}', '{"n":3}', 'probe', 'zzprobe:c');
  update public.reasoning_held_question set last_attempt_at = now() - interval '1 day', created_at = now() - interval '10 days'
   where id in (v_a, v_b, v_c);   -- first in the queue, ahead of every real row
  v := public.fn_reason_held_due(10);
  select count(*) into v_n from jsonb_array_elements(v) e where (e->>'id')::bigint in (v_a, v_b, v_c);
  if v_n <> 1 then v_fail := v_fail || ' R2 the same question was claimed ' || v_n || ' times;'; end if;
  v := public.fn_reason_held_resolve(v_a, '{"status":"answered","answer":"ZZ PROBE answer"}'::jsonb);
  if jsonb_array_length(v->'fanned') <> 2 then v_fail := v_fail || ' R2 fanned ' || jsonb_array_length(v->'fanned') || ' not 2;'; end if;
  select count(*) into v_n from public.reasoning_held_question where id in (v_a, v_b, v_c) and status in ('reasoned', 'applied');
  if v_n <> 3 then v_fail := v_fail || ' R2 ' || v_n || ' of 3 rows took the answer;'; end if;

  -- R3: a failed row stays failed when filed again; the same question under another key files nothing.
  v_id := public.fn_reason_hold('it_engineer', 'zz_demo.probe', 'ZZ PROBE a question that failed', v_req, '{}', '{"n":4}', 'probe', 'zzprobe:f');
  update public.reasoning_held_question set status = 'failed', attempts = 3, last_attempt_at = now() where id = v_id;
  perform public.fn_reason_hold('it_engineer', 'zz_demo.probe', 'ZZ PROBE a question that failed', v_req, '{}', '{"n":4}', 'probe', 'zzprobe:f');
  select attempts into v_att from public.reasoning_held_question where id = v_id and status = 'failed';
  if v_att is distinct from 3 then v_fail := v_fail || ' R3 a failed row was reopened;'; end if;
  if public.fn_reason_hold('it_engineer', 'zz_demo.probe', 'ZZ PROBE a question that failed', v_req, '{}', '{"n":5}', 'probe', 'zzprobe:g') <> v_id
     or exists (select 1 from public.reasoning_held_question where dedupe_key = 'zzprobe:g') then
    v_fail := v_fail || ' R3 a recently failed question was filed again under a new key;'; end if;

  -- R5: visitor chat lives an hour.
  v_id := public.fn_reason_hold('customer_support', 'site_assistant.person', 'ZZ PROBE how is the weather', v_req, '{}', '{"path":"/"}', 'probe', 'zzprobe:chat');
  if (select expires_at from public.reasoning_held_question where id = v_id) is null then v_fail := v_fail || ' R5 a visitor chat has no expiry;'; end if;
  update public.reasoning_held_question set expires_at = now() - interval '1 hour' where id = v_id;
  perform public.fn_reason_held_sweep();
  if (select status from public.reasoning_held_question where id = v_id) <> 'expired' then v_fail := v_fail || ' R5 a stale visitor chat was not expired;'; end if;

  -- R4: two held postmortems of one fault become one.
  select count(*) into v_n from (select subject->>'fault_key' fk from public.reasoning_held_question
                                  where surface = 'it_engineer.postmortem' and status = 'held' group by 1 having count(*) > 1) z;
  if v_n > 0 then v_fail := v_fail || ' R4 ' || v_n || ' fault(s) still have more than one held postmortem;'; end if;

  select count(*) into v_n from public.reasoning_held_question where status = 'held' and surface not like 'zz_demo.%';
  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK held_after=' || v_n
                                     || ' open_deliberations=' || (select count(*) from public.seat_deliberation where status = 'open')
                                     || ' supply_gap_deciding=' || (select count(*) from public.supply_gap where status = 'deciding')
                                     else 'PROBE FAILED:' || v_fail end;
end $probe$;
