-- EVERY NEW BUG LEAVES A PLAYBOOK ENTRY, A REGRESSION CHECK AND AN INCIDENT RECORD; EVERY MERGE IS
-- SMOKE-TESTED. Duties 16-18 of the IT engineer, and the playbook step the loop was missing.
--
-- Assigned: it_engineer (playbook, smoke results, the learning gate, incident records); ceo reads the
-- incidents; the seat owning the changed files answers a failed smoke test.
--
-- Founder, 14 Sep 2026: "yea add them". Deterministic templates, no model.
--
-- 16 POST-DEPLOY SMOKE. .github/workflows/it-post-deploy-smoke.yml runs a short harness journey after
--    every merge whose function deploy and Vercel build succeeded, and hands the result to
--    fn_it_smoke_ingest with the merge's changed files; a failed step goes to the seat owning most of them.
-- 17 LEARNING LOOP. A finding that became a new bug (the founder was emailed) cannot be closed by the
--    IT engineer's re-check alone: its incident must carry the cause, the fix, a regression check that
--    fails if the bug returns, and either a playbook entry for its failure class or the reason it
--    cannot be automated (trigger z62). The session that fixes the bug records them with
--    fn_it_attach_learning; the loop then closes it.
-- 18 INCIDENT RECORD. public.it_incident: one row per new bug, opened when the CEO decides it is new,
--    completed by fn_it_attach_learning; fn_it_incident_pdf_blocks renders it for pdf_native (EN).
--
-- THE PLAYBOOK STEP. public.it_playbook names, per failure class, the issue keys it covers and its
-- remedy. Where the remedy is a routine, fn_it_loop_tick runs it once per occurrence before handing the
-- finding to anyone; the finding is handed on only if it is still open on the next tick.
--
--   node scripts/apply_sql.mjs scripts/sql/every_new_bug_leaves_a_playbook_entry_a_check_and_an_incident_record.sql --apply --ddl

-- ── THE PLAYBOOK ─────────────────────────────────────────────────────────────────────────────────
create table if not exists public.it_playbook (
  failure_class          text primary key check (failure_class ~ '^[a-z0-9_]+$'),
  issue_prefix           text not null check (btrim(issue_prefix) <> ''),
  remedy                 text,
  remedy_routine         text check (remedy_routine ~ '^fn_[a-z0-9_]+$'),
  not_automatable_reason text,
  regression_check       text not null check (btrim(regression_check) <> ''),
  added_by               text not null check (btrim(added_by) <> ''),
  added_at               timestamptz not null default now(),
  check (coalesce(btrim(remedy), '') <> '' or coalesce(btrim(not_automatable_reason), '') <> '')
);
comment on table public.it_playbook is
  'The IT engineer''s known failure classes: which issue keys each covers, its remedy (and the zero-argument routine that applies it, if any) or why it cannot be automated, and the check that fails if it returns.';

insert into public.it_playbook (failure_class, issue_prefix, remedy, remedy_routine, not_automatable_reason, regression_check, added_by) values
  ('otp_pumping', 'duty:otp:prefix:', 'the prefix is blocked in otp_blocked_prefix for otp_block_hours when the burst is detected', null, null,
   'scripts/checks/it_engineer_duties_9_to_18.test.mjs', 'it_engineer'),
  ('stale_rehearsal_window', 'duty:demo:window:', 'the ceo closes the rehearsal window its run left open', null, null,
   'scripts/checks/it_engineer_duties_9_to_18.test.mjs', 'it_engineer'),
  ('credential_still_presented', 'duty:rotation:', 'hold the old credential for another overlap and re-check who presents it', 'fn_it_credential_reverify', null,
   'scripts/checks/it_engineer_duties_9_to_18.test.mjs', 'it_engineer')
on conflict (failure_class) do update set issue_prefix = excluded.issue_prefix, remedy = excluded.remedy,
  remedy_routine = excluded.remedy_routine, regression_check = excluded.regression_check;

