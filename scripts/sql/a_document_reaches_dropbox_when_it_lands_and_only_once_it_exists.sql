-- A DOCUMENT REACHES DROPBOX WHEN IT LANDS, AND ONLY ONCE IT EXISTS.
--
-- Assigned: sales_engineer (owner of the Dropbox tree and the uploader). 14 Sep 2026.
--
-- The founder, 14 Sep 2026: "we need to eliminate all other causes with fixes. unless its a server
-- issue from dropbox or supabase then i see no reason for any failures" (founder_instruction 208).
-- This file removes three internal causes: a document waiting a whole day for the daily pass, a
-- name Dropbox refuses, and a queue row pointing at a file storage never received.
--
-- MEASURED BEFORE WRITING (14 Sep 2026, production):
--   trigger misses  the only callers of dropbox_backup were resilience_ping's once-a-day pass (plus
--                   backlog passes) and nothing else: a supplier's licence uploaded at 09:00 reached
--                   Dropbox the next day at the earliest. fn_enqueue_doc_backups takes 2.75 s (timed
--                   in a rolled-back block), too slow to run inside a customer's upload transaction.
--   names           fn_dbx_safe removed only \ / : * ? " < > | and CR/LF/TAB. Other control
--                   characters, a trailing dot or space (Dropbox refuses a component ending in
--                   either) and length were not handled, and the file-name half of every path
--                   (regexp_replace(path,'^.*/','')) was never sanitised at all.
--   originals       26 rows abandoned, each with a recorded reason ('abandoned: ...'): 12 retired
--                   quote comparisons, 11 supplier_details for deleted test suppliers, 3 seed
--                   catalogue/profile files that were never in storage. Verified, unchanged here.
--                   The enqueue queued any path a column named whether or not storage held it.
--
-- WHAT CHANGES:
--   1. fn_backup_kick(reason, mode) posts to dropbox_backup through pg_net (asynchronous, so the
--      writer never waits) under its own credential 'fn.backup_kick', scoped to dropbox_backup only,
--      and is debounced to one kick a minute. Statement triggers on the columns that name a
--      document (leads x10, customers, inquiries, transactions) kick it in 'enqueue' mode, and
--      fn_conversation_archived kicks it in 'process_only' mode after it has queued the PDF.
--      resilience_ping stays the catch-up; .github/workflows/dropbox-backup-second-scheduler.yml is
--      the scheduler outside Supabase.
--   2. fn_dbx_safe also strips every control character and trailing dots/spaces, and never returns
--      an empty name. fn_dbx_component caps a component at 200 characters (80 in strict mode)
--      while keeping its id suffix (" (123)", " #123") and extension, so two long names cannot
--      collide. fn_dbx_path applies it to every component. Arabic and emoji are kept.
--   3. trg_doc_backups_admit (BEFORE INSERT on doc_backups): a 'storage' row whose object is not in
--      storage.objects is parked as status 'waiting_source' instead of being queued for upload,
--      and every dropbox_path is normalised by fn_dbx_path, for every writer at once.
--      fn_doc_backups_next(limit) is what the uploader now reads: it promotes parked rows whose
--      object has arrived, backs off an erroring row exponentially (2, 4, 8 ... minutes after its
--      last attempt), puts a half-finished chunked upload first, and leaves ZZ DEMO rows out.
--      The credential travels in the pg_net JSON body, the convention of every net.http_post in
--      scripts/sql (fn_kb_embed_dispatch and 19 others). Measured: anon and authenticated hold no
--      privilege on any net table (USAGE on the schema only); pg_net.ttl is 6 hours, so response
--      rows are purged; sent requests leave net.http_request_queue when dispatched.
--   4. doc_backups gains upload_state (the Dropbox session id, offset and block hashes of a
--      chunked upload, so the next run resumes it) and last_attempt_at (the backoff clock).
--
--   node scripts/apply_sql.mjs scripts/sql/a_document_reaches_dropbox_when_it_lands_and_only_once_it_exists.sql --apply --ddl

