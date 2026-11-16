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

create temp table _l5_out on commit drop as select public.fn_demo_purge(true) as out;

-- the sandbox test's evidence screenshots stay (header): off this purge's storage queue, never deleted
create temp table _l5_evidence_kept on commit drop as
with d as (
  delete from public.signup_purge_object o
   where o.purge_id = (select (out->>'purge_id')::bigint from _l5_out) and o.bucket = 'evidence' and o.done_at is null
  returning o.path)
select path from d;

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
       || ' Dropbox items; evidence kept ' || (select count(*) from _l5_evidence_kept)::text
       || '; kept: customers 0dc8c94f, ba61fa16 and leads 19398, 158318, 143027; non-demo counts ' || public.fn_demo_purge_real_counts()::text
       as verdict;
