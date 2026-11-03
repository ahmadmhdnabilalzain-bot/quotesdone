-- A POSTMORTEM IS WRITTEN FROM ITS CLASS, AND A TEST FIXTURE OPENS NONE (it_engineer, 3 Nov 2026)
--
-- MEASURED (reasoning_held_question and ai_cost_log, 7 days to 3 Nov): 134 it_engineer.postmortem questions (75 applied,
-- 28 failed, 31 held), about 232 GPT-6 Luna Pro calls through resilience_ping, 30% of rows aborted and retried three times.
-- Every fault key was a class of its own because the key is the whole finding key with digits stripped: one question per
-- Supabase advisor routine ('...:pdpl_cancel_me_p_request uuid', '...:pdpl_confirm_me_...'), one per nightly-journey step
-- ('duty:journey:f-drawings/...:the_intake_reached_ready', '...:no_contact_detail_...'), one per latency SLO function.
-- And 14 of the 40 keys read in that week were the nightly journey, which drives ZZ DEMO / @example.invalid fixtures.
--
-- WHAT CHANGES in fn_it_engineer_postmortem (supersedes the body of every_serious_incident_gets_a_postmortem.sql and its
-- later redefinitions; same signature, CREATE OR REPLACE keeps its grants):
--   1. A finding raised by a test fixture opens NO incident and no question: the nightly journey's keys (duty:journey:*,
--      scripts/e2e/journeys.mjs drives ZZ DEMO fixtures) and any finding whose detail or evidence names a fixture
--      (ZZ DEMO, @example.invalid, a qd_run: tag). The finding itself is untouched; it_engineer still sees it.
--   2. The CLASS is the first two parts of the key (fn_it_postmortem_class_key: 'duty:journey', 'duty:advisory_triage',
--      'duty:latency_slo', 'acct:owner_card'; a one-part key is its own class). An incident of a class with a recorded
--      cause is written from a code template naming that earlier incident and this occurrence - no model.
--   3. The model is asked only for a NOVEL class: once per class (7 days), three a run as before; the other incidents of
--      the class wait for that answer and are written by the template on a later run.
-- fn_it_postmortem_fault_key is unchanged (the held-question sweep still dedupes one question per fault with it).
--
--   node scripts/apply_sql.mjs scripts/sql/a_postmortem_is_written_from_its_class_and_a_test_fixture_opens_none.sql --apply --ddl

create or replace function public.fn_it_postmortem_class_key(p_detail jsonb)
returns text
language sql
immutable
set search_path to 'public', 'pg_temp'
as $fn$
  -- the first two ':' parts of the fault key; null, never '', when the finding names nothing
  select nullif(array_to_string((string_to_array(public.fn_it_postmortem_fault_key(p_detail), ':'))[1:2], ':'), '');
$fn$;
revoke execute on function public.fn_it_postmortem_class_key(jsonb) from public, anon, authenticated;
grant execute on function public.fn_it_postmortem_class_key(jsonb) to service_role;

create or replace function public.fn_it_finding_is_fixture(p_detail jsonb, p_evidence jsonb)
returns boolean
language sql
immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(p_detail ->> 'issue_key', '') like 'duty:journey:%'
      or (coalesce(p_detail::text, '') || ' ' || coalesce(p_evidence::text, '')) ~* '(zz demo|@example\.invalid|qd_run:)';
