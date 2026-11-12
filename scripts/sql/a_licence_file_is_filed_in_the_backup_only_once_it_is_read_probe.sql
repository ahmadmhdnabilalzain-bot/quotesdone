-- Assigned: it_engineer
-- PURE PROBE (no DDL) for a_licence_file_is_filed_in_the_backup_only_once_it_is_read.sql. It always ends in raise exception
-- 'CHK<<...>>', so every row it writes rolls back (the enqueue writes doc_backups rows only; nothing is sent to anyone, which the
-- probe counts). Its subject is ONE approved ZZ DEMO supplier at @example.invalid with a licence (the licence probes' convention).
--   unread : a new licence file in its first 15 minutes of 'ours_failed'        -> not queued for the backup
--   16 min : still 'ours_failed' 16 minutes on (the provider down)              -> queued once, as "Trade licence - <file>"
--   read   : the same file once read                                           -> still that one row
do $$
declare v_id bigint; v_path text; v_unread int; v_read int; v_type text; v_notes_before bigint; v_notes_after bigint; fail text := '';
begin
  select id into v_id from public.leads
   where company_name like 'ZZ DEMO%' and email like '%@example.invalid' and claimed_by like '%@example.invalid'
     and approval_status = 'approved' and license_doc_path is not null
   order by id limit 1;
  if v_id is null then raise exception 'CHK<<%>>', jsonb_build_object('verdict', 'PROBE FAILED: no approved ZZ DEMO supplier with a licence to probe'); end if;
  -- A demo row reaches doc_backups only in a tagged sandbox run (trg_doc_backups_admit: the tag in its path, filed under _sandbox/<tag>/),
  -- so the probe is one, for this transaction only, and names its licence file with the tag. Nothing is uploaded: it all rolls back.
  perform set_config('qd.backup_sandbox', 'qdprobe1985', true);
  v_path := 'licenses/' || v_id || '/qdprobe1985_licence.pdf';
  select count(*) into v_notes_before from public.notifications;

  update public.leads set license_doc_path = v_path, licence_read_state = 'ours_failed', licence_read_at = now() where id = v_id;
  perform public.fn_enqueue_doc_backups();
  select count(*) into v_unread from public.doc_backups where path = v_path;
  if v_unread <> 0 then fail := fail || format('unread: queued %s; ', v_unread); end if;

  -- still unread after 15 minutes (the provider down): filed as before, under its name (second review of #1985, W2)
  update public.leads set licence_read_at = now() - interval '16 minutes' where id = v_id;
  perform public.fn_enqueue_doc_backups();
  select count(*), max(doc_type) into v_read, v_type from public.doc_backups where path = v_path;
  if v_read <> 1 or v_type is distinct from 'Trade licence' then fail := fail || format('unread 16 min: queued %s as %s; ', v_read, coalesce(v_type, 'nothing')); end if;
  -- read: still one row (filed once)
  update public.leads set licence_read_state = 'read', licence_read_at = now() where id = v_id;
  perform public.fn_enqueue_doc_backups();
  select count(*) into v_read from public.doc_backups where path = v_path;
  if v_read <> 1 then fail := fail || format('read: %s rows, not 1; ', v_read); end if;

  select count(*) into v_notes_after from public.notifications;
  if v_notes_after <> v_notes_before then fail := fail || format('notifications: %s queued; ', v_notes_after - v_notes_before); end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end,
    'supplier', v_id, 'queued_while_unread', v_unread, 'queued_once_read', v_read, 'filed_as', v_type, 'notifications_queued', v_notes_after - v_notes_before);
end $$;
