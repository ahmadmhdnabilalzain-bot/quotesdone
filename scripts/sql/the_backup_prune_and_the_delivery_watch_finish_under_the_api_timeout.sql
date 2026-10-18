-- the_backup_prune_and_the_delivery_watch_finish_under_the_api_timeout.sql   (it_engineer, 19 Oct 2026)
--
-- Two routines called by resilience_ping over PostgREST (authenticator statement_timeout = 8 s) ran past it.
--
-- 1. BACKUP PRUNE. fn_backup_prune_plan measured 6,362 ms and fn_backup_prune_tick over 8 s. Two causes:
--    a. doc_backups was matched to an export day with a LIKE on a concatenated pattern, which no index can
--       serve: a seq scan of every doc_backups row per day (2,990 ms). Every EXPORT key has the shape
--       'EXPORT:YYYY-MM-DD/...' (measured 19 Oct: 0 of 28,096 break it), so the first 18 characters ARE the
--       day; an expression index on left(dedupe_key, 18) answers it by equality.
--    b. the storage.objects lateral filtered by bucket only, then LIKE on name (2,500 ms). storage.objects.name
--       has the default collation, its (bucket_id, name COLLATE "C") index does not, so the day becomes a
--       COLLATE "C" range ['YYYY-MM-DD/', 'YYYY-MM-DD0') -- '0' is the byte after '/' -- and the LIKE stays
--       as the exact filter.
--    Bodies are the MANIFEST-last ones (plan, cancel: the_backups_are_kept_ninety_days_and_friday_copies_a_year;
--    tick, storage_next: every_old_export_reaches_dropbox_and_no_export_is_pruned_without_a_verified_copy) with
--    only those matches changed.
-- 2. DELIVERY WATCH. resilience_ping's `ladder` step timed out: fn_customer_support_delivery_watch(null) walked
--    every done/failed delivery.request handoff with no result (~409) in one call. It now takes 50 per call
--    (the oldest first) and exactly the one asked for when given an id. Every call before this one timed out and
--    rolled back whole, so nothing ever closed; 391 of the 409 (19 Oct) have no notification and close on first
--    sight. ponytail: oldest-first can starve if >50 rows wait at once; a waiting row resolves within 24 h, add
--    a rotation (last-checked stamp) if the waiting backlog is ever measured above 50.
--    Body: the MANIFEST-last one (every_whatsapp_says_whether_it_arrived.sql) with that LIMIT only.
--
-- Prevented by: scripts/checks/backup_prune_and_delivery_watch_stay_under_the_api_timeout.test.mjs

create index if not exists ix_doc_backups_export_day on public.doc_backups (left(dedupe_key, 18));

create or replace function public.fn_backup_prune_plan(p_today date default null)
returns table(day date, origin text, kind text, day_status text, decision text, reason text,
              objects bigint, bytes bigint, dropbox_files bigint)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select p.day, p.origin, p.kind, p.day_status, p.decision, p.reason, s.n, s.b,
         (select count(*) from public.doc_backups b
           where left(b.dedupe_key, 18) = 'EXPORT:' || to_char(p.day, 'YYYY-MM-DD') || '/' and b.status <> 'pruned'
             and public.fn_backup_prune_dropbox_allowed(b.bucket, b.path, b.dedupe_key, b.doc_type, b.dropbox_path))
    from public.fn_backup_prune_decide(public.fn_backup_prune_days(),
                                       coalesce(p_today, (now() at time zone 'Asia/Dubai')::date)) p
    cross join lateral (select count(*) as n, coalesce(sum((o.metadata->>'size')::bigint), 0)::bigint as b
                          from storage.objects o
                         where o.bucket_id = 'backups'
                           and o.name collate "C" >= to_char(p.day, 'YYYY-MM-DD') || '/' and o.name collate "C" < to_char(p.day, 'YYYY-MM-DD') || '0'
                           and o.name like to_char(p.day, 'YYYY-MM-DD') || '/%'
                           and public.fn_backup_prune_path_allowed(o.bucket_id, o.name)) s;