-- Runs the playbook's routine for a finding once per occurrence. True when it ran this call.
create or replace function public.fn_it_playbook_first(p_issue_key text, p_started_at timestamptz)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare p public.it_playbook;
begin
  select * into p from public.it_playbook
   where p_issue_key like issue_prefix || '%' and remedy_routine is not null
   order by length(issue_prefix) desc limit 1;
  if not found then return false; end if;
  if exists (select 1 from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'playbook'
              and counts->>'issue_key' = p_issue_key and started_at >= p_started_at) then
    return false;                              -- already tried for this occurrence: hand it on
  end if;
  if to_regprocedure('public.' || p.remedy_routine || '()') is null then
    raise exception 'playbook % names % but no such routine exists', p.failure_class, p.remedy_routine;
  end if;
  execute format('select public.%I()', p.remedy_routine);
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), now(),
          jsonb_build_object('job', 'playbook', 'issue_key', p_issue_key, 'failure_class', p.failure_class), p.remedy);
  return true;
end $fn$;
revoke execute on function public.fn_it_playbook_first(text, timestamptz) from public, anon, authenticated;

-- ── 18. INCIDENT RECORDS ─────────────────────────────────────────────────────────────────────────
create table if not exists public.it_incident (
  id                     bigint generated always as identity primary key,
  handoff_id             bigint not null unique references public.agent_actions(id),
  issue_key              text not null,
  title                  text not null,
  what                   text not null,
  impact                 text not null,
  started_at             timestamptz not null,
  ended_at               timestamptz,
  cause                  text,
  fix                    text,
  regression_check       text,
  playbook_class         text references public.it_playbook(failure_class),
  not_automatable_reason text,
  recorded_by            text,
  pdf_path               text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);
comment on table public.it_incident is
  'One record per new bug (a finding nothing inside the company fixed, so the founder was told): what happened, impact, start and end, cause, fix, the regression check and the playbook entry. Read by the CEO; rendered for an external auditor by fn_it_incident_pdf_blocks.';
