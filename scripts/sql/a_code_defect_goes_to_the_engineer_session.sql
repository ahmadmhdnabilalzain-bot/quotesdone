-- A CODE DEFECT GOES TO THE ENGINEER SESSION: THE IT ENGINEER WRITES IT, AN HOURLY CLAUDE CODE SESSION CLAIMS IT, FIXES IT BY
-- THE FULL ROUTE AND WRITES THE LESSON BACK. Seat: it_engineer. Founder rulings 1705 (15 Nov 2026: "The IT engineer should solve
-- it, not report it ... His auto-learning loop should help him") and 1574; the seat itself never deploys or edits code (its
-- charter, the_it_engineer_repairs_within_its_guardrails.sql), so a defect it cannot repair operationally is written HERE and
-- the engineer session (docs/runbooks/the-code-defect-session.md, a scheduled task with a fresh session per fire) takes it.
--
-- MEASURED BEFORE WRITING (15 Nov 2026, SP/audit/SUPPORT_IT.md, SELECT): the escalation to a session that existed,
-- public.it_session_fix_day, held 12 items a day and read_by_session_at was NULL on each of the last 5 days: nothing read it.
-- No table held a defect with its evidence, its affected people, its claim, its PR or its verification.
--
-- WHAT THIS FILE DOES:
--   1. public.it_code_defect: ONE ROW PER DEFECT CLASS (class_key unique), its occurrences counted, the affected people as refs
--      (lead:<id>, customer:<uuid>, fault:<support_fault_report id>; never a name or an address), the evidence masked
--      (fn_it_mask_text), the suspected files, a repro with ZZ DEMO fixtures, the precedent (the earlier fix of the same class and
--      the playbook row), and the life cycle queued -> claimed -> fixing -> in_review -> merged -> deployed -> verified, or
--      wont_fix with a reason (money, a secret, a founder decision, a gate change, not reproducible). A claim holds a 2-hour lease;
--      a session that dies leaves the row claimed and the next run takes it back.
--   2. fn_it_code_defect_open(...): written by the seat (the classifier in fn_it_registration_watch and the families), never by
--      hand: a new class is queued; an open class counts the occurrence; a VERIFIED class that returns is REOPENED with its old
--      PR and lesson in history, so the session starts from the known fix. Each affected person is told once, through support,
--      that the platform is fixing it (no date promised). Emits it.defect_opened.
--   3. fn_it_code_defect_claim(session, id): the next queued (or lease-expired) defect by severity then age, for update skip
--      locked; with an id (a fire with a payload) that defect first.
--   4. fn_it_code_defect_progress(id, session, status, pr, note): the session's steps; wont_fix only with an allowed reason.
--   5. fn_it_code_defect_verified(id, session, observed, lesson_ref): only after deployed and only against what a SELECT showed;
--      closes the finding, tells every affected person "fixed, try again" through support, completes their hand-overs, emits
--      it.defect_fixed.
--   6. fn_it_code_defect_queue(): what the hourly session reads first: counts by status and the next claimable id (0 rows ->
--      the session says "no defects" and stops).
--
-- Prevented by: scripts/checks/the_it_engineer_repairs_a_registration_and_learns.test.mjs (local replay: opened once, counted,
-- claimed once under a lease, reclaimed after the lease, verified only after deployed, reopened when it returns).
--   node scripts/apply_sql.mjs scripts/sql/a_code_defect_goes_to_the_engineer_session.sql --apply --ddl --seat it_engineer