-- ── 1. THE COLUMNS THE UPLOADER NEEDS ──────────────────────────────────────────────────────────────
alter table public.doc_backups add column if not exists upload_state jsonb;
alter table public.doc_backups add column if not exists last_attempt_at timestamptz;
comment on column public.doc_backups.upload_state is
  'A chunked Dropbox upload in progress: {session_id, offset, size, blocks[]}. Written by dropbox_backup when a run ends mid-file; the next run resumes from offset. Cleared when the file is verified.';

-- ── 2. NAMES DROPBOX ACCEPTS ───────────────────────────────────────────────────────────────────────
create or replace function public.fn_dbx_safe(x text) returns text
language sql immutable set search_path to 'public', 'pg_catalog' as $$
  select coalesce(nullif(
           regexp_replace(
             btrim(regexp_replace(regexp_replace(coalesce(x, ''), '[\\/:*?"<>|[:cntrl:]]+', ' ', 'g'), '\s+', ' ', 'g')),
             '[. ]+$', ''),
           ''), '_')
$$;
revoke execute on function public.fn_dbx_safe(text) from public, anon, authenticated;
comment on function public.fn_dbx_safe(text) is
  'One Dropbox path component: characters Dropbox forbids and control characters become a space, whitespace collapses, no trailing dot or space, never empty. Arabic and emoji are kept.';

create or replace function public.fn_dbx_component(p text, p_max integer default 200) returns text
language plpgsql immutable set search_path to 'public', 'pg_catalog' as $fn$
declare s text := public.fn_dbx_safe(p); tail text;
begin
  if char_length(s) <= p_max then return s; end if;
  -- the id suffix and the extension survive; the middle is cut
  tail := coalesce(substring(s from '((?: \([0-9A-Za-z_-]{1,40}\)| #[0-9A-Za-z_-]{1,40})?(?:\.[A-Za-z0-9]{1,8})?)$'), '');
  return public.fn_dbx_safe(left(s, greatest(p_max - char_length(tail) - 1, 1)) || '…' || tail);
end $fn$;
revoke execute on function public.fn_dbx_component(text, integer) from public, anon, authenticated;

create or replace function public.fn_dbx_path(p text, p_strict boolean default false) returns text
language sql immutable set search_path to 'public', 'pg_catalog' as $$
  select '/' || string_agg(public.fn_dbx_component(u.c, case when p_strict then 80 else 200 end), '/' order by u.n)
    from unnest(string_to_array(p, '/')) with ordinality u(c, n)
   where btrim(u.c) <> ''
$$;
revoke execute on function public.fn_dbx_path(text, boolean) from public, anon, authenticated;

-- ── 3. ADMISSION: ONLY WHAT EXISTS IS QUEUED, AND EVERY PATH IS ONE DROPBOX ACCEPTS ────────────────
create or replace function public.trg_doc_backups_admit()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  new.dropbox_path := public.fn_dbx_path(new.dropbox_path);
  -- A rehearsal's documents are never uploaded: its fixtures are torn down minutes later, and the
  -- row would then fail as 'supplier_missing' for ever (measured: 4 such error rows and 22 parked
  -- rows, all ZZ DEMO suppliers/customers of a harness run, on the day this was written).
  if new.entity is distinct from 'zz_demo' and (
       coalesce(new.dropbox_path, '') ~* 'zz[ _-]?demo' or coalesce(new.path, '') ~* 'zz[ _-]?demo'
       or (new.entity = 'supplier' and exists (select 1 from public.leads l where l.id::text = new.entity_id and l.is_demo))
       or (new.entity = 'customer' and exists (select 1 from public.customers c where c.id::text = new.entity_id and c.is_demo))) then
    new.entity := 'zz_demo';
  end if;
  if new.source = 'storage' and new.status = 'pending'
     and not exists (select 1 from storage.objects o where o.bucket_id = new.bucket and o.name = new.path) then
    new.status := 'waiting_source';
    new.error := left('waiting: storage holds no object at ' || coalesce(new.bucket, '?') || '/' || coalesce(new.path, '?'), 300);
  end if;
  return new;
