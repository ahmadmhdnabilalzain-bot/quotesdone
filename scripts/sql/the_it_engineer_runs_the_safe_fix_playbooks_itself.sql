-- THE IT ENGINEER RUNS THE SAFE-FIX PLAYBOOKS ITSELF: A MATCHING FINDING RUNS ITS FIX AND RECORDS THE OUTCOME.
-- Seat: it_engineer (the playbooks and the dispatcher). The CEO approves a NEW playbook family once
-- (fn_ceo_approves_safe_fix_family); the eight families below are approved by founder ruling 1574 (10 Nov 2026): "the IT
-- engineer fixes the glitches it can fix itself (not core code) instead of sending counts of problems". 1574 supersedes the
-- 9 Sep charter's data_mutation / job_rerun prohibitions for these operational-safe families ONLY; deploys, code, schema
-- changes, secrets (apart from triggering the rotation that already exists) and business data (leads, quotes, money)
-- stay forbidden, and every family's guardrail below says what it may not touch.
--
-- MEASURED BEFORE WRITING (production htdblwldjkcgjvmqkbeh, read-only, 10 Nov 2026):
--   it_playbook: 54 rows, 1 with a remedy_routine; agent_runs with job 'playbook': 0 ever. Open findings of the families:
--     duty:credential_rotation_age:overdue:*   40  (43 internal credentials past 90+7 days; the scheduled rotation does 3 a day)
--     duty:workflow_audit:*                    67  (raised 2 Nov by the weekly workflow reading; GitHub Actions off, ruling 1564)
--     duty:delivery:request:*                  16  (all 16: handoff done, its notification row gone, detail.loop never written)
--     marketing:step_quarantined:*              5  (quality_review, 3 days of "evidence ... does not exist")
--     duty:model_spend:unlisted:*               4  (2 attributable through function_owner: sales_engineer, extract_text)
--     watch:queue_stalled:doc_backups_failed    1  (doc_backups 445197: "abandoned: no source in storage", 689 h)
--   plus 53 it.finding handoffs whose occurrence is over and 822 parked model questions (the two sweeper families).
--
-- WHAT THIS FILE DOES:
--   1. public.it_safe_fix_family: one row per playbook family: the findings it matches (issue_like), the routine, the
--      guardrail in words, the most runs per occurrence and per tick, and its approval (ruling 1574, or the CEO's once).
--      A CHECK refuses an active family with no approval; fn_ceo_approves_safe_fix_family is the CEO's one approval.
--   2. public.it_safe_fix_run: the audit row of every run: family, finding, occurrence, outcome (fixed / nothing_to_do /
--      refused_by_guardrail / failed) and what the routine read and did.
--   3. Eight deterministic routines, one per family, each verifying after it acts:
--        close_cleared_handoffs   fn_it_close_cleared_handoffs (the_originators_close_..._condition_cleared.sql)
--        delivery_outcome         writes the delivery loop's outcome on a request whose notification row is gone
--                                 ('record_removed', the loop's own word), whose notification reached a final status, or
--                                 that is past the 72 h provider window ('outcome_unknown'); never re-sends anything
--        model_consumer           registers an unlisted model caller in it_model_consumer when function_owner names its
--                                 seat; an unattributable caller is refused and stays a finding
--        workflow_park            closes a duty:workflow_audit finding as parked while ruling 1564 stands (the reading that
--                                 raised it cannot run; it re-raises when Actions return)
--        credential_rotation      triggers the existing fn_it_credential_rotate for an overdue internal credential (the same
--                                 predicate as the scheduled rotation duty), then checks the rotation row is in overlap
--        backup_requeue           re-queues an errored doc backup that HAS a storage source, once a week; an abandoned
--                                 one with no source is refused (nothing to copy)
--        marketing_step_retry     releases a quarantined marketing step once (public.marketing_step_release; the quarantine
--                                 counts only runs after the release); a second quarantine stays marketing's
--        expire_parked_questions  fn_held_questions_settle (a_parked_model_question_has_an_owner_and_a_deadline.sql)
--   4. fn_it_safe_fix_tick() (duty it_engineer.safe_fix, hourly): runs each active family on its matching open findings
--      (or once, for a sweeper), within its per-occurrence and per-tick bounds; two failed runs in a day PARK the family
--      (active false, with the reason) for the session's list.
--   5. fn_marketing_subject_blocked: the quarantine counts the runs after the step's release (the live body otherwise).
--
-- Prevented by: scripts/checks/the_it_engineer_runs_the_safe_fix_playbooks_itself.test.mjs (every family has a routine,
-- a guardrail and an approval; no family routine writes a business table; rolled-back replay: what each family fixes today).
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineer_runs_the_safe_fix_playbooks_itself.sql --apply --ddl --seat it_engineer

create table if not exists public.it_safe_fix_family (
  family text primary key check (family ~ '^[a-z_]+$'),
  issue_like text,                                   -- null: a sweeper, run once per tick
  routine text not null check (routine ~ '^fn_[a-z0-9_]+$'),
  guardrail text not null check (length(btrim(guardrail)) >= 30),
  max_runs_per_occurrence integer not null default 1 check (max_runs_per_occurrence between 1 and 3),
  max_per_tick integer not null default 20 check (max_per_tick between 1 and 500),
  approval_ruling integer,
  ceo_approved_at timestamptz,
  ceo_approval_reasons text,
  active boolean not null default false,
  parked_at timestamptz,
  parked_reason text,
  owner_file text not null check (owner_file ~ '^scripts/sql/[a-z0-9_]+\.sql$'),
  recorded_at timestamptz not null default now(),
  check (not active or approval_ruling is not null or ceo_approved_at is not null)
);
alter table public.it_safe_fix_family enable row level security;
drop policy if exists it_safe_fix_family_service_role_only on public.it_safe_fix_family;
create policy it_safe_fix_family_service_role_only on public.it_safe_fix_family as permissive for all to public using (false) with check (false);
revoke all on public.it_safe_fix_family from anon, authenticated;

create table if not exists public.it_safe_fix_run (
  id bigint generated always as identity primary key,
  family text not null references public.it_safe_fix_family(family),
  issue_key text,
  occurrence_started_at timestamptz,
  ran_at timestamptz not null default now(),
  outcome text not null check (outcome in ('fixed', 'nothing_to_do', 'refused_by_guardrail', 'failed')),
  result jsonb not null default '{}'::jsonb,
  error text
);
create index if not exists it_safe_fix_run_family_issue_idx on public.it_safe_fix_run (family, issue_key, occurrence_started_at);
alter table public.it_safe_fix_run enable row level security;
drop policy if exists it_safe_fix_run_service_role_only on public.it_safe_fix_run;
create policy it_safe_fix_run_service_role_only on public.it_safe_fix_run as permissive for all to public using (false) with check (false);
revoke all on public.it_safe_fix_run from anon, authenticated;

create table if not exists public.marketing_step_release (
  step text not null, subject text not null,
  released_at timestamptz not null default now(), released_by text not null default 'it_engineer',
  why text not null check (length(btrim(why)) >= 10),
  primary key (step, subject)
);
alter table public.marketing_step_release enable row level security;
drop policy if exists marketing_step_release_service_role_only on public.marketing_step_release;
create policy marketing_step_release_service_role_only on public.marketing_step_release as permissive for all to public using (false) with check (false);
revoke all on public.marketing_step_release from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('it_safe_fix_family', true, 'company', 'the IT engineer''s approved safe-fix playbook families, their guardrails and approvals (ruling 1574)', 'it_engineer'),
  ('it_safe_fix_run', true, 'decision', 'one audit row per safe-fix playbook run: the finding, the outcome and what the routine read and did', 'it_engineer'),
  ('marketing_step_release', true, 'marketing', 'a quarantined marketing step released once by the IT engineer''s playbook (ruling 1574)', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason;

-- ── 5. THE QUARANTINE COUNTS THE RUNS AFTER A RELEASE (live body, 10 Nov 2026, plus the release) ─────────────────
create or replace function public.fn_marketing_subject_blocked(p_step text, p_subject text, p_at timestamp with time zone default now())
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with d as (select (p_at at time zone 'Asia/Dubai')::date today),
       rel as (select max(x.released_at) at from public.marketing_step_release x where x.step = p_step and x.subject = p_subject)
  select case
    -- counted SINCE the last written run, not in a window tied to today: a quarantine does not lapse at midnight;
    -- and since the step's one release (10 Nov 2026, the IT engineer's safe-fix playbook), when there was one
    when (select count(distinct r.run_day) from public.marketing_model_run r, rel
           where r.step = p_step and r.subject = p_subject and r.outcome in ('rejected','failed')
             and (rel.at is null or r.created_at > rel.at)
             and r.id > coalesce((select max(w.id) from public.marketing_model_run w
                                   where w.step = p_step and w.subject = p_subject and w.outcome = 'written'), 0)) >= 3
      then 'quarantined: failed on 3 or more days since its last written run'
    when (select count(*) from public.marketing_model_run r, d where r.step = p_step and r.subject = p_subject
           and r.outcome in ('written','rejected','failed') and r.run_day = d.today) >= 2
      then 'attempt cap: 2 attempts today'
  end
$fn$;

revoke execute on function public.fn_marketing_subject_blocked(text, text, timestamp with time zone) from public, anon, authenticated;

-- ── 3. THE FAMILY ROUTINES (each returns {outcome, ...}) ──────────────────────────────────────────────────────
create or replace function public.fn_it_safe_fix_close_cleared_handoffs()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb := public.fn_it_close_cleared_handoffs(200);
begin
  return v || jsonb_build_object('outcome', case when coalesce((v->>'errors')::int, 0) > 0 and coalesce((v->>'closed')::int, 0) = 0 then 'failed'
                                                 when coalesce((v->>'closed')::int, 0) > 0 then 'fixed' else 'nothing_to_do' end);
end $fn$;

create or replace function public.fn_it_safe_fix_expire_parked_questions()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb := public.fn_held_questions_settle(1000);
begin
  return v || jsonb_build_object('outcome', case when coalesce((v->>'done')::int, 0) + coalesce((v->>'dismissed')::int, 0) > 0 then 'fixed' else 'nothing_to_do' end);
end $fn$;

create or replace function public.fn_it_safe_fix_delivery_outcome(p_issue_key text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint; a public.agent_actions; n public.notifications; v_loop text;
begin
  v_id := nullif(substring(p_issue_key from '^duty:delivery:request:([0-9]+)$'), '')::bigint;
  if v_id is null then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'not a delivery request finding'); end if;
  select * into a from public.agent_actions where id = v_id and kind = 'handoff' and detail->>'type' = 'delivery.request';
  if a.id is null then return jsonb_build_object('outcome', 'nothing_to_do', 'why', 'the request no longer exists'); end if;
  if a.detail ? 'loop' then return jsonb_build_object('outcome', 'nothing_to_do', 'why', 'the loop already has its outcome', 'loop', a.detail->'loop'); end if;
  select * into n from public.notifications where id = case when a.evidence->>'notification_id' ~ '^[0-9]+$' then (a.evidence->>'notification_id')::bigint end;
  if n.id is null then
    v_loop := 'record_removed';                                              -- the delivery loop's own word for a vanished row
  elsif n.status in ('delivered', 'failed', 'bounced', 'suppressed', 'cancelled')
        or (n.status = 'sent' and coalesce(btrim(n.provider_message_id), '') <> '') then
    v_loop := 'notification_' || n.status;
  elsif a.created_at < now() - interval '72 hours' then
    v_loop := 'outcome_unknown';                                              -- past the provider's final window
  else
    return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'still inside the 72-hour provider window', 'notification_status', n.status);
  end if;
  update public.agent_actions
     set detail = detail || jsonb_build_object('loop', v_loop, 'loop_at', now(), 'loop_by', 'it_engineer safe fix: delivery_outcome',
                                              'loop_reading', jsonb_build_object('notification_id', a.evidence->'notification_id', 'notification_status', n.status))
   where id = a.id and not (detail ? 'loop');
  if not exists (select 1 from public.agent_actions where id = a.id and detail->>'loop' = v_loop) then
    return jsonb_build_object('outcome', 'failed', 'why', 'the loop outcome did not land');
  end if;
  return jsonb_build_object('outcome', 'fixed', 'handoff_id', a.id, 'loop', v_loop, 'notification_status', n.status);
end $fn$;

create or replace function public.fn_it_safe_fix_model_consumer(p_issue_key text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_consumer text := substring(p_issue_key from '^duty:model_spend:unlisted:(.+)$'); v_fn text; v_owner text;
begin
  if v_consumer is null or v_consumer !~ '^[a-z0-9_]+[:.][a-z0-9_]+$' then
    return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'not a caller key the inventory can hold', 'consumer', v_consumer);
  end if;
  if exists (select 1 from public.it_model_consumer where consumer = v_consumer) then
    return jsonb_build_object('outcome', 'nothing_to_do', 'why', 'already in the inventory', 'consumer', v_consumer);
  end if;
  v_fn := split_part(v_consumer, ':', 1);
  select f.owner into v_owner from public.function_owner f join public.org_role r on r.role_id = f.owner and r.status = 'active'
   where f.function_slug = v_fn;
  if v_owner is null then
    return jsonb_build_object('outcome', 'refused_by_guardrail', 'consumer', v_consumer,
      'why', 'no function_owner row names a live seat for ' || v_fn || ': the caller cannot be attributed, so it stays a finding');
  end if;
  insert into public.it_model_consumer (consumer, owner_seat, why_a_model)
  values (v_consumer, v_owner, 'auto-registered by the IT engineer''s safe-fix playbook from function_owner (' || v_fn || ' is ' || v_owner
          || '''s, ruling 1574); the owning seat states the reason and the expected daily spend')
  on conflict (consumer) do nothing;
  if not public.fn_it_model_consumer_listed(v_fn, split_part(v_consumer, ':', 2)) then
    return jsonb_build_object('outcome', 'failed', 'why', 'registered, and fn_it_model_consumer_listed still says unlisted', 'consumer', v_consumer);
  end if;
  return jsonb_build_object('outcome', 'fixed', 'consumer', v_consumer, 'owner_seat', v_owner);
end $fn$;

create or replace function public.fn_it_safe_fix_workflow_park(p_issue_key text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare f public.it_engineer_finding;
begin
  if p_issue_key not like 'duty:workflow\_audit:%' then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'not a workflow finding'); end if;
  if not exists (select 1 from public.founder_instruction where id = 1564 and status = 'standing') then
    return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'founder ruling 1564 (GitHub Actions off) no longer stands: the workflow finding is real again');
  end if;
  select * into f from public.it_engineer_finding where issue_key = p_issue_key and closed_at is null;
  if f.issue_key is null then return jsonb_build_object('outcome', 'nothing_to_do', 'why', 'already closed'); end if;
  perform public.fn_it_engineer_finding_close(p_issue_key,
    'parked by the IT engineer''s safe-fix playbook: GitHub Actions are off (founder ruling 1564), so this workflow cannot run and the weekly reading that raised it '
    || 'does not run either; it re-raises when Actions return');
  if exists (select 1 from public.it_engineer_finding where issue_key = p_issue_key and closed_at is null) then
    return jsonb_build_object('outcome', 'failed', 'why', 'the finding did not close');
  end if;
  return jsonb_build_object('outcome', 'fixed', 'parked', p_issue_key);
end $fn$;

create or replace function public.fn_it_safe_fix_credential_rotation(p_issue_key text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_ctx text := substring(p_issue_key from '^duty:credential_rotation_age:overdue:(.+)$'); c public.internal_credential; v jsonb;
  v_days int := coalesce(public.fn_it_threshold('credential_rotate_days'), 90)::int;
begin
  if v_ctx is null then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'not an overdue-credential finding'); end if;
  -- exactly the scheduled rotation duty's predicate (fn_it_duties, ROTATION), past the 7-day grace
  select ic.* into c from public.internal_credential ic
   where ic.context = v_ctx and ic.active and ic.retired_at is null and not ic.is_legacy
     and exists (select 1 from public.app_secrets s where s.key = 'cred_' || replace(ic.context, '.', '_'))
     and not exists (select 1 from public.it_credential_rotation r where r.context = ic.context and r.status in ('overlap', 'held'))
     and coalesce(ic.rotated_at, ic.created_at) < now() - make_interval(days => v_days + 7)
   order by coalesce(ic.rotated_at, ic.created_at) limit 1 for update skip locked;
  if c.id is null then
    return jsonb_build_object('outcome', 'nothing_to_do', 'why', 'no overdue, rotatable credential for ' || v_ctx || ' (rotated, in overlap, legacy or keyless)');
  end if;
  v := public.fn_it_credential_rotate(c.id);
  if not exists (select 1 from public.it_credential_rotation r where r.context = v_ctx and r.new_id = (v->>'new_id')::bigint and r.status = 'overlap') then
    return jsonb_build_object('outcome', 'failed', 'why', 'the rotation row is not in overlap', 'rotation', v);
  end if;
  return jsonb_build_object('outcome', 'fixed', 'context', v_ctx, 'rotation', v - 'secret');
end $fn$;

create or replace function public.fn_it_safe_fix_backup_requeue(p_issue_key text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare n_req int := 0; n_refused int := 0; v_refused jsonb := '[]'::jsonb; d record;
begin
  for d in select b.id, b.bucket, b.path, b.error, b.requeued_at from public.doc_backups b
            where b.status = 'error' and b.entity <> 'zz_demo' order by b.id limit 20 loop
    if d.bucket is null or d.path is null or coalesce(d.error, '') like 'abandoned:%' then
      n_refused := n_refused + 1;
      v_refused := v_refused || jsonb_build_object('doc_backup_id', d.id, 'why', 'no storage source to copy: ' || left(coalesce(d.error, 'no bucket or path'), 160));
    elsif d.requeued_at is not null and d.requeued_at > now() - interval '7 days' then
      n_refused := n_refused + 1;
      v_refused := v_refused || jsonb_build_object('doc_backup_id', d.id, 'why', 're-queued within the week already');
    else
      update public.doc_backups set status = 'pending', attempts = 0, verified_at = null, requeued_at = now(),
             error = left('it_engineer safe fix re-queued it after: ' || coalesce(error, '?'), 500)
       where id = d.id and status = 'error';
      n_req := n_req + 1;
    end if;
  end loop;
  return jsonb_build_object('outcome', case when n_req > 0 then 'fixed' when n_refused > 0 then 'refused_by_guardrail' else 'nothing_to_do' end,
                            'requeued', n_req, 'refused', v_refused);
end $fn$;

create or replace function public.fn_it_safe_fix_marketing_step_retry(p_issue_key text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_step text; v_subject text; v_rest text := substring(p_issue_key from '^marketing:step_quarantined:(.+)$');
begin
  if v_rest is null then return jsonb_build_object('outcome', 'refused_by_guardrail', 'why', 'not a quarantined-step finding'); end if;
  v_step := split_part(v_rest, ':', 1); v_subject := substr(v_rest, length(v_step) + 2);
  if exists (select 1 from public.marketing_step_release where step = v_step and subject = v_subject) then
    return jsonb_build_object('outcome', 'refused_by_guardrail', 'step', v_step,
      'why', 'released once already and quarantined again: the step''s failure is marketing''s to fix (see the finding''s last reasons)');
  end if;
  insert into public.marketing_step_release (step, subject, why)
  values (v_step, v_subject, 'released once by the IT engineer''s safe-fix playbook (ruling 1574) after 3 days of failures');
  if public.fn_marketing_subject_blocked(v_step, v_subject) like 'quarantined%' then
    return jsonb_build_object('outcome', 'failed', 'why', 'still quarantined after the release', 'step', v_step);
  end if;
  return jsonb_build_object('outcome', 'fixed', 'step', v_step, 'subject', v_subject,
                            'note', 'the step runs again on its next tick; a second quarantine stays marketing''s');
end $fn$;

-- ── 1. THE FAMILIES ───────────────────────────────────────────────────────────────────────────────────────────
insert into public.it_safe_fix_family (family, issue_like, routine, guardrail, max_runs_per_occurrence, max_per_tick, approval_ruling, active, owner_file) values
  ('close_cleared_handoffs', null, 'fn_it_safe_fix_close_cleared_handoffs',
   'closes only an it.finding handoff whose occurrence is over and that waited a day for its learning; writes only the learning the record supports', 1, 1, 1574, true,
   'scripts/sql/the_it_engineer_runs_the_safe_fix_playbooks_itself.sql'),
  ('delivery_outcome', 'duty:delivery:request:%', 'fn_it_safe_fix_delivery_outcome',
   'labels the delivery loop outcome of a request (row removed, final notification status, or unknown past 72 hours); never re-sends a message', 1, 50, 1574, true,
   'scripts/sql/the_it_engineer_runs_the_safe_fix_playbooks_itself.sql'),
  ('model_consumer', 'duty:model\_spend:unlisted:%', 'fn_it_safe_fix_model_consumer',
   'adds a registry row only for a caller whose function_owner names a live seat; an unattributable caller stays a finding', 1, 20, 1574, true,
   'scripts/sql/the_it_engineer_runs_the_safe_fix_playbooks_itself.sql'),
  ('workflow_park', 'duty:workflow\_audit:%', 'fn_it_safe_fix_workflow_park',
   'closes a workflow finding as parked only while founder ruling 1564 (GitHub Actions off) stands; touches no workflow file', 1, 100, 1574, true,
   'scripts/sql/the_it_engineer_runs_the_safe_fix_playbooks_itself.sql'),
  ('credential_rotation', 'duty:credential\_rotation\_age:overdue:%', 'fn_it_safe_fix_credential_rotation',
   'triggers only the existing internal-credential rotation, on the scheduled duty''s own predicate past the grace; at most 5 a tick; never a provider or founder credential', 1, 5, 1574, true,
   'scripts/sql/the_it_engineer_runs_the_safe_fix_playbooks_itself.sql'),
  ('backup_requeue', 'watch:queue\_stalled:doc\_backups\_failed', 'fn_it_safe_fix_backup_requeue',
   're-queues only an errored backup that has a storage source, at most once a week; an abandoned one with no source is refused', 1, 1, 1574, true,
   'scripts/sql/the_it_engineer_runs_the_safe_fix_playbooks_itself.sql'),
  ('marketing_step_retry', 'marketing:step\_quarantined:%', 'fn_it_safe_fix_marketing_step_retry',
   'releases a quarantined marketing step once (one row in marketing_step_release); a second quarantine stays marketing''s; publishes nothing', 1, 10, 1574, true,
   'scripts/sql/the_it_engineer_runs_the_safe_fix_playbooks_itself.sql'),
  ('expire_parked_questions', null, 'fn_it_safe_fix_expire_parked_questions',
   'closes a parked model question only on its record (applied, expired, superseded, gone); never a question a customer, supplier or visitor is waiting on', 1, 1, 1574, true,
   'scripts/sql/the_it_engineer_runs_the_safe_fix_playbooks_itself.sql')
on conflict (family) do update set issue_like = excluded.issue_like, routine = excluded.routine, guardrail = excluded.guardrail,
  max_runs_per_occurrence = excluded.max_runs_per_occurrence, max_per_tick = excluded.max_per_tick, approval_ruling = excluded.approval_ruling,
  owner_file = excluded.owner_file;

-- the CEO's one approval of a NEW family (an improvement with reasons, never the founder)
create or replace function public.fn_ceo_approves_safe_fix_family(p_family text, p_reasons text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_problem text := public.fn_ceo_reasons_problem(p_reasons); f public.it_safe_fix_family;
begin
  if v_problem is not null then raise exception 'the CEO approves a playbook family with its reasons: %', v_problem; end if;
  select * into f from public.it_safe_fix_family where family = p_family for update;
  if f.family is null then raise exception 'no safe-fix family %', p_family; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = f.routine) then
    raise exception 'family % names routine %, which does not exist', p_family, f.routine;
  end if;
  update public.it_safe_fix_family set ceo_approved_at = now(), ceo_approval_reasons = p_reasons, active = true, parked_at = null, parked_reason = null
   where family = p_family;
  return jsonb_build_object('ok', true, 'family', p_family, 'approved_by', 'ceo');
end $fn$;

-- ── 4. THE DISPATCHER ─────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_safe_fix_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare fam public.it_safe_fix_family; f record; v jsonb; v_outcome text; v_err text; n int; v_out jsonb := '{}'::jsonb; v_fam jsonb;
  v_until timestamptz := clock_timestamp() + interval '40 seconds';
begin
  for fam in select * from public.it_safe_fix_family where active order by family loop
    v_fam := jsonb_build_object('fixed', 0, 'nothing_to_do', 0, 'refused_by_guardrail', 0, 'failed', 0);
    n := 0;
    for f in select null::text issue_key, null::timestamptz started_at where fam.issue_like is null
             union all
             select x.issue_key, x.started_at from public.it_engineer_finding x
              where fam.issue_like is not null and x.closed_at is null and x.issue_key like fam.issue_like
                and x.issue_key not ilike '%demo%' and not coalesce((x.evidence->>'demo')::boolean, false)
                and (select count(*) from public.it_safe_fix_run r where r.family = fam.family and r.issue_key = x.issue_key
                      and r.occurrence_started_at is not distinct from x.started_at) < fam.max_runs_per_occurrence
             order by 2 nulls first, 1 loop
      exit when n >= fam.max_per_tick or clock_timestamp() > v_until;
      n := n + 1; v := null; v_err := null;
      begin
        if fam.issue_like is null then execute format('select public.%I()', fam.routine) into v;
        else execute format('select public.%I($1)', fam.routine) into v using f.issue_key; end if;
        v_outcome := coalesce(v->>'outcome', 'failed');
        if v_outcome not in ('fixed', 'nothing_to_do', 'refused_by_guardrail', 'failed') then v_outcome := 'failed'; end if;
      exception when others then
        v_outcome := 'failed'; v_err := left(sqlerrm, 500);
      end;
      insert into public.it_safe_fix_run (family, issue_key, occurrence_started_at, outcome, result, error)
      values (fam.family, f.issue_key, f.started_at, v_outcome, coalesce(v, '{}'::jsonb), v_err);
      v_fam := jsonb_set(v_fam, array[v_outcome], to_jsonb((v_fam->>v_outcome)::int + 1));
    end loop;
    -- TWO FAILED REMEDIES PARK THE FAMILY: it stops, says why, and goes on the session's daily list
    if (select count(*) from public.it_safe_fix_run r where r.family = fam.family and r.outcome = 'failed' and r.ran_at > now() - interval '1 day') >= 2 then
      update public.it_safe_fix_family set active = false, parked_at = now(),
             parked_reason = 'two failed runs in a day: ' || coalesce((select string_agg(coalesce(r.error, r.result->>'why', '?'), ' | ')
                                                                       from (select * from public.it_safe_fix_run r where r.family = fam.family and r.outcome = 'failed'
                                                                              order by r.id desc limit 2) r), '?')
       where family = fam.family;
      v_fam := v_fam || jsonb_build_object('parked', true);
    end if;
    v_out := v_out || jsonb_build_object(fam.family, v_fam);
  end loop;
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), clock_timestamp(), jsonb_build_object('job', 'playbook', 'families', v_out),
          'the IT engineer''s safe-fix playbooks ran (ruling 1574)');
  return jsonb_build_object('families', v_out);
end $fn$;

revoke execute on function public.fn_it_safe_fix_close_cleared_handoffs() from public, anon, authenticated;
revoke execute on function public.fn_it_safe_fix_expire_parked_questions() from public, anon, authenticated;
revoke execute on function public.fn_it_safe_fix_delivery_outcome(text) from public, anon, authenticated;
revoke execute on function public.fn_it_safe_fix_model_consumer(text) from public, anon, authenticated;
revoke execute on function public.fn_it_safe_fix_workflow_park(text) from public, anon, authenticated;
revoke execute on function public.fn_it_safe_fix_credential_rotation(text) from public, anon, authenticated;
revoke execute on function public.fn_it_safe_fix_backup_requeue(text) from public, anon, authenticated;
revoke execute on function public.fn_it_safe_fix_marketing_step_retry(text) from public, anon, authenticated;
revoke execute on function public.fn_ceo_approves_safe_fix_family(text, text) from public, anon, authenticated;
revoke execute on function public.fn_it_safe_fix_tick() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('it_engineer.safe_fix', 'it_engineer', interval '1 hour', 'fn_it_safe_fix_tick',
   'The IT engineer fixes what it can fix itself: each approved safe-fix family runs on its matching open findings within its bounds, records every run, and a family that fails twice in a day parks for the session. No deploy, code, schema, secret or business data. Ruling 1574.',
   'scripts/sql/the_it_engineer_runs_the_safe_fix_playbooks_itself.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- ── VERDICT (read-only) ─────────────────────────────────────────────────────────────────────────────────────────
select case when problems is null then 'PROBE OK' else 'PROBE FAILED: ' || problems end as verdict from (
  select string_agg(p, '; ') problems from (
    select 'a routine is open or unpinned: ' || p.oid::regprocedure::text p from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and (p.proname like 'fn\_it\_safe\_fix\_%' or p.proname in ('fn_ceo_approves_safe_fix_family', 'fn_marketing_subject_blocked'))
       and (not p.prosecdef or not coalesce(p.proconfig @> array['search_path=public, pg_temp'], false)
            or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
    union all select 'a family names a routine that does not exist: ' || f.family from public.it_safe_fix_family f
     where not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = f.routine)
    union all select 'a table is readable by a client: ' || t from unnest(array['it_safe_fix_family', 'it_safe_fix_run', 'marketing_step_release']) t
     where has_table_privilege('anon', 'public.' || t, 'select') or has_table_privilege('authenticated', 'public.' || t, 'select')
    union all select 'the duty is not registered' where not exists (select 1 from public.seat_duty where duty = 'it_engineer.safe_fix' and enabled)
  ) z) y;
