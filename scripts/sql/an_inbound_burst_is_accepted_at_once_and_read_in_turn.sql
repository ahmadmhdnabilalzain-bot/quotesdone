-- AN INBOUND BURST IS ACCEPTED AT ONCE AND READ IN TURN (it_engineer, 15 Nov 2026).
-- Assigned: it_engineer (shared platform: the inbound mail queue). The function it serves, resend_inbound, is customer_support's
-- (public.function_owner); its pipeline is unchanged, only WHEN it runs changes.
--
-- MEASURED (production, 15 Nov 2026 18:40-18:54 UTC; edge logs and a light SELECT):
--   * 18 receipts were forwarded to expenses@mail.quotesdone.com within about 3 minutes. resend_inbound read every message
--     INSIDE the webhook request: the Resend read, the attachment downloads, the PDF and vision reads, the booking. It answered
--     546 (WORKER_RESOURCE_LIMIT) on most deliveries and 504 after 150 s on others; the calls that succeeded took 30-142 s each.
--   * Only 5 messages reached public.inbound_messages (SELECT: 5 rows to expenses@ after 18:30) and 4 were booked to
--     expense_entries. Resend keeps retrying the rest, into the same overloaded path.
--   * The same function receives supplier quotations and customer and supplier replies, so a burst can lose business mail.
--
-- CHANGE
--   1. public.inbound_mail_queue: one row per e-mail, unique on the provider's id (Resend's email_id, 'm365:<id>' for the
--      Microsoft 365 reader, else 'svix:<svix-id>'), holding the verified delivery as it arrived. resend_inbound now verifies the
--      token and the Svix signature, records the row (fn_inbound_mail_accept; a redelivery is answered "duplicate"), answers
--      200 and only then starts reading (EdgeRuntime.waitUntil).
--   2. fn_inbound_mail_claim hands a reader the oldest due message, under one advisory lock so the count is exact:
--        * at most fn_inbound_mail_readers() (2) messages are being read at any moment, estate-wide: one heavy read per
--          worker is what a single delivery always survived; eighteen at once is what died;
--        * a message waits while an EARLIER message of the same thread_key (sender > mailbox; NULL for the finance
--          mailboxes, where order does not matter) is still queued or being read, so a supplier's quotation and his
--          correction a minute later are read in the order he sent them;
--        * a reader holds a 150 s lease it renews every 30 s (fn_inbound_mail_touch); a reader the edge killed stops renewing,
--          and its message is taken back at the next claim after the backoff, counted as an attempt.
--   3. fn_inbound_mail_finish: read -> done; failed -> queued again after 1, 5, 15, then 60 minutes; failed on the
--      max_attempts-th (5) try -> dead (fn_inbound_mail_dead_letter): an it.finding handoff to the seat that owns the mail
--      (accountant for the finance mailboxes, marketing for the founder's replies to its approvals, customer_support for
--      the rest, as resend_inbound decided at acceptance) with the reason and how to read it again (fn_inbound_mail_requeue).
--   4. fn_inbound_mail_kick asks resend_inbound?drain=1 (db.internal credential, whose scope gains resend_inbound) to start one
--      reader per due message a free slot can take. A reader reads ONE message per invocation (the edge limits CPU per
--      invocation, and a run that read message after message would add theirs up and be killed part-way through a later one),
--      then calls the kick itself to hand on; the webhook starts a reader too, and one that finds both slots taken leaves its
--      message for the next. pg_cron inbound_mail_drain runs the kick every minute as the net under that chain.
--      Done rows are deleted after 30 days (the inbound_messages row is the record); dead rows are kept.
-- NOTHING IS PROCESSED TWICE: the queue key stops a redelivery; a message is claimed by one reader at a time (skip locked under
-- the advisory lock); a message re-read after a crash meets the pipeline's own guards (inbound_messages.provider_email_id is
-- unique and answered "already on file", expense_entries.source_msg_id 'resend:<email_id>' is unchanged).
-- ORDER: APPLY THIS FILE FIRST (the new resend_inbound refuses a delivery with 503 while fn_inbound_mail_accept is missing, so
-- Resend keeps it), then deploy resend_inbound. The old resend_inbound ignores the queue, so the order is safe both ways.
-- Revoked from public, anon, authenticated; granted to service_role (resend_inbound). Lock footprint: a new table, one row
-- UPDATE on internal_credential, inserts into cron.job, cron_registry and writer_seat.
-- Prevented by: resend_inbound/an_inbound_burst_is_accepted_at_once_and_read_in_turn.test.ts (the webhook and the reader),
-- scripts/checks/an_inbound_burst_is_accepted_at_once_and_read_in_turn.test.mjs (this file's shape) and the rolled-back probe
-- an_inbound_burst_is_accepted_at_once_and_read_in_turn_probe.sql (these routines, on a database).
--   node scripts/apply_sql.mjs scripts/sql/an_inbound_burst_is_accepted_at_once_and_read_in_turn.sql --apply --ddl

create table if not exists public.inbound_mail_queue (
  id                bigserial primary key,
  provider_email_id text not null,
  svix_id           text,
  payload           text not null,
  from_email        text not null default '',
  to_email          text not null default '',
  subject           text not null default '',
  thread_key        text,
  owner_seat        text not null default 'customer_support'
                    check (owner_seat in ('accountant', 'marketing', 'customer_support', 'sales_engineer', 'ceo')),
  status            text not null default 'queued' check (status in ('queued', 'reading', 'done', 'dead')),
  attempts          integer not null default 0,
  max_attempts      integer not null default 5,
  next_attempt_at   timestamptz not null default now(),
  received_at       timestamptz not null default now(),
  claimed_at        timestamptz,
  claimed_by        text,
  lease_until       timestamptz,
  finished_at       timestamptz,
  outcome           jsonb,
  last_error        text,
  handoff_id        bigint
);
create unique index if not exists inbound_mail_queue_provider_email_id_key on public.inbound_mail_queue (provider_email_id);
create index if not exists inbound_mail_queue_open on public.inbound_mail_queue (next_attempt_at, id) where status in ('queued', 'reading');
create index if not exists inbound_mail_queue_thread on public.inbound_mail_queue (thread_key, id) where status in ('queued', 'reading');
create index if not exists inbound_mail_queue_done on public.inbound_mail_queue (finished_at) where status = 'done';

alter table public.inbound_mail_queue enable row level security;
drop policy if exists inbound_mail_queue_service_role_only on public.inbound_mail_queue;
create policy inbound_mail_queue_service_role_only on public.inbound_mail_queue
  as permissive for all to public using (false) with check (false);
revoke all on public.inbound_mail_queue from anon, authenticated;
revoke all on sequence public.inbound_mail_queue_id_seq from anon, authenticated;
comment on table public.inbound_mail_queue is
  'One row per inbound e-mail resend_inbound accepted (unique provider_email_id), holding the verified delivery until its reader '
  'reads it; done rows are deleted after 30 days, dead rows (handed to their seat) are kept. it_engineer, 15 Nov 2026.';

-- A dead row holds an e-mail nobody has read, so the table is exported beside inbound_messages.
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('inbound_mail_queue', true, 'conversation', 'inbound e-mail accepted by resend_inbound and waiting to be read; a dead row is mail no reader could read, handed to its seat (15 Nov 2026)', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

update public.internal_credential set scope = scope || array['resend_inbound']
 where context = 'db.internal' and active and not ('resend_inbound' = any (scope));

-- How many messages may be read at once, estate-wide. The one place: the claim and the kick both read it.
create or replace function public.fn_inbound_mail_readers()
returns integer language sql immutable security definer set search_path to 'public', 'pg_temp' as $fn$ select 2 $fn$;
revoke execute on function public.fn_inbound_mail_readers() from public, anon, authenticated;

-- The wait before attempt n+1, after attempt n failed or its reader died.
create or replace function public.fn_inbound_mail_backoff(p_attempts integer)
returns interval language sql immutable security definer set search_path to 'public', 'pg_temp' as $fn$
  select case when coalesce(p_attempts, 0) <= 1 then interval '1 minute'
              when p_attempts = 2 then interval '5 minutes'
              when p_attempts = 3 then interval '15 minutes'
              else interval '60 minutes' end
$fn$;
revoke execute on function public.fn_inbound_mail_backoff(integer) from public, anon, authenticated;

-- The webhook's record. A redelivery of a message already on file changes nothing and says so.
create or replace function public.fn_inbound_mail_accept(p_provider_email_id text, p_svix_id text, p_payload text,
  p_from text default '', p_to text default '', p_subject text default '', p_thread_key text default null,
  p_owner_seat text default 'customer_support')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint; v_status text;
begin
  if coalesce(btrim(p_provider_email_id), '') = '' then raise exception 'an inbound e-mail must carry its provider id'; end if;
  insert into public.inbound_mail_queue (provider_email_id, svix_id, payload, from_email, to_email, subject, thread_key, owner_seat)
  values (p_provider_email_id, p_svix_id, coalesce(p_payload, ''), left(coalesce(p_from, ''), 320), left(coalesce(p_to, ''), 320),
          left(coalesce(p_subject, ''), 300), nullif(left(coalesce(p_thread_key, ''), 700), ''),
          case when p_owner_seat in ('accountant', 'marketing', 'customer_support', 'sales_engineer', 'ceo') then p_owner_seat
               else 'customer_support' end)
  on conflict (provider_email_id) do nothing
  returning id into v_id;
  if v_id is not null then return jsonb_build_object('queued', true, 'duplicate', false, 'id', v_id); end if;
  select id, status into v_id, v_status from public.inbound_mail_queue where provider_email_id = p_provider_email_id;
  return jsonb_build_object('queued', false, 'duplicate', true, 'id', v_id, 'status', v_status);
end $fn$;
revoke execute on function public.fn_inbound_mail_accept(text, text, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_inbound_mail_accept(text, text, text, text, text, text, text, text) to service_role;

-- A message no reader could finish: dead, and handed to the seat that owns the mail with the reason.
create or replace function public.fn_inbound_mail_dead_letter(p_id bigint, p_reason text)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.inbound_mail_queue; v_h bigint; v_reason text := left(coalesce(nullif(btrim(p_reason), ''), 'no reason was given'), 1000);
begin
  update public.inbound_mail_queue
     set status = 'dead', finished_at = now(), lease_until = null, last_error = v_reason
   where id = p_id and status <> 'dead'
  returning * into r;
  if not found then return null; end if;
  v_h := public.fn_seat_handoff('it_engineer', r.owner_seat, 'it.finding', 'inbound_mail_queue', r.id::text, jsonb_build_object(
    'duty', 'inbound_mail_dead_letter', 'subject', 'resend_inbound', 'issue_key', 'inbound_mail_dead_letter:' || r.id,
    'title', left('An e-mail to ' || r.to_email || ' from ' || r.from_email || ' could not be read after ' || r.attempts
                  || ' attempt(s): ' || v_reason, 200),
    'provider_email_id', r.provider_email_id, 'from_email', r.from_email, 'to_email', r.to_email,
    'mail_subject', left(r.subject, 200), 'received_at', r.received_at, 'attempts', r.attempts, 'reason', v_reason,
    'ask', case when r.owner_seat = 'accountant'
                then 'Nothing was booked from this e-mail. Replay it with the accountant''s expense_sweep (email_id '
                     || r.provider_email_id || ', dry_run first), or read the receipt yourself. Once the cause is fixed, '
                     || 'fn_inbound_mail_requeue(' || r.id || ') reads it again.'
                else 'Nobody has read this e-mail yet and the sender has had no answer. Read it in Resend (or the mailbox) and '
                     || 'act on it. Once the cause is fixed, fn_inbound_mail_requeue(' || r.id || ') reads it again.' end));
  update public.inbound_mail_queue set handoff_id = v_h where id = r.id;
  return v_h;
end $fn$;
revoke execute on function public.fn_inbound_mail_dead_letter(bigint, text) from public, anon, authenticated;

-- Hand a reader the oldest due messages it may read now. Takes back a message whose reader stopped renewing its lease.
create or replace function public.fn_inbound_mail_claim(p_worker text, p_limit integer default 1)
returns setof public.inbound_mail_queue
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; v_live integer; v_slots integer;
begin
  if coalesce(btrim(p_worker), '') = '' then raise exception 'a reader must name itself'; end if;
  -- one claim at a time, estate-wide, so the count of messages being read is exact (two readers counting at once would both
  -- see a free slot)
  perform pg_advisory_xact_lock(hashtext('public.inbound_mail_queue claim'));
  for r in select q.id, q.attempts, q.max_attempts from public.inbound_mail_queue q
            where q.status = 'reading' and q.lease_until < now() for update loop
    if r.attempts >= r.max_attempts then
      perform public.fn_inbound_mail_dead_letter(r.id, 'the reader stopped ' || r.attempts
        || ' times without finishing: the edge worker was killed (memory, CPU or wall clock) while reading this e-mail');
    else
      update public.inbound_mail_queue
         set status = 'queued', claimed_by = null, lease_until = null,
             next_attempt_at = now() + public.fn_inbound_mail_backoff(r.attempts),
             last_error = 'attempt ' || r.attempts || ': the reader stopped without finishing (its lease ran out)'
       where id = r.id;
    end if;
  end loop;
  select count(*) into v_live from public.inbound_mail_queue where status = 'reading';
  v_slots := least(greatest(coalesce(p_limit, 1), 1), 10, public.fn_inbound_mail_readers() - v_live);
  if v_slots <= 0 then return; end if;
  return query
    update public.inbound_mail_queue q
       set status = 'reading', attempts = q.attempts + 1, claimed_at = now(), claimed_by = p_worker,
           lease_until = now() + interval '150 seconds'
     where q.id in (
       select c.id from public.inbound_mail_queue c
        where c.status = 'queued' and c.next_attempt_at <= now() and c.attempts < c.max_attempts
          and (c.thread_key is null or not exists (
                select 1 from public.inbound_mail_queue e
                 where e.thread_key = c.thread_key and e.id < c.id and e.status in ('queued', 'reading')))
        order by c.id
        limit v_slots
        for update skip locked)
    returning q.*;
end $fn$;
revoke execute on function public.fn_inbound_mail_claim(text, integer) from public, anon, authenticated;
grant execute on function public.fn_inbound_mail_claim(text, integer) to service_role;

-- A live reader renews its lease. False: the message is no longer this reader's (it must stop writing for it).
create or replace function public.fn_inbound_mail_touch(p_id bigint, p_worker text)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  update public.inbound_mail_queue set lease_until = now() + interval '150 seconds'
   where id = p_id and status = 'reading' and claimed_by = p_worker;
  return found;
end $fn$;
revoke execute on function public.fn_inbound_mail_touch(bigint, text) from public, anon, authenticated;
grant execute on function public.fn_inbound_mail_touch(bigint, text) to service_role;

-- The reader's verdict on one message.
create or replace function public.fn_inbound_mail_finish(p_id bigint, p_worker text, p_ok boolean,
  p_outcome jsonb default null, p_error text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.inbound_mail_queue; v_next timestamptz;
begin
  select * into r from public.inbound_mail_queue where id = p_id for update;
  if not found then return jsonb_build_object('finished', false, 'reason', 'no such message'); end if;
  if r.status <> 'reading' or r.claimed_by is distinct from p_worker then
    return jsonb_build_object('finished', false, 'reason', 'this message is no longer this reader''s', 'status', r.status);
  end if;
  if coalesce(p_ok, false) then
    update public.inbound_mail_queue set status = 'done', finished_at = now(), lease_until = null, outcome = p_outcome
     where id = p_id;
    return jsonb_build_object('finished', true, 'status', 'done');
  end if;
  update public.inbound_mail_queue set outcome = coalesce(p_outcome, outcome) where id = p_id;
  if r.attempts >= r.max_attempts then
    perform public.fn_inbound_mail_dead_letter(p_id, 'attempt ' || r.attempts || ': ' || coalesce(p_error, 'no reason was given'));
    return jsonb_build_object('finished', true, 'status', 'dead');
  end if;
  v_next := now() + public.fn_inbound_mail_backoff(r.attempts);
  update public.inbound_mail_queue
     set status = 'queued', claimed_by = null, lease_until = null, next_attempt_at = v_next,
         last_error = left('attempt ' || r.attempts || ': ' || coalesce(p_error, 'no reason was given'), 1000)
   where id = p_id;
  return jsonb_build_object('finished', true, 'status', 'queued', 'next_attempt_at', v_next);
end $fn$;
revoke execute on function public.fn_inbound_mail_finish(bigint, text, boolean, jsonb, text) from public, anon, authenticated;
grant execute on function public.fn_inbound_mail_finish(bigint, text, boolean, jsonb, text) to service_role;

-- A dead message, read again once its cause is fixed (a seat or a session calls it; nothing calls it on a schedule).
create or replace function public.fn_inbound_mail_requeue(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  update public.inbound_mail_queue
     set status = 'queued', attempts = 0, next_attempt_at = now(), claimed_by = null, lease_until = null, finished_at = null
   where id = p_id and status = 'dead';
  return jsonb_build_object('requeued', found, 'id', p_id);
end $fn$;
revoke execute on function public.fn_inbound_mail_requeue(bigint) from public, anon, authenticated;

-- Start a reader for each due message a free slot can take (pg_cron every minute, and each reader when it finishes); forget
-- done rows after 30 days.
create or replace function public.fn_inbound_mail_kick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_due integer; v_live integer; v_n integer; v_secret text; v_ref text; v_req bigint; v_reqs bigint[] := '{}'; v_gone integer;
begin
  delete from public.inbound_mail_queue where status = 'done' and finished_at < now() - interval '30 days';
  get diagnostics v_gone = row_count;
  select count(*) filter (where (status = 'queued' and next_attempt_at <= now()) or (status = 'reading' and lease_until < now())),
         count(*) filter (where status = 'reading' and lease_until >= now())
    into v_due, v_live
    from public.inbound_mail_queue where status in ('queued', 'reading');
  v_n := least(v_due, greatest(0, public.fn_inbound_mail_readers() - v_live));
  if v_n = 0 then return jsonb_build_object('kicked', 0, 'due', v_due, 'reading', v_live, 'forgotten', v_gone); end if;
  select value into v_secret from public.app_secrets where key = 'cred_db_internal';
  v_ref := public.qd_project_ref();
  if coalesce(v_secret, '') = '' or v_ref is null then
    return jsonb_build_object('kicked', 0, 'due', v_due, 'reading', v_live, 'reason', 'no db.internal credential or project ref');
  end if;
  for i in 1..v_n loop
    select net.http_post('https://' || v_ref || '.supabase.co/functions/v1/resend_inbound?drain=1',
                         jsonb_build_object('__secret', v_secret, 'drain', true), '{}'::jsonb,
                         '{"Content-Type":"application/json"}'::jsonb, 10000) into v_req;
    v_reqs := v_reqs || v_req;
  end loop;
  return jsonb_build_object('kicked', v_n, 'due', v_due, 'reading', v_live, 'requests', to_jsonb(v_reqs), 'forgotten', v_gone);
end $fn$;
revoke execute on function public.fn_inbound_mail_kick() from public, anon, authenticated;
grant execute on function public.fn_inbound_mail_kick() to service_role;   -- a reader hands on to the next (lib/queue.ts)

select cron.schedule('inbound_mail_drain', '* * * * *',
  $CRON$set statement_timeout = '20s'; select public.fn_inbound_mail_kick();$CRON$);
insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('inbound_mail_drain', 'Inbound mail reader kick', 'Messaging',
   'Every minute: fn_inbound_mail_kick() starts resend_inbound''s reader (?drain=1) for each due message in '
   || 'public.inbound_mail_queue that a free reader slot (fn_inbound_mail_readers) can take, and forgets done rows after '
   || '30 days. The webhook records each e-mail and answers at once; this is the safety net that reads what it left. '
   || 'it_engineer, 15 Nov 2026 (18 receipts in 3 minutes: 546/504, 5 of 18 recorded).')
on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;
insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'inbound_mail_drain', 'it_engineer',
   'Every minute: starts the inbound mail reader for due messages a free slot can take.',
   'scripts/sql/an_inbound_burst_is_accepted_at_once_and_read_in_turn.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

-- PROBE: read-only; returns its verdict as a row (the file holds DDL, so it must not raise).
with f as (select count(*) n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and p.prosecdef
              and p.proname in ('fn_inbound_mail_readers', 'fn_inbound_mail_backoff', 'fn_inbound_mail_accept', 'fn_inbound_mail_dead_letter',
                                'fn_inbound_mail_claim', 'fn_inbound_mail_touch', 'fn_inbound_mail_finish', 'fn_inbound_mail_requeue',
                                'fn_inbound_mail_kick')
              and exists (select 1 from unnest(p.proconfig) cfg where cfg like 'search_path=%')
              and not has_function_privilege('anon', p.oid, 'execute')
              and not has_function_privilege('authenticated', p.oid, 'execute')),
     t as (select count(*) n from pg_class c where c.oid = 'public.inbound_mail_queue'::regclass and c.relrowsecurity
              and not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'select')),
     j as (select count(*) n from cron.job where jobname = 'inbound_mail_drain' and active),
     c as (select count(*) n from public.internal_credential where context = 'db.internal' and active and 'resend_inbound' = any (scope))
select case when (select n from f) = 9 and (select n from t) = 1 and (select n from j) = 1 and (select n from c) >= 1 then 'PROBE OK'
            else 'PROBE FAILED: routines ' || (select n from f) || ' of 9, table ' || (select n from t) || ', job ' || (select n from j)
                 || ', scope ' || (select n from c) end as verdict;
