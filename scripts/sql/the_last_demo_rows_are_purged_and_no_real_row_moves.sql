-- THE LAST DEMO ROWS ARE PURGED, AND NO REAL ROW MOVES (it_engineer; 16 Nov 2026; ledger 1121, 1199, 1214, 1539).
--
-- The founder: "once done, delete all the demo files and accounts so we go live clean and agents dont get mistaken" (1121);
-- "delete all test/demo data once and for all after the tests finish (DB, storage, Dropbox, logs)" (1199); "the +qdprobe1/
-- +qdcust1 Gmail-alias logins are test accounts - delete with the demo purge. The founder's real customer account (0dc8c94f)
-- and its folders stay" (1214); "Make sure all demo data is removed totally once the merges are finished" (1539); "I don't
-- want you to wait on me" (1710).
--
-- THE TOOL IS THE EXISTING ONE, UNCHANGED: public.fn_demo_purge(true) (scripts/sql/demo_data_is_purged_by_its_marker_and_no_seat_duty_reads_it.sql
--   and the_founders_rulings_of_10_november_settle_four_open_problems.sql). Production's bodies of all 13 fn_demo_purge*
--   routines and of fn_is_demo_email / fn_is_demo_phone / fn_inquiry_is_demo were read 16 Nov 2026 and match the local
--   mirror md5 for md5 (fn_demo_purge_run 592a1123660cd8d8e8e42a4198bbf249, fn_demo_purge_walk f80d12bd8d611c2a251129401666f2b7).
--   It picks rows by MARKER ONLY: customers.is_demo, leads.is_demo, fn_inquiry_is_demo (a demo customer, provenance qd_run,
--   brief_source qd_demo_fixture), a reserved address (example.invalid/.test/.example/localhost/example.com|net|org), the
--   fixture mobile 9715000000xx, and the two alias logins the founder named (fn_demo_purge_confirmed_logins). Lead 143027
--   is never a demo id (fn_demo_purge_kept_leads). Its own guard refuses the whole purge if the count of non-demo
--   customers, leads, inquiries, quotes, transactions or logins moves (QD198), if the walk reaches a ledger table (QD197)
--   or data-request evidence (QD196).
--
-- MEASURED BEFORE (SELECT on tables only, production, 16 Nov 2026 ~14:20Z):
--   auth.users 12 of 27: 10 on example.invalid + the +qdprobe1 / +qdcust1 aliases. customers 2 demo of 4 (34760038,
--   fc952c2c). leads 1 demo (126512 "ZZ DEMO Interiors gypsum found"). inquiries 3 of 3 (a179ea8d, 8b287960, d958e1ea,
--   18 Sep, qd_run). quotes 3, transactions 1 (29ac49f5: Stripe TEST mode, charge_audit.livemode false, 0 gl_journal /
--   gl_ledger / refund / supplier_dues rows). Storage: 28 objects (22 go, the 6 below stay). Dropbox: the 82 reviewed folders of
--   fn_demo_purge_dropbox_paths (= supabase/functions/dropbox_backup/demo_purge_paths.json), all still present, 170 entries.
-- KEPT, by name: the founder's two customer accounts 0dc8c94f (outlook.com) and ba61fa16 (gmail.com), is_demo false, and
--   their Dropbox folders (none inside a listed path); leads 19398, 158318 and 143027 (is_demo false).
-- KEPT, by decision of this file: the 6 objects in the private `evidence` bucket (QuotesDone_Sandbox_Test_2026-10/...
--   zz_demo_plan.png). They are the record of the October sandbox test, which ledger 1278 keeps there; no seat reads that
--   bucket as live data. They are taken off this purge's storage queue below, never deleted.
--
-- WHAT THIS FILE DOES, in ONE transaction at REPEATABLE READ (one snapshot, so the before and after counts are exact while
--   the estate keeps writing):
--   1. the SCOPE: every relation the purge names and every foreign-key descendant of one (176 on production);
--   2. the row count of each, BEFORE (count(*) through query_to_xml: read-only, an ACCESS SHARE lock, no EXECUTE);
--   3. the purge: select public.fn_demo_purge(true). Storage objects and Dropbox copies are LISTED in signup_purge_object /
--      signup_purge_dropbox; dropbox_backup removes them (50 objects and 25 Dropbox paths a run, 15 minutes after listing),
--      Dropbox only inside the reviewed list (dropbox_backup/purge.ts demoPurgeDeleteAllowed). Nothing outside it is deleted;
--   4. the count of each, AFTER, and the CHECK below. Any failure raises, and the raise rolls back the WHOLE purge:
--      a. every relation in scope lost EXACTLY the rows the purge says it deleted there, and no other relation lost a row;
--      b. no demo row is left in the tables fn_demo_purge_verify reads (the two queues and the doc_backups records whose
--         Dropbox copy is still to be removed are the only things that remain, by design, until dropbox_backup drains them);
--      c. the non-demo counts (customers, leads, inquiries, quotes, transactions, logins) are unchanged;
--      d. the kept accounts and leads above are all still there and still not demo.
--   5. a verdict row (PROBE OK / the raise) that apply_sql.mjs reads.
-- REVIEW OF 16 NOV 2026 (scratchpad REVIEW_L3_L5.md part 2), built in:
--   * the CENSUS PIN: the demo sets are read before the purge and must be exactly 2 customers, 1 lead, 3 inquiries, 3 quotes,
--     1 transaction, 12 logins, or nothing is purged. A paid certification was creating demo leads on 16 Nov (159933, 159934 at
--     15:00Z): run this only AFTER it ends, with a fresh census, and change the pin in review if the census moved;
--   * the FOREIGN-KEY PINS: every row in scope that points at a real customer, lead, inquiry, quote, transaction or login is
--     counted before and after; any change, and any row the walk unlinks ('unlinked') or the database nulls (a SET NULL / SET
--     DEFAULT reference to a demo row, kept by primary key), rolls the purge back;
--   * STORAGE the routine's segment-start marker misses (signed-terms and receipt-files files with ZZ_DEMO inside the name,
--     agent-docs/quote-files under a demo lead or inquiry, backups/generated summaries named by a demo id): queued under the
--     same purge. 39 objects on 16 Nov ~15:30Z, listed in the hand-back; the evidence bucket stays.
-- WHEN: apply it outside campaign hours, in a quiet minute (scripts/apply_sql.mjs, no --ddl). It deletes a few hundred rows.
-- AFTER: scripts/sql/the_last_demo_rows_are_purged_and_no_real_row_moves_probe.sql (PROBE OK) at once, and
--   `node scripts/it/purge_demo_data.mjs --verify-zero` (exit 0) once dropbox_backup has drained both queues (~3 hours).
set transaction isolation level repeatable read;