$fn$;
revoke execute on function public.fn_backup_prune_plan(date) from public, anon, authenticated;

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
   where left(b.dedupe_key, 18) = 'EXPORT:' || to_char(cl.day, 'YYYY-MM-DD') || '/'
     and b.status in ('prune_pending', 'pruning');
  get diagnostics v_reverted = row_count;
  return v_reverted;
end $fn$;
revoke execute on function public.fn_backup_prune_cancel(bigint, text) from public, anon, authenticated;

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
    -- the day's Dropbox copies leave the upload queue and join the delete queue; the status they had is kept.
    -- 15 Sep 2026 (the guard): only AFTER the day's storage deletion finished -- which itself happens only
    -- under verified copies -- and only a copy that was uploaded and verified. Before, every row of the day
    -- moved at once, uploaded or not, so a never-uploaded file was "deleted" from Dropbox (a missing path
    -- is success), marked pruned, and never uploaded while storage still held the only copy.
    update public.doc_backups b set status = 'prune_pending', status_before_prune = b.status, claimed_at = null, claimed_by = null
      from public.backup_prune_log l
     where l.mode = 'delete' and l.cancelled_at is null and l.dropbox_done_at is null
       and l.storage_deleted_at is not null
       and left(b.dedupe_key, 18) = 'EXPORT:' || to_char(l.day, 'YYYY-MM-DD') || '/'
       and b.status = 'done' and b.verified_at is not null
       and public.fn_backup_prune_dropbox_allowed(b.bucket, b.path, b.dedupe_key, b.doc_type, b.dropbox_path);
    update public.doc_backups b set status = 'pruned', error = null
     where b.status = 'prune_pending' and b.dropbox_path is null;
    update public.backup_prune_log l set dropbox_done_at = now()
     where l.mode = 'delete' and l.cancelled_at is null and l.dropbox_done_at is null
       and not exists (select 1 from public.doc_backups b
                        where left(b.dedupe_key, 18) = 'EXPORT:' || to_char(l.day, 'YYYY-MM-DD') || '/' and b.status <> 'pruned');
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
           where o2.bucket_id = 'backups'
             and o2.name collate "C" >= to_char(v_log.day, 'YYYY-MM-DD') || '/' and o2.name collate "C" < to_char(v_log.day, 'YYYY-MM-DD') || '0'
             and o2.name like to_char(v_log.day, 'YYYY-MM-DD') || '/%'
             and public.fn_backup_prune_path_allowed(o2.bucket_id, o2.name)
             -- 15 Sep 2026 (the guard): only a file whose Dropbox copy was uploaded AND verified. A file
             -- without one stays, and fn_backup_prune_storage_done counts it as left, so the day is never
             -- marked deleted and its Dropbox half never starts.
             and exists (select 1 from public.doc_backups d
                          where d.bucket = o2.bucket_id and d.path = o2.name
                            and d.status = 'done' and d.verified_at is not null)
           order by o2.name limit 1000) o;
  return jsonb_build_object('log_id', v_log.id, 'day', v_log.day, 'names', to_jsonb(v_names));
end $fn$;
revoke execute on function public.fn_backup_prune_storage_next() from public, anon, authenticated;

