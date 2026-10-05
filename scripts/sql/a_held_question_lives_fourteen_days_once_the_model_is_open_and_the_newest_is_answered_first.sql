-- A HELD QUESTION LIVES FOURTEEN DAYS ONCE THE MODEL IS OPEN, THE NEWEST IS ANSWERED FIRST, AND THE STALE BACKLOG
-- OF 23-28 SEP IS EXPIRED BEFORE THE HOLD LIFTS.
-- Seat: it_engineer (the reasoning queue), with ceo (the order the queue is answered in). 6 Oct 2026, final check
-- before the founder lifts the model hold (founder_instruction 1119: final check -> sandbox test with OpenRouter on).
--
-- MEASURED (production, 6 Oct 2026, read-only): 284 held questions, every one with expires_at NULL, 141 older than
-- 7 days. fn_reason_held_due claimed the OLDEST first (order by created_at), so the first day after the hold lifts
-- would be spent answering 23-24 Sep questions whose moment has passed:
--   * marketing.competitor_change: 31, all filed 24 Sep (a competitor's change of 12 days ago is not news);
--   * it_engineer.postmortem: 37 older than 7 days (the duty asks for a postmortem within 7 days of the incident);
--   * <seat>.knowledge_refresh: 60 rows, 30 of them Q3 (2026-07-01) refreshes of an item that also has a held Q4
--     (2026-10-01) refresh - the newer quarter asks the same question of the same item;
--   * sales_engineer.document_arabic (10) and documents.boq_arabic (5), all filed 23-28 Sep.
--
-- WHAT THIS CHANGES (through the existing state machine; status 'expired' with its reason in result, no delete,
-- no agent_runs row written)
--   1. reasoning_held_question.expires_at defaults to 14 days from filing, and fn_reason_hold sets it so (a visitor
--      chat keeps its hour). Rows already held get 14 days from now, so the current backlog has a clock too.
--   2. fn_reason_held_sweep expires a row past expires_at ONLY while a model may run. The 23 Sep reason a held
--      question "never expires" (a_held_question_never_expires_it_is_escalated_at_48_hours.sql: the hold lasts a while,
--      and an expiry would drop the very questions the hold is holding) still stands: under the founder's hold nothing
--      but a visitor chat expires. The 48-hour escalation to the owning seat is unchanged, so a question is seen by
--      its seat twelve days before it can expire.
--   3. fn_reason_held_due claims the NEWEST due question first (created_at desc); a row already tried still comes
--      before an untried one (last_attempt_at nulls first is unchanged), so a retry is never starved.
--   4. Expires, once, the four stale groups above by exact criteria. Nothing else is touched.
--
-- What this does NOT change: no spend ceiling (founder_instruction 987, still standing: "No caps on LLM spend"),
-- the 3-attempt bound, the one-postmortem-per-fault rule, the fan-out of one answer to its duplicates.
-- Routines below are copied from a_held_question_is_paid_for_once_and_test_traffic_never_waits_for_a_model.sql
-- (canonical until this file), with only the lines marked "6 Oct" changed.
-- Probe: scripts/sql/a_held_question_lives_fourteen_days_once_the_model_is_open_and_the_newest_is_answered_first_probe.sql
-- Pending: scripts/sql/pending/a_held_question_lives_fourteen_days_once_the_model_is_open_and_the_newest_is_answered_first.txt
-- Prevented by: scripts/checks/a_held_question_is_answered_newest_first.test.mjs

alter table public.reasoning_held_question alter column expires_at set default now() + interval '14 days';
update public.reasoning_held_question set expires_at = now() + interval '14 days'
 where status = 'held' and expires_at is null;

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
  -- Not for a visitor chat: it lives an hour, and one visitor's failed "hi" must not silence the next visitor's.
  select h.id into v_id from public.reasoning_held_question h
   where p_surface not like 'site_assistant.%' and h.surface = p_surface and h.qhash = v_hash and h.status = 'failed'
     and coalesce(h.last_attempt_at, h.created_at) > now() - interval '7 days'
   order by h.id desc limit 1;
  if v_id is not null then return v_id; end if;

  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key, qhash, expires_at)
  values (p_seat, p_surface, left(p_question, 8000), p_request, coalesce(p_plan, '{}'::jsonb), p_subject, p_reason, p_dedupe_key, v_hash,
          -- A VISITOR'S CHAT IS ANSWERED WHILE THE VISITOR IS THERE, OR NOT AT ALL.
          -- 6 Oct: every other question lives 14 days (it can only expire while a model may run; see the sweep).
          case when p_surface like 'site_assistant.%' then now() + interval '1 hour' else now() + interval '14 days' end)
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
  -- 6 Oct: under the founder's hold a held question never expires by age (the hold is what keeps it waiting)
  v_held boolean := coalesce(public.fn_kernel_paid_provider_gate('hold-probe/not-a-model') ->> 'rule', '')
                      in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state');