create temp table _l5_scope on commit drop as
with recursive roots(rel) as (
  select to_regclass(r) from unnest(array['public.company_event', 'public.agent_actions', 'public.doc_versions', 'public.documents',
    'public.quote_items', 'public.notifications', 'public.email_verifications', 'public.phone_verifications', 'public.inquiry_intake',
    'public.drawing_redaction_runs', 'public.cad_read_jobs', 'public.support_case', 'public.support_customer_profile',
    'public.customer_support_duty_message', 'public.quote_reviews', 'public.quote_spec_hold', 'public.supplier_score',
    'public.supplier_document_cache', 'public.wa_conversation', 'public.wa_messages', 'public.wa_inbound_seen', 'public.wa_answer_log',
    'public.sms_messages', 'public.email_suppressions', 'public.rl_hits', 'public.ai_rate_limit', 'public.assistant_logs',
    'public.ai_cost_log', 'public.rehearsal_window', 'public.marketing_outreach_message', 'public.marketing_prospect',
    'public.marketing_post', 'public.marketing_campaign', 'public.marketing_article', 'public.marketing_ad_spend_day',
    'public.ad_campaign_state', 'public.social_conversation', 'public.transactions', 'public.quotes', 'public.inquiries',
    'public.customers', 'public.leads', 'auth.users', 'public.doc_backups', 'storage.objects']) r
   where to_regclass(r) is not null),