end $fn$;
revoke execute on function public.trg_doc_backups_admit() from public, anon, authenticated;
drop trigger if exists a10_doc_backups_admit on public.doc_backups;
create trigger a10_doc_backups_admit before insert on public.doc_backups
  for each row execute function public.trg_doc_backups_admit();

-- Rows already queued get the same treatment once; rows already in Dropbox keep their path.
update public.doc_backups d set entity = 'zz_demo'
 where d.status in ('pending', 'error', 'waiting_source') and d.entity <> 'zz_demo'
   and (coalesce(d.dropbox_path, '') ~* 'zz[ _-]?demo' or coalesce(d.path, '') ~* 'zz[ _-]?demo'
        or (d.entity = 'supplier' and exists (select 1 from public.leads l where l.id::text = d.entity_id and l.is_demo))
        or (d.entity = 'customer' and exists (select 1 from public.customers c where c.id::text = d.entity_id and c.is_demo)));
-- the fixtures behind those rows were torn down; the rows say so rather than wait for ever
update public.doc_backups d
   set status = 'abandoned', error = 'abandoned: ZZ DEMO fixture of a rehearsal, torn down; never uploaded (14 Sep 2026)'
 where d.entity = 'zz_demo' and d.status in ('error', 'waiting_source') and d.created_at < now() - interval '1 hour';
update public.doc_backups d
   set status = 'waiting_source', error = left('waiting: storage holds no object at ' || d.bucket || '/' || d.path, 300)
 where d.status in ('pending', 'error') and d.source = 'storage'
   and not exists (select 1 from storage.objects o where o.bucket_id = d.bucket and o.name = d.path);
update public.doc_backups d set dropbox_path = public.fn_dbx_path(d.dropbox_path)
 where d.status in ('pending', 'error', 'waiting_source') and d.dropbox_path is distinct from public.fn_dbx_path(d.dropbox_path);

-- What the uploader reads - its ONLY reader. Rows are CLAIMED atomically (status 'processing',
-- FOR UPDATE SKIP LOCKED), so two overlapping runs (a kick, the drain chain, the 15-minute tick)
-- never upload the same row. A claim older than 10 minutes belonged to a run that died (the edge
-- limit is 150 s) and goes back to 'pending'. p_demo claims ONLY zz_demo rows: the probes prove the
-- contract on them; the edge function never passes it, so it never sees a demo row.
alter table public.doc_backups add column if not exists claimed_at timestamptz;
alter table public.doc_backups add column if not exists claimed_by text;
drop function if exists public.fn_doc_backups_next(integer);
create or replace function public.fn_doc_backups_next(p_limit integer default 8, p_run text default null, p_demo boolean default false)
returns setof public.doc_backups
language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if coalesce(btrim(p_run), '') = '' then raise exception 'fn_doc_backups_next: p_run (the claiming run id) is required'; end if;
  update public.doc_backups d set status = 'pending', claimed_at = null, claimed_by = null,
         error = left('claim by ' || coalesce(d.claimed_by, '?') || ' expired after 10 minutes; requeued', 300)
   where d.status = 'processing' and d.claimed_at < now() - interval '10 minutes';
  update public.doc_backups d set status = 'pending', error = null
   where d.status = 'waiting_source'
     and exists (select 1 from storage.objects o where o.bucket_id = d.bucket and o.name = d.path);
  return query
    with c as (
      select d.id from public.doc_backups d
       where d.status in ('pending', 'error') and d.attempts < 5
         and (d.entity = 'zz_demo') = coalesce(p_demo, false)
         and (d.status = 'pending' or d.last_attempt_at is null
              or d.last_attempt_at < now() - interval '1 minute' * power(2, least(d.attempts, 8)))
       order by (d.upload_state is not null) desc, d.id
       limit greatest(1, least(coalesce(p_limit, 8), 25))
       for update skip locked)
    update public.doc_backups d set status = 'processing', claimed_at = now(), claimed_by = p_run
      from c where d.id = c.id
    returning d.*;