do $rls$
declare t text;
begin
  foreach t in array array['it_playbook', 'it_incident'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_service_role_only', t);
    execute format('create policy %I on public.%I as permissive for all to public using (false) with check (false)', t || '_service_role_only', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end
$rls$;

create or replace function public.fn_it_incident_open(p_handoff_id bigint)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare h public.agent_actions; v_id bigint; v_pub boolean;
begin
  select * into h from public.agent_actions where id = p_handoff_id and kind = 'handoff' and detail->>'type' = 'it.finding';
  if not found then raise exception 'fn_it_incident_open: % is not an it.finding handoff', p_handoff_id; end if;
  v_pub := coalesce((h.detail->'finding_evidence'->>'public_surface')::boolean, false)
           or h.detail->>'severity' = 'critical';
  insert into public.it_incident (handoff_id, issue_key, title, what, impact, started_at)
  values (h.id, h.detail->>'issue_key', coalesce(h.detail->>'title', h.detail->>'issue_key'),
          coalesce(h.detail->>'title', h.detail->>'issue_key') || ' (' || coalesce(h.detail->>'where_it_is', h.detail->>'subject', 'not recorded') || ').',
          case when v_pub then 'Customer-facing: something a customer or supplier opens was affected.'
               else 'Internal: an agent''s work was affected; no customer-facing surface was.' end
            || ' Severity ' || coalesce(h.detail->>'severity', 'unrecorded') || '; the ' || h.agent || ' had no remedy within its reply window.',
          (h.detail->>'occurrence_started_at')::timestamptz)
  on conflict (handoff_id) do nothing
  returning id into v_id;
  return coalesce(v_id, (select id from public.it_incident where handoff_id = p_handoff_id));
end $fn$;
revoke execute on function public.fn_it_incident_open(bigint) from public, anon, authenticated;

-- ── 17. A NEW BUG CLOSES ONLY WITH WHAT WAS LEARNED ───────────────────────────────────────────────
create or replace function public.trg_new_bug_closes_with_learning()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare i public.it_incident;
begin
  if new.kind = 'handoff' and new.detail->>'type' = 'it.finding' and new.status = 'done' and old.status is distinct from 'done' then
    select * into i from public.it_incident where handoff_id = new.id;
    if found and (coalesce(btrim(i.cause), '') = '' or coalesce(btrim(i.fix), '') = '' or coalesce(btrim(i.regression_check), '') = ''
                  or (i.playbook_class is null and coalesce(btrim(i.not_automatable_reason), '') = '')) then
      raise exception 'handoff % was a new bug (incident %): it closes only with its cause, fix, a regression check and a playbook entry or the reason it cannot be automated (fn_it_attach_learning)',
        new.id, i.id;
    end if;
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_new_bug_closes_with_learning() from public, anon, authenticated;
drop trigger if exists z62_new_bug_closes_with_learning on public.agent_actions;
create trigger z62_new_bug_closes_with_learning before update of status on public.agent_actions
  for each row execute function public.trg_new_bug_closes_with_learning();

-- Called by the session that fixed the bug. Closes the loop itself when the finding is already gone.
create or replace function public.fn_it_attach_learning(
  p_handoff_id bigint, p_cause text, p_fix text, p_regression_check text,
  p_playbook_class text default null, p_not_automatable_reason text default null, p_recorded_by text default 'it_engineer')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare i public.it_incident; h public.agent_actions; f public.it_engineer_finding; v_closed boolean := false;
begin
  if coalesce(btrim(p_cause), '') = '' or coalesce(btrim(p_fix), '') = '' or coalesce(btrim(p_regression_check), '') = '' then
    raise exception 'fn_it_attach_learning: the cause, the fix and the regression check are all required';
  end if;
  if p_playbook_class is null and coalesce(btrim(p_not_automatable_reason), '') = '' then
    raise exception 'fn_it_attach_learning: name the playbook entry for this failure class, or say why it cannot be automated';
  end if;
  if p_playbook_class is not null and not exists (select 1 from public.it_playbook where failure_class = p_playbook_class) then
    raise exception 'fn_it_attach_learning: no playbook entry %; add it to public.it_playbook first', p_playbook_class;
  end if;
  update public.it_incident
     set cause = p_cause, fix = p_fix, regression_check = p_regression_check, playbook_class = p_playbook_class,
         not_automatable_reason = p_not_automatable_reason, recorded_by = p_recorded_by, updated_at = now()
   where handoff_id = p_handoff_id
  returning * into i;
  if not found then raise exception 'fn_it_attach_learning: handoff % has no incident record', p_handoff_id; end if;

  select * into h from public.agent_actions where id = p_handoff_id;
  select * into f from public.it_engineer_finding where issue_key = h.detail->>'issue_key';
  if h.status <> 'done' and (f.issue_key is null or f.closed_at is not null
                             or f.started_at > (h.detail->>'occurrence_started_at')::timestamptz) then
    perform set_config('qd.handoff_closer', 'it_engineer', true);
    perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
      'verified_by', 'it_engineer', 'verified_at', now(), 'incident_id', i.id, 'learning_recorded_by', p_recorded_by));
    perform set_config('qd.handoff_closer', '', true);
    update public.it_incident set ended_at = coalesce(f.closed_at, now()), updated_at = now() where id = i.id;
    v_closed := true;
  end if;
  return jsonb_build_object('ok', true, 'incident_id', i.id, 'closed', v_closed,
    'note', case when v_closed then 'recorded and closed' else 'recorded; the loop closes it once the IT engineer sees the finding gone' end);
end $fn$;
revoke execute on function public.fn_it_attach_learning(bigint, text, text, text, text, text, text) from public, anon, authenticated;