walk(rel, depth) as (
  select rel, 0 from roots
  union
  select c.conrelid::regclass, w.depth + 1 from walk w
    join pg_constraint c on c.confrelid = w.rel and c.contype = 'f' and c.conrelid <> c.confrelid
   where w.depth < 9)
select distinct w.rel::oid as rel,
       -- the key fn_demo_purge_walk writes in 'touched': regclass text under search_path public, pg_temp
       case when n.nspname = 'public' then c.relname else n.nspname || '.' || c.relname end as k
  from walk w join pg_class c on c.oid = w.rel join pg_namespace n on n.oid = c.relnamespace
 where c.relkind in ('r', 'p') and c.relname not in ('signup_purge', 'signup_purge_object', 'signup_purge_dropbox');

create temp table _l5_before on commit drop as
select s.rel, s.k, (xpath('/row/n/text()', query_to_xml('select count(*) as n from ' || s.rel::regclass::text, false, true, '')))[1]::text::bigint as n
  from _l5_scope s;

-- the kept accounts, as measured 16 Nov: 2 customers, their 2 logins (by e-mail), 3 leads, none demo
create or replace temp view _l5_kept as
select (select count(*) from public.customers where left(id::text, 8) in ('0dc8c94f', 'ba61fa16') and not coalesce(is_demo, false)) as founder_customers,
       (select count(*) from auth.users u join public.customers c on lower(c.email) = lower(u.email)
         where left(c.id::text, 8) in ('0dc8c94f', 'ba61fa16') and not coalesce(c.is_demo, false)) as founder_logins,
       (select count(*) from public.leads where id in (19398, 158318, 143027) and not coalesce(is_demo, false)) as kept_leads;

create temp table _l5_kept_before on commit drop as
select k.*, public.fn_demo_purge_real_counts() as real_counts from _l5_kept k;

do $kept$
begin
  if (select row(founder_customers, founder_logins, kept_leads)::text from _l5_kept_before) <> '(2,2,3)' then
    raise exception 'DEMO PURGE REFUSED before it started: the founder''s accounts and the kept leads are not as measured (customers, logins, leads = %, expected (2,2,3))',
      (select row(founder_customers, founder_logins, kept_leads)::text from _l5_kept_before);
  end if;
end $kept$;

-- THE DEMO SETS, by the purge's own rules (fn_demo_purge_run), read here BEFORE it runs. Pinned to the reviewed census
-- (review 16 Nov 2026: a running paid certification adds demo leads, e.g. 159933 and 159934 at 15:00Z; this file runs only after
-- it, with a fresh census and this pin updated by review). Anything else: nothing is purged.
create temp table _l5_demo on commit drop as
select 'public.customers'::regclass as rel, id::text as id from public.customers where is_demo
union all select 'public.leads'::regclass, id::text from public.leads where is_demo and id <> all(public.fn_demo_purge_kept_leads())
union all select 'public.inquiries'::regclass, i.id::text from public.inquiries i where public.fn_inquiry_is_demo(i.id);
insert into _l5_demo
select 'public.quotes'::regclass, q.id::text from public.quotes q
 where q.inquiry_id::text in (select id from _l5_demo where rel = 'public.inquiries'::regclass)
    or q.supplier_id::text in (select id from _l5_demo where rel = 'public.leads'::regclass);
insert into _l5_demo
select 'public.transactions'::regclass, t.id::text from public.transactions t
 where t.customer_id::text in (select id from _l5_demo where rel = 'public.customers'::regclass)
    or t.supplier_id::text in (select id from _l5_demo where rel = 'public.leads'::regclass)
    or t.inquiry_id::text in (select id from _l5_demo where rel = 'public.inquiries'::regclass)
    or t.quote_id::text in (select id from _l5_demo where rel = 'public.quotes'::regclass);
