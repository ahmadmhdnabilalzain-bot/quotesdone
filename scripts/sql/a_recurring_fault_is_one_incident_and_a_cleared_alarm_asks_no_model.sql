-- A RECURRING FAULT IS ONE INCIDENT, COUNTED ON IT, CLOSED WHEN IT MEASURES HEALTHY; A CLEARED ALARM ASKS NO MODEL.
-- Seat: it_engineer. 16 Nov 2026. Founder ledger 1557 (LEDGER_OPEN #5), rulings 1696/1706/1710/1609 for the founder routing.
--
-- MEASURED BEFORE (SELECT on production, 16 Nov 2026, 7 days):
--   * it_incident: 1,916 rows. 1,025 were "Delivery request N has had no confirmed outcome" (one cause, send_outbox),
--     614 were resilience_ping heartbeat steps (one cause, 471 of them already folded AFTER the fact by
--     fn_it_incident_collapse), 71 detached itlater. Every one of them was a row born from a hand-over: a flapping
--     finding closes on the first good tick, reopens on the next bad one, gets a new hand-over and, through
--     fn_it_engineer_postmortem, a new incident. Replayed with one incident per cause (a recurrence within 24 hours of
--     the cause's last sighting is the same incident; re-measured after review, 16 Nov): 142 of 1,923, heartbeat 621 -> 2,
--     delivery 1,025 -> 1; two different faults of one class (duty:run_cluster:site_assistant / :fn:license_extract) stay two.
--   * The model: resilience_ping logged 897 calls, AED 19.90, in 7 days (ai_cost_log fn='resilience_ping'). No step
--     calls a model because of its own readings: every call is a queued question (held replay), a deliberation, a
--     routine judgement, a duty voice or a case summary. The share the alarms caused: it_engineer.postmortem (13 questions,
--     30 attempts; profile_model_read_failed alone was asked 6 times, once per occurrence, because a FAILED ask did not
--     count as asked) and ceo.it_finding (one question per hand-over of the same fault, reasoned even after the finding
--     had cleared, so the apply step then threw the answer away: "the hand-over is no longer open").
--   * founder_alerts: 197 rows, of which 171 'inquiry_contact_masked' channel 'system' (a masking log line, never sent)
--     and 20 notifications actually reached him: daily brief 7, reports 6, and three alarms (OpenRouter credit low,
--     Dropbox backup blocked from outside, a person asking for a human). 30 days: refund_ceo_summary 4 also reached him.
--
-- WHAT CHANGES:
--   1. fn_it_incident_cause_key: the cause of an occurrence, computed when it is OPENED (the same key
--      fn_it_incident_collapse writes after the fact: playbook class + subject, else the WHOLE fault key (digits as #; review 16 Nov: the two-part class key joined different faults), else the issue key).
--   2. fn_it_incident_open: an occurrence whose cause has an open incident, or one seen within 24 hours, writes NO new
--      row. It is counted on that incident (occurrences + 1, last_seen_at) and the hand-over carries incident_id, so
--      every reader that asks "has this hand-over an incident" gets the answer without a second row. A live occurrence
--      reopens an internal incident; a customer-facing occurrence never reopens an ended one (it is a new outage,
--      judged and told on its own - the rule fn_it_incident_collapse already keeps). A new cause opens one incident
--      with its cause_key and last_seen_at set at once.
--   3. fn_it_incident_settle: an open incident whose cause has no open finding left is closed (the cause measured
--      healthy again). Run every 15 minutes inside fn_it_incident_impact_tick.
--   4. fn_it_engineer_postmortem: a hand-over counted on an open incident is neither re-opened nor asked about; a class
--      whose postmortem question FAILED in the last 7 days is not asked again for every occurrence.
--   5. fn_reason_held_sweep: a held ceo.it_finding question whose hand-over closed, or whose finding has cleared, is
--      expired BEFORE any model is called (the model reasons only while something is wrong); one postmortem per fault
--      also holds after a failed ask.
--   6. fn_it_daily_line: a hand-over counted on an open incident is not an "auto-fixed" class.
--   7. Nothing changes in founder_mail_policy. Measured: the alarms that reached him in 7 days were all kinds his rulings
--      still route to him - billing (finance_reminder: OpenRouter credit low; ruling 1609 "the founder only funds
--      OpenRouter and keeps subscriptions running"), a credential only he holds (backup_failed_after_retry: Dropbox
--      blocked from outside; ruling 1090) and a person asking for a human (person_request; ruling 1264). An IT fault
--      reaches him only through the 19:00 digest and only in his three categories (fn_customer_support_sends_the_it_digest).
--      Folding occurrences adds no founder path: an occurrence counted on an incident is never escalated again by itself.
--      scripts/checks/one_incident_per_cause_and_no_model_on_a_healthy_alarm.test.mjs proves, kind by kind, that every alarm
--      he still receives still reaches him.
--
-- Routine bodies are production's (pg_get_functiondef, 16 Nov 2026) with only the lines marked "16 Nov 2026 (ledger 1557)"
-- changed; md5 before the edit: fn_it_incident_open 880c215b..., fn_it_engineer_postmortem 2628da5a...,
-- fn_reason_held_sweep d92fd428..., fn_it_daily_line 3725dea5..., fn_it_incident_impact_tick 0f8b1c53....


-- 1. THE CAUSE OF AN OCCURRENCE, KNOWN WHEN IT OPENS. fn_it_incident_collapse's key with the class narrowed to the whole fault; collapse writes after the fact
--    (a playbook class is a remedy, not a cause, so the failing subject is part of it), with the playbook class read the
--    way fn_it_engineer_postmortem reads it: the longest issue_prefix that matches. Null only when the detail names nothing.
create or replace function public.fn_it_incident_cause_key(p_detail jsonb)
returns text
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  select coalesce(
    'playbook:' || (select p.failure_class from public.it_playbook p
                     where p.issue_prefix is not null and (p_detail->>'issue_key') like p.issue_prefix || '%'
                     order by length(p.issue_prefix) desc limit 1)
                || ':' || coalesce(p_detail->>'subject', p_detail->>'where_it_is', '-'),
    -- review 16 Nov: the whole fault (digits as #), not its first two parts: 'class:duty:run_cluster' joined license_extract,
    -- llm_gateway_auth and site_assistant, and 'class:acct:reveal_reconcile' joined different payments, into one incident
    'fault:' || public.fn_it_postmortem_fault_key(p_detail),
    'issue:' || nullif(btrim(p_detail->>'issue_key'), ''));
$function$;
revoke execute on function public.fn_it_incident_cause_key(jsonb) from public, anon, authenticated;

-- 2. ONE INCIDENT PER CAUSE, DEDUPED AT OPEN (16 Nov 2026, ledger 1557). Before: one row per hand-over, folded hours later.
CREATE OR REPLACE FUNCTION public.fn_it_incident_open(p_handoff_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare h public.agent_actions; v_id bigint; v_pub boolean; v_key text; v_at timestamptz; v_demo boolean; v_root public.it_incident;
begin
  select * into h from public.agent_actions where id = p_handoff_id and kind = 'handoff' and detail->>'type' = 'it.finding';
  if not found then raise exception 'fn_it_incident_open: % is not an it.finding handoff', p_handoff_id; end if;
  -- 16 Nov 2026 (ledger 1557): asked twice for the same hand-over, the answer is the incident it was counted on, never a second count
  if h.detail->>'incident_id' ~ '^[0-9]+$' then return (h.detail->>'incident_id')::bigint; end if;
  select id into v_id from public.it_incident where handoff_id = p_handoff_id;
  if v_id is not null then return v_id; end if;
  v_pub := coalesce((h.detail->'finding_evidence'->>'public_surface')::boolean, false)
           or h.detail->>'severity' = 'critical';
  -- 16 Nov 2026 (ledger 1557): THE SAME CAUSE, STILL OPEN OR SEEN IN THE LAST 24 HOURS, IS THIS OCCURRENCE'S INCIDENT.
  v_key := public.fn_it_incident_cause_key(h.detail);
  v_at := coalesce((h.detail->>'occurrence_started_at')::timestamptz, now());
  v_demo := coalesce(h.detail->>'title', h.detail->>'issue_key', '') like 'ZZ DEMO%';
  if v_key is not null then
    select r.* into v_root from public.it_incident r
     where r.cause_key = v_key and r.same_cause_as is null
       and (r.ended_at is null or coalesce(r.last_seen_at, r.started_at, r.created_at) > v_at - interval '24 hours')
       and (coalesce(r.title, '') like 'ZZ DEMO%') = v_demo
       -- never hide what customers may feel (fn_it_incident_collapse's rule): a customer-facing occurrence counts only on a
       -- customer-facing incident, and a live one never on an incident that has ended - that is a new outage, told on its own
       and (not v_pub or (coalesce(r.impact, '') like 'Customer-facing%' and (r.ended_at is null or h.status = 'done')))
     order by r.id desc limit 1
     for update;
    if v_root.id is not null then
      update public.it_incident
         set occurrences = occurrences + 1,
             last_seen_at = greatest(coalesce(last_seen_at, started_at, created_at), v_at),
             -- a live occurrence reopens the incident; one already over (the postmortem path) moves its end to the later clearance
             ended_at = case when h.status <> 'done' then null
                             when ended_at is null then null
                             else greatest(ended_at, coalesce(h.decided_at, now())) end,
             updated_at = now()
       where id = v_root.id;
      update public.agent_actions
         set detail = detail || jsonb_build_object('incident_id', v_root.id, 'incident_counted_at', now())
       where id = h.id;
      return v_root.id;
    end if;
  end if;
  insert into public.it_incident (handoff_id, issue_key, title, what, impact, started_at, cause_key, last_seen_at)
  values (h.id, h.detail->>'issue_key', coalesce(h.detail->>'title', h.detail->>'issue_key'),
          coalesce(h.detail->>'title', h.detail->>'issue_key') || ' (' || coalesce(h.detail->>'where_it_is', h.detail->>'subject', 'not recorded') || ').',
          case when v_pub then 'Customer-facing: something a customer or supplier opens was affected.'
               else 'Internal: an agent''s work was affected; no customer-facing surface was.' end
            || ' Severity ' || coalesce(h.detail->>'severity', 'unrecorded') || '; the ' || h.agent || ' had no remedy within its reply window.',
          (h.detail->>'occurrence_started_at')::timestamptz, v_key, v_at)
  on conflict (handoff_id) do nothing
  returning id into v_id;
  return coalesce(v_id, (select id from public.it_incident where handoff_id = p_handoff_id));
end $function$
;

-- 3. AN OPEN INCIDENT CLOSES WHEN ITS CAUSE MEASURES HEALTHY AGAIN (16 Nov 2026, ledger 1557): no finding that is open now
--    has this incident's cause. The open findings are a few hundred rows at most (153 on 16 Nov), so the cause of each is
--    computed here rather than stored. A customer-facing incident closed here gets its "fixed" notice from
--    fn_customer_support_incident_notice_tick exactly as one closed by the loop does.
create or replace function public.fn_it_incident_settle()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare n_closed int := 0; v_ids jsonb;
begin
  -- review 16 Nov: every key form an open incident may carry. Roots keyed by fn_it_incident_collapse before this file read
  -- 'class:<first two parts>' where this function now derives 'playbook:...' (6 open roots on 16 Nov, 18092 customer-facing,
  -- each with its finding still open): matching one form only closed them while their cause was live.
  with fd as (
    select jsonb_build_object('issue_key', f.issue_key, 'title', f.title, 'where_it_is', f.where_it_is,
             'subject', coalesce(nullif(f.evidence->>'subject', ''),
                                 (select w.subject from public.it_watch_finding w where 'watch:' || w.detector_key = f.issue_key limit 1))) d
      from public.it_engineer_finding f where f.closed_at is null
  ), live as (
    select distinct v.k from fd, lateral (values (public.fn_it_incident_cause_key(fd.d)),
                                                 ('class:' || public.fn_it_postmortem_class_key(fd.d)),
                                                 ('fault:' || public.fn_it_postmortem_fault_key(fd.d)),
                                                 ('issue:' || nullif(btrim(fd.d->>'issue_key'), ''))) v(k)
     where v.k is not null
  ), closed as (
    update public.it_incident r
       set ended_at = now(), updated_at = now()
     where r.ended_at is null and r.same_cause_as is null and r.cause_key is not null
       and not exists (select 1 from live where live.k = r.cause_key)
    returning r.id
  )
  select count(*), coalesce(jsonb_agg(id order by id), '[]'::jsonb) into n_closed, v_ids from closed;
  return jsonb_build_object('closed_healthy', n_closed, 'incident_ids', v_ids);
end $function$;
revoke execute on function public.fn_it_incident_settle() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_it_incident_impact_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- 16 Nov 2026 (ledger 1557): 'settled' closes every open incident whose cause measures healthy again (fn_it_incident_settle)
  return jsonb_build_object('settled', public.fn_it_incident_settle(),
    'collapse', public.fn_it_incident_collapse(2000), 'impact', public.fn_it_incident_impact_ask(5),
    'register_roots_24h', (select count(*) from public.it_incident where same_cause_as is null and cause_key is not null and created_at > now() - interval '24 hours'),
    'incidents_24h', (select count(*) from public.it_incident where created_at > now() - interval '24 hours'));
end $function$
;

CREATE OR REPLACE FUNCTION public.fn_it_engineer_postmortem()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare h record; v_inc bigint; p public.it_playbook; v_since timestamptz; n_open int := 0; n_play int := 0; n_asked int := 0;
        n_known int := 0; n_waiting int := 0; v_cause text; v_prev bigint; v_check text; v_hid bigint; n_fixture int := 0;
        n_folded int := 0;   -- 16 Nov 2026 (ledger 1557)
        v_hist int; v_late int; v_ids jsonb; v_items jsonb := '[]'::jsonb; f public.it_engineer_finding;
begin
  select created_at into v_since from public.seat_duty where duty = 'it_engineer.postmortem';
  v_since := coalesce(v_since, now());

  -- 1. a test fixture's finding opens no incident (counted, never opened)
  select count(*) into n_fixture from public.agent_actions a
   where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'done'
     and a.detail->>'severity' in ('critical', 'high') and coalesce(a.decided_at, a.created_at) >= v_since
     and not exists (select 1 from public.it_incident i where i.handoff_id = a.id) and not (a.detail ? 'incident_id')
     and public.fn_it_finding_is_fixture(a.detail, a.evidence);

  for h in
    select a.* from public.agent_actions a
     where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'done'
       and a.detail->>'severity' in ('critical', 'high') and coalesce(a.decided_at, a.created_at) >= v_since
       and not exists (select 1 from public.it_incident i where i.handoff_id = a.id) and not (a.detail ? 'incident_id')
       and not public.fn_it_finding_is_fixture(a.detail, a.evidence)
     order by a.id limit 50
  loop
    v_inc := public.fn_it_incident_open(h.id);
    -- 16 Nov 2026 (ledger 1557): an occurrence of a cause that already has an incident is counted on it, not a new postmortem
    if not exists (select 1 from public.it_incident where id = v_inc and handoff_id = h.id) then
      n_folded := n_folded + 1;
      continue;
    end if;
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
    v_cause := null; v_prev := null; v_check := null;
    select i2.id, i2.cause, i2.regression_check into v_prev, v_cause, v_check from public.it_incident i2 join public.agent_actions a2 on a2.id = i2.handoff_id
     where i2.id <> h.inc_id and coalesce(btrim(i2.cause), '') <> '' and public.fn_it_postmortem_class_key(a2.detail) = h.ck
     order by i2.id desc limit 1;
    if v_cause is not null then
      -- the earlier cause without the template's own wrapping, so a template never wraps a template
      -- (.+? and not [^ ]+: a class key may hold a space, e.g. an advisor routine's 'p_request uuid')
      v_cause := regexp_replace(split_part(v_cause, ' | This occurrence: ', 1), '^Known class .+? \(incident [0-9]+\): ', '');
      update public.it_incident
         set cause = left('Known class ' || h.ck || ' (incident ' || v_prev || '): ' || v_cause
                          || ' | This occurrence: ' || coalesce(h.detail->>'title', h.detail->>'issue_key', 'untitled'), 2000),
             regression_check = coalesce(nullif(btrim(regression_check), ''), v_check),
             recorded_by = 'it_engineer.postmortem (template: known class ' || h.ck || ')', updated_at = now()
       where id = h.inc_id;
      n_known := n_known + 1;
      continue;
    end if;
    if exists (select 1 from public.reasoning_held_question q
                where q.surface = 'it_engineer.postmortem'
                  and coalesce(q.subject->>'class_key', public.fn_it_postmortem_class_key(jsonb_build_object('issue_key', q.subject->>'fault_key'))) = h.ck
                  and q.status in ('held', 'reasoned', 'applied', 'failed') and q.created_at > now() - interval '7 days') then
      -- 16 Nov 2026 (ledger 1557): 'failed' counts as asked; profile_model_read_failed was asked 6 times in a day, once per occurrence
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
     and not exists (select 1 from public.it_incident i where i.handoff_id = a.id) and not (a.detail ? 'incident_id')
     and not public.fn_it_finding_is_fixture(a.detail, a.evidence);

  select count(*), coalesce(jsonb_agg(id order by id) filter (where rn <= 20), '[]') into v_late, v_ids
    from (select i.id, row_number() over (order by i.id) rn from public.it_incident i
            join public.agent_actions a on a.id = i.handoff_id
           where i.ended_at < now() - interval '72 hours' and i.created_at >= v_since
             and (coalesce(btrim(i.cause), '') = '' or coalesce(btrim(i.regression_check), '') = '')
             and not public.fn_it_finding_is_fixture(a.detail, a.evidence)) z;
  if v_late > 0 then
    v_items := jsonb_build_array(jsonb_build_object('item', 'incomplete', 'owner_seat', 'it_engineer', 'blast', 'internal', 'affected', v_late,
      'title', v_late || ' closed incident(s) have no root cause or no regression check 72 hours after they closed',
      'evidence', jsonb_build_object('incident_ids', v_ids)));
  end if;

  return jsonb_build_object('opened', n_open, 'counted_on_an_open_incident', n_folded, 'from_playbook', n_play, 'asked', n_asked, 'cause_from_its_class', n_known,
                            'waiting_on_its_class', n_waiting, 'fixture_findings_not_opened', n_fixture,
                            'historical_without_postmortem', v_hist, 'settled', public.fn_it_duty_settle('postmortem', v_items));
end $function$
;

CREATE OR REPLACE FUNCTION public.fn_reason_held_sweep()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  n_failed int; n_fixture int; n_gone int; n_stale int; n_dup_failed int; n_pm int; n_healthy int;
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
           'why', 'a visitor chat past its hour: the visitor has gone, a late answer reaches nobody')
   where status = 'held'
     and surface like 'site_assistant.%' and (expires_at < now() or created_at < now() - interval '1 hour');
  get diagnostics n_stale = row_count;

  -- 6 Oct: anything else ages out only with the model open, only after its first attempt started its 14-day clock,
  -- and through fn_reason_held_expire, so a customer or supplier still waiting is handed to the seat, never dropped.
  if not v_held then
    n_stale := n_stale + coalesce((public.fn_reason_held_expire(
      array(select id from public.reasoning_held_question
             where status = 'held' and surface not like 'site_assistant.%' and attempts > 0 and expires_at < now()),
      x, 'held 14 days after its first attempt with the model open: its moment has passed') ->> 'expired')::int, 0);
  end if;

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
             -- 16 Nov 2026 (ledger 1557): a FAILED ask covers its fault for 7 days too; it used to be re-asked for every occurrence
             and (status = 'held' or (status in ('reasoned', 'applied', 'failed') and created_at > now() - interval '7 days'))
           order by subject ->> 'fault_key', id) l
   where h.surface = 'it_engineer.postmortem' and h.status = 'held' and h.subject ->> 'fault_key' = l.fk and h.id <> l.id;
  get diagnostics n_pm = row_count;

  -- 16 Nov 2026 (ledger 1557): THE MODEL REASONS ONLY WHILE SOMETHING IS WRONG. A CEO judgement of an IT finding whose
  -- hand-over has closed, or whose finding has cleared (closed, or reopened since as a later occurrence with its own
  -- hand-over), is expired here, before fn_reason_held_due hands it to a model. Until now it was reasoned anyway and
  -- fn_reason_apply_ceo__it_finding then discarded the answer ("the hand-over is no longer open").
  update public.reasoning_held_question h
     set status = 'expired', result = coalesce(h.result, '{}'::jsonb) || jsonb_build_object('expired_by', x,
           'why', 'the IT finding measured healthy again (or its hand-over closed) before the CEO was asked: nothing to decide')
   where h.surface = 'ceo.it_finding' and h.status = 'held' and h.subject ->> 'handoff_id' ~ '^[0-9]+$'
     and not exists (select 1 from public.agent_actions a
                       join public.it_engineer_finding f on f.issue_key = a.detail ->> 'issue_key'
                      where a.id = (h.subject ->> 'handoff_id')::bigint and a.kind = 'handoff' and a.status = 'pending'
                        and f.closed_at is null
                        and f.started_at <= coalesce((a.detail ->> 'occurrence_started_at')::timestamptz, f.started_at));
  get diagnostics n_healthy = row_count;

  return jsonb_build_object('it_finding_healthy_again', n_healthy, 'failed_at_three', n_failed, 'fixture', n_fixture, 'subject_gone', n_gone, 'visitor_gone', n_stale,
                            'failed_with_its_hash', n_dup_failed, 'postmortem_same_fault', n_pm);
end $function$
;

CREATE OR REPLACE FUNCTION public.fn_it_daily_line()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_local timestamp := now() at time zone 'Asia/Dubai';
  v_day   text := to_char(v_local, 'YYYY-MM-DD');
  v_since timestamptz := (date_trunc('day', v_local) at time zone 'Asia/Dubai');
  v_ev jsonb; v_rep jsonb; n_done int;
begin
  update public.support_ceo_report
     set status = 'completed', completed_at = now(),
         completion_note = 'IT engineer saw the CEO''s receipt: ' || acceptance_receipt
   where source_agent = 'it_engineer' and idempotency_key like 'it_daily:%' and status = 'accepted';
  get diagnostics n_done = row_count;

  if v_local::time < time '19:00'
     or exists (select 1 from public.support_ceo_report where idempotency_key = 'it_daily:' || v_day) then
    return jsonb_build_object('filed', false, 'completed_after_receipt', n_done);
  end if;

  select jsonb_build_object(
    'day', v_day,
    'open_findings', (select count(*) from public.it_engineer_finding where closed_at is null),
    'open_findings_actionable', (select count(*) from public.it_engineer_finding
                                  where closed_at is null and public.fn_it_engineer_severity(blast, affected, started_at) <> 'warn'),
    'open_loops', (select count(*) from public.agent_actions
                    where kind = 'handoff' and detail->>'from' = 'it_engineer' and status in ('pending', 'failed')),
    'open_loops_by_seat', coalesce((select jsonb_object_agg(agent, n) from (
                      select agent, count(*) n from public.agent_actions
                       where kind = 'handoff' and detail->>'from' = 'it_engineer' and status in ('pending', 'failed')
                       group by agent) x), '{}'::jsonb),
    'loops_closed_today', (select count(*) from public.agent_actions
                            where kind = 'handoff' and detail->>'from' = 'it_engineer' and status = 'done' and decided_at >= v_since),
    'escalated_today', (select count(*) from public.support_ceo_report
                         where source_agent = 'it_engineer' and idempotency_key like 'it_loop:%' and created_at >= v_since),
    'founder_emails_today', (select count(*) from public.founder_alerts
                              where dedupe_key like 'it\_%' and channel = 'email' and created_at >= v_since),
    'repeats_folded_today', (select count(*) from public.founder_alerts
                              where dedupe_key like 'it\_%' and channel = 'deduped' and created_at >= v_since),
    -- Duty 17: failure classes the company fixed on its own versus new ones.
    'auto_fixed_today', (select count(*) from public.agent_actions a
                          where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.status = 'done' and a.decided_at >= v_since
                            and not exists (select 1 from public.it_incident i where i.handoff_id = a.id) and not (a.detail ? 'incident_id')),
    'playbook_runs_today', (select count(*) from public.agent_runs
                             where agent = 'it_engineer' and counts->>'job' = 'playbook' and started_at >= v_since),
    'new_bugs_today', (select count(*) from public.it_incident where created_at >= v_since),
    'awaiting_learning', (select count(*) from public.agent_actions
                           where kind = 'handoff' and detail->>'type' = 'it.finding' and status <> 'done' and detail ? 'awaiting_learning'),
    -- Instruction 979: what the integration watch fixed itself today (recorded here, never mailed), and what is down.
    'integrations_fixed_today', coalesce((select jsonb_agg(distinct counts->'fix'->>'integration') from public.agent_runs
                           where agent = 'it_engineer' and counts->>'job' = 'integration_self_fix' and started_at >= v_since), '[]'::jsonb),
    'integrations_failing', coalesce((select jsonb_agg(regexp_replace(issue_key, '^duty:', '') order by issue_key) from public.it_engineer_finding
                           where closed_at is null and issue_key like 'duty:integration%'), '[]'::jsonb),
    'integrations_waiting_on_external', coalesce((select jsonb_agg(jsonb_build_object('integration', integration, 'party', external_party,
                           'ticket', ticket_ref, 'opened_on', opened_on, 'last_reply_at', last_reply_at,
                           'reply_needs_founder', reply_needs_founder, 'last_checked_at', last_checked_at) order by integration)
                           from public.it_integration_external_cause where closed_at is null), '[]'::jsonb),
    -- The newest Gmail Postmaster reading (duty 'postmaster'); null until the first read. Its numbers are Postmaster's
    -- day (stats_day), 1-2 days behind read_on; a number Postmaster did not publish is null, never 0.
    'gmail_postmaster', (select jsonb_build_object('domain', p.domain, 'read_on', p.read_on, 'basis', p.basis, 'stats_day', p.stats_day,
                           'spam_ratio', p.spam_ratio, 'spam_lower', p.spam_lower, 'spam_upper', p.spam_upper, 'reputation', p.reputation,
                           'spf_ratio', p.spf_ratio, 'dkim_ratio', p.dkim_ratio, 'dmarc_ratio', p.dmarc_ratio, 'reason', p.reason,
                           'paused_at', p.paused_at, 'line', p.line)
                           from public.it_postmaster_reading p order by p.read_on desc, p.read_at desc limit 1))
  into v_ev;

  v_rep := public.fn_support_report_to_ceo('it_daily:' || v_day, 'routine',
    'IT engineer daily line ' || v_day || ': ' || (v_ev->>'open_loops') || ' open loop(s), '
      || (v_ev->>'loops_closed_today') || ' closed today, ' || (v_ev->>'founder_emails_today') || ' founder email(s), '
      || (v_ev->>'repeats_folded_today') || ' repeat(s) folded, '
      || jsonb_array_length(v_ev->'integrations_fixed_today') || ' integration(s) fixed without anyone, '
      || jsonb_array_length(v_ev->'integrations_failing') || ' integration(s) down ('
      || jsonb_array_length(v_ev->'integrations_waiting_on_external') || ' waiting on a provider''s ticket). '
      || coalesce(v_ev->'gmail_postmaster'->>'line', 'Gmail Postmaster: not read yet (duty postmaster has not run)'),
    v_ev, '[]'::jsonb,
    'Acknowledge the day''s IT position. Nothing else is requested; anything that needs a decision reaches you as its own report.',
    p_review_in => interval '3 hours', p_source_agent => 'it_engineer');
  if not coalesce((v_rep->>'ok')::boolean, false) then
    raise exception 'fn_it_daily_line: the CEO report was refused: %', v_rep->>'reason';
  end if;
  return jsonb_build_object('filed', true, 'report', v_rep, 'completed_after_receipt', n_done);
end $function$
;