-- ── 18. THE AUDITOR'S PDF ────────────────────────────────────────────────────────────────────────
-- Blocks for supabase/functions/pdf_native (h2 / h3 / p / kv). English only, fixed wording.
create or replace function public.fn_it_incident_pdf_blocks(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare i public.it_incident; p public.it_playbook;
begin
  select * into i from public.it_incident where id = p_id;
  if not found then raise exception 'no incident %', p_id; end if;
  select * into p from public.it_playbook where failure_class = i.playbook_class;
  return jsonb_build_object('title', 'Incident record ' || i.id || ': ' || left(i.title, 80), 'blocks', jsonb_build_array(
    jsonb_build_object('t', 'h2', 'text', 'Incident record ' || i.id),
    jsonb_build_object('t', 'kv', 'pairs', jsonb_build_array(
      jsonb_build_array('Reference', i.issue_key),
      jsonb_build_array('Started', to_char(i.started_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' (Dubai)'),
      jsonb_build_array('Ended', coalesce(to_char(i.ended_at at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' (Dubai)', 'Still open')),
      jsonb_build_array('Duration', coalesce(to_char(i.ended_at - i.started_at, 'DD "days" HH24 "h" MI "min"'), 'Still open')),
      jsonb_build_array('Recorded by', coalesce(i.recorded_by, 'Not yet recorded')))),
    jsonb_build_object('t', 'h3', 'text', 'What happened'), jsonb_build_object('t', 'p', 'text', i.what),
    jsonb_build_object('t', 'h3', 'text', 'Impact'), jsonb_build_object('t', 'p', 'text', i.impact),
    jsonb_build_object('t', 'h3', 'text', 'Cause'), jsonb_build_object('t', 'p', 'text', coalesce(i.cause, 'Not yet recorded.')),
    jsonb_build_object('t', 'h3', 'text', 'Fix'), jsonb_build_object('t', 'p', 'text', coalesce(i.fix, 'Not yet recorded.')),
    jsonb_build_object('t', 'h3', 'text', 'Regression check'),
    jsonb_build_object('t', 'p', 'text', coalesce(i.regression_check, 'Not yet recorded.')),
    jsonb_build_object('t', 'h3', 'text', 'Playbook entry'),
    jsonb_build_object('t', 'p', 'text', case
      when p.failure_class is not null then p.failure_class || ': ' || coalesce(p.remedy, p.not_automatable_reason)
      when i.not_automatable_reason is not null then 'Not automatable: ' || i.not_automatable_reason
      else 'Not yet recorded.' end)));
end $fn$;
revoke execute on function public.fn_it_incident_pdf_blocks(bigint) from public, anon, authenticated;

-- ── 16. POST-DEPLOY SMOKE ────────────────────────────────────────────────────────────────────────
-- p_report: {sha, changed_files:[...], tag, steps:[{journey, name, status, detail}]}. The owner is the
-- seat owning most of the changed files (supabase/functions/<slug>/ through function_owner; anything
-- else, and a 'website' owner, is the ceo's).
create or replace function public.fn_it_smoke_ingest(p_report jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_owner text; v_owners jsonb; x jsonb; v_items jsonb := '[]'::jsonb; v_res jsonb;
begin
  if jsonb_typeof(p_report->'steps') is distinct from 'array' or coalesce(btrim(p_report->>'sha'), '') = '' then
    raise exception 'fn_it_smoke_ingest takes {sha, changed_files, steps} from scripts/e2e/report_to_it_engineer.mjs --smoke';
  end if;
  with files as (
    select f from jsonb_array_elements_text(coalesce(p_report->'changed_files', '[]'::jsonb)) f),
  owned as (
    select case when o.owner in (select t.to_seat from public.fn_seat_handoff_types() t where t.type = 'it.finding')
                then o.owner else 'ceo' end seat
      from files
      left join public.function_owner o on o.function_slug = substring(files.f from '^supabase/functions/([^/_][^/]*)/'))
  select coalesce(jsonb_object_agg(seat, n), '{}'::jsonb) into v_owners
    from (select seat, count(*) n from owned group by seat) z;
  select key into v_owner from jsonb_each_text(v_owners) order by value::int desc, key limit 1;
  for x in select e from jsonb_array_elements(p_report->'steps') e where e->>'status' = 'FAIL' loop
    v_items := v_items || jsonb_build_object(
      'item', coalesce(x->>'journey', '?') || ':' || left(regexp_replace(coalesce(x->>'name', '?'), '[^a-zA-Z0-9]+', '_', 'g'), 80),
      'owner_seat', coalesce(v_owner, 'ceo'), 'subject', 'merge ' || left(p_report->>'sha', 7),
      'title', 'After merge ' || left(p_report->>'sha', 7) || ', the smoke test failed: [' || coalesce(x->>'journey', '?') || '] ' || coalesce(x->>'name', '?'),
      'blast', 'customer_facing', 'affected', 0, 'demo', coalesce((p_report->>'demo')::boolean, false),
      'evidence', jsonb_build_object('sha', p_report->>'sha', 'owners', v_owners, 'changed_files', p_report->'changed_files',
                                     'tag', p_report->>'tag', 'detail', left(x->>'detail', 600)));
  end loop;
  v_res := public.fn_it_duty_settle('smoke', v_items);
  perform public.fn_it_duty_ran('smoke', v_res || jsonb_build_object('sha', p_report->>'sha'));
  return v_res;
end $fn$;
revoke execute on function public.fn_it_smoke_ingest(jsonb) from public, anon, authenticated;