end $fn$;
revoke execute on function public.fn_doc_backups_next(integer, text, boolean) from public, anon, authenticated;

-- ── 4. THE KICK ────────────────────────────────────────────────────────────────────────────────────
-- Its own credential, so internal_credential_audit names the database, not the watchdog.
do $mint$
declare v text;
begin
  if not exists (select 1 from public.app_secrets where key = 'cred_fn_backup_kick') then
    v := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.internal_credential (context, label, secret_hash, scope)
    values ('fn.backup_kick', 'the database kicks dropbox_backup when a document lands (fn_backup_kick)',
            public.fn_internal_credential_hash(v), array['dropbox_backup']);
    insert into public.app_secrets (key, value) values ('cred_fn_backup_kick', v);
  end if;
end $mint$;

create or replace function public.fn_backup_kick(p_reason text, p_mode text default 'process_only')
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_ref text; v_secret text; v_req bigint;
begin
  if p_mode not in ('process_only', 'enqueue') then
    raise exception 'fn_backup_kick: mode must be process_only or enqueue, got %', p_mode;
  end if;
  -- the lock makes check-then-act atomic: two kicks in the same instant cannot both pass
  if not pg_try_advisory_xact_lock(hashtext('fn_backup_kick'))
     or exists (select 1 from public.agent_runs where agent = 'backup_kick' and status = 'ok'
                and started_at > now() - interval '60 seconds') then
    return jsonb_build_object('kicked', false, 'reason', 'debounced: a kick in the last 60 seconds is still draining');
  end if;
  select value into v_ref from public.app_secrets where key = 'project_ref';
  select value into v_secret from public.app_secrets where key = 'cred_fn_backup_kick';
  if coalesce(v_ref, '') = '' or coalesce(v_secret, '') = '' then
    insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
    values ('backup_kick', 'error', jsonb_build_object('reason', p_reason, 'mode', p_mode),
            'Could not kick dropbox_backup: app_secrets project_ref or cred_fn_backup_kick is missing. The daily pass still runs.', now(), now());
    return jsonb_build_object('kicked', false, 'reason', 'missing project_ref or cred_fn_backup_kick');
  end if;
  select net.http_post(
           url := 'https://' || v_ref || '.supabase.co/functions/v1/dropbox_backup',
           headers := '{"Content-Type":"application/json"}'::jsonb,
           body := jsonb_build_object('__secret', v_secret, 'mode', p_mode, 'reason', left(coalesce(p_reason, ''), 120), 'chain', 0),
           timeout_milliseconds := 150000) into v_req;
  insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
  values ('backup_kick', 'ok', jsonb_build_object('reason', p_reason, 'mode', p_mode, 'request_id', v_req),
          left('dropbox_backup kicked (' || p_mode || '): ' || coalesce(p_reason, ''), 500), now(), now());
  return jsonb_build_object('kicked', true, 'request_id', v_req, 'mode', p_mode);
end $fn$;
revoke execute on function public.fn_backup_kick(text, text) from public, anon, authenticated;

-- A failed kick must never fail the customer's or supplier's write; it is logged instead, and the
-- IT engineer's daily check still finds anything that did not arrive.
create or replace function public.trg_document_landed_kicks_backup()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  begin
    perform public.fn_backup_kick('document_landed:' || tg_table_name, 'enqueue');
  exception when others then
    insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
    values ('backup_kick', 'error', jsonb_build_object('table', tg_table_name, 'stage', 'trigger'),
            left('The document-landed kick failed on ' || tg_table_name || ': ' || sqlerrm, 500), now(), now());
  end;
  return null;