insert into _l5_demo
select 'auth.users'::regclass, u.id::text from auth.users u
 where public.fn_is_demo_email(u.email) or public.fn_is_demo_phone(u.phone)
    or u.id::text in (select id from _l5_demo where rel = 'public.customers'::regclass)
    or lower(coalesce(u.email, '')) = any(public.fn_demo_purge_confirmed_logins());

do $census$
declare v jsonb := jsonb_build_object(
  'customers', (select count(*) from _l5_demo where rel = 'public.customers'::regclass), 'leads', (select count(*) from _l5_demo where rel = 'public.leads'::regclass),
  'inquiries', (select count(*) from _l5_demo where rel = 'public.inquiries'::regclass), 'quotes', (select count(*) from _l5_demo where rel = 'public.quotes'::regclass),
  'transactions', (select count(*) from _l5_demo where rel = 'public.transactions'::regclass), 'auth_users', (select count(*) from _l5_demo where rel = 'auth.users'::regclass));
begin
  if v is distinct from '{"customers": 2, "leads": 1, "inquiries": 3, "quotes": 3, "transactions": 1, "auth_users": 12}'::jsonb then
    raise exception 'DEMO PURGE REFUSED before it started: the demo census is % and the reviewed one is 2 customers, 1 lead, 3 inquiries, 3 quotes, 1 transaction, 12 logins: run it after the certification, with a fresh census and review', v;
  end if;
end $census$;

-- THE FOREIGN-KEY PINS (review 16 Nov 2026: the per-table accounting proves the purge deleted what it says, not that what it deleted
-- was demo). For every single-column foreign key from a table in scope to the id of a customer, lead, inquiry, quote, transaction
-- or login: the rows that point at a NON-demo one (the child itself not a demo entity). The count must not move: a real-linked row
-- deleted, or its link nulled, rolls the whole purge back. read-only counts through query_to_xml, as above.
create temp table _l5_fk on commit drop as
select c.conrelid::regclass as child, a.attname::text as col, c.confrelid::regclass as parent,
       format('select count(*) as n from %s x where x.%I is not null and x.%I::text not in (select id from _l5_demo where rel = %L::regclass)%s',
              c.conrelid::regclass, a.attname, a.attname, c.confrelid::regclass::text,
              case when c.conrelid in ('public.customers'::regclass, 'public.leads'::regclass, 'public.inquiries'::regclass, 'public.quotes'::regclass,
                                       'public.transactions'::regclass, 'auth.users'::regclass)
                   then format(' and x.id::text not in (select id from _l5_demo where rel = %L::regclass)', c.conrelid::regclass::text) else '' end) as q
  from pg_constraint c
  join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
  join pg_attribute pa on pa.attrelid = c.confrelid and pa.attnum = c.confkey[1]
 where c.contype = 'f' and cardinality(c.conkey) = 1 and pa.attname = 'id'
   and c.confrelid in ('public.customers'::regclass, 'public.leads'::regclass, 'public.inquiries'::regclass, 'public.quotes'::regclass,
                       'public.transactions'::regclass, 'auth.users'::regclass)
   and c.conrelid in (select rel from _l5_scope);
create temp table _l5_fk_before on commit drop as
select child, col, parent, q, (xpath('/row/n/text()', query_to_xml(q, false, true, '')))[1]::text::bigint as n from _l5_fk;

