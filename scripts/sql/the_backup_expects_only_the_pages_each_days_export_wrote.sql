-- THE BACKUP EXPECTS ONLY THE PAGES EACH DAY'S EXPORT WROTE.
--
-- Assigned: it_engineer. 22 Sep 2026. Founder instruction 573: "i dont want things to pop up again
-- for the same reasons".
--
-- ══ WHAT WAS MEASURED, 22 Sep 2026, against htdblwldjkcgjvmqkbeh ═══════════════════════════════
--
-- fn_it_backup_check found 7 never_queued files every run: obj:backups:<day>/table_export_change/
-- page_0000.json for 15..21 Sep. None of them exists: storage holds 0 objects in any of those folders,
-- and each day's table_export_run.state->'tables' (110 tables) does not name table_export_change --
-- the table joined fn_table_export_list() (now 111) after those exports ran; the 22 Sep full export
-- wrote it and it is backed up. Every file the exports DID write is backed up: storage objects per
-- day = doc_backups rows (15: 2840, 16/17/19/20/21: 257, 18: 4433, 22: 416), and pages recorded in
-- state = page objects in storage for every day (15: 2839/2839, 18: 4432/4432, others 256/256).
-- The cause: fn_it_backup_expected expected page_0000 of every table on TODAY's list for EVERY day.
--
-- ══ WHAT THIS FILE CHANGES ══════════════════════════════════════════════════════════════════
--
-- fn_it_backup_expected, TABLE EXPORTS block only: a day whose run is 'done' expects its manifest
-- and page_0000..page_<pages-1> of each table its own run recorded writing; a day with no finished
-- run keeps the whole static list (a day that never ran is still a finding); every object actually
-- in the day's folder stays expected. Every other block is the deployed body, byte for byte.
-- Then the exact-key close: a 'REFILE:backups:<day>/table_export_change/page_0000.json' row for the
-- 7 keys, if a refile ever filed one, is abandoned with its reason (fn_it_backup_recheck reads an
-- abandoned row with an 'abandoned:' reason as settled and closes the handoff itself). Measured
-- before writing: 0 such rows and 0 handoffs, findings, reports or notifications naming the keys,
-- because every check that found them timed out and rolled back.
--
-- WHAT IT DOES NOT CHANGE: fn_table_export_list, the export writer, the enqueue, the 24-hour grace.
--
-- ══ PREVENTED BY ════════════════════════════════════════════════════════════════════════════
--
-- scripts/sql/the_backup_check_answers_inside_its_budget_probe.sql: fails when any finished
-- export day's expected table-export files differ from what the day's folder holds, either way.
--
--   node scripts/apply_sql.mjs scripts/sql/the_backup_expects_only_the_pages_each_days_export_wrote.sql --apply