create table if not exists public.it_code_defect (
  id bigint generated always as identity primary key,
  opened_at timestamptz not null default now(),
  class_key text not null unique check (class_key ~ '^[a-z0-9_.:-]{3,160}$'),
  severity text not null default 'P2' check (severity in ('P1', 'P2', 'P3')),   -- P1 registration or payment blocked
  issue_key text,
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  occurrences integer not null default 1 check (occurrences >= 1),
  affected_cases text[] not null default '{}'::text[] check (cardinality(affected_cases) <= 200),
  fn text,
  http integer,
  action text,
  time_window tstzrange,
  evidence jsonb not null default '[]'::jsonb,
  suspected_files text[] not null default '{}'::text[],
  repro jsonb not null default '{}'::jsonb,
  precedent jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued', 'claimed', 'fixing', 'in_review', 'merged', 'deployed', 'verified', 'wont_fix')),
  claimed_by_session text,
  claimed_at timestamptz,
  lease_until timestamptz,
  pr_number integer,
  deployed_at timestamptz,
  verified_at timestamptz,
  verified_observed text,
  lesson_ref text,
  wont_fix_reason text,
  reopened_count integer not null default 0,
  history jsonb not null default '[]'::jsonb,
  fixture boolean not null default false,
  updated_at timestamptz not null default now(),
  check (status <> 'verified' or (verified_at is not null and deployed_at is not null and coalesce(btrim(verified_observed), '') <> '')),
  check (status <> 'wont_fix' or coalesce(btrim(wont_fix_reason), '') <> '')
);
create index if not exists it_code_defect_queue_idx on public.it_code_defect (severity, opened_at) where status in ('queued', 'claimed');
alter table public.it_code_defect enable row level security;
drop policy if exists it_code_defect_service_role_only on public.it_code_defect;
create policy it_code_defect_service_role_only on public.it_code_defect as permissive for all to public using (false) with check (false);
revoke all on public.it_code_defect from anon, authenticated;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('it_code_defect', true, 'decision', 'a code defect the IT engineer could not repair operationally, its evidence, the engineer session''s claim, PR, deploy and verification (ruling 1705)', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason;

-- ── 2. OPEN (or count, or reopen) ───────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_code_defect_open(p_class_key text, p_severity text, p_issue_key text, p_fn text, p_http integer,
  p_action text, p_evidence jsonb, p_affected text[] default '{}'::text[], p_suspected_files text[] default '{}'::text[], p_repro jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_class text := lower(left(regexp_replace(coalesce(p_class_key, ''), '[^A-Za-z0-9_.:-]+', '_', 'g'), 160));
  v_sev text := case when p_severity in ('P1', 'P2', 'P3') then p_severity else 'P2' end;
  v_aff text[] := array(select distinct a from unnest(coalesce(p_affected, '{}'::text[])) a where a ~ '^(lead|customer|fault|case):[A-Za-z0-9-]{1,64}$');
  v_ev jsonb := jsonb_build_object('at', now(), 'issue_key', p_issue_key,
                                   'detail', public.fn_it_mask_text(left(coalesce(p_evidence::text, '{}'), 1500)));
  v_files text[] := coalesce(p_suspected_files, '{}'::text[]);
  d public.it_code_defect; v_new boolean := false; v_reopened boolean := false; v_pb public.it_playbook; a text; v_new_aff text[];
begin
  if length(v_class) < 3 then raise exception 'fn_it_code_defect_open: a defect needs its class'; end if;
  if p_fn ~ '^[a-z0-9_]+$' and cardinality(v_files) = 0 then v_files := array['supabase/functions/' || p_fn || '/index.ts']; end if;
  select * into d from public.it_code_defect where class_key = v_class for update;
  if d.id is null then
    select * into v_pb from public.it_playbook b where coalesce(p_issue_key, v_class) like b.issue_prefix || '%' order by length(b.issue_prefix) desc limit 1;
    insert into public.it_code_defect (class_key, severity, issue_key, fn, http, action, time_window, evidence, affected_cases, suspected_files, repro, precedent, fixture)
    values (v_class, v_sev, p_issue_key, p_fn, p_http, p_action, tstzrange(now() - interval '15 minutes', now(), '[]'), jsonb_build_array(v_ev), v_aff,
            v_files, coalesce(p_repro, '{}'::jsonb),
            jsonb_build_object('playbook', case when v_pb.failure_class is null then null else jsonb_build_object('class', v_pb.failure_class,
              'prefix', v_pb.issue_prefix, 'remedy', v_pb.remedy, 'remedy_routine', v_pb.remedy_routine, 'regression_check', v_pb.regression_check) end), v_fx)
    returning * into d;
    v_new := true; v_new_aff := v_aff;
  else
    v_new_aff := array(select x from unnest(v_aff) x where not x = any (d.affected_cases));
    if d.status in ('verified', 'wont_fix') then
      -- A FIXED CLASS THAT RETURNS IS REOPENED, carrying what fixed it last time (C3.5: "two months later, the same issue")
      v_reopened := d.status = 'verified' or d.wont_fix_reason !~* '^(money|secret|founder)';
      if not v_reopened then
        update public.it_code_defect set occurrences = occurrences + 1, last_seen = now(), updated_at = now() where id = d.id;
        return d.id;
      end if;
      update public.it_code_defect
         set status = 'queued', severity = least(severity, v_sev), reopened_count = reopened_count + 1, occurrences = occurrences + 1,
             last_seen = now(), updated_at = now(), issue_key = coalesce(p_issue_key, issue_key),
             history = history || jsonb_build_array(jsonb_build_object('closed_as', d.status, 'pr_number', d.pr_number, 'deployed_at', d.deployed_at,
               'verified_at', d.verified_at, 'verified_observed', d.verified_observed, 'lesson_ref', d.lesson_ref, 'wont_fix_reason', d.wont_fix_reason,
               'reopened_at', now())),
             precedent = precedent || jsonb_build_object('previous_fix', jsonb_build_object('pr_number', d.pr_number, 'lesson_ref', d.lesson_ref)),
             claimed_by_session = null, claimed_at = null, lease_until = null, pr_number = null, deployed_at = null, verified_at = null,
             verified_observed = null, wont_fix_reason = null,
             affected_cases = (select coalesce(array_agg(distinct x), '{}'::text[]) from unnest(v_aff) x),
             evidence = jsonb_build_array(v_ev), time_window = tstzrange(now() - interval '15 minutes', now(), '[]')
       where id = d.id returning * into d;
      v_new_aff := v_aff;
    else
      update public.it_code_defect
         set occurrences = occurrences + 1, last_seen = now(), updated_at = now(), severity = least(severity, v_sev),
             affected_cases = (select coalesce(array_agg(distinct x), '{}'::text[]) from (select unnest(affected_cases) x union select unnest(v_aff)) z),
             evidence = case when jsonb_array_length(evidence) >= 20 then evidence else evidence || jsonb_build_array(v_ev) end,
             time_window = tstzrange(least(lower(time_window), now() - interval '15 minutes'), now(), '[]')
       where id = d.id returning * into d;
    end if;
  end if;

  -- EVERY NEWLY AFFECTED PERSON IS TOLD ONCE, THROUGH SUPPORT, THAT THE PLATFORM IS FIXING IT (no date promised)
  foreach a in array coalesce(v_new_aff, '{}'::text[]) loop
    perform public.fn_it_defect_tell(d.id, a, 'opened');
  end loop;
  if v_new or v_reopened then
    perform public.fn_emit('it.defect_opened', 'it_code_defect', d.id::text, 'it_engineer',
      jsonb_build_object('class_key', d.class_key, 'severity', d.severity, 'issue_key', d.issue_key, 'reopened', v_reopened,
                         'affected', cardinality(d.affected_cases), 'previous_fix', d.precedent->'previous_fix'));
  end if;
  return d.id;
end $fn$;

-- one person, one defect, one stage: an owed message in support's voice (fn_it_tells_the_person)
create or replace function public.fn_it_defect_tell(p_defect_id bigint, p_ref text, p_stage text)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_email text; v_role text := 'customer'; v_lang text := 'en'; v_ar boolean; v_lead bigint;
begin
  if p_stage not in ('opened', 'fixed') then raise exception 'fn_it_defect_tell: stage opened or fixed'; end if;
  if p_ref like 'lead:%' then
    select lower(l.claimed_by), l.id into v_email, v_lead from public.leads l where l.id = substr(p_ref, 6)::bigint and not coalesce(l.banned, false);
    v_role := 'supplier';
  elsif p_ref like 'customer:%' then
    select lower(c.email) into v_email from public.customers c where c.id::text = substr(p_ref, 10) and not coalesce(c.banned, false);
  elsif p_ref like 'fault:%' then
    select r.email, r.lang, case when r.audience = 'supplier' then 'supplier' else 'customer' end, r.lead_id into v_email, v_lang, v_role, v_lead
      from public.support_fault_report r where r.id = substr(p_ref, 7)::bigint;
  end if;
  if v_email is null then return false; end if;
  v_ar := v_lang = 'ar' and v_role <> 'supplier';
  if p_stage = 'opened' then
    return public.fn_it_tells_the_person('it_defect.opened', p_defect_id || ':' || p_ref, v_role, v_email, v_lang,
      case when v_ar then 'QuotesDone: نعمل على إصلاح مشكلة واجهتكم' else 'QuotesDone: we are fixing a problem you ran into' end,
      case when v_ar then 'واجهتم مشكلة على QuotesDone، وفريقنا التقني يعمل على إصلاحها الآن. بياناتكم محفوظة، وسنراسلكم فور إصلاحها لتكملوا من حيث توقفتم.' || chr(10) || chr(10) || 'فريق QuotesDone'
           else 'You ran into a problem on QuotesDone, and our technical team is fixing it now. Nothing you entered is lost, and we will write again as soon as it is fixed so you can carry on from where you stopped.' || chr(10) || chr(10) || 'The QuotesDone team' end,
      'Write a short e-mail telling them they ran into a problem on QuotesDone, our technical team is fixing it now, nothing they entered is lost, and we will write again as soon as it is fixed so they can carry on. Name no date.',
      'STATUS: being fixed' || chr(10) || 'WHAT THEY CAN DO NOW: nothing; we will write when it is fixed');
  end if;
  return public.fn_it_tells_the_person('it_defect.fixed', p_defect_id || ':' || p_ref, v_role, v_email, v_lang,
    case when v_ar then 'QuotesDone: تم إصلاح المشكلة' else 'QuotesDone: the problem is fixed, please try again' end,
    case when v_ar then 'تم إصلاح المشكلة التي واجهتموها على QuotesDone. يرجى المحاولة مرة أخرى من حيث توقفتم.' || chr(10) || chr(10) || 'فريق QuotesDone'
         else 'The problem you ran into on QuotesDone is fixed. Please try again from where you stopped.' || chr(10) || chr(10) || 'The QuotesDone team' end,
    'Write a short e-mail telling them the problem they ran into on QuotesDone is fixed and asking them to try again from where they stopped. Thank them for their patience.',
    'STATUS: fixed' || chr(10) || 'WHAT THEY CAN DO NOW: try again from where they stopped');
end $fn$;

-- ── 3. CLAIM ────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_code_defect_claim(p_session text, p_id bigint default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d public.it_code_defect;
begin
  if coalesce(btrim(p_session), '') = '' then raise exception 'fn_it_code_defect_claim: the session names itself'; end if;
  select * into d from public.it_code_defect x
   where (p_id is null or x.id = p_id)
     and (x.status = 'queued' or (x.status in ('claimed', 'fixing', 'in_review') and x.lease_until < now()))
   order by case when p_id is not null then 0 else 1 end, x.severity, x.opened_at
   limit 1 for update skip locked;
  if d.id is null then return jsonb_build_object('claimed', false, 'reason', case when p_id is null then 'no defects' else 'defect ' || p_id || ' is not claimable' end); end if;
  update public.it_code_defect
     set status = 'claimed', claimed_by_session = left(p_session, 200), claimed_at = now(), lease_until = now() + interval '2 hours', updated_at = now(),
         history = history || jsonb_build_array(jsonb_build_object('claimed_by', left(p_session, 200), 'at', now(), 'took_back_from', d.claimed_by_session))
   where id = d.id returning * into d;
  return jsonb_build_object('claimed', true, 'defect', to_jsonb(d));
end $fn$;

-- ── 4. PROGRESS ─────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_code_defect_progress(p_id bigint, p_session text, p_status text, p_pr_number integer default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d public.it_code_defect; v_order text[] := array['claimed', 'fixing', 'in_review', 'merged', 'deployed'];
begin
  select * into d from public.it_code_defect where id = p_id for update;
  if d.id is null then return jsonb_build_object('ok', false, 'reason', 'no such defect'); end if;
  if d.claimed_by_session is distinct from p_session then return jsonb_build_object('ok', false, 'reason', 'claimed by another session'); end if;
  if p_status = 'wont_fix' then
    if coalesce(p_note, '') !~* '^(money|secret|founder decision|gate change|not reproducible|duplicate of [0-9]+)' then
      return jsonb_build_object('ok', false, 'reason', 'wont_fix needs one of: money, secret, founder decision, gate change, not reproducible, duplicate of <id>');
    end if;
    update public.it_code_defect set status = 'wont_fix', wont_fix_reason = left(p_note, 1000), lease_until = null, updated_at = now() where id = p_id;
    return jsonb_build_object('ok', true, 'status', 'wont_fix');
  end if;
  if not p_status = any (v_order) or array_position(v_order, p_status) < array_position(v_order, d.status) then
    return jsonb_build_object('ok', false, 'reason', 'a defect moves forward through ' || array_to_string(v_order, ' -> ') || ', not from ' || d.status || ' to ' || coalesce(p_status, '?'));
  end if;
  if p_status in ('merged', 'deployed') and coalesce(p_pr_number, d.pr_number) is null then
    return jsonb_build_object('ok', false, 'reason', 'merged and deployed name the PR');
  end if;
  update public.it_code_defect
     set status = p_status, pr_number = coalesce(p_pr_number, pr_number), lease_until = now() + interval '2 hours', updated_at = now(),
         deployed_at = case when p_status = 'deployed' then now() else deployed_at end,
         history = history || jsonb_build_array(jsonb_build_object('status', p_status, 'at', now(), 'note', left(coalesce(p_note, ''), 500)))
   where id = p_id;
  return jsonb_build_object('ok', true, 'status', p_status);
end $fn$;

-- ── 5. VERIFIED ─────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_code_defect_verified(p_id bigint, p_session text, p_observed text, p_lesson_ref text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare d public.it_code_defect; a text; n_told int := 0;
begin
  select * into d from public.it_code_defect where id = p_id for update;
  if d.id is null then return jsonb_build_object('ok', false, 'reason', 'no such defect'); end if;
  if d.claimed_by_session is distinct from p_session then return jsonb_build_object('ok', false, 'reason', 'claimed by another session'); end if;
  if d.status <> 'deployed' or d.deployed_at is null then return jsonb_build_object('ok', false, 'reason', 'verified only after deployed (now ' || d.status || ')'); end if;
  if coalesce(btrim(p_observed), '') = '' or length(p_observed) < 20 then
    return jsonb_build_object('ok', false, 'reason', 'verified names what the production SELECT showed (at least 20 characters)');
  end if;
  update public.it_code_defect
     set status = 'verified', verified_at = now(), verified_observed = left(p_observed, 1000), lesson_ref = left(p_lesson_ref, 300),
         lease_until = null, updated_at = now(),
         history = history || jsonb_build_array(jsonb_build_object('status', 'verified', 'at', now(), 'observed', left(p_observed, 500), 'lesson_ref', p_lesson_ref))
   where id = p_id returning * into d;
  foreach a in array d.affected_cases loop
    if public.fn_it_defect_tell(d.id, a, 'fixed') then n_told := n_told + 1; end if;
  end loop;
  -- the people who told support about it: their hand-overs complete with the observation
  for a in select substr(x, 7) from unnest(d.affected_cases) x where x like 'fault:%' loop
    perform public.fn_support_fault_fixed((select r.issue_key from public.support_fault_report r where r.id = a::bigint), null,
      'code defect ' || d.class_key || ' fixed by PR #' || coalesce(d.pr_number::text, '?') || ': ' || left(p_observed, 300));
  end loop;
  if d.issue_key is not null then
    perform public.fn_it_engineer_finding_close(d.issue_key, 'code defect ' || d.class_key || ' fixed by PR #' || coalesce(d.pr_number::text, '?')
      || ' and verified: ' || left(p_observed, 400));
  end if;
  perform public.fn_emit('it.defect_fixed', 'it_code_defect', d.id::text, 'it_engineer',
    jsonb_build_object('class_key', d.class_key, 'issue_key', d.issue_key, 'pr_number', d.pr_number, 'lesson_ref', d.lesson_ref,
                       'affected', cardinality(d.affected_cases), 'told', n_told, 'observed', left(p_observed, 300)));
  return jsonb_build_object('ok', true, 'status', 'verified', 'told', n_told);
end $fn$;

-- ── 6. THE QUEUE THE SESSION READS FIRST ────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_code_defect_queue()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'claimable', (select count(*) from public.it_code_defect x where not x.fixture
                   and (x.status = 'queued' or (x.status in ('claimed', 'fixing', 'in_review') and x.lease_until < now()))),
    'next_id', (select x.id from public.it_code_defect x where not x.fixture
                 and (x.status = 'queued' or (x.status in ('claimed', 'fixing', 'in_review') and x.lease_until < now()))
                 order by x.severity, x.opened_at limit 1),
    'by_status', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from public.it_code_defect where not fixture group by 1) z))
$fn$;

revoke execute on function public.fn_it_code_defect_open(text, text, text, text, integer, text, jsonb, text[], text[], jsonb) from public, anon, authenticated;
revoke execute on function public.fn_it_defect_tell(bigint, text, text) from public, anon, authenticated;
revoke execute on function public.fn_it_code_defect_claim(text, bigint) from public, anon, authenticated;
revoke execute on function public.fn_it_code_defect_progress(bigint, text, text, integer, text) from public, anon, authenticated;
revoke execute on function public.fn_it_code_defect_verified(bigint, text, text, text) from public, anon, authenticated;
revoke execute on function public.fn_it_code_defect_queue() from public, anon, authenticated;

-- ── VERDICT (read-only) ─────────────────────────────────────────────────────────────────────────────────────────────
select case when problems is null then 'PROBE OK' else 'PROBE FAILED: ' || problems end as verdict from (
  select string_agg(p, '; ') problems from (
    select 'a routine is open or unpinned: ' || p.oid::regprocedure::text p from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and (p.proname like 'fn\_it\_code\_defect\_%' or p.proname = 'fn_it_defect_tell')
       and (not p.prosecdef or not coalesce(p.proconfig @> array['search_path=public, pg_temp'], false)
            or has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
    union all select 'the defect table is readable by a client' where has_table_privilege('anon', 'public.it_code_defect', 'select')
                                                               or has_table_privilege('authenticated', 'public.it_code_defect', 'select')
    union all select 'the queue does not read' where public.fn_it_code_defect_queue() is null
  ) z) y;
