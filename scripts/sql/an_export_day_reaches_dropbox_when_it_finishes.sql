-- AN EXPORT DAY REACHES DROPBOX WHEN IT FINISHES, AND A QUEUE THAT STOPS MOVING IS A FINDING IN HOURS.
-- Assigned: it_engineer. 15 Sep 2026.
--
-- MEASURED, 15 Sep 2026 (production htdblwldjkcgjvmqkbeh):
--   * 06:17:37Z the nightly export 2026-09-15 finished and fn_table_export_finish queued 2,840
--     doc_backups rows (EXPORT:2026-09-15/...). Between 06:17 and 06:29 not one moved.
--   * Nothing was broken, and nothing was told. fn_table_export_finish calls fn_enqueue_doc_backups and
--     returns: it kicks no upload. The kickers that exist (fn_backup_kick) are called only by
--     trg_document_landed_kicks_backup and fn_conversation_archived. The only other driver is
--     resilience_ping -> fn_dropbox_backup_due, every 15 minutes (vercel.json). Between 02:00:42Z (the
--     last tick that found work) and 06:17 the queue was empty, so due was false and the ticks were
--     silent - correct. The 2,840 rows then waited for whichever came first: the next tick (06:30) or
--     an unrelated document trigger. A document_landed:customers kick won at 06:29:30Z.
--   * Once kicked it drains: 2,840 -> 2,510 pending by 06:36:02Z (~50 rows/minute with two chains
--     overlapping; one link = 8 files in 16-30 s, ~2.9 s per file, measured in agent_runs and the edge
--     log). A kick carries limit 8 and at most 20 more links (168 rows); after that each 15-minute tick
--     carries limit 25 x 21 links (up to 525 rows), so an export day of ~2,840 files clears in roughly
--     1 to 1.5 hours. That is well inside a day, so no batching: none of the Dropbox API limits is near,
--     upload.ts already retries a 429 with backoff, and every file is still confirmed by
--     files/get_metadata (size and content_hash), so the Dropbox copy stays the verified off-site copy.
--     ponytail: one file per request; if a day ever outgrows the gap between exports, commit them with
--     files/upload_session/finish_batch_v2 instead.
--
-- WHAT THIS FILE CHANGES
--   1. fn_table_export_finish (canonical body from every_business_table_is_exported_every_day_again.sql,
--      unchanged but for the kick): after queuing the day it calls fn_backup_kick('table_export_finished:
--      <day>', 'process_only'), so the upload starts at 06:17, not at the next tick. A kick that fails or
--      is debounced is swallowed with a warning: the 15-minute tick is still the fallback, and a kick
--      must never turn a finished export day into a failed one.
--   2. fn_dropbox_queue_stale(p_hours, p_demo): a row still pending/error (attempts < 5) N hours after it
--      was queued (default 3 - an export day drains in ~1 hour) is an it_engineer finding through
--      fn_it_duty_settle, duty 'dropbox_queue'. It closes itself when the queue moves again.
--      Not a duplicate: fn_backup_coverage already raises backup_coverage at 48 HOURS (and escalates to
--      the CEO). That is the "something is missing from Dropbox" verdict; this is the IT engineer's early
--      "the queue has stopped moving" signal, 45 hours sooner, on the finding ledger rather than as an
--      agent_actions row. p_demo=true reads only zz_demo rows under duty 'dropbox_queue_zz_demo', so the
--      probe can never close or raise a real finding.
--   3. fn_it_backup_tick (canonical body from the_it_engineer_knows_what_should_be_backed_up_and_closes_
--      the_loop.sql) gains one stage, 'queue', guarded like the others.
--
-- PROVED BY scripts/checks/an_export_day_reaches_dropbox_when_it_finishes.probe.sql (ZZ DEMO rows,
-- rolled back; asserts the live finish body kicks after it enqueues).

-- ── 1. THE EXPORT DAY KICKS THE UPLOAD ─────────────────────────────────────────────────────────────
create or replace function public.fn_table_export_finish(p_stamp date, p_manifest jsonb, p_error text default null)
returns jsonb
language plpgsql volatile security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_day text := to_char(p_stamp, 'YYYY-MM-DD');
  v_bad text; v_queued integer; v_pruned integer := 0; v_run public.table_export_run; v_kick jsonb;
begin
  select * into v_run from public.table_export_run r where r.stamp = p_stamp;
  if not found then return jsonb_build_object('ok', false, 'stamp', p_stamp, 'error', 'no table_export_run row for this day'); end if;
  if p_error is null then
    select string_agg(x.table_name, ', ') into v_bad
      from public.fn_table_export_list() x
     where coalesce((p_manifest->'tables'->x.table_name->>'pages')::int, -1)
           <> (select count(*) from storage.objects o
                where o.bucket_id = 'backups' and o.name like v_day || '/' || x.table_name || '/page\_%.json');
    if v_bad is not null then p_error := 'pages in storage disagree with the manifest for: ' || v_bad; end if;
    if p_error is null and not exists (select 1 from storage.objects o where o.bucket_id = 'backups' and o.name = v_day || '/_manifest.json') then
      p_error := 'the manifest is not in storage';
    end if;
  end if;

  if p_error is not null then
    update public.table_export_run r set status = 'failed', error = left(p_error, 2000), heartbeat_at = now()
     where r.stamp = p_stamp;
    return jsonb_build_object('ok', false, 'stamp', p_stamp, 'error', left(p_error, 500));
  end if;

  update public.table_export_run r set status = 'done', finished_at = now(), heartbeat_at = now(), manifest = p_manifest, error = null
   where r.stamp = p_stamp;
  -- a full copy holds every row, so changes logged well before it started are no longer needed
  if v_run.kind = 'full' then
    delete from public.kb_chunks_export_change cl where cl.changed_at < v_run.started_at - interval '1 day';
    get diagnostics v_pruned = row_count;
  end if;
  v_queued := public.fn_enqueue_doc_backups();
  -- start the upload now; the 15-minute tick (fn_dropbox_backup_due) stays the fallback
  if v_queued > 0 then
    begin
      v_kick := public.fn_backup_kick('table_export_finished:' || v_day, 'process_only');
    exception when others then
      v_kick := jsonb_build_object('kicked', false, 'reason', left(sqlerrm, 200));
      raise warning 'fn_table_export_finish: could not kick dropbox_backup: %', sqlerrm;
    end;
  end if;
  return jsonb_build_object('ok', true, 'stamp', p_stamp, 'kind', v_run.kind, 'queued_for_dropbox', v_queued,
                            'change_log_pruned', v_pruned, 'dropbox_kick', v_kick);
end $fn$;

-- ── 2. A QUEUE THAT STOPS MOVING IS A FINDING ──────────────────────────────────────────────────────
create or replace function public.fn_dropbox_queue_stale(p_hours integer default 3, p_demo boolean default false)
returns jsonb
language plpgsql volatile security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_hours integer := greatest(coalesce(p_hours, 3), 1);
  v_duty text := case when coalesce(p_demo, false) then 'dropbox_queue_zz_demo' else 'dropbox_queue' end;
  v_n integer; v_oldest timestamptz; v_ids jsonb; v_items jsonb := '[]'::jsonb;
begin
  select count(*), min(coalesce(d.requeued_at, d.created_at)),
         coalesce(jsonb_agg(d.id order by d.id) filter (where d.rn <= 20), '[]'::jsonb)
    into v_n, v_oldest, v_ids
    from (select b.*, row_number() over (order by b.id) rn from public.doc_backups b
           where b.status in ('pending', 'error') and coalesce(b.attempts, 0) < 5
             and (b.entity = 'zz_demo') = coalesce(p_demo, false)
             and coalesce(b.requeued_at, b.created_at) < now() - make_interval(hours => v_hours)) d;
  if v_n > 0 then
    v_items := jsonb_build_array(jsonb_build_object(
      'item', 'stale_pending',
      'title', left(format('%s Dropbox backup row(s) still queued after %s hours (oldest queued %s)',
                           v_n, v_hours, to_char(v_oldest at time zone 'UTC', 'YYYY-MM-DD HH24:MI "UTC"')), 300),
      'owner_seat', 'it_engineer', 'subject', 'dropbox_backup', 'demo', coalesce(p_demo, false),
      'affected', v_n,
      'evidence', jsonb_build_object('hours', v_hours, 'count', v_n, 'oldest_queued_at', v_oldest, 'first_ids', v_ids,
        'why', 'nothing is draining the doc_backups queue: check resilience_ping backupTick, fn_backup_kick and the dropbox_backup edge log')));
  end if;
  return public.fn_it_duty_settle(v_duty, v_items)
         || jsonb_build_object('stale', v_n, 'hours', v_hours, 'oldest_queued_at', v_oldest);
end $fn$;
revoke execute on function public.fn_dropbox_queue_stale(integer, boolean) from public, anon, authenticated;

-- ── 3. THE IT ENGINEER'S BACKUP TICK RUNS IT ───────────────────────────────────────────────────────
create or replace function public.fn_it_backup_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare o jsonb := '{}'::jsonb;
begin
  begin o := o || jsonb_build_object('recheck', public.fn_it_backup_recheck());
  exception when others then o := o || jsonb_build_object('recheck', public.fn_it_backup_stage_failed('recheck', sqlerrm)); end;
  begin o := o || jsonb_build_object('ceo', public.fn_ceo_backup_escalation_sweep());
  exception when others then o := o || jsonb_build_object('ceo', public.fn_it_backup_stage_failed('ceo', sqlerrm)); end;
  begin o := o || jsonb_build_object('watch', public.fn_backup_watch());
  exception when others then o := o || jsonb_build_object('watch', public.fn_it_backup_stage_failed('watch', sqlerrm)); end;
  begin o := o || jsonb_build_object('queue', public.fn_dropbox_queue_stale());
  exception when others then o := o || jsonb_build_object('queue', public.fn_it_backup_stage_failed('queue', sqlerrm)); end;
  begin o := o || jsonb_build_object('daily', public.fn_dropbox_backup_daily_report());
  exception when others then o := o || jsonb_build_object('daily', public.fn_it_backup_stage_failed('daily', sqlerrm)); end;
  return o || jsonb_build_object('reconcile', public.fn_dropbox_reconcile_due());
end $fn$;