-- A SET NULL OR SET DEFAULT REFERENCE TO A DEMO ROW: the row that holds it survives the purge, changed. fn_demo_purge_walk reports
-- the ones it walks as '(unlinked ...)', but not a table's reference to itself (inquiries.repeat_of), which Postgres nulls on the
-- delete. So every such row is named here by its primary key before the purge; if one of them still exists after it, nothing is purged.
create temp table _l5_setnull_q on commit drop as
select c.conrelid::regclass as child, a.attname::text as col,
       (select pa2.attname::text from pg_constraint p join pg_attribute pa2 on pa2.attrelid = p.conrelid and pa2.attnum = p.conkey[1]
         where p.conrelid = c.conrelid and p.contype = 'p' and cardinality(p.conkey) = 1) as pk,
       format('from %s x where x.%I::text in (select id from _l5_demo where rel = %L::regclass)%s', c.conrelid::regclass, a.attname, c.confrelid::regclass::text,
              case when c.conrelid in (select distinct rel from _l5_demo)
                   then format(' and x.id::text not in (select id from _l5_demo where rel = %L::regclass)', c.conrelid::regclass::text) else '' end) as q_from
  from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
 where c.contype = 'f' and cardinality(c.conkey) = 1 and c.confdeltype in ('n', 'd') and c.confrelid in (select distinct rel from _l5_demo);
create temp table _l5_setnull on commit drop as
select z.child, z.col, z.pk,
       (xpath('/row/n/text()', query_to_xml('select count(*) as n ' || z.q_from, false, true, '')))[1]::text::bigint as n,
       case when z.pk is null then null else string_to_array((xpath('/row/i/text()',
         query_to_xml(format('select string_agg(x.%I::text, %L) as i ', z.pk, chr(31)) || z.q_from, false, true, '')))[1]::text, chr(31)) end as ids
  from _l5_setnull_q z;

create temp table _l5_out on commit drop as select public.fn_demo_purge(true) as out;

-- the sandbox test's evidence screenshots stay (header): off this purge's storage queue, never deleted
create temp table _l5_evidence_kept on commit drop as
with d as (
  delete from public.signup_purge_object o
   where o.purge_id = (select (out->>'purge_id')::bigint from _l5_out) and o.bucket = 'evidence' and o.done_at is null
  returning o.path)
select path from d;

-- STORAGE THE ROUTINE MISSES (review 16 Nov 2026). fn_demo_purge_run matches the ZZ DEMO marker only at the START of a path
-- segment, so 'signed-terms/suppliers/<ms>_ZZ_DEMO_<name>_TnC-Acceptance.pdf' and 'receipt-files/.../<ms>_zz_demo_delivery_note.pdf'
-- were never listed; and it lists by id only in supplier-docs and drawing-files, so agent-docs/supplier/<demo lead>/ and the
-- backups/generated summaries named by a demo id stayed. Queued here under the same purge, by marker or demo id only:
--   1. the marker after any non-alphanumeric character, in every bucket but the shared assets and evidence;
--   2. a path segment equal to a demo lead, customer or inquiry id, or 'QD-<first 8 of a demo inquiry>-' (our document ids),
--      or a file name carrying a demo id with '_' for '-' (backups/generated), in agent-docs, quote-files, backups, receipt-files.
create temp table _l5_extra_objects on commit drop as
with ins as (
  insert into public.signup_purge_object (purge_id, bucket, path)
  select (select (out->>'purge_id')::bigint from _l5_out), o.bucket_id, o.name from storage.objects o
   where o.bucket_id not in ('brand', 'site', 'demo-assets', 'social-media', 'kb-import-assets', 'evidence')
     and (o.name ~* '(^|[^a-z0-9])(zz[ _-]?demo([^a-z]|$)|__selftest__|_selftest/)'
          or (o.bucket_id in ('agent-docs', 'quote-files', 'backups', 'receipt-files')
              and exists (select 1 from _l5_demo d where d.rel in ('public.leads'::regclass, 'public.customers'::regclass, 'public.inquiries'::regclass)
                           and (('/' || o.name || '/') like '%/' || d.id || '/%'
                                or (d.rel <> 'public.leads'::regclass and (o.name ilike '%QD-' || left(d.id, 8) || '-%' or o.name ilike '%\_' || replace(d.id, '-', '\_') || '.%'))
                                or (d.rel = 'public.leads'::regclass and o.name ~ ('_' || d.id || '\.[a-z]+$'))))))
  on conflict (bucket, path) do nothing
  returning bucket, path)
select bucket, path from ins;