create or replace function public.fn_customer_support_delivery_watch(p_request_id bigint default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  q record; n public.notifications; tx public.transactions; sup record; v_since timestamptz;
  v_reply jsonb; v_result text; v_evidence jsonb; v_retries int; v_nid bigint; v_done int := 0; v_waiting int := 0; v_retried int := 0;
  v_overdue int := 0; v_rep jsonb; v_failed int := 0;
begin
  for q in
    select a.* from public.agent_actions a
     where a.kind = 'handoff' and a.agent = 'customer_support' and a.status in ('done', 'failed')
       and a.detail->>'type' = 'delivery.request'
       and (a.detail->>'result_handoff_id') is null
       and (p_request_id is null or a.id = p_request_id)
     order by a.id
     limit case when p_request_id is null then 50 else 1 end
  loop
    v_nid := coalesce((q.detail->>'retry_notification_id')::bigint, (q.evidence->>'notification_id')::bigint);
    n := null;
    select * into n from public.notifications where id = v_nid;

    -- NOT TERMINAL IN TIME IS A FINDING, whatever else is true of the request.
    if n.id is not null and n.status in ('pending', 'queued') and n.created_at < now() - interval '24 hours'
       and (q.detail->>'overdue_report_id') is null then
      v_rep := public.fn_support_report_to_ceo(
        'delivery_overdue:' || q.id, 'elevated',
        'A ' || coalesce(q.detail->>'msg_type', 'notice') || ' for the ' || coalesce(n.to_role, 'recipient') || ' has not left the outbox in 24 hours',
        jsonb_build_object('request_id', q.id, 'asked_by', q.detail->>'from', 'notification_id', n.id, 'status', n.status,
                           'queued_at', n.created_at, 'attempts', n.attempts, 'last_error', n.last_error),
        jsonb_build_array('queued by customer_support', 'watched every heartbeat since'),
        'Find why the outbox is not draining this row (dispatcher down, sending disabled, cap) and get it out, or tell the asking seat it will not go.',
        'agent_actions#' || q.id);
      update public.agent_actions set detail = detail || jsonb_build_object('overdue_report_id', v_rep->'report_id') where id = q.id;
      v_overdue := v_overdue + 1;
    end if;

    if q.status = 'done' and (q.detail->>'watch_until') is not null then
      -- ── the watched path, carried over unchanged ──
      select * into tx from public.transactions where id = (q.detail->>'transaction_id')::uuid;
      select l.id, lower(coalesce(l.claimed_by, l.email)) as email,
             regexp_replace(coalesce(nullif(btrim(l.whatsapp), ''), l.phone_e164, l.phone, ''), '[^0-9]', '', 'g') as phone
        into sup from public.leads l where l.id = (q.detail->>'supplier_id')::bigint;
      v_since := coalesce(tx.revealed_at, q.created_at);
      v_retries := coalesce((q.detail->>'retries')::int, 0);

      -- ANY CHANNEL, EVERY TIME. The first thing that came back wins.
      select jsonb_build_object('channel', ch, 'at', at, 'ref', ref) into v_reply from (
        select 'portal' ch, m.created_at at, 'messages#' || m.id ref from public.messages m
         where tx.id is not null and m.inquiry_id = tx.inquiry_id and m.supplier_id = tx.supplier_id
           and m.sender = 'supplier' and coalesce(m.blocked, false) = false and m.created_at > v_since
        union all
        select 'supplier_ack', tx.supplier_ack_at, 'transactions.supplier_ack_at' where tx.supplier_ack_at > v_since
        union all
        select coalesce(w.response_channel, 'recorded'), w.first_response_at, coalesce(w.response_ref, 'supplier_response_watch#' || w.id)
          from public.supplier_response_watch w where tx.id is not null and w.transaction_id = tx.id and w.first_response_at > v_since
        union all
        select 'email', im.created_at, 'inbound_messages#' || im.id from public.inbound_messages im
         where sup.email is not null and lower(im.from_email) = sup.email and im.created_at > v_since
        union all
        select 'whatsapp', wm.created_at, 'wa_messages#' || wm.id from public.wa_messages wm
         where length(coalesce(sup.phone, '')) >= 8 and regexp_replace(coalesce(wm.wa_from, ''), '[^0-9]', '', 'g') = sup.phone
           and wm.created_at > v_since
        order by 2 limit 1) z;

      if v_reply is not null and q.detail->>'recipient_role' = 'supplier' then
        v_result := 'proof_of_response';
        v_evidence := jsonb_build_object('reply', v_reply);
      elsif n.id is null or n.status in ('failed', 'bounced', 'error') then
        if v_retries < 1 and n.id is not null then
          perform set_config('app.qd_delivery_tracked', 'on', true);   -- the retry is tracked by this request (retry_notification_id)
          insert into public.notifications (type, kind, to_email, cc_emails, to_role, lead_id, inquiry_id, quote_id, channel, subject, body, status, requested_by)
          values (n.type, n.kind, n.to_email, n.cc_emails, n.to_role, n.lead_id, n.inquiry_id, n.quote_id, 'email', n.subject, n.body, 'queued', n.requested_by)
          returning id into v_nid;
          perform set_config('app.qd_delivery_tracked', 'off', true);
          update public.agent_actions
             set detail = detail || jsonb_build_object('retries', v_retries + 1, 'retry_notification_id', v_nid,
                                                       'first_failure', jsonb_build_object('notification_id', n.id, 'status', n.status, 'error', n.last_error))
           where id = q.id;
          perform public.fn_seat_handoff_event(q.id, 'retried');
          v_retried := v_retried + 1;
          continue;
        end if;
        v_result := 'no_response_confirmation';
        v_evidence := jsonb_build_object('delivered', false, 'retries', v_retries,
          'delivery', jsonb_build_object('notification_id', n.id, 'status', n.status, 'error', n.last_error),
          'first_failure', q.detail->'first_failure');
      elsif now() >= (q.detail->>'watch_until')::timestamptz then
        v_result := 'no_response_confirmation';
        v_evidence := jsonb_build_object('delivered', n.status = 'sent' or n.sent_at is not null,
          'delivery', jsonb_build_object('notification_id', n.id, 'status', n.status, 'sent_at', n.sent_at,
                                         'provider_message_id', n.provider_message_id, 'attempts', n.attempts),
          'whatsapp', (select coalesce(jsonb_agg(jsonb_build_object('notification_id', w.id, 'status', w.status, 'sent_at', w.sent_at,
                                                                    'provider_message_id', w.provider_message_id)), '[]'::jsonb)
                         from public.notifications w
                        where w.id in (select (x)::bigint from jsonb_array_elements_text(coalesce(q.evidence->'whatsapp_ids', '[]'::jsonb)) x)),
          'window_closed_at', q.detail->'watch_until',
          'channels_checked', jsonb_build_array('portal', 'supplier_ack', 'recorded_reply', 'email', 'whatsapp'));
      else
        v_waiting := v_waiting + 1;
        continue;
      end if;
    else
      -- ── every other request: one result when the send is terminal ──
      v_evidence := jsonb_build_object('notification', case when n.id is null then null else jsonb_build_object(
                      'id', n.id, 'status', n.status, 'channel', n.channel, 'to_role', n.to_role, 'sent_at', n.sent_at,
                      'provider_message_id', n.provider_message_id, 'attempts', n.attempts, 'last_error', n.last_error,
                      -- what Twilio reported, and its error in plain words (null for email)
                      'provider_status', n.provider_status, 'provider_error_code', n.provider_error_code,
                      'provider_error_explained', public.fn_twilio_error_in_plain_words(n.provider_error_code)) end,
                    'whatsapp', (select coalesce(jsonb_agg(jsonb_build_object('notification_id', w.id, 'status', w.status,
                                                   'provider_message_id', w.provider_message_id, 'provider_status', w.provider_status,
                                                   'provider_error_code', w.provider_error_code)), '[]'::jsonb)
                                   from public.notifications w
                                  where w.id in (select (x)::bigint from jsonb_array_elements_text(coalesce(q.evidence->'whatsapp_ids', '[]'::jsonb)) x)));
      if q.status = 'failed' then
        v_result := 'not_queued';
        v_evidence := v_evidence || jsonb_build_object('error', q.detail->>'error');
      elsif coalesce((q.evidence->>'stubbed')::boolean, false) then
        v_result := 'stubbed';
      elsif n.id is null and q.evidence ? 'notify' then
        v_result := 'routed';
        v_evidence := v_evidence || jsonb_build_object('notify', q.evidence->'notify');
      -- 22 SEP 2026 (it_engineer, UNSOLVED-06) — "NOTHING WAS QUEUED" WAS THREE DIFFERENT THINGS.
      -- MEASURED: support_ceo_report 3075, 3076, 3084 and 3085 each read 'A supplier_invite for the supplier
      -- did not arrive (not_sent)' with reason 'nothing was queued'. Their requests (agent_actions 42578,
      -- 42579, 42595, 42596) each carry evidence.queued = true and evidence.notification_id 36988/36989/
      -- 37002/37003, and NONE of those notification rows exists any more: every one addressed a
      -- zz-demo-supplier-invite-…@example.invalid fixture and the demo hygiene sweep deleted them between
      -- being queued at 19:11-19:15Z and the watch tick at 19:30Z on 21 Sep. So support DID queue the
      -- message; its record was removed afterwards. (The 22 Sep audit read these as invitations held by
      -- app_secrets.supplier_outreach_golive=false. They are not: the hold path
      -- (the_invitations_warm_up_on_measured_health_and_leave_across_the_working_day.sql) writes an
      -- invite_schedule row with status 'pending' and a supplier_invites agent_run, and asks for no
      -- delivery at all — so a held invitation never reaches this watch.)
      -- The three cases now answer differently, and only the first is a fault:
      --   nothing was ever queued and nothing explains it  -> 'not_sent'  (escalates, as before)
      --   the campaign is held by the founder's own switch  -> 'held'     (recorded, never escalated)
      --   the row it queued has since been deleted         -> 'record_removed'
      elsif n.id is null and coalesce(q.detail->>'msg_type', '') like '%invite%'
            and not public.fn_supplier_outreach_golive() then
        v_result := 'held';
        v_evidence := v_evidence || jsonb_build_object('reason',
          'the supplier campaign is held: app_secrets.supplier_outreach_golive is false, so no invitation is sent. This is the founder''s switch, not a delivery failure.');
      elsif n.id is null and coalesce((q.evidence->>'notification_id'), '') <> '' then
        v_result := 'record_removed';
        v_evidence := v_evidence || jsonb_build_object('reason',
          'the notification this request queued (id ' || (q.evidence->>'notification_id')
          || ') no longer exists, so its delivery cannot be read. A queued message whose row was deleted afterwards - the demo hygiene sweep does this to fixture rows - is not a message that was never sent.');
      elsif n.id is null then
        v_result := 'not_sent';
        v_evidence := v_evidence || jsonb_build_object('reason', coalesce(q.evidence->>'reason', 'nothing was queued'));
      elsif n.status = 'sent' and n.channel in ('whatsapp', 'sms') and coalesce(btrim(n.provider_message_id), '') <> '' then
        -- 22 SEP 2026: a Twilio SID proves only that Twilio ACCEPTED the message. Meta or the carrier can
        -- still refuse it, and that arrives later as a status report (wa_status). So a WhatsApp or SMS
        -- waits for delivered/read; a failure has already turned the row 'failed' (below); and a message
        -- with no final report 24 hours on is returned as unconfirmed rather than claimed as delivered.
        if n.provider_status in ('delivered', 'read') then
          v_result := 'delivered';
        elsif n.sent_at < now() - interval '24 hours' then
          v_result := 'sent_unconfirmed';
          v_evidence := v_evidence || jsonb_build_object('reason',
            'Twilio accepted it but reported no delivery within 24 hours: neither its status callback nor the backstop poll gave a final status');
        else
          v_waiting := v_waiting + 1;
          continue;
        end if;
      elsif n.status = 'sent' then
        v_result := case when coalesce(btrim(n.provider_message_id), '') <> '' then 'delivered' else 'sent_unconfirmed' end;
      elsif n.status in ('failed', 'bounced', 'error') then v_result := 'failed';
      elsif n.status in ('held', 'suppressed', 'skipped', 'cancelled') then v_result := n.status;
      elsif n.status = 'digest' then v_result := 'digested';
      else
        v_waiting := v_waiting + 1;
        continue;
      end if;
    end if;

    -- ONE RESULT, TO WHOEVER ASKED. A result the handoff register refuses must not stop the rest of the
    -- queue: it is recorded on the request and in the stream, and counted.
    -- The result is acted on at once, and the asking seat's close writes THIS request row (its loop,
    -- closed_by, the retry). So the handoff is sent first and its id written after, in a statement of
    -- its own: calling fn_seat_handoff inside the UPDATE of the same row failed with "tuple to be updated
    -- was already modified by an operation triggered by the current command" (measured 14 Sep 2026).
    begin
      update public.agent_actions set detail = detail || jsonb_build_object('result', v_result) where id = q.id;
      v_nid := public.fn_seat_handoff('customer_support', q.detail->>'from', 'delivery.result', 'agent_actions', q.id::text,
                 jsonb_build_object('request_id', q.id, 'result', v_result, 'evidence', v_evidence,
                                    'msg_type', q.detail->>'msg_type', 'recipient_role', q.detail->>'recipient_role',
                                    'retry_of', q.detail->'retry_of',
                                    'step', q.detail->>'step', 'refund_id', q.detail->>'refund_id',
                                    'transaction_id', q.detail->>'transaction_id', 'supplier_id', q.detail->>'supplier_id',
                                    'remediation_id', q.detail->>'remediation_id'));
      update public.agent_actions set detail = detail || jsonb_build_object('result_handoff_id', v_nid) where id = q.id;
      v_done := v_done + 1;
    exception when others then
      update public.agent_actions set detail = detail || jsonb_build_object('result_error', left(sqlerrm, 500)) where id = q.id;
      perform public.fn_seat_handoff_event(q.id, 'result_failed');
      v_failed := v_failed + 1;
    end;
  end loop;
  return jsonb_build_object('results_returned', v_done, 'still_watching', v_waiting, 'retried', v_retried,
                            'overdue_raised', v_overdue, 'results_failed', v_failed);
