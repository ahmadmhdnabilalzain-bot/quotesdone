-- THE DAILY TABLE EXPORTS ARE KEPT FOR 90 DAYS, AND FRIDAY FULL COPIES FOR 12 MONTHS.
--
-- Assigned: it_engineer. 15 Sep 2026.
--
-- The decision (offered to the founder as the default on 15 Sep 2026; he did not object): every daily
-- export is kept 90 days; the Friday full copy is kept 12 months; a restore must always stay possible,
-- so the newest full copy is never deleted, and no daily incremental a kept kb_chunks restore chain
-- still needs is deleted (a kb_chunks restore is the latest full day plus every later day).
--
-- MEASURED BEFORE WRITING (15 Sep 2026, production, read-only):
--   * The 'backups' bucket holds 64 dated export days, 2026-06-23 .. 2026-09-07, written by backup v1
--     before pg_cron went on 7 Sep: 5,199 objects, 13,470 MB. 45 days have a _manifest.json; 19 do not
--     (v1 died mid-run or errored), and the last day, 2026-09-07, is one of the 19. The oldest is 84 days
--     old today, so NOTHING has reached 90 days yet: 2026-06-23 is 91 days old on 2026-09-22.
--   * Read through fn_backup_prune_plan in an aborted transaction (15 Sep 2026, with the founder's
--     documents-never and month-forever rules below): 64 days, 0 to delete, all 64 kept as "blocked: the
--     latest full copy (2026-09-07) did not complete". The allow-list covers 4,652 of the 5,199 dated
--     objects (13,468 MB; 4,739 before the final review's fix); the other 547 are v1's document
--     inventories, kept for ever. Kept for ever as
--     their month's copy: 2026-06-23, 2026-07-05, 2026-08-01, 2026-09-02. With a complete revived full on
--     Friday 2026-09-18, the first deletion would be on 2026-09-27 (one day, 2026-06-28), and 55 days
--     would be gone by 2026-12-31.
--   * public.table_export_run exists (every_business_table_is_exported_every_day_again.sql, #664) and
--     holds 0 rows: the revived writer has not completed a day yet. No export file is in doc_backups.
--   * Without pruning, a full copy is ~7.3 GB and runs weekly, so storage grows ~32 GB a month in the
--     bucket AND in Dropbox, forever.
--
-- WHAT A DAY IS, AND WHERE ITS FILES ARE (never guessed from names alone):
--   export day   a public.table_export_run row: kind full/incremental, status done/failed/running. A
--                day is a complete restore point only when status = 'done' (fn_table_export_finish
--                checked every page against storage and the manifest).
--   legacy day   a <YYYY-MM-DD>/ folder in 'backups' dated on or before 2026-09-07 (the measured last
--                day of backup v1, which wrote only full copies) with no table_export_run row. It is a
--                FULL day; it is a complete restore point only when its _manifest.json is present
--                (v1 wrote the manifest last). A dated folder after 2026-09-07 with no run row is not
--                listed at all, so it is never deleted.
--   Its files are the storage objects under '<day>/', and its Dropbox copies are the doc_backups rows
--   the TABLE EXPORTS rule queued for that day (dedupe_key 'EXPORT:<day>/...').
--
-- THE RULES (fn_backup_prune_decide, a pure function the probe below exercises):
--   keep   a day 90 days old or newer;
--   keep   a complete Friday (Asia/Dubai) full copy newer than 12 months;
--   keep   the newest complete full copy, and every day after it (the newest restore chain);
--   keep   every day a kept incremental needs: its latest complete full on or before it, and each day
--          between;
--   keep   a day still being written;
--   keep   EVERYTHING when the latest full copy failed or is incomplete, or no complete full copy
--          exists (nothing is deleted while the one thing that makes deletion safe is in doubt);
--   delete everything else, with the reason recorded.
--
-- HOW IT RUNS (no pg_cron; it was removed on the founder's 7 Sep instruction):
--   resilience_ping -> fn_backup_prune_tick every 15 minutes. A PASS is due once per Asia/Dubai day,
--   after that day's export finished (done, or failed after its 6 attempts). The pass writes one
--   public.backup_prune_log row per day it would delete: what (day, files, bytes, Dropbox copies), when,
--   why, and in which mode.
--   MODE: app_secrets.backup_prune_mode. Anything but 'delete' - including no row, which is today - is
--   DRY RUN: the log says what would be deleted and nothing is touched. In 'delete' mode:
--     storage  supabase/functions/backup op 'prune' takes one logged day at a time from
--              fn_backup_prune_storage_next (which re-decides the day before handing over a single name),
--              removes its objects through the Storage API, and reports to fn_backup_prune_storage_done,
--              which stamps the day only when storage holds nothing under '<day>/'.
--     Dropbox  the same conveyor that uploads: the day's doc_backups rows become 'prune_pending' (so the
--              uploader never retries a file whose source is gone), dropbox_backup op 'prune' deletes
--              each dropbox_path through its existing DropboxClient and reports to
--              fn_doc_backups_prune_done; a path already gone is an answer, not a failure.
--     BOTH halves are re-decided first (fn_backup_prune_recheck, called by the tick and by both pickers):
--     a logged day the rules now keep - say the latest full copy failed since - is cancelled by
--     fn_backup_prune_cancel, which in the same statement returns the day's prune_pending/pruning rows to
--     the status they had (status_before_prune). Found by the independent review of #672: before this,
--     the Dropbox picker never re-decided, so storage could keep a day that Dropbox still deleted.
--     Proved by scripts/checks/backup_retention_cancels_both_halves.probe.sql (ZZ DEMO days, rolled back).
--
-- NOTHING IS ONE-WAY:
--   * a pruned export day gets table_export_run.pruned_at, and fn_it_backup_expected (in
--     every_stored_document_source_is_registered_for_backup.sql, applied AFTER this file) stops
--     expecting it, so pruning never raises a false "missing backup";
--   * a storage deletion that failed 3 times, a day still not deleted 2 days after it was logged, or a
--     Dropbox copy that failed 5 times is an it_engineer finding (fn_it_duty_settle 'backup_prune'),
--     closed by the same settle once the deletion completes.
--
-- DOCUMENTS ARE NEVER PRUNED, AND A COPY OF EVERY MONTH IS KEPT FOR EVER. The founder, 15 Sep 2026:
--   "that doesnt mean removing the verified suppliers and registered customers later yea? ... of course
--    that data should never get lost no matter what"
--   * An ALLOW-LIST, not a deny-list: fn_backup_prune_path_allowed accepts only the shapes the table
--     export writes in the 'backups' bucket - <day>/_manifest.json, <day>/<table>/page_NNNN.json and
--     backup v1's <day>/<table>.json - and fn_backup_prune_dropbox_allowed accepts only a doc_backups row
--     the TABLE EXPORTS rule wrote (doc_type 'Database export', dedupe_key 'EXPORT:<path>', Dropbox path
--     /QuotesDone Backup/Company/Database Exports/<YYYY-MM>/<path>). Every picker, count and queue move
--     goes through them, so a document (a trade licence, signed terms, a KYC file, a quotation PDF,
--     anything in fn_backup_source_registry) can never be selected, in storage or in Dropbox, whatever
--     the mode. Measured 15 Sep 2026: of 6,443 objects in all buckets, 0 outside a dated export folder
--     match; 547 inside them are backup v1's <day>/_storage_<bucket>.json inventories (which documents
--     existed that day). None is on the allow-list, so they are kept for ever too. (The first version
--     allowed [a-z0-9_]+ as a table name and let 87 of them through - _storage_brand, _storage_reports,
--     _storage_site - found by the final review of #672. A table name now starts with a letter, and no
--     path segment may start with '_' except _manifest.json. The edge functions check the same rule in
--     supabase/functions/_shared/backup_prune_allow.ts.)
--   * The first complete full copy of every calendar month is kept for ever, whatever its age; a month
--     with no complete full copy keeps its last complete copy. Every table holding a registered customer,
--     a verified supplier or an accepted term is a full copy every day (customers, customer_preference,
--     leads with accepted_terms_at/_version/_sha256/_ip, supplier_capabilities,
--     supplier_capability_confirmation, doc_reviews, company_registration), so one of them survives
--     from every month there has ever been.
--
-- WHAT THIS DOES NOT DO: it does not switch deletion on (backup_prune_mode is not written here), and it
-- does not touch the other folders in 'backups' (conversations/, generated/, accountant/), which are
-- kept for ever.
--
--   node scripts/apply_sql.mjs scripts/sql/the_backups_are_kept_ninety_days_and_friday_copies_a_year.sql --apply --ddl

-- ── 1. THE RECORD ──────────────────────────────────────────────────────────────────────────────────
alter table public.table_export_run add column if not exists pruned_at timestamptz;
comment on column public.table_export_run.pruned_at is
  'When the day''s files were removed from the backups bucket under the retention rules (the_backups_are_kept_ninety_days_and_friday_copies_a_year.sql). The row itself is kept.';

alter table public.doc_backups add column if not exists prune_attempts integer not null default 0;
-- the status a row had before the retention pass took it, restored exactly if the deletion is cancelled
alter table public.doc_backups add column if not exists status_before_prune text;

create table if not exists public.backup_prune_log (
  id                 bigserial primary key,
  decided_at         timestamptz not null default now(),
  decided_for        date not null,                    -- the Asia/Dubai day of the pass
  mode               text not null check (mode in ('dry_run', 'delete')),
  day                date not null,                    -- the export day decided
  origin             text not null check (origin in ('export', 'legacy')),
  kind               text not null,
  day_status         text,
  reason             text not null,
  objects            integer,
  bytes              bigint,
  dropbox_files      integer,
  objects_removed    integer not null default 0,
  storage_attempts   integer not null default 0,
  storage_error      text,
  storage_deleted_at timestamptz,
  dropbox_done_at    timestamptz,
  cancelled_at       timestamptz
);
create unique index if not exists backup_prune_log_pass_uidx on public.backup_prune_log (decided_for, day, mode);
-- one open deletion per day
create unique index if not exists backup_prune_log_open_uidx on public.backup_prune_log (day)
  where mode = 'delete' and storage_deleted_at is null and cancelled_at is null;
comment on table public.backup_prune_log is
  'Every export day the retention pass decided to delete (or, in dry-run mode, would delete): what, when, why, and what happened. Never pruned. the_backups_are_kept_ninety_days_and_friday_copies_a_year.sql';
alter table public.backup_prune_log enable row level security;
drop policy if exists backup_prune_log_service_role_only on public.backup_prune_log;
create policy backup_prune_log_service_role_only on public.backup_prune_log
  as permissive for all to public using (false) with check (false);
revoke all on public.backup_prune_log from anon, authenticated;

-- ── 2. THE RULES, AS A PURE FUNCTION ───────────────────────────────────────────────────────────────
-- p_days: [{day, origin, kind: full|incremental, status: done|failed|running|incomplete}]
create or replace function public.fn_backup_prune_decide(p_days jsonb, p_today date)
returns table(day date, origin text, kind text, day_status text, decision text, reason text)
language sql stable set search_path to 'public', 'pg_temp' as $fn$
  with d as (
    select (e->>'day')::date as dy, coalesce(e->>'origin', 'export') as og,
           coalesce(e->>'kind', 'full') as kd, coalesce(e->>'status', '') as st
      from jsonb_array_elements(coalesce(p_days, '[]'::jsonb)) e),
  g as (
    select max(d.dy) filter (where d.kd = 'full' and d.st = 'done') as newest_full,
           max(d.dy) filter (where d.kd = 'full') as latest_full_attempt
      from d),
  -- kept for ever: the first complete full copy of each month, or a full-less month's last complete copy
  mf as (
    select date_trunc('month', d.dy)::date as mo,
           min(d.dy) filter (where d.kd = 'full' and d.st = 'done') as first_full,
           max(d.dy) filter (where d.st = 'done') as last_done
      from d group by 1),
  k as (
    select d.dy, d.og, d.kd, d.st,
           (d.st = 'done' and (d.dy = mf.first_full or (mf.first_full is null and d.dy = mf.last_done))) as forever,
           case when g.newest_full is null then 'blocked: no complete full copy exists, so nothing is deleted'
                when g.latest_full_attempt > g.newest_full
                  then 'blocked: the latest full copy (' || g.latest_full_attempt || ') did not complete, so nothing is deleted'
           end as blocked,
           d.dy = g.newest_full as is_newest_full,
           d.dy > g.newest_full as after_newest_full,
           d.st = 'running' as running,
           (p_today - d.dy) <= 90 as within_90,
           (d.kd = 'full' and d.st = 'done' and extract(isodow from d.dy) = 5
            and d.dy > (p_today - interval '12 months')::date) as friday_kept
      from d cross join g left join mf on mf.mo = date_trunc('month', d.dy)::date),
  kp as (
    select k.*, (k.is_newest_full or k.after_newest_full or k.running or k.forever or k.within_90 or k.friday_kept) as policy_keep from k),
  anchor as (
    select kp.dy as inc_day,
           (select max(f.dy) from d f where f.kd = 'full' and f.st = 'done' and f.dy <= kp.dy) as full_day
      from kp where kp.kd = 'incremental' and kp.policy_keep),
  c as (
    select kp.*, exists (select 1 from anchor a where kp.dy between a.full_day and a.inc_day) as in_kept_chain from kp)
  select c.dy, c.og, c.kd, c.st,
         case when c.blocked is not null or c.policy_keep or c.in_kept_chain then 'keep' else 'delete' end,
         case when c.blocked is not null then c.blocked
              when c.is_newest_full then 'the newest complete full copy'
              when c.after_newest_full then 'part of the newest restore chain (the newest full copy and every day after it)'
              when c.running then 'still being written'
              when c.forever and c.kd = 'full' then 'the first complete full copy of its month, kept forever'
              when c.forever then 'the last complete copy of a month with no full copy, kept forever'
              when c.within_90 then 'within 90 days'
              when c.friday_kept then 'a complete Friday full copy within 12 months'
              when c.in_kept_chain then 'needed by a kept kb_chunks restore chain (its full copy, or a day between)'
              when c.kd = 'full' and c.st = 'done' and extract(isodow from c.dy) = 5 then 'a Friday full copy older than 12 months'
              when c.st <> 'done' then 'an incomplete export (' || coalesce(nullif(c.st, ''), 'unknown') || ') older than 90 days'
              else 'a daily copy older than 90 days'
         end
    from c order by c.dy;
$fn$;
revoke execute on function public.fn_backup_prune_decide(jsonb, date) from public, anon, authenticated;

-- ── 2b. THE ALLOW-LIST: only a table-export file can ever be selected ─────────────────────────────
create or replace function public.fn_backup_prune_path_allowed(p_bucket text, p_path text)
returns boolean
language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  -- A table name starts with a letter, and no path segment may start with '_' except the exact
  -- _manifest.json. Final review of #672 (HIGH): '[a-z0-9_]+' let v1's inventory of the backups bucket
  -- itself, <day>/_storage_backups.json, through (the bucket name has no hyphen), so a document inventory
  -- would have been deleted. The same rule is in supabase/functions/_shared/backup_prune_allow.ts.
  select coalesce(p_bucket = 'backups'
         and (p_path ~ '^\d{4}-\d{2}-\d{2}/_manifest\.json$' or p_path !~ '/_')
         and (p_path ~ '^\d{4}-\d{2}-\d{2}/_manifest\.json$'                      -- the day's manifest
           or p_path ~ '^\d{4}-\d{2}-\d{2}/[a-z][a-z0-9_]*/page_\d{4}\.json$'     -- backup v1 (paged) and v2
           or p_path ~ '^\d{4}-\d{2}-\d{2}/[a-z][a-z0-9_]*\.json$'),              -- backup v1 (one file per table)
         false);
$fn$;
revoke execute on function public.fn_backup_prune_path_allowed(text, text) from public, anon, authenticated;

create or replace function public.fn_backup_prune_dropbox_allowed(p_bucket text, p_path text, p_dedupe_key text,
                                                                 p_doc_type text, p_dropbox_path text)
returns boolean
language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(p_doc_type = 'Database export'
                  and p_dedupe_key = 'EXPORT:' || p_path
                  and public.fn_backup_prune_path_allowed(p_bucket, p_path)
                  and p_dropbox_path = '/QuotesDone Backup/Company/Database Exports/' || left(p_path, 7) || '/' || p_path,
                  false);
$fn$;
revoke execute on function public.fn_backup_prune_dropbox_allowed(text, text, text, text, text) from public, anon, authenticated;

-- ── 3. THE DAYS THAT EXIST ─────────────────────────────────────────────────────────────────────────
create or replace function public.fn_backup_prune_days()
returns jsonb
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(jsonb_agg(t.x order by t.x->>'day'), '[]'::jsonb) from (
    select jsonb_build_object('day', r.stamp, 'origin', 'export', 'kind', r.kind, 'status', r.status)
      from public.table_export_run r where r.pruned_at is null
    union all
    select jsonb_build_object('day', lg.dy, 'origin', 'legacy', 'kind', 'full',
                              'status', case when lg.has_manifest then 'done' else 'incomplete' end)
      from (select split_part(o.name, '/', 1)::date as dy,
                   bool_or(o.name = split_part(o.name, '/', 1) || '/_manifest.json') as has_manifest
              from storage.objects o
             where o.bucket_id = 'backups' and o.name ~ '^\d{4}-\d{2}-\d{2}/' and split_part(o.name, '/', 1) <= '2026-09-07'
             group by 1) lg
     where not exists (select 1 from public.table_export_run r where r.stamp = lg.dy)
  ) t(x);
$fn$;
revoke execute on function public.fn_backup_prune_days() from public, anon, authenticated;

create or replace function public.fn_backup_prune_mode()
returns text
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((select 'delete' from public.app_secrets s where s.key = 'backup_prune_mode' and s.value = 'delete'), 'dry_run');
$fn$;
revoke execute on function public.fn_backup_prune_mode() from public, anon, authenticated;

-- ── 4. THE DRY RUN: what would be deleted today, with what it holds ───────────────────────────────
create or replace function public.fn_backup_prune_plan(p_today date default null)
returns table(day date, origin text, kind text, day_status text, decision text, reason text,
              objects bigint, bytes bigint, dropbox_files bigint)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select p.day, p.origin, p.kind, p.day_status, p.decision, p.reason, s.n, s.b,
         (select count(*) from public.doc_backups b
           where b.dedupe_key like 'EXPORT:' || to_char(p.day, 'YYYY-MM-DD') || '/%' and b.status <> 'pruned'
             and public.fn_backup_prune_dropbox_allowed(b.bucket, b.path, b.dedupe_key, b.doc_type, b.dropbox_path))
    from public.fn_backup_prune_decide(public.fn_backup_prune_days(),
                                       coalesce(p_today, (now() at time zone 'Asia/Dubai')::date)) p
    cross join lateral (select count(*) as n, coalesce(sum((o.metadata->>'size')::bigint), 0)::bigint as b
                          from storage.objects o
                         where o.bucket_id = 'backups' and o.name like to_char(p.day, 'YYYY-MM-DD') || '/%'
                           and public.fn_backup_prune_path_allowed(o.bucket_id, o.name)) s;
$fn$;
revoke execute on function public.fn_backup_prune_plan(date) from public, anon, authenticated;

-- ── 4b. A LOGGED DELETION IS RE-DECIDED BEFORE ANY HALF OF IT RUNS, AND CANCELLED WHOLE ───────────
-- Review of #672 (15 Sep 2026): the Dropbox picker never re-ran the rules, and a cancelled day's Dropbox
-- rows stayed claimable, so after a fresh full-copy failure storage kept the day while Dropbox still
-- deleted it. Now ONE routine cancels, and it reverts the day's prune_pending/pruning rows to the status
-- they had before (status_before_prune) in the same statement as the cancel. ONE routine re-decides,
-- and the tick and both pickers call it before they hand over anything.
create or replace function public.fn_backup_prune_cancel(p_log_id bigint, p_why text)
returns integer
language plpgsql volatile security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_reverted integer;
begin
  with cl as (
    update public.backup_prune_log bl
       set cancelled_at = now(),
           storage_error = left('cancelled: the day is no longer due for deletion (' || coalesce(p_why, 'no reason given') || ')', 1000)
     where bl.id = p_log_id and bl.mode = 'delete' and bl.cancelled_at is null
    returning bl.day)
  update public.doc_backups b
     set status = coalesce(b.status_before_prune, 'pending'), status_before_prune = null,
         claimed_at = null, claimed_by = null, error = null
    from cl
   where b.dedupe_key like 'EXPORT:' || to_char(cl.day, 'YYYY-MM-DD') || '/%'
     and b.status in ('prune_pending', 'pruning');
  get diagnostics v_reverted = row_count;
  return v_reverted;
end $fn$;
revoke execute on function public.fn_backup_prune_cancel(bigint, text) from public, anon, authenticated;

-- Every open deletion (either half still to run) is decided again against today's sources. A day whose
-- storage half already ran is no longer listed by fn_backup_prune_days, so it is decided with its
-- logged description added back: if the rules now keep it (the latest full failed since), its Dropbox
-- copy is kept too, and it may be the only copy left.
create or replace function public.fn_backup_prune_recheck()
returns integer
language plpgsql volatile security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_days jsonb := public.fn_backup_prune_days(); v_n integer := 0; x record;
begin
  v_days := v_days || coalesce((
    select jsonb_agg(jsonb_build_object('day', bl.day, 'origin', bl.origin, 'kind', bl.kind, 'status', bl.day_status))
      from public.backup_prune_log bl
     where bl.mode = 'delete' and bl.cancelled_at is null and bl.dropbox_done_at is null
       and not exists (select 1 from jsonb_array_elements(v_days) e where (e->>'day')::date = bl.day)), '[]'::jsonb);
  for x in select bl.id, pd.decision, pd.reason
             from public.backup_prune_log bl
             left join public.fn_backup_prune_decide(v_days, (now() at time zone 'Asia/Dubai')::date) pd on pd.day = bl.day
            where bl.mode = 'delete' and bl.cancelled_at is null
              and (bl.storage_deleted_at is null or bl.dropbox_done_at is null)
              and pd.decision is distinct from 'delete' loop
    perform public.fn_backup_prune_cancel(x.id, coalesce(x.reason, 'the day is no longer listed'));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $fn$;
revoke execute on function public.fn_backup_prune_recheck() from public, anon, authenticated;

-- ── 5. THE TICK (resilience_ping, every 15 minutes) ────────────────────────────────────────────────
create or replace function public.fn_backup_prune_tick()
returns jsonb
language plpgsql volatile security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_mode text := public.fn_backup_prune_mode();
  v_export public.table_export_run;
  v_pass jsonb := null; v_logged int := 0; v_items jsonb := '[]'::jsonb; v_settle jsonb; x record;
begin
  -- A PASS: once per Dubai day, after that day's export finished.
  select * into v_export from public.table_export_run r where r.stamp = v_today;
  if found and (v_export.status = 'done' or (v_export.status = 'failed' and v_export.attempts >= 6))
     and not exists (select 1 from public.agent_runs ar
                      where ar.agent = 'it_engineer' and ar.counts->>'job' = 'backup_prune'
                        and (ar.started_at at time zone 'Asia/Dubai')::date = v_today) then
    insert into public.backup_prune_log (decided_for, mode, day, origin, kind, day_status, reason, objects, bytes, dropbox_files)
    select v_today, v_mode, p.day, p.origin, p.kind, p.day_status, p.reason, p.objects, p.bytes, p.dropbox_files
      from public.fn_backup_prune_plan(v_today) p
     where p.decision = 'delete'
       and not exists (select 1 from public.backup_prune_log l
                        where l.day = p.day and l.mode = 'delete' and l.storage_deleted_at is null and l.cancelled_at is null)
    on conflict do nothing;
    get diagnostics v_logged = row_count;
    v_pass := jsonb_build_object('days', v_logged);
    insert into public.agent_runs (agent, status, counts, note, started_at, finished_at)
    values ('it_engineer', 'ok', jsonb_build_object('job', 'backup_prune', 'mode', v_mode, 'days', v_logged),
            left(case when v_mode = 'delete' then 'Backup retention: ' || v_logged || ' export day(s) logged for deletion.'
                      else 'Backup retention DRY RUN: ' || v_logged || ' export day(s) would be deleted; nothing was touched.' end, 500),
            now(), now());
  end if;

  if v_mode = 'delete' then
    perform public.fn_backup_prune_recheck();
    -- the day's Dropbox copies leave the upload queue and join the delete queue; the status they had is kept
    update public.doc_backups b set status = 'prune_pending', status_before_prune = b.status, claimed_at = null, claimed_by = null
      from public.backup_prune_log l
     where l.mode = 'delete' and l.cancelled_at is null and l.dropbox_done_at is null
       and b.dedupe_key like 'EXPORT:' || to_char(l.day, 'YYYY-MM-DD') || '/%'
       and b.status not in ('pruned', 'prune_pending', 'pruning', 'processing')
       and public.fn_backup_prune_dropbox_allowed(b.bucket, b.path, b.dedupe_key, b.doc_type, b.dropbox_path);
    update public.doc_backups b set status = 'pruned', error = null
     where b.status = 'prune_pending' and b.dropbox_path is null;
    update public.backup_prune_log l set dropbox_done_at = now()
     where l.mode = 'delete' and l.cancelled_at is null and l.dropbox_done_at is null
       and not exists (select 1 from public.doc_backups b
                        where b.dedupe_key like 'EXPORT:' || to_char(l.day, 'YYYY-MM-DD') || '/%' and b.status <> 'pruned');
  end if;

  -- A prune failure is an it_engineer finding; the same settle closes it once the deletion completes.
  for x in select l.* from public.backup_prune_log l
            where l.mode = 'delete' and l.storage_deleted_at is null and l.cancelled_at is null
              and (l.storage_attempts >= 3 or l.decided_at < now() - interval '2 days') loop
    v_items := v_items || jsonb_build_object('item', 'storage:' || x.day, 'owner_seat', 'it_engineer', 'subject', 'backups',
      'title', 'Backup retention could not remove the ' || x.day || ' export from the backups bucket',
      'blast', 'agent_facing', 'affected', 1,
      'evidence', jsonb_build_object('backup_prune_log_id', x.id, 'attempts', x.storage_attempts, 'error', x.storage_error,
                                     'objects_removed', x.objects_removed, 'logged_at', x.decided_at));
  end loop;
  for x in select split_part(substr(b.dedupe_key, 8), '/', 1) as dy, count(*) as n, max(b.error) as err
             from public.doc_backups b
            where b.status in ('prune_pending', 'pruning') and b.prune_attempts >= 5
            group by 1 loop
    v_items := v_items || jsonb_build_object('item', 'dropbox:' || x.dy, 'owner_seat', 'it_engineer', 'subject', 'dropbox',
      'title', 'Backup retention could not remove ' || x.n || ' Dropbox copy(ies) of the ' || x.dy || ' export',
      'blast', 'agent_facing', 'affected', x.n, 'evidence', jsonb_build_object('last_error', x.err));
  end loop;
  v_settle := public.fn_it_duty_settle('backup_prune', v_items);

  return jsonb_build_object('mode', v_mode, 'pass', v_pass,
    'storage_pending', case when v_mode = 'delete' then (select count(*) from public.backup_prune_log l
                          where l.mode = 'delete' and l.storage_deleted_at is null and l.cancelled_at is null) else 0 end,
    'dropbox_pending', case when v_mode = 'delete' then (select count(*) from public.doc_backups b
                          where b.status = 'prune_pending' and b.prune_attempts < 5) else 0 end,
    'findings', v_settle->'failing');
end $fn$;
revoke execute on function public.fn_backup_prune_tick() from public, anon, authenticated;

-- ── 6. STORAGE: the worker (supabase/functions/backup op 'prune') ─────────────────────────────────
-- The day is RE-DECIDED here, against today's sources, before a single name is handed over.
create or replace function public.fn_backup_prune_storage_next()
returns jsonb
language plpgsql volatile security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_log public.backup_prune_log; v_cancelled integer; v_names text[];
begin
  if public.fn_backup_prune_mode() <> 'delete' then return jsonb_build_object('log_id', null, 'reason', 'dry run'); end if;
  v_cancelled := public.fn_backup_prune_recheck();
  select * into v_log from public.backup_prune_log l
   where l.mode = 'delete' and l.storage_deleted_at is null and l.cancelled_at is null and l.storage_attempts < 3
   order by l.day limit 1 for update skip locked;
  if not found then return jsonb_build_object('log_id', null, 'cancelled', v_cancelled); end if;
  select coalesce(array_agg(o.name order by o.name), '{}') into v_names
    from (select o2.name from storage.objects o2
           where o2.bucket_id = 'backups' and o2.name like to_char(v_log.day, 'YYYY-MM-DD') || '/%'
             and public.fn_backup_prune_path_allowed(o2.bucket_id, o2.name)
           order by o2.name limit 1000) o;
  return jsonb_build_object('log_id', v_log.id, 'day', v_log.day, 'names', to_jsonb(v_names));
end $fn$;
revoke execute on function public.fn_backup_prune_storage_next() from public, anon, authenticated;

create or replace function public.fn_backup_prune_storage_done(p_log_id bigint, p_removed integer, p_error text default null)
returns jsonb
language plpgsql volatile security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_log public.backup_prune_log; v_left bigint;
begin
  select * into v_log from public.backup_prune_log l where l.id = p_log_id and l.mode = 'delete';
  if not found then raise exception 'fn_backup_prune_storage_done: no delete-mode log row %', p_log_id; end if;
  update public.backup_prune_log l set objects_removed = l.objects_removed + greatest(coalesce(p_removed, 0), 0) where l.id = p_log_id;
  if p_error is not null then
    update public.backup_prune_log l set storage_attempts = l.storage_attempts + 1, storage_error = left(p_error, 1000) where l.id = p_log_id;
    return jsonb_build_object('ok', false, 'day', v_log.day, 'error', left(p_error, 300));
  end if;
  select count(*) into v_left from storage.objects o
   where o.bucket_id = 'backups' and o.name like to_char(v_log.day, 'YYYY-MM-DD') || '/%'
     and public.fn_backup_prune_path_allowed(o.bucket_id, o.name);   -- the inventories that stay are not "left"
  if v_left = 0 then
    update public.backup_prune_log l set storage_deleted_at = now(), storage_error = null where l.id = p_log_id;
    update public.table_export_run r set pruned_at = now() where r.stamp = v_log.day;
  end if;
  return jsonb_build_object('ok', true, 'day', v_log.day, 'left', v_left);
end $fn$;
revoke execute on function public.fn_backup_prune_storage_done(bigint, integer, text) from public, anon, authenticated;

-- ── 7. DROPBOX: the same conveyor (supabase/functions/dropbox_backup op 'prune') ──────────────────
create or replace function public.fn_doc_backups_prune_next(p_limit integer default 25, p_run text default null)
returns setof public.doc_backups
language plpgsql volatile security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if coalesce(btrim(p_run), '') = '' then raise exception 'fn_doc_backups_prune_next: p_run (the claiming run id) is required'; end if;
  if public.fn_backup_prune_mode() <> 'delete' then return; end if;
  -- the rules again, before a single Dropbox path is handed over; a cancelled day's rows revert here
  perform public.fn_backup_prune_recheck();
  update public.doc_backups d set status = 'prune_pending', claimed_at = null, claimed_by = null
   where d.status = 'pruning' and d.claimed_at < now() - interval '10 minutes';
  return query
    with c as (
      select d.id from public.doc_backups d
       where d.status = 'prune_pending' and d.prune_attempts < 5
         and public.fn_backup_prune_dropbox_allowed(d.bucket, d.path, d.dedupe_key, d.doc_type, d.dropbox_path)
         and exists (select 1 from public.backup_prune_log bl
                      where bl.mode = 'delete' and bl.cancelled_at is null
                        and d.dedupe_key like 'EXPORT:' || to_char(bl.day, 'YYYY-MM-DD') || '/%')
         and (d.last_attempt_at is null or d.prune_attempts = 0
              or d.last_attempt_at < now() - interval '1 minute' * power(2, least(d.prune_attempts, 8)))
       order by d.id limit greatest(1, least(coalesce(p_limit, 25), 25))
       for update skip locked)
    update public.doc_backups d set status = 'pruning', claimed_at = now(), claimed_by = p_run
      from c where d.id = c.id
    returning d.*;
end $fn$;
revoke execute on function public.fn_doc_backups_prune_next(integer, text) from public, anon, authenticated;

-- p_results: [{id, ok, error}]. error 'deadline' is a row the run had no time for, not a failure.
create or replace function public.fn_doc_backups_prune_done(p_results jsonb)
returns jsonb
language plpgsql volatile security definer set search_path to 'public', 'pg_temp' as $fn$
declare r jsonb; n_ok int := 0; n_fail int := 0;
begin
  for r in select * from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    if (r->>'ok')::boolean then
      update public.doc_backups d set status = 'pruned', status_before_prune = null, claimed_at = null, claimed_by = null,
             error = null, last_attempt_at = now()
       where d.id = (r->>'id')::bigint and d.status = 'pruning';
      if not found then
        -- the day was cancelled while this delete was in flight: the Dropbox copy is gone but the rules keep
        -- it, so the row goes back to the upload queue and says why (the uploader re-files it from storage)
        update public.doc_backups d set status = 'pending', status_before_prune = null, backed_up_at = null, verified_at = null,
               dropbox_content_hash = null, dropbox_size = null,
               error = 'deleted from Dropbox after its retention deletion was cancelled; re-filed'
         where d.id = (r->>'id')::bigint and d.status not in ('pruned', 'prune_pending', 'pruning');
      end if;
      n_ok := n_ok + 1;
    else
      update public.doc_backups d set status = 'prune_pending', claimed_at = null, claimed_by = null,
             prune_attempts = d.prune_attempts + case when r->>'error' = 'deadline' then 0 else 1 end,
             error = left('prune: ' || coalesce(r->>'error', 'unknown'), 300), last_attempt_at = now()
       where d.id = (r->>'id')::bigint and d.status = 'pruning';
      n_fail := n_fail + 1;
    end if;
  end loop;
  update public.backup_prune_log l set dropbox_done_at = now()
   where l.mode = 'delete' and l.cancelled_at is null and l.dropbox_done_at is null
     and not exists (select 1 from public.doc_backups b
                      where b.dedupe_key like 'EXPORT:' || to_char(l.day, 'YYYY-MM-DD') || '/%' and b.status <> 'pruned');
  return jsonb_build_object('deleted', n_ok, 'failed', n_fail);
end $fn$;
revoke execute on function public.fn_doc_backups_prune_done(jsonb) from public, anon, authenticated;

-- ── 8. PROBE: the rules on invented ZZ DEMO days. Pure: it reads and writes nothing real. ─────────
-- This file defines things, so the probe ends in a notice, never an exception.
do $probe$
declare
  v_today date := date '2027-09-16';     -- invented; chosen so v_today - 90 is a Friday
  v_days jsonb; v_del int; v_dec text; v_why text;
begin
  assert extract(isodow from v_today - 90) = 5, 'probe setup: v_today - 90 must be a Friday';

  -- A: a normal year. Complete full copies on Fridays, complete incrementals on the other days.
  select jsonb_agg(jsonb_build_object('day', g::date, 'origin', 'ZZ DEMO', 'status', 'done',
                   'kind', case when extract(isodow from g) = 5 then 'full' else 'incremental' end))
    into v_days from generate_series(v_today - 420, v_today, interval '1 day') g;

  select p.decision, p.reason into v_dec, v_why from public.fn_backup_prune_decide(v_days, v_today) p where p.day = v_today - 6;
  assert v_dec = 'keep' and v_why = 'the newest complete full copy', 'A: the newest full copy was not kept: ' || v_why;
  select p.decision into v_dec from public.fn_backup_prune_decide(v_days, v_today) p where p.day = v_today - 89;
  assert v_dec = 'keep', 'A: an 89-day daily copy was not kept';
  select p.decision, p.reason into v_dec, v_why from public.fn_backup_prune_decide(v_days, v_today) p where p.day = v_today - 91;
  assert v_dec = 'delete' and v_why = 'a daily copy older than 90 days', 'A: a 91-day daily copy was not deleted: ' || v_why;
  select p.decision, p.reason into v_dec, v_why from public.fn_backup_prune_decide(v_days, v_today) p where p.day = v_today - 90 - 7 * 35;
  assert extract(isodow from v_today - 90 - 7 * 35) = 5 and v_dec = 'keep' and v_why = 'a complete Friday full copy within 12 months',
    'A: an 11-month Friday full copy was not kept: ' || v_why;
  select p.decision, p.reason into v_dec, v_why from public.fn_backup_prune_decide(v_days, v_today) p where p.day = v_today - 90 - 7 * 43;
  assert v_dec = 'delete' and v_why = 'a Friday full copy older than 12 months', 'A: a 13-month Friday full copy was not deleted: ' || v_why;
  -- the FIRST Friday full of that same month (2026-08-07, 13 months old) is kept for ever
  select p.decision, p.reason into v_dec, v_why from public.fn_backup_prune_decide(v_days, v_today) p where p.day = v_today - 90 - 7 * 45;
  assert extract(day from v_today - 90 - 7 * 45) <= 7 and v_dec = 'keep' and v_why = 'the first complete full copy of its month, kept forever',
    'A: the first full copy of a 13-month-old month was not kept forever: ' || v_why;
  select count(*) into v_del from public.fn_backup_prune_decide(v_days, v_today) p
   where p.decision = 'delete' and (v_today - p.day) <= 90;
  assert v_del = 0, 'A: a day 90 days old or newer was deleted';

  -- B: the latest full copy FAILED: nothing at all is deleted.
  v_days := v_days || jsonb_build_array(jsonb_build_object('day', v_today + 1, 'origin', 'ZZ DEMO', 'kind', 'full', 'status', 'failed'));
  select count(*) into v_del from public.fn_backup_prune_decide(v_days, v_today + 1) p where p.decision = 'delete';
  assert v_del = 0, 'B: a day was deleted while the latest full copy had failed';

  -- C: no complete full copy exists: nothing is deleted.
  select jsonb_agg(jsonb_build_object('day', g::date, 'origin', 'ZZ DEMO', 'kind', 'incremental', 'status', 'done'))
    into v_days from generate_series(v_today - 200, v_today, interval '1 day') g;
  select count(*) into v_del from public.fn_backup_prune_decide(v_days, v_today) p where p.decision = 'delete';
  assert v_del = 0, 'C: a day was deleted with no complete full copy';

  -- D: the newest full copy is kept however old it is (400 days, a Monday); the month's first full is
  --    kept for ever; a full that is neither, past 90 days and not a Friday, goes.
  v_days := jsonb_build_array(jsonb_build_object('day', date '2026-08-10', 'origin', 'ZZ DEMO', 'kind', 'full', 'status', 'done'),
                              jsonb_build_object('day', date '2026-08-09', 'origin', 'ZZ DEMO', 'kind', 'full', 'status', 'done'),
                              jsonb_build_object('day', date '2026-08-03', 'origin', 'ZZ DEMO', 'kind', 'full', 'status', 'done'));
  select p.decision into v_dec from public.fn_backup_prune_decide(v_days, date '2027-09-14') p where p.day = date '2026-08-10';
  assert v_dec = 'keep', 'D: the newest full copy was deleted';
  select p.decision, p.reason into v_dec, v_why from public.fn_backup_prune_decide(v_days, date '2027-09-14') p where p.day = date '2026-08-03';
  assert v_dec = 'keep' and v_why like '%kept forever', 'D: the month''s first full copy was not kept forever: ' || v_why;
  select p.decision into v_dec from public.fn_backup_prune_decide(v_days, date '2027-09-14') p where p.day = date '2026-08-09';
  assert v_dec = 'delete', 'D: an older non-Friday full copy past 90 days was kept';

  -- E: a kept incremental keeps its chain: a non-Friday fallback full at 95 days and the days to 90.
  select jsonb_agg(jsonb_build_object('day', g::date, 'origin', 'ZZ DEMO', 'status', 'done',
                   'kind', case when g::date = v_today - 95 or g::date = v_today - 2 then 'full' else 'incremental' end))
    into v_days from generate_series(v_today - 95, v_today, interval '1 day') g;
  -- two May days with no full copy that month: the later one is May's copy kept for ever, the earlier goes
  v_days := v_days || jsonb_build_array(jsonb_build_object('day', v_today - 120, 'origin', 'ZZ DEMO', 'kind', 'incremental', 'status', 'done'),
                                        jsonb_build_object('day', v_today - 110, 'origin', 'ZZ DEMO', 'kind', 'incremental', 'status', 'done'));
  select p.decision, p.reason into v_dec, v_why from public.fn_backup_prune_decide(v_days, v_today) p where p.day = v_today - 110;
  assert v_dec = 'keep' and v_why = 'the last complete copy of a month with no full copy, kept forever',
    'E: a full-less month''s last complete copy was not kept forever: ' || v_why;
  select p.decision into v_dec from public.fn_backup_prune_decide(v_days, v_today) p where p.day = v_today - 95;
  assert v_dec = 'keep', 'E: the full copy a kept incremental needs was deleted';
  select p.decision, p.reason into v_dec, v_why from public.fn_backup_prune_decide(v_days, v_today) p where p.day = v_today - 93;
  assert v_dec = 'keep' and v_why like 'needed by a kept kb_chunks restore chain%', 'E: a chain day was deleted: ' || v_why;
  select p.decision into v_dec from public.fn_backup_prune_decide(v_days, v_today) p where p.day = v_today - 120;
  assert v_dec = 'delete', 'E: an orphan 120-day incremental was kept';

  -- F: the allow-list. Export files only; every document shape is refused.
  assert public.fn_backup_prune_path_allowed('backups', '2026-06-23/customers.json')
     and public.fn_backup_prune_path_allowed('backups', '2026-09-20/leads/page_0000.json')
     and public.fn_backup_prune_path_allowed('backups', '2026-09-20/_manifest.json'), 'F: an export file was refused';
  assert not public.fn_backup_prune_path_allowed('supplier-docs', '2026-09-20/leads/page_0000.json')
     and not public.fn_backup_prune_path_allowed('signed-terms', '123/terms.pdf')
     and not public.fn_backup_prune_path_allowed('backups', 'conversations/2026-09/x.pdf')
     and not public.fn_backup_prune_path_allowed('backups', 'accountant/year-end/2026/pack.pdf')
     and not public.fn_backup_prune_path_allowed('backups', '2026-06-23/_storage_supplier-docs.json')
     and not public.fn_backup_prune_path_allowed('backups', '2026-06-23/_storage_backups.json')
     and not public.fn_backup_prune_path_allowed('backups', '2026-06-23/_anything.json')
     and not public.fn_backup_prune_path_allowed('backups', '2026-06-23/_storage/page_0000.json')
     and not public.fn_backup_prune_path_allowed('backups', '2026-06-23/9leads.json')
     -- regression cases from the final review of #672 (LOW): case, trailing slash, Unicode lookalikes
     and not public.fn_backup_prune_path_allowed('backups', '2026-09-20/_MANIFEST.json')
     and not public.fn_backup_prune_path_allowed('backups', '2026-09-20/leads/')
     and not public.fn_backup_prune_path_allowed('backups', '2026-09-20/_manifest.json/')
     and not public.fn_backup_prune_path_allowed('backups', '2026-09-20/leads.json/')
     and not public.fn_backup_prune_path_allowed('backups', '2026-09-20/l' || chr(1077) || 'ads.json')
     and not public.fn_backup_prune_path_allowed('backups', '2026-09-20/' || chr(1072) || 'ccounts/page_0000.json')
     and not public.fn_backup_prune_path_allowed('backups', '2026-06-23/../supplier-docs/licence.pdf')
     and not public.fn_backup_prune_path_allowed(null, null), 'F: a document shape was allowed';
  -- and on production's own files, read-only: no stored document and no document backup row qualifies
  assert not exists (select 1 from storage.objects o
                      where public.fn_backup_prune_path_allowed(o.bucket_id, o.name)
                        and not (o.bucket_id = 'backups' and o.name ~ '^\d{4}-\d{2}-\d{2}/')), 'F: a stored document is on the allow-list';
  assert not exists (select 1 from public.doc_backups b
                      where coalesce(b.doc_type, '') <> 'Database export'
                        and public.fn_backup_prune_dropbox_allowed(b.bucket, b.path, b.dedupe_key, b.doc_type, b.dropbox_path)),
    'F: a document backup row is on the allow-list';

  raise notice 'backup retention: the rules hold on invented days (newest full kept, 89 kept, 91 deleted, 11-month Friday kept, 13-month deleted, each month''s first full and a full-less month''s last copy kept forever, failed latest full and no full delete nothing, a kept chain keeps its full, documents refused); mode now %',
    public.fn_backup_prune_mode();
end $probe$;