create or replace function public.fn_it_backup_expected()
returns table(item_key text, kind text, bucket text, path text, gen_kind text, gen_ref text, owner text, since timestamp with time zone)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with rl as (select * from public.leads where not coalesce(is_demo, false)),
       rc as (select * from public.customers where not coalesce(is_demo, false)),
       ri as (select i.* from public.inquiries i join rc on rc.id = i.customer_id),
  base as (
  select 'obj:' || o.bucket_id || ':' || o.name as item_key, 'storage' as kind, o.bucket_id as bucket, o.name as path,
         null::text as gen_kind, null::text as gen_ref, x.owner, o.created_at as since
    from storage.objects o
    cross join lateral (select case
      when o.bucket_id = 'supplier-docs' then (select 'supplier:' || l.id from rl l
             where l.id::text = split_part(o.name, '/', 2)
                or o.name in (l.license_doc_path, l.egr_doc_path, l.insurance_doc_path, l.vat_doc_path,
                              l.iso_doc_path, l.manufacturer_auth_doc_path, l.company_profile_doc_path)
                or o.name = any(coalesce(l.catalog_doc_paths, '{}')) limit 1)
      when o.bucket_id = 'signed-terms' then coalesce(
             (select 'customer:' || c.id from rc c where c.signed_terms_path = o.name limit 1),
             (select 'supplier:' || l.id from rl l where l.signed_terms_path = o.name limit 1))
      when o.bucket_id = 'drawing-files' then (select 'inquiry:' || i.id from ri i
             where i.id::text = split_part(o.name, '/', 2) or i.drawing_file_path = o.name limit 1)
      when o.bucket_id = 'finance-docs' then (select 'transaction:' || t.id from public.transactions t where t.doc_path = o.name limit 1)
    end as owner) x
   where o.bucket_id in (select r.bucket from public.fn_backup_source_registry() r where r.kind = 'bucket' and r.backed_up)
     and x.owner is not null and o.name !~* 'zz[_ -]?demo'
  union all
  -- a Stripe invoice the transaction names but storage no longer holds is still expected
  select 'obj:finance-docs:' || t.doc_path, 'invoice', 'finance-docs', t.doc_path, null, null, 'transaction:' || t.id, t.revealed_at
    from public.transactions t
    -- transactions carries no is_demo of its own: a sale is demo when either party is (review of
    -- #628). Without this, a purged demo invoice would read never_queued forever and escalate.
    left join public.customers tc on tc.id = t.customer_id
    left join public.leads tl on tl.id = t.supplier_id
   where t.doc_path is not null
     and not coalesce(tc.is_demo, false) and not coalesce(tl.is_demo, false)
     and coalesce(tc.email, '') !~* 'example\.invalid' and coalesce(tl.email, '') !~* 'example\.invalid'
     and not exists (select 1 from storage.objects o where o.bucket_id = 'finance-docs' and o.name = t.doc_path)
  union all
  select 'msg:' || m.source_table || ':' || m.source_id, 'conversation', c.pdf_bucket, c.pdf_path, null, null,
         coalesce(m.party_kind || ':' || m.party_id, 'company'), m.occurred_at
    from public.v_conversation_message m
    left join public.conversation_archive c on c.source_table = m.source_table and c.source_id = m.source_id
   where not m.is_demo
  union all
  select 'gen:supplier_details:' || l.id, 'generated', null, null, 'supplier_details', l.id::text, 'supplier:' || l.id, l.created_at
    from rl l
   where l.approved_at is not null or l.registration_submitted_at is not null or l.signed_terms_path is not null
      or l.company_profile_doc_path is not null or l.license_doc_path is not null or coalesce(l.claimed, false)
  union all
  select 'gen:customer_details:' || c.id, 'generated', null, null, 'customer_details', c.id::text, 'customer:' || c.id, c.created_at from rc c
  union all
  select 'gen:inquiry_summary:' || i.id, 'generated', null, null, 'inquiry_summary', i.id::text, 'inquiry:' || i.id, i.created_at from ri i
  union all
  -- ── ACCOUNTING (14 Sep 2026, accountant duty 4): what fn_enqueue_doc_backups files under Finance ──
  select 'obj:' || c.pdf_bucket || ':' || v.path, 'storage', c.pdf_bucket, v.path, null, null,
         'finance:close:' || to_char(c.month, 'YYYY-MM'), c.rendered_at
    from public.accountant_month_close c cross join lateral (values (c.pdf_path), (c.csv_path)) v(path)
   where c.rendered_at is not null and c.pdf_bucket is not null and length(coalesce(v.path, '')) > 0
  union all
  select 'obj:' || split_part(b.doc_path, '/', 1) || ':' || substr(b.doc_path, strpos(b.doc_path, '/') + 1), 'storage',
         split_part(b.doc_path, '/', 1), substr(b.doc_path, strpos(b.doc_path, '/') + 1), null, null,
         'finance:bank_statement:' || b.source_ref, b.received_at
    from public.bank_statement_intake b
   where b.doc_path ~ '^[a-z0-9-]+/.+' and b.account <> 'zz_demo'
  union all
  select 'obj:' || split_part(d.file_path, '/', 1) || ':' || substr(d.file_path, strpos(d.file_path, '/') + 1), 'storage',
         split_part(d.file_path, '/', 1), substr(d.file_path, strpos(d.file_path, '/') + 1), null, null,
         'finance:issued:' || d.id, d.issued_at
    from public.accountant_issued_document d
   where d.file_path ~ '^[a-z0-9-]+/.+' and d.recipient !~* 'example\.invalid'
  union all
  select 'obj:' || (f->>'bucket') || ':' || (f->>'path'), 'storage', f->>'bucket', f->>'path', null, null,
         'finance:year_end:' || p.year, p.rendered_at
    from public.accountant_year_end_pack p cross join lateral jsonb_array_elements(p.files) f
   where p.rendered_at is not null and (f->>'path') !~* 'zz[_ -]?demo'
  union all
  -- ── TABLE EXPORTS (14 Sep 2026): each Asia/Dubai day from the first the revived writer ran ──
  -- due from 03:00 Dubai that day; the expected-status grace then decides when a gap is a finding
  select 'obj:backups:' || f.path, 'storage', 'backups', f.path, null, null,
         'company:table_export:' || to_char(d.day, 'YYYY-MM-DD'), (d.day::date + time '03:00') at time zone 'Asia/Dubai'
    from generate_series((select min(r.stamp) from public.table_export_run r),
                         (now() at time zone 'Asia/Dubai')::date, interval '1 day') d(day)
    -- a day removed under the retention rules is no longer expected (15 Sep 2026)
    join lateral (select not exists (select 1 from public.table_export_run pr
                                      where pr.stamp = d.day::date and pr.pruned_at is not null) as kept) k on k.kept
    cross join lateral (
      select to_char(d.day, 'YYYY-MM-DD') || '/_manifest.json' as path
      -- 22 SEP 2026: a FINISHED day expects exactly the pages its own run recorded writing
      -- (table_export_run.state->'tables': table -> pages), page_0000 .. page_<pages-1>. It used to
      -- expect page_0000 of every table fn_table_export_list() names TODAY, so a table added to the
      -- list on 22 Sep (table_export_change) was "never queued" on every earlier day -- seven files
      -- that never existed, refiled every run. A day with no finished run keeps the whole list.
      union select to_char(d.day, 'YYYY-MM-DD') || '/' || t.key || '/page_' || lpad(g::text, 4, '0') || '.json'
              from public.table_export_run r
              cross join lateral jsonb_each(r.state->'tables') t
              cross join lateral generate_series(0, coalesce((t.value->>'pages')::int, 1) - 1) g
             where r.stamp = d.day::date and r.status = 'done' and jsonb_typeof(r.state->'tables') = 'object'
      union select to_char(d.day, 'YYYY-MM-DD') || '/' || x.table_name || '/page_0000.json' from public.fn_table_export_list() x
             where not exists (select 1 from public.table_export_run r
                                where r.stamp = d.day::date and r.status = 'done' and jsonb_typeof(r.state->'tables') = 'object')
      union select o.name from storage.objects o where o.bucket_id = 'backups' and o.name like to_char(d.day, 'YYYY-MM-DD') || '/%') f
  )
  select * from base
  union all
  -- ── STORAGE SWEEP (15 Sep 2026): every other stored file the registry sweeps ──
  select 'obj:' || s.bucket || ':' || s.path, 'storage', s.bucket, s.path, null, null, s.entity || ':' || s.entity_id, s.created_at
    from public.fn_backup_sweep_objects() s
   where not exists (select 1 from base b where b.item_key = 'obj:' || s.bucket || ':' || s.path);
$fn$;
-- CREATE OR REPLACE preserves the ACL; the revoke is restated on the exact (only) signature.
revoke execute on function public.fn_it_backup_expected() from public, anon, authenticated;

-- The exact-key close. Keys spelled out, never matched by pattern.
update public.doc_backups b
   set status = 'abandoned',
       error = left('abandoned: never written -- the ' || split_part(b.path, '/', 1) || ' export ran before table_export_change '
                    || 'joined the export list, so no such page exists (fn_it_backup_expected fixed 22 Sep 2026); last error: '
                    || coalesce(b.error, 'none'), 300)
 where b.dedupe_key in ('REFILE:backups:2026-09-15/table_export_change/page_0000.json',
                        'REFILE:backups:2026-09-16/table_export_change/page_0000.json',
                        'REFILE:backups:2026-09-17/table_export_change/page_0000.json',
                        'REFILE:backups:2026-09-18/table_export_change/page_0000.json',
                        'REFILE:backups:2026-09-19/table_export_change/page_0000.json',
                        'REFILE:backups:2026-09-20/table_export_change/page_0000.json',
                        'REFILE:backups:2026-09-21/table_export_change/page_0000.json')
   and b.status not in ('done', 'abandoned')
   and not exists (select 1 from storage.objects o where o.bucket_id = b.bucket and o.name = b.path);