end $fn$;
revoke execute on function public.trg_document_landed_kicks_backup() from public, anon, authenticated;

drop trigger if exists z70_document_landed_kicks_backup on public.leads;
create trigger z70_document_landed_kicks_backup
  after insert or update of license_doc_path, iban_doc_path, egr_doc_path, insurance_doc_path, vat_doc_path, iso_doc_path,
                            manufacturer_auth_doc_path, company_profile_doc_path, catalog_doc_paths, signed_terms_path
  on public.leads for each statement execute function public.trg_document_landed_kicks_backup();
drop trigger if exists z70_document_landed_kicks_backup on public.customers;
create trigger z70_document_landed_kicks_backup after insert or update of signed_terms_path
  on public.customers for each statement execute function public.trg_document_landed_kicks_backup();
drop trigger if exists z70_document_landed_kicks_backup on public.inquiries;
create trigger z70_document_landed_kicks_backup after insert or update of drawing_file_path
  on public.inquiries for each statement execute function public.trg_document_landed_kicks_backup();
drop trigger if exists z70_document_landed_kicks_backup on public.transactions;
create trigger z70_document_landed_kicks_backup after insert or update of doc_path
  on public.transactions for each statement execute function public.trg_document_landed_kicks_backup();

-- fn_conversation_archived: MANIFEST-last definition (every_conversation_is_kept_backed_up_twice_and_
-- readable_by_the_sales_engineer.sql) with one line added: the PDF it just queued is kicked.
create or replace function public.fn_conversation_archived(
  p_source_table text, p_source_id text, p_path text, p_bytes bigint)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_queued integer;
begin
  if coalesce(p_path, '') !~ '^conversations/' then
    return jsonb_build_object('ok', false, 'reason', 'the PDF must live under backups/conversations/');
  end if;
  insert into public.conversation_archive (source_table, source_id, pdf_path, bytes)
  values (p_source_table, p_source_id, p_path, p_bytes)
  on conflict (source_table, source_id) do update set pdf_path = excluded.pdf_path, bytes = excluded.bytes, archived_at = now();
  v_queued := public.fn_enqueue_doc_backups();
  if v_queued > 0 then perform public.fn_backup_kick('conversation_archived', 'process_only'); end if;
  return jsonb_build_object('ok', true, 'queued_for_dropbox', v_queued);
end $fn$;
revoke execute on function public.fn_conversation_archived(text, text, text, bigint) from public, anon, authenticated;

-- ── 5. PROBE: the names, the admission gate; self-cleaning ─────────────────────────────────────────
do $probe$
declare
  long text := repeat('شركة المقاولات العامة ', 14);          -- 308 characters of Arabic
  p text; n int; v_id bigint; v_a bigint[]; v_b bigint[]; v_c bigint[];
