-- every_promise_a_case_records_is_kept_or_its_seat_is_told_before_it_is_due.sql
-- Assigned: customer_support (the case and its promises are support's record). Founder rulings of 11 Nov 2026:
--   1635: "Every conversation is a case with a case number. After each exchange the agent records a summary of the case."
--   1631: every agent reads the history before it replies, so it never repeats itself (or forgets what it said it would do).
--   1634: keep everything in history (a closed promise keeps its row; nothing here deletes).
--
-- MEASURED 11 Nov 2026 (production, read-only, ~12:00 UTC): support_case 28 rows, 0 with a summary, 0 summary versions
-- (#1938's summary step was applied ~11:20 UTC and runs on WhatsApp only until this branch's channels deploy). A promise
-- existed only as a line of the summary text ("WE PROMISED: - send the quotes as they arrive"); no table held one and no
-- duty read one, so a promise due tomorrow could pass with nobody told.
--
-- WHAT THIS ADDS
--   1. public.support_case_promise: one row per promise a case summary records - the case, what, when it is due, the seat
--      that owns it, its status. The due time is read by CODE from our own words (supabase/functions/_shared/
--      case_promises.ts); words that name no time are given support_promise_undated_hours (default 48) and due_basis
--      'assumed'. One row per (case, wording): the summary step keeps an earlier promise's wording, so a promise restated
--      in a later summary is the same row, and its first due time stands.
--   2. fn_support_case_promises_record, called by the one summary writer fn_support_case_summary_write, redefined here with
--      that one line added; the rest of its body is the live one, read back 11 Nov 2026 (md5 of prosrc c75a933f...).
--      Only promises in the summary being written are recorded, and the summary step has already dropped any promise our
--      reply or the earlier summary never stated (support_case_memory.ts checkSummary). The owner is the seat that wrote
--      the summary, i.e. the seat that answered on that channel (customer_support or sales_engineer).
--   3. The duty customer_support.promise_watch: hourly, on its own staggered minute of the five (fn_seat_duty_isolate,
--      the_seat_duty_jobs_are_spread_over_the_five_minutes.sql):
--      a. a 'quotes' promise to a customer is KEPT when a new_quote notification reached them (status 'sent') on one of
--         their requests after the promise was made - the one event code can see. The kind is the summary model's reading
--         (one of two words), never a word list run here (founder_instruction 890);
--      b. every open promise due within support_promise_warn_hours (default 24), or already overdue, is FLAGGED to its
--         owning seat once: a support.promise_due handoff that waits until the promise is kept or the seat marks it;
--      c. the count is in the CEO's end-of-day brief (ceo_brief_line, one line per Dubai day, its text refreshed each
--         hour; fn_founder_brief_ceo_lines prints it).
--   4. fn_support_case_promise_mark: where code cannot see the event, the owning seat (or the CEO) marks the promise kept,
--      not kept or withdrawn, saying how; that closes its flag.
-- WHAT IT DOES NOT CHANGE: how a case opens or closes, fn_support_touch, the summary step's model or class, the Dropbox
-- seam (a_case_summary_is_a_text_file_in_the_persons_dropbox_folder.sql), any existing row.
-- prevented by: supabase/functions/_shared/case_promises.test.ts (due times, wording),
-- scripts/checks/every_case_keeps_a_summary.test.mjs (this file's shape) and this file's _probe.sql (run on a local
-- Postgres 16 stub built from the schema mirror, 11 Nov 2026; the PR rehearsal runs it on production, rolled back).
--
--   node scripts/apply_sql.mjs scripts/sql/every_promise_a_case_records_is_kept_or_its_seat_is_told_before_it_is_due.sql --apply --ddl

-- 1. the ledger
create table if not exists public.support_case_promise (
  id bigserial primary key,
  case_id bigint not null references public.support_case (case_id),
  case_ref text not null,
  promise_key text not null,
  what text not null check (length(what) between 1 and 400),
  due_text text,
  due_at timestamptz not null,
  due_basis text not null check (due_basis in ('stated', 'assumed')),
  kind text not null default 'other' check (kind in ('quotes', 'other')),
  -- the seats that answer a person today; a promise is flagged through a support.promise_due handoff registered for each
  owner_seat text not null check (owner_seat in ('customer_support', 'sales_engineer')),
  status text not null default 'open' check (status in ('open', 'kept', 'not_kept', 'withdrawn')),
  stated_in_version integer not null,
  is_demo boolean not null default false,
  flagged_at timestamptz,
  handoff_id bigint,
  closed_at timestamptz,
  closed_by text,
  closed_how text,
  created_at timestamptz not null default now(),
  unique (case_id, promise_key),
  constraint support_case_promise_closed_ck check ((status = 'open') = (closed_at is null)),
  constraint support_case_promise_closed_how_ck check (status = 'open' or length(btrim(coalesce(closed_how, ''))) > 0)
);
create index if not exists support_case_promise_open_due_idx on public.support_case_promise (due_at) where status = 'open';
alter table public.support_case_promise enable row level security;
drop policy if exists support_case_promise_service_role_only on public.support_case_promise;
create policy support_case_promise_service_role_only on public.support_case_promise
  as permissive for all to public using (false) with check (false);
revoke all on public.support_case_promise from anon, authenticated;

-- ruling 1634: exported every day, like the case summary history
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('support_case_promise', true, 'customer', 'Every promise a support case recorded (what, due, owner seat, kept or not): the record of what we told customers and suppliers we would do (founder rulings 1634, 1635).', 'customer_support')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- 2. the recorder (called by the summary writer only)
create or replace function public.fn_support_case_promises_record(p_case_id bigint, p_version integer, p_promised jsonb, p_owner_seat text)
returns integer language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  c public.support_case; p public.support_customer_profile; e jsonb; v_what text; v_due timestamptz; v_basis text;
  v_seat text := case when p_owner_seat in ('customer_support', 'sales_engineer') then p_owner_seat else 'customer_support' end;
  v_hours int := greatest(1, public.fn_seat_clock_policy('support_promise_undated_hours', 48)::int);
  v_demo boolean; n int := 0;
begin
  if p_promised is null or jsonb_typeof(p_promised) <> 'array' then return 0; end if;
  select * into c from public.support_case where case_id = p_case_id;
  if c.case_id is null then return 0; end if;
  select * into p from public.support_customer_profile where id = c.customer_profile_id;
  -- the demo marker of whoever the case is with (ruling 1199: no seat duty works a demo row as if it were real)
  v_demo := public.fn_party_is_demo(c.party_kind, c.party_id)
         or coalesce(public.fn_is_demo_email(p.email), false)
         or (p.customer_id is not null and coalesce(public.fn_customer_is_demo(p.customer_id), false))
         or (p.lead_id is not null and coalesce(public.fn_supplier_is_demo(p.lead_id), false));
  for e in select x from jsonb_array_elements(p_promised) as t(x) loop
    v_what := left(btrim(coalesce(e ->> 'what', '')), 400);
    continue when v_what = '';
    v_due := null;
    begin v_due := nullif(e ->> 'due_at', '')::timestamptz; exception when others then v_due := null; end;
    v_basis := case when v_due is null then 'assumed' else 'stated' end;
    insert into public.support_case_promise (case_id, case_ref, promise_key, what, due_text, due_at, due_basis, kind, owner_seat,
                                             stated_in_version, is_demo)
    values (c.case_id, c.case_ref, md5(lower(regexp_replace(v_what, '\s+', ' ', 'g'))), v_what,
            nullif(left(btrim(coalesce(e ->> 'by', '')), 60), ''), coalesce(v_due, now() + make_interval(hours => v_hours)), v_basis,
            case when e ->> 'kind' = 'quotes' then 'quotes' else 'other' end, v_seat, p_version, v_demo)
    on conflict (case_id, promise_key) do nothing;
    if found then n := n + 1; end if;
  end loop;
  return n;
end $fn$;
revoke execute on function public.fn_support_case_promises_record(bigint, integer, jsonb, text) from public, anon, authenticated;

-- the one summary writer: the live body (every_support_case_keeps_a_summary_and_the_reply_reads_it.sql), plus the ledger line
create or replace function public.fn_support_case_summary_write(
  p_case_ref text, p_expected_version integer, p_summary jsonb, p_summary_text text, p_title text,
  p_written_by text, p_model text default null, p_linked_refs jsonb default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.support_case; v_next int;
begin
  select * into c from public.support_case where case_ref = p_case_ref for update;
  if c.case_id is null then return jsonb_build_object('ok', false, 'reason', 'no such case'); end if;
  if c.summary_version <> coalesce(p_expected_version, -1) then
    return jsonb_build_object('ok', false, 'reason', 'stale', 'version', c.summary_version);
  end if;
  if p_summary is null or jsonb_typeof(p_summary) <> 'object' or not (p_summary ? 'asked' and p_summary ? 'said_or_did')
     or jsonb_typeof(p_summary -> 'promised') <> 'array' or jsonb_typeof(p_summary -> 'open') <> 'array'
     or length(coalesce(p_summary_text, '')) not between 1 and 4000 then
    return jsonb_build_object('ok', false, 'reason', 'bad shape');
  end if;
  v_next := c.summary_version + 1;
  update public.support_case
     set summary = p_summary, summary_text = p_summary_text, title = coalesce(nullif(left(btrim(p_title), 160), ''), title),
         summary_version = v_next, summary_updated_at = now(),
         linked_refs = case when p_linked_refs is null then linked_refs else linked_refs || p_linked_refs end
   where case_id = c.case_id;
  insert into public.support_case_summary_version (case_id, version, summary, summary_text, title, written_by, model)
  values (c.case_id, v_next, p_summary, p_summary_text, left(btrim(p_title), 160), coalesce(p_written_by, 'customer_support'), p_model);
  -- every promise this summary states, in the ledger (11 Nov 2026, the promise ledger)
  perform public.fn_support_case_promises_record(c.case_id, v_next, p_summary -> 'promised', p_written_by);
  perform public.fn_support_case_summary_backup_enqueue(c.case_id);
  return jsonb_build_object('ok', true, 'case_ref', c.case_ref, 'version', v_next);
end $fn$;
revoke execute on function public.fn_support_case_summary_write(text, integer, jsonb, text, text, text, text, jsonb) from public, anon, authenticated;

-- 3b. the flag: a handoff to the owning seat that waits until the promise is kept or marked
create or replace function public.fn_support_promise_due_waits(p_id bigint)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('waiting', 'the promise kept (customer_support.promise_watch sees the event) or marked kept, not kept or '
                            || 'withdrawn by the owning seat (fn_support_case_promise_mark)', 'promise', a.detail -> 'promise', 'due_at', a.detail -> 'due_at')
    from public.agent_actions a where a.id = p_id
$fn$;
revoke execute on function public.fn_support_promise_due_waits(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
select 'support.promise_due', 'customer_support', s,
       'A promise a support case recorded (what we told a customer or supplier we would do, and by when) is due within support_promise_warn_hours, or overdue, and is not kept. Keep it, or mark it kept, not kept or withdrawn with fn_support_case_promise_mark; it closes when it is kept or marked.',
       'fn_support_promise_due_waits', null, false,
       'scripts/sql/every_promise_a_case_records_is_kept_or_its_seat_is_told_before_it_is_due.sql'
  from unnest(array['customer_support', 'sales_engineer']) as s
on conflict (type, from_seat, to_seat) do update set meaning = excluded.meaning, handler = excluded.handler,
  reply_within = excluded.reply_within, originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

-- 4. the seat marks what code cannot see
create or replace function public.fn_support_case_promise_mark(p_id bigint, p_status text, p_by text, p_how text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare pr public.support_case_promise;
begin
  if p_status not in ('kept', 'not_kept', 'withdrawn') then return jsonb_build_object('ok', false, 'reason', 'status is kept, not_kept or withdrawn'); end if;
  if length(btrim(coalesce(p_how, ''))) < 3 then return jsonb_build_object('ok', false, 'reason', 'say how (the evidence)'); end if;
  select * into pr from public.support_case_promise where id = p_id for update;
  if pr.id is null then return jsonb_build_object('ok', false, 'reason', 'no such promise'); end if;
  if pr.status <> 'open' then return jsonb_build_object('ok', false, 'reason', 'already ' || pr.status); end if;
  if p_by is distinct from pr.owner_seat and p_by is distinct from 'ceo' then
    return jsonb_build_object('ok', false, 'reason', 'only the owning seat (' || pr.owner_seat || ') or the ceo marks this promise');
  end if;
  update public.support_case_promise set status = p_status, closed_at = now(), closed_by = p_by, closed_how = left(btrim(p_how), 500)
   where id = pr.id;
  if pr.handoff_id is not null then
    perform public.fn_seat_handoff_complete(pr.handoff_id, jsonb_build_object('status', p_status, 'by', p_by, 'how', left(btrim(p_how), 500)));
  end if;
  return jsonb_build_object('ok', true, 'id', pr.id, 'status', p_status);
end $fn$;
revoke execute on function public.fn_support_case_promise_mark(bigint, text, text, text) from public, anon, authenticated;

-- 3. the duty
create or replace function public.fn_support_case_promise_watch()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_warn int := greatest(1, public.fn_seat_clock_policy('support_promise_warn_hours', 24)::int);
  r record; v_h bigint; n_kept int := 0; n_flag int := 0;
  v_due int := 0; v_over int := 0; v_seats text; v_day text := to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD');
begin
  -- a. a quotes promise to a customer is kept when quotes reached them: a new_quote notice SENT on one of their requests
  --    after the promise was made (the demo marker on both sides: a fixture is only ever kept by a fixture)
  for r in
    select pr.id, pr.handoff_id, q.id as notice_id
      from public.support_case_promise pr
      join public.support_case c on c.case_id = pr.case_id
      join public.support_customer_profile pf on pf.id = c.customer_profile_id
      join lateral (select n.id from public.notifications n
                     where n.type = 'new_quote' and n.status = 'sent' and coalesce(n.sent_at, n.created_at) > pr.created_at
                       and n.inquiry_id in (select i.id from public.inquiries i where i.customer_id = pf.customer_id)
                     order by n.id limit 1) q on true
     where pr.status = 'open' and pr.kind = 'quotes' and pr.is_demo = v_fx and pf.customer_id is not null
  loop
    update public.support_case_promise
       set status = 'kept', closed_at = now(), closed_by = 'customer_support',
           closed_how = 'quotes delivered: notification ' || r.notice_id || ' (new_quote, sent)'
     where id = r.id and status = 'open';
    if r.handoff_id is not null then
      perform public.fn_seat_handoff_complete(r.handoff_id, jsonb_build_object('status', 'kept', 'how', 'new_quote notification ' || r.notice_id));
    end if;
    n_kept := n_kept + 1;
  end loop;

  -- b. due within the warning window (or overdue) and not kept: the owning seat is told, once
  for r in
    select pr.* from public.support_case_promise pr
     where pr.status = 'open' and pr.flagged_at is null and pr.is_demo = v_fx
       and pr.due_at <= now() + make_interval(hours => v_warn)
     order by pr.due_at, pr.id limit 200
  loop
    v_h := public.fn_seat_handoff('customer_support', r.owner_seat, 'support.promise_due', 'support_case_promise', r.id::text,
      jsonb_build_object('case_ref', r.case_ref, 'promise', r.what, 'due_at', r.due_at, 'due_basis', r.due_basis, 'due_text', r.due_text,
                         'kind', r.kind, 'overdue', r.due_at < now(),
                         'ask', 'Keep this promise before it is due, or mark it kept, not kept or withdrawn (fn_support_case_promise_mark), saying how.'));
    update public.support_case_promise set flagged_at = now(), handoff_id = v_h where id = r.id;
    n_flag := n_flag + 1;
  end loop;

  -- c. the CEO's brief: one line per Dubai day, its count refreshed each hour (real promises only)
  if not v_fx then
    select count(*), count(*) filter (where pr.due_at < now()),
           string_agg(distinct pr.owner_seat, ', ')
      into v_due, v_over, v_seats
      from public.support_case_promise pr
     where pr.status = 'open' and not pr.is_demo and pr.due_at <= now() + make_interval(hours => v_warn);
    if v_due > 0 or exists (select 1 from public.ceo_brief_line where subject_key = 'support.promises_due:' || v_day) then
      insert into public.ceo_brief_line (subject_key, line, source)
      values ('support.promises_due:' || v_day,
              format('Promises to customers and suppliers due within %s hours and not yet kept: %s, of them %s overdue%s. Each is flagged to the seat that made it.',
                     v_warn, v_due, v_over, case when v_seats is null then '' else ' (' || v_seats || ')' end),
              'customer_support.promise_watch')
      on conflict (subject_key) do update set line = excluded.line;
    end if;
  end if;
  return jsonb_build_object('ok', true, 'fixture', v_fx, 'kept', n_kept, 'flagged', n_flag, 'open_due', v_due, 'overdue', v_over);
end $fn$;
revoke execute on function public.fn_support_case_promise_watch() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file)
values ('customer_support.promise_watch', 'customer_support', interval '1 hour', 'fn_support_case_promise_watch',
        'Every promise a support case recorded: a quotes promise closes when the quotes reach the customer; one due within support_promise_warn_hours (24) and not kept is flagged to the seat that made it; the count goes into the CEO''s brief.',
        'scripts/sql/every_promise_a_case_records_is_kept_or_its_seat_is_told_before_it_is_due.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
-- its own job, on the minute of the five holding the fewest seat-duty jobs (the generator of #1936)
do $iso$ begin perform public.fn_seat_duty_isolate('customer_support.promise_watch'); end $iso$;

-- VERDICT (this file defines routines, so it never raises to report)
select case
  when to_regclass('public.support_case_promise') is null then 'PROBE FAILED: no support_case_promise'
  when not exists (select 1 from public.table_export_registry where table_name = 'support_case_promise' and exported)
    then 'PROBE FAILED: support_case_promise is not exported'
  when has_function_privilege('anon', 'public.fn_support_case_promise_mark(bigint, text, text, text)', 'execute')
    or has_function_privilege('anon', 'public.fn_support_case_promises_record(bigint, integer, jsonb, text)', 'execute')
    or has_function_privilege('anon', 'public.fn_support_case_promise_watch()', 'execute')
    then 'PROBE FAILED: anon can execute a promise routine'
  when position('fn_support_case_promises_record' in (select prosrc from pg_proc
        where oid = 'public.fn_support_case_summary_write(text, integer, jsonb, text, text, text, text, jsonb)'::regprocedure)) = 0
    then 'PROBE FAILED: the summary writer does not record promises'
  when (select count(*) from public.seat_handoff_kind where type = 'support.promise_due') <> 2
    then 'PROBE FAILED: support.promise_due is not registered for both answering seats'
  when not exists (select 1 from cron.job where jobname = 'seat_duty:customer_support.promise_watch'
                    and schedule ~ '^[0-4]-59/5 \* \* \* \*$')
    then 'PROBE FAILED: the promise watch has no staggered job'
  else 'PROBE OK' end as verdict;