begin
  -- One sweep at a time: replayHeld and fn_reason_held_due both call it, and two ticks may overlap.
  if not pg_try_advisory_xact_lock(hashtext('fn_reason_held_sweep')) then
    return jsonb_build_object('skipped', 'another sweep is running');
  end if;
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
           'why', case when surface like 'site_assistant.%'
                       then 'a visitor chat past its hour: the visitor has gone, a late answer reaches nobody'
                       else 'held 14 days with the model open: its moment has passed (6 Oct)' end)
   where status = 'held'
     -- 6 Oct: a visitor chat expires on its hour always; anything else only past expires_at AND with the model open
     and (   (surface like 'site_assistant.%' and (expires_at < now() or created_at < now() - interval '1 hour'))
          or (surface not like 'site_assistant.%' and expires_at < now() and not v_held));
  get diagnostics n_stale = row_count;

  -- A FAILED QUESTION TAKES ITS WAITING DUPLICATES WITH IT (R3): the same hash is not tried three more times.
  update public.reasoning_held_question h
     set status = 'failed', result = coalesce(h.result, '{}'::jsonb) || jsonb_build_object('failed_with', f.id, 'by', x)
    from (select distinct on (surface, qhash) id, surface, qhash from public.reasoning_held_question
           where status = 'failed' and qhash is not null and coalesce(last_attempt_at, created_at) > now() - interval '7 days'
           order by surface, qhash, id desc) f
   where h.status = 'held' and h.surface = f.surface and h.qhash = f.qhash and h.surface not like 'site_assistant.%';
  get diagnostics n_dup_failed = row_count;

  -- ONE POSTMORTEM PER FAULT (R4): the oldest held question of a fault stays; the rest wait on it.
  update public.reasoning_held_question h
     set subject = h.subject || jsonb_build_object('fault_key', public.fn_it_postmortem_fault_key(a.detail))
    from public.it_incident i join public.agent_actions a on a.id = i.handoff_id
   where h.surface = 'it_engineer.postmortem' and h.status = 'held' and h.subject ->> 'fault_key' is null
     and h.subject ->> 'incident_id' ~ '^[0-9]+$' and i.id = (h.subject ->> 'incident_id')::bigint
     and public.fn_it_postmortem_fault_key(a.detail) is not null;
  update public.reasoning_held_question h
     set status = 'expired', result = coalesce(h.result, '{}'::jsonb) || jsonb_build_object('expired_by', x,
           'why', 'one postmortem per fault: held question ' || l.id || ' asks it, and its answer fills this incident too')
    from (select distinct on (subject ->> 'fault_key') id, subject ->> 'fault_key' fk from public.reasoning_held_question
           where surface = 'it_engineer.postmortem' and subject ->> 'fault_key' is not null
             -- a held leader of any age is still pending; an answered one covers its fault for 7 days, as the duty asks
             and (status = 'held' or (status in ('reasoned', 'applied') and created_at > now() - interval '7 days'))
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
     -- 6 Oct: the NEWEST due question first; a retry (last_attempt_at set) still waits its 10 minutes, then goes
     -- behind untried rows exactly as before, so it is never starved past its three tries.
     order by h.last_attempt_at nulls first, h.created_at desc
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

-- ── 4. the stale backlog of 23-28 Sep, expired once, by exact criteria ─────────────────────────────────────────
update public.reasoning_held_question
   set status = 'expired', result = coalesce(result, '{}'::jsonb) || jsonb_build_object('expired_by', '6 Oct final check',
         'why', 'a competitor change filed on 24 Sep: twelve days later it is no longer news worth paying to read')
 where status = 'held' and surface = 'marketing.competitor_change'
   and created_at >= '2026-09-24 00:00+00' and created_at < '2026-09-25 00:00+00';

update public.reasoning_held_question
   set status = 'expired', result = coalesce(result, '{}'::jsonb) || jsonb_build_object('expired_by', '6 Oct final check',
         'why', 'a postmortem question older than 7 days: the duty asks for it within 7 days of the incident')
 where status = 'held' and surface = 'it_engineer.postmortem' and created_at < now() - interval '7 days';

update public.reasoning_held_question h
   set status = 'expired', result = coalesce(h.result, '{}'::jsonb) || jsonb_build_object('expired_by', '6 Oct final check',
         'why', 'superseded: a newer quarter''s refresh of the same item is held and asks the same question', 'superseded_by', n.id)
  from public.reasoning_held_question n
 where h.status = 'held' and h.surface like '%.knowledge_refresh'
   and n.status = 'held' and n.surface = h.surface and n.id <> h.id
   and n.subject ->> 'item_key' = h.subject ->> 'item_key'
   and n.subject ->> 'quarter' > h.subject ->> 'quarter';

update public.reasoning_held_question
   set status = 'expired', result = coalesce(result, '{}'::jsonb) || jsonb_build_object('expired_by', '6 Oct final check',
         'why', 'an Arabic document question filed 23-28 Sep, expired before the model hold lifts')
 where status = 'held' and surface in ('sales_engineer.document_arabic', 'documents.boq_arabic')
   and created_at >= '2026-09-23 00:00+00' and created_at < '2026-09-29 00:00+00';
