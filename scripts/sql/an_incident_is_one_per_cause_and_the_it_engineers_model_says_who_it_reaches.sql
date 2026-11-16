-- AN INCIDENT IS ONE PER CAUSE, AND THE IT ENGINEER'S MODEL SAYS WHO IT REACHES (16 Nov 2026). Seat: it_engineer.
-- Agent: OPS_LOOPS (it_engineer + ceo builder, wave 2 of the real-company holes; hole H3 of the COO hunt).
--
-- MEASURED (production, read-only SELECT, 16 Nov 2026):
--   * it_incident, last 7 days: 1,898 rows, about 270 a day. 1,029 are playbook class delivery_request_unconfirmed, each
--     its own issue key (duty:delivery:request:<id>, one prefix); 570 heartbeat_step (40 keys, one prefix); 41
--     model_runaway; 203 with no playbook class (142 keys, 54 prefixes, 74 still open). A real outage would be one row in
--     two hundred.
--   * 0 of the 1,898 have customer_impact and 0 have a customer note. customer_support.incident_notices (CS-C12) sends
--     only for it_incident.customer_impact in (customers, suppliers, everyone); the column's own comment says
--     "Set by it_engineer", and no code writes it (READ: grep of scripts/sql, supabase/functions and the mirror).
--
-- WHAT THIS ADDS (one duty, it_engineer.incident_impact, every 15 minutes)
--   1. ONE INCIDENT PER CAUSE. it_incident.cause_key names the cause an incident belongs to: its playbook class when it
--      has one, otherwise the first two parts of its fault key (fn_it_postmortem_class_key, the same key the postmortem
--      already uses to ask once per class), otherwise its issue key. A new incident whose cause already has a ROOT seen in
--      the last 24 hours becomes an occurrence of that root (same_cause_as = the root, cause copied from it); the root
--      counts it (occurrences, last_seen_at) and keeps the latest end. Everything that works per handoff keeps working
--      (one row per it.finding, unique handoff_id); the register a person reads is the roots (view it_incident_register).
--   2. THE MODEL SAYS WHO IT REACHES. For every root whose finding the detector marked as touching a public surface (the
--      same fact fn_it_incident_open writes into `impact`: finding_evidence.public_surface, or severity critical), the duty
--      files ONE held question to the it_engineer seat (surface it_engineer.incident_impact) with the facts: what failed
--      and where, since when, how often, the cause if known, the finding's evidence, and the support conversations active
--      in the window by side. The model picks none / customers / suppliers / everyone and writes, for the people affected,
--      one or two plain sentences on what is affected for them. fn_reason_apply_it_engineer__incident_impact writes
--      customer_impact and customer_note_en; customer_support.incident_notices (unchanged) then sends the holding message
--      to everyone of that side mid-conversation while the incident is open, and the resolved one when it ends.
--      A root the detector marked internal (no public surface) is recorded as judged with that reason and no model call:
--      a self-healing class stays a log. The model decides meaning; code only routes by the detector's flag, checks the
--      choice is one of the four, and never sends.
-- WHAT IT DOES NOT CHANGE: fn_it_incident_open, fn_it_engineer_postmortem, the notice duty, any existing incident's
-- cause or end. Incidents older than 3 days are not re-keyed.
--
-- Probe: scripts/sql/an_incident_is_one_per_cause_and_the_it_engineers_model_says_who_it_reaches_probe.sql (local PG16).
-- Pending: scripts/sql/pending/an_incident_is_one_per_cause_and_the_it_engineers_model_says_who_it_reaches.txt
-- prevented by: scripts/checks/the_ops_loops_close_against_what_they_measure.test.mjs and the probe.
--   node scripts/apply_sql.mjs scripts/sql/an_incident_is_one_per_cause_and_the_it_engineers_model_says_who_it_reaches.sql --apply --ddl

set local lock_timeout = '3s';
alter table public.it_incident
  add column if not exists cause_key text,
  add column if not exists same_cause_as bigint references public.it_incident (id),
  add column if not exists occurrences integer not null default 1,
  add column if not exists last_seen_at timestamptz,
  add column if not exists impact_judged_at timestamptz,
  add column if not exists impact_judgement jsonb;
