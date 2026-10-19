-- THE IT ENGINEER CLOSES THE LOOPS A SENIOR IT ENGINEER CLOSES (it_engineer, founder ledger 1003 stage 2, 19 Oct 2026).
--
-- Assigned: it_engineer. Stage 1 of ledger 1003 measured the IT seat against a 20-year senior bar
-- (knowledge/standards/it_engineer.json in the seat-audit branch). Five contributions are built here as seat_duties
-- that ACT, in code, no model. IT-C14 (failure cluster) is owned elsewhere and is not touched.
--
-- ══ MEASURED, 19 Oct 2026 ~04:50 UTC, htdblwldjkcgjvmqkbeh ═══════════════════════════════════════════════════════
--   IT-C02  it_engineer.latency_slo settles 10 failing findings (3 p95, 7 error-budget; the oldest open since 29 Sep).
--           fn_it_duty_settle closes a key the hour it stops breaching and fn_it_engineer_finding_upsert reopens it,
--           but no finding carries a deadline, and nothing acts when one is open past any date.
--   IT-C06  it_engineer.model_spend settles 41 failing findings, cost_watch 1. Same shape: detected, chased daily by
--           fn_it_engineer_finding_chase, never given a deadline, never escalated when it outlives one.
--   IT-C13  it_duty_schedule (15 perimeter checks) has no last-success column. Runs land only in agent_runs
--           ('duty:<name>' via fn_it_duty_ran). model_catalogue has NO recorded run in 35 days.
--   IT-C15  fn_it_dependency_ingest settles npm/OSV advisories weekly; nothing audits .github/workflows. On main,
--           27 `uses:` lines are not pinned to a commit SHA (actions/checkout@v7 and others).
--   IT-C16  no load-test duty, no recorded ceiling. 11 inquiries and 11 quotes exist, ALL demo (fn_*_is_demo).
--
-- ══ WHAT THIS ADDS ═══════════════════════════════════════════════════════════════════════════════════════════════
--   IT-C02  it_engineer.latency_closure       daily   fn_it_engineer_finding_closure('latency_slo', 7)
--   IT-C06  it_engineer.model_spend_closure   daily   fn_it_engineer_finding_closure('model_spend', 3) + ('cost_watch', 7)
--           Each open finding of the duty gets an it_finding_closure row: owner seat (the finding's owner_seat), a
--           deadline, the reading at open and the latest reading (the hourly duty re-measures; the row copies it).
--           Closed when the duty closes the finding (p95 back under 2.5 s / spend back under its line) with the
--           reading at close; a finding that reopens reopens its row (reopen_count + 1, a fresh deadline).
--           Past its deadline: ONE overdue 'it.finding' handoff to the owner seat (the CEO when IT owns it).
--           Spend: the idle ceiling stays USD 1-2/day (model_spend's idle_floor). Nothing here caps OpenRouter,
--           proposes a hold, or changes a model route -- the handoff says so in its payload.
--   IT-C13  it_duty_schedule.last_ok_at / last_result: stamped by fn_it_duty_ran, backfilled from agent_runs.
--           it_engineer.perimeter_freshness  hourly  a schedule row with no success inside 2 x every + 1 h is a
--           finding ('duty:perimeter_freshness:<duty>') owned by that row's seat; it closes on the next success.
--   IT-C15  fn_it_workflow_audit_ingest(report) -- scripts/it/workflow_audit.mjs, weekly in it-weekly-readings.yml:
--           runner = vars.RUNNER || ubicloud-standard-2, every action pinned to a 40-hex SHA, top-level
--           permissions declared and never write-all, no secret echoed into a log. One finding per file per rule.
--           it_engineer.advisory_triage  daily  the dependency and workflow readings are fresh (<= 8 days), and every
--           open Supabase security advisor at WARN/ERROR outside the baseline is a finding until it clears.
--           report_dependency_audit.mjs now audits only the edge functions actually DEPLOYED and attaches EPSS;
--           fn_it_dependency_ingest makes an advisory with EPSS >= 0.1 a security finding whatever its label
--           Ruling 1254 (nothing technical goes to the founder): every advisory is marked no_founder_email, and a
--           high/critical/EPSS one is owned by the CEO seat, so fn_ceo_it_escalation_decide keeps it in the company.
--   IT-C16  it_engineer.load_test  every 30 days  fn_it_engineer_load_test(): the inquiry (fn_match_capability),
--           quote (fn_quote_quality_flags + fn_quote_spec_mismatches) and comparison (fn_quote_structured_score)
--           database paths run at 10/40/160/640 operations over ZZ DEMO rows ONLY, each step inside a
--           sub-transaction that is rolled back. Every step is a row in it_load_test_run; the first step whose
--           per-operation p95 passes slow_query_mean_ms (500) is the breakpoint and a finding.
--           ponytail: one connection, serial -- the DB-path ceiling, not concurrency; a k6 run against a Supabase
--           branch is the upgrade when January's arrival rate is known.
--
-- NOT CHANGED: fn_it_engineer_latency_slo, fn_it_engineer_model_spend, fn_it_cost_watch_tick, fn_it_duty_settle,
-- fn_it_engineer_finding_chase. Nothing here notifies the founder.
-- Prevented by: scripts/checks/the_it_engineer_senior_duties_are_registered_and_act.test.mjs, and the aborted-
-- transaction probe the_it_engineer_closes_the_loops_a_senior_it_engineer_closes_probe.sql (0 founder notifications).
--
--   node scripts/apply_sql.mjs scripts/sql/the_it_engineer_closes_the_loops_a_senior_it_engineer_closes.sql --apply --ddl

-- ── IT-C02 / IT-C06 ───────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.it_finding_closure (
  issue_key        text primary key,
  duty             text not null,
  owner_seat       text not null,
  opened_at        timestamptz not null,
  deadline         timestamptz not null,
  reading_at_open  jsonb not null default '{}'::jsonb,
  last_reading     jsonb not null default '{}'::jsonb,
  last_measured_at timestamptz,
  closed_at        timestamptz,
  reading_at_close jsonb,
  reopen_count     int not null default 0,
  overdue_handoff_id bigint
);
alter table public.it_finding_closure enable row level security;
drop policy if exists it_finding_closure_service_role_only on public.it_finding_closure;
create policy it_finding_closure_service_role_only on public.it_finding_closure as permissive for all to public using (false) with check (false);
revoke all on public.it_finding_closure from anon, authenticated;

create or replace function public.fn_it_engineer_finding_closure(p_duty text, p_days int)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare f public.it_engineer_finding; c public.it_finding_closure; v_owner text; v_to text; v_id bigint;
  n_new int := 0; n_reopened int := 0; n_closed int := 0; n_overdue int := 0;
begin
  if coalesce(btrim(p_duty), '') = '' or coalesce(p_days, 0) < 1 then
    raise exception 'fn_it_engineer_finding_closure(duty, days): a duty and a deadline of at least one day are required';
  end if;

  -- every open finding of the duty: an owner, a deadline, and the latest reading the hourly duty took
  for f in select * from public.it_engineer_finding
            where closed_at is null and issue_key like 'duty:' || p_duty || ':%'
              and not coalesce((evidence->>'demo')::boolean, false) loop
    v_owner := coalesce(nullif(f.evidence->>'owner_seat', ''), 'it_engineer');
    select * into c from public.it_finding_closure where issue_key = f.issue_key;
    if not found then
      insert into public.it_finding_closure (issue_key, duty, owner_seat, opened_at, deadline, reading_at_open, last_reading, last_measured_at)
      values (f.issue_key, p_duty, v_owner, f.started_at, f.started_at + make_interval(days => p_days), f.evidence, f.evidence, f.last_seen_at);
      n_new := n_new + 1;
    elsif c.closed_at is not null then
      -- a regression: the finding came back, so its closure opens again with a fresh deadline
      update public.it_finding_closure set opened_at = f.started_at, deadline = greatest(now(), f.started_at) + make_interval(days => p_days),
             reading_at_open = f.evidence, last_reading = f.evidence, last_measured_at = f.last_seen_at, owner_seat = v_owner,
             closed_at = null, reading_at_close = null, reopen_count = reopen_count + 1, overdue_handoff_id = null
       where issue_key = f.issue_key;
      n_reopened := n_reopened + 1;
    else
      update public.it_finding_closure set last_reading = f.evidence, last_measured_at = f.last_seen_at, owner_seat = v_owner
       where issue_key = f.issue_key;
    end if;
  end loop;

  -- the duty closed it (the reading is back under its line): the closure closes with what it read
  for c in select k.* from public.it_finding_closure k join public.it_engineer_finding fi using (issue_key)
            where k.duty = p_duty and k.closed_at is null and fi.closed_at is not null loop
    update public.it_finding_closure k set closed_at = fi.closed_at,
           reading_at_close = jsonb_build_object('close_note', fi.close_note, 'last_breach_reading', k.last_reading,
                                                 'days_open', round(extract(epoch from fi.closed_at - k.opened_at) / 86400, 1),
                                                 'met_deadline', fi.closed_at <= k.deadline)
      from public.it_engineer_finding fi where fi.issue_key = k.issue_key and k.issue_key = c.issue_key;
    n_closed := n_closed + 1;
  end loop;

  -- past its deadline and still open: one overdue handoff to the owner (the CEO when IT itself owns it)
  for c in select * from public.it_finding_closure
            where duty = p_duty and closed_at is null and deadline < now() and overdue_handoff_id is null
            order by deadline limit 20 loop
    select * into f from public.it_engineer_finding where issue_key = c.issue_key;
    v_to := case when c.owner_seat = 'it_engineer' then 'ceo' else c.owner_seat end;
    v_id := public.fn_seat_handoff('it_engineer', v_to, 'it.finding', 'it_engineer_finding',
      c.issue_key || '@' || floor(extract(epoch from c.opened_at))::bigint || '@overdue',
      jsonb_build_object('issue_key', c.issue_key, 'occurrence_started_at', f.started_at, 'duty', p_duty,
        'subject', f.evidence->>'subject', 'overdue', true, 'deadline', c.deadline, 'owner_seat', c.owner_seat,
        'title', 'Past its ' || to_char(c.deadline at time zone 'Asia/Dubai', 'DD Mon') || ' deadline: ' || f.title,
        'where_it_is', f.where_it_is, 'reading_at_open', c.reading_at_open, 'latest_reading', c.last_reading,
        'done_when', case p_duty when 'latency_slo' then 'p95 is back under 2500 ms over 24 h (the hourly duty closes it)'
                                 else 'the hourly reading is back under its line (the duty closes it)' end,
        'never', case when p_duty in ('model_spend', 'cost_watch')
                      then 'no OpenRouter cap, no hold, no model-route change: fix the caller; the idle internal ceiling is USD 1-2 a day' end));
    update public.it_finding_closure set overdue_handoff_id = coalesce(v_id, -1) where issue_key = c.issue_key;
    n_overdue := n_overdue + 1;
  end loop;

  return jsonb_build_object('duty', p_duty, 'deadline_days', p_days, 'new', n_new, 'reopened', n_reopened, 'closed', n_closed,
    'overdue_handed', n_overdue,
    'open', (select count(*) from public.it_finding_closure where duty = p_duty and closed_at is null),
    'open_past_deadline', (select count(*) from public.it_finding_closure where duty = p_duty and closed_at is null and deadline < now()),
    'closed_30d', (select count(*) from public.it_finding_closure where duty = p_duty and closed_at > now() - interval '30 days'));
end $fn$;
revoke execute on function public.fn_it_engineer_finding_closure(text, int) from public, anon, authenticated;
grant execute on function public.fn_it_engineer_finding_closure(text, int) to service_role;

create or replace function public.fn_it_engineer_latency_closure()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp' as $fn$
  select public.fn_it_engineer_finding_closure('latency_slo', 7)
$fn$;
revoke execute on function public.fn_it_engineer_latency_closure() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_latency_closure() to service_role;

create or replace function public.fn_it_engineer_model_spend_closure()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('model_spend', public.fn_it_engineer_finding_closure('model_spend', 3),
                            'cost_watch', public.fn_it_engineer_finding_closure('cost_watch', 7))
$fn$;
revoke execute on function public.fn_it_engineer_model_spend_closure() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_model_spend_closure() to service_role;

-- ── IT-C13 ────────────────────────────────────────────────────────────────────────────────────────────────────────
alter table public.it_duty_schedule add column if not exists last_ok_at timestamptz;
alter table public.it_duty_schedule add column if not exists last_result jsonb;

create or replace function public.fn_it_duty_ran(p_duty text, p_result jsonb)
 returns void language sql security definer set search_path to 'public', 'pg_temp' as $function$
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('it_engineer', 'ok', now(), now(), jsonb_build_object('job', 'duty:' || p_duty, 'result', p_result), null);
  -- the perimeter check's own last success, on its schedule row (IT-C13)
  update public.it_duty_schedule set last_ok_at = now(), last_result = p_result where duty = p_duty;
$function$;

update public.it_duty_schedule s set last_ok_at = r.at
  from (select substring(counts->>'job' from 6) duty, max(started_at) at from public.agent_runs
         where agent = 'it_engineer' and status = 'ok' and counts->>'job' like 'duty:%' group by 1) r
 where r.duty = s.duty and s.last_ok_at is null;

create or replace function public.fn_it_engineer_perimeter_freshness()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare s record; v_items jsonb := '[]'::jsonb;
begin
  for s in select * from public.it_duty_schedule
            where coalesce(last_ok_at, 'epoch') < now() - (every * 2 + interval '1 hour') order by duty loop
    v_items := v_items || jsonb_build_object('item', s.duty, 'subject', s.duty, 'owner_seat', s.owner_seat, 'blast', 'internal',
      'title', 'Perimeter check ' || s.duty || ' has not succeeded since '
               || coalesce(to_char(s.last_ok_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI'), 'any recorded run')
               || ' (it runs every ' || s.every || ')',
      'evidence', jsonb_build_object('every', s.every, 'last_ok_at', s.last_ok_at, 'note', s.note));
  end loop;
  return jsonb_build_object('checks', (select count(*) from public.it_duty_schedule), 'stale', jsonb_array_length(v_items),
                            'settled', public.fn_it_duty_settle('perimeter_freshness', v_items));
end $fn$;
revoke execute on function public.fn_it_engineer_perimeter_freshness() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_perimeter_freshness() to service_role;

-- ── IT-C15 ────────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_it_workflow_audit_ingest(p_r jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare e jsonb; v_items jsonb := '[]'::jsonb; v_res jsonb;
begin
  if jsonb_typeof(p_r->'violations') is distinct from 'array' or coalesce((p_r->>'files')::int, 0) < 1 then
    raise exception 'fn_it_workflow_audit_ingest takes {files:n, violations:[...]} from scripts/it/workflow_audit.mjs';
  end if;
  for e in select v from jsonb_array_elements(p_r->'violations') v loop
    v_items := v_items || jsonb_build_object('item', (e->>'file') || ':' || (e->>'rule'), 'subject', e->>'file',
      'owner_seat', 'it_engineer', 'blast', case when e->>'rule' in ('secret_in_log', 'write_all') then 'security' else 'internal' end,
      'title', (e->>'file') || ': ' || (e->>'message'), 'evidence', e);
  end loop;
  v_res := public.fn_it_duty_settle('workflow_audit', v_items) || jsonb_build_object('files', p_r->'files');
  perform public.fn_it_duty_ran('workflow_audit', v_res);
  return v_res;
end $fn$;
revoke execute on function public.fn_it_workflow_audit_ingest(jsonb) from public, anon, authenticated;
grant execute on function public.fn_it_workflow_audit_ingest(jsonb) to service_role;

-- The dependency ingest. Ruling 1254: no advisory is emailed to the founder; high/critical/EPSS ones go to the CEO seat.
-- Triage: an advisory whose CVE has EPSS >= 0.1 (likely exploited within 30
-- days) is a security finding whatever its label, and the report's deployed-only basis is kept on the run.
create or replace function public.fn_it_dependency_ingest(p_r jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $function$
declare e jsonb; v_items jsonb := '[]'::jsonb; v_res jsonb; v_hot boolean;
begin
  if jsonb_typeof(p_r->'advisories') is distinct from 'array' then
    raise exception 'fn_it_dependency_ingest takes {advisories:[...]} from scripts/it/report_dependency_audit.mjs';
  end if;
  for e in select a from jsonb_array_elements(p_r->'advisories') a loop
    v_hot := lower(e->>'severity') in ('high', 'critical') or coalesce((e->>'epss')::numeric, 0) >= 0.1;
    v_items := v_items || jsonb_build_object('item', (e->>'ecosystem') || ':' || (e->>'package') || ':' || coalesce(e->>'id', '?'),
      'owner_seat', case when v_hot or e->>'ecosystem' = 'app' then 'ceo' else coalesce(e->>'owner_seat', 'ceo') end,
      'subject', coalesce(e->>'function', e->>'package'),
      'title', upper(coalesce(e->>'severity', '?')) || ' advisory in ' || (e->>'package') || ': ' || left(coalesce(e->>'title', ''), 120)
               || coalesce(' (EPSS ' || round((e->>'epss')::numeric, 3) || ')', ''),
      'blast', case when v_hot then 'security' else 'internal' end,
      'affected', case when v_hot then 1 else 0 end,
      'evidence', e || jsonb_build_object('no_founder_email', true));   -- ruling 1254: never the founder, high/critical included
  end loop;
  v_res := public.fn_it_duty_settle('dependency', v_items)
           || jsonb_build_object('functions_not_deployed', p_r->'functions_not_deployed', 'deployed_list_read', p_r->'deployed_list_read');
  perform public.fn_it_duty_ran('dependency', v_res);
  return v_res;
end $function$;

create or replace function public.fn_it_engineer_advisory_triage()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_items jsonb := '[]'::jsonb; r record; v_at timestamptz;
begin
  -- the two weekly readings that need the repository are fresh, or their absence is the finding
  for r in select k duty from unnest(array['dependency', 'workflow_audit']) k loop
    select max(started_at) into v_at from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:' || r.duty;
    if coalesce(v_at, 'epoch') < now() - interval '8 days' then
      v_items := v_items || jsonb_build_object('item', 'stale:' || r.duty, 'subject', r.duty, 'owner_seat', 'it_engineer', 'blast', 'internal',
        'title', 'The weekly ' || r.duty || ' reading has not reported since ' || coalesce(to_char(v_at, 'DD Mon'), 'it was built')
                 || ' (it-weekly-readings.yml)', 'evidence', jsonb_build_object('last_run_at', v_at));
    end if;
  end loop;
  -- provider advisories: an open Supabase security advisor outside the accepted baseline is about what is deployed
  for r in select cache_key, name, level, title, metadata from public.security_advisor_baseline
            where cleared_at is null and not in_baseline and level in ('WARN', 'ERROR') and last_seen_at > now() - interval '2 days' loop
    v_items := v_items || jsonb_build_object('item', 'supabase:' || r.cache_key, 'subject', coalesce(r.metadata->>'name', r.name),
      'owner_seat', 'it_engineer', 'blast', case when r.level = 'ERROR' then 'security' else 'internal' end,
      'title', 'Supabase advisor ' || r.level || ' ' || r.name || ' on ' || coalesce(r.metadata->>'schema', '?') || '.' || coalesce(r.metadata->>'name', '?'),
      'evidence', jsonb_build_object('advisor', r.name, 'level', r.level, 'metadata', r.metadata));
  end loop;
  return jsonb_build_object('settled', public.fn_it_duty_settle('advisory_triage', v_items),
    'dependency_open', (select count(*) from public.it_engineer_finding where closed_at is null and issue_key like 'duty:dependency:%'),
    'workflow_open', (select count(*) from public.it_engineer_finding where closed_at is null and issue_key like 'duty:workflow_audit:%'));
end $fn$;
revoke execute on function public.fn_it_engineer_advisory_triage() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_advisory_triage() to service_role;

-- ── IT-C16 ────────────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.it_load_test_run (
  id            bigserial primary key,
  run_at        timestamptz not null,
  journey       text not null,
  step_ops      int not null,
  total_ms      numeric not null,
  ops_per_sec   numeric,
  p95_ms        numeric,
  max_ms        numeric,
  within_budget boolean not null,
  breakpoint    boolean not null default false,
  detail        jsonb not null default '{}'::jsonb
);
alter table public.it_load_test_run enable row level security;
drop policy if exists it_load_test_run_service_role_only on public.it_load_test_run;
create policy it_load_test_run_service_role_only on public.it_load_test_run as permissive for all to public using (false) with check (false);
revoke all on public.it_load_test_run from anon, authenticated;

create or replace function public.fn_it_engineer_load_test()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_run timestamptz := now(); v_budget numeric := coalesce((select value::numeric from public.it_threshold where key = 'slow_query_mean_ms'), 500);
  v_inq uuid[]; v_quo uuid[]; j text; n int; i int; t0 timestamptz; t1 timestamptz; v_ms numeric[]; v_total numeric; v_p95 numeric;
  v_broke boolean; v_items jsonb := '[]'::jsonb; v_out jsonb := '[]'::jsonb; v_x int; v_deadline timestamptz;
  v_inquiry public.inquiries; v_quote public.quotes; v_err text;
begin
  -- ZZ DEMO ONLY: no real customer's or supplier's row is ever read by the test
  select array_agg(id order by id) into v_inq from public.inquiries where public.fn_inquiry_is_demo(id) and coalesce(cardinality(trades), 0) > 0;
  select array_agg(id order by id) into v_quo from public.quotes where public.fn_quote_is_demo(id);
  if v_inq is null or v_quo is null then
    v_items := v_items || jsonb_build_object('item', 'no_demo_fixture', 'subject', 'load_test', 'owner_seat', 'it_engineer', 'config', true,
      'title', 'The load test has no ZZ DEMO inquiry with trades or no ZZ DEMO quote to run on', 'evidence', jsonb_build_object('inquiries', cardinality(v_inq), 'quotes', cardinality(v_quo)));
    return jsonb_build_object('ran', false, 'settled', public.fn_it_duty_settle('load_test', v_items));
  end if;

  foreach j in array array['inquiry_match', 'quote_check', 'comparison'] loop
    v_broke := false;
    v_deadline := clock_timestamp() + interval '5 seconds';   -- each journey gets 5 s, so the duty ends inside ~16 s
    foreach n in array array[10, 40, 160, 640] loop
      exit when v_broke or clock_timestamp() > v_deadline;
      v_ms := '{}'; v_err := null;
      t0 := clock_timestamp();
      begin
        for i in 1..n loop
          t1 := clock_timestamp();
          if j = 'inquiry_match' then
            select * into v_inquiry from public.inquiries where id = v_inq[1 + (i % cardinality(v_inq))];
            select count(*) into v_x from public.fn_match_capability(v_inquiry.trades, 'executes', '{}', '{}', null, null, v_inquiry.emirate, 12);
          elsif j = 'quote_check' then
            select * into v_quote from public.quotes where id = v_quo[1 + (i % cardinality(v_quo))];
            perform public.fn_quote_quality_flags(v_quote), public.fn_quote_spec_mismatches(v_quote.id::text);
          else
            perform public.fn_quote_structured_score(v_quo[1 + (i % cardinality(v_quo))]::text);
          end if;
          v_ms := v_ms || round(extract(epoch from clock_timestamp() - t1) * 1000, 2);
          exit when clock_timestamp() > v_deadline;
        end loop;
        -- whatever the paths wrote is rolled back with this sub-transaction; the timings live in variables
        raise exception using errcode = 'QDLT0', message = 'load test step rolled back';
      exception when sqlstate 'QDLT0' then null;
        when others then v_err := sqlerrm;   -- a path that fails under load is the breakpoint, not a crashed duty
      end;
      v_total := round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
      select percentile_cont(0.95) within group (order by m) into v_p95 from unnest(v_ms) m;
      v_broke := v_err is not null or coalesce(v_p95 > v_budget, true);
      insert into public.it_load_test_run (run_at, journey, step_ops, total_ms, ops_per_sec, p95_ms, max_ms, within_budget, breakpoint, detail)
      values (v_run, j, cardinality(v_ms), v_total, round(cardinality(v_ms) / greatest(v_total / 1000, 0.001), 1), round(v_p95, 2),
              (select max(m) from unnest(v_ms) m), not v_broke, v_broke,
              jsonb_build_object('budget_ms', v_budget, 'requested_ops', n, 'demo_inquiries', cardinality(v_inq), 'demo_quotes', cardinality(v_quo), 'error', v_err));
      v_out := v_out || jsonb_build_object('journey', j, 'ops', cardinality(v_ms), 'total_ms', v_total, 'p95_ms', round(v_p95, 2), 'breakpoint', v_broke);
      if v_broke then
        v_items := v_items || jsonb_build_object('item', j, 'subject', j, 'owner_seat', 'it_engineer', 'blast', 'internal',
          'title', 'Load test: the ' || j || ' database path broke its ' || v_budget || ' ms per-operation budget at ' || n
                   || ' operations (p95 ' || round(v_p95) || ' ms) on ZZ DEMO data',
          'evidence', jsonb_build_object('run_at', v_run, 'step_ops', n, 'p95_ms', round(v_p95, 2), 'budget_ms', v_budget));
      end if;
    end loop;
  end loop;
  return jsonb_build_object('ran', true, 'run_at', v_run, 'budget_ms', v_budget, 'steps', v_out,
    'ceiling_ops_per_sec', (select jsonb_object_agg(journey, m) from (select journey, max(ops_per_sec) m from public.it_load_test_run
                              where run_at = v_run and within_budget group by 1) x),
    'settled', public.fn_it_duty_settle('load_test', v_items));
end $fn$;
revoke execute on function public.fn_it_engineer_load_test() from public, anon, authenticated;
grant execute on function public.fn_it_engineer_load_test() to service_role;

-- ── the duties ────────────────────────────────────────────────────────────────────────────────────────────────────
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('it_engineer.latency_closure', 'it_engineer', interval '1 day', 'fn_it_engineer_latency_closure',
   'IT-C02: every open latency finding has an owner seat and a 7-day deadline, carries its latest hourly reading, closes when p95 is back under 2.5 s, reopens on regression, and is handed to its owner once when it outlives the deadline.',
   'scripts/sql/the_it_engineer_closes_the_loops_a_senior_it_engineer_closes.sql'),
  ('it_engineer.model_spend_closure', 'it_engineer', interval '1 day', 'fn_it_engineer_model_spend_closure',
   'IT-C06: every open model-spend (3-day) and provider-cost (7-day) finding has an owner and a deadline, closes when the reading is back under its line, reopens on regression, and is handed to its owner once past the deadline; never caps OpenRouter or proposes a hold.',
   'scripts/sql/the_it_engineer_closes_the_loops_a_senior_it_engineer_closes.sql'),
  ('it_engineer.perimeter_freshness', 'it_engineer', interval '1 hour', 'fn_it_engineer_perimeter_freshness',
   'IT-C13: every perimeter check in it_duty_schedule records its last success; one with no success inside twice its interval plus an hour is a finding for its seat until it succeeds again.',
   'scripts/sql/the_it_engineer_closes_the_loops_a_senior_it_engineer_closes.sql'),
  ('it_engineer.advisory_triage', 'it_engineer', interval '1 day', 'fn_it_engineer_advisory_triage',
   'IT-C15: the weekly dependency advisories (deployed code only, with EPSS) and the GitHub workflow audit (runner, SHA-pinned actions, permissions, no secret in a log) are fresh, and every open Supabase security advisor outside the baseline is a finding until it clears.',
   'scripts/sql/the_it_engineer_closes_the_loops_a_senior_it_engineer_closes.sql'),
  ('it_engineer.load_test', 'it_engineer', interval '30 days', 'fn_it_engineer_load_test',
   'IT-C16: the inquiry, quote and comparison database paths are stepped to their breakpoint on ZZ DEMO rows in rolled-back sub-transactions; every step is recorded in it_load_test_run and a broken budget is a finding.',
   'scripts/sql/the_it_engineer_closes_the_loops_a_senior_it_engineer_closes.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