begin
  p := public.fn_dbx_path('/QuotesDone Backup/Suppliers/Fit-out/' || long || ' (30999)/Trade licence - ' || repeat('x', 290) || '.pdf');
  assert p like '%(30999)/%', 'the id suffix must survive truncation: ' || p;
  assert p like '%.pdf', 'the extension must survive truncation';
  assert (select max(char_length(c)) from unnest(string_to_array(p, '/')) c) <= 200, 'a component is longer than 200';
  assert public.fn_dbx_path(p) = p, 'fn_dbx_path must be idempotent';
  assert public.fn_dbx_safe('مؤسسة النور للتجارة') = 'مؤسسة النور للتجارة', 'Arabic must be kept as-is';
  assert public.fn_dbx_safe('🏗️ Build & Co') = '🏗️ Build & Co', 'emoji must be kept';
  assert public.fn_dbx_safe('a<b>c:d"e|f?g*h' || chr(1) || 'i. . ') = 'a b c d e f g h i', 'forbidden, control and trailing characters';
  assert public.fn_dbx_safe('...') = '_', 'a name of only dots must not become empty';
  assert public.fn_dbx_path('/a/b', true) = '/a/b' and char_length(public.fn_dbx_component(repeat('y', 300) || ' #77.pdf', 80)) <= 80, 'strict mode';

  insert into public.doc_backups (entity, entity_id, doc_type, bucket, path, file_name, dropbox_path, source, dedupe_key)
  values ('zz_demo', 'zz_demo', 'ZZ DEMO', 'supplier-docs', 'zz_demo/never-uploaded.pdf', 'never-uploaded.pdf',
          '/QuotesDone Backup/_zz_demo/ZZ DEMO file. ', 'storage', 'ZZDEMO:admit:' || txid_current())
  returning id into v_id;
  assert (select status from public.doc_backups where id = v_id) = 'waiting_source', 'a missing original must be parked, not queued';
  assert (select dropbox_path from public.doc_backups where id = v_id) = '/QuotesDone Backup/_zz_demo/ZZ DEMO file', 'the path must be normalised on insert';
  -- the object arrives -> promoted -> claimed -> marked done the way dropbox_backup marks it
  update public.doc_backups
     set bucket = 'brand',
         path = (select o.name from storage.objects o
                  where o.bucket_id = 'brand'
                    and not exists (select 1 from public.doc_backups d where d.bucket = o.bucket_id and d.path = o.name)
                  order by o.name limit 1)
   where id = v_id;
  insert into public.doc_backups (entity, entity_id, doc_type, source, gen_kind, gen_ref, dropbox_path, dedupe_key)
  select 'zz_demo', 'zz_demo', 'ZZ DEMO', 'generated', 'zz_demo', g::text, '/QuotesDone Backup/_zz_demo/' || g || '.pdf', 'ZZDEMO:admit:claim:' || g || ':' || txid_current()
    from generate_series(1, 3) g;
  select array_agg(id) into v_a from public.fn_doc_backups_next(2, 'zz_demo_run_A', true);
  v_b := '{}';
  for i in 1..40 loop     -- other rehearsals' zz_demo rows come first by id; claim until none is left
    select array_agg(id) into v_c from public.fn_doc_backups_next(25, 'zz_demo_run_B', true);
    exit when v_c is null;
    assert not (v_b && v_c) and not (v_a && v_c), 'a row was claimed twice';
    v_b := v_b || v_c;
  end loop;
  -- another rehearsal's zz_demo rows may be claimed too; they are handed back below
  assert v_id = any(v_a || v_b), 'the parked row must be promoted and claimed once its object exists';
  assert cardinality(v_a) <= 2 and not (v_a && v_b), 'two claims must be disjoint: ' || v_a::text || ' / ' || coalesce(v_b::text, '{}');
  assert (select count(*) from public.doc_backups where dedupe_key like 'ZZDEMO:admit:%' and status = 'processing') = 4, 'all four probe rows claimed, as processing';
  update public.doc_backups set status = 'done', claimed_at = null, claimed_by = null, verified_at = now()
   where dedupe_key like 'ZZDEMO:admit:%';
  assert (select count(*) from public.fn_doc_backups_next(25, 'zz_demo_run_C', true) x where x.dedupe_key like 'ZZDEMO:admit:%') = 0, 'a done row is never claimed again';
  update public.doc_backups set status = 'pending', claimed_at = null, claimed_by = null
   where claimed_by in ('zz_demo_run_A', 'zz_demo_run_B', 'zz_demo_run_C') and dedupe_key not like 'ZZDEMO:admit:%';
  delete from public.doc_backups where dedupe_key like 'ZZDEMO:admit:%';
  select count(*) into n from public.doc_backups where dedupe_key like 'ZZDEMO:admit:%';
  assert n = 0, 'probe rows left behind';
  raise notice 'names and admission: ok (sample %)', left(p, 120);
  raise notice 'queue now: %', (select jsonb_object_agg(status, c) from (select status, count(*) c from public.doc_backups group by 1) z);
end $probe$;