comment on column public.it_incident.cause_key is
  'The cause this incident belongs to: playbook:<class>, class:<first two parts of the fault key> or issue:<key>. Written by fn_it_incident_collapse.';
comment on column public.it_incident.same_cause_as is
  'Set when this incident is another occurrence of a root seen in the last 24 hours with the same cause_key; null on a root.';
comment on column public.it_incident.impact_judged_at is
  'When the it_engineer seat judged who this root reaches (the model, or the detector''s internal flag); customer_impact holds the answer.';

create index if not exists it_incident_cause_root_idx on public.it_incident (cause_key, id desc) where same_cause_as is null;

create or replace view public.it_incident_register with (security_invoker = true) as
  select i.* from public.it_incident i where i.same_cause_as is null;
comment on view public.it_incident_register is 'One row per cause: the roots of it_incident (occurrences of the same cause within 24 hours are folded into their root).';
revoke all on public.it_incident_register from anon, authenticated;

-- 1. one incident per cause
create or replace function public.fn_it_incident_collapse(p_limit integer default 2000)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare i record; v_key text; v_root public.it_incident; n_root int := 0; n_occ int := 0;
begin
  for i in
    select inc.id, inc.issue_key, inc.playbook_class, inc.cause, inc.started_at, inc.created_at, inc.ended_at, a.detail
      from public.it_incident inc join public.agent_actions a on a.id = inc.handoff_id
     where inc.cause_key is null and inc.created_at > now() - interval '3 days'
     order by inc.id
     limit greatest(1, least(coalesce(p_limit, 2000), 5000))
  loop
    v_key := coalesce('playbook:' || i.playbook_class, 'class:' || public.fn_it_postmortem_class_key(i.detail), 'issue:' || i.issue_key);
    select r.* into v_root from public.it_incident r
     where r.cause_key = v_key and r.same_cause_as is null and r.id < i.id
       and coalesce(r.last_seen_at, r.started_at, r.created_at) > coalesce(i.started_at, i.created_at) - interval '24 hours'
     order by r.id desc limit 1;
    if v_root.id is null then
      update public.it_incident set cause_key = v_key, last_seen_at = coalesce(started_at, created_at), updated_at = now() where id = i.id;
      n_root := n_root + 1;
    else
      update public.it_incident
         set cause_key = v_key, same_cause_as = v_root.id,
             cause = coalesce(nullif(btrim(cause), ''), left('Same cause as incident ' || v_root.id
                       || coalesce(': ' || nullif(btrim(v_root.cause), ''), ''), 2000)),
             recorded_by = coalesce(recorded_by, 'it_engineer.incident_impact (occurrence of ' || v_root.id || ')'),
             updated_at = now()
       where id = i.id;
      update public.it_incident
         set occurrences = occurrences + 1,
             last_seen_at = greatest(coalesce(last_seen_at, started_at, created_at), coalesce(i.started_at, i.created_at)),
             ended_at = case when ended_at is null or i.ended_at is null then ended_at else greatest(ended_at, i.ended_at) end,
             updated_at = now()
       where id = v_root.id;
      n_occ := n_occ + 1;
    end if;
    v_root := null;
  end loop;
  return jsonb_build_object('roots', n_root, 'occurrences_folded', n_occ);
end $fn$;
revoke execute on function public.fn_it_incident_collapse(integer) from public, anon, authenticated;

-- 2. the model says who it reaches
create or replace function public.fn_it_incident_impact_ask(p_limit integer default 5)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  i record; v_pub boolean; v_hid bigint; n_asked int := 0; n_internal int := 0; n_waiting int := 0;
  v_cases jsonb; v_runs jsonb; v_q text; v_from timestamptz;
