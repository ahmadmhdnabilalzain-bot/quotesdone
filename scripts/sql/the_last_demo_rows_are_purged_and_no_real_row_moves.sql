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
--   1. the SCOPE: every relation the purge names and every foreign-key descendant of one (176 on production 16 Nov, 179 on 17 Nov);
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
-- RE-COUNTED 17 NOV 2026 ~09:08Z (it_engineer; SELECT on tables, views and the catalogue only, no routine called; the
--   markers re-written in plain SQL from production's bodies, fn_demo_purge_run still md5 592a1123660cd8d8e8e42a4198bbf249).
--   A paid certification was RUNNING (started 09:04:50Z, run 1 tag 54943ac4, rehearsal window 3608 open until 11:05Z).
--   Its rows are excluded from the census and this file must never pin or touch them:
--     demo entities, the certification's excluded: customers 2 (34760038, fc952c2c), leads 1 (126512; lead 160048 "ZZ DEMO
--     Saker ..." tagged qd_run:54943ac4, 09:05:29Z, is the running run's and NOT in the pin), inquiries 3 (a179ea8d, 8b287960,
--     d958e1ea, qd_run founderdemo), quotes 3 (7ca86d2e, f99c6e2f, 3f0e7209), transactions 1 (29ac49f5), logins 12 (10 on
--     example.invalid, the +qdprobe1 / +qdcust1 aliases; none created on 17 Nov). The PIN IS THEREFORE UNCHANGED from 16 Nov:
--     every run since 16 Nov tore its entities down; what moved is the log and storage they left.
--   Rows the routine also deletes by marker, 17 Nov: ai_cost_log with a run tag 31,565 (5 of them the running run's, after
--     09:00Z); rehearsal_window qd_run 2,101 (1 open: the running run's); doc_backups demo 1,076 (all with a Dropbox copy);
--     notifications to a demo address 161; email_verifications on a demo address 105; assistant_logs probe agents 70.
--   Storage carrying the marker anywhere in the name (this file's rule 1 below): signed-terms 33 (3 after 09:00Z: the running
--     run's), drawing-files 3, quote-files 2, supplier-docs 2, receipt-files 1, evidence 6 (kept). Dropbox: 169 files under the
--     82 reviewed paths (listing synced 16 Nov 22:30Z); the 6 "ZZ DEMO" files in the listing are all inside a reviewed path.
-- RE-COUNTED AGAIN 17 NOV 2026 ~10:13Z, after the certification (54943ac4) ended at 10:09:31Z with EXIT 0 and its own
--   teardown (coordinator, 17 Nov: its leftover cost rows and closed window are demo and go like every other run's). SELECT
--   only: demo entities 2 customers, 1 lead (126512), 3 inquiries, 3 quotes, 1 transaction, 12 logins, the same again, so the
--   pin is unchanged; no qd_run window open, none started after 10:09:32Z; the run's leads, logins and sink addresses are
--   gone. ai_cost_log with a run tag 31,657 (49 of them 54943ac4's, 0 after the cutoff); rehearsal_window qd_run 2,102;
--   doc_backups demo 1,076; notifications to a demo address 90; signed-terms by marker or sink name 36. Kept: (2,2,3).
--   THE FOUR DEMO TABLES THE ROUTINE NEVER REACHED (no foreign key to anything it walks), brought in below by exact markers:
--     demo_shadow_trace 13,586 (every row of the table is a demo shadow by construction: its writer fn_demo_shadow_record is
--       called only for Stripe TEST-mode payments or fn_seat_work_is_demo work, never for a live payment; 0 rows name an
--       existing real customer, inquiry, quote, transaction or supplier, 0 carry livemode true);
--     rehearsal_spend_reservation 907 (every row's e2e_run_tag is a qd_run rehearsal window's tag);
--     support_reply_readability 68 with demo = true (the writer's own flag; the 2,159 others stay);
--     accountant_reveal_reconcile_item 53 with demo = true, livemode false, outcome rehearsal_torn_down, all on example.invalid
--       (the 7 test_mode_not_demo rows of the 10 Nov ruling have no demo address and stay). NOTE: the hourly reveal sweep
--       re-reads Stripe TEST events for 30 days and re-files these 53 as resolved rehearsal_torn_down until about 12 Dec.
-- RE-COUNTED 17 NOV 2026 ~20:43Z (it_engineer; SELECT only), after the apply of 20:41Z REFUSED, safely, on today's five paid
--   drawing/memory proofs (qd_run 712aae1d, b7bdf916, 14173f94, 623d9200, 6244a525; 12:57Z-19:24:04Z, each torn down by its
--   harness; 408 run-tagged cost rows after 10:09:32Z). The cutoff moves to 19:30:00Z, after the last teardown, and their
--   rows go like every other run's. Census against the pin: entities UNCHANGED (2 customers, 1 lead, 3 inquiries, 3 quotes,
--   1 transaction, 12 logins; none made after the cutoff); kept (2,2,3); no qd_run window open or started after 19:30Z;
--   0 run-tagged cost rows, demo notifications, email codes or windows after it. Moved since 10:13Z: run-tagged cost rows
--   31,657 -> 32,065; qd_run windows 2,102 -> 2,107; demo_shadow_trace before the cutoff 13,586 -> 16,366 (of 16,746);
--   rehearsal_spend_reservation 907 -> 913; support_reply_readability 68 and reconcile items 53 unchanged; storage by this
--   file's rules 44 (unchanged), evidence 6 kept. The OpenRouter reconcile check: the Asia/Dubai day 17 Nov, which holds every
--   tagged row of today's proofs (16:57-23:24 Dubai), was reconciled at 20:30:29Z; no tagged day is unreconciled.
--   cad_read_jobs: the 17:20Z proof left two queued jobs (943e0b0e, 62c5537d) whose customer f09eab3b and source drawings are
--   gone; their owner is an example.invalid address, so fn_demo_purge_run already deletes them (owner_email marker), and the
--   check below now refuses unless every cad_read_jobs row with a demo owner, or a ZZ DEMO file name, made before the cutoff
--   is gone (4 such rows on production; 0 with the name and a real owner, so none is a real job).
-- THE CUTOFF (17 Nov): _l5_cut holds it (now 2026-11-17 19:30:00Z, after the last proof's teardown at 19:24:04Z) and any running
--   tag (none now). The routine is unchanged and deletes every run-tagged cost row and window, so this file REFUSES, before
--   anything is purged, while a qd_run window is open or any row it would delete carries a running tag or was created at or
--   after the cutoff; and after the purge it refuses if any table in scope lost a row created at or after the cutoff (each
--   table dated by its created_at or by its column that defaults to the insertion time). Storage created at or after the
--   cutoff, or named by a running tag, is taken off the queue like the evidence bucket, never deleted. A later certification
--   therefore makes it refuse again until a review moves the cutoff, re-reads the census with SELECTs and updates the pin.
-- IDEMPOTENT: the pin accepts the reviewed census or an all-zero one (a second apply after a successful purge: 0 entities,
--   only marker rows written since are deleted, every check still applies).
-- LOCKS: lock_timeout 5s, so a purge that would queue behind a live writer gives up instead of holding the queue.
-- ROLLBACK: the whole file is one transaction and every refusal rolls back everything, the queues included. A purge that
--   committed cannot be undone in SQL: the rows are gone. The daily export (table_export_registry) holds only the exported
--   tables (customers, leads, inquiries, quotes, transactions, notifications, agent_actions, accountant_reveal_reconcile_item);
--   demo_shadow_trace, ai_cost_log, rehearsal_window, rehearsal_spend_reservation, support_reply_readability, doc_backups,
--   rl_hits, company_event, email_verifications and auth.users are NOT exported and are gone for good (review 17 Nov); the storage and
--   Dropbox queues can be stopped before dropbox_backup drains them (15 minutes after listing) by setting done_at on this
--   purge's signup_purge_object / signup_purge_dropbox rows.
-- WHEN: apply it outside campaign hours, in a quiet minute, AFTER the certification (scripts/apply_sql.mjs, no --ddl).
-- AFTER: scripts/sql/the_last_demo_rows_are_purged_and_no_real_row_moves_probe.sql (PROBE OK) at once, and
--   `node scripts/it/purge_demo_data.mjs --verify-zero` (exit 0) once dropbox_backup has drained both queues (~3 hours).
set transaction isolation level repeatable read;
set local lock_timeout = '5s';

-- the cutoff, the running certification's tag(s) and the reviewed census, in one place (17 Nov 2026 ~20:43Z: the day's last
-- paid proof, 6244a525, tore itself down at 19:24:04Z; nothing is running, so no tag is protected by name; census unchanged)
create temp table _l5_cut on commit drop as
select '2026-11-17 19:30:00+00'::timestamptz as t, '{}'::text[] as running_tags,
       '{"customers": 2, "leads": 1, "inquiries": 3, "quotes": 3, "transactions": 1, "auth_users": 12}'::jsonb as pin,
       '{"customers": 0, "leads": 0, "inquiries": 0, "quotes": 0, "transactions": 0, "auth_users": 0}'::jsonb as pin_done;

-- a certification that is running, or one whose rows the routine would delete, stops everything here
do $running$
declare v_bad text;
begin
  select concat_ws('; ',
    (select 'open certification window ' || string_agg(run_tag, ', ') from public.rehearsal_window
      where run_tag like 'qd\_run:%' and ended_at is null and expires_at > now()),
    (select 'certification window started at or after the cutoff: ' || string_agg(w.run_tag, ', ') from public.rehearsal_window w, _l5_cut k
      where w.run_tag like 'qd\_run:%' and (w.started_at >= k.t or w.run_tag = any(array(select 'qd_run:' || x from unnest(k.running_tags) x)))),
    (select 'run-tagged cost rows at or after the cutoff: ' || count(*) from public.ai_cost_log l, _l5_cut k
      where l.e2e_run_tag is not null and (l.occurred_at >= k.t or l.e2e_run_tag = any(k.running_tags)) having count(*) > 0),
    (select 'leads tagged by a running run: ' || string_agg(l.id::text, ', ') from public.leads l, _l5_cut k
      where l.tags && array(select 'qd_run:' || x from unnest(k.running_tags) x)),
    -- review 17 Nov: the OpenRouter reconcile (20:30Z, the Asia/Dubai day before) compares the meter with ai_cost_log and never
    -- recomputes a day; purged run-tagged rows of a day not yet reconciled read as unattributed spend (17 Nov: USD 0.69 of ~2.08,
    -- 33% against the 5% threshold) and raise a false it_engineer finding
    (select 'OpenRouter day(s) not yet reconciled hold run-tagged cost rows: ' || string_agg(distinct d::text, ', ')
       from (select (l.occurred_at at time zone 'Asia/Dubai')::date d from public.ai_cost_log l where l.e2e_run_tag is not null) s
      where s.d > coalesce((select max(o.day) from public.openrouter_day o where o.reconciled_at is not null), '-infinity'::date))) into v_bad;
  if nullif(v_bad, '') is not null then
    raise exception 'DEMO PURGE REFUSED before it started: the certification of 17 Nov is running or its rows are still here (%): nothing of it may be touched; after it, move the cutoff in review', v_bad;
  end if;
end $running$;

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
       case when n.nspname = 'public' then c.relname else n.nspname || '.' || c.relname end as k,
       -- when the row was made (17 Nov): created_at, else the column that defaults to the insertion time; 168 of 179 on
       -- 17 Nov, the other 11 (auth MFA/session tables, po_lines, workflow_step_run, ...) are named in the verdict as undated
       (select a.attname::text from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
         where a.attrelid = w.rel and a.attnum > 0 and not a.attisdropped and a.atttypid in ('timestamptz'::regtype, 'timestamp'::regtype)
           and (a.attname = 'created_at'
                or pg_get_expr(d.adbin, d.adrelid) ~* '^(now\(\)|CURRENT_TIMESTAMP|statement_timestamp\(\)|clock_timestamp\(\)|transaction_timestamp\(\))')
         order by (a.attname <> 'created_at'), a.attnum limit 1) as ts
  from walk w join pg_class c on c.oid = w.rel join pg_namespace n on n.oid = c.relnamespace
 where c.relkind in ('r', 'p') and c.relname not in ('signup_purge', 'signup_purge_object', 'signup_purge_dropbox');

-- n: every row; r: the rows made at or after the cutoff (the running certification's and anything else new), which must all survive
create temp table _l5_before on commit drop as
select s.rel, s.k, (xpath('/row/n/text()', x.x))[1]::text::bigint as n, (xpath('/row/r/text()', x.x))[1]::text::bigint as r
  from _l5_scope s
 cross join lateral (select query_to_xml(format('select count(*) as n, %s as r from %s',
          case when s.ts is null then 'null::bigint' else format('count(*) filter (where x.%I >= %L::timestamptz)', s.ts, (select t from _l5_cut)) end,
          s.rel::regclass::text || ' x'), false, true, '') as x) x;

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

-- THE DEMO SETS, by the purge's own rules (fn_demo_purge_run), read here BEFORE it runs. Pinned to the reviewed census in
-- _l5_cut (re-read 17 Nov 2026 ~09:08Z with the running certification excluded; on 16 Nov a running paid certification added
-- demo leads 159933 and 159934 at 15:00Z, on 17 Nov lead 160048 at 09:05Z). Anything else: nothing is purged.
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
  v_new text;
begin
  if v is distinct from (select pin from _l5_cut) and v is distinct from (select pin_done from _l5_cut) then
    raise exception 'DEMO PURGE REFUSED before it started: the demo census is % and the reviewed one (17 Nov ~09:08Z, the running certification excluded) is %: run it after the certification, with a fresh census and review', v, (select pin from _l5_cut);
  end if;
  -- the pin counts; this names: no demo entity made at or after the cutoff (17 Nov: none, the running run's lead 160048 aside)
  select concat_ws('; ',
    (select 'customers ' || string_agg(left(c.id::text, 8), ', ') from public.customers c, _l5_cut k
      where c.id::text in (select id from _l5_demo where rel = 'public.customers'::regclass) and c.created_at >= k.t),
    (select 'leads ' || string_agg(l.id::text, ', ') from public.leads l, _l5_cut k
      where l.id::text in (select id from _l5_demo where rel = 'public.leads'::regclass) and l.created_at >= k.t),
    (select 'inquiries ' || string_agg(left(i.id::text, 8), ', ') from public.inquiries i, _l5_cut k
      where i.id::text in (select id from _l5_demo where rel = 'public.inquiries'::regclass) and (i.created_at >= k.t or i.provenance->>'qd_run' = any(k.running_tags))),
    (select 'quotes ' || string_agg(left(q.id::text, 8), ', ') from public.quotes q, _l5_cut k
      where q.id::text in (select id from _l5_demo where rel = 'public.quotes'::regclass) and q.created_at >= k.t),
    (select 'logins ' || string_agg(left(u.id::text, 8), ', ') from auth.users u, _l5_cut k
      where u.id::text in (select id from _l5_demo where rel = 'auth.users'::regclass) and u.created_at >= k.t)) into v_new;
  if nullif(v_new, '') is not null then
    raise exception 'DEMO PURGE REFUSED before it started: demo rows made at or after the cutoff % (the running certification''s): %', (select t from _l5_cut), v_new;
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

-- THE FOUR TABLES THE ROUTINE NEVER REACHES (17 Nov, header): their totals and the rehearsal tags, read BEFORE the purge
-- deletes the windows that name the tags
create temp table _l5_run_tags on commit drop as
select distinct substring(w.run_tag from 8) as tag from public.rehearsal_window w, _l5_cut k
 where w.run_tag like 'qd\_run:%' and w.started_at < k.t and not (substring(w.run_tag from 8) = any(k.running_tags));
create temp table _l5_four_before on commit drop as
select 'public.demo_shadow_trace' as k, (select count(*) from public.demo_shadow_trace) as n
union all select 'public.rehearsal_spend_reservation', (select count(*) from public.rehearsal_spend_reservation)
union all select 'public.support_reply_readability', (select count(*) from public.support_reply_readability)
union all select 'public.accountant_reveal_reconcile_item', (select count(*) from public.accountant_reveal_reconcile_item);

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
--      or a file name carrying a demo id with '_' for '-' (backups/generated), in agent-docs, quote-files, backups, receipt-files;
--   3. (17 Nov) a signed-terms file named by a certification's sink login 'deliveredqd-<8 hex>-sup<n>resend.dev' and no company
--      name: no marker, no demo row names it (4 made before the cutoff on 17 Nov ~09:12Z, by runs whose teardown has run).
-- Never an object made at or after the cutoff (17 Nov: 4 in signed-terms, the running run's): see _l5_running_kept below.
create temp table _l5_extra_objects on commit drop as
with ins as (
  insert into public.signup_purge_object (purge_id, bucket, path)
  select (select (out->>'purge_id')::bigint from _l5_out), o.bucket_id, o.name from storage.objects o
   where o.bucket_id not in ('brand', 'site', 'demo-assets', 'social-media', 'kb-import-assets', 'evidence')
     and o.created_at < (select t from _l5_cut)
     and (o.name ~* '(^|[^a-z0-9])(zz[ _-]?demo([^a-z]|$)|__selftest__|_selftest/)'
          or (o.bucket_id = 'signed-terms' and o.name ~ '^suppliers/[0-9]+_deliveredqd-[0-9a-f]{8}-sup[0-9]+resend\.dev_TnC-Acceptance\.pdf$')
          or (o.bucket_id in ('agent-docs', 'quote-files', 'backups', 'receipt-files')
              and exists (select 1 from _l5_demo d where d.rel in ('public.leads'::regclass, 'public.customers'::regclass, 'public.inquiries'::regclass)
                           and (('/' || o.name || '/') like '%/' || d.id || '/%'
                                or (d.rel <> 'public.leads'::regclass and (o.name ilike '%QD-' || left(d.id, 8) || '-%' or o.name ilike '%\_' || replace(d.id, '-', '\_') || '.%'))
                                or (d.rel = 'public.leads'::regclass and o.name ~ ('_' || d.id || '\.[a-z]+$'))))))
  on conflict (bucket, path) do nothing
  returning bucket, path)
select bucket, path from ins;

-- the running certification's storage stays (17 Nov): whatever either queue holds for this purge that was made at or after the
-- cutoff, or is named by a running tag, comes off the queue like the evidence above; never deleted
create temp table _l5_running_kept on commit drop as
with d as (
  delete from public.signup_purge_object q
   where q.purge_id = (select (out->>'purge_id')::bigint from _l5_out) and q.done_at is null
     and exists (select 1 from storage.objects o, _l5_cut k where o.bucket_id = q.bucket and o.name = q.path
                  and (o.created_at >= k.t
                       -- with no running tag the pattern would be 'qd[-_](run:)?()', which matches every sink name: guarded
                       or (cardinality(k.running_tags) > 0 and o.name ~* ('qd[-_](run:)?(' || array_to_string(k.running_tags, '|') || ')'))))
  returning q.bucket, q.path)
select bucket, path from d;

-- THE FOUR TABLES, by exact markers only, never a row made at or after the cutoff (header). Run AFTER the purge, so every
-- customer, inquiry, quote, transaction and lead that still exists is a real one: a shadow that names any of them stays.
create temp table _l5_four (k text, n bigint) on commit drop;
with d as (
  delete from public.demo_shadow_trace x
   where x.recorded_at < (select t from _l5_cut)
     and coalesce(x.payload->>'livemode', '') <> 'true'
     and (x.customer_id is null or not exists (select 1 from public.customers c where c.id = x.customer_id))
     and (x.inquiry_id is null or not exists (select 1 from public.inquiries i where i.id = x.inquiry_id))
     and (x.quote_id is null or not exists (select 1 from public.quotes q where q.id = x.quote_id))
     and (x.transaction_id is null or not exists (select 1 from public.transactions t where t.id = x.transaction_id))
     and not (x.payload->>'supplier_id' ~ '^[0-9]{1,12}$'
              and exists (select 1 from public.leads l where l.id = (x.payload->>'supplier_id')::bigint))
     and not (x.payload->>'subject_table' = 'leads' and x.payload->>'subject_id' ~ '^[0-9]{1,12}$'
              and exists (select 1 from public.leads l where l.id = (x.payload->>'subject_id')::bigint))
  returning 1)
insert into _l5_four select 'public.demo_shadow_trace', count(*) from d;
with d as (
  delete from public.rehearsal_spend_reservation r
   where r.created_at < (select t from _l5_cut) and r.e2e_run_tag in (select tag from _l5_run_tags)
  returning 1)
insert into _l5_four select 'public.rehearsal_spend_reservation', count(*) from d;
with d as (
  delete from public.support_reply_readability s
   where s.demo and s.created_at < (select t from _l5_cut)
  returning 1)
insert into _l5_four select 'public.support_reply_readability', count(*) from d;
with d as (
  delete from public.accountant_reveal_reconcile_item a
   where a.demo and a.livemode is false and a.outcome = 'rehearsal_torn_down' and public.fn_is_demo_email(a.customer_email)
     and a.first_seen_at < (select t from _l5_cut)
     and (a.transaction_id is null or not exists (select 1 from public.transactions t where t.id = a.transaction_id))
  returning 1)
insert into _l5_four select 'public.accountant_reveal_reconcile_item', count(*) from d;

create temp table _l5_after on commit drop as
select s.rel, s.k, (xpath('/row/n/text()', x.x))[1]::text::bigint as n, (xpath('/row/r/text()', x.x))[1]::text::bigint as r
  from _l5_scope s
 cross join lateral (select query_to_xml(format('select count(*) as n, %s as r from %s',
          case when s.ts is null then 'null::bigint' else format('count(*) filter (where x.%I >= %L::timestamptz)', s.ts, (select t from _l5_cut)) end,
          s.rel::regclass::text || ' x'), false, true, '') as x) x;

do $check$
declare
  v_out jsonb := (select out from _l5_out);
  v_touched jsonb := coalesce((select out->'touched' from _l5_out), '{}'::jsonb);
  v_kept record; v_bad text; v_left jsonb; v_pid bigint;
begin
  v_pid := (v_out->>'purge_id')::bigint;
  -- exactly the reviewed census (or the all-zero one of a repeat), or nothing (16 Nov a running certification added demo leads
  -- 159933/159934 at 15:00Z; 17 Nov lead 160048 at 09:05Z)
  if v_out->'demo_ids' is distinct from (select pin from _l5_cut) and v_out->'demo_ids' is distinct from (select pin_done from _l5_cut) then
    raise exception 'DEMO PURGE REFUSED: the demo census is not the reviewed one (%): re-census and review before purging', v_out->'demo_ids';
  end if;
  -- the running certification (17 Nov): no table in scope lost a row made at or after the cutoff
  select string_agg(format('%s: %s -> %s rows made since %s', b.k, b.r, a.r, (select t from _l5_cut)), '; ' order by b.k) into v_bad
    from _l5_before b join _l5_after a on a.rel = b.rel
   where b.r is not null and (a.r is null or a.r < b.r);
  if v_bad is not null then raise exception 'DEMO PURGE REFUSED: rows made at or after the cutoff (the running certification''s) would be deleted: %', v_bad; end if;
  -- ...nor is a Dropbox copy of a backup record made since the cutoff queued for deletion
  select string_agg(s.doc_backup_id::text, ', ') into v_bad
    from public.signup_purge_dropbox s join public.doc_backups d on d.id = s.doc_backup_id
   where s.purge_id = v_pid and d.created_at >= (select t from _l5_cut);
  if v_bad is not null then raise exception 'DEMO PURGE REFUSED: backup records made at or after the cutoff are queued for Dropbox deletion: %', v_bad; end if;
  -- review 17 Nov: storage is not in the daily export, so a queued object is gone for good 15 minutes after commit. The reviewed
  -- queue was 68 objects (22 the routine lists + 46 by this file's rules; the 6 evidence objects taken off): no more, or nothing.
  if (select count(*) from public.signup_purge_object where purge_id = v_pid) > 68 then
    raise exception 'DEMO PURGE REFUSED: % storage objects queued, more than the 68 reviewed on 17 Nov: list them and review',
      (select count(*) from public.signup_purge_object where purge_id = v_pid);
  end if;
  -- the four tables the routine never reaches: each lost exactly the rows its own delete reported, nothing else moved there
  -- (a purge trigger writing one of them, or a row of it deleted by another route, refuses)
  select string_agg(format('%s: %s -> %s, its delete says %s', b.k, b.n, a.n, f.n), '; ' order by b.k) into v_bad
    from _l5_four_before b join _l5_four f on f.k = b.k
    cross join lateral (select (xpath('/row/n/text()', query_to_xml('select count(*) as n from ' || b.k, false, true, '')))[1]::text::bigint as n) a
   where b.n - f.n <> a.n;
  if v_bad is not null then raise exception 'DEMO PURGE REFUSED: a demo table outside the routine moved by other than its demo rows: %', v_bad; end if;
  if (select count(*) from _l5_four) <> 4 then raise exception 'DEMO PURGE REFUSED: the four demo tables were not all purged (%)', (select count(*) from _l5_four); end if;
  -- 17 Nov: the CAD read jobs a proof leaves behind (943e0b0e, 62c5537d of 17:20Z, customer and drawings already torn down) are
  -- demo by their owner address; none with a demo owner or a ZZ DEMO file name, made before the cutoff, may survive the purge
  select string_agg(left(j.id::text, 8), ', ') into v_bad from public.cad_read_jobs j
   where j.created_at < (select t from _l5_cut)
     and (public.fn_demo_purge_address(j.owner_email) or j.file_name ~* '(^|[^a-z0-9])zz[ _-]?demo([^a-z]|$)');
  if v_bad is not null then raise exception 'DEMO PURGE INCOMPLETE: demo CAD read jobs left: %', v_bad; end if;
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
       || '; made since ' || (select t from _l5_cut)::text || ' (the running certification''s), none deleted: '
       || (select coalesce(sum(r), 0) from _l5_after)::text || ' rows in ' || (select count(*) from _l5_scope where ts is not null)::text
       || ' dated tables (undated: ' || coalesce((select string_agg(k, ', ' order by k) from _l5_scope where ts is null), 'none') || '), '
       || (select count(*) from _l5_running_kept)::text || ' storage objects kept off the queue'
       || '; the four tables the routine never reaches: ' || (select string_agg(k || ' ' || n, ', ' order by k) from _l5_four)
       || '; foreign keys to a real party pinned: ' || (select count(*) from _l5_fk_before)::text
       || '; kept: customers 0dc8c94f, ba61fa16 and leads 19398, 158318, 143027; non-demo counts ' || public.fn_demo_purge_real_counts()::text
       as verdict;