create temp table _l5_after on commit drop as
select s.rel, s.k, (xpath('/row/n/text()', query_to_xml('select count(*) as n from ' || s.rel::regclass::text, false, true, '')))[1]::text::bigint as n
  from _l5_scope s;

do $check$
declare
  v_out jsonb := (select out from _l5_out);
  v_touched jsonb := coalesce((select out->'touched' from _l5_out), '{}'::jsonb);
  v_kept record; v_bad text; v_left jsonb; v_pid bigint;
begin
  v_pid := (v_out->>'purge_id')::bigint;
  -- review 16 Nov: exactly the reviewed census, or nothing (a running certification added demo leads 159933/159934 at 15:00Z)
  if v_out->'demo_ids' is distinct from '{"customers": 2, "leads": 1, "inquiries": 3, "quotes": 3, "transactions": 1, "auth_users": 12}'::jsonb then
    raise exception 'DEMO PURGE REFUSED: the demo census is not the reviewed one (%): re-census and review before purging', v_out->'demo_ids';
  end if;
  if (v_out->'demo_ids') is distinct from (select jsonb_build_object('customers', count(*) filter (where rel = 'public.customers'::regclass),
        'leads', count(*) filter (where rel = 'public.leads'::regclass), 'inquiries', count(*) filter (where rel = 'public.inquiries'::regclass),
        'quotes', count(*) filter (where rel = 'public.quotes'::regclass), 'transactions', count(*) filter (where rel = 'public.transactions'::regclass),
        'auth_users', count(*) filter (where rel = 'auth.users'::regclass)) from _l5_demo) then
    raise exception 'DEMO PURGE REFUSED: the purge chose other demo rows (%) than the census read before it', v_out->'demo_ids';
  end if;
  -- e. no surviving row was unlinked from a demo one (a SET NULL reference is a row that is not demo, changed)
  select string_agg(t.key || '=' || t.value, ', ') into v_bad from jsonb_each_text(v_touched) t where t.key ~ ' \(unlinked ' and t.value::bigint > 0;
  if v_bad is not null then raise exception 'DEMO PURGE REFUSED: a row that is not demo would be changed (its link to a demo row nulled): %', v_bad; end if;
  -- e2. ...nor a row that held a SET NULL / SET DEFAULT reference to a demo row (the walk's or the database's own)
  select string_agg(format('%s.%s: %s row(s)', z.child, z.col, coalesce(
           (select (xpath('/row/n/text()', query_to_xml(format('select count(*) as n from %s x where x.%I::text = any(%L::text[])', z.child, z.pk, z.ids), false, true, '')))[1]::text
             where z.pk is not null), z.n::text || ' (no single-column key to tell)')), '; ') into v_bad
    from _l5_setnull z
   where z.n > 0 and (z.pk is null or (xpath('/row/n/text()', query_to_xml(format('select count(*) as n from %s x where x.%I::text = any(%L::text[])', z.child, z.pk, z.ids), false, true, '')))[1]::text::bigint > 0);
  if v_bad is not null then raise exception 'DEMO PURGE REFUSED: a row that is not demo held a reference to a demo row and would survive with it nulled: %', v_bad; end if;
  -- f. no row that points at a real customer, lead, inquiry, quote, transaction or login was deleted or unlinked
  select string_agg(format('%s.%s -> %s: %s -> %s', b.child, b.col, b.parent, b.n, a.n), '; ') into v_bad
    from _l5_fk_before b cross join lateral (select (xpath('/row/n/text()', query_to_xml(b.q, false, true, '')))[1]::text::bigint as n) a
   where a.n <> b.n;
  if v_bad is not null then raise exception 'DEMO PURGE REFUSED: rows pointing at a real party moved: %', v_bad; end if;
  -- a. every relation lost exactly what the purge says it deleted there; none lost anything else
  select string_agg(format('%s: %s -> %s, purge says %s', b.k, b.n, a.n, coalesce(v_touched->>b.k, '0')), '; ' order by b.k) into v_bad
    from _l5_before b join _l5_after a on a.rel = b.rel
   where b.n - a.n <> coalesce((v_touched->>b.k)::bigint, 0);
  if v_bad is not null then raise exception 'DEMO PURGE REFUSED: a table moved by other than the demo rows: %', v_bad; end if;
  select string_agg(t.key, ', ') into v_bad from jsonb_each_text(v_touched) t
   where t.key !~ ' \(unlinked ' and t.value::bigint > 0 and not exists (select 1 from _l5_scope s where s.k = t.key);
  if v_bad is not null then raise exception 'DEMO PURGE REFUSED: the purge deleted in % outside the measured scope', v_bad; end if;
  -- b. no demo row left; only the two queues (and the backup records waiting on them) remain, until dropbox_backup drains them
  v_left := public.fn_demo_purge_verify();
  select string_agg(t.key || ' ' || t.value, ', ') into v_bad from jsonb_each_text(v_left) t
   where t.key not in ('storage_queue_open', 'dropbox_queue_open', 'doc_backups') and t.value::bigint <> 0;
  if v_bad is not null then raise exception 'DEMO PURGE INCOMPLETE: demo rows left: %', v_bad; end if;
  if (v_left->>'doc_backups')::bigint > (select count(*) from public.signup_purge_dropbox where purge_id = v_pid and doc_backup_id is not null) then
    raise exception 'DEMO PURGE INCOMPLETE: % demo backup records left, more than the % whose Dropbox copy is queued',
      v_left->>'doc_backups', (select count(*) from public.signup_purge_dropbox where purge_id = v_pid and doc_backup_id is not null);
  end if;
  -- c. the non-demo counts did not move (the tool's own guard says the same; this reads it again after the evidence step)
  select * into v_kept from _l5_kept_before;
  if public.fn_demo_purge_real_counts() is distinct from v_kept.real_counts then
    raise exception 'DEMO PURGE REFUSED: non-demo counts moved: before % after %', v_kept.real_counts, public.fn_demo_purge_real_counts();
  end if;
  -- d. the founder's two accounts and the three named leads are still there and still not demo
  if (select row(founder_customers, founder_logins, kept_leads)::text from _l5_kept) <> '(2,2,3)' then
    raise exception 'DEMO PURGE REFUSED: a kept account or lead moved (customers, logins, leads = %)', (select row(founder_customers, founder_logins, kept_leads)::text from _l5_kept);
  end if;
end $check$;

drop view if exists pg_temp._l5_kept;

select 'PROBE OK: demo ' || ((select out from _l5_out)->'demo_ids')::text
       || '; rows deleted ' || (select coalesce(sum(b.n - a.n), 0) from _l5_before b join _l5_after a on a.rel = b.rel)::text
       || ' in ' || (select count(*) from _l5_before b join _l5_after a on a.rel = b.rel where b.n <> a.n)::text || ' of '
       || (select count(*) from _l5_scope)::text || ' tables, every one exactly as the purge reported'
       || '; unlinked ' || coalesce((select string_agg(t.key || '=' || t.value, ', ') from jsonb_each_text((select out->'touched' from _l5_out)) t
                                      where t.key ~ ' \(unlinked ' and t.value::bigint > 0), 'none')
       || '; queued for dropbox_backup: ' || (select count(*) from public.signup_purge_object where purge_id = ((select out from _l5_out)->>'purge_id')::bigint)::text
       || ' storage objects, ' || (select count(*) from public.signup_purge_dropbox where purge_id = ((select out from _l5_out)->>'purge_id')::bigint)::text
       || ' Dropbox items (of them ' || (select count(*) from _l5_extra_objects)::text || ' objects the routine''s own marker misses); evidence kept ' || (select count(*) from _l5_evidence_kept)::text
       || '; foreign keys to a real party pinned: ' || (select count(*) from _l5_fk_before)::text
       || '; kept: customers 0dc8c94f, ba61fa16 and leads 19398, 158318, 143027; non-demo counts ' || public.fn_demo_purge_real_counts()::text
       as verdict;