begin
  for i in
    select inc.*, a.detail adetail, a.evidence aevidence, a.agent aagent
      from public.it_incident inc join public.agent_actions a on a.id = inc.handoff_id
     where inc.same_cause_as is null and inc.cause_key is not null and inc.impact_judged_at is null
       and inc.created_at > now() - interval '2 days'
       and (coalesce(inc.title, '') like 'ZZ DEMO%') = v_fx
       and not public.fn_it_finding_is_fixture(a.detail, a.evidence)
     order by inc.ended_at is null desc, inc.id desc
  loop
    -- the detector's own flag, the one fn_it_incident_open writes into `impact`
    v_pub := coalesce((i.adetail->'finding_evidence'->>'public_surface')::boolean, false) or i.adetail->>'severity' = 'critical';
    if not v_pub then
      update public.it_incident set impact_judged_at = now(), impact_judgement = jsonb_build_object('choice', 'none', 'by', 'detector',
               'why', 'the detector marked no customer-facing surface (finding_evidence.public_surface false, severity '
                      || coalesce(i.adetail->>'severity', 'unrecorded') || '); kept as a log'), updated_at = now()
       where id = i.id;
      n_internal := n_internal + 1;
      continue;
    end if;
    if exists (select 1 from public.reasoning_held_question q where q.dedupe_key = 'incident_impact:' || i.id) then
      n_waiting := n_waiting + 1;
      continue;
    end if;
    exit when n_asked >= greatest(1, coalesce(p_limit, 5));
    v_from := coalesce(i.started_at, i.created_at) - interval '1 hour';
    -- who was mid-conversation with us in the window, by side (counts only: never a person's details)
    select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) into v_cases from (
      select s.party_kind k, count(*) n from public.support_case s join public.support_customer_profile pr on pr.id = s.customer_profile_id
       where s.last_activity_at >= v_from and pr.email is not null and public.fn_is_demo_email(pr.email) = v_fx
       group by s.party_kind) z;
    select jsonb_build_object('errors', count(*) filter (where r.status = 'error'), 'runs', count(*),
             'sample_error', left(min(r.note) filter (where r.status = 'error'), 300))
      into v_runs from public.agent_runs r
     where r.started_at >= v_from and (r.agent = i.aagent or r.agent = coalesce(i.adetail->>'subject', '-') or r.agent = 'fn:' || coalesce(i.adetail->>'subject', '-'));
    v_q := 'Incident ' || i.id || ': who outside the company does it reach? ' || coalesce(i.title, i.issue_key)
        || '. Pick none, customers, suppliers or everyone. Then write, for the people it reaches, one or two plain sentences saying '
        || 'what part of QuotesDone is affected for them right now; no cause, no internal names, no promised time. If none, '
        || 'write in one sentence why no customer or supplier could see or feel it.';
    v_hid := public.fn_reason_hold('it_engineer', 'it_engineer.incident_impact', v_q,
      jsonb_build_object('seat', 'it_engineer', 'surface', 'it_engineer.incident_impact', 'research', false, 'stakes', 'normal',
        'question', v_q,
        'context', jsonb_build_object('audience', 'internal', 'case', jsonb_build_object(
          'what', i.what, 'where', coalesce(i.adetail->>'where_it_is', i.adetail->>'subject'), 'severity', i.adetail->>'severity',
          'started_at', i.started_at, 'ended_at', i.ended_at, 'still_open', i.ended_at is null,
          'occurrences', i.occurrences, 'last_seen_at', i.last_seen_at, 'cause', i.cause, 'playbook_class', i.playbook_class,
          'finding_evidence', left(coalesce(i.adetail->'finding_evidence', '{}'::jsonb)::text, 2000),
          'answer_from_owner', left(coalesce(i.aevidence, '{}'::jsonb)::text, 1000),
          'support_conversations_active_in_window_by_side', v_cases, 'runs_of_the_failing_agent_in_window', v_runs)),
        'decision', jsonb_build_object('name', 'customer_impact', 'options', jsonb_build_array(
          jsonb_build_object('id', 'none', 'meaning', 'internal only: no customer or supplier could see or feel it'),
          jsonb_build_object('id', 'customers', 'meaning', 'customers (people asking for quotes) could see or feel it'),
          jsonb_build_object('id', 'suppliers', 'meaning', 'suppliers (companies that quote) could see or feel it'),
          jsonb_build_object('id', 'everyone', 'meaning', 'both customers and suppliers could see or feel it'))),
        'subject', jsonb_build_object('incident_id', i.id), 'dedupeKey', 'incident_impact:' || i.id),
      jsonb_build_object('filed_by', 'it_engineer.incident_impact'), jsonb_build_object('incident_id', i.id, 'fixture', v_fx),
      'seat_duty', 'incident_impact:' || i.id);
    if v_hid is not null then
      update public.it_incident set impact_judgement = jsonb_build_object('asked', v_hid, 'asked_at', now()), updated_at = now() where id = i.id;
      n_asked := n_asked + 1;
    end if;
  end loop;
  return jsonb_build_object('asked', n_asked, 'internal_by_detector', n_internal, 'waiting_on_the_model', n_waiting);