end $fn$;
revoke execute on function public.fn_customer_support_delivery_watch(bigint) from public, anon, authenticated;

-- ── PROBE: read paths only. The plan is timed end to end (it is `stable`, writes nothing); the watch's
-- candidate query is timed with its new LIMIT. Both must finish well inside the 8 s API timeout.
with t0 as materialized (select clock_timestamp() as s),
     plan as materialized (select count(*) as c from t0, public.fn_backup_prune_plan()),
     t1 as materialized (select clock_timestamp() as e from plan),
     watch as materialized (select count(*) as c from t1, (select a.id from public.agent_actions a
                    where a.kind = 'handoff' and a.agent = 'customer_support' and a.status in ('done', 'failed')
                      and a.detail->>'type' = 'delivery.request' and (a.detail->>'result_handoff_id') is null
                    order by a.id limit 50) w),
     t2 as materialized (select clock_timestamp() as e from watch),
     m as (select round(extract(epoch from (t1.e - t0.s)) * 1000) as plan_ms,
                  round(extract(epoch from (t2.e - t1.e)) * 1000) as watch_ms,
                  plan.c as plan_days, watch.c as watch_rows,
                  to_regclass('public.ix_doc_backups_export_day') is not null as idx
             from t0, t1, t2, plan, watch)
select case when not idx then 'PROBE FAILED: ix_doc_backups_export_day missing'
            when plan_ms >= 4000 then 'PROBE FAILED: fn_backup_prune_plan took ' || plan_ms || ' ms'
            when watch_ms >= 1000 then 'PROBE FAILED: the delivery watch candidates took ' || watch_ms || ' ms'
            else 'PROBE OK: plan ' || plan_ms || ' ms (' || plan_days || ' days), watch candidates ' || watch_ms || ' ms (' || watch_rows || ' rows)' end as verdict
  from m;
