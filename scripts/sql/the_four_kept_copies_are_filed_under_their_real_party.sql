-- THE FOUR KEPT COPIES ARE FILED UNDER THEIR REAL PARTY (it_engineer; 19 Nov 2026; ledger 1199, 1214, 1726, 1729).
--
-- THE FOUR: doc_backups 52497, 52501, 53162, 710220. The 17/18 Nov demo purge kept them on purpose, because they sat in the
--   founder's real customer folder "/QuotesDone Backup/Customers/ahmad alzain (0dc8c94f)/Correspondence/" (ledger 1214: "his real account
--   0dc8c94f and its folders stay"). Customer 0dc8c94f is no longer in public.customers (0 rows, 19 Nov), so the folder names a party that
--   does not exist, and shellFolders() will list it as `no_party`. They are the only 4 files in it (dropbox_files: 4 paths).
--
-- MEASURED (SELECT only, production, 19 Nov 2026). Every row: entity 'customer', entity_id 0dc8c94f-903b-440a-b263-9b659513d7d1,
--   doc_type Correspondence, bucket backups, status done, moved_from null, verified (content hash + size stored), source storage:
--   id      dedupe_key                     what it is                                            the system's party today (v_conversation_message)
--   52497   CONV:wa_messages:29            28 Jul "Hi", from whatsapp:+971567918605 "DJ ZAINO"    supplier 158318 (Triple Six Real Estate)
--   52501   CONV:wa_messages:30            28 Jul "Supplier", same sender; the bot's reply names     supplier 158318
--                                          the supplier registration page
--   53162   CONV:inbound_messages:143      9 Sep, djzaino@outlook.com -> expenses@mail.quotesdone.com  company (party_id null)
--                                          "Fw: Renewal receipt for order #4161152146." (GoDaddy; the accountant's sweep booked it)
--   710220  CONV:notifications:112172      27 Oct, out, supplier_invite_seed "A question about    company (party_id null: to_email is the founder's
--                                          your work in the UAE", to djzaino@outlook.com             own mailbox, no lead_id)
--   Lead 158318 = "Triple six real estate" (TRIPLE SIX REAL ESTATE L.L.C), is_demo false, approved, phone/whatsapp +971567918605, folder
--   /QuotesDone Backup/Suppliers/Real estate brokerage & property management/TRIPLE SIX REAL ESTATE L.L.C/ (ledger 1729: a real supplier,
--   its mail is real supplier mail). The two WhatsApp messages come from the phone that is now that lead's own number, so the party
--   resolver already files them under it. The two e-mails are the founder's own mailbox and the company's expense inbox: no customer
--   and no supplier, which is what fn_enqueue_doc_backups files under /QuotesDone Backup/Company/Correspondence/<Dubai month>/.
--
-- HOW dropbox_backup RE-FILES (read from origin/main 19 Nov 2026): NOT from the entity fields alone. fn_enqueue_doc_backups inserts a CONV row
--   once (anti-join on dedupe_key) and never revisits it; its re-file steps (0) and (1) match only entity 'supplier' rows. The worker does
--   the moving: a row that carries moved_from (the path the file is in now) and a different dropbox_path, status 'pending', is claimed by a
--   worker whose run id says 'moves1' (fn_doc_backups_next), moved with files/move_v2 (move.ts moveFile: confirmed by size and content
--   hash, never overwrites, falls back to an upload of the stored copy if the old path is empty), and the party folder it left is removed
--   when no file is beneath it (removeEmptiedSource, ruling 1726). So this file does exactly what step (1) of the enqueue does to a
--   supplier row: it points the SAME row at the ruled path and queues it again, with moved_from. Nothing is inserted, nothing deleted.
--   Expected: 4 moves in one worker run (~25 rows per run), then "Customers/ahmad alzain (0dc8c94f)" is deleted as an emptied party folder.
--
-- WHAT IS NOT DONE, and why: no file is queued for removal through signup_purge_dropbox. (a) None is demo/test data under ledger 1199: two are
--   a real supplier's messages, one is the company's own expense receipt, one is a real outbound invite that went out. (b) A removal would
--   not hold: the archive rows (conversation_archive 143 and 112172, and wa_messages) stay, the anti-join in fn_enqueue_doc_backups finds no
--   doc_backups row for the dedupe key and files the message again under Company/ within the hour. (c) 710220 is a seed invite to the
--   founder's own inbox (ledger/memory: "no test email to the founder's own inboxes"); if he wants it gone it must be removed at its source
--   (notifications 112172 and its archive row), which is his decision and a different file.
--
-- SEAT: it_engineer. APPLY: node scripts/apply_sql.mjs scripts/sql/the_four_kept_copies_are_filed_under_their_real_party.sql --apply,
--   then append it to scripts/sql/MANIFEST.txt (Edit, last line); it defines no routine. ROLLBACK: for each id set entity/entity_id/
--   dropbox_path back to the values in the MEASURED table and moved_from = the new path, status 'pending' (the worker moves it back).
--   The probe below raises on any mismatch, which rolls this whole file back.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- the facts this file stands on, re-read inside the transaction; any difference aborts it
create temp table _kc on commit drop as
select d.id, d.dropbox_path as old_path, d.file_name, d.dedupe_key,
       split_part(d.dedupe_key, ':', 2) as source_table, split_part(d.dedupe_key, ':', 3) as source_id,
       v.party_kind, v.party_id, v.occurred_at,
       f.folder as supplier_folder
  from public.doc_backups d
  -- LATERAL with OFFSET 0, as fn_enqueue_doc_backups does: a plain join plans as a Hash Right Join over the whole view (~1,500
  -- fn_conversation_party calls at ~27 ms, past the 60 s statement_timeout); this is one lookup per row
  left join lateral (select v0.party_kind, v0.party_id, v0.occurred_at from public.v_conversation_message v0
                      where v0.source_table = split_part(d.dedupe_key, ':', 2) and v0.source_id = split_part(d.dedupe_key, ':', 3) offset 0) v on true
  left join lateral (select x.folder from public.fn_dbx_supplier_folders(case when v.party_kind = 'supplier' and v.party_id ~ '^[0-9]{1,18}$' then v.party_id::bigint else -1 end) x
                      where v.party_kind = 'supplier' and v.party_id ~ '^[0-9]{1,18}$') f on true
 where d.id in (52497, 52501, 53162, 710220)
   and d.entity = 'customer' and d.entity_id = '0dc8c94f-903b-440a-b263-9b659513d7d1';   -- a copy already re-filed is not touched: a second run is a no-op

do $chk$
declare n int;
begin
  select count(*) into n from _kc;
  if n = 0 then return; end if;
  if n <> 4 then raise exception 'CHK<<four kept copies: found % rows of 4 still under the customer>>', n; end if;
  if exists (select 1 from public.doc_backups d where d.id in (52497, 52501, 53162, 710220)
              and not (d.entity = 'customer' and d.entity_id = '0dc8c94f-903b-440a-b263-9b659513d7d1' and d.status = 'done'
                       and d.moved_from is null and d.doc_type = 'Correspondence' and d.dropbox_path like '/QuotesDone Backup/Customers/ahmad alzain (0dc8c94f)/Correspondence/%'
                       and d.dedupe_key like 'CONV:%')) then
    raise exception 'CHK<<a kept copy is no longer in the state this file was written for (already moved, or not done)>>';
  end if;
  if exists (select 1 from public.customers c where c.id::text = '0dc8c94f-903b-440a-b263-9b659513d7d1') then
    raise exception 'CHK<<customer 0dc8c94f exists again: the copies are not orphans, nothing to do>>';
  end if;
  if exists (select 1 from _kc where party_kind is null) then raise exception 'CHK<<a message has no row in v_conversation_message>>'; end if;
  if exists (select 1 from _kc where party_kind = 'customer') then raise exception 'CHK<<a message resolves to a customer: this file files only supplier and company>>'; end if;
  if exists (select 1 from _kc where party_kind = 'supplier' and (supplier_folder is null
              or not exists (select 1 from public.leads l where l.id::text = _kc.party_id and not l.is_demo))) then
    raise exception 'CHK<<a supplier party has no ruled folder yet, or is a demo lead: it waits for the sweep, as the enqueue does>>';
  end if;
end $chk$;

create temp table _kc_to on commit drop as
select k.id, k.old_path,
       case when k.party_kind = 'supplier' then 'supplier' else 'company' end as entity,
       case when k.party_kind = 'supplier' then k.party_id else k.source_table || ':' || k.source_id end as entity_id,
       public.fn_dbx_path(case when k.party_kind = 'supplier' then k.supplier_folder || 'Correspondence/' || k.file_name
                               else '/QuotesDone Backup/Company/Correspondence/' || to_char(k.occurred_at at time zone 'Asia/Dubai', 'YYYY-MM') || '/' || k.file_name end) as new_path
  from _kc k;

-- the move changes the FOLDER only, never the file's name, and lands on no path another row holds
do $chk2$
begin
  if exists (select 1 from _kc_to t where regexp_replace(t.new_path, '^.*/', '') <> regexp_replace(t.old_path, '^.*/', '')) then
    raise exception 'CHK<<a new path renames the file>>';
  end if;
  if exists (select 1 from _kc_to t join public.doc_backups o on o.dropbox_path = t.new_path and o.id <> t.id) then
    raise exception 'CHK<<a new path is already held by another backup row>>';
  end if;
end $chk2$;

update public.doc_backups d
   set moved_from = coalesce(d.moved_from, d.dropbox_path), dropbox_path = t.new_path, entity = t.entity, entity_id = t.entity_id,
       status = 'pending', error = null, attempts = 0, upload_state = null, backed_up_at = null, verified_at = null, requeued_at = now()
  from _kc_to t
 where d.id = t.id and d.status = 'done' and d.moved_from is null;

-- PROBE: no DDL in this file, so a failure raises and takes the update with it
do $probe$
begin
  if not exists (select 1 from _kc_to) then return; end if;   -- nothing to file: already done
  if (select count(*) from public.doc_backups d join _kc_to t on t.id = d.id
       where d.status = 'pending' and d.moved_from = t.old_path and d.dropbox_path = t.new_path and d.entity = t.entity and d.entity_id = t.entity_id
         and d.dedupe_key like 'CONV:%' and d.dropbox_content_hash is not null) <> 4 then
    raise exception 'CHK<<PROBE: not all four copies are queued to move>>';
  end if;
  if (select count(*) from public.doc_backups where entity = 'supplier' and entity_id = '158318' and id in (52497, 52501)) <> 2
     or (select count(*) from public.doc_backups where entity = 'company' and id in (53162, 710220)) <> 2 then
    raise exception 'CHK<<PROBE: 2 copies should be Triple Six (158318) and 2 Company>>';
  end if;
  if exists (select 1 from public.doc_backups where entity = 'customer' and entity_id = '0dc8c94f-903b-440a-b263-9b659513d7d1') then
    raise exception 'CHK<<PROBE: a row still names customer 0dc8c94f>>';
  end if;
  if exists (select 1 from public.signup_purge_dropbox where doc_backup_id in (52497, 52501, 53162, 710220)) then
    raise exception 'CHK<<PROBE: a copy is on a purge queue; this file queues no removal>>';
  end if;
end $probe$;

select 'PROBE OK' as verdict, t.id, t.entity, t.entity_id, t.old_path as moved_from, t.new_path as moves_to from _kc_to t
union all
select 'PROBE OK (nothing to file: none of the four is under the customer any more)', null, null, null, null, null where not exists (select 1 from _kc_to)
order by 2;