end $fn$;
revoke execute on function public.fn_it_incident_impact_ask(integer) from public, anon, authenticated;

create or replace function public.fn_reason_apply_it_engineer__incident_impact(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_inc bigint; v_choice text := p_result->'decision'->>'choice';
        v_ans text := btrim(coalesce(p_result->>'answer', ''));
begin
  select * into r from public.reasoning_held_question where id = p_id;
  v_inc := nullif(r.subject->>'incident_id', '')::bigint;
  -- code only checks the model's answer against what is certain: one of the four, and words for the people it reaches
  if v_inc is null or v_choice is null or v_choice not in ('none', 'customers', 'suppliers', 'everyone')
     or (v_choice <> 'none' and v_ans = '') then
    return null;                                   -- nothing applied: the row stays 'reasoned' for the seat to read
  end if;
  update public.it_incident
     set customer_impact = case when v_choice = 'none' then null else v_choice end,
         customer_note_en = case when v_choice = 'none' then customer_note_en else left(v_ans, 400) end,
         impact_judged_at = now(),
         impact_judgement = jsonb_build_object('choice', v_choice, 'by', 'model', 'model', p_result->>'model', 'held_id', p_id,
                                               'answer', left(v_ans, 600), 'judged_at', now()),
         updated_at = now()
   where id = v_inc and same_cause_as is null;
  return jsonb_build_object('incident_id', v_inc, 'customer_impact', v_choice, 'applied', found);
end $fn$;
revoke execute on function public.fn_reason_apply_it_engineer__incident_impact(bigint, jsonb) from public, anon, authenticated;

create or replace function public.fn_it_incident_impact_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp'
as $fn$
begin
  return jsonb_build_object('collapse', public.fn_it_incident_collapse(2000), 'impact', public.fn_it_incident_impact_ask(5),
    'register_roots_24h', (select count(*) from public.it_incident where same_cause_as is null and cause_key is not null and created_at > now() - interval '24 hours'),
    'incidents_24h', (select count(*) from public.it_incident where created_at > now() - interval '24 hours'));
end $fn$;
revoke execute on function public.fn_it_incident_impact_tick() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file)
values ('it_engineer.incident_impact', 'it_engineer', interval '15 minutes', 'fn_it_incident_impact_tick',
        'One incident per cause (an occurrence of a cause seen in the last 24 hours folds into its root), and for every root the detector marked customer-facing the it_engineer''s model says who it reaches and what to tell them, which customer_support.incident_notices sends.',
        'scripts/sql/an_incident_is_one_per_cause_and_the_it_engineers_model_says_who_it_reaches.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

comment on column public.it_incident.customer_impact is
  'Who a customer-facing incident touches (customers | suppliers | everyone); null = internal. Set by the it_engineer seat''s model (it_engineer.incident_impact); customer_support.incident_notices writes the holding and resolved messages.';

-- VERDICT (this file defines routines, so it never raises to report)
select case
  when not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'it_incident' and column_name = 'same_cause_as')
    then 'PROBE FAILED: it_incident has no same_cause_as'
  when has_function_privilege('anon', 'public.fn_it_incident_collapse(integer)', 'execute')
    or has_function_privilege('anon', 'public.fn_it_incident_impact_ask(integer)', 'execute')
    or has_function_privilege('anon', 'public.fn_reason_apply_it_engineer__incident_impact(bigint, jsonb)', 'execute')
    or has_function_privilege('anon', 'public.fn_it_incident_impact_tick()', 'execute')
    then 'PROBE FAILED: anon can execute an incident routine'
  when not exists (select 1 from public.seat_duty where duty = 'it_engineer.incident_impact' and enabled)
    then 'PROBE FAILED: the incident impact duty is not registered'
  else 'PROBE OK' end as verdict;