$fn$;
revoke execute on function public.fn_it_finding_is_fixture(jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.fn_it_finding_is_fixture(jsonb, jsonb) to service_role;

create or replace function public.fn_it_engineer_postmortem()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare h record; v_inc bigint; p public.it_playbook; v_since timestamptz; n_open int := 0; n_play int := 0; n_asked int := 0;
        n_known int := 0; n_waiting int := 0; v_cause text; v_prev bigint; v_hid bigint; n_fixture int := 0;
        v_hist int; v_late int; v_ids jsonb; v_items jsonb := '[]'::jsonb; f public.it_engineer_finding;
begin
  select created_at into v_since from public.seat_duty where duty = 'it_engineer.postmortem';
  v_since := coalesce(v_since, now());

  -- 1. a test fixture's finding opens no incident (counted, never opened)
  select count(*) into n_fixture from public.agent_actions a
   where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'done'
     and a.detail->>'severity' in ('critical', 'high') and coalesce(a.decided_at, a.created_at) >= v_since
     and not exists (select 1 from public.it_incident i where i.handoff_id = a.id)
     and public.fn_it_finding_is_fixture(a.detail, a.evidence);

  for h in
    select a.* from public.agent_actions a
     where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'done'
       and a.detail->>'severity' in ('critical', 'high') and coalesce(a.decided_at, a.created_at) >= v_since
       and not exists (select 1 from public.it_incident i where i.handoff_id = a.id)
       and not public.fn_it_finding_is_fixture(a.detail, a.evidence)
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

  -- 2. no playbook: the CLASS's recorded cause by template; 3. a novel class: asked once per class.
  for h in
    select i.id inc_id, a.detail, a.evidence, public.fn_it_postmortem_fault_key(a.detail) fk, public.fn_it_postmortem_class_key(a.detail) ck
      from public.it_incident i join public.agent_actions a on a.id = i.handoff_id
     where i.created_at >= v_since and i.playbook_class is null and coalesce(btrim(i.cause), '') = ''
       and not exists (select 1 from public.reasoning_held_question q where q.dedupe_key = 'postmortem:' || i.id)
       and not public.fn_it_finding_is_fixture(a.detail, a.evidence)
     order by i.id
  loop
    v_cause := null; v_prev := null;
    select i2.id, i2.cause into v_prev, v_cause from public.it_incident i2 join public.agent_actions a2 on a2.id = i2.handoff_id
     where i2.id <> h.inc_id and coalesce(btrim(i2.cause), '') <> '' and public.fn_it_postmortem_class_key(a2.detail) = h.ck
     order by i2.id desc limit 1;
    if v_cause is not null then
      -- the earlier cause without the template's own wrapping, so a template never wraps a template
      v_cause := regexp_replace(split_part(v_cause, ' | This occurrence: ', 1), '^Known class [^ ]+ \(incident [0-9]+\): ', '');
      update public.it_incident
         set cause = left('Known class ' || h.ck || ' (incident ' || v_prev || '): ' || v_cause
                          || ' | This occurrence: ' || coalesce(h.detail->>'title', h.detail->>'issue_key', 'untitled'), 2000),
             recorded_by = 'it_engineer.postmortem (template: known class ' || h.ck || ')', updated_at = now()
       where id = h.inc_id;
      n_known := n_known + 1;
      continue;
    end if;
    if exists (select 1 from public.reasoning_held_question q
                where q.surface = 'it_engineer.postmortem'
                  and coalesce(q.subject->>'class_key', public.fn_it_postmortem_class_key(jsonb_build_object('issue_key', q.subject->>'fault_key'))) = h.ck
                  and q.status in ('held', 'reasoned', 'applied') and q.created_at > now() - interval '7 days') then
      n_waiting := n_waiting + 1;
      continue;
    end if;
    exit when n_asked >= 3;
    select * into f from public.it_engineer_finding where issue_key = h.detail->>'issue_key';
    v_hid := public.fn_reason_hold('it_engineer', 'it_engineer.postmortem',
      'Postmortem: what was the root cause of this fault, in two or three sentences? ' || coalesce(h.detail->>'title', h.detail->>'issue_key'),
      jsonb_build_object('seat', 'it_engineer', 'surface', 'it_engineer.postmortem', 'research', false, 'stakes', 'normal',
        'question', 'Root cause of: ' || coalesce(h.detail->>'title', h.detail->>'issue_key'),
        'context', jsonb_build_object('audience', 'internal', 'case', jsonb_build_object('handoff', h.detail, 'answer', h.evidence,
          'finding', to_jsonb(f) - 'evidence')),
        'subject', jsonb_build_object('incident_id', h.inc_id, 'fault_key', h.fk, 'class_key', h.ck), 'dedupeKey', 'postmortem:' || h.inc_id),
      jsonb_build_object('filed_by', 'it_engineer.postmortem'), jsonb_build_object('incident_id', h.inc_id, 'fault_key', h.fk, 'class_key', h.ck),
      'seat_duty', 'postmortem:' || h.inc_id);
    if exists (select 1 from public.reasoning_held_question q where q.id = v_hid and q.dedupe_key = 'postmortem:' || h.inc_id) then
      n_asked := n_asked + 1;
    end if;
  end loop;

  select count(*) into v_hist from public.agent_actions a
   where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'done' and a.detail->>'severity' in ('critical', 'high')
     and not exists (select 1 from public.it_incident i where i.handoff_id = a.id)
     and not public.fn_it_finding_is_fixture(a.detail, a.evidence);

  select count(*), coalesce(jsonb_agg(id order by id) filter (where rn <= 20), '[]') into v_late, v_ids
    from (select i.id, row_number() over (order by i.id) rn from public.it_incident i
           where i.ended_at < now() - interval '72 hours' and i.created_at >= v_since
             and (coalesce(btrim(i.cause), '') = '' or coalesce(btrim(i.regression_check), '') = '')) z;
  if v_late > 0 then
    v_items := jsonb_build_array(jsonb_build_object('item', 'incomplete', 'owner_seat', 'it_engineer', 'blast', 'internal', 'affected', v_late,
      'title', v_late || ' closed incident(s) have no root cause or no regression check 72 hours after they closed',
      'evidence', jsonb_build_object('incident_ids', v_ids)));
  end if;

  return jsonb_build_object('opened', n_open, 'from_playbook', n_play, 'asked', n_asked, 'cause_from_its_class', n_known,
                            'waiting_on_its_class', n_waiting, 'fixture_findings_not_opened', n_fixture,
                            'historical_without_postmortem', v_hist, 'settled', public.fn_it_duty_settle('postmortem', v_items));
end $fn$;

update public.seat_duty set owner_file = 'scripts/sql/a_postmortem_is_written_from_its_class_and_a_test_fixture_opens_none.sql',
       what = 'Every closed critical/high fault that no test fixture raised gets an incident record with its root cause (playbook first, then its class''s recorded cause by template, think() once per new class) and a regression check.'
 where duty = 'it_engineer.postmortem';

-- PROBE (verdict row; reads only): the class key folds the measured keys, and the fixture rule reads the journey and markers.
select case
  when public.fn_it_postmortem_class_key('{"issue_key":"duty:advisory_triage:supabase:authenticated_security_definer_function_executable_public_pdpl_cancel_me_p_request uuid"}')
       is distinct from 'duty:advisory_triage' then 'PROBE FAILED: an advisor key does not fold to its class'
  when public.fn_it_postmortem_class_key('{"issue_key":"delivery_outcome_unreturned"}') is distinct from 'delivery_outcome_unreturned'
    then 'PROBE FAILED: a one-part key is not its own class'
  when public.fn_it_postmortem_class_key('{}') is not null then 'PROBE FAILED: a finding that names nothing has a class'
  when not public.fn_it_finding_is_fixture('{"issue_key":"duty:journey:f-drawings/x:y"}', null) then 'PROBE FAILED: a journey finding is not a fixture'
  when not public.fn_it_finding_is_fixture('{"issue_key":"duty:delivery:x","title":"to qd-ab12-c@example.invalid"}', null) then 'PROBE FAILED: a fixture address is not a fixture'
  when public.fn_it_finding_is_fixture('{"issue_key":"duty:latency_slo:kyc:error_budget","title":"kyc is burning its error budget"}', '{}') then 'PROBE FAILED: a real finding reads as a fixture'
  else 'PROBE OK' end as verdict;
